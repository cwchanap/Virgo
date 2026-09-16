# HPA-166 Package Engraver and Static Renderer Design

**Issue:** HPA-166 — `[Notation] Complete reusable package renderer and VexFlow beam/modifier parity`

**Scope:** Third and final PR in the HPA-163 → HPA-164 → HPA-166 native `DrumNotation` migration. Move the remaining reusable engraving semantics and complete static notation rendering into `Packages/DrumNotation`, cut Virgo over to the package-owned layout/view, and delete the transitional app-side composition/rendering stack.

**Baseline reviewed:** `main` at `54c4513d967bb50882791bd4a5bd4627ee412f77`, immediately after HPA-164 / PR #66 merged.

## Current state

HPA-163 and HPA-164 deliberately stopped before the final renderer migration:

- `DrumNotation` owns Bravura resources, glyph metrics/primitive glyph views, the resolved tick input, measured formatter, row packing, notehead displacement, printed-rest X placement, and the authoritative tick → row/X lookup.
- `VirgoNotationProjection` maps the analyzed app snapshot into `ResolvedNotationInput` and currently performs a Virgo-side beam-topology prepass only to tell the formatter which visible flag footprint to reserve.
- `GameplayNotationPreparer` still turns `FormattedNotation` back into Virgo `Rendered*` values, then runs Virgo's beam/stem/flag/ledger/rest/control/articulation/tuplet builders and finalizer.
- `GameplaySheetMusicView` still owns the complete static layer stack: staff lines, bars, clefs/time signatures, app primitive wrappers, tuplets, controls, and annotations.
- The mounted live playhead and scroll/auto-scroll orchestration are already separate from the static generation-isolated sheet and should stay that way.

This ticket is therefore not another formatting rewrite. It is the ownership cutover for the engraving work that HPA-164 intentionally left transitional.

## Decision

Use one package-owned engraving pipeline and one package-owned static SwiftUI view:

```text
Virgo DTX / SwiftData / rhythm analysis
                |
                v
       RhythmLayoutSnapshot
                |
                v
       VirgoNotationProjection
  - expand requested measures
  - apply staff overrides
  - resolve voice / beat groups / tuplets
  - resolve articulation + control intent
  - preserve app diagnostics separately
                |
                v
 DrumNotation.ResolvedNotationInput
                |
                v
   package beam-topology prepass
  - measure / voice / stem / beat group
  - primary + secondary beams / hooks
  - uncovered flag levels
                |
                +----> visible flag footprint
                |             |
                v             v
        NotationFormatter.format
                |
                v
       package engraving geometry
  heads / rests / stems / beams / flags
  ledgers / dots / articulations / controls
  tuplets / bars / staff / clef / meter
                |
                v
      DrumNotation.EngravedNotation
          |                  |
          |                  +--> tick/row/bounds lookup
          v
      DrumNotationView
          |
          v
Virgo static generation wrapper
  + app-only feel/warning annotations
  + separate live playhead
  + ScrollView / auto-scroll
```

There is no old/new renderer toggle, no second package target, no app copy of beam topology after cutover, and no new rhythm-analysis subsystem.

## Alternatives considered

### 1. Move only the SwiftUI views, keep beam/modifier geometry in Virgo

Rejected. It would make `DrumNotation` a paint library rather than a reusable renderer, keep the current transitional package→Virgo→package round trip, and leave two owners for notation geometry.

### 2. Move DTX/rhythm inference into the package too

Rejected. `NotationRhythmAnalyzer`, source lane semantics, persistence, diagnostics, and gameplay timing are app/domain responsibilities. Pulling them into `DrumNotation` would widen the package boundary and create a second musical timeline rather than completing the approved renderer extraction.

### 3. Move only resolved engraving semantics into the package

Chosen. Extend the existing resolved input with the smallest information the engraver actually needs: voice, exact event duration, beat groups/meter, supported tuplet membership, articulation intent, and control-mark intent. Everything remains pure values and suitable for off-main preparation.

## Ownership after HPA-166

| Concern | Owner | Rule |
| --- | --- | --- |
| DTX parsing, source lanes, SwiftData | Virgo | Never imported by `DrumNotation` |
| Rhythm inference / diagnostics | Virgo | Package receives resolved values only |
| Staff-position overrides | Virgo projection | Convert to package `staffStep` once |
| Meter + beat-group ranges | Package input | Resolved by Virgo, consumed by package beam topology |
| Horizontal formatting / row packing | `DrumNotation` | Existing HPA-164 formatter remains authoritative |
| Beam/hook topology + flag coverage | `DrumNotation` | Port current proven beat-group algorithm; no app prepass remains |
| Stem/beam/flag/rest/dot/tuplet/control geometry | `DrumNotation` | One immutable engraving result |
| Staff/ledger/clef/meter/bar/static notation view | `DrumNotation` | One package view over the immutable layout |
| Feel text + rhythm warning diagnostics | Virgo | App annotations, because these are app analysis/status UI rather than reusable engraving semantics |
| Playback clock / scoring / MIDI | Virgo | Unchanged |
| Tick → row/X lookup | `DrumNotation` | Package result remains the only notation position authority |
| Final notation Y / row staff centers | `DrumNotation` | App consumes package row geometry; no parallel `GameplayLayout` formula |
| Row anchors, ScrollView, auto-scroll | Virgo | Consume package row geometry; do not recreate notation layout |
| Live playhead | Virgo | Separate overlay using package position/row geometry |

The existing non-notation gameplay fallback for charts with no renderable notation is not a second notation renderer and remains app-owned.

## Minimal resolved package model

HPA-164 intentionally omitted fields that were not needed for horizontal formatting. HPA-166 adds only fields required by final engraving.

### Voice and beat groups

Add package-local value types; do not expose Virgo's enums:

```swift
public enum NotationVoiceRole: Int, Hashable, Sendable {
    case upper
    case lower
}

public struct ResolvedBeatGroup: Hashable, Sendable {
    public let index: Int
    public let startTick: Int
    public let durationTicks: Int
}

public struct NotationMeter: Hashable, Sendable {
    public let beats: Int
    public let noteValue: Int
}
```

Extend `ResolvedMeasure` with `meter` and ordered `beatGroups`. Validate that groups are positive, contiguous from tick 0, and exactly cover `durationTicks`. This reuses the contract the current `NotationBeamTopologyBuilder` already expects; the package does not infer compound-meter grouping itself.

### Notes and rests

Extend `ResolvedNote` with:

- `voice: NotationVoiceRole`;
- `durationTicks: Int` — exact timeline duration, needed for adjacency when tuplets compress a notated duration;
- `isRhythmEngravable: Bool` — resolved app verdict for duration-bearing engraving; notehead identity still renders when the app intentionally preserves a head in an unsupported rhythm;
- `articulation: PercussionArticulation?` — currently `.open` for the supported open-hi-hat mark.

Delete public `visibleFlagDuration`. Once topology is package-owned, exposing a flag-footprint verdict from Virgo would preserve the transitional duplicate source of truth.

`stemMember` also becomes derived inside the package from `isRhythmEngravable` plus whether the notated duration requires a stem. Do not keep both fields.

Extend `ResolvedRest` with `voice` and exact `durationTicks`. Hidden/suppressed rests continue to be filtered before input.

### Tuplets

Represent already-resolved supported groups directly; do not teach the package to discover tuplets:

```swift
public struct ResolvedTupletRatio: Hashable, Sendable {
    public let actual: Int
    public let normal: Int
}

public struct ResolvedTupletGroup: Hashable, Sendable {
    public let id: Int
    public let measureIndex: Int
    public let voice: NotationVoiceRole
    public let ratio: ResolvedTupletRatio
    public let memberNoteIDs: [Int]
    public let memberRestIDs: [Int]
}
```

`VirgoNotationProjection` creates these groups only for tuplets the analyzer already supports. The group ID is a deterministic adapter-local ordinal after sorting the app's stable tuple identity; it is not a Swift `Hasher` result and does not need to survive outside one prepared engraving. Existing swing/shuffle feel-pairs that should not show a tuplet bracket are filtered at the adapter boundary, using the current app rule, rather than adding `RhythmicFeel` to the package.

### Controls

Replace timing-only `ResolvedControl` with resolved visual intent:

```swift
public enum NotationControlKind: String, Hashable, Sendable {
    case stop
    case choke
    case damp
}

public struct ResolvedControl: Hashable, Sendable {
    public let id: Int
    public let position: NotationTickPosition
    public let kind: NotationControlKind
    public let targetStaffStep: Int
}
```

Virgo continues to resolve target lane/instrument semantics and user position overrides. The package sees only the control kind, exact tick, and final target staff step. It does not receive DTX lane IDs, source note IDs, display names, or `DrumType`.

### Input validation

`ResolvedNotationInput` additionally owns `[ResolvedTupletGroup]` and validates:

- unique event/group IDs within each collection;
- note/rest `durationTicks > 0` and remain inside their measure;
- beat groups exactly cover each measure;
- tuplets reference existing notes/rests in the same measure/voice and have a positive ratio.

Do not add defensive compatibility conversions for old package initializers. This is a pre-release package with one consumer; update package fixtures and Virgo projection in the same PR.

## Package beam topology and flag footprint

Port the current `NotationBeamTopologyBuilder` into `DrumNotation` rather than redesigning its musical rules.

### Grouping key

The package pre-format topology groups by:

- measure;
- resolved voice;
- stem direction;
- resolved beat group.

The current app builder also carries row in the grouping key. It is unnecessary before formatting because HPA-164 never splits a measure across rows. After formatting, add an invariant that every beam group belongs to one formatted row; a violation is a formatter/engraver bug.

### Adjacency and segments

Preserve the current exact-duration adjacency and segment behavior:

- primary run requires at least two consecutive beamable onsets;
- level 0 spans the primary run;
- higher levels form full secondary segments when adjacent members share the level;
- one isolated higher-level member becomes a forward/backward hook using the current neighbor/tie-break rule;
- groups never cross measure, voice, stem direction or beat-group boundaries.

Supported tuplets provide exact `durationTicks`, so adjacency does not depend on converting a tuplet back into a binary duration.

### Visible flags

The topology prepass returns covered beam levels per stem event. The engraver derives uncovered levels and reserves the flag footprint before the formatter runs:

- no uncovered levels → no flag footprint;
- all required levels uncovered → one canonical duration-specific flag;
- partially uncovered levels → component eighth-flag footprint per uncovered level, matching the existing rendering policy.

The post-format renderer consumes the same topology result to create actual flags. There is no second classification pass and `VirgoNotationProjection+Flags.swift` is deleted after cutover.

## Engraving result and style

### Style

Keep `NotationFormattingStyle` for the formatter and introduce one `NotationEngravingStyle` that composes it with the vertical/mark metrics needed after formatting:

```swift
public struct NotationEngravingStyle: Hashable, Sendable {
    public let formatting: NotationFormattingStyle
    public let rowHeight: CGFloat
    public let rowVerticalSpacing: CGFloat
    public let stemLength: CGFloat
    public let minimumStemExtensionPastChord: CGFloat
    public let beamThickness: CGFloat
    public let beamLevelSpacing: CGFloat
    public let beamHookLength: CGFloat
    public let ledgerLineOverhang: CGFloat
    public let upperVoiceRestOffset: CGFloat
    public let lowerVoiceRestOffset: CGFloat
    public let stopMarkSize: CGFloat
    public let stopMarkStrokeWidth: CGFloat
    public let stopMarkVerticalOffset: CGFloat
    public let articulationVerticalOffset: CGFloat
    public let tupletLineWidth: CGFloat
    public let tupletLabelSize: CGSize
    public let tupletVerticalOffset: CGFloat
    public let tupletHookLength: CGFloat
    public let barLineWidth: CGFloat
    public let doubleBarThinWidth: CGFloat
    public let doubleBarThickWidth: CGFloat
    public let doubleBarSpacing: CGFloat
    public let clefWidth: CGFloat
    public let meterWidth: CGFloat
}
```

Derive staff height and line Y positions from the formatter's `staffSpace`; do not add app-authored notehead/rest box sizes because Bravura metrics already own those glyph bounds.

Provide a small public `.standard` style so the package's ordinary-import consumer test and a future second consumer can construct the API without Virgo. Virgo does **not** rely on that convenience: `VirgoNotationProjection.engravingStyle(rowWidth:style:)` remains the only app mapper and explicitly maps current numeric `GameplayLayout`/`NotationLayoutStyle` values.

### Immutable result

Add one public `EngravedNotation` value containing:

- the existing `FormattedNotation`;
- formatted measures and explicit row geometry;
- notehead/rest/control positions;
- stems, beams, flags, ledger lines, dots, articulations, tuplets and measure bars;
- staff-row, clef and meter descriptors used by the package view;
- `paintedBounds`, `contentWidth`, `contentHeight`;
- lookup helpers for note ID and musical tick positions.

Primitive/result types are public immutable values because consumers/tests need geometry. Their mutation/build helpers remain internal.

Expose one entry point:

```swift
public enum NotationEngraver {
    public static func engrave(
        _ input: ResolvedNotationInput,
        style: NotationEngravingStyle
    ) throws -> EngravedNotation
}
```

`NotationFormatter` may remain public during this PR if package tests/consumers still need direct formatter coverage, but Virgo production code must call only `NotationEngraver.engrave`. Do not introduce a second public engine object or mutable builder.

## Geometry rules

### Vertical coordinate system

Package output becomes authoritative in both X and notation Y:

- each formatted row gets one deterministic staff center derived from `rowHeight` + `rowVerticalSpacing`;
- `staffStep` converts to notehead Y using `staffSpace / 2`;
- rests use voice offsets from the staff center;
- controls use their resolved target staff step and stop-mark vertical offset;
- ledger lines derive from final head geometry;
- stems use Bravura head attachment metrics and keep the HPA-164 undisplaced stem-side axis.

Build raw vertical geometry, calculate its painted bounds once, then normalize the complete engraving by one package-owned Y translation when raw `minY < 0`. `EngravedNotation.rows`, every primitive, `paintedBounds`, and the row geometry consumed by Virgo are all the **final normalized sheet-local coordinates**. `DrumNotationView` therefore applies no hidden layout translation, and Virgo has no `topContentInset` formula to reproduce for the playhead or row anchors.

This removes the current state where package X is authoritative but Virgo recomputes every notation Y.

### Stems, beams and hooks

Reuse existing flat percussion beam behavior unless the pinned reference fixture proves a difference:

- stem anchor starts from the final stem-side notehead attachment point;
- same-stem staff-second displacement never shifts the shared stem axis;
- primary/secondary beams use flat Y for a group;
- stem endpoints extend only enough to reach the beam stack plus minimum chord clearance;
- hook length uses the existing style value and the same neighbor direction as topology;
- beam paint is clipped by neither measure nor row because topology guarantees group boundaries.

### Rests and dots

- printed rest X remains the HPA-164 formatter result;
- voice determines rest Y;
- dot X uses actual final glyph painted bounds + formatter dot spacing, not legacy box width;
- full-measure rest centering remains formatter-owned.

### Articulations

The adapter resolves `.open` intent on the note. Package placement follows the final notehead bounds and staff direction-independent gap. Closed hi-hat remains represented by its existing X notehead, not a new articulation feature.

### Tuplets

Package geometry uses the resolved group membership:

- if the entire group is continuously beamed and contains no rests, show the label without a bracket;
- otherwise show the bracket + label;
- place the label outside the beam/head/rest bounds in the resolved stem/voice direction;
- support only the tuplets Virgo already resolves; no arbitrary/nested tuplets.

### Stop / choke / damp

All three remain independent control marks, never rests. The package positions them at the authoritative logical tick X and resolved target staff Y. Preserve kind and ID in `EngravedNotation` so visual tests can distinguish them even if the initial mark shape remains shared.

## Static SwiftUI package view

Add one public view:

```swift
public struct DrumNotationView: View {
    public init(
        layout: EngravedNotation,
        appearance: NotationAppearance = .init()
    )
}
```

`NotationAppearance` is a view-boundary value and may contain SwiftUI `Color`; it is not part of the off-main engraving request.

The view owns only static notation drawing:

- five staff lines per rendered row;
- percussion clef at each row start;
- meter at each row start and at a resolved meter change within a row;
- measure/final bars;
- ledger lines;
- noteheads/rests/stems/beams/flags/dots;
- articulations, controls and tuplets.

Virgo continues to draw:

- background/screen chrome;
- feel label and rhythm warning annotations;
- row-anchor invisible views used by `ScrollViewReader`;
- live playhead.

Move the reusable portions of `NotationPrimitiveViews.swift`, `GameplayBarLinesView`, `GameplayClefsAndTimeSignaturesView`, and `GameplayDrumNotationView` into the package; do not keep wrappers that only translate one package primitive back into another package primitive.

## Virgo cutover

### Projection

`VirgoNotationProjection` becomes the permanent resolved-data adapter:

1. expand trailing measures using the existing app policy;
2. map measures + beat groups + meter;
3. map notes with resolved voice, staff step, duration ticks, notehead style, articulation and rhythm-engravable verdict;
4. map printed rests with voice/duration/tuplet membership;
5. map supported tuplets to deterministic adapter-local group IDs, filtering current feel-pairs that intentionally have no tuplet mark;
6. resolve control target lane + user staff override to package control intent;
7. map one `NotationEngravingStyle`;
8. call `NotationEngraver.engrave`.

Delete the package-visible flag classification from Virgo.

### Preparation state

Replace the transitional pair `NotationLayout + FormattedNotation` with package engraving plus app annotations:

```swift
struct GameplayNotationPreparedState: Sendable {
    let engraving: EngravedNotation
    let annotations: GameplayNotationAnnotations
}
```

`GameplayNotationAnnotations` contains only the current feel mark and rhythm warning values derived from app analysis. It must not recreate stems, beams, bars, rests, tuplets or controls.

### Mounted sheet

`GameplayStaticNotationView` remains generation-keyed/equatable, but its static tree becomes:

```text
ZStack
  DrumNotationView(layout: engraving, appearance: chalk appearance)
  GameplayNotationAnnotationsView(...)
  GameplayRowAnchorColumn(rows: engraving.rows)
```

The parent still places the separate playhead overlay and owns scrolling.

The package result supplies normalized content bounds/row geometry. Delete app `contentWidth`, `topContentInset`, notehead-derived row padding, and measure-position geometry that exist only to re-derive the static sheet. Keep only the legacy non-notation fallback values needed when there is no renderable notation.

## VexFlow reference strategy

Do not add Node/jsdom tooling by default.

First port current topology and add package structural fixtures for:

- mixed 8/16;
- mixed 16/32;
- forward hooks;
- backward hooks;
- isolated flags in both stem directions;
- dotted notes and rests;
- triplets/tuplets;
- supported 6/8 compound grouping;
- simultaneous upper/lower voices;
- stop/choke/damp adjacent to notes;
- one dense multi-row passage.

For each fixture, record the expected VexFlow 5.0.0 structural behavior in the test name/comment and assert the package's actual segment membership/direction/geometry.

Only if an implementation dispute cannot be resolved from the pinned VexFlow 5.0.0 source/behavior should this PR add a package-local executable reference harness. If added, it must:

- be test/reference tooling only;
- pin VexFlow 5.0.0;
- generate a small committed reference artifact for the exact disputed fixtures;
- be consumed by Swift parity tests or the review gate.

A generator whose output no test reads is out of scope.

## Testing and verification

### Package-native tests

Move pure geometry/topology checks into `Packages/DrumNotation/Tests/DrumNotationTests/` and add:

- resolved-input validation tests;
- beam topology + hooks + mixed-level tests;
- flag coverage tests proving the same topology drives spacing and painting;
- stem/head attachment and beam connection geometry tests;
- rest/dot/articulation/control placement tests;
- tuplet bracket/no-bracket tests;
- staff/clef/meter/bar descriptor tests;
- raster ink-within-painted-bounds coverage for the final package view;
- an ordinary `import DrumNotation` public-consumer test that constructs resolved input → `NotationEngraver.engrave(style: .standard)` → geometry lookup → `DrumNotationView` without `@testable` or Virgo.

Run `swift test --package-path Packages/DrumNotation` independently.

### Virgo integration tests

Keep tests that provide different evidence:

- real DTX → analyzer → `VirgoNotationProjection` → package integration;
- `DrumTabGoldenTests` / structural invariants over representative real fixtures;
- playhead alignment using package tick/row lookup;
- generation isolation and mounted static-sheet test;
- control source semantics before they are converted to package values;
- app warning/feel annotations.

Delete app-only pure beam/primitive tests once equivalent package tests exist; do not keep two copies of the same geometry contract.

### Visual gate

Before accepting golden churn:

1. render one dense real DTX chart;
2. render one sparse chart;
3. render at widths that force different row wrapping;
4. inspect one production-mounted macOS sheet for symbol attachment, beam/hook direction, collisions, clipping and readability;
5. run the iPad simulator build/compile gate.

Regenerate goldens only after structural/numeric package invariants are green. Any changed golden must be attributable to the intended HPA-166 engraving ownership/parity change.

No new art/image-generation task is required; this work uses notation glyph/font resources already owned by the package.

## Deletion target

By the end of this PR, remove code whose only purpose was transitional app-side engraving:

- `Virgo/layout/NotationBeamTopology.swift` after its tests move;
- `Virgo/layout/VirgoNotationProjection+Flags.swift`;
- reusable beam/stem/flag/ledger/rest/control/tuplet construction in `NotationLayoutEngine+Beams.swift`, `+Controls.swift`, `+Rests.swift`, and `+RhythmRendering.swift` once the package owns each responsibility;
- `GameplayNotationPreparer.composeVirgoLayout` and its lookup/rebuild/finalization helpers;
- package-backed wrappers in `Virgo/views/NotationPrimitiveViews.swift` and app static notation layers that the package view replaces.

Do **not** delete unrelated rhythm analysis, timeline, DTX, playback, scrolling, annotations or test-fixture import code merely because it shares an old file.

## Risks and mitigations

### Scope explosion while moving the large app renderer

Mitigation: port proven algorithms first, change ownership before changing musical behavior, and keep VexFlow parity fixes limited to the explicit fixture set. No generic music-notation framework.

### Spacing/flag drift when topology ownership moves

Mitigation: one package topology result must feed both pre-format flag footprint and post-format flag painting. Add a direct invariant before deleting Virgo's prepass.

### Vertical coordinate drift

Mitigation: package output becomes the only notation Y authority and normalizes to final zero-based sheet coordinates once. Lock row/staff/notehead numeric invariants before visual golden regeneration; app playhead/row anchors consume those final package row coordinates.

### Test churn hides real regressions

Mitigation: migrate pure tests before deleting app implementations; keep real-DTX, mounted-view and playhead tests in Virgo; review golden changes last.

### Public API grows into app model duplication

Mitigation: public values contain only resolved engraving semantics. No `DrumType`, DTX lane IDs, diagnostics, playback state, SwiftData identity or app theme types.

## Non-goals

- No rhythm analyzer rewrite.
- No new DTX semantics or control import behavior.
- No pitched/cross-staff notation.
- No arbitrary/nested tuplets.
- No WebView, Canvas, Metal, pagination or virtualization work.
- No package publication, second repository, demo app, versioning policy or extraction harness.
- No backward-compatibility shim for the pre-HPA-166 package API.
- No new production dependency on VexFlow/Node.
- No performance work from HPA-584.

## Completion criteria

HPA-166 is complete when:

1. `DrumNotation` owns beam topology, modifier/control/tuplet geometry, vertical geometry and the complete static notation view.
2. Virgo maps resolved domain semantics once, then consumes one `EngravedNotation`; it does not rebuild package engraving.
3. The package topology result drives both formatter flag footprint and rendered flags.
4. Package row/primitives are normalized final sheet-local Y coordinates, and Virgo playhead/row anchors consume them without a parallel inset formula.
5. The mounted sheet hosts `DrumNotationView` while Virgo retains only app annotations, row anchors, scrolling and the live playhead.
6. Pure package tests cover the requested VexFlow beam/modifier fixtures and the ordinary-import consumer flow.
7. Real-DTX/golden/playhead/mounted-sheet integration coverage remains in Virgo and passes.
8. Transitional app geometry/rendering code is deleted rather than hidden behind a compatibility path.
9. `swift test --package-path Packages/DrumNotation`, focused/full macOS verification, mounted visual smoke, iPad build and SwiftLint are green before this same PR is marked ready.

**Exactly one PR for HPA-166.** Planning documents land first on the ticket branch; implementation continues on this same draft PR.