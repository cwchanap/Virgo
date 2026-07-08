# DTX Parser Model Normalization Design

**Date:** 2026-07-05
**Status:** Design approved; pending written-spec review
**Scope:** Normalize DTX parser and persisted model data for drum-tab rendering without rewriting layout/rendering behavior in this ticket.
**Linear:** [HPA-139](https://linear.app/cwchanap/issue/HPA-139/normalize-dtx-parsermodel-data-for-drum-tab-rendering)

## 1. Context

Virgo imports DTX chart chips through `DTXFileParser`, converts them to `Note`, and then sends persisted `Note` objects directly into gameplay, scoring, input timing, and `NotationLayoutEngine`.

The current parser-level `DTXNote` already contains useful raw identity:

- DTX measure index
- lane ID
- note ID
- chip position within the parsed lane array
- total positions in that lane array

The problem is that `DTXChartData.toNotes(for:)` drops that identity when it creates `Note`, and `DTXNote.toNoteInterval()` treats `totalPositions` as final visual duration. That conflates parser grid resolution, playback timing, visual duration, and notation semantics.

HPA-139 is the parser/model normalization step in a larger drum-tab rendering sequence:

- HPA-140 owns fixed tab grid and timeline-to-x mapping.
- HPA-141 owns notehead/stem placement and the canonical notation legend.
- HPA-142 owns beam, hook, flag, and tail behavior.
- HPA-143 owns rests, stop/choke events, and articulation rendering.
- HPA-144 owns broader regression/golden coverage.
- HPA-145 owns rhythm/meter scoping for tuplets, compound meter, and measure-length timing.

Therefore HPA-139 should expose correct canonical data to those later tickets, not build the full renderer primitive pipeline now.

## 2. Goals

- Introduce a canonical import pipeline:

  ```swift
  DTXChipEvent -> NormalizedRhythmicEvent -> Note
  ```

- Preserve raw DTX lane ID, note ID, and grid position through import.
- Persist enough normalized timing and notation candidates on `Note` for layout to consume in follow-up tickets.
- Stop treating source grid resolution as authoritative visual `NoteInterval`.
- Map DTX lane `1C` / `.lb` to `.bass` so left-bass chips import as playable kick events.
- Keep existing gameplay, scoring, input matching, and layout callers compatible.

## 3. Non-Goals

- No fixed-grid x mapping. HPA-140 owns that.
- No playhead or row-wrapping rewrite. HPA-140 owns that.
- No notehead/stem placement rewrite. HPA-141 owns that.
- No beam, hook, flag, or tail rewrite. HPA-142 owns that.
- No rest, stop/choke, or articulation rendering. HPA-143 owns that.
- No full MusicXML model.
- No migration or backfill for already-persisted notes beyond safe default values.

## 4. Design

### 4.1 Parser event: `DTXChipEvent`

Create a raw parser chip type, or evolve/rename `DTXNote` to fill that role. It represents what the DTX line said, not what Virgo should render.

Required fields:

- `measureIndex`: zero-based DTX measure number from `#xxxYY`.
- `laneID`: normalized uppercase DTX lane ID.
- `noteID`: normalized uppercase DTX note ID.
- `gridPosition`: zero-based chip index inside the lane array.
- `gridSize`: total number of two-character slots in the lane array.

The existing `measureOffset` fraction can remain as a convenience, but it should be documented as timing input derived from `gridPosition / gridSize`, not notation duration.

### 4.2 Normalized event: `NormalizedRhythmicEvent`

Add a small intermediate value type that maps a raw chip into Virgo's canonical import data.

Required fields:

- `measureIndex`
- `absoluteTick`
- `tickWithinMeasure`
- `ticksPerMeasure`
- `voiceCandidate`
- `laneID`
- `noteID`
- `gridPosition`
- `gridSize`
- `noteType`
- `visualDurationCandidate`
- `articulationCandidate`

This type stays in the import/parser domain. It is not a rendered primitive and it should not know about x coordinates, beams, row wrapping, or SwiftUI views.

`ticksPerMeasure` should be a chart-level normalization resolution for this first pass, not each lane line's raw grid size. A practical rule is to choose the least common multiple of parsed grid sizes that contribute timing in the chart, then convert each chip position into that shared tick space. This keeps simultaneous chips from different lane grids comparable. HPA-145 can refine this when variable measure lengths and compound meter are handled explicitly.

### 4.3 Persisted model fields on `Note`

Extend `Note` rather than replacing it. Keep the existing initializer source-compatible by giving new fields defaults.

Add SwiftData-compatible optional fields such as:

- `sourceFormat` or `originKind`, defaulting to manual/local.
- `sourceLaneID`
- `sourceNoteID`
- `sourceGridPosition`
- `sourceGridSize`
- `normalizedMeasureIndex`
- `normalizedAbsoluteTick`
- `normalizedTickWithinMeasure`
- `normalizedTicksPerMeasure`
- `notationVoiceCandidate`
- `visualDurationCandidate`
- `articulationCandidate`

Existing manually-created notes and tests may leave these fields nil or defaulted. Imported DTX notes should populate them.

### 4.4 Conversion flow

`DTXChartData.toNotes(for:)` should become a two-step conversion:

1. Convert each playable chip event to a `NormalizedRhythmicEvent`.
2. Convert each normalized event to a persisted `Note`.

The conversion should preserve current public behavior where needed:

- `Note.measureNumber` remains one-based for current layout/gameplay code.
- `Note.measureOffset` remains a fraction for current gameplay timing.
- `Note.noteType` remains the playable/scoring instrument.
- `Note.interval` remains available for current layout, but its value comes from `visualDurationCandidate`, not directly from `gridSize`.

### 4.5 Lane mapping

Update `DTXLane.lb` (`1C`) to map to `.bass`. This is the only required lane-behavior change in HPA-139.

Open hi-hat vs closed hi-hat and china/splash vs crash should be preserved through raw lane identity and note type where possible, but HPA-141 and HPA-143 own the canonical notation legend and rendered symbol differences.

## 5. Normalization Rules

For HPA-139, normalization uses simple fixed-length 4/4 assumptions already present in the app. HPA-145 will refine tuplets, compound meter, and variable measure length.

Rules:

- Preserve raw chip identity exactly after case normalization.
- Derive `ticksPerMeasure` from a deterministic chart-level resolution that can represent the source grids without losing timing.
- Derive `tickWithinMeasure` by converting `gridPosition` from its raw `gridSize` into the shared `ticksPerMeasure` space.
- Derive `absoluteTick` as `measureIndex * ticksPerMeasure + tickWithinMeasure` for the first pass.
- Keep `measureOffset` available as `Double(gridPosition) / Double(gridSize)`.
- Derive `voiceCandidate` from the playable instrument: lower for kick and hi-hat pedal, upper for the rest.
- Derive `articulationCandidate` as `.none` or nil unless the parser has explicit stop/choke semantics.
- Derive `visualDurationCandidate` conservatively from musical spacing when possible, not from raw `gridSize` alone. Dense source grids should preserve timing resolution without forcing every sparse chip in that grid to render as a 32nd or 64th note solely because the lane array is high-resolution. The implementation sorts all playable chips by absolute tick across the entire chart (not just within a single measure) so that the final chip in one measure can inherit its visual duration from the first chip in the next measure; this is musically more correct than a per-measure-only scan.

The key invariant is that timing precision and visual duration are separate fields.

## 6. Compatibility

This design intentionally limits blast radius:

- Existing `Note` initializers continue to work with default metadata.
- Existing non-DTX tests can keep creating notes with only interval, note type, measure number, and measure offset.
- Existing gameplay and input matching continue using `measureNumber` and `measureOffset`.
- Existing layout can keep using `Note.interval` until HPA-140 through HPA-143 consume the richer fields.
- Previously imported songs are not backfilled. Reimported songs receive normalized metadata.

If SwiftData requires migration-safe default values for new properties, they should be optional or have scalar defaults that preserve existing data.

## 7. Error Handling

- Malformed note lines continue to be ignored as they are today.
- Unknown/non-playable lanes remain excluded from playable `Note` conversion, except BGM lane data continues to feed BGM offset detection.
- Unknown playable-looking lane IDs should preserve parser-level events only if the parser gains a non-playable event collection later. HPA-139 does not need to persist unknown playable notes as `Note`.
- Invalid grid sizes remain rejected by `parseNoteLine`.

## 8. Tests

Focused tests for HPA-139:

- Lane `1C` imports as `.bass` and survives conversion to `Note`.
- Imported `Note` preserves source lane ID, note ID, grid position, grid size, and normalized tick fields.
- A non-power-of-two grid, such as 12 slots, preserves timing/ticks and does not silently collapse the model to "quarter because unknown grid".
- A sparse high-resolution lane, such as one chip in a 32- or 64-slot line, preserves high-resolution timing while assigning a readable visual duration candidate.
- Existing BGM lane offset behavior remains intact, including the distinction between `0.0` and `nil`.

Existing tests that assert `DTXNote.toNoteInterval()` maps unknown grids to `.quarter` should be rewritten or removed because that fallback is the behavior HPA-139 is replacing.

## 9. Verification

Recommended focused verification command:

```bash
xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' \
  -only-testing:VirgoTests/DTXFileParserTests \
  -parallel-testing-enabled NO test
```

Before merging implementation, also run the repo's macOS unit-test command from `CLAUDE.md` with parallel testing disabled.
