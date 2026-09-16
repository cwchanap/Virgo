# HPA-166 Package Engraver and Static Renderer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Finish the three-PR `DrumNotation` migration by moving beam/modifier/control/tuplet engraving and the complete static notation view into the package, then delete Virgo's transitional engraving composition while preserving app-owned rhythm analysis, annotations, scrolling and live playback.

**Architecture:** Virgo continues to analyze DTX into `RhythmLayoutSnapshot`, then `VirgoNotationProjection` maps only resolved engraving semantics into package values. `DrumNotation.NotationEngraver` performs one package beam-topology prepass, feeds its visible-flag coverage into the existing measured formatter, builds all reusable engraving geometry, normalizes final Y once, and returns immutable `EngravedNotation`; `DrumNotationView` paints that value. Virgo keeps only domain projection, feel/warning annotations, row anchors, scrolling and the live playhead.

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
- Package output owns final normalized notation Y; Virgo must not recreate top inset/staff-row formulas for the notation branch.
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

- `EngravingTypes.swift` — package voice/meter/beat-group/tuplet/control types plus immutable engraving primitive/result values.
- `EngravingStyle.swift` — `NotationEngravingStyle` and package row/staff geometry scalars.

### Modify in `Packages/DrumNotation/Sources/DrumNotation/Model/`

- `ResolvedNotation.swift` — extend measures/notes/rests/controls, remove transitional visible-flag/stem-member inputs, add tuplets and validation.

### Create in `Packages/DrumNotation/Sources/DrumNotation/Layout/`

- `BeamTopology.swift` — package-internal port of the proven beat-group topology builder.
- `NotationEngraver.swift` — single public resolved-input → immutable engraving entry point.
- `NotationEngraver+Rhythm.swift` — stems/beams/flags/rest/dot/tuplet geometry helpers only if splitting the main engraver materially improves readability.
- `NotationEngraver+Marks.swift` — articulation/control/ledger/bar/staff descriptor helpers only if needed for the same reason.

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

### Modify/create in Virgo

- `Virgo/layout/VirgoNotationProjection.swift`
- `Virgo/layout/GameplayNotationPreparation.swift`
- `Virgo/layout/NotationLayout.swift` — shrink/delete package-owned rendering data; retain only app annotation values if still needed by call sites
- `Virgo/viewmodels/GameplayViewModel+Notation.swift`
- `Virgo/viewmodels/GameplayViewModel+VisualUpdates.swift` as required by the new prepared-state shape
- `Virgo/views/subviews/GameplaySheetMusicView.swift`
- `Virgo/views/GameplayNotationAnnotationViews.swift`
- `VirgoTests/VirgoNotationProjectionTests.swift`
- affected fixture/golden/playhead/mounting/preparation tests
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

**Files:** `EngravingTypes.swift`, `ResolvedNotation.swift`, `ResolvedNotationEngravingTests.swift`, existing formatter fixtures/tests.

- [ ] **Step 1: Add failing beat-group validation tests**

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

- [ ] **Step 2: Add the minimal package values**

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

Required fields become index/start/duration + meter + ordered beat groups. Validate positive meter values, positive contiguous groups starting at tick 0, and final group end == measure duration.

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

Add `tuplets` to `ResolvedNotationInput`. Validate unique group IDs, positive ratios, non-empty membership, existing members, and same measure/voice. Virgo later assigns deterministic ordinal IDs after sorting its stable tuple identities; do not use Swift `Hasher` as a persistent/stable ID.

- [ ] **Step 6: Add exact-duration containment validation**

For notes/rests, require `durationTicks > 0` and overflow-safe `localTick + durationTicks <= measure.durationTicks`.

- [ ] **Step 7: Update HPA-164 package fixtures without compatibility overloads**

Existing formatter fixtures explicitly provide simple 4/4 groups and new note/rest fields. Do not add deprecated/default old initializers merely to keep tests compiling.

- [ ] **Step 8: Run the package suite**

```bash
swift test --package-path Packages/DrumNotation
```

Expected: PASS before topology migration.

- [ ] **Step 9: Commit**

```text
feat: extend resolved notation for engraving
```

---

## Task 2: Port beam topology and make it the single flag-coverage source

**Files:** `BeamTopology.swift`, `BeamTopologyTests.swift`, `NotationFormatter.swift`, formatter spacing tests; current Virgo topology is reference-only until Task 8 deletion.

- [ ] **Step 1: Port current topology tests as red package tests**

Move the meaningful cases from `VirgoTests/NotationBeamTopologyTests.swift` to package-value fixtures before porting implementation.

- [ ] **Step 2: Port the builder with package types**

Preserve segment shape:

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

Group by measure + voice + stem direction + beat-group index. Omit pre-format row because a measure never splits across rows.

- [ ] **Step 3: Preserve exact-duration adjacency**

Use `ResolvedNote.durationTicks`; do not infer adjacency from `NotationDuration` or visual spacing.

- [ ] **Step 4: Add parity cases**

Cover mixed 8/16, mixed 16/32, forward/backward hooks, upper/lower separation, opposite stem separation, and resolved 6/8 group boundaries. Name tests after expected VexFlow 5.0.0 structural behavior; no executable JS harness yet.

- [ ] **Step 5: Derive one visible-flag plan**

```swift
func visibleFlagPlan(requiredLevels: Int, coveredLevels: Set<Int>) -> VisibleFlagPlan
```

Rules:

```text
uncovered empty           -> .none
all required uncovered    -> .canonical(note duration)
partial uncovered         -> .components(uncovered levels)
```

The formatter measures this plan and the engraver paints this same plan.

- [ ] **Step 6: Replace formatter tests that injected `visibleFlagDuration`**

Build natural isolated/fully-beamed/partially-covered documents and assert HPA-164 collision/row contracts remain green.

- [ ] **Step 7: Run**

```bash
swift test --package-path Packages/DrumNotation
```

- [ ] **Step 8: Commit**

```text
feat: move beam topology into DrumNotation
```

---

## Task 3: Add package engraving style, rows and final note/rest geometry

**Files:** `EngravingStyle.swift`, `EngravingTypes.swift`, `NotationEngraver.swift`, `NotationEngraverGeometryTests.swift`.

- [ ] **Step 1: Add failing style/row tests**

Pin two-row staff centers and `staffStep * staffSpace / 2` Y movement.

- [ ] **Step 2: Implement `NotationEngravingStyle`**

Use the exact fields in the design spec. Do not carry legacy notehead/rest box sizes, feel-mark size or warning size.

Provide a **public** `.standard` convenience suitable for standalone consumer examples/tests. Virgo production code must still map its current numeric style explicitly through `VirgoNotationProjection` rather than silently relying on `.standard`.

- [ ] **Step 3: Define immutable rows/primitives**

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

Define similarly focused immutable values for rest/stem/beam/flag/ledger/dot/articulation/control/tuplet/bar. Constructors may remain internal.

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

Forward tick-position interpolation to `FormattedNotation` rather than reimplementing it.

- [ ] **Step 5: Run topology → formatter once**

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

Virgo production code will call only this entry point.

- [ ] **Step 6: Build head/rest/ledger/dot geometry**

Use formatted X, package row Y, staff step, voice offsets and Bravura painted bounds. Dots use actual glyph bounds + formatter spacing, not legacy boxes.

- [ ] **Step 7: Normalize final Y exactly once in the package**

After building all raw primitives, calculate raw painted bounds. If `minY < 0`, translate every row and primitive by `-minY` before constructing `EngravedNotation`. Return normalized `paintedBounds`, `rows`, `contentHeight` and primitive coordinates. `DrumNotationView` must not apply an implicit second translation.

Add a regression proving a high cymbal/tuplet produces non-negative final bounds and that row center reported to consumers includes the same translation.

- [ ] **Step 8: Add content-bounds tests**

Every primitive must be contained by final `paintedBounds`, including high cymbal notes and lower-voice rests.

- [ ] **Step 9: Run and commit**

```bash
swift test --package-path Packages/DrumNotation --filter NotationEngraverGeometryTests
swift test --package-path Packages/DrumNotation
```

```text
feat: add package engraving geometry
```

---

## Task 4: Build stems, beams, flags and modifier/control/tuplet geometry

**Files:** `NotationEngraver.swift`, optional focused extensions if needed for readability, `NotationEngraverModifierTests.swift`; current Virgo builders are references until deletion.

- [ ] **Step 1: Add stem/head attachment tests**

Up/down isolated notes and same-stem seconds must attach to Bravura metrics on the undisplaced stem-side axis.

- [ ] **Step 2: Port flat percussion stem/beam geometry**

Move only the proven calculations from `NotationLayoutEngine+Beams.swift`; use package style/final head metrics, not `GameplayLayout` or app `Rendered*` values.

- [ ] **Step 3: Add beam-stack/hook geometry tests**

Assert beam-level spacing, stem extension, hook direction/length and one-row membership.

- [ ] **Step 4: Paint flags from Task 2's same plan**

Canonical isolated flags use duration-specific glyphs; partial uncovered levels use eighth components. Add an invariant that formatter-reserved flag bounds contain final flag ink.

- [ ] **Step 5: Port articulations**

For `.open`, position the package Bravura articulation from final notehead bounds; do not add new articulation types.

- [ ] **Step 6: Port controls**

Keep the existing cross-mark shape initially for stop/choke/damp while preserving kind, ID and resolved target staff step. X always uses logical-column X.

- [ ] **Step 7: Port tuplets**

Use resolved group membership. Preserve:

```text
entire group continuously beamed + no rests -> label only
otherwise                                   -> bracket + label
```

Cover up/down, bracket/no-bracket, rest member and triplet cases. No nested/general tuplets.

- [ ] **Step 8: Add bars/staff/clef/meter descriptors**

Derive bars from formatted measure bounds. Create row descriptors for five staff lines and percussion clef. Emit meter at each row start and whenever the resolved meter changes within a row; do not assume the whole chart has one app `TimeSignature`.

- [ ] **Step 9: Run and commit**

```bash
swift test --package-path Packages/DrumNotation
```

```text
feat: complete DrumNotation engraving primitives
```

---

## Task 5: Add complete `DrumNotationView` and public-consumer proof

**Files:** `Rendering/DrumNotationView.swift`, `PrimitiveViews.swift`, `DrumNotationViewTests.swift`, `PackageBoundaryTests.swift`.

- [ ] **Step 1: Add ordinary-import consumer test first**

Keep ordinary `import DrumNotation`:

```swift
@Test("public consumer engraves and constructs the static view")
func publicConsumerFlow() throws {
    let input = try ResolvedNotationInput(/* one 4/4 measure + note */)
    let layout = try NotationEngraver.engrave(input, style: .standard)
    #expect(layout.position(measureIndex: 0, localTick: 0)?.rowIndex == 0)
    _ = DrumNotationView(layout: layout)
}
```

No `@testable` or Virgo type may be required for this flow.

- [ ] **Step 2: Add narrow appearance boundary**

```swift
public struct NotationAppearance {
    public var foreground: Color
    public var secondaryBarOpacity: Double
}
```

No app `Palette` import.

- [ ] **Step 3: Move static primitive painters**

Paint staff/ledger/stems/beams/flags/notes/rests/dots/articulations/controls/tuplets/bars from package geometry; reuse `GlyphFill` for Bravura.

- [ ] **Step 4: Move percussion clef and meter painting**

Port existing visual behavior without a second font/resource system or environment-dependent sizing.

- [ ] **Step 5: Add raster/bounds coverage**

At least one flag/beam and one control/tuplet fixture must render inside final normalized `EngravedNotation.paintedBounds` with small AA tolerance.

- [ ] **Step 6: Run package-only**

```bash
swift test --package-path Packages/DrumNotation
```

Must pass without Virgo host, `Bundle.main`, `AppFonts.registerAll()` or repo-root resource paths.

- [ ] **Step 7: Commit**

```text
feat: add complete DrumNotation static view
```

---

## Task 6: Cut Virgo projection/preparation over to `NotationEngraver`

**Files:** `VirgoNotationProjection.swift`, delete `VirgoNotationProjection+Flags.swift`, `GameplayNotationPreparation.swift`, shrink `NotationLayout.swift`, create `VirgoTests/VirgoNotationProjectionTests.swift`, modify `GameplayNotationPreparationTests.swift` / installation tests as needed.

- [ ] **Step 1: Add red projection tests**

Assert mapping of voice, beat groups/meter, exact duration ticks, open articulation, stop/choke/damp target staff override, supported tuplets, deterministic tuplet ordinal IDs, and swing/shuffle feel-pair omission.

- [ ] **Step 2: Replace app formatting mapper with one engraving-style mapper**

```swift
static func engravingStyle(
    rowWidth: CGFloat,
    style: NotationLayoutStyle
) -> NotationEngravingStyle
```

Embed HPA-164 formatting values plus current row/stem/beam/rest/control/tuplet/bar/clef/meter values. This is the only app site constructing package style.

- [ ] **Step 3: Update resolved projection**

Resolve app-only semantics before the boundary. Never pass `RhythmLayoutSnapshot`, `RhythmMeasure`, `RhythmTupletID`, `NotationControlEventKind`, `DrumType` or lane IDs into the package.

- [ ] **Step 4: Delete Virgo flag prepass**

Remove `visibleFlagClassifications` and delete `VirgoNotationProjection+Flags.swift` after package topology tests are green.

- [ ] **Step 5: Replace transitional preparation**

Target:

```swift
struct GameplayNotationPreparedState: Sendable {
    let engraving: EngravedNotation
    let annotations: GameplayNotationAnnotations
}
```

Preparation becomes expand measures → project input/style → `NotationEngraver.engrave` → build only app feel/warning annotations from analysis + package final measure/row bounds.

Delete `ComposedNotation`, `RebuiltArtifacts`, package-X lookup dictionaries, `composeVirgoLayout`, `rebuiltArtifacts`, `finalizationInput`.

- [ ] **Step 6: Keep annotations honest**

`GameplayNotationAnnotations` may contain only app warning/feel values. It must not reconstruct notes/rests/beams/bars/tuplets/controls.

- [ ] **Step 7: Run focused tests**

```bash
xcodebuild test \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'platform=macOS' \
  -parallel-testing-enabled NO \
  -only-testing:VirgoTests/VirgoNotationProjectionTests \
  -only-testing:VirgoTests/GameplayNotationPreparationTests \
  -only-testing:VirgoTests/GameplayNotationInstallationTests
```

- [ ] **Step 8: Commit**

```text
refactor: consume DrumNotation engraver from Virgo
```

---

## Task 7: Replace Virgo's static notation tree with `DrumNotationView`

**Files:** `GameplaySheetMusicView.swift`, create `GameplayNotationAnnotationViews.swift`, delete `NotationPrimitiveViews.swift`, viewmodel notation/visual update files as needed, mounting/playhead tests.

- [ ] **Step 1: Update mounting test first**

Require one package `DrumNotationView` inside the generation-equatable static tree and keep live playhead outside it.

- [ ] **Step 2: Change static input**

Carry `EngravedNotation`, annotations, generation and only non-notation legacy fallback values. Notation width/height/row geometry comes from package output.

- [ ] **Step 3: Replace notation layers**

Conceptual branch:

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

The parent keeps separate `GameplayPlayheadBarView`.

- [ ] **Step 4: Make row anchors consume normalized package rows**

Use `EngravedRow.bounds` directly. Delete notehead-derived top padding and notation-branch `GameplayLayout` staff-center reconstruction.

- [ ] **Step 5: Update playhead Y alignment**

X/row comes from `EngravedNotation.position`; Y comes from final normalized `EngravedNotation.rows`. Keep clock→musical-position conversion in Virgo. Add multi-row wrap coverage.

- [ ] **Step 6: Move only warning/feel views to annotation file**

Preserve app copy/theme there.

- [ ] **Step 7: Delete app static notation view types**

Remove notation-side `GameplayDrumNotationView`, package-replaced bar/clef/meter views and obsolete compatibility wrappers. Keep the non-notation fallback.

- [ ] **Step 8: Run**

```bash
xcodebuild test \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'platform=macOS' \
  -parallel-testing-enabled NO \
  -only-testing:VirgoTests/GameplaySheetMusicMountingTests \
  -only-testing:VirgoTests/DrumTabPlayheadAlignmentTests
```

- [ ] **Step 9: Commit**

```text
refactor: mount package notation view
```

---

## Task 8: Delete app engraving implementations and migrate pure tests

**Files:** delete `NotationBeamTopology.swift`; reduce/delete reusable code from beam/control/rest/rhythm-rendering engine extensions and `NotationLayout.swift`; migrate/delete pure app geometry tests.

- [ ] **Step 1: Search transitional symbols**

```bash
rg 'NotationBeamTopologyBuilder|buildBeams\(|buildStems\(|buildFlags\(|buildLedgerLines\(|buildRests\(|buildStopNotes\(|buildTuplets\(|GameplayDrumNotationView|NotationNoteHeadView|NotationBeamView' Virgo VirgoTests
```

Classify every hit before deletion.

- [ ] **Step 2: Delete app topology + pure topology tests**

Only after package `BeamTopologyTests` covers current cases plus HPA-166 parity fixtures.

- [ ] **Step 3: Remove package-replaced engine helpers**

Do not delete warning/feel helpers still used for app annotations; relocate them to an honest app annotation file if an old engine file becomes misleading.

- [ ] **Step 4: Retire app rendered primitive types**

Remove `RenderedNoteHead`, `RenderedRest`, `RenderedStem`, `RenderedBeam`, `RenderedFlag`, `RenderedLedgerLine`, `RenderedMeasureBar`, `RenderedRhythmDot`, `RenderedArticulation`, `RenderedStopNote`, `RenderedTuplet` after callers are gone. Keep/relocate only app annotation/domain values.

- [ ] **Step 5: Preserve source-semantic tests**

Keep `ChartControlEventTests` / DTX control import tests because source lane semantics remain Virgo-owned.

- [ ] **Step 6: Run package + focused app regression**

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

Move/delete `NotationLayoutControlRenderingTests` only to the extent its assertions are pure package geometry; retain any source/projection semantics at app level.

- [ ] **Step 7: Re-run symbol search**

Expected: no Virgo production hit for package-owned topology/builders/views.

- [ ] **Step 8: Commit**

```text
refactor: retire app engraving renderer
```

---

## Task 9: Complete parity fixtures, real-chart evidence, docs and CI

**Files:** package parity/reference tests, package README, real fixture/golden/invariant/render-probe tests, existing CI workflow if necessary.

- [ ] **Step 1: Audit all eleven logical fixture categories**

```text
mixed 8th/16th
mixed 16th/32nd
forward hook
backward hook
isolated flags (up and down)
dotted note/rest
triplet/tuplet
6/8 compound grouping
simultaneous upper/lower voices
stop/choke/damp adjacent to notes
multi-row dense passage
```

Expand the multi-case categories (both flag directions, note/rest dots, three control kinds) into separate concrete assertions where that improves failure diagnosis.

- [ ] **Step 2: Decide if executable VexFlow evidence is needed**

If pinned VexFlow 5.0.0 source/behavior makes all expectations unambiguous, add **no** Node tooling. If a disputed case remains, add the smallest package-local pinned script + committed artifact for only that case and a Swift test that consumes it. A generator with no consumer is out of scope.

- [ ] **Step 3: Update package README**

Document final public flow:

```swift
let input = try ResolvedNotationInput(...)
let layout = try NotationEngraver.engrave(input, style: .standard)
let position = layout.position(measureIndex: 0, localTick: 240)
let view = DrumNotationView(layout: layout)
```

Also document dependency direction and VexFlow/Bravura reference versions; Virgo owns rhythm inference/playback/scrolling.

- [ ] **Step 4: Run dense + sparse real-DTX fixtures**

Verify event identity, rows, bars, controls and playhead lookup through the existing app harness; do not build a package DTX importer.

- [ ] **Step 5: Exercise wrap widths**

Use the 900pt floor plus at least one production-supported width that changes row packing. Package rows, mounted anchors and playhead row must agree.

- [ ] **Step 6: Regenerate goldens only after structural tests are green**

Review every changed value/image; reject unrelated churn.

- [ ] **Step 7: Verify CI explicitly runs package tests**

If the existing workflow already runs:

```bash
swift test --package-path Packages/DrumNotation
```

leave CI unchanged. Otherwise add it to the existing test workflow; no new performance/release workflow.

- [ ] **Step 8: Commit**

```text
test: lock DrumNotation renderer parity
```

---

## Task 10: Final production verification and PR readiness gate

- [ ] **Step 1: Package suite**

```bash
swift test --package-path Packages/DrumNotation
```

- [ ] **Step 2: Full serial macOS suite**

```bash
xcodebuild test \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'platform=macOS' \
  -parallel-testing-enabled NO
```

- [ ] **Step 3: Mounted macOS visual smoke**

Use dense real DTX, sparse chart, and at least two widths. Inspect stem/head attachment, beam/hook direction, dots/rests/tuplets, controls, bar/clef/meter alignment, clipping/collisions and playhead alignment.

- [ ] **Step 4: iPad/iOS simulator compile gate**

```bash
xcodebuild build \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO
```

- [ ] **Step 5: SwiftLint**

Use the repository's existing lint command/workflow. Fix HPA-166-touched violations only.

- [ ] **Step 6: Ownership searches**

```bash
rg 'import (Virgo|SwiftData)|GameplayLayout|Palette|AppFonts|RhythmLayoutSnapshot|DrumType' Packages/DrumNotation/Sources
rg 'NotationBeamTopologyBuilder|GameplayDrumNotationView|NotationNoteHeadView|NotationBeamView' Virgo
```

Expected: no package app-dependency leaks and no superseded renderer/topology production symbols.

- [ ] **Step 7: Self-review HPA-166 acceptance criteria**

Confirm package-owned reusable engraving/static drawing, ordinary-import consumer, package-only resources, generation isolation, removal of app transitional geometry, beam/hook fixtures, correct stem/head attachment, modifier/control/tuplet coverage, real mounted smoke, iPad build, and no HPA-584/performance scope.

- [ ] **Step 8: Mark this same PR ready only after every gate passes**

Do not open a second implementation PR for HPA-166.
