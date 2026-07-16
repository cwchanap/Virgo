# Wire DTX Import to Populate ChartControlEvent — Design

**Linear issue:** [HPA-214](https://linear.app/cwchanap/issue/HPA-214/wire-dtx-import-to-populate-chartcontrolevent)
**Parent:** HPA-143 (PR #45) — added the `ChartControlEvent` model, `safeControlEvents` accessor, rest/stop-note rendering, and authored fixture copy, but left the DTX importer intentionally unwired.
**Date:** 2026-07-16

## Problem

HPA-143 added `ChartControlEvent` (stop/choke/damp marks) and wired it fully into the notation rendering engine, but the DTX importer was left disconnected per plan constraints ("without changing parser semantics"). As a result, `DTXFileParser.swift` has zero references to `ChartControlEvent`/`controlEvents`, and `LocalDTXFixtureImporter.importSong` never sets `chart.controlEvents`. Stop/choke/damp marks are inert in production — they only appear via authored fixtures and tests.

## Goal

Populate `ChartControlEvent` from DTX lane/note identity during import so stop/choke/damp marks render for real DTX charts, not just fixtures.

### Acceptance Criteria

1. `DTXFileParser` constructs `ChartControlEvent` rows from DTX stop/choke/damp lanes.
2. Imported charts render stop marks without a fixture-copy step.
3. `DTXFileParserTests` cover at least one stop/choke fixture end-to-end.
4. No regression to playable-note grid, scoring, input, or playback.

## Approach: Parallel Parsing Path

Add a control-event parsing path that mirrors the existing `toNotes(for:)` → `normalizedRhythmicEvents()` pipeline exactly, keeping the note path byte-for-byte unchanged. The acceptance criterion "no regression to playable-note grid" is structurally guaranteed because control chips never enter the note normalization pipeline.

## Design

### 1. Control Lane IDs

Standard DTX/DTXCreator has no native drum-stop lane. Virgo defines three dedicated control lanes in the unused `2x` hex block (playable drum lanes occupy `11`–`1C`):

| Kind | Lane ID | Enum case |
|------|---------|-----------|
| `stop` | `21` | `DTXLane.stop` |
| `choke` | `22` | `DTXLane.choke` |
| `damp` | `23` | `DTXLane.damp` |

These lanes return `nil` from `noteType` (non-playable, same as `bgm`/`bpm`), so `normalizedRhythmicEvents()` — which filters on `toNoteType() != nil` — automatically excludes them. No change to note filtering logic.

### 2. Target Encoding: Chip Value = Target Lane

The 2-char chip value on a control lane encodes the target drum lane ID. Control lanes carry no WAV audio, so the chip value is free to encode the target rather than referencing a sample.

Example:
```
#00122: 16000000
```
- Measure `001`, lane `22` (choke), grid position `0` of `4`
- Chip value `16` → `targetLaneID = "16"` (crash cymbal)
- Produces one `ChartControlEvent(kind: .choke, targetLaneID: "16", ...)`

The parser uppercases the chip value to match `DrumNotationCatalog.resolveTarget`'s normalization. Unresolvable target lanes (e.g. `"ZZ"`) are stored as-is; the layout engine already drops their geometry with a diagnostic — no new validation needed.

### 3. Parsing Flow

All additions are in `Virgo/utilities/DTXFileParser.swift`.

**3a. New `DTXLane` cases** (after `case lb = "1C"`):

```swift
case stop = "21"
case choke = "22"
case damp = "23"
```

**3b. `DTXLane.controlEventKind`** computed property:

```swift
var controlEventKind: NotationControlEventKind? {
    switch self {
    case .stop: return .stop
    case .choke: return .choke
    case .damp: return .damp
    default: return nil
    }
}
```

**3c. `DTXNote.toControlEventKind()`** — mirrors the existing `toNoteType()` extension:

```swift
func toControlEventKind() -> NotationControlEventKind? {
    DTXLane(rawValue: laneID.uppercased()).flatMap { $0.controlEventKind }
}
```

**3d. `DTXChartData.toControlEvents(for:)`** — mirrors `toNotes(for:)`:

1. Compute `sharedTicksPerMeasure` from **playable chips only** — same private static method (`Self.sharedTicksPerMeasure(for:)`), same value the notes use.
2. Filter chips where `toControlEventKind() != nil`.
3. For each control chip, validate `ticksPerMeasure.isMultiple(of: chip.gridSize)`. If it fails, skip with `Logger.warning` (same pattern as `NormalizedRhythmicEvent.init?` returning nil).
4. Build `ChartControlEvent` with:
   - `kind`: from `chip.toControlEventKind()`
   - `targetLaneID`: `chip.noteID.uppercased()`
   - `originKind`: `.dtx`
   - `measureNumber`: `chip.measureIndex + 1`
   - `measureOffset`: `Double(chip.gridPosition) / Double(chip.gridSize)`
   - `sourceLaneID`: `chip.laneID.uppercased()`
   - `sourceNoteID`: `chip.noteID.uppercased()`
   - `sourceGridPosition` / `sourceGridSize`: from chip
   - `normalizedMeasureIndex`: `chip.measureIndex`
   - `normalizedAbsoluteTick`: `chip.measureIndex * ticksPerMeasure + tickWithinMeasure`
   - `normalizedTickWithinMeasure`: `chip.gridPosition * (ticksPerMeasure / chip.gridSize)`
   - `normalizedTicksPerMeasure`: the shared value

Because control chips use the same `sharedTicksPerMeasure` as the notes, the layout engine's `exactRescaledTick` always succeeds for aligned controls — `sourceTicksPerMeasure` divides evenly into the tab grid by construction.

The `sharedTicksPerMeasure(for:)` static method is currently `private`. It will be made `internal` so `toControlEvents(for:)` can call it without recomputing. If it returns `nil` (LCM exceeds `maximumTicksPerMeasure`), `toControlEvents(for:)` returns `[]` — the same guard `normalizedRhythmicEvents()` uses to drop all notes in that case.

### 4. Importer Wiring

One change in `LocalDTXFixtureImporter.importSong` (the `importedCharts.forEach` block at lines 78–91):

```swift
chart.notes = importedChart.data.toNotes(for: chart)
chart.controlEvents = importedChart.data.toControlEvents(for: chart)
context.insert(chart)
for note in chart.notes { context.insert(note) }
for control in chart.controlEvents { context.insert(control) }
```

No other importer changes:
- `Song.fixtureCopy` already copies `controlEvents` via `copiedControlEvents` (HPA-143).
- `refreshDurationIfStale` / `refreshAudioPaths` / `refreshBGMStartOffsetIfMissing` touch only song-level fields, not chart notes or controls.
- Bundled Soukyuu fixtures contain no control-lane chips → `toControlEvents(for:)` returns `[]` → no rendering change for the demo song.

### 5. Edge Cases & Diagnostics

| Case | Behavior |
|------|----------|
| Control chip grid doesn't divide `sharedTicksPerMeasure` | Chip dropped, `Logger.warning` with lane/measure/grid info |
| `targetLaneID` doesn't resolve in `DrumNotationCatalog` | Stored as-is; layout engine drops geometry + logs (existing behavior) |
| Chart has controls but no playable chips | `sharedTicksPerMeasure` = 1; most control grids won't divide 1 → dropped. Acceptable: a control-only chart with no notes is malformed |
| Duplicate control at same time/target | Both stored; layout engine assigns deterministic `-duplicate-N` suffixes (existing behavior) |
| Existing Soukyuu fixtures (no control lanes) | `toControlEvents` returns `[]`, zero rendering change |

No new validation layer. The layout engine's two-phase timing validation (`NotationLayoutEngine+Controls.swift`) already handles all rendering-side decisions. The importer populates data faithfully; the engine renders or drops with diagnostics.

### 6. Testing Strategy

All tests use **Swift Testing** (`import Testing`), in-memory `TestContainer`, `-parallel-testing-enabled NO`.

**Unit tests in `DTXFileParserTests.swift`:**

- `toControlEventKind()` maps lanes 21/22/23 → stop/choke/damp; returns nil for playable lanes (11, 12, etc.)
- `toControlEvents(for:)` parses an inline DTX string with one stop chip targeting crash (lane 16) — asserts kind, targetLaneID, measureNumber, all normalized timing fields, `originKind == .dtx`
- Choke + damp chips produce correct kinds
- Control chip excluded from `toNotes` output (no `Note` created for lane 22)
- Playable chip excluded from `toControlEvents` output (no `ChartControlEvent` for lane 12)
- Misaligned control grid dropped with no crash (logged warning, empty result)

**Importer test in `LocalDTXFixtureImporterTests.swift`:**

- Import a chart whose DTX data contains a control-lane chip; assert `chart.controlEvents.count == 1` and the event is populated without a fixture-copy step

**Regression guard:**

- Run existing `DTXFileParserTests`, `DTXNormalizationTests`, `DTXNoteLineParsingTests` unchanged — confirms the note path is byte-for-byte unaffected

## Constraints (inherited from HPA-143)

- Do not infer stop/choke/damp events from sample IDs, unknown lanes, or neighboring cymbals — only dedicated control lanes (21/22/23) produce control events.
- Do not change parser semantics for playable notes — control chips are parsed by the existing `parseNoteLine` into `DTXNote` values; the new code only filters them by lane.
- Controls never enter `buildTabGrid` or `buildRests` — the layout engine already guarantees this.
- Use Swift Testing, not XCTest.
- Run `xcodebuild test` with `-parallel-testing-enabled NO`.
- iPad-only for iOS builds (`TARGETED_DEVICE_FAMILY = 2`); never target iPhone.

## Out of Scope

- Audio choking (muting a sample at a control-event timestamp) — notation marks only.
- New scoring or input targets for control events.
- Compound-meter control timing beyond what the existing layout engine supports.
- Modifying the bundled Soukyuu fixtures to include control chips.
- GUI/editor support for placing control chips in DTXCreator — this is a parser/importer change only.
