# HPA-164 Measured Formatting and Shared Tick Geometry Design

**Issue:** HPA-164 — `[Notation] Add measured formatting and shared tick geometry to DrumNotation`

**Scope:** Second PR in the HPA-163 → HPA-164 → HPA-166 migration. Move horizontal notation formatting and musical-position lookup into the existing `DrumNotation` package, cut Virgo over to that geometry, and delete the superseded fixed-grid notation renderer. Final stem/beam/modifier parity and the complete package-owned static sheet remain HPA-166.

**Baseline reviewed:** `main` at `8a29b68f7afeb29c162e2587fad26c192d71beda` after HPA-163 / PR #65 merged.

## Current state after HPA-163

HPA-163 established the intended package boundary but deliberately stopped before horizontal formatting:

- `Packages/DrumNotation/` is one local Swift package with one library target and one package test target.
- The package owns Bravura resources, the closed percussion primitive vocabulary, staff-space-scaled glyph metrics, and primitive SwiftUI views.
- `Virgo/layout/VirgoNotationAdapter.swift` is the single pure app-to-package mapping seam, but today it maps primitive types/metrics and flag paint policy only.
- Virgo still owns `TabGrid`, a single chart-wide `tickWidth`, measure width calculation, row packing, note/rest/control X placement, and playhead X lookup.
- `NotationLayoutEngine` still contains both `.timeline(RhythmLayoutSnapshot)` and the fixed-measure `.legacy(notes:controls:timeSignature:)` notation path.
- Existing stems/beams/flags/ledger lines are built after notehead placement, which gives HPA-164 a clean transitional seam: they can consume package-positioned heads without moving final topology into the package yet.
- HPA-581 already removed the old production `cachedBeatPositions` cache. HPA-164 must not recreate that unused cache simply because older HPA-164 wording mentions it.

The problem is therefore narrow: Virgo already has exact musical timing and package-owned glyph metrics, but its visual X geometry is still a global linear grid.

## Decision

Add one deterministic measured formatter to the existing `DrumNotation` target and make its result the only notation X-coordinate authority.

The data flow becomes:

```text
Virgo DTX / SwiftData / rhythm analysis
                |
                v
       RhythmLayoutSnapshot
                |
                v
       VirgoNotationAdapter
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
       |                         +--> tick lookup --> Virgo playhead / scrolling
       v
Virgo transitional renderer
(existing stems / beams / marks, using package head/column geometry)
```

There is no second formatter, no fallback `TabGrid`, and no generalized constraint solver.

## Ownership boundary

### DrumNotation owns in HPA-164

- Package-local resolved notation input values.
- Scalar numeric formatting style.
- Exact-onset logical time columns.
- Glyph-aware horizontal column extents.
- Local same-onset notehead displacement.
- Per-measure collision-free minimum width.
- Greedy complete-measure row packing.
- Immutable row/measure/column/head geometry.
- Authoritative exact-tick and between-anchor tick-to-X lookup.

### Virgo continues to own

- DTX parsing and source chip/lane semantics.
- SwiftData and persistence.
- `RhythmLayoutSnapshot`, rhythm inference, duration/rest/tuplet analysis, and diagnostic generation.
- Drum/instrument mapping and user staff-position overrides.
- Staff Y placement and app theme/chrome.
- Existing beam grouping/topology, stem/beam/flag rendering, tuplets and app-side warning/control presentation until HPA-166 moves reusable pieces.
- Audio, metronome, scoring, playback clock → musical tick conversion, auto-scroll policy, task cancellation and generation rejection.

The package never imports Virgo and never receives `Note`, `DrumType`, `NoteType`, `RhythmLayoutSnapshot`, `GameplayLayout`, `Palette`, SwiftData IDs, or the app logger.

## Small public package model

Do not create separate Core/Layout/UI targets or a generic music-notation object graph. Add only the resolved values needed by the approved percussion formatter.

The exact naming may be adjusted during implementation for Swift ergonomics, but the boundary should have this shape:

```swift
public struct NotationTickPosition: Hashable, Sendable {
    public let measureIndex: Int
    public let localTick: Int
    public let absoluteTick: Int
}

public enum NotationVoice: String, Sendable {
    case upper
    case lower
}

public struct ResolvedMeasure: Hashable, Sendable {
    public let index: Int
    public let startTick: Int
    public let durationTicks: Int
    public let meterNumerator: Int
    public let meterDenominator: Int
    public let beatGroupStarts: [Int]
    public let engravingSupport: NotationEngravingSupport
}

public struct ResolvedNote: Hashable, Sendable {
    public let id: String
    public let position: NotationTickPosition
    public let durationTicks: Int
    public let voice: NotationVoice
    public let stemDirection: NotationStemDirection
    public let staffStep: Int
    public let noteheadStyle: PercussionNoteheadStyle
    public let duration: NotationDuration
    public let dotCount: Int
    public let tuplet: ResolvedTuplet?
    public let articulation: PercussionArticulation?
}

public struct ResolvedRest: Hashable, Sendable { /* resolved timing/voice/visibility */ }
public struct ResolvedControl: Hashable, Sendable { /* opaque id, exact tick, staff intent */ }

public struct ResolvedNotationInput: Hashable, Sendable {
    public let ticksPerWholeNote: Int
    public let measures: [ResolvedMeasure]
    public let notes: [ResolvedNote]
    public let rests: [ResolvedRest]
    public let controls: [ResolvedControl]
}
```

Use caller-supplied scalar/string IDs. Virgo retains any lookup from these IDs back to source chips, scoring events, controls, or model objects.

`ResolvedNotationInput` is already resolved notation. The package must not infer durations, re-quantize ticks, decide DTX lane semantics, or translate BPM/seconds.

### Diagnostics and unsupported engraving

The formatter needs to know whether a measure is engravable, but it does not need Virgo's complete diagnostic enum. Use a minimal package-owned support value such as supported / warning / unsupported, with opaque diagnostic codes only if the transitional app presentation actually needs to round-trip them.

Do not mirror the entire Virgo rhythm diagnostic model into the package.

## Numeric formatting style

The formatter receives a plain `Sendable` scalar style. It must not reference app globals or SwiftUI appearance values.

Required values are limited to geometry that changes formatting:

- available row width;
- staff space;
- minimum inter-column gap;
- minimum quarter-note spacing;
- measure spacing;
- leading/trailing measure content inset needed by current bar/clef/meter presentation;
- row vertical metrics only if required to return concrete row bounds.

Virgo maps its current `NotationLayoutStyle`/`GameplayLayout` constants into this value once in `VirgoNotationAdapter`. Do not copy app constant names into the package API.

The app continues resolving the historical 900pt row-width floor before the request reaches the package; changing that product behavior is not part of HPA-164.

## Measured formatting algorithm

Use a simple deterministic left-to-right formatter. A full constraint solver is unnecessary.

### 1. Build exact logical time columns

For each measure:

1. collect notes, printed rests and controls by exact `localTick`;
2. create one logical time column per exact tick;
3. retain all event IDs/voices inside that column;
4. add explicit measure-start (`0`) and measure-end (`durationTicks`) lookup anchors even when no visible event exists there.

Events sharing a tick always share one logical column X. Notehead displacement never changes their musical tick or logical-column X.

### 2. Resolve local notehead displacement

All heads begin centered on their logical column. Within a same-onset stem/voice chord, apply the smallest horizontal displacement needed for adjacent-head collisions according to the pinned VexFlow reference cases.

Do not guess a broad VexFlow implementation up front. Add package fixtures for the small percussion cases Virgo needs first, including both stem directions, then implement the closed rule that matches those fixtures.

The formatter output must preserve both:

- `logicalColumnX` — authoritative timing coordinate;
- `headCenterX` — possibly displaced visual notehead center.

Stem attachment and HPA-164's transitional app-side beam composition consume `headCenterX` plus the HPA-163 package glyph anchors. Playhead lookup consumes `logicalColumnX`.

### 3. Measure each column from real glyph geometry

For every logical column compute horizontal visual extents relative to the logical X from the package metrics already established by HPA-163.

Include only geometry that materially affects horizontal collision in this stage:

- natural notehead painted bounds, including displaced heads;
- rhythm dots already resolved by Virgo;
- natural flag extent when it is attached to an unbeamed head and affects the column's horizontal footprint;
- current control/mark horizontal footprint when it shares the onset column and can collide with the next column.

Do not move final beam/modifier topology into the formatter merely to measure it. Beam spans connect already-positioned stems and are handled after columns are placed.

Full-measure rests are a special visual: keep their musical anchor in the tick map, but center their painted glyph in the final measure body after width is known. Their centered visual X is not the logical onset X.

### 4. Place columns with local rhythmic spacing plus collision clearance

For adjacent anchors at ticks `a` and `b`, calculate a temporal baseline from their local musical distance:

```text
quarterTicks = ticksPerWholeNote / 4
rhythmicGap = minimumQuarterNoteSpacing * (b - a) / quarterTicks
collisionGap = left.rightExtent + minimumInterColumnGap + right.leftExtent
requiredGap = max(rhythmicGap, collisionGap)
```

Use exact rational/integer-safe arithmetic where needed to avoid assuming `ticksPerWholeNote` is divisible by four before the final CGFloat conversion.

A single left-to-right pass accumulates the minimum X positions. This preserves proportional rhythmic readability where content is small while allowing local collisions to expand only the affected interval. A dense measure therefore no longer inflates every unrelated measure in the chart.

No iterative relaxation, Cassowary-style solver, or chart-wide density scan is needed.

### 5. Derive one minimum width per measure

The measure width is:

```text
leading inset
+ formatted start→end anchor span
+ trailing inset
```

It is never compressed below that collision-free minimum.

An exceptionally wide measure is allowed to exceed the available row width and occupies a row alone. The existing horizontal scrolling surface handles the overflow; the formatter does not scale glyphs or squeeze spacing to make it fit.

## Greedy row packing

After all measures have independent minimum widths, pack complete measures in source order:

- start a new row when the next complete measure plus inter-measure spacing would exceed the available row width;
- never split one measure across rows;
- if the first measure on a row is wider than the available width, keep it on that row at its natural width;
- row packing never changes column identity or per-measure internal spacing.

This preserves the current simple product behavior while allowing dense and sparse measures to size independently.

## Authoritative tick-position lookup

`FormattedNotation` owns the only notation tick-position lookup.

Expose a value API equivalent to:

```swift
public func position(
    measureIndex: Int,
    localTick: Double
) -> TimelineGeometryPosition?
```

The result includes at least the row index and X coordinate.

Rules:

1. Clamp or reject non-finite/out-of-measure values explicitly; do not silently jump to another measure.
2. Exact anchor ticks return the exact logical column X.
3. Between anchors, interpolate only between the nearest anchors inside the same measure.
4. Measure start/end anchors make empty, control-only and trailing measures resolvable.
5. Never interpolate across a row boundary or from one measure's end into another measure's start.
6. A displaced notehead center and a centered full-measure rest never replace the logical timing coordinate.

Virgo converts playback seconds to continuous musical ticks as it does today, then asks this mapping for row/X. The package never sees seconds or BPM.

## Virgo integration

### Extend, do not duplicate, VirgoNotationAdapter

`VirgoNotationAdapter` becomes the permanent representation boundary for HPA-164:

- `RhythmLayoutSnapshot` + staff overrides → `ResolvedNotationInput`;
- app numeric style → package formatting style;
- app IDs/enums → package IDs/enums;
- package formatted geometry → the existing app-rendered values needed while HPA-166 is pending.

The adapter may contain small conversion helpers, but it must not implement spacing rules or a second tick map.

### Keep GameplayNotationPreparer as the worker boundary

`GameplayNotationPreparer.prepare` remains the detached pure-value operation established by HPA-581. Its work becomes:

1. convert the immutable snapshot/request through `VirgoNotationAdapter`;
2. call the package formatter;
3. compose the package geometry with the still-app-owned stem/beam/mark renderer;
4. return one immutable `NotationLayout` for the existing generation-checked install path.

No layout work moves into a SwiftUI body and no package type needs `@MainActor`.

### Transitional app renderer

To keep HPA-164 one PR without stealing HPA-166:

- notes/rests/controls receive X geometry from `FormattedNotation`;
- app staff-position logic continues deriving Y from row + staff step;
- current stem/beam/flag/ledger/tuplet/mark builders consume those positioned primitives;
- existing beam topology remains unchanged;
- `NotationLayout` retains or embeds the immutable package formatted result so live tick lookup uses package geometry directly rather than copying its anchor table.

Do not introduce a new `VirgoNotationLayoutFormatter` or any other app-owned formatter facade.

## Delete the fixed-grid notation path in this PR

HPA-164 is a breaking pre-release cutover. Delete, rather than adapt:

- `NotationLayoutTimingInput.legacy`;
- `NotationLayoutInput(notes:controlEvents:timeSignature:...)` when no production caller remains;
- `NotationLayoutEngine.layoutLegacy`;
- `TabGrid` and its fixed-measure/tick-width compatibility helpers once all supported callers are migrated;
- `buildTabGrid(...)` and chart-wide `tickWidth` sizing;
- test-only assumptions that one chart-wide tick scale spans every measure;
- app branches whose only purpose is selecting the old notation renderer.

This does **not** require deleting the separate non-notation legacy beat UI/runtime fallback used when no valid rhythm snapshot exists. When the notation runtime has no valid `RhythmLayoutSnapshot`, do not invoke a second notation formatter. Existing non-notation fallback behavior may remain outside this package migration.

Tests that manually construct `NotationLayoutInput(notes:...)` must either:

- move to package-level resolved formatting tests when they test geometry only;
- construct a small `RhythmLayoutSnapshot`/production conversion when they test app integration;
- be deleted when they exist solely to preserve `TabGrid` compatibility.

No compatibility shim is required.

## Stale cachedBeatPositions wording

HPA-164's older ticket text mentions routing `cached beat positions` through the new mapping. HPA-581 subsequently deleted that production cache because it had no production reader.

Do not recreate it.

The current equivalent acceptance contract is:

- notation events use package logical columns;
- live timeline playhead lookup uses the same package tick map;
- row lookup comes from the same package-formatted measures;
- tests compare those paths directly rather than asserting an otherwise-unused cache.

## Tests

### Package tests

Add package-only tests for:

- input validation and deterministic ordering;
- sparse measure beside dense measure;
- dense/sparse alternation across rows;
- same-tick kick/snare/hi-hat sharing one logical column;
- up-stem and down-stem adjacent-head displacement reference cases;
- column extents and non-overlap;
- independent per-measure minimum widths;
- controlled row wrapping;
- one over-wide measure occupying a row alone;
- exact tick lookup;
- between-anchor interpolation;
- empty/control-only/trailing measure start/end anchors;
- lookup never crossing a row/measure boundary;
- reformat at a second available width preserving IDs/ticks while changing rows deterministically.

Keep these tests free of Virgo and the app test host.

### Virgo integration tests

Retain or update tests that prove:

- adapter preserves event IDs, ticks, voice, staff intent, notehead family, duration, dots/tuplets/rest/control semantics;
- real DTX/snapshot → formatter → existing rendered sheet works;
- stems/beams stay attached to displaced/package-positioned heads;
- purple playhead X resolves through package tick geometry;
- resize/reflow updates rows and keeps the playhead aligned;
- generation/stale-worker rejection remains unchanged;
- golden/raster output contains no adjacent head/column overlap in the approved fixtures.

Replace the old global `tickWidth` invariant with behavioral invariants: monotonic logical time, same-tick logical-column identity, collision-free extents, local measure sizing, and shared notation/playhead lookup.

## Visual verification

Horizontal spacing and local chord displacement are user-visible changes. Before regenerating text goldens blindly:

1. run package geometry tests;
2. run the existing raster/render probes on representative sparse/dense and chord fixtures;
3. inspect at least one generated macOS notation preview covering both changed behaviors;
4. only then update expected goldens.

Do not add a permanent screenshot framework or a new visual-regression service.

## Explicit non-goals

- No final beam grouping, secondary-beam, hook, stem-angle or modifier parity rewrite; HPA-166 owns it.
- No complete package static sheet yet; HPA-166 owns staff/clef/bar presentation migration.
- No DTX parser or rhythm-analysis rewrite.
- No playback, scoring or timing-model rewrite.
- No virtualization, pagination, Canvas, Metal, WebView or alternate renderer.
- No arbitrary pitched notation or generic VexFlow compatibility layer.
- No second Swift package target, repository extraction, publication/versioning workflow, or demo app.
- No backward-compatible old/new formatter switch.

## Risks and controls

### Existing beams assume shared head centers

**Risk:** New chord displacement can expose assumptions in app beam/stem code.

**Control:** package output keeps logical and displaced head X separately; app composition uses displaced head geometry and HPA-163 stem anchors. Adapt only coordinates required to keep current topology attached. Defer topology parity to HPA-166.

### Width-dependent reflow can expose stale playhead state

**Risk:** row changes after resize while playback is active.

**Control:** install one coherent formatted result through the existing generation funnel; derive row and X from the newly installed package geometry. Reuse the HPA-581 generation/debounce path rather than adding another cache.

### Manual tests depend heavily on legacy input

**Risk:** preserving all old helpers would quietly preserve the old renderer.

**Control:** classify tests by behavior. Move pure formatting coverage into package tests, migrate meaningful integration tests to snapshots, and delete fixed-grid compatibility assertions.

### Scope creep into HPA-166

**Risk:** package ownership makes it tempting to move beams/staff rendering now.

**Control:** stop at finalized columns/heads/rows/tick geometry plus the minimum app coordinate adaptation. If a change is only needed to improve final beam/modifier parity rather than to attach existing geometry, it belongs to HPA-166.

## Completion criteria

HPA-164 is complete when:

- `DrumNotation` has one package-owned resolved input and one deterministic measured formatter;
- each measure derives width from its own content and exact timing rather than a global chart `tickWidth`;
- same-tick events share a logical column and required head displacement is deterministic;
- adjacent formatted columns/heads do not overlap in supported fixtures;
- complete measures pack greedily by available width and over-wide measures remain natural width;
- `FormattedNotation` is the single tick→row/X authority for notation and playhead lookup;
- Virgo's adapter is representation conversion only and no app spacing/tick-map copy exists;
- HPA-581 off-main preparation/generation isolation is preserved;
- existing app beams/stems remain attached sufficiently for an intermediate usable renderer;
- `.legacy` fixed-grid notation layout, `TabGrid`, chart-wide `tickWidth`, and their compatibility-only tests are removed;
- no deleted cache such as `cachedBeatPositions` is reintroduced;
- package tests, affected Virgo tests/goldens/raster checks, full serial macOS tests, SwiftLint and the iPad build pass;
- final beam/modifier/static-view work remains clearly deferred to HPA-166.
