# HPA-166 Package Engraver and Static Renderer Design

**Issue:** HPA-166 — `[Notation] Complete reusable package renderer and VexFlow beam/modifier parity`

**Scope:** Third and final PR in the HPA-163 → HPA-164 → HPA-166 native `DrumNotation` migration. Move the remaining reusable engraving semantics and complete static notation rendering into `Packages/DrumNotation`, cut Virgo over to the package-owned layout/view, and delete the transitional app-side composition/rendering stack.

**Baseline reviewed:** `main` at `54c4513d967bb50882791bd4a5bd4627ee412f77`, immediately after HPA-164 / PR #66 merged.

## Current state

HPA-163 and HPA-164 deliberately stopped before the final renderer migration:

- `DrumNotation` owns Bravura resources, glyph metrics/primitive glyph views, the resolved tick input, measured formatter, row packing, notehead displacement, printed-rest X placement, and the authoritative tick → row/X lookup.
- `VirgoNotationProjection` maps the analyzed app snapshot into `ResolvedNotationInput` and currently performs a Virgo-side beam-topology prepass only to tell the formatter which visible flag footprint to reserve.
- `GameplayNotationPreparer` still turns `FormattedNotation` back into Virgo `Rendered*` values, then runs Virgo beam/stem/flag/ledger/rest/control/articulation/tuplet builders and finalization.
- `GameplaySheetMusicView` still owns the static layer stack: staff lines, bars, clefs/time signatures, app primitive wrappers, tuplets, controls, and annotations.
- `DrumTabGoldenTests`, `DrumTabRegressionInvariantTests`, `DrumTabRenderProbeTests`, and the real-DTX fixture harness are the regression net around exactly this renderer boundary.
- Live playhead and scrolling are already separate from the generation-isolated static sheet and remain app-owned.

This ticket is an ownership cutover of existing behavior, not a new notation architecture.

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
                |
                v
 DrumNotation.ResolvedNotationInput
                |
                v
   package stem groups + beam topology
  - representative selection
  - primary / secondary beams / hooks
  - one visible flag plan per stem group
                |
                v
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
          ^
          |  appearance + accessibility labels
          |
Virgo static generation wrapper
  + app-only feel/warning annotations
  + separate live playhead
  + ScrollView / auto-scroll
```

Final state has no old/new renderer toggle, no second package target, no app beam-topology copy, no app flag prepass, and no second rhythm-analysis subsystem.

## Ownership after HPA-166

| Concern | Owner | Rule |
| --- | --- | --- |
| DTX parsing, source lanes, SwiftData | Virgo | Never imported by `DrumNotation` |
| Rhythm inference / diagnostics | Virgo | Package receives resolved values only |
| Staff-position overrides | Virgo projection | Convert to package `staffStep` once |
| Localized VoiceOver copy | Virgo presentation | Passed to `DrumNotationView`; never stored in engraving geometry |
| Meter + beat-group ranges | Package input | Resolved by Virgo, consumed by package topology |
| Horizontal formatting / row packing | `DrumNotation` | Existing HPA-164 formatter remains authoritative |
| Beam/hook topology + flag coverage | `DrumNotation` | Port current proven beat-group algorithm |
| Stem/beam/flag/rest/dot/tuplet/control geometry | `DrumNotation` | One immutable engraving result |
| Staff/ledger/clef/meter/bar/static notation view | `DrumNotation` | One package view over immutable geometry |
| Feel text + rhythm warning diagnostics | Virgo | App annotations, not reusable engraving semantics |
| Tick → row/X lookup | `DrumNotation` | Package result remains the only notation position authority |
| Final notation Y / row staff centers | `DrumNotation` | App consumes package row geometry; no parallel `GameplayLayout` formula |
| Row anchors, ScrollView, auto-scroll | Virgo | Consume package row geometry |
| Live playhead | Virgo | Separate overlay using package position/row geometry |
| Preparation failure presentation | Virgo | Closed ready/failed state; failed engraving uses existing practice-unavailable UI |

The existing non-notation gameplay fallback for charts with no renderable notation is not a second notation renderer and remains app-owned.

## Minimal resolved package model

HPA-164 intentionally omitted fields not needed for horizontal formatting. HPA-166 adds only final-engraving semantics.

### Voice, meter, and beat groups

```swift
public enum NotationVoiceRole: Int, Hashable, Sendable {
    case upper
    case lower
}

public struct NotationMeter: Hashable, Sendable {
    public let beats: Int
    public let noteValue: Int
}

public struct ResolvedBeatGroup: Hashable, Sendable {
    public let startTick: Int
    public let durationTicks: Int
}
```

Extend `ResolvedMeasure` with `meter` and ordered `beatGroups`.

Validation requires groups to be positive, ordered, contiguous from tick 0, and to exactly cover `durationTicks`. The topology group ordinal is the array position; do not carry a redundant public `index` field. Do not carry `RhythmBeatGroup.isResidual`; that is analyzer diagnostic state, not engraving input.

### Notes

Final `ResolvedNote` adds:

```swift
public let voice: NotationVoiceRole
public let durationTicks: Int
public let tiebreakOrder: Int
public let isRhythmEngravable: Bool
public let articulation: PercussionArticulation?
```

Rules:

- `durationTicks` is exact timeline duration used for adjacency; never reconstruct it from `NotationDuration`.
- `tiebreakOrder` maps `DrumNotationDefinition.catalogOrder` once in `VirgoNotationProjection`; package code never receives `DrumType` or the app catalog.
- `isRhythmEngravable` is **note rhythm supported AND owning measure `engravingSupport.permitsEngraving`**.
- A head may still exist in an unsupported measure when Virgo preserves note identity; false `isRhythmEngravable` suppresses duration-bearing stems/beams/flags/dots.
- Reuse existing `PercussionArticulation`; do not add a second articulation enum.
- Localized accessibility strings do not belong on `ResolvedNote` or any geometry type.

Final state deletes public `visibleFlagDuration` and `stemMember`. Package topology owns flag coverage, and stem membership derives from `isRhythmEngravable` plus duration stem requirement.

### Rests

Extend `ResolvedRest` only with:

```swift
public let voice: NotationVoiceRole
public let durationTicks: Int
```

Hidden rests and rests from measures that do not permit engraving remain filtered at the Virgo projection boundary. The package never receives invisible spacing anchors.

### Tuplets

Represent already-resolved supported groups; do not rediscover tuplets:

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

Virgo creates groups only for tuplets the analyzer already supports. Swing/shuffle feel-pairs that should not draw a tuplet bracket are filtered at the adapter boundary rather than adding `RhythmicFeel` to the package.

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

Virgo resolves target lane/instrument semantics and user staff overrides. Package code never receives DTX lane IDs, source note IDs, target display-name models, or `DrumType`.

### Input validation

`ResolvedNotationInput` additionally owns `[ResolvedTupletGroup]` and validates:

- unique IDs within each collection;
- positive note/rest `durationTicks` contained in the owning measure;
- beat groups exactly cover each measure;
- tuplets reference existing notes/rests in the same measure/voice and have a positive ratio.

No backward-compatible package initializers are required. Every commit that changes a public package initializer also updates the single Virgo projection consumer in that same commit so the app keeps compiling.

## First-class stem groups

The existing renderer already collapses one onset/voice/direction chord into one stem group. HPA-166 makes that existing concept explicit inside the package.

```swift
struct StemGroupKey: Hashable {
    let measureIndex: Int
    let localTick: Int
    let voice: NotationVoiceRole
    let stemDirection: NotationStemDirection
}

struct StemGroup {
    let key: StemGroupKey
    let noteIDs: [Int]
    let stemRepresentativeID: Int?
    let flagRepresentativeID: Int?
}
```

`StemGroup` stays internal. Topology, stem geometry, formatter flag footprint, and final flag painting consume the same groups.

### Stem representative

Preserve the current comparator:

1. candidates require a stem and `isRhythmEngravable`;
2. sort by final staff position (`staffStep` replaces rendered Y ordering);
3. then `tiebreakOrder`;
4. then event ID;
5. up-stem takes the lowest/stem-side head; down-stem takes the highest/stem-side head.

This remains the shared, undisplaced stem axis.

### Flag representative

Preserve the current comparator:

1. most required flag levels;
2. then `tiebreakOrder`;
3. then event ID.

It decides required beam/flag levels and canonical flag family. It is intentionally distinct from the stem representative.

## Package topology and one flag plan per stem group

Port `NotationBeamTopologyBuilder` by changing ownership/types, not musical behavior.

Topology groups stem events by measure, voice, stem direction, and resolved beat-group ordinal. Pre-format row is unnecessary because HPA-164 never splits a measure across rows; after formatting, assert a beam group belongs to one row.

Preserve exact-duration adjacency and segment behavior:

- primary run needs at least two consecutive beamable stem events;
- level 0 spans the primary run;
- higher levels form full secondary segments when adjacent members share the level;
- one isolated higher level becomes a forward/backward hook using the existing neighbor/tie-break rule;
- groups never cross measure, voice, stem direction, or beat-group boundaries.

`VisibleFlagPlan` belongs to exactly one stem group:

```swift
enum VisibleFlagPlan: Hashable, Sendable {
    case none
    case canonical(NotationFlagDuration)
    case components(Set<Int>)
}
```

Rules:

- no uncovered levels → `.none`;
- all required levels uncovered → `.canonical(...)` from the flag representative;
- partially uncovered levels → `.components(uncoveredLevels)`.

The formatter reserves flag ink **once at the shared stem axis**, keyed by the stem group/stem-side representative. It never unions the same flag footprint for every chord member. Add a mandatory same-tick snare + closed-hi-hat isolated-sixteenth fixture that proves exactly one flag extent is reserved.

The final flag painter consumes the same plan/topology result. Final production cutover deletes `VirgoNotationProjection+Flags.swift` and public `visibleFlagDuration` together.

## Engraving style

Keep `NotationFormattingStyle` for horizontal formatting and add one numeric `NotationEngravingStyle`:

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
    public let flagVerticalSpacing: CGFloat
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

Use defaulted initializer arguments for package-only/ordinary-import construction, following `NotationFormattingStyle`; do **not** add a public `.standard` convenience whose only consumer is a test. Virgo explicitly maps every app scalar through `VirgoNotationProjection.engravingStyle(...)`.

Additional rules:

- `flagVerticalSpacing` maps `GameplayLayout.flagVerticalSpacing`.
- Flag stem-origin X uses `style.formatting.stemWidth`; do not duplicate stem width.
- Bravura metrics remain the authority for notehead/rest/flag/articulation bounds; do not carry legacy box sizes.

## Engraving result

Expose one immutable `EngravedNotation` containing:

- existing `FormattedNotation`;
- formatted measures and explicit row geometry;
- notes/rests/controls with final geometry and semantic source IDs;
- stems, beams, flags, ledger lines, dots, articulations, tuplets, and measure bars;
- staff-row, percussion-clef, and meter descriptors;
- `paintedBounds`, `contentWidth`, `contentHeight`;
- lookup helpers for note ID and musical tick positions.

`EngravedNotation` is pure reusable geometry/semantics. It does **not** contain localized accessibility strings.

Expose one production entry point:

```swift
public enum NotationEngraver {
    public static func engrave(
        _ input: ResolvedNotationInput,
        style: NotationEngravingStyle
    ) throws -> EngravedNotation
}
```

Virgo production code calls only `NotationEngraver.engrave`; it does not reconstruct package geometry.

## Accessibility boundary

Preserve Virgo's current instrument/rest/control/tuplet VoiceOver copy without polluting geometry values.

Add one small view-only semantic key:

```swift
public enum NotationSemanticID: Hashable, Sendable {
    case note(Int)
    case rest(Int)
    case control(Int)
    case tuplet(Int)
}
```

The package static view accepts one label map at paint time:

```swift
DrumNotationView(
    layout: engraving,
    appearance: appearance,
    accessibilityLabels: [NotationSemanticID: String]
)
```

The enum prevents collisions between the package's separate integer ID namespaces. Virgo builds the localized label map from its domain/catalog state alongside app annotations. A locale/copy change therefore updates the view without changing `EngravedNotation` identity or re-running geometry.

Decorative stems/beams/ledger lines/dots/articulations remain accessibility-hidden unless they gain an independent semantic requirement.

## Geometry rules

### Final sheet-local Y

Package output becomes authoritative in X **and** notation Y:

- each row gets one deterministic staff center from `rowHeight + rowVerticalSpacing`;
- `staffStep` changes Y by `formatting.staffSpace / 2`;
- rests use voice offsets;
- controls use target staff step + stop offset;
- ledger lines derive from final head bounds;
- stems use Bravura attachment metrics and the undisplaced stem representative.

Build raw vertical geometry, calculate painted bounds once, then normalize the complete engraving by one package-owned Y translation when raw `minY < 0`. `EngravedNotation.rows`, every primitive, `paintedBounds`, playhead row Y, and row-anchor geometry all use final normalized coordinates. `DrumNotationView` applies no hidden translation, and Virgo has no parallel notation `topContentInset` formula.

### Stems, beams, flags

- Stem starts from the stem representative's Bravura attachment anchor.
- Primary/secondary beams remain flat percussion beams unless an explicit VexFlow fixture proves otherwise.
- Stem length reaches the outermost beam stack or isolated-flag clearance plus minimum chord clearance.
- Hook geometry uses the existing neighbor direction and `beamHookLength`.
- Canonical isolated flags use duration-specific Bravura glyphs.
- Partial uncovered levels use component flag geometry with `flagVerticalSpacing`.
- Formatter-reserved flag bounds must contain final painted flag bounds.

### Rests, dots, articulations

- Printed rest X remains HPA-164 formatter output.
- Voice owns rest Y.
- Dot X uses actual final note/rest painted `maxX` + formatter dot spacing/radius.
- `.open` articulation reuses `PercussionArticulation.open` and final head bounds.
- Closed hi-hat remains an X notehead, not a new articulation.

### Controls

Stop/choke/damp remain independent control primitives. X is the formatted logical timing column, Y derives from resolved target staff step, and the existing cross-mark shape stays unless a reference fixture proves another rule.

### Tuplets

Use resolved group membership. If all members are continuously beamed and there are no rests, show label only; otherwise show bracket + label. Support only tuplets Virgo already resolves; no arbitrary/nested tuplets.

## Static package view

Add one `DrumNotationView` that consumes only:

- `EngravedNotation`;
- explicit view appearance;
- view-only accessibility label map.

It draws staff lines, ledgers, clef, meter, bars, noteheads, rests, stems, beams, flags, dots, articulations, controls, and tuplets. It observes no gameplay clock and reads no Virgo environment/theme/global layout values.

Virgo's generation-equatable static wrapper hosts this view plus app-only feel/warning annotations. The playhead remains a sibling overlay so playback does not re-run engraving.

## Regression-net migration before production cutover

This migration must not blanket-regenerate the current golden suite after the old types are deleted. The real-DTX regression net is moved **before** the production view/preparation cutover, while the current renderer still compiles.

After package engraving + static view are complete and package tests are green:

1. Extend the test fixture harness to derive `EngravedNotation` from the same real `RhythmLayoutSnapshot` in a test-only package path while the production app still uses the old `NotationLayout` path.
2. Retarget the digest to package engraving. Rename it if useful, but keep the timeline/analyzer section app-owned.
3. Serialize vertical geometry **row-relative to each row's staff center** instead of absolute sheet Y. Package Y normalization then does not cause meaningless full-golden churn.
4. Remove obsolete app `NotationLayoutStyle` box fields from the digest; serialize only enduring package style/geometry values.
5. Hidden/unprinted rests disappear from engraving digest by design; analyzer/timeline semantics remain covered by the timeline section and source tests.
6. Retarget `DrumTabRegressionInvariantTests` to package primitives/lookup while keeping the real-DTX app harness. These are integration invariants, not duplicate package-only unit tests.
7. Retarget `DrumTabRenderProbeTests` to `DrumNotationView`/`EngravedNoteHead.paintedBounds` before deleting the app painter.
8. Regenerate the golden baseline once and review every change. Expected changes are digest schema reshaping plus explicitly named engraving fixes (for example one flag footprint per stem group), not an unexplained blanket update.

From that baseline onward, later production-cutover tasks should leave geometry goldens unchanged unless a concrete bug fix names the cause. Final verification checks attribution rather than running a blanket regeneration at the end.

## Production cutover is one compile-safe task

Do not commit preparation and view cutover separately.

The same implementation task must update together:

- `GameplayNotationPreparer`;
- prepared-state shape;
- view-model installation/cache;
- `GameplayStaticNotationInput`;
- `GameplaySheetMusicView`;
- row anchors and playhead Y lookup;
- accessibility label map construction/consumption;
- app flag prepass removal;
- old static primitive wrappers after replacement tests are green.

Use a closed state:

```swift
enum GameplayNotationPreparedState: Sendable {
    case ready(EngravedNotation, GameplayNotationPresentation)
    case failed(GameplayNotationPreparationFailure)
}

struct GameplayNotationPresentation: Sendable {
    let annotations: GameplayNotationAnnotations
    let accessibilityLabels: [NotationSemanticID: String]
}
```

No both-nil/both-set state is representable.

Package validation/engraving failures must not become a successful empty sheet. Keep rhythm-analysis availability honest; store the notation-preparation failure separately in the view model and route its message through the existing practice-unavailable presentation branch. Debug may additionally assert/log. Do not add a second error screen.

## VexFlow reference policy

Keep VexFlow 5.0.0 as the semantic reference. Do not add Node/jsdom/runtime tooling by default. If one disputed beam/modifier fixture cannot be settled from pinned source/behavior, add the smallest package-local script + committed reference artifact for that fixture and make a Swift test consume it. A generator whose output no test reads is not part of this ticket.

Required high-value cases include mixed eighth/sixteenth levels, mixed sixteenth/thirty-second levels, forward/backward hooks, isolated flags both directions, dotted note/rest, supported tuplet, 6/8 grouping, simultaneous voices, stop/choke/damp near notes, and a dense multi-row passage.

## Verification boundary

Package tests own pure formatter/topology/engraving/view behavior. Virgo tests keep evidence that only the app can provide:

- real DTX → analyzer → projection → package integration;
- stable event/control identity;
- row/playhead alignment;
- generation isolation;
- golden/invariant regression net using package engraving;
- production-mounted static view;
- app accessibility copy;
- practice-unavailable failure routing.

CI already runs `swift test --package-path Packages/DrumNotation`; do not add another workflow unless that existing command disappears.

## Explicit non-goals

- no `NotationRhythmAnalyzer` rewrite unless a required fixture exposes a concrete bug;
- no arbitrary/nested tuplets;
- no pitched score, cross-staff notation, MusicXML, WebView, Canvas/Metal, virtualization, or pagination;
- no repository extraction/demo app/publication workflow;
- no backward-compatibility shim or old/new renderer toggle;
- no HPA-584 performance scope;
- no new image assets.

## Acceptance criteria

- Reusable engraving and static notation drawing live in `DrumNotation`; Virgo has no copied package-owned renderer/topology.
- Ordinary `import DrumNotation` consumer coverage constructs input → engraver → lookup → static view using the public initializer defaults, not a test-only `.standard` API.
- Package resources resolve without `AppFonts`, `Bundle.main`, Virgo test host, or repository-relative paths.
- One topology/stem-group result owns beam coverage, formatter flag footprint, and final flags; a chord reserves one shared flag footprint.
- Existing representative ordering (`staffStep`/catalog tiebreak/ID and flag-count/catalog tiebreak/ID) is preserved.
- `isRhythmEngravable` combines note support and measure engraving permission.
- `flagVerticalSpacing` is explicit package style; stem width remains formatter style.
- `EngravedNotation` owns final normalized X/Y geometry and contains no localized copy.
- Existing note/rest/control/tuplet VoiceOver labels survive through one view-only semantic label map.
- The real-DTX golden + geometric invariant suite is retargeted to `EngravedNotation` **before** production cutover, using row-relative Y; the new baseline is reviewed before old geometry types are deleted.
- `DrumTabRenderProbeTests` targets package rendering before `NotationPrimitiveViews.swift` is removed.
- Production preparation + view installation cut over in one compile-safe task using a closed ready/failed state.
- Package validation failure surfaces through existing practice-unavailable UI, never an empty successful notation state.
- Generation isolation remains; live playhead does not re-run engraving.
- Mixed beam/hook/flag/rest/dot/articulation/tuplet/control fixtures match the accepted VexFlow-referenced structure.
- Production-mounted dense/sparse notation and changed wrap widths are visually reviewed; iPad remains a build/compile gate unless a platform-specific difference appears.
- `swift test --package-path Packages/DrumNotation`, focused app integration tests, full serial macOS tests, iPad build, SwiftLint, and final ownership searches pass.

## PR boundary

**Exactly one PR for HPA-166.** The suggested midpoint merge is intentionally not taken: this project uses one ticket → one PR, and HPA-166 is already the final package ownership/parity ticket. Keep the branch draft through implementation and mark this same PR ready only after the final verification gate.