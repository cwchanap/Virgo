# HPA-164 Measured Formatting and Shared Tick Geometry Design

**Issue:** HPA-164 — `[Notation] Add measured formatting and shared tick geometry to DrumNotation`

**Scope:** Second PR in the HPA-163 → HPA-164 → HPA-166 migration. Move horizontal notation formatting and musical-position lookup into the existing `DrumNotation` package, cut Virgo over to that geometry, and delete the superseded fixed-grid notation renderer. Final beam/modifier parity and the complete package-owned static sheet remain HPA-166.

**Baseline reviewed:** `main` at `8a29b68f7afeb29c162e2587fad26c192d71beda` after HPA-163 / PR #65 merged.

## Current state after HPA-163

HPA-163 established the package and primitive geometry but intentionally left horizontal layout in Virgo:

- `DrumNotation` owns Bravura resources, percussion glyph semantics, staff-space-scaled glyph metrics, and primitive SwiftUI views.
- `VirgoNotationAdapter` is the single app-to-package seam, but today it maps primitive types and flag paint policy only.
- Virgo still owns `TabGrid`, one chart-wide `tickWidth`, measure sizing, row packing, note/rest/control X placement, and playhead X lookup.
- `NotationLayoutEngine` still contains both `.timeline(RhythmLayoutSnapshot)` and `.legacy(notes:controls:timeSignature:)` notation paths.
- Existing stems/beams/flags are built after notehead placement, so HPA-164 can keep their topology app-owned while feeding them package-positioned heads.
- HPA-581 already removed the old production `cachedBeatPositions` cache. HPA-164 must not recreate it.

The task is therefore horizontal layout ownership, not a renderer rewrite.

## Decision

Add one deterministic measured formatter to the existing `DrumNotation` target and make its result the only notation X-coordinate authority.

```text
Virgo DTX / SwiftData / rhythm analysis
                |
                v
       RhythmLayoutSnapshot
                |
                v
       VirgoNotationAdapter
  - expands trailing measures
  - applies staff overrides
  - maps only formatter-needed values
                |
                v
 DrumNotation.ResolvedNotationInput
                |
                v
      NotationFormatter.format
                |
                v
      DrumNotation.FormattedNotation
       |                         |
       |                         +--> position(measure, tick)
       |                                  |
       |                                  +--> live playhead / row lookup
       v
Virgo transitional composition
(existing Y placement, stems, beams, flags, marks)
                |
                v
         one NotationLayout
```

There is no second formatter, no fallback `TabGrid`, no old/new feature flag, and no generalized constraint solver.

## Ownership and composition contract

The cutover is defined field-by-field so Virgo cannot accidentally retain a second X map.

| App/output value | Owner after HPA-164 | Composition rule |
| --- | --- | --- |
| `RenderedMeasure.row/xOffset/width` | package formatted measures | copy directly; do not recompute from app spacing formulas |
| `RenderedNoteHead.position.x` | package `headCenterX` | match by the note's opaque event ID |
| `RenderedNoteHead.position.y` | Virgo | derive from formatted row + existing staff position/override |
| logical onset X | package `logicalColumnX` | shared by every event at the same exact tick |
| rest/control onset X | package position geometry | Virgo keeps semantic/Y presentation; no second tick map |
| full-measure-rest visual X | package | center in final measure body; keep logical timing anchor separate |
| live playhead X + row | package `position(measureIndex:localTick:)` | view model uses result directly; adds no X offset |
| trailing empty measures | Virgo before formatting | move/reuse current `expandedRhythmMeasures` behavior in adapter/preparer, then convert those measures to package values |
| stems/beams/flags | Virgo after formatted heads exist | current topology consumes displaced `RenderedNoteHead.position.x`; HPA-166 owns topology migration |
| measure bars | package measure bounds consumed by Virgo | no `TabGrid` end-X formula |
| no valid snapshot | no notation formatter | clear/install empty notation and use existing non-notation beat UI/runtime fallback |

`RhythmEventPosition` remains Virgo's musical identity. `NotationTickPosition` is only its package-side scalar copy.

For notes, use a deterministic reversible opaque ID derived from `RhythmEventID.rawValue` rather than installing a second persistent ID→geometry table. The package echoes the caller ID unchanged. Rest/control IDs may be deterministic app-generated strings; the package treats them as opaque.

## Coordinate-space contract

All package X values are returned in the same sheet-local X coordinate space that Virgo paints today:

- sheet/canvas left edge is X = 0;
- the first measure on every row starts at `rowLeadingInset`;
- `rowLeadingInset` is mapped from current `GameplayLayout.leftMargin`;
- formatted measure origins, logical columns, displaced head centers, rest/control X, and `position(...)` results all use that same coordinate space;
- Virgo must not add `leftMargin`, `contentStartX`, or any other X transform after formatting.

Y remains app-owned in HPA-164. The package returns row identity; Virgo derives concrete staff Y from row + staff step.

This prevents the playhead and noteheads from drifting because of two different origin transforms.

## Small public package model

HPA-164 exposes only values the formatter uses. Do not publish a second `NotationVoice`: Virgo already owns that concept, and the formatter can resolve the approved displacement rule from `NotationStemDirection` + `staffStep`.

A representative boundary is:

```swift
public struct NotationTickPosition: Hashable, Sendable {
    public let measureIndex: Int
    public let localTick: Int
    public let absoluteTick: Int
}

public enum NotationEngravingSupport: String, Sendable {
    case supported
    case warning
    case unsupported
}

public struct ResolvedMeasure: Hashable, Sendable {
    public let index: Int
    public let startTick: Int
    public let durationTicks: Int
    public let engravingSupport: NotationEngravingSupport
}

public struct ResolvedNote: Hashable, Sendable {
    public let id: String
    public let position: NotationTickPosition
    public let stemDirection: NotationStemDirection
    public let staffStep: Int
    public let noteheadStyle: PercussionNoteheadStyle
    public let duration: NotationDuration
    public let dotCount: Int
}

public struct ResolvedRest: Hashable, Sendable {
    public let id: String
    public let position: NotationTickPosition
    public let duration: NotationDuration
    public let dotCount: Int
    public let isPrinted: Bool
    public let isFullMeasure: Bool
}

public struct ResolvedControl: Hashable, Sendable {
    public let id: String
    public let position: NotationTickPosition
}

public struct ResolvedNotationInput: Hashable, Sendable {
    public let ticksPerWholeNote: Int
    public let measures: [ResolvedMeasure]
    public let notes: [ResolvedNote]
    public let rests: [ResolvedRest]
    public let controls: [ResolvedControl]
}
```

Do not carry package `NotationVoice`, beat-group arrays, tuplet membership, app diagnostic arrays, BPM/seconds, DTX lanes, source models, or SwiftData identifiers in HPA-164. HPA-166 may add beat/tuplet data when the package actually owns those rendering decisions.

Virgo still retains its full source snapshot while composing the transitional renderer, so tuplets, voices, warnings, control semantics and other app-owned rendering data are not lost merely because the HPA-164 formatter does not duplicate them.

The package may receive a minimal supported/warning/unsupported measure state, but never Virgo's diagnostic taxonomy.

## Numeric formatting style

Use one plain `Sendable` scalar style containing only inputs that affect HPA-164 formatting:

```swift
public struct NotationFormattingStyle: Hashable, Sendable {
    public let availableRowWidth: CGFloat
    public let rowLeadingInset: CGFloat
    public let staffSpace: CGFloat
    public let minimumInterColumnGap: CGFloat
    public let minimumQuarterNoteSpacing: CGFloat
    public let measureSpacing: CGFloat
    public let leadingMeasureInset: CGFloat
    public let trailingMeasureInset: CGFloat
    public let rhythmDotRadius: CGFloat
    public let rhythmDotSpacing: CGFloat
}
```

`availableRowWidth` is the sheet-local row boundary used for wrapping, while `rowLeadingInset` places the first measure in that same coordinate space. Virgo resolves the historical 900pt row-width floor before creating this style.

No `GameplayLayout`, screen globals, colors, SwiftUI views, or logger enter the package.

## Measured formatting algorithm

Use one deterministic left-to-right pass. No iterative constraint solver is needed.

### 1. Build exact logical time columns

For each measure:

1. collect notes, printed rests and controls by exact `localTick`;
2. create one logical time column per exact tick;
3. add explicit start (`0`) and end (`durationTicks`) anchors even for empty/trailing measures;
4. keep caller event IDs unchanged.

Controls participate in the exact tick map but contribute no HPA-164 collision width.

All events at the same exact tick share one `logicalColumnX`.

### 2. Apply only approved second-note displacement

HPA-141 intentionally removed voice-based X offsets. HPA-164 must not reintroduce that bug under a generic "VexFlow displacement" label.

Rules:

- mixed-voice / mixed-stem events at the same tick keep the same logical X and head-center X unless a head also participates in the same-stem rule below;
- only heads on the **same stem direction** whose `staffStep` values are adjacent (a staff second) are candidates for local displacement;
- non-adjacent same-stem heads stay centered on the logical column;
- the exact shifted head/direction and minimum offset are pinned by the package's small VexFlow-reference fixtures for up- and down-stem seconds;
- displacement changes only `headCenterX`; event ID, tick and `logicalColumnX` never change.

The output preserves both:

- `logicalColumnX` — timing/playhead coordinate;
- `headCenterX` — visual notehead coordinate.

Virgo's existing stem/beam builders must consume displaced `RenderedNoteHead.position.x` and package glyph stem anchors. They must never substitute `logicalColumnX` when attaching a stem or beam.

### 3. Measure only HPA-164-owned collision geometry

Column horizontal extents include:

- natural HPA-163 notehead painted bounds after local displacement;
- rhythm-dot footprint using `rhythmDotRadius` / `rhythmDotSpacing`;
- natural printed-rest bounds.

They deliberately exclude:

- flags and beam geometry;
- tuplet brackets/labels;
- stop/choke/damp mark footprints;
- articulation footprints;
- warning/feel-mark footprints.

Determining whether a flag is actually unbeamed requires beam topology, and stop marks still use app-owned sizing. Pulling those into the formatter would prematurely absorb HPA-166. If one of those modifiers exposes a visual collision after the measured-X cutover, HPA-166 owns that parity fix unless the problem is simply an incorrect anchor transform.

A full-measure rest keeps a logical timing anchor but is visually centered only after final measure width is known.

### 4. Place columns by rhythm plus collision clearance

For adjacent anchors at ticks `a` and `b`:

```text
rhythmicGap = minimumQuarterNoteSpacing
              * (b - a)
              * 4
              / ticksPerWholeNote

collisionGap = left.rightExtent
               + minimumInterColumnGap
               + right.leftExtent

requiredGap = max(rhythmicGap, collisionGap)
```

Use integer/rational-safe arithmetic until the final `CGFloat` conversion; do not require `ticksPerWholeNote % 4 == 0`.

Accumulate one pass from left to right. Collision expansion is local to the affected interval; there is no chart-wide density-derived scale.

### 5. Derive independent measure widths

Each measure width is its formatted anchor span plus leading/trailing measure insets. Never compress below that collision-free minimum.

An over-wide measure stays at natural width and occupies one row alone. Existing horizontal scrolling handles overflow.

## Greedy row packing

Start every row at `rowLeadingInset`, then pack complete measures in source order:

- include inter-measure spacing;
- start a new row when the next whole measure would exceed `availableRowWidth`;
- never split a measure;
- allow an over-wide first measure to exceed the row boundary;
- row wrapping never changes exact tick identity or per-measure internal spacing.

All returned measure/column/head X values already include row origin. Virgo adds nothing afterward.

## Authoritative tick-position lookup

`FormattedNotation.position(measureIndex:localTick:)` is the only notation musical-position→row/X lookup.

Rules:

1. reject non-finite input; explicitly clamp only tiny boundary drift if needed;
2. exact anchors return exact `logicalColumnX`;
3. between anchors, interpolate only between nearest anchors inside that measure;
4. start/end anchors make empty, control-only and trailing measures resolvable;
5. never interpolate across measure or row boundaries;
6. displaced heads and centered full-measure rests never replace the logical timing coordinate.

Collision-expanded intervals mean there is intentionally **no single X-per-tick scale**. Tests must assert event-tick→logical-X identity and measure-local interpolation, not uniform visual speed across the whole measure.

Virgo continues converting playback seconds to continuous musical ticks; the package never sees seconds/BPM.

## Virgo adapter and preparer responsibilities

### Before formatting

`VirgoNotationAdapter` / `GameplayNotationPreparer`:

- start from immutable `RhythmLayoutSnapshot`;
- expand requested trailing measures using the current timeline-aware behavior before package conversion;
- apply user/default staff-position overrides;
- map only fields used by HPA-164 formatting;
- map app style to `NotationFormattingStyle`, including `rowLeadingInset` and dot metrics.

The adapter performs representation conversion, not spacing or rhythm inference.

### After formatting

The preparer composes one `NotationLayout`:

- copy formatted measures directly;
- build noteheads with package `headCenterX` and app-owned Y;
- place rests/controls from package logical/special visual geometry and app-owned semantic/Y data;
- run existing app stem/beam/flag/ledger/tuplet/mark builders using those positioned primitives;
- use formatted measure bounds for bars;
- embed/retain the immutable `FormattedNotation` so live playhead lookup reads the same anchor data.

No app formatter facade or copied tick table is added.

`GameplayNotationPreparer` remains the detached pure-value worker from HPA-581, and the existing generation rejection/cancellation/install funnel remains unchanged.

## No-snapshot behavior

Delete the notation fallback in `cacheNotationLayout()` as part of the `.legacy` cutover, not merely `layoutLegacy` itself.

- valid `RhythmLayoutSnapshot` → package formatter path;
- no valid snapshot → clear/install empty notation and leave rendering/playback to the existing non-notation legacy beat UI/runtime path;
- fatal rhythm behavior remains governed by the existing rhythm runtime.

HPA-164 does not synthesize a second notation input from `cachedNotes` when the snapshot is absent.

## Fixed-grid deletion checklist

Delete or relocate every production dependency whose only owner is the old notation grid:

- `NotationLayoutTimingInput.legacy` and the timing enum if no longer needed;
- `NotationLayoutInput(notes:controlEvents:timeSignature:...)`;
- `NotationLayoutEngine.layoutLegacy`;
- `TabGrid` and `TabGrid.fallback`;
- chart-wide `tickWidth` and compatibility `ticksPerMeasure` wrappers;
- `TabGrid.tickIndex(forBeatWithinMeasure:)`;
- `RenderedMeasure.contentStartX`;
- `NotationLayout.empty`'s `tabGrid: .fallback` state;
- `buildTabGrid(...)` and fixed-grid measure builders;
- rest/control overloads that accept `TabGrid`;
- `cacheNotationLayout()`'s `NotationLayoutInput(notes:...)` branch;
- `calculateNotationPurpleBarPosition`'s beat-fraction→grid path when no production notation caller remains;
- fixed-grid-only tests/invariants.

Move any still-useful pure timing helper to its real owner instead of leaving `NotationLayoutEngine+TabGrid.swift` as a compatibility shell.

The separate non-notation beat fallback is not part of this deletion.

## Tests

### Package tests

Cover:

- validation/deterministic ordering;
- sparse measure beside dense measure;
- alternating dense/sparse measures across rows;
- same-tick kick/snare/hi-hat sharing one logical column and no voice-based X shift;
- up-stem and down-stem same-stem second displacement;
- non-adjacent chord heads staying centered;
- note/dot/rest extents and adjacent-column non-overlap;
- independent measure widths;
- controlled wrapping and one over-wide measure;
- exact tick lookup and between-anchor interpolation;
- empty/control-only/trailing measures;
- reflow preserving IDs/ticks;
- every returned X using `rowLeadingInset` in one coordinate space.

### Virgo integration tests

Prove:

- adapter preserves exact note IDs/ticks, stem direction, staff step, notehead family, duration/dots, rest/control identity needed by composition;
- app-only voice/tuplet/control semantics still render from the original snapshot without being duplicated into package API;
- formatted measures are copied, not recomputed;
- stem/beam attachment uses displaced `headCenterX`;
- playhead event tick resolves to the same `logicalColumnX` as notation;
- resize/reflow keeps the same musical tick aligned;
- no-snapshot flow does not invoke a notation formatter;
- HPA-581 generation/stale-worker behavior is unchanged;
- real DTX/golden/raster output remains usable.

Run visual/raster checks before accepting regenerated goldens.

## Explicit non-goals

- final beam grouping, secondary beams, hooks, flag collision/parity;
- package-owned tuplet/stop/articulation/warning layout footprint;
- complete static notation view / staff / clef / meter extraction;
- DTX or rhythm-inference changes;
- virtualization, Canvas/Metal, pagination or another rendering backend;
- arbitrary pitched notation or broad VexFlow compatibility;
- compatibility renderer or old/new toggle.

## Acceptance criteria

- One existing `DrumNotation` target owns the measured formatter and tick lookup.
- The HPA-164 package input contains only formatter-needed fields; no package `NotationVoice`, beat groups or tuplets.
- All package X values share one sheet-local coordinate space with explicit `rowLeadingInset`; Virgo applies no post-format X transform.
- Same-tick events share one logical column; mixed voices are not shifted apart.
- Only same-stem adjacent staff-step heads receive the approved local second displacement.
- HPA-164 collision extents cover noteheads, dots and printed rests only; flags/tuplets/stop marks remain HPA-166 scope.
- Dense measures no longer globally widen unrelated sparse measures.
- Measures wrap deterministically and over-wide measures remain natural width.
- `FormattedNotation.position(...)` is the only notation tick→row/X map used by the live playhead.
- `RenderedMeasure` geometry is copied from the package; notehead X uses package `headCenterX`; Y remains app-owned.
- Current stems/beams remain attached to displaced head geometry without changing topology.
- No valid snapshot means no notation formatter; existing non-notation beat fallback remains available.
- `.legacy`, `TabGrid`, `RenderedMeasure.contentStartX`, fixed-grid playhead conversion, and compatibility-only overloads/tests are removed.
- `cachedBeatPositions` is not reintroduced.
- Existing off-main preparation/generation rejection remains intact.
- Package tests, focused visual/golden checks, full serial macOS tests, SwiftLint and iPad build pass.

## PR boundary

Exactly one PR for HPA-164. It owns the compact package formatter contract, measured horizontal columns/rows, authoritative package tick geometry, explicit Virgo composition seam, and deletion of fixed-grid notation. HPA-166 owns final beam/modifier/tuplet/mark parity and the complete reusable static sheet.