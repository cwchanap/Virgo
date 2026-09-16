# HPA-166 Package Engraver and Static Renderer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Finish the three-PR `DrumNotation` migration by moving shared stem-group/beam/modifier/control/tuplet engraving and the complete static notation view into the package, then delete Virgo's transitional engraving composition while preserving app-owned rhythm analysis, accessibility copy, annotations, scrolling and live playback.

**Architecture:** Virgo continues to analyze DTX into `RhythmLayoutSnapshot`, then `VirgoNotationProjection` maps only resolved engraving semantics into package values. `DrumNotation.NotationEngraver` constructs first-class stem groups, runs the ported beam topology once, uses one `VisibleFlagPlan` per stem group for both formatter footprint and final flags, builds immutable final X/Y geometry, and returns `EngravedNotation`; `DrumNotationView` paints that value. Virgo keeps DTX/rhythm inference, feel/warning annotations, row anchors/scrolling, the live playhead, and app-specific accessibility strings.

**Tech Stack:** Swift Package Manager, SwiftUI, CoreGraphics, Swift Testing, Xcode macOS/iOS simulator builds, vendored Bravura/SMuFL resources, VexFlow 5.0.0 as semantic reference only.

**Spec:** `docs/superpowers/specs/2026-09-15-hpa-166-package-engraver-static-renderer-design.md`

## Global Constraints

- Exactly one PR for HPA-166; implementation continues on draft PR #67.
- Keep one `DrumNotation` library target and one package test target; no Core/UI split.
- No DTX parsing, SwiftData, `RhythmLayoutSnapshot`, `DrumType`, `GameplayViewModel`, `GameplayLayout`, `Palette`, `AppFonts`, app logger, playback clock or app diagnostics inside the package.
- No old/new renderer toggle, fallback notation renderer, compatibility shim, repository-extraction harness, demo app or publication workflow.
- No backward-compatibility requirement for package initializers/types; update the single Virgo consumer in the **same commit** as every package API change so the app remains compilable.
- Preserve HPA-164 `FormattedNotation` as the horizontal authority; do not add another formatter or post-format app X transform.
- Port the proven beam grouping/representative rules before changing musical behavior; parity changes require explicit VexFlow fixture evidence.
- `StemGroup` is first-class inside the package. Topology, stems, flags and formatter flag footprint consume the same groups.
- Exactly one `VisibleFlagPlan` belongs to one stem group; never reserve/paint a copy per chord member.
- `tiebreakOrder` maps the current `DrumNotationDefinition.catalogOrder`; do not silently replace existing representative comparators.
- `isRhythmEngravable` is note support **AND** owning measure `engravingSupport.permitsEngraving`.
- Reuse existing package `PercussionArticulation`; do not add a duplicate articulation enum.
- `flagVerticalSpacing` is an explicit engraving-style scalar. Stem width remains `NotationFormattingStyle.stemWidth`.
- Feel text and rhythm-warning diagnostics remain Virgo annotations.
- App-specific VoiceOver strings cross as optional scalar labels and are applied by the package view.
- Keep `GameplayStaticNotationView` generation-isolated; live playback/playhead updates must not re-run engraving.
- Package preparation values remain `Sendable` and view-free; SwiftUI `Color` appears only at the view appearance boundary.
- Package output owns final normalized X/Y. Virgo row anchors and playhead consume package geometry rather than recreating staff/top-inset math.
- Projection/engraver validation failures must not return a successful empty sheet; route them to the existing practice-unavailable/fatal flow.
- Existing CI already runs `swift test --package-path Packages/DrumNotation`; do not add another workflow unless that step disappears.
- App `xcodebuild` tests remain serial/non-parallel.
- Do not add Node/VexFlow as a production dependency. Add executable reference tooling only if one disputed fixture needs it and a Swift test consumes its artifact.
- No new image/art assets are required.

---

## File Map

### Package: create/extend

- Modify: `Packages/DrumNotation/Sources/DrumNotation/Model/ResolvedNotation.swift`
- Modify: `Packages/DrumNotation/Sources/DrumNotation/Model/PrimitiveTypes.swift` only where existing package types need conformance/API; reuse `PercussionArticulation`
- Create: `Packages/DrumNotation/Sources/DrumNotation/Model/EngravingStyle.swift`
- Create: `Packages/DrumNotation/Sources/DrumNotation/Model/EngravingTypes.swift`
- Create: `Packages/DrumNotation/Sources/DrumNotation/Layout/BeamTopology.swift`
- Modify: `Packages/DrumNotation/Sources/DrumNotation/Layout/NotationFormatter.swift`
- Create: `Packages/DrumNotation/Sources/DrumNotation/Layout/NotationEngraver.swift`
- Split `NotationEngraver+Rhythm.swift` / `NotationEngraver+Marks.swift` only if file-size/readability actually requires it
- Create: `Packages/DrumNotation/Sources/DrumNotation/Rendering/DrumNotationView.swift`
- Modify: `Packages/DrumNotation/Sources/DrumNotation/Rendering/PrimitiveViews.swift`
- Modify: `Packages/DrumNotation/README.md`

### Package tests

- Create: `StemGroupTests.swift`
- Create: `BeamTopologyTests.swift`
- Modify/add formatter flag-footprint tests in existing formatter suites
- Create: `NotationEngraverGeometryTests.swift`
- Create: `NotationEngraverModifierTests.swift`
- Create: `DrumNotationViewTests.swift`
- Modify: `PackageBoundaryTests.swift`

### Virgo integration

- Modify throughout API changes: `Virgo/layout/VirgoNotationProjection.swift`
- Delete after package topology is green: `Virgo/layout/VirgoNotationProjection+Flags.swift`
- Modify: `Virgo/layout/GameplayNotationPreparation.swift`
- Modify/shrink: `Virgo/layout/NotationLayout.swift`
- Modify: `Virgo/views/subviews/GameplaySheetMusicView.swift`
- Create: `Virgo/views/GameplayNotationAnnotationViews.swift` if moving feel/warning UI keeps the sheet readable
- Modify: view-model notation installation/playhead files that currently store/consume `NotationLayout`

### Delete after replacement coverage

- `Virgo/layout/NotationBeamTopology.swift`
- reusable portions of `NotationLayoutEngine+Beams.swift`
- reusable portions of `NotationLayoutEngine+Controls.swift`
- reusable portions of `NotationLayoutEngine+Rests.swift`
- reusable portions of `NotationLayoutEngine+RhythmRendering.swift`
- `Virgo/views/NotationPrimitiveViews.swift`
- app `Rendered*` engraving values whose callers are gone
- pure app topology/geometry tests duplicated by package tests

---

## Task 1: Extend the resolved model without breaking Virgo

**Files:**
- Modify package `ResolvedNotation.swift`
- Modify `Virgo/layout/VirgoNotationProjection.swift` in the same commit
- Modify package fixtures/tests
- Modify focused Virgo projection tests

**Interfaces produced:**

```swift
public enum NotationVoiceRole: Int, Hashable, Sendable { case upper, lower }

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

Extend `ResolvedNote` with:

```swift
voice: NotationVoiceRole
durationTicks: Int
tiebreakOrder: Int
isRhythmEngravable: Bool
articulation: PercussionArticulation?
accessibilityLabel: String?
```

Extend `ResolvedRest` with `voice`, `durationTicks`, `accessibilityLabel`. Extend `ResolvedControl` with package-local stop/choke/damp kind, resolved target staff step and accessibility label. Add resolved tuplet groups/ratios.

- [ ] **Step 1: Write package validation tests first**

Cover:

- 4/4 ordered beat groups exactly cover measure duration;
- 6/8 resolved groups preserve caller ranges;
- invalid gap/overlap/zero-length group rejects;
- note/rest duration must be positive and contained in measure;
- tuplet members must exist in same measure/voice;
- package model remains `Sendable`.

- [ ] **Step 2: Add projection tests before changing package initializers**

Pin current app semantics:

```text
NotationVoice.upper/lower -> package upper/lower
TimeSignature -> NotationMeter
RhythmBeatGroup ranges -> ResolvedBeatGroup (drop isResidual)
rhythmDurationTicks -> exact durationTicks
DrumNotationDefinition.catalogOrder -> tiebreakOrder
open-hi-hat -> existing PercussionArticulation.open
```

Add the two engraving gates explicitly:

```swift
expected.isRhythmEngravable = note.rhythm.support == .supported
    && owningMeasure.engravingSupport.permitsEngraving
```

Use an unsupported-measure fixture whose head still projects, but `isRhythmEngravable == false`.

- [ ] **Step 3: Pin accessibility mapping**

Projection tests require the existing app labels for representative cases:

```text
Closed hi-hat
Open hi-hat
Pedal hi-hat
Upper voice quarter rest
Lower voice full-measure rest
Choke Crash
```

The package stores strings only; do not move localized/catalog wording into the package.

- [ ] **Step 4: Implement package model + Virgo projection together**

Update package initializers and `VirgoNotationProjection.resolvedNotation(...)` in the same commit. Reuse `PercussionArticulation`; do not create `NotationArticulationKind`.

Keep hidden/unsupported rests filtered in Virgo.

- [ ] **Step 5: Add tuplet projection**

Map only analyzer-supported tuplets. Use deterministic adapter-local integer group IDs. Apply the existing swing/shuffle declared-feel-pair suppression before crossing the package boundary.

- [ ] **Step 6: Run package + focused projection tests**

```bash
swift test --package-path Packages/DrumNotation
xcodebuild test \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'platform=macOS' \
  -parallel-testing-enabled NO \
  -only-testing:VirgoTests/VirgoNotationProjectionTests
```

If the concrete suite name differs, use the exact existing test identifier from the projection test file.

- [ ] **Step 7: Verify the app still compiles**

```bash
xcodebuild build \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO
```

- [ ] **Step 8: Commit**

```bash
git add Packages/DrumNotation Virgo/layout/VirgoNotationProjection.swift VirgoTests
git commit -m "feat: extend resolved notation engraving input"
```

---

## Task 2: Port first-class stem groups and beam topology

**Files:**
- Create package `Layout/BeamTopology.swift`
- Modify formatter API/tests as needed for group-level flag plans
- Keep `VirgoNotationProjection+Flags.swift` temporarily until package behavior is proven

**Interfaces produced:**

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

Internal `BeamTopologyResult` contains groups/segments/coverage plus one `VisibleFlagPlan` per stem group.

- [ ] **Step 1: Port representative tests before topology**

Add a controlled chord fixture proving stem representative order:

```text
needs stem + engravable only
staffStep first
tiebreakOrder second
id third
up stem chooses stem-side low head
down stem chooses stem-side high head
```

Add a separate flag representative fixture:

```text
most flag levels first
tiebreakOrder second
id third
```

Do not merge these two comparator concepts.

- [ ] **Step 2: Add the one-flag-per-stem-group regression**

Construct same-tick snare + closed hi-hat isolated sixteenths in one upper/up stem group. Assert:

- exactly one `StemGroup`;
- one stem representative;
- one flag representative;
- one `VisibleFlagPlan`;
- formatter reserves one flag footprint, not two note-level footprints.

This must be green before the Virgo flag prepass is deleted.

- [ ] **Step 3: Port topology structurally**

Reuse current primary-run, secondary-level and hook-neighbor logic. Group by measure + voice + stem direction + resolved beat-group index. Do not include pre-format row; assert post-format that one group does not cross rows.

- [ ] **Step 4: Preserve exact-duration adjacency**

Use `ResolvedNote.durationTicks`; do not derive adjacency from `NotationDuration` or rendered spacing. `isRhythmEngravable == false` creates a boundary/non-beamable event.

- [ ] **Step 5: Add parity tests**

Cover:

- mixed eighth/sixteenth;
- mixed sixteenth/thirty-second;
- forward hook;
- backward hook;
- upper/lower voice separation;
- opposite stem-direction separation;
- 6/8 beat-group boundary separation;
- unsupported measure produces no duration-bearing beam/flag event.

- [ ] **Step 6: Define one group-level flag plan**

```swift
enum VisibleFlagPlan: Hashable, Sendable {
    case none
    case canonical(NotationFlagDuration)
    case components(Set<Int>)
}
```

Derive it once from topology coverage + flag representative. Key it by the stem group/stem representative identity.

- [ ] **Step 7: Change formatter footprint to consume flag plans**

Stop reading public `ResolvedNote.visibleFlagDuration`. For each column/stem group, reserve the plan exactly once at the shared stem axis.

Update HPA-164 formatter tests so isolated/full-beam/partial-beam cases arise from real package topology instead of manually stamping note-level flag state.

- [ ] **Step 8: Compare package classification with the still-existing Virgo prepass**

For representative fixtures, assert the package plan produces the same effective canonical/component footprint as `visibleFlagClassifications` today. This is the deletion gate, not permanent duplicate behavior.

- [ ] **Step 9: Run and commit**

```bash
swift test --package-path Packages/DrumNotation
xcodebuild build \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO
git add Packages/DrumNotation
git commit -m "feat: move stem groups and beam topology into DrumNotation"
```

---

## Task 3: Add engraving style and final package X/Y geometry

**Files:**
- Create `Model/EngravingStyle.swift`
- Create `Model/EngravingTypes.swift`
- Create `Layout/NotationEngraver.swift`
- Create `NotationEngraverGeometryTests.swift`

**Interfaces:**

`NotationEngravingStyle` contains the existing HPA-164 formatting style plus row/stem/beam/flag/rest/control/tuplet/bar/clef/meter scalars. It **must** include:

```swift
public let flagVerticalSpacing: CGFloat
```

It must **not** duplicate `stemWidth`; use `style.formatting.stemWidth`.

Add public `.standard` for ordinary package use; Virgo will map explicitly later.

- [ ] **Step 1: Add style contract tests**

Pin `.standard` as a complete usable package value. Add a focused assertion that partial flag levels use `flagVerticalSpacing` and flag stem-origin X uses `formatting.stemWidth / 2`.

- [ ] **Step 2: Define immutable engraving primitives**

At minimum define focused read-only package values for rows, heads, rests, stems, beams, flags, ledger lines, dots, articulations, controls, tuplets, measure bars, clef/meter descriptors.

Semantic primitives that currently expose app accessibility must carry `String?` labels:

```text
EngravedNoteHead.accessibilityLabel
EngravedRest.accessibilityLabel
EngravedControl.accessibilityLabel
EngravedTuplet.accessibilityLabel
```

Decorative primitives do not invent labels.

- [ ] **Step 3: Define `EngravedNotation`**

```swift
public struct EngravedNotation: Hashable, Sendable {
    public let formatted: FormattedNotation
    public let rows: [EngravedRow]
    // immutable primitive arrays
    public let paintedBounds: CGRect
    public let contentWidth: CGFloat
    public let contentHeight: CGFloat
}
```

Forward `position(measureIndex:localTick:)` to `formatted`; do not duplicate interpolation.

- [ ] **Step 4: Make `NotationEngraver.engrave` run topology → formatter once**

```swift
public static func engrave(
    _ input: ResolvedNotationInput,
    style: NotationEngravingStyle
) throws -> EngravedNotation {
    let stemGroups = StemGroupBuilder.build(input)
    let topology = BeamTopologyBuilder.build(input: input, stemGroups: stemGroups)
    let formatted = try NotationFormatter.format(
        input,
        style: style.formatting,
        flagPlans: topology.visibleFlagPlans
    )
    return buildEngraving(
        input: input,
        stemGroups: stemGroups,
        topology: topology,
        formatted: formatted,
        style: style
    )
}
```

Keep helpers internal.

- [ ] **Step 5: Build final note/rest positions**

Use package formatted X, row staff center, `staffStep`, voice offsets and Bravura painted bounds. Preserve HPA-164 displaced-head X exactly.

- [ ] **Step 6: Build ledger lines and dots from final bounds**

Ledger lines use final head bounds + `ledgerLineOverhang`. Dots use actual note/rest painted `maxX` + formatter dot spacing/radius.

Do not create dots for `isRhythmEngravable == false` notes.

- [ ] **Step 7: Normalize Y once**

Build raw geometry, calculate raw painted bounds, then translate all rows/primitives by `max(0, -rawBounds.minY)`. Assert final `paintedBounds.minY >= 0` and that row geometry/playhead row Y sees the same normalized coordinate system.

- [ ] **Step 8: Add content-bounds tests**

Every primitive must fit within final painted/content bounds, including high cymbal notes and lower-voice rests.

- [ ] **Step 9: Run and commit**

```bash
swift test --package-path Packages/DrumNotation
xcodebuild build \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO
git add Packages/DrumNotation
git commit -m "feat: add package engraving geometry"
```

---

## Task 4: Build stems, beams, flags and final modifiers

**Files:**
- Modify `NotationEngraver.swift`
- Split rhythm/marks helpers only if readability requires it
- Create `NotationEngraverModifierTests.swift`
- Reference current Virgo builders before deleting them

- [ ] **Step 1: Add stem attachment tests**

For up/down isolated notes and same-stem seconds, assert stem start uses the `StemGroup.stemRepresentativeID` Bravura attachment. A displaced sibling must never become the shared stem axis accidentally.

- [ ] **Step 2: Port stem/beam geometry**

Move the minimal proven calculations from `NotationLayoutEngine+Beams.swift`. Keep flat percussion beam policy and current hook-length behavior.

- [ ] **Step 3: Test beam stacks/hooks**

Assert primary/secondary level spacing, stem endpoint to outermost level, hook direction/length, and one formatted-row invariant.

- [ ] **Step 4: Paint flags from the same group plan**

Canonical isolated plan → one duration-specific Bravura flag at the shared stem axis.

Partial plan → one component flag per uncovered level, vertically separated by `style.flagVerticalSpacing`.

Assert formatter-reserved flag bounds contain the final painted flag bounds.

- [ ] **Step 5: Port articulations using existing enum**

`ResolvedNote.articulation == .open` produces the package open articulation from final notehead bounds. No second articulation type.

- [ ] **Step 6: Port controls**

For stop/choke/damp, preserve the current cross-mark geometry initially. X is `logicalColumnX`; Y is resolved target staff step + style offset. Preserve control kind/ID/accessibility label.

Add adjacent note + stop/choke/damp coverage.

- [ ] **Step 7: Port tuplets**

Preserve current rule:

```text
all members continuously beamed + no rests -> label only
otherwise                                  -> bracket + label
```

Cover up/down, bracket/no-bracket, dotted/rest member and triplet cases. Preserve tuplet accessibility label.

- [ ] **Step 8: Add staff/bar/clef/meter descriptors**

Derive bars from formatted measure bounds and row identity. Create package row descriptors for five staff lines, percussion clef and resolved meter.

- [ ] **Step 9: Run package tests and commit**

```bash
swift test --package-path Packages/DrumNotation
xcodebuild build \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO
git add Packages/DrumNotation
git commit -m "feat: complete DrumNotation engraving primitives"
```

---

## Task 5: Add `DrumNotationView` and prove the public boundary

**Files:**
- Create `Rendering/DrumNotationView.swift`
- Modify `Rendering/PrimitiveViews.swift`
- Create `DrumNotationViewTests.swift`
- Modify `PackageBoundaryTests.swift`

**Interfaces:**

```swift
public struct NotationAppearance {
    public var foreground: Color
    public var secondaryBarOpacity: Double
    public static let standard: NotationAppearance
}

public struct DrumNotationView: View {
    public init(
        layout: EngravedNotation,
        appearance: NotationAppearance = .standard
    )
}
```

- [ ] **Step 1: Add ordinary-import consumer test first**

`PackageBoundaryTests.swift` remains ordinary `import DrumNotation`, not `@testable`:

```swift
@Test("public consumer engraves and constructs the static view")
func publicConsumerFlow() throws {
    let input = try ResolvedNotationInput(/* explicit one-measure values */)
    let layout = try NotationEngraver.engrave(input, style: .standard)
    #expect(layout.position(measureIndex: 0, localTick: 0)?.rowIndex == 0)
    _ = DrumNotationView(layout: layout)
}
```

Use the public `.standard`; do not expose a test-only default.

- [ ] **Step 2: Paint all reusable package geometry**

Render staff, ledger, stems, beams, flags, notes, rests, dots, articulations, controls, tuplets, bars, clef and meter. Reuse package `GlyphFill` for Bravura glyphs.

- [ ] **Step 3: Preserve accessibility**

Apply app-provided labels to notes/rests/controls/tuplets. Hide decorative stems/beams/ledger/dots/articulations from accessibility unless a future semantic requirement exists.

Add a package-view accessibility construction test verifying labels remain attached to the correct semantic primitive values.

- [ ] **Step 4: Add raster/bounds tests**

Render focused package fixtures and assert visible ink remains inside final `paintedBounds` with small anti-alias tolerance. Include:

- notehead + stem/flag;
- beamed run;
- control + tuplet.

- [ ] **Step 5: Verify package resources are independent**

```bash
swift test --package-path Packages/DrumNotation
```

No `AppFonts.registerAll()`, `Bundle.main`, Virgo test host or repository-root resource lookup.

- [ ] **Step 6: Commit**

```bash
git add Packages/DrumNotation
git commit -m "feat: add complete DrumNotation static view"
```

---

## Task 6: Cut Virgo preparation over and make failures explicit

**Files:**
- Modify `Virgo/layout/VirgoNotationProjection.swift`
- Delete after parity gate: `Virgo/layout/VirgoNotationProjection+Flags.swift`
- Modify `Virgo/layout/GameplayNotationPreparation.swift`
- Modify/shrink `Virgo/layout/NotationLayout.swift`
- Modify view-model notation installation state/tests

- [ ] **Step 1: Add engraving-style mapper tests**

Replace formatter-only app mapping with:

```swift
static func engravingStyle(
    rowWidth: CGFloat,
    style: NotationLayoutStyle
) -> NotationEngravingStyle
```

Assert it maps existing HPA-164 values plus row/stem/beam/rest/control/tuplet/bar/clef/meter values and specifically:

```text
flagVerticalSpacing = GameplayLayout.flagVerticalSpacing
formatting.stemWidth = existing stem width
```

Do not add duplicate `stemWidth` to `NotationEngravingStyle`.

- [ ] **Step 2: Switch production preparation to `NotationEngraver`**

Target shape:

```swift
struct GameplayNotationPreparedState: Sendable {
    let engraving: EngravedNotation?
    let annotations: GameplayNotationAnnotations
    let failure: GameplayNotationPreparationFailure?
}
```

Success path:

```text
expanded measures
-> resolvedNotation
-> engravingStyle
-> NotationEngraver.engrave
-> app-only feel/warning annotations
```

Delete `ComposedNotation`, `RebuiltArtifacts`, package-X lookup maps, `composeVirgoLayout`, `rebuiltArtifacts` and reusable finalization.

- [ ] **Step 3: Make validation failures loud but simple**

Write a failing preparation test that injects invalid resolved beat-group/duration data and currently would produce an empty layout.

Implement one app-owned `GameplayNotationPreparationFailure` with:

- diagnostic text for logs/tests;
- one user-facing practice-unavailable message.

The preparer returns failure instead of `.empty`. Installation routes it to the existing fatal/practice-unavailable presentation state. Do not add a second error screen or renderer.

Debug may assert/log; production must not silently show blank notation.

- [ ] **Step 4: Delete the Virgo flag prepass**

After Task 2 parity tests are green and production uses `NotationEngraver`, remove `visibleFlagClassifications` and delete `VirgoNotationProjection+Flags.swift`.

- [ ] **Step 5: Keep feel/warning annotations app-owned**

Create `GameplayNotationAnnotations` only if needed. It may consume package measure/row bounds but contains no reusable note/rest/beam/control/tuplet geometry.

- [ ] **Step 6: Run focused tests**

```bash
swift test --package-path Packages/DrumNotation
xcodebuild test \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'platform=macOS' \
  -parallel-testing-enabled NO \
  -only-testing:VirgoTests/GameplayNotationPreparationTests \
  -only-testing:VirgoTests/GameplayNotationInstallationTests
```

Also run the concrete projection suite used in Task 1.

- [ ] **Step 7: Commit**

```bash
git add -A Packages/DrumNotation Virgo/layout Virgo/viewmodels VirgoTests
git commit -m "refactor: consume DrumNotation engraver from Virgo"
```

---

## Task 7: Retarget the render probe, then replace the production static tree

**Files:**
- Modify `VirgoTests/DrumTabRenderProbeTests.swift`
- Modify `Virgo/views/subviews/GameplaySheetMusicView.swift`
- Create `Virgo/views/GameplayNotationAnnotationViews.swift` if needed
- Modify `GameplaySheetMusicMountingTests.swift`
- Modify `DrumTabPlayheadAlignmentTests.swift`
- Do **not** delete `NotationPrimitiveViews.swift` until the new probe and mounting tests are green

- [ ] **Step 1: Retarget `DrumTabRenderProbeTests` before deleting old painters**

Replace the `NotationNoteHeadView` / `RenderedNoteHead.paintedBounds` differential with package evidence:

- render `DrumNotationView` (or the package head painter for the per-head isolation arm);
- sample `EngravedNoteHead.paintedBounds`;
- keep the current differential claim that actual head ink appears inside its own bounds.

Preserve the suite's documented boundary: this is rendering evidence, not the production-mounting claim.

- [ ] **Step 2: Add/adjust production mounting test**

`GameplaySheetMusicMountingTests` must fail if the mounted notation branch does not host `DrumNotationView`. It separately proves the production sheet mounts the package view; do not expect the raster probe to prove this.

- [ ] **Step 3: Change static input**

Carry `EngravedNotation`, app annotations, generation and only non-notation fallback values still required. Derive notation width/height from package output.

- [ ] **Step 4: Replace notation layers**

Conceptual notation branch:

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

The live `GameplayPlayheadBarView` remains a sibling outside the generation-equatable static subtree.

- [ ] **Step 5: Make row anchors/playhead consume final package Y**

Delete notation-branch notehead-derived top padding and `GameplayLayout.StaffLinePosition` recomputation. Use normalized `EngravedRow` geometry for anchors and playhead row Y.

Add wrapped multi-row playhead alignment coverage.

- [ ] **Step 6: Keep only app annotations in Virgo**

Move feel/warning text views if necessary. Preserve their copy/theme/accessibility behavior.

- [ ] **Step 7: Run probe + mounting + playhead tests**

```bash
xcodebuild test \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'platform=macOS' \
  -parallel-testing-enabled NO \
  -only-testing:VirgoTests/DrumTabRenderProbeTests \
  -only-testing:VirgoTests/GameplaySheetMusicMountingTests \
  -only-testing:VirgoTests/DrumTabPlayheadAlignmentTests
```

- [ ] **Step 8: Only now delete app primitive/static notation wrappers**

Delete `NotationPrimitiveViews.swift`, `GameplayDrumNotationView`, package-replaced bar/clef/staff views and compatibility wrappers only after Step 7 is green.

- [ ] **Step 9: Commit**

```bash
git add -A Virgo/views VirgoTests
git commit -m "refactor: mount package notation view"
```

---

## Task 8: Delete app engraving implementations and migrate pure tests

**Files:**
- Delete `Virgo/layout/NotationBeamTopology.swift`
- Reduce/delete reusable code from engine extensions and `NotationLayout.swift`
- Migrate/delete pure topology/control/beam/tuplet tests now owned by package
- Keep real-DTX, projection, source-semantic, mounted UI and playhead tests

- [ ] **Step 1: Inventory transitional symbols**

```bash
rg 'NotationBeamTopologyBuilder|buildBeams\(|buildStems\(|buildFlags\(|buildLedgerLines\(|buildRests\(|buildStopNotes\(|buildTuplets\(|GameplayDrumNotationView|NotationNoteHeadView|NotationBeamView' Virgo VirgoTests
```

Classify each hit before deleting anything.

- [ ] **Step 2: Delete topology after package replacement coverage**

Delete `NotationBeamTopology.swift` and app topology tests only after `BeamTopologyTests.swift` covers the existing behavior plus HPA-166 fixtures.

- [ ] **Step 3: Remove reusable engine helpers/finalization**

Remove stems/beams/flags/ledger/rest/control/tuplet/bounds construction now owned by the package. Relocate any remaining feel/warning annotation helper to an app-appropriate file rather than leaving a misleading engine extension.

- [ ] **Step 4: Remove obsolete app `Rendered*` values**

Delete note/rest/stem/beam/flag/ledger/bar/dot/articulation/control/tuplet render types after callers are gone. Keep only actual app annotation/domain values.

- [ ] **Step 5: Preserve source-semantic tests**

Keep `ChartControlEventTests`, DTX parser/control tests, analyzer tests and projection tests because package control values intentionally do not own DTX lane/source semantics.

- [ ] **Step 6: Run package + focused app regressions**

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

If `NotationLayoutControlRenderingTests` becomes fully package-pure, migrate its structural claims and delete it; retain any projection/source-semantics assertion under an honest integration suite.

- [ ] **Step 7: Re-run ownership search**

Expected: no Virgo production implementation of package-owned beam topology or primitive rendering.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "refactor: retire app engraving renderer"
```

---

## Task 9: Lock parity, real-chart evidence, docs and existing CI

**Files:**
- Package parity tests/reference artifacts only if needed
- `Packages/DrumNotation/README.md`
- Virgo golden/invariant/integration tests
- `.github/workflows/ci.yml` only if the existing package-test step has disappeared

- [ ] **Step 1: Audit required fixture matrix**

Package tests must contain named cases for:

```text
mixed 8th/16th
mixed 16th/32nd
forward hook
backward hook
isolated flag up
isolated flag down
same-stem chord isolated flag (one footprint)
dotted note/rest
triplet/tuplet bracket + no-bracket
6/8 compound grouping
simultaneous upper/lower voices
stop/choke/damp adjacent to notes
multi-row dense passage
representative tiebreakOrder behavior
unsupported-measure engraving suppression
```

- [ ] **Step 2: Decide whether executable VexFlow evidence is necessary**

If source/known VexFlow 5.0.0 behavior makes all expectations unambiguous, add no tooling.

If one fixture remains disputed, add the smallest package-local VexFlow 5.0.0 script + committed artifact for that case and a Swift test that reads/compares it. The script by itself is not a deliverable.

- [ ] **Step 3: Update README**

Document the public flow:

```swift
let input = try ResolvedNotationInput(...)
let layout = try NotationEngraver.engrave(input, style: .standard)
let position = layout.position(measureIndex: 0, localTick: 240)
let view = DrumNotationView(layout: layout)
```

Document dependency direction, Bravura/VexFlow lineage, package-owned resources and that Virgo owns rhythm inference/playback/scrolling/app accessibility copy.

- [ ] **Step 4: Run dense + sparse real-DTX integration fixtures**

Verify event identity, package rows/bars/controls, VoiceOver labels and playhead lookup through the real DTX → analyzer → projection → package path.

- [ ] **Step 5: Exercise controlled wrap widths**

Use the 900pt floor plus a practical width that produces a different row packing. Assert package row count, mounted row anchors and playhead row agree.

- [ ] **Step 6: Regenerate goldens only after structural tests are green**

Review every changed golden. Reject unrelated geometry churn; do not blanket-update snapshots.

- [ ] **Step 7: Confirm existing CI package step**

Verify `.github/workflows/ci.yml` still contains:

```bash
swift test --package-path Packages/DrumNotation
```

If present, leave workflow unchanged. Only restore it if it disappeared.

- [ ] **Step 8: Commit**

```bash
git add Packages/DrumNotation VirgoTests .github
git commit -m "test: lock DrumNotation renderer parity"
```

---

## Task 10: Final production verification and PR readiness gate

**Files:** no planned production changes; only fixes exposed by these gates.

- [ ] **Step 1: Independent package test**

```bash
swift test --package-path Packages/DrumNotation
```

Expected: PASS.

- [ ] **Step 2: Full serial macOS suite**

```bash
xcodebuild test \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'platform=macOS' \
  -parallel-testing-enabled NO
```

Expected: PASS.

- [ ] **Step 3: Production-mounted macOS visual smoke**

Use the actual gameplay sheet for:

- one dense real DTX;
- one sparse chart;
- at least two widths with different wrapping.

Inspect notehead/stem attachment, primary/secondary beams, hook direction, flags, dots/rests/tuplets, stop/choke/damp marks, staff/bar/clef/meter alignment, clipping/collisions, app annotations and playhead alignment.

- [ ] **Step 4: Accessibility smoke**

Confirm production-mounted semantics still expose representative current labels such as a named hi-hat/rest/control rather than generic glyph names.

- [ ] **Step 5: iPad compile gate**

```bash
xcodebuild build \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO
```

Expected: BUILD SUCCEEDED. Add an iPad-specific visual baseline only if a platform-specific rendering difference is actually observed.

- [ ] **Step 6: SwiftLint**

Run the repository's existing SwiftLint command/workflow. Fix only HPA-166-touched violations; no unrelated cleanup.

- [ ] **Step 7: Ownership/dependency searches**

```bash
rg 'import (Virgo|SwiftData)|GameplayLayout|Palette|AppFonts|RhythmLayoutSnapshot|DrumType' Packages/DrumNotation/Sources
rg 'NotationBeamTopologyBuilder|GameplayDrumNotationView|NotationNoteHeadView|NotationBeamView' Virgo
```

Expected:

- no app dependency leaks into package sources;
- no superseded app renderer/topology production symbols.

- [ ] **Step 8: Verify no silent empty-layout failure remains**

Search `GameplayNotationPreparer` error paths and run its invalid-input regression. Package validation failure must surface as practice unavailable/fatal state.

- [ ] **Step 9: Self-review against HPA-166 acceptance**

Check directly:

- first-class stem groups;
- one group-level flag plan;
- explicit representative tiebreaks;
- measure + note engraving suppression;
- `flagVerticalSpacing` style mapping;
- app accessibility strings preserved;
- package X/Y authority;
- ordinary-import public flow;
- render probe retargeted before old painter deletion;
- app compiles throughout API changes;
- preparation failure is not swallowed;
- package/static renderer ownership singular;
- no HPA-584 scope or compatibility renderer.

- [ ] **Step 10: Mark this same PR ready only after all gates pass**

Do not open a second implementation PR for HPA-166.
