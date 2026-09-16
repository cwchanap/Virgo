# HPA-166 Package Engraver and Static Renderer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Finish the three-PR `DrumNotation` migration by moving reusable beam/modifier/control/tuplet engraving and the complete static notation view into the package, preserving the real-DTX regression net through the cutover, then deleting Virgo's transitional renderer.

**Architecture:** Virgo keeps DTX/rhythm inference and projects resolved engraving values into `DrumNotation`. Package stem groups/topology drive both pre-format flag footprint and final beam/flag geometry. `NotationEngraver.engrave` returns pure immutable `EngravedNotation`; `DrumNotationView` paints it with caller-supplied appearance and accessibility labels. Before production switches, Virgo's real-DTX golden/invariant harness is retargeted to package engraving so later production cutover cannot hide geometry regressions behind blanket golden churn.

**Tech Stack:** Swift / Swift Package Manager / SwiftUI / CoreGraphics / Swift Testing / Xcode macOS + iOS Simulator, vendored Bravura/SMuFL resources, VexFlow 5.0.0 as semantic reference only.

**Spec:** `docs/superpowers/specs/2026-09-15-hpa-166-package-engraver-static-renderer-design.md`

## Global Constraints

- Exactly one PR for HPA-166; implementation continues on this draft PR.
- Keep one `DrumNotation` library target and one package test target.
- No DTX parsing, SwiftData, `RhythmLayoutSnapshot`, `DrumType`, `GameplayViewModel`, `GameplayLayout`, `Palette`, `AppFonts`, app logger, playback clock, localized app copy, or app diagnostics inside package geometry/model code.
- No old/new renderer toggle, fallback notation renderer, compatibility migration, second package target, repository-extraction harness, demo app, or publication workflow.
- Every commit that changes a public package initializer/type must update Virgo's only consumer in the same commit so the app still compiles.
- Preserve HPA-164 `FormattedNotation` as horizontal authority; no second formatter or app-side post-format X transform.
- Port existing beam topology before changing musical behavior; any parity change needs an explicit fixture.
- One package stem-group/topology result drives formatter flag footprint and final flags.
- `isRhythmEngravable` = note support AND measure `permitsEngraving`.
- Preserve current representative ordering with package scalar `tiebreakOrder` mapped from app `catalogOrder`.
- `flagVerticalSpacing` is an engraving-style scalar; stem width remains in `NotationFormattingStyle`.
- Package `EngravedNotation` contains geometry/semantics only; localized VoiceOver copy is passed to `DrumNotationView` at paint time.
- Final package Y is normalized once; Virgo does not recreate notation `topContentInset` / staff-center formulas.
- Keep feel/warning annotations in Virgo.
- Package preparation remains value/Sendable and off-main capable; SwiftUI colors exist only at the view appearance boundary.
- Keep macOS 14 and iOS/iPadOS 17.5 floors and current project Swift language mode.
- App `xcodebuild` tests remain serial/non-parallel.
- CI already runs `swift test --package-path Packages/DrumNotation`; do not add another package-test workflow unless that existing command disappears.
- VexFlow/Node is not a production dependency. Add reference tooling only when a disputed fixture requires executable evidence consumed by a Swift test.
- No new image/art assets.

---

## File Map

### Package — modify/create

- `Packages/DrumNotation/Sources/DrumNotation/Model/ResolvedNotation.swift` — final resolved engraving input.
- `Packages/DrumNotation/Sources/DrumNotation/Model/EngravingTypes.swift` — package voice/meter/tuplet/control values and immutable primitives.
- `Packages/DrumNotation/Sources/DrumNotation/Model/EngravingStyle.swift` — numeric engraving style with defaulted initializer.
- `Packages/DrumNotation/Sources/DrumNotation/Layout/BeamTopology.swift` — ported topology/stem-group/flag-plan logic.
- `Packages/DrumNotation/Sources/DrumNotation/Layout/NotationFormatter.swift` — consume one group flag plan for spacing.
- `Packages/DrumNotation/Sources/DrumNotation/Layout/NotationEngraver.swift` — single production package facade.
- `Packages/DrumNotation/Sources/DrumNotation/Rendering/DrumNotationView.swift` — complete static notation view.
- `Packages/DrumNotation/Sources/DrumNotation/Rendering/PrimitiveViews.swift` — reuse/extend Bravura painters.
- `Packages/DrumNotation/README.md` — final public flow/ownership/reference contract.

### Package tests

- `Packages/DrumNotation/Tests/DrumNotationTests/ResolvedNotationEngravingTests.swift`
- `Packages/DrumNotation/Tests/DrumNotationTests/BeamTopologyTests.swift`
- `Packages/DrumNotation/Tests/DrumNotationTests/NotationEngraverGeometryTests.swift`
- `Packages/DrumNotation/Tests/DrumNotationTests/NotationEngraverModifierTests.swift`
- `Packages/DrumNotation/Tests/DrumNotationTests/DrumNotationViewTests.swift`
- `Packages/DrumNotation/Tests/DrumNotationTests/PackageBoundaryTests.swift`
- existing HPA-163/164 package tests as affected.

### Virgo integration

- `Virgo/layout/VirgoNotationProjection.swift`
- `Virgo/layout/VirgoNotationProjection+Flags.swift` — delete at production cutover.
- `Virgo/layout/GameplayNotationPreparation.swift`
- `Virgo/viewmodels/GameplayViewModel+Notation.swift` plus concrete notation cache/install call sites.
- `Virgo/views/subviews/GameplaySheetMusicView.swift`
- `Virgo/views/GameplayNotationAnnotationViews.swift` if app annotations need extraction.
- `Virgo/views/NotationPrimitiveViews.swift` — delete after package render/mount probes are green.
- existing app layout/topology files — delete/reduce after production cutover.

### Real-DTX regression net — explicitly migrate before cutover

- `VirgoTests/Fixtures/DrumTabFixtureHarness.swift`
- `VirgoTests/NotationLayoutDigest.swift` (rename to `DrumNotationDigest.swift` if clearer).
- `VirgoTests/DrumTabGoldenTests.swift`
- `VirgoTests/DrumTabRegressionInvariantTests.swift`
- `VirgoTests/DrumTabRenderProbeTests.swift`
- `VirgoTests/GameplaySheetMusicMountingTests.swift`
- `VirgoTests/DrumTabPlayheadAlignmentTests.swift`
- `VirgoTests/Goldens/*`

---

## Task 1: Extend the resolved package model without breaking Virgo

**Files:**
- Modify `ResolvedNotation.swift`.
- Create/modify package engraving model tests.
- Modify `VirgoNotationProjection.swift` in the same commit.

**Interfaces:**
- Package input gains only resolved engraving semantics.
- Production may still call the existing formatter directly after this task.
- Existing transitional `visibleFlagDuration` stays only until the production cutover; do not invent a new compatibility layer.

- [ ] **Step 1: Add failing package model tests**

Pin package-local values:

```swift
public enum NotationVoiceRole: Int, Hashable, Sendable { case upper, lower }

public struct NotationMeter: Hashable, Sendable {
    public let beats: Int
    public let noteValue: Int
}

public struct ResolvedBeatGroup: Hashable, Sendable {
    public let startTick: Int
    public let durationTicks: Int
}
```

Do not add `ResolvedBeatGroup.index`; array position is the validated group ordinal.

- [ ] **Step 2: Extend `ResolvedMeasure`**

Add `meter` + ordered `beatGroups`. Validation must reject:

- non-positive group duration;
- gaps/overlap;
- first group not starting at 0;
- final group not ending at `measure.durationTicks`.

- [ ] **Step 3: Extend notes/rests/controls/tuplets**

Final new note semantics:

```text
voice
durationTicks
tiebreakOrder
isRhythmEngravable
articulation: existing PercussionArticulation?
```

Rest adds `voice` + `durationTicks`.

Control adds package-local `stop/choke/damp` + resolved `targetStaffStep`.

Tuplet group carries deterministic adapter-local ID, measure, voice, ratio, note IDs and rest IDs.

Do not add accessibility strings to any resolved type.

- [ ] **Step 4: Define the exact app mapping**

In `VirgoNotationProjection`:

```text
voice               <- existing NotationVoice
meter/beatGroups    <- existing RhythmMeasure
note.durationTicks  <- RhythmLayoutNote durationTicks
note.tiebreakOrder  <- DrumNotationDefinition.catalogOrder
isRhythmEngravable <- note.rhythm.support == .supported
                       && owningMeasure.engravingSupport.permitsEngraving
articulation        <- existing open-hi-hat intent
control kind/step   <- existing control target resolution + user override
```

Keep rest filtering exactly as current: hidden rests and rests in non-engraving measures do not cross the boundary.

- [ ] **Step 5: Keep the current app compile path alive**

If HPA-164's existing `stemMember` / `visibleFlagDuration` are still required by the direct production formatter, keep them temporarily unchanged in this commit. The final model removal happens in Task 7 when production stops calling the transitional path.

This is not a new fallback; it is sequencing the deletion with its last consumer.

- [ ] **Step 6: Run package tests + app compile**

```bash
swift test --package-path Packages/DrumNotation
xcodebuild build \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO
```

Expected: both pass before commit.

- [ ] **Step 7: Commit**

```bash
git add Packages/DrumNotation Virgo/layout/VirgoNotationProjection.swift
git commit -m "feat: extend resolved notation for engraving"
```

---

## Task 2: Port stem groups + beam topology and unify flag planning

**Files:**
- Create `Layout/BeamTopology.swift`.
- Modify `NotationFormatter.swift` package internals/tests.
- Read/port from `Virgo/layout/NotationBeamTopology.swift`, `NotationLayoutEngine+Beams.swift`, and `VirgoNotationProjection+Flags.swift`.
- Do not delete app topology/prepass yet.

**Interfaces:**
- Internal `StemGroupKey = measure + localTick + voice + stemDirection`.
- Internal `StemGroup` carries member IDs + explicit stem/flag representative IDs.
- One internal `VisibleFlagPlan` per stem group.

- [ ] **Step 1: Add representative tests before porting topology**

Pin current comparators:

```text
stem representative:
  needs stem + isRhythmEngravable
  staffStep
  then tiebreakOrder
  then ID
  up -> lowest/stem-side, down -> highest/stem-side

flag representative:
  most required flag levels
  then tiebreakOrder
  then ID
```

Include equal-staff-position/equal-duration cases so `tiebreakOrder` is actually exercised.

- [ ] **Step 2: Port the topology algorithm mechanically**

Preserve current primary runs, exact-duration adjacency, beam levels, hook-neighbor rule, and boundaries by measure/voice/stem direction/beat-group ordinal.

Do not use pre-format row in the grouping key; measures never split across rows. Add a post-format invariant that a group maps to exactly one row.

- [ ] **Step 3: Add required parity fixtures**

Package tests must cover:

- mixed eighth/sixteenth;
- mixed sixteenth/thirty-second;
- forward hook;
- backward hook;
- upper/lower voice separation;
- opposite stem direction separation;
- 6/8 beat-group boundary;
- supported tuplet exact-duration adjacency.

- [ ] **Step 4: Add one `VisibleFlagPlan` per stem group**

```swift
enum VisibleFlagPlan: Hashable, Sendable {
    case none
    case canonical(NotationFlagDuration)
    case components(Set<Int>)
}
```

The plan is keyed by the stem group/stem-side representative. Formatter collision code must measure it once at the shared stem axis.

- [ ] **Step 5: Add the chord double-reservation regression**

Use same-tick snare + closed-hi-hat isolated sixteenths. Assert:

- one stem group;
- one visible flag plan;
- one reserved flag extent;
- row/measure width does not double because two heads share the stem.

- [ ] **Step 6: Keep production parity observable before deletion**

Add a test-only parity helper in Virgo tests that projects a controlled snapshot through:

1. current `VirgoNotationProjection+Flags`;
2. package `StemGroup`/topology plan.

Compare visible-plan ownership/canonical/component levels for isolated, fully beamed, partially covered, and chord cases.

Do not delete the app prepass until this gate is green.

- [ ] **Step 7: Preserve the old direct formatter path temporarily**

Package `NotationEngraver` work in later tasks may pass internal flag plans explicitly, while the still-live HPA-164 production formatter can continue reading its current projected flag field until Task 7. Do not expose a second public formatting engine.

- [ ] **Step 8: Verify**

```bash
swift test --package-path Packages/DrumNotation
xcodebuild test \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'platform=macOS' \
  -parallel-testing-enabled NO \
  -only-testing:VirgoTests/VirgoNotationProjectionFlagTests
```

Use the actual existing projection-flag suite identifier if its concrete name differs.

- [ ] **Step 9: Commit**

```bash
git add Packages/DrumNotation VirgoTests
git commit -m "feat: move beam topology into DrumNotation"
```

---

## Task 3: Add package engraving style + immutable geometry result

**Files:**
- Create `Model/EngravingStyle.swift`.
- Create/extend `Model/EngravingTypes.swift`.
- Create `Layout/NotationEngraver.swift`.
- Add `NotationEngraverGeometryTests.swift`.

**Interfaces:**
- `NotationEngravingStyle` contains formatting style + vertical/beam/control/tuplet/bar metrics.
- No `.standard` static singleton: use a public initializer with default arguments.
- `EngravedNotation` is pure geometry/semantics; no localized strings.

- [ ] **Step 1: Add failing style tests**

Pin defaults needed by package-only tests and require explicit `flagVerticalSpacing`.

Virgo's later mapper must map `GameplayLayout.flagVerticalSpacing`; flag stem origin must use `style.formatting.stemWidth`.

- [ ] **Step 2: Implement defaulted `NotationEngravingStyle.init(...)`**

Follow `NotationFormattingStyle`'s existing default-argument pattern. Do not add a `.standard` API whose only consumer is `PackageBoundaryTests`.

- [ ] **Step 3: Define immutable geometry values**

At minimum, public values for:

```text
EngravedRow
EngravedMeasure
EngravedNoteHead
EngravedRest
EngravedStem
EngravedBeam
EngravedFlag
EngravedLedgerLine
EngravedRhythmDot
EngravedArticulation
EngravedControl
EngravedTuplet
EngravedMeasureBar
```

Each semantic primitive retains its source integer ID/kind so app tests/view accessibility can associate it without app types.

- [ ] **Step 4: Define `EngravedNotation`**

Include:

```text
formatted: FormattedNotation
rows + measures
all reusable primitive arrays
paintedBounds
contentWidth
contentHeight
```

Forward musical-position lookup to the embedded formatter rather than duplicating interpolation.

- [ ] **Step 5: Implement one engraver facade**

```swift
public enum NotationEngraver {
    public static func engrave(
        _ input: ResolvedNotationInput,
        style: NotationEngravingStyle
    ) throws -> EngravedNotation
}
```

Order:

```text
stem groups/topology
-> one visible flag plan per group
-> measured formatter using those package plans
-> final vertical/primitive geometry
-> painted bounds
-> one Y normalization
```

- [ ] **Step 6: Build notes/rests/rows/ledgers/dots**

Use package-formatted X and package-owned Y:

```text
staffStep delta = formatting.staffSpace / 2
row pitch = rowHeight + rowVerticalSpacing
rest Y = row staff center + voice offset
```

Use Bravura painted bounds for heads/rests. Dots use actual painted maxX + formatter dot spacing/radius.

- [ ] **Step 7: Normalize Y once**

After raw geometry bounds are known, apply one package translation when minY < 0 to rows and every primitive. `DrumNotationView` must not add another hidden translation.

- [ ] **Step 8: Geometry/bounds tests**

Cover:

- two rows;
- high cymbal / low rest;
- displaced same-stem seconds;
- full-measure rest;
- every primitive inside final `paintedBounds`.

- [ ] **Step 9: Verify + commit**

```bash
swift test --package-path Packages/DrumNotation
xcodebuild build -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
git add Packages/DrumNotation
git commit -m "feat: add package engraving geometry"
```

---

## Task 4: Complete stems/beams/flags/modifiers/controls/tuplets and row descriptors

**Files:**
- Modify `NotationEngraver.swift`.
- Split to focused extensions only if needed for file-size limits.
- Add `NotationEngraverModifierTests.swift`.

**Interfaces:**
- Reuse Task 2 topology/stem groups.
- Produce all reusable primitive arrays consumed by `EngravedNotation`.

- [ ] **Step 1: Port stem + flat-beam geometry**

Use current Virgo calculations and package metrics. Stem starts from the stem representative's Bravura attachment point; same-stem displaced sibling never moves the axis.

- [ ] **Step 2: Add beam/hook geometry tests**

Assert:

- primary/secondary stack spacing = `beamLevelSpacing`;
- stem reaches the outermost beam + minimum chord clearance;
- hook direction/length follows topology;
- one beam group stays within one formatted row.

- [ ] **Step 3: Paint flags from the same group plan**

Canonical plan paints one duration-specific Bravura flag. Component plan paints uncovered eighth components using `flagVerticalSpacing`.

Add invariant: formatter-reserved flag bounds contain final painted flag bounds.

- [ ] **Step 4: Port articulation placement**

Reuse existing `PercussionArticulation.open`; do not add another articulation enum.

- [ ] **Step 5: Port controls**

Use logical-column X + resolved target staff step. Preserve stop/choke/damp kinds and existing cross-mark geometry first.

- [ ] **Step 6: Port tuplets**

Use resolved membership + final head/rest/beam bounds:

```text
all members continuously beamed + no rests -> label only
otherwise                                  -> bracket + label
```

Add up/down, bracket/no-bracket, dotted/rest-member, and supported triplet cases.

- [ ] **Step 7: Add staff/clef/meter/bar descriptors**

Rows carry enough final geometry for package painting and Virgo row anchors/playhead Y. Derive bar X from formatted measure bounds.

- [ ] **Step 8: Run + commit**

```bash
swift test --package-path Packages/DrumNotation
git add Packages/DrumNotation
git commit -m "feat: complete DrumNotation engraving primitives"
```

---

## Task 5: Add complete `DrumNotationView` + one view-only accessibility seam

**Files:**
- Create `Rendering/DrumNotationView.swift`.
- Modify `PrimitiveViews.swift`.
- Add `DrumNotationViewTests.swift`.
- Modify `PackageBoundaryTests.swift`.

**Interfaces:**
- `DrumNotationView(layout:appearance:accessibilityLabels:)`.
- Geometry remains pure; accessibility is view input.

- [ ] **Step 1: Add one collision-safe semantic accessibility key**

```swift
public enum NotationSemanticID: Hashable, Sendable {
    case note(Int)
    case rest(Int)
    case control(Int)
    case tuplet(Int)
}
```

Do not use one bare `[Int: String]` namespace: package note/rest/control/tuplet IDs are separate collections and may share the same integer.

- [ ] **Step 2: Add view appearance**

Keep view-only color/opacity in a narrow appearance value. No `Palette` import.

- [ ] **Step 3: Paint all reusable package geometry**

Render staff, ledger, stems, beams, flags, notes, rests, dots, articulations, controls, tuplets, bars, clef, and meter. Reuse package Bravura painters.

- [ ] **Step 4: Apply labels at paint time**

For each semantic primitive look up:

```text
.note(noteID)
.rest(restID)
.control(controlID)
.tuplet(tupletID)
```

Decorative geometry is accessibility-hidden. Do not store localized strings in `ResolvedNotationInput` or `EngravedNotation`.

- [ ] **Step 5: Add package raster/bounds tests**

Render focused fixtures and assert ink within final bounds for:

- notehead + isolated flag;
- beamed run;
- control + tuplet.

- [ ] **Step 6: Expand the ordinary-import consumer test**

Keep `PackageBoundaryTests.swift` on ordinary `import DrumNotation`:

```swift
let input = try ResolvedNotationInput(/* simple resolved measure + note */)
let layout = try NotationEngraver.engrave(
    input,
    style: NotationEngravingStyle()
)
#expect(layout.position(measureIndex: 0, localTick: 0)?.rowIndex == 0)
_ = DrumNotationView(layout: layout, accessibilityLabels: [:])
```

No test-only `.standard` style.

- [ ] **Step 7: Verify package resources independently**

```bash
swift test --package-path Packages/DrumNotation
```

No `AppFonts.registerAll()`, `Bundle.main`, Virgo test host, or repository-root resource lookup.

- [ ] **Step 8: Commit**

```bash
git add Packages/DrumNotation
git commit -m "feat: add complete DrumNotation static view"
```

---

## Task 6: Move the real-DTX golden/invariant net to package engraving before production cutover

**Files:**
- Modify `VirgoTests/Fixtures/DrumTabFixtureHarness.swift`.
- Retarget/rename `VirgoTests/NotationLayoutDigest.swift`.
- Modify `DrumTabGoldenTests.swift`.
- Modify `DrumTabRegressionInvariantTests.swift`.
- Modify `DrumTabRenderProbeTests.swift`.
- Regenerate/review `VirgoTests/Goldens/*` once.
- Production Virgo renderer remains unchanged in this task.

**Goal:** Establish a reviewable package-geometry baseline while the old production renderer still compiles. From the next task onward, production cutover should not require blanket golden regeneration.

- [ ] **Step 1: Add test-only package engraving to the real-DTX harness**

Keep the existing real import/analyzer path. From the same `RhythmLayoutSnapshot`, use `VirgoNotationProjection` + `NotationEngraver` to expose `EngravedNotation` for tests.

The app still mounts/installs its current `NotationLayout` in production at this checkpoint.

- [ ] **Step 2: Retarget the digest to `EngravedNotation`**

Keep the timeline/analyzer section from the existing digest.

For engraving lines:

- source package primitives, not `NotationLayout`;
- express primitive Y relative to the owning row's `staffCenterY`;
- keep X absolute/sheet-local;
- output package semantic style values, not deleted app box widths/heights;
- do not serialize hidden rests because package engraving intentionally never receives them.

This makes package global Y normalization a digest no-op while preserving meaningful staff-relative geometry.

- [ ] **Step 3: Retarget real-DTX geometric invariants**

Keep these tests in `VirgoTests` because the harness exercises the real DTX/analyzer/projection path. Rewrite their primitive access to `EngravedNotation`:

- beam extent within member stems;
- beam membership within rhythm beat group;
- partition by measure/row/voice/direction;
- head X matches package formatted head center;
- simultaneous onset alignment;
- painted-bounds containment.

Do not duplicate pure package unit assertions; these remain integration invariants across the real app source path.

- [ ] **Step 4: Retarget the raster probe before old painters disappear**

Replace `NotationNoteHeadView` / `RenderedNoteHead.paintedBounds` with `DrumNotationView` (or its package head painter for per-head isolation) + `EngravedNoteHead.paintedBounds`.

Preserve the current claim separation:

- raster probe proves package ink paints inside package geometry;
- `GameplaySheetMusicMountingTests` later proves production mounts that package view.

- [ ] **Step 5: Add direct old-vs-package bridge assertions where cheap**

At this checkpoint only, compare a few high-value identities from the same fixture:

```text
measure count/index
note event IDs
control kinds/IDs
formatted tick -> row/X
```

Do not build a generalized dual-renderer comparator.

- [ ] **Step 6: Run the new package-backed regression net before updating goldens**

```bash
xcodebuild test \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'platform=macOS' \
  -parallel-testing-enabled NO \
  -only-testing:VirgoTests/DrumTabRegressionInvariantTests \
  -only-testing:VirgoTests/DrumTabRenderProbeTests
```

Fix structural failures before any golden update.

- [ ] **Step 7: Regenerate the package-geometry golden baseline exactly once**

```bash
TEST_RUNNER_VIRGO_UPDATE_GOLDENS=1 xcodebuild test \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'platform=macOS' \
  -configuration Debug \
  -only-testing:VirgoTests/DrumTabGoldenTests \
  -parallel-testing-enabled NO \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  -destination-timeout 300 \
  -derivedDataPath ./DerivedData
```

The regeneration run intentionally fails after rewriting per existing golden safety behavior; then run the same test without the update variable and require PASS.

- [ ] **Step 8: Review every golden diff by named cause**

Expected classes only:

- digest schema changes from app `NotationLayout` → package `EngravedNotation`;
- absolute Y → row-relative Y representation;
- hidden-rest lines removed because package never engraves them;
- explicitly accepted geometry correction such as one shared flag footprint per chord stem group.

Reject unexplained beam membership, X movement, rest/control identity, or row-packing changes.

- [ ] **Step 9: Commit the regression baseline separately**

```bash
git add VirgoTests
git commit -m "test: move drum tab regression net to package engraving"
```

This commit is the geometry baseline for all later tasks.

---

## Task 7: Perform one compile-safe production cutover

**Files:**
- Modify `VirgoNotationProjection.swift` and delete `VirgoNotationProjection+Flags.swift`.
- Modify `GameplayNotationPreparation.swift`.
- Modify `GameplayViewModel+Notation.swift` and concrete notation cache/install call sites.
- Modify `GameplaySheetMusicView.swift`.
- Create `GameplayNotationAnnotationViews.swift` if needed.
- Delete `NotationPrimitiveViews.swift` only after replacement tests are green in this same task.
- Update mounting/playhead/failure/accessibility tests.

**Rule:** Do not split preparation and view installation into separate commits. The app must compile at the task boundary.

- [ ] **Step 1: Define closed prepared state**

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

No both-nil/both-set states.

- [ ] **Step 2: Build app-only presentation data**

Virgo builds:

- feel/warning annotations;
- localized note/rest/control/tuplet labels keyed by collision-safe `NotationSemanticID`.

Do not pass those strings into the engraver.

- [ ] **Step 3: Switch preparation to one package engraver call**

```text
expand measures
-> project resolved package input
-> map NotationEngravingStyle
-> NotationEngraver.engrave
-> build app presentation
-> .ready(...)
```

Delete `ComposedNotation`, `RebuiltArtifacts`, app X lookup dictionaries, and reusable app finalization after all call sites switch.

- [ ] **Step 4: Make engraving failures explicit**

Create one small app `GameplayNotationPreparationFailure` carrying log/test detail + one practice-unavailable user message.

On package validation/engraving error return `.failed`, not an empty success.

Do not mutate rhythm-analysis truth. Store notation-preparation failure separately in the view model and expose one existing-screen presentation message, for example conceptually:

```swift
var practiceUnavailableMessage: String? {
    notationPreparationFailure?.userMessage
        ?? (hasFatalRhythmTiming ? rhythmFatalMessage : nil)
}
```

Reuse the existing `rhythmFatalSheet` / practice-unavailable surface; no second error screen.

- [ ] **Step 5: Replace view-model installation/cache**

`applyPreparedNotation` handles the enum exhaustively:

```text
.ready -> install engraving + presentation for the generation
.failed -> install failure for the generation and mark preparation settled
stale generation -> ignore either result
```

Update every `cachedNotationLayout`/`prepared.layout` consumer in this same task before committing.

- [ ] **Step 6: Replace the production static notation branch**

Conceptual branch:

```swift
DrumNotationView(
    layout: input.engraving,
    appearance: .init(foreground: Palette.chalk),
    accessibilityLabels: input.presentation.accessibilityLabels
)
```

Overlay only Virgo feel/warning annotations. Live playhead remains a sibling outside the generation-equatable static subtree.

- [ ] **Step 7: Use final package rows for anchors/playhead Y**

Delete notation-branch `topContentInset`, notehead-derived row padding, and `GameplayLayout.StaffLinePosition` Y reconstruction. Row anchors and playhead resolve the same normalized package rows the package view paints.

- [ ] **Step 8: Delete the app flag prepass and transitional input fields**

Now remove:

- `VirgoNotationProjection+Flags.swift`;
- public `visibleFlagDuration`;
- public `stemMember` if still present;
- direct Virgo production calls to `NotationFormatter`.

Package `NotationEngraver` becomes the sole production route.

- [ ] **Step 9: Preserve VoiceOver behavior**

Add app tests that pin representative current copy (`Closed hi-hat`, `Open hi-hat`, rest voice label, stop/choke label, tuplet label) and prove `DrumNotationView` receives labels through presentation without changing engraving equality.

- [ ] **Step 10: Update production mounting and playhead tests**

`GameplaySheetMusicMountingTests` must fail if the production static branch omits `DrumNotationView`.

`DrumTabPlayheadAlignmentTests` covers multiple wrapped rows using package row Y + formatter X.

- [ ] **Step 11: Delete old static primitive wrappers only after tests are green**

Remove `NotationPrimitiveViews.swift`, `GameplayDrumNotationView`, package-replaced bar/clef/staff views, and obsolete compatibility wrappers in this same cutover commit.

- [ ] **Step 12: Run the cutover gate**

```bash
swift test --package-path Packages/DrumNotation
xcodebuild test \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'platform=macOS' \
  -parallel-testing-enabled NO \
  -only-testing:VirgoTests/GameplayNotationPreparationTests \
  -only-testing:VirgoTests/GameplayNotationInstallationTests \
  -only-testing:VirgoTests/GameplaySheetMusicMountingTests \
  -only-testing:VirgoTests/DrumTabPlayheadAlignmentTests \
  -only-testing:VirgoTests/DrumTabRenderProbeTests \
  -only-testing:VirgoTests/DrumTabGoldenTests \
  -only-testing:VirgoTests/DrumTabRegressionInvariantTests
```

**Important:** do not regenerate goldens here. They were intentionally baselined in Task 6. A golden diff now is a production-cutover regression unless a concrete bug fix explains it.

- [ ] **Step 13: Commit the entire cutover together**

```bash
git add -A Packages/DrumNotation Virgo VirgoTests
git commit -m "refactor: cut Virgo over to DrumNotation renderer"
```

---

## Task 8: Delete superseded app engraving algorithms and migrate pure tests

**Files:**
- Delete `Virgo/layout/NotationBeamTopology.swift`.
- Reduce/delete package-replaced logic from `NotationLayoutEngine+Beams.swift`, `+Controls.swift`, `+Rests.swift`, `+RhythmRendering.swift`, `NotationLayout.swift`, and related engine helpers.
- Migrate/delete pure app geometry tests now covered by package suites.
- Keep source/analyzer/projection/real-DTX/mounted UI tests.

- [ ] **Step 1: Inventory transitional symbols**

```bash
rg 'NotationBeamTopologyBuilder|buildBeams\(|buildStems\(|buildFlags\(|buildLedgerLines\(|buildRests\(|buildStopNotes\(|buildTuplets\(|GameplayDrumNotationView|NotationNoteHeadView|NotationBeamView|RenderedNoteHead|RenderedBeam|RenderedFlag' Virgo VirgoTests
```

Classify each hit before deletion.

- [ ] **Step 2: Delete app topology after package parity coverage**

Delete `NotationBeamTopology.swift` and its pure unit tests only after Task 2 package tests cover the same structural cases.

- [ ] **Step 3: Delete reusable app builders/finalization**

Remove package-replaced stems/beams/flags/ledger/rest/control/tuplet/bounds construction. Relocate any remaining feel/warning helper to an app annotation file rather than keeping a misleading layout-engine extension.

- [ ] **Step 4: Remove obsolete app `Rendered*` values**

Delete app note/rest/stem/beam/flag/ledger/bar/dot/articulation/control/tuplet render types after no callers remain.

Keep app domain/analyzer values and presentation annotations that are genuinely outside the package.

- [ ] **Step 5: Preserve source-semantic tests**

Keep:

- `ChartControlEventTests`;
- DTX parser/control import tests;
- rhythm analyzer/timeline tests;
- Virgo projection tests;
- real-DTX package integration goldens/invariants;
- production mounting/playhead/accessibility/failure tests.

- [ ] **Step 6: Re-run ownership search**

Expected: no Virgo production hits for package-owned topology/builders/static primitive view types.

- [ ] **Step 7: Run package + regression net**

```bash
swift test --package-path Packages/DrumNotation
xcodebuild test \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'platform=macOS' \
  -parallel-testing-enabled NO \
  -only-testing:VirgoTests/DrumTabGoldenTests \
  -only-testing:VirgoTests/DrumTabRegressionInvariantTests \
  -only-testing:VirgoTests/DrumTabRenderProbeTests \
  -only-testing:VirgoTests/GameplaySheetMusicMountingTests \
  -only-testing:VirgoTests/DrumTabPlayheadAlignmentTests
```

Again: no blanket golden regeneration.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "refactor: retire Virgo engraving implementation"
```

---

## Task 9: Final parity evidence, docs, full verification, and PR readiness

**Files:** package parity tests/references only if still needed, package README, existing CI only if package-test command disappeared.

- [ ] **Step 1: Audit the required fixture matrix**

Require named package/real-DTX coverage for:

```text
mixed 8th/16th
mixed 16th/32nd
forward hook
backward hook
isolated flag up/down
dotted note/rest
supported triplet/tuplet
6/8 grouping
simultaneous upper/lower voices
stop/choke/damp adjacent to notes
multi-row dense passage
shared-stem chord flag footprint
```

- [ ] **Step 2: Decide whether executable VexFlow evidence is actually needed**

If pinned VexFlow 5.0.0 behavior/source makes every structural expectation unambiguous, add no Node tooling.

Only for a disputed fixture: add the smallest package-local pinned script + committed artifact and a Swift test that consumes it.

- [ ] **Step 3: Update package README**

Document the final flow using defaulted initializer arguments:

```swift
let input = try ResolvedNotationInput(...)
let layout = try NotationEngraver.engrave(
    input,
    style: NotationEngravingStyle()
)
let position = layout.position(measureIndex: 0, localTick: 240)
let view = DrumNotationView(layout: layout, accessibilityLabels: [:])
```

Document dependency direction, Bravura/VexFlow lineage, package resources, and that Virgo owns rhythm inference/playback/scrolling/localized copy.

- [ ] **Step 4: Run dense + sparse real-DTX integration at controlled widths**

Use one dense real chart + one sparse fixture, at the 900pt floor and at least one practical width that changes wrapping. Verify package rows, mounted row anchors, bars, controls, and playhead agree.

- [ ] **Step 5: Audit golden history since Task 6**

```bash
git diff <TASK6_GOLDEN_BASELINE_COMMIT>..HEAD -- VirgoTests/Goldens
```

Every changed golden line after the Task 6 baseline must map to a named subsequent bug fix. If there was no such fix, expect no golden changes. Do not run another blanket update.

- [ ] **Step 6: Run production-mounted macOS visual + accessibility smoke**

Review dense/sparse + changed-wrap examples for:

- head/stem attachment;
- beam/hook direction;
- dots/rests/tuplets;
- control marks;
- staff/clef/meter/bars;
- collisions/clipping;
- playhead alignment;
- representative VoiceOver labels.

- [ ] **Step 7: Run package tests**

```bash
swift test --package-path Packages/DrumNotation
```

- [ ] **Step 8: Run full serial macOS tests**

```bash
xcodebuild test \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'platform=macOS' \
  -parallel-testing-enabled NO
```

- [ ] **Step 9: Run iPad compile gate**

```bash
xcodebuild build \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO
```

- [ ] **Step 10: Run SwiftLint**

Use the repository's existing command/workflow. Fix only HPA-166-touched serious violations/readability issues; no unrelated cleanup.

- [ ] **Step 11: Run final ownership searches**

```bash
rg 'import (Virgo|SwiftData)|GameplayLayout|Palette|AppFonts|RhythmLayoutSnapshot|DrumType' Packages/DrumNotation/Sources
rg 'NotationBeamTopologyBuilder|GameplayDrumNotationView|NotationNoteHeadView|NotationBeamView|VirgoNotationProjection\+Flags' Virgo
```

Expected: no package app-dependency leaks and no superseded production renderer/topology symbols.

- [ ] **Step 12: Check acceptance criteria directly**

Confirm:

- package owns reusable engraving/static view;
- one group topology drives beam + spacing + flags;
- representative order and engraving suppression preserved;
- geometry is final normalized X/Y;
- accessibility labels are view-only and preserved;
- golden/invariant net moved before cutover and remains meaningful;
- cutover used closed ready/failed state and no blank-success failure;
- generation isolation/playhead behavior remains;
- no fallback/compatibility path, HPA-584 work, extra target, or unused VexFlow harness.

- [ ] **Step 13: Mark this same PR ready for review**

Do not open a second implementation PR for HPA-166.