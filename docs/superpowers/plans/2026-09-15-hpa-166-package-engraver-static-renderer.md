# HPA-166 Package Engraver and Static Renderer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Finish the three-PR `DrumNotation` migration by moving beam/modifier/control/tuplet engraving and the complete static notation view into the package, then delete Virgo's transitional engraving composition while preserving app-owned rhythm analysis, annotations, scrolling and live playback.

**Architecture:** Virgo continues to analyze DTX into `RhythmLayoutSnapshot`, then `VirgoNotationProjection` maps only resolved engraving semantics into package values. `DrumNotation.NotationEngraver` performs one package beam-topology prepass, feeds its visible-flag coverage into the existing measured formatter, builds all reusable engraving geometry, and returns immutable `EngravedNotation`; `DrumNotationView` paints that value. Virgo keeps only domain projection, feel/warning annotations, row anchors, scrolling and the live playhead.

**Tech Stack:** Swift 6/current repo language mode, Swift Package Manager, SwiftUI, CoreGraphics, Swift Testing, Xcode/macOS+iOS simulator builds, vendored Bravura/SMuFL resources, VexFlow 5.0.0 as a semantic reference only.

**Spec:** `docs/superpowers/specs/2026-09-15-hpa-166-package-engraver-static-renderer-design.md`

## Global Constraints

- Exactly one PR for HPA-166; implementation continues on this draft PR.
- Keep one `DrumNotation` library target and one package test target; do not split Core/UI subtargets.
- No DTX parsing, SwiftData, `RhythmLayoutSnapshot`, `DrumType`, `GameplayViewModel`, `GameplayLayout`, `Palette`, `AppFonts`, app logger, playback clock or app diagnostics inside the package.
- No old/new renderer toggle, fallback notation renderer, compatibility shim, repository-extraction harness, demo app or publication workflow.
- No backward-compatibility requirement for package initializers/types; update the single Virgo consumer in this PR.
- Preserve HPA-164 `FormattedNotation` as the horizontal authority; do not add another formatter or post-format app X transform.
- Move the proven beam grouping algorithm before changing its musical behavior; parity changes must be justified by the explicit VexFlow fixture set.
- One package topology result drives both pre-format flag footprint and post-format flag painting.
- Keep feel text and rhythm warning diagnostics in Virgo; they are app annotations, not reusable percussion engraving semantics.
- Keep `GameplayStaticNotationView` generation-isolated; live playback/playhead updates must not re-run engraving.
- Package preparation values remain `Sendable` and view-free; SwiftUI `Color` appears only at the static-view appearance boundary.
- Keep existing iOS/iPadOS 17.5 and macOS 14 deployment floors and current Swift language mode.
- App `xcodebuild` tests remain serial/non-parallel.
- Do not add VexFlow/Node as a production dependency. Add reference tooling only if a disputed fixture needs executable evidence and Swift tests consume its output.
- No new image/art assets are required.

---

## File Map

### Create in `Packages/DrumNotation/Sources/DrumNotation/Model/`

- `EngravingTypes.swift` — package voice/meter/beat-group/tuplet/control types plus immutable engraving primitives/result values.
- `EngravingStyle.swift` — `NotationEngravingStyle` and package row/staff geometry scalars.

### Modify in `Packages/DrumNotation/Sources/DrumNotation/Model/`

- `ResolvedNotation.swift` — extend measures/notes/rests/controls, remove transitional visible-flag/stem-member inputs, add tuplets and validation.

### Create in `Packages/DrumNotation/Sources/DrumNotation/Layout/`

- `BeamTopology.swift` — package-internal port of the proven beat-group topology builder.
- `NotationEngraver.swift` — single public resolved-input → immutable engraving entry point.
- `NotationEngraver+Rhythm.swift` — stems/beams/flags/rest/dot/tuplet geometry helpers if `NotationEngraver.swift` would otherwise exceed the repo's normal readable-file size.
- `NotationEngraver+Marks.swift` — articulation/control/ledger/bar/staff descriptor helpers if needed for the same reason.

### Modify in `Packages/DrumNotation/Sources/DrumNotation/Layout/`

- `NotationFormatter.swift` — accept package-derived visible-flag footprint instead of public `ResolvedNote.visibleFlagDuration`; preserve HPA-164 spacing/row behavior.
- `FormattedNotation.swift` — add only lookup conveniences needed by `EngravedNotation`; do not duplicate geometry.

### Create/modify in `Packages/DrumNotation/Sources/DrumNotation/Rendering/`

- `DrumNotationView.swift` — complete static staff/clef/meter/bar + notation layer view.
- `PrimitiveViews.swift` — keep glyph painters; add only reusable primitive painters whose geometry is now package-owned.

### Create/modify package tests

- `ResolvedNotationEngravingTests.swift`
- `BeamTopologyTests.swift`
- `NotationEngraverGeometryTests.swift`
- `NotationEngraverModifierTests.swift`
- `DrumNotationViewTests.swift`
- `PackageBoundaryTests.swift`
- existing formatter/Bravura tests where initializer changes require updates
- optional `Reference/` fixture data only if executable VexFlow evidence becomes necessary

### Modify in Virgo

- `Virgo/layout/VirgoNotationProjection.swift`
- `Virgo/layout/GameplayNotationPreparation.swift`
- `Virgo/layout/NotationLayout.swift` — shrink/delete package-owned rendering data; retain only app annotation values if still needed by call sites
- `Virgo/viewmodels/GameplayViewModel+Notation.swift`
- `Virgo/viewmodels/GameplayViewModel+VisualUpdates.swift` as required by the new prepared-state shape
- `Virgo/views/subviews/GameplaySheetMusicView.swift`
- app annotation rendering file(s), preferably `Virgo/views/GameplayNotationAnnotationViews.swift`
- affected fixture/golden/playhead/mounting tests
- `Packages/DrumNotation/README.md`
- CI workflow only if package tests are not already explicitly executed after HPA-164

### Delete after cutover

- `Virgo/layout/NotationBeamTopology.swift`
- `Virgo/layout/VirgoNotationProjection+Flags.swift`
- reusable portions of `NotationLayoutEngine+Beams.swift`, `NotationLayoutEngine+Controls.swift`, `NotationLayoutEngine+Rests.swift`, `NotationLayoutEngine+RhythmRendering.swift`
- `Virgo/views/NotationPrimitiveViews.swift` once app-only warning/feel rendering is moved out
- `GameplayNotationPreparer.composeVirgoLayout` and its package-X→Virgo-geometry lookup/rebuild/finalization helpers
- `GameplayDrumNotationView`, notation-side `GameplayBarLinesView`, and notation-side `GameplayClefsAndTimeSignaturesView`

Do not delete analyzer/timeline/import helpers or the non-notation fallback simply because they currently share these files.

---

## Task 1: Extend the resolved package input for final engraving

**Files:**
- Create: `Packages/DrumNotation/Sources/DrumNotation/Model/EngravingTypes.swift`
- Modify: `Packages/DrumNotation/Sources/DrumNotation/Model/ResolvedNotation.swift`
- Create: `Packages/DrumNotation/Tests/DrumNotationTests/ResolvedNotationEngravingTests.swift`
- Modify: existing package formatter fixtures/tests for initializer changes

**Interfaces:**
- Produces `NotationVoiceRole`, `NotationMeter`, `ResolvedBeatGroup`, `ResolvedTupletRatio`, `ResolvedTupletGroup`, `NotationControlKind`.
- `ResolvedNotationInput` remains the only public resolved document passed to formatting/engraving.
- Later tasks rely on exact duration ticks, voice, beat groups, tuplets, articulation and control target staff step.

- [ ] **Step 1: Add failing beat-group validation tests**

Use Swift Testing and prove invalid/non-contiguous groups are rejected:

```swift
@Test("beat groups must exactly cover their measure")
func beatGroupsCoverMeasure() throws {
    #expect(throws: ResolvedNotationInput.ValidationError.self) {
        try makeInput(
            measures: [
                ResolvedMeasure(
                    index: 0,
                    startTick: 0,
                    durationTicks: 1920,
                    meter: NotationMeter(beats: 4, noteValue: 4),
                    beatGroups: [
                        .init(index: 0, startTick: 0, durationTicks: 480),
                        .init(index: 1, startTick: 960, durationTicks: 480)
                    ]
                )
            ]
        )
    }
}
```

Run:

```bash
swift test --package-path Packages/DrumNotation --filter ResolvedNotationEngravingTests
```

Expected: FAIL because meter/beat-group input does not exist yet.

- [ ] **Step 2: Add the minimal package enums/values**

Implement exactly:

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

public struct ResolvedTupletRatio: Hashable, Sendable {
    public let actual: Int
    public let normal: Int
}

public enum NotationControlKind: String, Hashable, Sendable {
    case stop
    case choke
    case damp
}
```

Do not mirror app diagnostic/source enums.

- [ ] **Step 3: Change `ResolvedMeasure`**

Required fields become:

```swift
public let index: Int
public let startTick: Int
public let durationTicks: Int
public let meter: NotationMeter
public let beatGroups: [ResolvedBeatGroup]
```

Validate positive meter values, ordered positive groups, `group.startTick == previousEnd`, and final end equals `durationTicks`.

- [ ] **Step 4: Change notes/rests/controls**

`ResolvedNote` gains:

```swift
public let voice: NotationVoiceRole
public let durationTicks: Int
public let isRhythmEngravable: Bool
public let articulation: PercussionArticulation?
```

Delete `visibleFlagDuration` and `stemMember`; both become package-derived.

`ResolvedRest` gains `voice` + exact `durationTicks`.

`ResolvedControl` becomes:

```swift
public let id: Int
public let position: NotationTickPosition
public let kind: NotationControlKind
public let targetStaffStep: Int
```

- [ ] **Step 5: Add explicit resolved tuplets**

```swift
public struct ResolvedTupletGroup: Hashable, Sendable {
    public let id: Int
    public let measureIndex: Int
    public let voice: NotationVoiceRole
    public let ratio: ResolvedTupletRatio
    public let memberNoteIDs: [Int]
    public let memberRestIDs: [Int]
}
```

Add `tuplets: [ResolvedTupletGroup]` to `ResolvedNotationInput` and validate unique group IDs, positive ratios, non-empty membership, existing members, same measure and same voice.

- [ ] **Step 6: Add exact-duration containment validation**

For notes/rests, require `durationTicks > 0` and `localTick + durationTicks <= measure.durationTicks` using overflow-safe arithmetic.

- [ ] **Step 7: Update HPA-164 package fixtures without compatibility overloads**

Make existing formatter fixtures specify simple 4/4 beat groups and the new note/rest fields. Do not add deprecated/default legacy initializers only to keep tests compiling.

- [ ] **Step 8: Run package model + formatter tests**

```bash
swift test --package-path Packages/DrumNotation
```

Expected: PASS before moving topology.

- [ ] **Step 9: Commit**

```bash
git add Packages/DrumNotation/Sources/DrumNotation/Model Packages/DrumNotation/Tests/DrumNotationTests
git commit -m "feat: extend resolved notation for engraving"
```

---

## Task 2: Port beam topology and make it the single flag-coverage source

**Files:**
- Create: `Packages/DrumNotation/Sources/DrumNotation/Layout/BeamTopology.swift`
- Create: `Packages/DrumNotation/Tests/DrumNotationTests/BeamTopologyTests.swift`
- Modify: `Packages/DrumNotation/Sources/DrumNotation/Layout/NotationFormatter.swift`
- Modify: `Packages/DrumNotation/Tests/DrumNotationTests/NotationFormatterSpacingTests.swift`
- Source reference only: `Virgo/layout/NotationBeamTopology.swift`

**Interfaces:**
- Internal `BeamTopologyResult` exposes primary groups/segments and covered beam levels keyed by package stem event.
- Formatter receives an internal visible-flag classification derived from this topology; `ResolvedNote` never carries flag coverage.
- Task 3 consumes the same topology result to build actual beams/flags.

- [ ] **Step 1: Port current topology tests as red package tests**

Move the meaningful cases from `VirgoTests/NotationBeamTopologyTests.swift` into package fixtures using package note IDs/voice/measure beat groups. Start with behavior-preserving cases before adding parity cases.

Run:

```bash
swift test --package-path Packages/DrumNotation --filter BeamTopologyTests
```

Expected: FAIL because the package builder does not exist.

- [ ] **Step 2: Port the builder with package types**

Keep the current algorithm structure:

```swift
enum BeamSegmentKind: Hashable, Sendable {
    case full
    case forwardHook
    case backwardHook
}

struct BeamTopologySegment: Hashable, Sendable {
    let level: Int
    let kind: BeamSegmentKind
    let eventIndices: [Int]
    let hookNeighborIndex: Int?
}
```

Group by measure + voice + stem direction + beat-group index. Omit pre-format row from the key because measures never split across rows.

- [ ] **Step 3: Preserve exact-duration adjacency**

Use `ResolvedNote.durationTicks`; do not derive adjacency from `NotationDuration` or equal visual spacing. Keep the existing run flush semantics for boundaries/non-beamable notes.

- [ ] **Step 4: Add mixed-level and hook parity tests**

Add explicit fixtures for:

- eighth + sixteenth mixed primary/secondary membership;
- sixteenth + thirty-second levels;
- forward hook;
- backward hook;
- upper/lower voice separation;
- opposite stem-direction separation;
- 6/8 resolved beat-group boundary separation.

Name each test with the expected VexFlow 5.0.0 behavior; no executable JS harness yet.

- [ ] **Step 5: Derive flag coverage from topology**

Implement one internal helper:

```swift
func visibleFlagPlan(
    requiredLevels: Int,
    coveredLevels: Set<Int>
) -> VisibleFlagPlan
```

Behavior:

```text
uncovered empty                 -> .none
uncovered == all required       -> .canonical(note duration)
partial uncovered               -> .components(uncovered levels)
```

The formatter converts that plan to painted horizontal extents; the engraver later converts the same plan to flag primitives.

- [ ] **Step 6: Update formatter spacing tests**

Replace fixtures that injected `visibleFlagDuration` with note/beat-group documents whose topology naturally produces isolated, fully beamed and partially covered flags. Assert the same HPA-164 clearance contracts remain green.

- [ ] **Step 7: Run package tests**

```bash
swift test --package-path Packages/DrumNotation
```

Expected: PASS; HPA-164 measured widths/row packing must not drift except where prior tests were directly injecting an impossible flag state.

- [ ] **Step 8: Commit**

```bash
git add Packages/DrumNotation
git commit -m "feat: move beam topology into DrumNotation"
```

---

## Task 3: Add package engraving style, rows and final note/rest geometry

**Files:**
- Create: `Packages/DrumNotation/Sources/DrumNotation/Model/EngravingStyle.swift`
- Extend: `Packages/DrumNotation/Sources/DrumNotation/Model/EngravingTypes.swift`
- Create: `Packages/DrumNotation/Sources/DrumNotation/Layout/NotationEngraver.swift`
- Create: `Packages/DrumNotation/Tests/DrumNotationTests/NotationEngraverGeometryTests.swift`
- Reuse: `FormattedNotation.swift`, Bravura metrics

**Interfaces:**
- Public `NotationEngravingStyle` contains `formatting: NotationFormattingStyle` plus vertical/beam/mark scalars.
- Public `EngravedNotation` is the only production layout returned to Virgo.
- Public `NotationEngraver.engrave(_:style:)` is the only Virgo production entry point.

- [ ] **Step 1: Add failing style/row tests**

Pin that a two-row formatted document produces deterministic staff centers separated by `rowHeight + rowVerticalSpacing`, and `staffStep` changes Y by `formatting.staffSpace / 2`.

- [ ] **Step 2: Implement `NotationEngravingStyle`**

Use the fields from the design spec. Do not carry legacy notehead/rest box sizes, feel-mark size or warning size into the package.

Add a package-local default suitable for tests, but Virgo must map its numeric style explicitly later.

- [ ] **Step 3: Define immutable row and primitive values**

At minimum:

```swift
public struct EngravedRow: Hashable, Sendable {
    public let index: Int
    public let staffCenterY: CGFloat
    public let bounds: CGRect
}

public struct EngravedNoteHead: Hashable, Sendable {
    public let noteID: Int
    public let rowIndex: Int
    public let center: CGPoint
    public let paintedBounds: CGRect
    public let style: PercussionNoteheadStyle
    public let duration: NotationDuration
    public let stemDirection: NotationStemDirection
}
```

Define similarly focused immutable values for rest/stem/beam/flag/ledger/dot/articulation/control/tuplet/bar. Constructors may remain internal; expose read-only geometry/semantic fields needed by consumers/tests.

- [ ] **Step 4: Define `EngravedNotation`**

```swift
public struct EngravedNotation: Hashable, Sendable {
    public let formatted: FormattedNotation
    public let rows: [EngravedRow]
    public let noteHeads: [EngravedNoteHead]
    // remaining immutable primitives
    public let paintedBounds: CGRect
    public let contentWidth: CGFloat
    public let contentHeight: CGFloat
}
```

Add forwarding `position(measureIndex:localTick:)` and row lookup rather than duplicating the formatter's interpolation.

- [ ] **Step 5: Make `NotationEngraver.engrave` run topology → formatter once**

The outline is:

```swift
public static func engrave(
    _ input: ResolvedNotationInput,
    style: NotationEngravingStyle
) throws -> EngravedNotation {
    let topology = BeamTopologyBuilder.build(input)
    let formatted = try NotationFormatter.format(
        input,
        style: style.formatting,
        flagPlans: topology.visibleFlagPlans
    )
    return buildEngraving(input: input, formatted: formatted, topology: topology, style: style)
}
```

Keep formatter/topology helpers internal even if direct package tests use `@testable`.

- [ ] **Step 6: Build final head/rest positions**

Use package-formatted head/rest X, package row staff center Y, `staffStep`, voice offsets and Bravura painted bounds. Add tests proving Virgo-style staff steps and same-tick displaced seconds preserve HPA-164 X while gaining package-owned Y.

- [ ] **Step 7: Build ledger lines and dots from final painted bounds**

Ledger lines follow actual head geometry plus `ledgerLineOverhang`. Dots use actual head/rest painted `maxX` + formatting dot spacing/radius; no legacy box width.

- [ ] **Step 8: Add content bounds tests**

Assert `paintedBounds`, `contentWidth` and `contentHeight` contain every produced primitive, including top-of-staff cymbal notes and bottom voice rests. This replaces app `topContentInset`/painted-bounds recomputation.

- [ ] **Step 9: Run and commit**

```bash
swift test --package-path Packages/DrumNotation --filter NotationEngraverGeometryTests
swift test --package-path Packages/DrumNotation
git add Packages/DrumNotation
git commit -m "feat: add package engraving geometry"
```

---

## Task 4: Build stems, beams, flags and modifier/control/tuplet geometry

**Files:**
- Modify: `NotationEngraver.swift`
- Create only if needed for file size: `NotationEngraver+Rhythm.swift`, `NotationEngraver+Marks.swift`
- Create: `Packages/DrumNotation/Tests/DrumNotationTests/NotationEngraverModifierTests.swift`
- Reference current Virgo builders before deleting them

**Interfaces:**
- Consumes final heads/rests + Task 2 topology.
- Produces all reusable primitive arrays stored in `EngravedNotation`.

- [ ] **Step 1: Add stem/head attachment tests**

For up/down isolated notes and same-stem seconds, assert stem start matches Bravura attachment metrics on the undisplaced stem-side axis and never starts from the displaced sibling.

- [ ] **Step 2: Port stem/beam geometry with flat percussion policy**

Move the minimal proven calculations from `NotationLayoutEngine+Beams.swift`. Use package style values and final head metrics. Do not preserve app `Rendered*` types or `GameplayLayout` calls.

- [ ] **Step 3: Add beam-stack/hook geometry tests**

Assert:

- primary/secondary beam Y separation equals `beamLevelSpacing`;
- stem endpoint reaches the furthest required beam level plus minimum chord clearance;
- forward/backward hook start/end follow Task 2 topology;
- groups stay within one formatted row.

- [ ] **Step 4: Paint flags from the same Task 2 visible plan**

Canonical isolated flags use the duration-specific Bravura glyph. Partial uncovered levels use component eighth-flag geometry. Add a direct invariant that formatter-reserved flag bounds contain the final painted flag bounds.

- [ ] **Step 5: Port articulations**

For `ResolvedNote.articulation == .open`, position the Bravura articulation from the final notehead painted bounds and `articulationVerticalOffset`. Do not introduce new articulation kinds.

- [ ] **Step 6: Port controls**

For `.stop`, `.choke`, `.damp`, keep the existing cross-mark geometry first; preserve `kind`, ID and target staff step in the primitive. X is always the formatted logical column, never a notehead-displaced X.

Add the adjacent-control regression: one playable note and each control kind at nearby ticks remain independent and collision-free at the accepted current spacing.

- [ ] **Step 7: Port tuplets**

Use `ResolvedTupletGroup` membership and final head/rest/beam bounds. Preserve current rule:

```text
all members continuously beamed + no rests -> label only
otherwise                                  -> bracket + label
```

Add up/down, bracket/no-bracket, dotted/rest-member and triplet fixture tests. No nested/general tuplet support.

- [ ] **Step 8: Add bars/staff/clef/meter descriptors**

Derive measure bars from formatted measure bounds and final-row identity. Add row-level descriptors for the five staff lines, percussion clef and meter required by the static package view.

- [ ] **Step 9: Run package tests and commit**

```bash
swift test --package-path Packages/DrumNotation
git add Packages/DrumNotation
git commit -m "feat: complete DrumNotation engraving primitives"
```

---

## Task 5: Add the complete static `DrumNotationView` and public-consumer proof

**Files:**
- Create: `Packages/DrumNotation/Sources/DrumNotation/Rendering/DrumNotationView.swift`
- Modify: `Packages/DrumNotation/Sources/DrumNotation/Rendering/PrimitiveViews.swift`
- Create: `Packages/DrumNotation/Tests/DrumNotationTests/DrumNotationViewTests.swift`
- Modify: `Packages/DrumNotation/Tests/DrumNotationTests/PackageBoundaryTests.swift`

**Interfaces:**
- `DrumNotationView(layout:appearance:)` consumes only `EngravedNotation` + view appearance.
- `NotationAppearance` contains view-only color/opacity values; it is not passed to the engraver.

- [ ] **Step 1: Add the ordinary-import consumer test first**

Keep `PackageBoundaryTests.swift` on ordinary `import DrumNotation`, not `@testable`:

```swift
@Test("public consumer engraves and constructs the static view")
func publicConsumerFlow() throws {
    let input = try ResolvedNotationInput(/* one 4/4 measure + note */)
    let layout = try NotationEngraver.engrave(input, style: .testDefault)
    #expect(layout.position(measureIndex: 0, localTick: 0)?.rowIndex == 0)
    _ = DrumNotationView(layout: layout)
}
```

Use a public package default or explicit public style; do not expose an internal test helper just to satisfy this test.

- [ ] **Step 2: Add `NotationAppearance`**

Keep it narrow:

```swift
public struct NotationAppearance {
    public var foreground: Color
    public var secondaryBarOpacity: Double
}
```

No app `Palette` import.

- [ ] **Step 3: Move static primitive painters**

Package view renders package geometry for staff, ledger, stems, beams, flags, notes, rests, dots, articulations, controls, tuplets and bars. Reuse `GlyphFill` for Bravura glyphs.

- [ ] **Step 4: Move percussion clef and meter painting**

Port current visual behavior into package rendering without introducing a second font/resource system. Keep this as static drawing over row descriptors; no app screen-size/environment reads.

- [ ] **Step 5: Add raster/bounds coverage**

Render a focused package fixture and assert visible ink remains inside `EngravedNotation.paintedBounds` with a small anti-alias tolerance. Include one up-stem flag/beam and one control/tuplet fixture.

- [ ] **Step 6: Run package-only resource/view tests**

```bash
swift test --package-path Packages/DrumNotation
```

Verify this succeeds without `AppFonts.registerAll()`, `Bundle.main`, Virgo test host or repository-root relative resources.

- [ ] **Step 7: Commit**

```bash
git add Packages/DrumNotation
git commit -m "feat: add complete DrumNotation static view"
```

---

## Task 6: Cut Virgo projection/preparation over to `NotationEngraver`

**Files:**
- Modify: `Virgo/layout/VirgoNotationProjection.swift`
- Delete after green: `Virgo/layout/VirgoNotationProjection+Flags.swift`
- Modify: `Virgo/layout/GameplayNotationPreparation.swift`
- Modify/shrink: `Virgo/layout/NotationLayout.swift`
- Modify: focused projection/preparation tests

**Interfaces:**
- Virgo maps app semantics → `ResolvedNotationInput` + `NotationEngravingStyle` exactly once.
- `GameplayNotationPreparedState` contains package engraving + app annotations, not reconstructed reusable primitives.

- [ ] **Step 1: Add failing projection tests for the new fields**

From controlled `RhythmLayoutSnapshot` fixtures assert:

- app `.upper/.lower` maps to `NotationVoiceRole`;
- measure beat groups/meter are preserved exactly;
- note `rhythmDurationTicks` maps to exact duration ticks;
- open-hi-hat maps to `.open` articulation;
- stop/choke/damp resolve target staff step after user overrides;
- supported tuplets map stable members/ratio;
- declared swing/shuffle feel-pairs are omitted from package tuplets.

- [ ] **Step 2: Replace `formattingStyle` with one engraving-style mapper**

```swift
static func engravingStyle(
    rowWidth: CGFloat,
    style: NotationLayoutStyle
) -> NotationEngravingStyle
```

Embed the existing HPA-164 formatting values and map current row/stem/beam/rest/control/tuplet/bar/clef/meter scalars. This is the only app site constructing package style.

- [ ] **Step 3: Update resolved notation projection**

Resolve app-only semantics before crossing the boundary. Do not pass `RhythmLayoutSnapshot`, `RhythmMeasure`, `RhythmTupletID`, `NotationControlEventKind`, `DrumType` or source lane IDs into the package.

- [ ] **Step 4: Delete Virgo pre-format flag classification**

Remove calls to `visibleFlagClassifications` and delete `VirgoNotationProjection+Flags.swift`. Package topology now owns both coverage and formatter footprint.

- [ ] **Step 5: Replace transitional preparation**

Target shape:

```swift
struct GameplayNotationPreparedState: Sendable {
    let engraving: EngravedNotation
    let annotations: GameplayNotationAnnotations
}
```

`prepare(_:)` becomes:

```text
expand measures
-> project resolved package input
-> map engraving style
-> NotationEngraver.engrave
-> build only feel/warning app annotations from analysis + package measure/row bounds
```

Delete `ComposedNotation`, `RebuiltArtifacts`, X lookup dictionaries, `composeVirgoLayout`, `rebuiltArtifacts`, and `finalizationInput`.

- [ ] **Step 6: Keep app annotations explicitly app-only**

Create a tiny `GameplayNotationAnnotations` value if needed. Its contents may use package row/measure bounds, but must not contain reusable note/rest/beam/control/tuplet geometry.

- [ ] **Step 7: Run focused macOS tests**

```bash
xcodebuild test \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'platform=macOS' \
  -parallel-testing-enabled NO \
  -only-testing:VirgoTests/VirgoNotationProjectionTests \
  -only-testing:VirgoTests/GameplayNotationPreparationTests
```

If exact suite names differ, use the existing files' concrete test identifiers; do not broaden to full-suite merely to hide a focused failure.

- [ ] **Step 8: Commit**

```bash
git add Virgo/layout VirgoTests
git commit -m "refactor: consume DrumNotation engraver from Virgo"
```

---

## Task 7: Replace Virgo's static notation tree with `DrumNotationView`

**Files:**
- Modify: `Virgo/views/subviews/GameplaySheetMusicView.swift`
- Create: `Virgo/views/GameplayNotationAnnotationViews.swift`
- Delete after green: `Virgo/views/NotationPrimitiveViews.swift`
- Modify: `Virgo/viewmodels/GameplayViewModel+Notation.swift` and visual-update call sites as needed
- Modify: `VirgoTests/GameplaySheetMusicMountingTests.swift`
- Modify: `VirgoTests/DrumTabPlayheadAlignmentTests.swift`

**Interfaces:**
- `GameplayStaticNotationView` remains generation-equatable.
- The package static view receives immutable engraving; playback remains a sibling overlay.
- Row anchors consume `EngravedRow` positions rather than re-deriving row padding from noteheads.

- [ ] **Step 1: Update mounting test to demand the package view**

Assert the production static sheet uses one `DrumNotationView` and the playhead remains outside the generation-equatable static subtree. Remove assertions tied to app primitive wrappers only after the replacement test is red.

- [ ] **Step 2: Change `GameplayStaticNotationInput`**

Carry `EngravedNotation`, app annotations, generation and only the legacy non-notation fallback values still required. Derive notation content width/height from package output.

- [ ] **Step 3: Replace the notation layers**

The notation branch becomes conceptually:

```swift
ZStack(alignment: .topLeading) {
    DrumNotationView(
        layout: input.engraving,
        appearance: .init(foreground: Palette.chalk)
    )
    GameplayNotationAnnotationsView(annotations: input.annotations)
    GameplayRowAnchorColumn(rows: input.engraving.rows)
}
```

Keep the separate `GameplayPlayheadBarView` in the parent ZStack.

- [ ] **Step 4: Make row anchors use package rows**

Place invisible anchors at each `EngravedRow.bounds.minY`/row span. Delete notehead-derived top padding and `GameplayLayout` staff-center reconstruction from the notation branch.

- [ ] **Step 5: Update playhead Y alignment**

Tick X/row comes from `EngravedNotation.position`; row Y comes from `EngravedNotation.rows`. Keep clock→musical-position conversion in Virgo.

Add/adjust a playhead alignment test for multiple wrapped rows.

- [ ] **Step 6: Move only warning/feel views to the annotation file**

Preserve app text/copy/theme there. Delete `NotationPrimitiveViews.swift` after no package-owned primitive wrappers remain.

- [ ] **Step 7: Delete app static notation view types**

Remove notation-side `GameplayDrumNotationView`, package-replaced `GameplayBarLinesView`, package-replaced `GameplayClefsAndTimeSignaturesView`, and compatibility wrappers used only by obsolete primitive probes. Keep the non-notation fallback branch.

- [ ] **Step 8: Run focused mounting/playhead tests**

```bash
xcodebuild test \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'platform=macOS' \
  -parallel-testing-enabled NO \
  -only-testing:VirgoTests/GameplaySheetMusicMountingTests \
  -only-testing:VirgoTests/DrumTabPlayheadAlignmentTests
```

Expected: PASS with no playback-triggered full engraving rebuild.

- [ ] **Step 9: Commit**

```bash
git add Virgo/views Virgo/viewmodels VirgoTests
git commit -m "refactor: mount package notation view"
```

---

## Task 8: Delete app engraving implementations and migrate pure tests

**Files:**
- Delete: `Virgo/layout/NotationBeamTopology.swift`
- Reduce/delete reusable code from `NotationLayoutEngine+Beams.swift`, `NotationLayoutEngine+Controls.swift`, `NotationLayoutEngine+Rests.swift`, `NotationLayoutEngine+RhythmRendering.swift`, `NotationLayout.swift`
- Migrate/delete: `VirgoTests/NotationBeamTopologyTests.swift`, `VirgoTests/BeamHookPreservationTests.swift`, pure control/beam/tuplet geometry tests now covered by package suites
- Keep: real DTX/golden/regression/mount/playhead/source-control tests

**Interfaces:**
- No reusable engraving algorithm remains in Virgo.
- App tests remain only when they exercise analyzer/projection/integration/mounted UI behavior that package tests cannot.

- [ ] **Step 1: Search for transitional symbols before deletion**

```bash
rg 'NotationBeamTopologyBuilder|buildBeams\(|buildStems\(|buildFlags\(|buildLedgerLines\(|buildRests\(|buildStopNotes\(|buildTuplets\(|GameplayDrumNotationView|NotationNoteHeadView|NotationBeamView' Virgo VirgoTests
```

Classify each hit as package-replaced or genuinely app-owned before editing.

- [ ] **Step 2: Delete `NotationBeamTopology.swift` and app topology unit tests**

Only after `BeamTopologyTests.swift` covers the same structural cases plus HPA-166 parity fixtures.

- [ ] **Step 3: Remove package-replaced engine helpers**

Delete reusable builders/finalization fields, not unrelated rhythm-warning/feel helpers still used by `GameplayNotationAnnotations`.

If a file becomes empty or contains only one app annotation helper, move that helper to an app-appropriate file and delete the old engine extension.

- [ ] **Step 4: Shrink/delete app `NotationLayout` rendered primitive types**

Remove `RenderedNoteHead`, `RenderedRest`, `RenderedStem`, `RenderedBeam`, `RenderedFlag`, `RenderedLedgerLine`, `RenderedMeasureBar`, `RenderedRhythmDot`, `RenderedArticulation`, `RenderedStopNote`, `RenderedTuplet` after callers are gone.

Keep only app annotation/domain values that are not represented by package engraving, or relocate them to a more honest file.

- [ ] **Step 5: Preserve source-semantic tests**

Keep tests such as `ChartControlEventTests` / DTX control import tests because package controls intentionally do not own source lane semantics.

- [ ] **Step 6: Run package + focused app regression tests**

```bash
swift test --package-path Packages/DrumNotation
xcodebuild test \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'platform=macOS' \
  -parallel-testing-enabled NO \
  -only-testing:VirgoTests/DrumTabRegressionInvariantTests \
  -only-testing:VirgoTests/NotationLayoutControlRenderingTests
```

Update/delete `NotationLayoutControlRenderingTests` only if every assertion is pure package geometry; retain any app source-semantics assertion at the projection/integration layer.

- [ ] **Step 7: Re-run the transitional-symbol search**

Expected: no Virgo production hit for package-owned topology/builders/views.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "refactor: retire app engraving renderer"
```

---

## Task 9: Complete parity fixtures, real-chart evidence, docs and CI

**Files:**
- Package parity tests/reference fixture files
- `Packages/DrumNotation/README.md`
- `VirgoTests/DrumTabGoldenTests.swift`
- `VirgoTests/DrumTabRegressionInvariantTests.swift`
- `VirgoTests/DrumTabRenderProbeTests.swift`
- CI workflow only if needed to keep package tests explicit

- [ ] **Step 1: Audit the required fixture matrix**

Before adding tooling, prove package tests contain named cases for all ten HPA-166 categories:

```text
mixed 8th/16th
mixed 16th/32nd
forward hook
backward hook
isolated flag up/down
dotted note/rest
triplet/tuplet
6/8 compound grouping
simultaneous upper/lower voices
stop/choke/damp adjacent to notes
multi-row dense passage
```

(The isolated flag category contains both directions, so there are ten logical rows with eleven concrete visual cases.)

- [ ] **Step 2: Decide whether executable VexFlow evidence is actually needed**

If all structural expectations are unambiguous from pinned VexFlow 5.0.0 behavior/source, stop here: do **not** add Node tooling.

If one or more disputed fixtures remain, add the smallest package-local reference script and committed JSON for those exact cases only, pin VexFlow 5.0.0, and add a Swift test that reads/compares the artifact. The script alone is not a deliverable.

- [ ] **Step 3: Update package README**

Document the final public flow:

```swift
let input = try ResolvedNotationInput(...)
let layout = try NotationEngraver.engrave(input, style: style)
let position = layout.position(measureIndex: 0, localTick: 240)
let view = DrumNotationView(layout: layout)
```

Also document dependency direction, package-owned resources, VexFlow/Bravura reference versions, and that Virgo owns rhythm inference/playback/scrolling.

- [ ] **Step 4: Run dense + sparse real-DTX integration fixtures**

Use the existing real chart harness and one sparse fixture. Verify event identity, rows, bars, controls and playhead lookup; do not rebuild a package-only fake DTX importer.

- [ ] **Step 5: Exercise controlled wrap widths**

Run at least the 900pt floor and one narrower/wider production-supported width that changes row packing. Assert package `rows`, mounted row anchors and playhead row all agree.

- [ ] **Step 6: Regenerate goldens only after structural tests are green**

Review every changed image/value. Reject unrelated geometry churn; do not blanket-update snapshots.

- [ ] **Step 7: Verify CI explicitly runs package tests**

If current workflow already has:

```bash
swift test --package-path Packages/DrumNotation
```

leave CI unchanged. Otherwise add that command to the existing test workflow; do not create a new performance/release pipeline.

- [ ] **Step 8: Commit**

```bash
git add Packages/DrumNotation VirgoTests .github
git commit -m "test: lock DrumNotation renderer parity"
```

---

## Task 10: Final production verification and PR readiness gate

**Files:** no planned production changes; only fix defects exposed by the gate.

- [ ] **Step 1: Run package tests independently**

```bash
swift test --package-path Packages/DrumNotation
```

Expected: PASS.

- [ ] **Step 2: Run the full serial macOS suite**

```bash
xcodebuild test \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'platform=macOS' \
  -parallel-testing-enabled NO
```

Expected: PASS.

- [ ] **Step 3: Run the mounted macOS visual smoke**

Use the production gameplay sheet for:

- one dense real DTX;
- one sparse chart;
- at least two widths with different wrapping.

Capture review evidence for notehead/stem attachment, beam/hook direction, dots/rests/tuplets, control marks, bar/clef/meter alignment, collisions/clipping and playhead alignment.

- [ ] **Step 4: Run the iPad compile gate**

```bash
xcodebuild build \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO
```

Expected: BUILD SUCCEEDED. Add an iPad-specific visual baseline only if a platform-specific rendering difference is actually found.

- [ ] **Step 5: Run lint**

Use the repository's existing SwiftLint command/workflow. Fix only HPA-166-touched violations; no unrelated cleanup.

- [ ] **Step 6: Run final ownership searches**

```bash
rg 'import (Virgo|SwiftData)|GameplayLayout|Palette|AppFonts|RhythmLayoutSnapshot|DrumType' Packages/DrumNotation/Sources
rg 'NotationBeamTopologyBuilder|GameplayDrumNotationView|NotationNoteHeadView|NotationBeamView' Virgo
```

Expected:

- first command has no app dependency leaks;
- second has no superseded renderer/topology production symbols.

- [ ] **Step 7: Self-review the PR against HPA-166**

Check each acceptance criterion directly:

- reusable engraving/static drawing package-owned;
- ordinary-import consumer test;
- package resources independent;
- static generation isolation preserved;
- app transitional geometry removed;
- mixed beam/hook fixtures correct;
- stem/head attachment correct;
- flags/rests/dots/articulations/tuplets/controls covered;
- real mounted visual smoke + iPad build green;
- no fallback/compatibility path or unrelated HPA-584 work.

- [ ] **Step 8: Mark this same PR ready only after all gates pass**

Do not open a second implementation PR for HPA-166.
