# HPA-581 Gameplay Notation Preparation and Static Rendering Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans`. Steps use checkbox syntax for tracking.

**Goal:** First isolate static gameplay notation from 30 Hz playback observation with one enforced layout-install generation, then re-profile. Only if the measured ~268 ms timeline layout/beat preparation remains worth the lifecycle/call-site churn, move that pure work off `@MainActor` through one Sendable request/result and one stale-generation guard.

**Architecture:** Keep `GameplayViewModel` as the screen facade. Phase A is concurrency-free: one notation install funnel advances one layout generation, a file-local Equatable static child owns every O(note/measure) static derivation and row anchor, and the playhead gets position only. Phase B re-profiles. Conditional phases then remove worker-facing model identity, introduce one pure preparer around the existing `NotationLayoutEngine`, and make setup async with generation invalidation in `cleanup()`. No pre-readiness width retry loop; the existing 0.5 pt tolerance + 100 ms debounce remains the width policy.

**Tech Stack:** Swift 6, SwiftUI Observation, SwiftData, Swift Concurrency (conditional phase), Swift Testing/XCTest, Xcode/macOS `xcodebuild`, Instruments.

## Global constraints

- HPA-579 is the evidence authority: HPA-581 was **Proceed** for measured gameplay preparation/static rendering only.
- Static isolation ships before async setup churn because it is independent and affects recurring playback work.
- HPA-581 may narrow/close after the static-phase re-profile if the remaining preparation work no longer has enough value to justify async migration; that narrowing is explicitly allowed by the Linear ticket.
- HPA-584 does not preempt HPA-581; virtualization remains the post-HPA-581 evidence decision.
- Keep SwiftData extraction, `RhythmTimelineResolver`, `RhythmLayoutSnapshotBuilder`, runtime model lookups, legacy layout, observable assignment, BGM, metronome, and input on `@MainActor`.
- Do not make `NotationLayoutInput` Sendable; `.legacy` contains `[Note]`.
- Do not use `@unchecked Sendable`.
- Do not add a notation actor/service/scheduler/registry/worker pool/repository-use-case layer.
- Do not add a benchmark harness or CI performance gate.
- Do not add row virtualization.
- Do not add pre-readiness width re-dispatch/retry logic. Seed the initial width exactly as today; if geometry changes while a later worker runs, the existing prepared-sheet width handler/debounce performs one normal repack.
- Post-prepared width relayout remains synchronous unless a real Release packing-changing resize proves material main-thread cost.
- Run tests with parallel testing disabled because existing suites share SwiftData/audio/global-state seams.

---

# Phase A — Static rendering isolation, no concurrency

## Task 1: Enforce one notation-layout install funnel and generation

**Files:**
- Modify: `Virgo/viewmodels/GameplayViewModel.swift`
- Modify: `Virgo/viewmodels/GameplayViewModel+Computations.swift`
- Test: `VirgoTests/GameplayViewModelLayoutComputationsTests.swift`
- Test: `VirgoTests/GameplayViewModelDataLoadingTests.swift` or the smallest existing suite that covers fatal/no-track setup paths

### Step 1.1 — Characterize every production write/reset

- [ ] Use `rg -n 'cachedNotationLayout\s*=' Virgo` and confirm all production write paths before editing.
- [ ] At minimum cover:
  - normal layout install in `cacheNotationLayout()`;
  - no-track/empty reset;
  - fatal-rhythm-timing reset in `setupGameplay()`.
- [ ] Do not treat test-only direct assignment as a production writer, but plan to migrate tests if the setter becomes inaccessible.

### Step 1.2 — Write generation-invariant tests first

Add deterministic tests proving:

- [ ] normal notation install advances the generation;
- [ ] empty/no-track reset advances the generation;
- [ ] fatal-timing reset advances the generation;
- [ ] two different installs produce different generations;
- [ ] the generation cannot be assigned directly by callers.

No sleeps/tasks are needed.

### Step 1.3 — Add the single install seam

Implement one view-model seam, exact spelling flexible:

```swift
func installNotationLayout(_ layout: NotationLayout) {
    notationLayoutStorage = layout
    notationLayoutGeneration &+= 1
}
```

Requirements:

- [ ] backing layout storage is not directly writable by production extensions/callers;
- [ ] `notationLayoutGeneration` is read-only outside the view model;
- [ ] keep a read-only `cachedNotationLayout` compatibility accessor if it reduces consumer churn;
- [ ] route normal install, no-track reset, and fatal reset through the same seam;
- [ ] later async worker install must reuse this same funnel (or a widened coherent-state version of it), not create a second generation path.

Do **not** create a new observable manager/service just to hold the generation.

### Step 1.4 — Verify

```bash
xcodebuild test -project Virgo.xcodeproj -scheme Virgo \
  -destination 'platform=macOS' -configuration Debug \
  -only-testing:VirgoTests/GameplayViewModelLayoutComputationsTests \
  -only-testing:VirgoTests/GameplayViewModelDataLoadingTests \
  -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -destination-timeout 300 -derivedDataPath ./DerivedData
```

- [ ] If another focused existing suite is the actual fatal/no-track owner, substitute/add it and record why.

### Step 1.5 — Commit

```bash
git add Virgo/viewmodels VirgoTests
git commit -m "refactor(HPA-581): centralize notation layout installation"
```

---

## Task 2: Remove `AnyView` caches and isolate the complete static sheet

**Files:**
- Modify: `Virgo/viewmodels/GameplayViewModel.swift`
- Modify: `Virgo/viewmodels/GameplayViewModel+Computations.swift`
- Modify: `Virgo/views/subviews/GameplaySheetMusicView.swift`
- Test: `VirgoTests/GameplaySheetMusicMountingTests.swift`
- Test: `VirgoTests/GameplayViewModelLayoutComputationsTests.swift`
- Test as useful: `VirgoTests/DrumTabPlayheadAlignmentTests.swift`

### Step 2.1 — Add static-boundary regressions first

- [ ] Capture the installed layout generation/static input.
- [ ] Mutate only high-frequency playback state (playhead position/current playback tick) and assert static generation/input identity is unchanged.
- [ ] Install a new layout and assert the static child's generation differs.
- [ ] Preserve the existing mounting/raster smoke.
- [ ] Preserve row-anchor/auto-scroll expectations with the anchor column relocated under the static child.

### Step 2.2 — Delete presentation caching from the view model

- [ ] Delete `staticStaffLinesView`.
- [ ] Delete `notationStaffLinesView`.
- [ ] Delete `cacheNotationStaffLinesView()` and all `AnyView(StaffLinesBackgroundView(...))` creation.
- [ ] Construct `StaffLinesBackgroundView` directly in the static child from immutable inputs.

### Step 2.3 — Extract a real Equatable child

Create a private/file-local type such as:

```swift
private struct GameplayStaticNotationView: View, Equatable {
    let layout: NotationLayout
    let legacyMeasurePositions: [GameplayLayout.MeasurePosition]
    let timeSignature: TimeSignature
    let generation: UInt64

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.generation == rhs.generation
    }
}
```

Exact inputs may differ. Requirements:

- [ ] child receives no `GameplayViewModel`;
- [ ] equality compares only the installed layout generation;
- [ ] use `.equatable()` (or equivalent); do **not** use `.id(generation)`;
- [ ] every static notation layer moves under this child: staff lines, bars, clefs/time signatures, noteheads, stems, beams, flags, rests, ledger lines, articulations, stop notes, tuplets, feel marks, warnings, etc.;
- [ ] move `rowAnchorColumn` under this child too;
- [ ] `GameplayPlayheadBarView` becomes `GameplayPlayheadBarView(position:)` and receives no view model;
- [ ] auto-scroll hooks stay in the observable container.

### Step 2.4 — Put O(note/measure) derivations behind the Equatable boundary

The live container must **not** perform these on every playhead update:

- [ ] `sheetMeasurePositions` / `measurePositions(from:)` mapping;
- [ ] `sheetRowCount` measure-row scan;
- [ ] `spacingAboveLine5` note-head scan;
- [ ] printed-rest filtering;
- [ ] row-anchor construction;
- [ ] other array-building/static filtering needed only for the sheet tree.

Move them into `GameplayStaticNotationView.body` or a static immutable input constructed only when generation changes.

Keep the observable container limited to:

- [ ] playhead position;
- [ ] `currentRow` / `isPlaying`;
- [ ] generation + immutable static inputs;
- [ ] O(1) frame values already stored by `NotationLayout`, e.g. `contentWidth`, `totalHeight`, and top inset from `paintedBounds`;
- [ ] minimal renderability predicate for auto-scroll.

Do **not** create duplicate caches for every derived value unless the implementation naturally needs one small immutable static projection. The performance rule is “no O(n) static walk in the 30 Hz container body,” not “cache every scalar.”

### Step 2.5 — Verify focused rendering behavior

```bash
xcodebuild test -project Virgo.xcodeproj -scheme Virgo \
  -destination 'platform=macOS' -configuration Debug \
  -only-testing:VirgoTests/GameplaySheetMusicMountingTests \
  -only-testing:VirgoTests/GameplayViewModelLayoutComputationsTests \
  -only-testing:VirgoTests/DrumTabPlayheadAlignmentTests \
  -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -destination-timeout 300 -derivedDataPath ./DerivedData
```

### Step 2.6 — Commit

```bash
git add Virgo/viewmodels Virgo/views/subviews/GameplaySheetMusicView.swift VirgoTests
git commit -m "refactor(HPA-581): isolate static gameplay notation"
```

---

# Phase B — Re-profile before concurrency

## Task 3: Measure the static-only result and decide whether async setup still pays

**Production files:** none expected.

Use the same HPA-579 representative chart when available:

- `soukyuu_e_no_shouka` MASTER / Expert;
- 2,870 notes;
- 156 measures;
- 900 pt baseline row width;
- Release macOS on the same machine/configuration when practical.

### Step 3.1 — Record the static-isolation result

Measure/record:

- [ ] chart selection → gameplay prepared;
- [ ] main-thread samples in `cacheNotationLayout` / notation layout / beat-position preparation;
- [ ] initial production `GameplayView` mount versus **4,890.729 ms**;
- [ ] playback main-thread/SwiftUI activity, specifically whether the static sheet body still broadly evaluates with playhead ticks;
- [ ] production auto-scroll correctness.

### Step 3.2 — Apply the HPA-581 gate

**Proceed to Phase C/D** when the timeline-native notation layout + beat-position slice remains a material main-actor stall. HPA-579's **267.857 ms** baseline already says it was material; this checkpoint ensures the decision still reflects the code after Phase A.

The user-facing reason for proceeding must be stated correctly:

- freeing ~268 ms of main-actor CPU keeps the loading/window/dismiss surface responsive while preparation runs;
- because readiness still needs the layout, **do not promise a shorter chart-selection-to-ready wall-clock time** solely from the detached task.

**Narrow/close HPA-581 after Phase A** only if the new profile shows the remaining preparation work no longer justifies converting the widespread `setupGameplay()` test/call surface to async. Record that explicit narrowing in HPA-581/HPA-579.

Do not start HPA-584 before this gate is resolved.

---

# Phase C — Conditional worker value boundary

> Execute Phase C only when Task 3 says Proceed.

## Task 4: Remove model identity and make the timeline/render graph safely Sendable

**Files:**
- Modify: `Virgo/models/RhythmMetadata.swift`
- Modify: `Virgo/models/ChartControlEvent.swift` **only for `NotationControlEventKind` / `NotationControlEvent`; do not add Sendable to the SwiftData `ChartControlEvent` model**
- Modify: `Virgo/layout/RhythmLayoutSnapshotBuilder.swift`
- Modify: `Virgo/layout/NotationLayout.swift`
- Modify: `Virgo/layout/NotationRhythmRendering.swift`
- Modify: `Virgo/layout/NotationLayoutEngine.swift`
- Modify as compiler requires: immutable value-definition files referenced by the timeline graph
- Modify: `Virgo/viewmodels/GameplayViewModel+Computations.swift`
- Test: `VirgoTests/RhythmLayoutSnapshotBuilderTests.swift`
- Test: `VirgoTests/NotationLayoutEngineTests.swift`
- Test: `VirgoTests/NotationLayoutNotePositionOverrideTests.swift`
- Test: `VirgoTests/DrumTabGoldenTests.swift`
- Test: `VirgoTests/DrumTabRegressionInvariantTests.swift`
- Test: `VirgoTests/DrumTabPlayheadAlignmentTests.swift`

### Step 4.1 — Add two independent boundary gates

Compile-time gate:

```swift
private func requireSendable<T: Sendable>(_: T.Type) {}

requireSendable(RhythmLayoutSnapshot.self)
requireSendable(NotationLayout.self)
requireSendable(NotationLayoutStyle.self)
```

Structural gate:

- [ ] Reuse the repository's existing Mirror/omitted-API test style.
- [ ] Build representative `RhythmLayoutNote` / `RenderedNoteHead` values and assert no `sourceObjectID` field is exposed.
- [ ] Confirm this structural assertion is RED on current code even if some `Sendable` assertions compile.

`ObjectIdentifier` itself can be Sendable; compiler success is not semantic proof.

### Step 4.2 — Remove worker-facing model identity

- [ ] Remove `RhythmLayoutNote.sourceObjectID`.
- [ ] Stop creating it in `RhythmLayoutSnapshotBuilder`.
- [ ] Remove `RenderedNoteHead.sourceObjectID`.
- [ ] Keep `RhythmEventID` as timeline source identity.
- [ ] Timeline dropped-note diagnostics use rendered event IDs vs `GameplayRhythmRuntime.noteByEventID` on `@MainActor`.
- [ ] Legacy dropped-note diagnostics explicitly degrade to count + representative metadata when exact object identity is unavailable.

Reasoning to preserve in code review/tests:

- `RenderedNoteHead.id: UInt64` remains the rendered `Identifiable`/Hashable discriminator;
- removing `sourceObjectID` does not remove the stable rendered ID used by existing equatable note-head views;
- the goldens/invariants confirm no geometry/digest regression.

### Step 4.3 — Propagate normal Sendable conformances

- [ ] Add `Sendable` only to immutable value enums/structs the compiler proves safe.
- [ ] `ChartControlEvent.swift`: touch only `NotationControlEventKind` / `NotationControlEvent` as required.
- [ ] Do not use `@unchecked Sendable`.

### Step 4.4 — Run identity-sensitive gates immediately

First focused value/layout tests:

```bash
xcodebuild test -project Virgo.xcodeproj -scheme Virgo \
  -destination 'platform=macOS' -configuration Debug \
  -only-testing:VirgoTests/RhythmLayoutSnapshotBuilderTests \
  -only-testing:VirgoTests/NotationLayoutEngineTests \
  -only-testing:VirgoTests/NotationLayoutNotePositionOverrideTests \
  -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -destination-timeout 300 -derivedDataPath ./DerivedData
```

Then production-layout geometry/identity gates **before async wiring**:

```bash
xcodebuild test -project Virgo.xcodeproj -scheme Virgo \
  -destination 'platform=macOS' -configuration Debug \
  -only-testing:VirgoTests/DrumTabGoldenTests \
  -only-testing:VirgoTests/DrumTabRegressionInvariantTests \
  -only-testing:VirgoTests/DrumTabPlayheadAlignmentTests \
  -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -destination-timeout 300 -derivedDataPath ./DerivedData
```

### Step 4.5 — Commit

```bash
git add Virgo VirgoTests
git commit -m "refactor(HPA-581): make timeline notation values sendable"
```

---

## Task 5: Introduce one pure preparation request/result

**Files:**
- Create: `Virgo/layout/GameplayNotationPreparation.swift`
- Create: `VirgoTests/GameplayNotationPreparationTests.swift`
- Modify: `Virgo.xcodeproj/project.pbxproj`
- Reuse: `Virgo/layout/NotationLayoutEngine.swift`

### Step 5.1 — Write non-tautological preparer seam tests

Add tests for:

- [ ] request and result compile as `Sendable`;
- [ ] pinned beat rhythm positions produce pinned expected rendered coordinates across at least two measures/rows;
- [ ] empty/no-playable timeline input preserves current empty/renderable semantics;
- [ ] no worker request/result value exposes model identity.

Do **not** add “preparer layout equals `NotationLayoutEngine.layout` for the same input” as the primary equivalence test; the preparer calls that engine, so the assertion is tautological. `DrumTabGoldenTests` / `DrumTabRegressionInvariantTests` own layout equivalence.

The view-model installed-state equivalence test belongs in Task 6 after the setup seam changes.

### Step 5.2 — Implement the minimal pure boundary

Add:

```swift
struct GameplayNotationPreparationRequest: Sendable { ... }
struct GameplayNotationPreparedState: Sendable { ... }
struct GameplayNotationPreparer {
    static func prepare(_ request: GameplayNotationPreparationRequest) -> GameplayNotationPreparedState
}
```

Requirements:

- [ ] request contains only timeline-safe immutable values: snapshot, measure count, style/row width, note-position overrides, beat rhythm positions;
- [ ] construct `NotationLayoutInput(timing: .timeline(...))` **inside** the preparer;
- [ ] call the existing `NotationLayoutEngine`;
- [ ] reuse the existing timeline `TabGrid`/measure beat-position calculation; do not fork math;
- [ ] result contains `NotationLayout` + beat positions and only existing hot/coherent lookup values that belong together;
- [ ] no SwiftData, `ModelContext`, `ObjectIdentifier`, SwiftUI view, observable reference, or actor-isolated service.

### Step 5.3 — Verify and commit

```bash
xcodebuild test -project Virgo.xcodeproj -scheme Virgo \
  -destination 'platform=macOS' -configuration Debug \
  -only-testing:VirgoTests/GameplayNotationPreparationTests \
  -only-testing:VirgoTests/NotationLayoutEngineTests \
  -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -destination-timeout 300 -derivedDataPath ./DerivedData
```

```bash
git add Virgo/layout/GameplayNotationPreparation.swift \
  VirgoTests/GameplayNotationPreparationTests.swift \
  Virgo.xcodeproj/project.pbxproj
git commit -m "feat(HPA-581): add pure notation preparation boundary"
```

---

# Phase D — Conditional off-main setup

> Execute Phase D only when Task 3 says Proceed.

## Task 6: Dispatch initial timeline preparation off-main, guard cleanup, keep width simple

**Files:**
- Modify: `Virgo/viewmodels/GameplayViewModel.swift`
- Modify: `Virgo/viewmodels/GameplayViewModel+Computations.swift`
- Modify: `Virgo/viewmodels/GameplayViewModel+Playback.swift`
- Modify: `Virgo/views/GameplayView.swift`
- Modify: all production/test call sites found by `rg -n 'setupGameplay\(' Virgo VirgoTests`
- Test: `VirgoTests/GameplayViewModelLayoutComputationsTests.swift`
- Test: `VirgoTests/GameplayViewModelCleanupTests.swift`
- Test as compiler identifies: existing setup/cleanup/input/audio/playback suites calling `setupGameplay()`

### Step 6.1 — Write deterministic lifecycle/apply tests first

Add tests for the apply seam:

1. [ ] generation N result cannot install after generation N+1 exists;
2. [ ] generation N+1 result installs through the same notation install/coherent-state funnel;
3. [ ] call `cleanup()` after allocating/in-flight generation N, then attempt N completion; it cannot reinstall notation or set `isGameplayPrepared = true`;
4. [ ] representative timeline setup produces the same pinned layout row maps/note-head positions/beat positions as the established synchronous/golden baseline.

Drive the apply rule directly. Do not race real detached tasks or sleep.

### Step 6.2 — Make setup awaitable only now

- [ ] Change `setupGameplay(loadPersistedSpeed:)` to `async`.
- [ ] Update `GameplayView.prepareGameplay(initialRowWidth:)` to `await vm.setupGameplay(...)`.
- [ ] Mechanically update all current test/production callers to `await`; make tests async where needed.
- [ ] Keep one production setup API; do not add a sync wrapper merely to avoid test edits.

This migration is intentionally delayed until profiling confirms the value because the call surface is widespread.

### Step 6.3 — Add one generation counter for worker freshness

- [ ] Reuse the notation/layout generation when it cleanly represents the worker request lifecycle, or add one clearly named notation-preparation generation if the install-generation semantics differ. Do **not** add multiple tokens/registries.
- [ ] Starting async preparation advances the authoritative stale-request generation.
- [ ] Completion applies only when captured generation is current.
- [ ] Optional task cancellation is cleanup/resource control only.

Keep the design to one stale-result mechanism.

### Step 6.4 — Invalidate on cleanup

In `GameplayViewModel+Playback.swift`:

- [ ] `cleanup()` invalidates/advances the preparation generation before/while tearing down gameplay;
- [ ] cancel a retained in-flight task if one exists, only to save work;
- [ ] `isGameplayPrepared = false` remains part of cleanup;
- [ ] a detached completion after cleanup fails the generation check and cannot resurrect readiness.

### Step 6.5 — Dispatch only timeline-native pure work

On `@MainActor`:

- [ ] compute drum beats;
- [ ] use the currently seeded/floored `cachedLayoutRowWidth`;
- [ ] build `GameplayNotationPreparationRequest` from the already-built timeline snapshot + immutable inputs;
- [ ] keep SwiftData/resolver/model maps on main.

Execute:

```swift
let prepared = await Task.detached(priority: .userInitiated) {
    GameplayNotationPreparer.prepare(request)
}.value
```

Back on `@MainActor`:

- [ ] generation check;
- [ ] install through the single coherent notation install funnel;
- [ ] set readiness only for a current result;
- [ ] preserve BGM/metronome/input ordering unless tests justify a change.

Legacy `NotationLayoutInput` stays synchronous on-main.

### Step 6.6 — Do **not** add pre-readiness width freshness retries

Keep today's width policy:

- [ ] `GameplayView.prepareGameplay(initialRowWidth:)` seeds width immediately before setup;
- [ ] `updateRowWidth` keeps its `> 0.5` pt tolerance;
- [ ] prepared-sheet `onAppear` / geometry change keeps the 100 ms trailing-edge debounce;
- [ ] if width changed while the worker ran, install the current-generation initial result, then let that existing path perform one normal repack.

No “generation + exact row-width match → re-dispatch until equal” loop.

### Step 6.7 — Verify focused behavior

```bash
xcodebuild test -project Virgo.xcodeproj -scheme Virgo \
  -destination 'platform=macOS' -configuration Debug \
  -only-testing:VirgoTests/GameplayViewModelLayoutComputationsTests \
  -only-testing:VirgoTests/GameplayViewModelCleanupTests \
  -only-testing:VirgoTests/GameplayViewTests \
  -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -destination-timeout 300 -derivedDataPath ./DerivedData
```

- [ ] Also run every suite mechanically changed for the new `await` at least once before final verification.

### Step 6.8 — Commit

```bash
git add Virgo/viewmodels Virgo/views/GameplayView.swift VirgoTests
git commit -m "feat(HPA-581): prepare timeline notation off main actor"
```

---

## Task 7: Keep post-prepared width relayout evidence-gated

**Files:** production changes only if evidence justifies them.

### Step 7.1 — Preserve existing debounce by default

- [ ] Keep row-width normalization/floor semantics.
- [ ] Keep the existing 100 ms trailing-edge debounce.
- [ ] Keep current test-immediate behavior.

### Step 7.2 — Attempt a real Release packing-changing resize

- [ ] Use a natural host/window size; do not treat the synthetic 3,000 pt probe from HPA-579 as user-resize proof.
- [ ] If no real host width changes row packing, record **not measurable / no change** and stop.
- [ ] If row packing changes, profile the post-debounce layout CPU.

### Step 7.3 — Only if material

If and only if profiling shows material main-thread cost:

- [ ] route timeline relayout through the existing `GameplayNotationPreparer`;
- [ ] reuse the same stale-request generation;
- [ ] latest width wins;
- [ ] cancellation is cleanup only;
- [ ] add deterministic out-of-order width-result coverage.

Otherwise make no production change.

---

# Final verification

## Task 8: Strict concurrency, regression, known baseline, and Release handoff

### Step 8.1 — Strict concurrency build (worker path only)

If Phase C/D ran:

```bash
xcodebuild build -project Virgo.xcodeproj -scheme Virgo \
  -destination 'platform=macOS' -configuration Debug \
  SWIFT_STRICT_CONCURRENCY=complete \
  ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath ./DerivedData
```

- [ ] Fix compiler-proven violations by narrowing/copying immutable values.
- [ ] Compiler success does not replace the structural `sourceObjectID` regression.

### Step 8.2 — Focused high-value suites

Always run static/layout coverage; include worker suites when those files exist:

```bash
xcodebuild test -project Virgo.xcodeproj -scheme Virgo \
  -destination 'platform=macOS' -configuration Debug \
  -only-testing:VirgoTests/GameplayViewModelLayoutComputationsTests \
  -only-testing:VirgoTests/GameplaySheetMusicMountingTests \
  -only-testing:VirgoTests/DrumTabGoldenTests \
  -only-testing:VirgoTests/DrumTabRegressionInvariantTests \
  -only-testing:VirgoTests/DrumTabPlayheadAlignmentTests \
  -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -destination-timeout 300 -derivedDataPath ./DerivedData
```

If worker work proceeded, also include:

- `GameplayNotationPreparationTests`;
- `RhythmLayoutSnapshotBuilderTests`;
- `NotationLayoutEngineTests`;
- `GameplayViewModelCleanupTests`.

### Step 8.3 — Full suite with explicit known-red policy

```bash
xcodebuild test -project Virgo.xcodeproj -scheme Virgo \
  -destination 'platform=macOS' -configuration Debug \
  -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -destination-timeout 300 -derivedDataPath ./DerivedData
```

Clean `main` has a known nondeterministic detached-context SwiftData crash involving `\Chart.difficulty`.

If and only if the full suite hits that exact failure:

1. [ ] run the identical command on clean `main`;
2. [ ] confirm the same stack/signature;
3. [ ] record it as baseline.

Any other failure remains an HPA-581 regression until independently disproven. Do not waive failures by vague resemblance to “SwiftData flake.”

### Step 8.4 — Final Release profile

Repeat HPA-579's representative identity and record:

- [ ] chart selection → gameplay prepared;
- [ ] main-thread preparation samples;
- [ ] initial mount versus **4,890.729 ms**;
- [ ] playback/static-body activity after Equatable isolation;
- [ ] auto-scroll correctness;
- [ ] real width-relayout result/limitation;
- [ ] if worker shipped, confirm timeline layout/beat-position CPU is absent from the main-thread preparation slice.

If worker shipped, do **not** claim that moving CPU off-main necessarily reduced readiness wall-clock. Report the actual before/after number and the main-thread responsiveness result separately.

### Step 8.5 — Record Linear result / HPA-584 handoff

Add an HPA-581 comment containing:

- [ ] static isolation summary;
- [ ] install-generation invariant;
- [ ] Phase-B Proceed/Narrow decision;
- [ ] whether async preparation shipped;
- [ ] before/after preparation + mount numbers;
- [ ] focused/strict/full-suite result, including exact known baseline reproduction if encountered;
- [ ] width-relayout decision;
- [ ] explicit HPA-584 handoff if eager initial mount remains dominant.

---

## Completion checklist

- [ ] One enforced notation install funnel advances every layout/reset generation.
- [ ] Static notation is a file-local Equatable child keyed by that generation.
- [ ] Row anchors and every O(note/measure) static derivation are behind the Equatable boundary.
- [ ] Playhead receives position only; auto-scroll observation stays narrow.
- [ ] `staticStaffLinesView` / `notationStaffLinesView` and `AnyView` presentation caches are removed.
- [ ] Static-only Release result is measured before async setup migration.
- [ ] If remaining preparation is not worth the churn, HPA-581 narrows/closes with evidence.
- [ ] If it is worth the churn, timeline-native layout + beat positions move off-main through one Sendable request/result.
- [ ] Worker graph contains no SwiftData, `ModelContext`, `ObjectIdentifier`, or SwiftUI views; no `@unchecked Sendable`.
- [ ] `sourceObjectID` removal is structurally tested and legacy diagnostic degradation is explicit.
- [ ] If async setup ships, one generation rejects stale completion and `cleanup()` invalidates it.
- [ ] No pre-readiness width retry state machine is introduced.
- [ ] Post-prepared relayout only changes with real evidence.
- [ ] Identity-sensitive drum-tab goldens/invariants/playhead suites pass before async wiring when applicable.
- [ ] Known `\Chart.difficulty` full-suite baseline failure is named and reproduced on clean `main` before classification.
- [ ] Final Release evidence is recorded for HPA-584.