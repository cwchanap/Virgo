# HPA-166 Package Engraver and Static Renderer Design

**Issue:** HPA-166 — `[Notation] Complete reusable package renderer and VexFlow beam/modifier parity`

**Scope:** Third and final PR in the HPA-163 → HPA-164 → HPA-166 native `DrumNotation` migration. Move the remaining reusable engraving semantics and complete static notation rendering into `Packages/DrumNotation`, cut Virgo over to the package-owned layout/view, and delete the transitional app-side composition/rendering stack.

**Baseline reviewed:** `main` at `54c4513d967bb50882791bd4a5bd4627ee412f77`, immediately after HPA-164 / PR #66 merged.

## Current state

HPA-163 and HPA-164 deliberately stopped before the final renderer migration:

- `DrumNotation` owns Bravura resources, glyph metrics/primitive glyph views, exact resolved tick input, measured formatting, row packing, notehead displacement, printed-rest X placement, and authoritative tick → row/X lookup.
- `VirgoNotationProjection` maps the analyzed app snapshot into `ResolvedNotationInput` and currently performs a Virgo-side beam-topology prepass only to classify one visible flag footprint per stem group.
- `GameplayNotationPreparer` still converts `FormattedNotation` back into Virgo `Rendered*` values, then rebuilds stems, beams, flags, ledger lines, dots, articulations, controls, tuplets, bars and bounds in Virgo.
- `GameplaySheetMusicView` still owns the complete static layer stack: staff lines, bars, clefs/time signatures, app primitive wrappers, tuplets, controls and app annotations.
- The live playhead and scroll/auto-scroll orchestration are already separate from the generation-isolated static sheet and stay separate.

This ticket is therefore an ownership cutover, not another formatter or rhythm-analysis rewrite.

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
  - resolve control + articulation intent
  - map catalog-order tiebreak + accessibility copy
  - fold note + measure engraving support
  - preserve feel/warning diagnostics separately
                |
                v
 DrumNotation.ResolvedNotationInput
                |
                v
     package StemGroup construction
  measure + tick + voice + stem direction
  explicit stem/flag representatives
                |
                v
   package beam-topology prepass
  primary + secondary beams / hooks
  one VisibleFlagPlan per StemGroup
                |
                +----> formatter flag footprint
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

There is no old/new renderer toggle, no second package target, no app copy of beam topology after cutover, and no second musical timeline.

## Ownership after HPA-166

| Concern | Owner | Rule |
| --- | --- | --- |
| DTX parsing, source lanes, SwiftData | Virgo | Never imported by `DrumNotation` |
| Rhythm inference / diagnostics | Virgo | Package receives resolved values only |
| Staff-position overrides | Virgo projection | Convert to package `staffStep` once |
| Catalog-order tie break | Virgo projection → scalar | Package gets one integer, never `DrumType`/catalog types |
| Accessibility instrument/control copy | Virgo projection → optional strings | Package view exposes those labels; it does not invent app terminology |
| Meter + beat-group ranges | Package input | Resolved by Virgo, consumed by package topology |
| Horizontal formatting / row packing | `DrumNotation` | Existing HPA-164 formatter remains authoritative |
| Stem groups + representative picking | `DrumNotation` | One explicit group model shared by topology/stems/flags |
| Beam/hook topology + flag coverage | `DrumNotation` | One topology result; no app prepass remains |
| Stem/beam/flag/rest/dot/tuplet/control geometry | `DrumNotation` | One immutable engraving result |
| Staff/ledger/clef/meter/bar/static notation view | `DrumNotation` | One package view over immutable geometry |
| Feel text + rhythm-warning diagnostics | Virgo | App annotations, not reusable engraving semantics |
| Playback clock / scoring / MIDI | Virgo | Unchanged |
| Tick → row/X lookup | `DrumNotation` | Package result is the notation position authority |
| Final notation Y / row staff centers | `DrumNotation` | Virgo never recreates `GameplayLayout.StaffLinePosition` for the notation branch |
| Row anchors, ScrollView, auto-scroll | Virgo | Consume package row geometry only |
| Live playhead | Virgo | Separate overlay using package tick/row geometry |

The existing non-notation gameplay fallback for charts with no renderable notation is not a second notation renderer and remains app-owned.

## Minimal resolved package model

HPA-164 omitted fields not needed for horizontal formatting. HPA-166 adds only final engraving inputs.

### Voice, meter and beat groups

Add package-local value types; do not expose Virgo enums:

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
    public let index: Int
    public let startTick: Int
    public let durationTicks: Int
}
```

Extend `ResolvedMeasure` with `meter` and ordered `beatGroups`. Validate groups are positive, contiguous from tick 0, and exactly cover `durationTicks`. Do not carry `RhythmBeatGroup.isResidual`; topology needs ranges, not analyzer diagnostics.

### Notes

Extend `ResolvedNote` with:

```swift
public let voice: NotationVoiceRole
public let durationTicks: Int
public let tiebreakOrder: Int
public let isRhythmEngravable: Bool
public let articulation: PercussionArticulation?
public let accessibilityLabel: String?
```

Rules:

- `durationTicks` is exact timeline duration used for adjacency; do not reconstruct it from `NotationDuration`.
- `tiebreakOrder` maps `DrumNotationDefinition.catalogOrder` once in `VirgoNotationProjection`; package code never receives `DrumType` or the app catalog.
- `isRhythmEngravable` is **the AND of both current gates**: the note rhythm is supported **and** the owning measure `engravingSupport.permitsEngraving`.
- Heads may still exist in an unsupported measure when the app intentionally preserves note identity; `isRhythmEngravable == false` suppresses duration-bearing stems/beams/flags/dots.
- Reuse the package's existing `PercussionArticulation`; do not add a second articulation enum.
- `accessibilityLabel` is app copy such as instrument names. The package view paints it but does not generate Virgo-specific wording.

Delete public `visibleFlagDuration`. Once topology is package-owned, an app-supplied flag verdict would preserve the transitional duplicate source of truth.

Delete public `stemMember`; package stem membership derives from `isRhythmEngravable` + duration stem requirement.

### Rests

Extend `ResolvedRest` with:

```swift
public let voice: NotationVoiceRole
public let durationTicks: Int
public let accessibilityLabel: String?
```

Hidden rests and rests from measures that do not permit engraving remain filtered at the Virgo projection boundary, matching current behavior. The package never receives an invisible spacing anchor.

### Tuplets

Represent already-resolved supported groups directly; do not rediscover tuplets:

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
    public let accessibilityLabel: String?
}
```

`VirgoNotationProjection` creates groups only for tuplets already supported by the analyzer. Existing swing/shuffle feel-pairs that should not show a tuplet bracket are filtered at the adapter boundary rather than adding `RhythmicFeel` to the package.

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
    public let accessibilityLabel: String?
}
```

Virgo resolves target lane/instrument semantics and user staff overrides. The package never receives source lane IDs, target lane IDs, display-name models, source note IDs or `DrumType`.

### Input validation

`ResolvedNotationInput` additionally owns `[ResolvedTupletGroup]` and validates:

- unique event/group IDs within each collection;
- note/rest `durationTicks > 0` and contained in the owning measure;
- beat groups exactly cover each measure;
- tuplets reference existing notes/rests in the same measure/voice and have a positive ratio.

No backward-compatible package initializers are required. **However, every commit that changes the public package input also updates the single Virgo projection consumer in that same commit so the app continues to compile.**

## First-class stem groups

The current renderer does not beam or flag individual heads. It collapses one onset/voice/direction chord into a shared stem group. HPA-166 makes that invariant explicit inside the package.

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

`StemGroup` stays internal. Topology, stem geometry, flag coverage, formatter flag footprint and final flag painting all consume these same groups.

### Stem representative

Preserve the current deterministic comparator:

1. candidates require a stem and `isRhythmEngravable`;
2. sort by final staff position (`staffStep` replaces rendered Y ordering);
3. then `tiebreakOrder` (mapped from catalog order);
4. then event ID;
5. up-stem takes the lowest/stem-side head; down-stem takes the highest/stem-side head.

This is the shared stem axis and remains undisplaced under the HPA-164 staff-second rule.

### Flag representative

Preserve the current comparator:

1. head with most required flag levels;
2. then `tiebreakOrder`;
3. then event ID.

The flag representative decides required beam/flag levels and canonical flag family. It is intentionally distinct from the stem representative.

## Package beam topology and one flag plan per stem group

Port the current `NotationBeamTopologyBuilder` algorithm, changing types/ownership rather than musical behavior.

### Grouping and adjacency

Topology groups stem events by:

- measure;
- resolved voice;
- stem direction;
- resolved beat group.

Pre-format row is omitted because HPA-164 never splits a measure across rows. After formatting, assert every group lies in one formatted row.

Preserve exact-duration adjacency and segment behavior:

- primary run needs at least two consecutive beamable stem events;
- level 0 spans the primary run;
- higher levels form full secondary segments when adjacent members share the level;
- one isolated higher level becomes a forward/backward hook using the existing neighbor/tie-break rule;
- groups never cross measure, voice, stem direction or beat-group boundaries.

### VisibleFlagPlan

`VisibleFlagPlan` belongs to **one `StemGroup`**, never each note:

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

Store/lookup the plan by the stem-side representative/group identity. The formatter reserves flag ink **once** at the shared stem axis. It never unions the same flag footprint for every chord member.

Add a mandatory regression fixture: same-tick snare + closed hi-hat isolated sixteenths share one stem group and reserve exactly one flag extent.

The final flag painter consumes the exact same plan/topology result. `VirgoNotationProjection+Flags.swift` is then deleted.

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

Important style rules:

- `flagVerticalSpacing` maps `GameplayLayout.flagVerticalSpacing`; do not leak or hard-code the app constant inside the package.
- Flag stem-origin X uses `style.formatting.stemWidth`; do not duplicate stem width in the engraving style.
- Bravura metrics remain the authority for notehead/rest/flag/articulation bounds; do not carry legacy box sizes.
- Provide a small public `.standard` style for package-only/ordinary-import use. Virgo explicitly maps every app scalar through `VirgoNotationProjection.engravingStyle(...)` and does not rely on `.standard`.

## Engraving result

Expose one immutable `EngravedNotation` containing:

- existing `FormattedNotation`;
- formatted measures and explicit row geometry;
- notes/rests/controls with final positions, painted bounds, semantics and optional accessibility labels;
- stems, beams, flags, ledger lines, dots, articulations, tuplets and measure bars;
- row staff-line, percussion-clef and meter descriptors;
- `paintedBounds`, `contentWidth`, `contentHeight`;
- lookup helpers for note ID and musical tick positions.

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

## Geometry rules

### Final sheet-local Y

Package output becomes authoritative in X **and** notation Y:

- each row gets one deterministic staff center from `rowHeight + rowVerticalSpacing`;
- `staffStep` changes Y by `formatting.staffSpace / 2`;
- rests use voice offsets;
- controls use target staff step + stop offset;
- ledger lines derive from final head bounds;
- stems use Bravura attachment metrics and the undisplaced stem representative.

Build raw vertical geometry, calculate painted bounds once, then normalize the complete engraving by one package-owned Y translation when raw `minY < 0`. `EngravedNotation.rows`, every primitive, `paintedBounds`, playhead row Y and row-anchor geometry all use these final normalized coordinates. `DrumNotationView` applies no hidden translation, and Virgo has no parallel `topContentInset` formula for notation.

### Stems, beams and flags

- Stem starts from the stem representative's Bravura attachment anchor.
- Primary/secondary beams remain flat percussion beams unless an explicit VexFlow fixture proves otherwise.
- Stem length reaches the outermost beam stack or isolated-flag clearance plus the existing minimum chord clearance.
- Hook geometry uses the existing neighbor direction and `beamHookLength`.
- Canonical isolated flags use duration-specific Bravura glyphs.
- Partial uncovered levels use component flag geometry with `flagVerticalSpacing`.
- Formatter-reserved flag bounds must contain final painted flag bounds.

### Rests, dots and articulations

- Printed rest X remains HPA-164 formatter output.
- Voice owns rest Y.
- Dot X uses actual final note/rest painted `maxX` + formatter dot spacing/radius.
- `.open` articulation uses existing `PercussionArticulation.open` and final head bounds.
- Closed hi-hat remains an X notehead, not a new articulation.

### Controls

Stop/choke/damp remain independent control primitives:

- X is the formatted logical timing column, never a displaced head X;
- Y derives from resolved target staff step;
- keep the existing cross-mark shape in HPA-166 unless a parity fixture provides evidence for a different glyph;
- preserve app-provided accessibility copy.

### Tuplets

Use resolved group membership:

- continuously beamed group with no rests → label only;
- otherwise → bracket + label;
- label/bracket sits outside member/beam bounds in the resolved stem/voice direction;
- no arbitrary/nested tuplets.

## Static package view and accessibility

Add:

```swift
public struct NotationAppearance {
    public var foreground: Color
    public var secondaryBarOpacity: Double
}

public struct DrumNotationView: View {
    public init(
        layout: EngravedNotation,
        appearance: NotationAppearance = .standard
    )
}
```

The view draws staff lines, clef, meter, bars and every reusable engraving primitive from `EngravedNotation`. It does not read `Palette`, app environment keys, screen dimensions or gameplay clock state.

Accessibility ownership is explicit:

- Virgo projection supplies optional note/rest/control/tuplet labels using current app terminology (`Closed hi-hat`, `Choke Crash`, voice-aware rest labels, etc.).
- `EngravedNotation` preserves those strings on the corresponding primitive.
- `DrumNotationView` applies `.accessibilityLabel` to the visible semantic primitive.
- decorative stem/beam/ledger/dot/articulation layers stay hidden from accessibility unless they carry independent semantics.
- generic package wording such as `x notehead` is not a substitute for Virgo instrument labels.

This lets `NotationPrimitiveViews.swift` be deleted without regressing VoiceOver.

## Virgo integration

`GameplayNotationPreparer` remains the pure off-main preparation boundary. After cutover it does only:

```text
expand measures
-> VirgoNotationProjection.resolvedNotation
-> VirgoNotationProjection.engravingStyle
-> NotationEngraver.engrave
-> build app-only feel/warning annotations from analysis + package row/measure geometry
```

Delete `ComposedNotation`, `RebuiltArtifacts`, app X lookup dictionaries, `composeVirgoLayout`, reusable builder calls and app `Rendered*` finalization.

`GameplayStaticNotationView` stays generation-equatable. The notation branch mounts one `DrumNotationView` plus Virgo feel/warning annotations and row anchors. The live playhead stays a sibling outside the static subtree.

## Preparation failures are not an empty sheet

Current HPA-164 code catches every projection/formatter error and returns `.empty`. HPA-166 adds stricter beat-group/tuplet/duration validation, so silent blanking is no longer acceptable.

Keep failure handling small:

```swift
struct GameplayNotationPreparedState: Sendable {
    let engraving: EngravedNotation?
    let annotations: GameplayNotationAnnotations
    let failure: GameplayNotationPreparationFailure?
}
```

`GameplayNotationPreparationFailure` is one small app-owned value carrying a user-facing fallback message and diagnostic description. Projection/engraver validation errors return `.failure`, not an empty successful layout. Installation surfaces that failure through the existing `Practice unavailable` / fatal-rhythm sheet path (or an equivalent single app-owned fatal-practice state); it must not introduce a second renderer or a separate error UI.

Debug builds may additionally assert/log the invariant failure, but production remains a controlled unavailable state rather than a crash or silent empty notation.

## Reference parity

Required package fixture matrix:

1. mixed eighth/sixteenth beam levels;
2. mixed sixteenth/thirty-second levels;
3. forward hook;
4. backward hook;
5. isolated flag, stem up;
6. isolated flag, stem down;
7. same-stem chord isolated flag (one footprint/one flag group);
8. dotted note/rest;
9. triplet/tuplet bracket + no-bracket cases;
10. 6/8 resolved grouping;
11. simultaneous upper/lower voices;
12. stop/choke/damp adjacent to playable notes;
13. multi-row dense passage.

Also lock representative tie-break behavior with an equal-staff-position/equal-flag-count chord fixture using `tiebreakOrder`.

Do not add Node/jsdom/VexFlow runtime by default. If a concrete parity fixture is disputed and source/behavior is insufficient, add the smallest package-local VexFlow 5.0.0 reference script and committed artifact for that case **only when a Swift test consumes it**.

## Test ownership and migration

Package tests own pure engraving behavior:

- resolved input validation;
- stem-group construction/representative picks;
- beam topology + hooks + flag plans;
- formatter flag footprint;
- final geometry/bounds;
- flags/rests/dots/articulations/tuplets/controls;
- package raster/resource tests;
- ordinary `import DrumNotation` public consumer flow.

Virgo tests keep evidence that needs app semantics/integration:

- DTX/control import semantics;
- rhythm analyzer/projection mapping;
- real-DTX adapter → package integration;
- source event identity;
- feel/warning annotation behavior;
- generation isolation;
- row/playhead alignment;
- production mounting.

`DrumTabRenderProbeTests` must move **before** `NotationNoteHeadView`/`RenderedNoteHead` are deleted. Retarget its differential pixel evidence to `DrumNotationView`/`EngravedNoteHead.paintedBounds` (or the package notehead painter where appropriate), while `GameplaySheetMusicMountingTests` continues to prove the production sheet actually mounts the package view. Do not let the package raster test replace this integration probe by accident.

## CI and verification

Current CI already runs:

```bash
swift test --package-path Packages/DrumNotation
```

Keep that existing job; do not add another workflow unless it is removed later.

Final verification:

- independent package tests;
- focused projection/preparation/mount/playhead app tests;
- full serial macOS `VirgoTests`;
- dense + sparse real DTX at controlled widths that change wrapping;
- production-mounted macOS visual smoke;
- generic iOS/iPad simulator build;
- SwiftLint;
- ownership searches proving no package dependency leak and no superseded app renderer/topology production symbols.

No new image/art assets are required.

## Explicit non-goals

- no `NotationRhythmAnalyzer` rewrite unless a fixture proves a concrete existing correctness bug blocking accepted engraving;
- no arbitrary/nested tuplets;
- no pitched-score engraving or cross-staff notation;
- no MusicXML import/export;
- no WebView/Canvas/Metal rewrite;
- no virtualization, pagination or HPA-584 work;
- no second package target, demo app, standalone repository or publication pipeline;
- no old/new renderer toggle or backward-compatibility shim;
- no generalized VexFlow harness.

## Acceptance criteria

- All reusable engraving and static notation drawing live in `DrumNotation`.
- Virgo package projection remains the only app→package semantic seam.
- `StemGroup` is first-class internally; topology/stems/flags share it.
- `VisibleFlagPlan` is one plan per stem group and formatter flag footprint is reserved once.
- Stem/flag representative comparators preserve staff position + catalog-order tiebreak + ID behavior.
- `isRhythmEngravable` folds both note support and measure `permitsEngraving`; unsupported measures do not regain duration engraving.
- `flagVerticalSpacing` is an explicit package style scalar; stem width remains formatter-owned.
- Ordinary-import consumer coverage constructs resolved notation → `NotationEngraver` → tick/row/bounds lookup → `DrumNotationView` using `.standard`.
- Package resources resolve without Virgo/AppFonts/Bundle.main scanning.
- App accessibility labels survive the renderer cutover and are applied by `DrumNotationView`.
- Package output owns final normalized X/Y; Virgo row anchors/playhead consume that geometry without recomputation.
- Preparation validation failure surfaces through the existing fatal/practice-unavailable flow, not as an empty successful sheet.
- Every API-breaking package commit updates Virgo projection in the same commit so the app remains compilable.
- Mixed beam/hook/flag/tuplet/control fixtures match the approved VexFlow-referenced behavior.
- `DrumTabRenderProbeTests` follows package geometry/view before old app primitive wrappers are deleted.
- Production mounting, event identity and playhead alignment remain green.
- `VirgoNotationProjection+Flags.swift`, app beam topology, reusable `Rendered*` engraving builders and duplicate static notation layers are deleted after replacement coverage is green.
- Existing package CI, full serial macOS tests, mounted visual smoke and iPad build pass.

## PR boundary

**Exactly one PR for HPA-166.** Planning and implementation continue on draft PR #67. Do not split this ticket into extraction, rendering or cleanup PRs; the cutover is only complete when package ownership is singular and the transitional Virgo renderer is gone.
