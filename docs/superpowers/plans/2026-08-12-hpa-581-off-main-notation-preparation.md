# HPA-581 Off-Main Gameplay Notation Preparation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move measured timeline-native notation layout and beat-position preparation off the main actor, reject stale generation/width results before first install, and isolate static sheet-music rendering from high-frequency playback observation without virtualization or a new UI/concurrency framework.

**Architecture:** Keep SwiftData extraction, `RhythmTimelineResolver`, `RhythmLayoutSnapshotBuilder`, model lookup maps, and observable/audio/input state on `@MainActor`. Remove model identity from the timeline/render worker graph, pass one `GameplayNotationPreparationRequest` through a detached pure worker, and return one `GameplayNotationPreparedState`. A single generation counter is authoritative for stale work. Initial install additionally requires the request's floored row width to match the latest cached width; otherwise re-dispatch with the same generation mechanism before readiness. Static notation becomes a separate Equatable child keyed by prepared-layout generation; playhead receives only position and auto-scroll remains in the observable container.

**Tech Stack:** Swift 6, SwiftUI Observation, SwiftData, Swift Concurrency, Swift Testing/XCTest, Xcode/macOS `xcodebuild`, Instruments for the final Release comparison.

## Global Constraints

- Follow HPA-579 evidence: initial gameplay layout/notation/beat-position preparation and static/eager rendering are in scope; parser/persistence work is not.
- Keep SwiftData models, `ModelContext`, runtime model lookup identity, `RhythmTimelineResolver`, and `RhythmLayoutSnapshotBuilder` on `@MainActor`.
- Do not make `NotationLayoutInput` Sendable; `.legacy` owns `[Note]`.
- Do not use `@unchecked Sendable`.
- Reuse `NotationLayoutEngine.layout(input:)` and the existing timeline beat-position math; do not fork layout algorithms.
- Use one generation counter as the stale-result correctness mechanism. Cancellation is optional cleanup only.
- Keep the legacy SwiftData layout path synchronous on `@MainActor`.
- **Mandatory:** initial async preparation must reject a result whose request width is already stale before `isGameplayPrepared = true`.
- **Evidence-gated:** post-prepared live width relayout remains on the existing debounce/path unless a real Release resize proves material main-thread work.
- Static isolation must be a real separate Equatable `View`; do not use `.id(generation)` as a substitute.
- Do not add row virtualization; HPA-584 owns that decision.
- Do not add a performance service, scheduler, actor pool, benchmark framework, CI performance gate, or generic UI host.
- Run tests with parallel testing disabled because existing suites contain shared SwiftData/audio/global-state seams.

---

## Task 1: Make the timeline/render value graph Sendable **and** remove model identity

**Files:**
- Modify: `Virgo/models/RhythmMetadata.swift`
- Modify: `Virgo/models/ChartControlEvent.swift` **only for value types declared there (`NotationControlEventKind` / `NotationControlEvent`); do not add Sendable to the SwiftData `ChartControlEvent` model**
- Modify: `Virgo/layout/RhythmLayoutSnapshotBuilder.swift`
- Modify: `Virgo/layout/NotationLayout.swift`
- Modify: `Virgo/layout/NotationRhythmRendering.swift`
- Modify: `Virgo/layout/NotationLayoutEngine.swift`
- Modify as compiler requires: immutable value-definition files referenced by the timeline layout graph (`DrumType`, `NoteType`, `NoteInterval`, notation enums, `GameplayLayout.NotePosition`, etc.)
- Modify: `Virgo/viewmodels/GameplayViewModel+Computations.swift`
- Test: `VirgoTests/RhythmLayoutSnapshotBuilderTests.swift`
- Test: `VirgoTests/NotationLayoutEngineTests.swift`
- Test: `VirgoTests/NotationLayoutNotePositionOverrideTests.swift`
- Test: `VirgoTests/DrumTabGoldenTests.swift`
- Test: `VirgoTests/DrumTabRegressionInvariantTests.swift`
- Test: `VirgoTests/DrumTabPlayheadAlignmentTests.swift`

### Step 1.1 — Add two independent boundary gates first

- [ ] Add compile-time assertions:

```swift
private func requireSendable<T: Sendable>(_: T.Type) {}

requireSendable(RhythmLayoutSnapshot.self)
requireSendable(NotationLayout.self)
requireSendable(NotationLayoutStyle.self)
```

- [ ] Do **not** assume a compile failure proves `ObjectIdentifier` was removed. `ObjectIdentifier` itself can satisfy `Sendable`; the compiler may instead fail on unrelated unmarked value enums.
- [ ] Add an explicit structural regression using the repository's existing `Mirror` omitted-API style. Build representative timeline/render values and assert neither exposes a `sourceObjectID` field.
- [ ] Confirm the structural assertion is RED on current code even if some Sendable assertions compile.

### Step 1.2 — Remove model identity from timeline/render values

- [ ] Remove `RhythmLayoutNote.sourceObjectID`.
- [ ] Stop passing `ObjectIdentifier(note)` from `RhythmLayoutSnapshotBuilder`.
- [ ] Remove `RenderedNoteHead.sourceObjectID` from the rendered value graph.
- [ ] Keep `RhythmEventID` as authoritative timeline identity.
- [ ] Update timeline dropped-note diagnostics to compare rendered `eventID`s against `GameplayRhythmRuntime.noteByEventID`/its keys on `@MainActor`.
- [ ] Keep legacy dropped-note diagnostics main-actor local. If exact object matching disappears, use count + representative source metadata; do not put object identity back into `NotationLayout`.

### Step 1.3 — Propagate normal Sendable conformances

- [ ] Add `Sendable` only to immutable value enums/structs the compiler proves safe.
- [ ] In `ChartControlEvent.swift`, add it only to `NotationControlEventKind` / `NotationControlEvent` when required; leave `@Model final class ChartControlEvent` untouched.
- [ ] Add `Sendable` to rendered layout primitives/style definitions required for `NotationLayout` synthesis.
- [ ] Do not use `@unchecked Sendable`.

### Step 1.4 — Run the identity-sensitive rendering gate immediately

First run the focused value/layout tests:

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

Then run the production-layout identity/geometry gates **before** any async setup wiring:

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

- [ ] If digests never emitted `sourceObjectID`, expect the goldens to remain unchanged; that is useful proof, not a reason to skip them.

### Step 1.5 — Commit

```bash
git add Virgo VirgoTests
git commit -m "refactor(HPA-581): make timeline notation values sendable"
```

---

## Task 2: Introduce one pure notation preparation request/result

**Files:**
- Create: `Virgo/layout/GameplayNotationPreparation.swift`
- Create: `VirgoTests/GameplayNotationPreparationTests.swift`
- Modify: `Virgo.xcodeproj/project.pbxproj` (add both new Swift files to the correct groups/targets)
- Reuse: `Virgo/layout/NotationLayoutEngine.swift`

### Step 2.1 — Write failing pure-preparer tests

- [ ] Use a small timeline-native fixture/snapshot already supported by rhythm test helpers.
- [ ] Assert request and result are `Sendable`.
- [ ] Assert `GameplayNotationPreparer.prepare(request)` matches direct timeline `NotationLayoutEngine().layout(input:)` geometry/content.
- [ ] Assert timeline beat-position derivation for at least two rhythm positions across different measures/rows.
- [ ] Assert empty/no-playable-content semantics remain unchanged.
- [ ] Do not use sleeps or wall-clock timing.

```bash
xcodebuild test -project Virgo.xcodeproj -scheme Virgo \
  -destination 'platform=macOS' -configuration Debug \
  -only-testing:VirgoTests/GameplayNotationPreparationTests \
  -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -destination-timeout 300 -derivedDataPath ./DerivedData
```

Expected: RED because the preparer types do not exist yet.

### Step 2.2 — Implement the minimal boundary

- [ ] Add `GameplayNotationPreparationRequest: Sendable` containing only timeline-safe values:
  - `RhythmLayoutSnapshot`;
  - minimum measure count;
  - `NotationLayoutStyle` with resolved/floored row width;
  - note-position overrides;
  - beat rhythm positions keyed by existing beat ID.
- [ ] Add one `GameplayNotationPreparedState: Sendable` used as worker result and coherent view-model state.
- [ ] At minimum return `NotationLayout` + derived timeline beat positions; include existing hot lookup maps only when coherent installation benefits.
- [ ] Add synchronous actor-independent `GameplayNotationPreparer.prepare(_:)`.
- [ ] Construct timeline-only `NotationLayoutInput` **inside** the preparer.
- [ ] Reuse `NotationLayoutEngine` and its rendered measures/`TabGrid` for beat positions; do not duplicate layout math.

### Step 2.3 — Verify and commit

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

## Task 3: Dispatch initial timeline preparation off-main and reject stale width before readiness

**Files:**
- Modify: `Virgo/viewmodels/GameplayViewModel.swift`
- Modify: `Virgo/viewmodels/GameplayViewModel+Computations.swift`
- Modify: `Virgo/views/GameplayView.swift`
- Modify: all production/test call sites found by `rg -n 'setupGameplay\(' Virgo VirgoTests`
- Test: `VirgoTests/GameplayViewModelLayoutComputationsTests.swift`
- Test as compiler identifies: existing gameplay setup/cleanup/input/audio suites that call `setupGameplay()`

### Step 3.1 — Write deterministic generation **and initial-width freshness** tests first

Add an apply-seam test for stale generation:

1. allocate generation N;
2. allocate N+1;
3. attempt to apply N;
4. assert active state is unchanged;
5. apply N+1 and assert it becomes active.

Add a separate first-install width test:

1. seed cached width/request N at the 900 pt floor;
2. while N is conceptually in flight, update the cached loading width to a packing-changing width;
3. present N to the deterministic apply seam;
4. assert N is rejected even though its generation was current when dispatched;
5. assert a new generation/request is allocated using the latest floored width;
6. apply the latest result and assert only it becomes prepared.

- [ ] Do not race real tasks or sleep. Drive the apply/re-dispatch rule directly.
- [ ] Add a representative timeline setup integration case proving layout, row map, note-head positions, and beat positions remain equivalent.

### Step 3.2 — Make setup awaitable; keep one production API

- [ ] Change `setupGameplay(loadPersistedSpeed:)` to `async`.
- [ ] Update `GameplayView.prepareGameplay(initialRowWidth:)` to `await vm.setupGameplay(...)`.
- [ ] Mechanically update existing test call sites to `await`; make tests async where needed.
- [ ] Do not add a second synchronous production wrapper.

### Step 3.3 — Keep loading width current from the outer GeometryReader

The sheet's existing width handlers are inside the prepared sheet and therefore cannot update an in-flight first request.

- [ ] While gameplay is loading, propagate `geometry.size.width` from the outer `GeometryReader` into `viewModel.updateRowWidth(...)` (or an equally small loading-safe seam) so `cachedLayoutRowWidth` tracks the latest known width before the sheet mounts.
- [ ] Preserve current width normalization: finite/positive values, 900 pt floor, existing tolerance semantics.
- [ ] While `!isGameplayPrepared`, `updateRowWidth` should remain cheap: store the normalized width only; do not start live relayout work.

### Step 3.4 — Add one generation counter and one apply rule

- [ ] Add one monotonically increasing notation-preparation generation to `GameplayViewModel`.
- [ ] Increment when starting async timeline preparation and when invalidating/cleaning it up.
- [ ] Optionally retain one in-flight task for cancellation/resource cleanup; generation remains the correctness mechanism.
- [ ] A result may install only when:
  1. its captured generation equals the current generation; and
  2. its request row width equals the latest normalized cached row width.
- [ ] If generation matches but width is stale, bump/invalidate and dispatch the latest request **before** `isGameplayPrepared = true`.
- [ ] Do not expose the stale first layout and rely on sheet `onAppear` to repair it.

### Step 3.5 — Split timeline and legacy preparation

- [ ] Keep `computeDrumBeats()` on `@MainActor`.
- [ ] Build `GameplayNotationPreparationRequest` from the already-built timeline snapshot, current resolved note-position overrides, **current floored cached width**, and beat rhythm positions.
- [ ] Execute only the measured pure work:

```swift
let prepared = await Task.detached(priority: .userInitiated) {
    GameplayNotationPreparer.prepare(request)
}.value
```

- [ ] Back on `@MainActor`, run the generation + width apply rule above.
- [ ] Install `GameplayNotationPreparedState` coherently so views never observe mismatched layout/lookup/beat-position generations.
- [ ] Keep legacy SwiftData layout synchronous on-main and build the same stored state locally.
- [ ] Preserve fatal rhythm timing and BGM/metronome/input semantic ordering.

### Step 3.6 — Verify focused gameplay behavior

```bash
xcodebuild test -project Virgo.xcodeproj -scheme Virgo \
  -destination 'platform=macOS' -configuration Debug \
  -only-testing:VirgoTests/GameplayViewModelLayoutComputationsTests \
  -only-testing:VirgoTests/GameplayViewTests \
  -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -destination-timeout 300 -derivedDataPath ./DerivedData
```

- [ ] Also run every setup-related suite changed solely for the new `await`.

### Step 3.7 — Commit

```bash
git add Virgo/viewmodels Virgo/views/GameplayView.swift VirgoTests
git commit -m "feat(HPA-581): prepare timeline notation off main actor"
```

---

## Task 4: Remove `AnyView` caches and make static notation a real Equatable child

**Files:**
- Modify: `Virgo/viewmodels/GameplayViewModel.swift`
- Modify: `Virgo/viewmodels/GameplayViewModel+Computations.swift`
- Modify: `Virgo/views/subviews/GameplaySheetMusicView.swift`
- Test: `VirgoTests/GameplaySheetMusicMountingTests.swift`
- Test: `VirgoTests/GameplayViewModelLayoutComputationsTests.swift`

### Step 4.1 — Add the static-boundary regression first

- [ ] Extend mounting/layout tests to obtain the immutable static inputs and active prepared-layout generation.
- [ ] Mutate only high-frequency playback state (for example playhead position) and assert static generation/input identity remains unchanged.
- [ ] Assert a new installed layout generation compares unequal to the old static child.
- [ ] Keep the existing raster smoke proving production notation primitives mount.

### Step 4.2 — Remove presentation caches

- [ ] Delete `staticStaffLinesView` and `notationStaffLinesView` from `GameplayViewModel`.
- [ ] Delete `cacheNotationStaffLinesView()` and staff-line `AnyView` construction from computations.
- [ ] Construct `StaffLinesBackgroundView` normally from immutable layout/measure values in the view layer.

### Step 4.3 — Extract a separate Equatable static View

- [ ] Keep the observable sheet container responsible for `ScrollViewReader`, auto-scroll hooks, and live state extraction.
- [ ] Extract a private/file-local `GameplayStaticNotationView: View, Equatable` that receives immutable `NotationLayout`/measure/static values plus the installed layout generation.
- [ ] Implement `==` using the generation only; do **not** deep-compare the 2,870-note layout.
- [ ] Use the child through an explicit equatable boundary such as `.equatable()` so unchanged generation skips static body evaluation.
- [ ] Preserve the invariant: every installed layout change advances the generation.
- [ ] Do **not** use `.id(generation)`; that remounts on layout changes rather than serving as the equality optimization.
- [ ] Move the static `ForEach` notation layers (`barLines`, clefs/time signatures, noteheads, stems/beams/rests/etc.) under this child rather than leaving them as `GameplayView` methods that read the view model.
- [ ] Pass only playhead position to `GameplayPlayheadBarView(position:)`; remove its `GameplayViewModel` input.
- [ ] Keep auto-scroll `onChange` hooks on the container and narrow them to `currentRow` / `isPlaying` plus the minimum static renderability predicate.
- [ ] Do not introduce caches for cheap row/rest/clef/time-signature derivations unless naturally required by the static child API.
- [ ] Do not virtualize rows.

### Step 4.4 — Verify static/raster behavior

```bash
xcodebuild test -project Virgo.xcodeproj -scheme Virgo \
  -destination 'platform=macOS' -configuration Debug \
  -only-testing:VirgoTests/GameplaySheetMusicMountingTests \
  -only-testing:VirgoTests/GameplayViewModelLayoutComputationsTests \
  -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -destination-timeout 300 -derivedDataPath ./DerivedData
```

### Step 4.5 — Commit

```bash
git add Virgo/viewmodels Virgo/views/subviews/GameplaySheetMusicView.swift VirgoTests
git commit -m "refactor(HPA-581): isolate static gameplay notation rendering"
```

---

## Task 5: Keep **post-prepared** width relayout evidence-gated

**Files:**
- Potentially modify: `Virgo/viewmodels/GameplayViewModel+Computations.swift`
- Potentially modify: `Virgo/viewmodels/GameplayViewModel.swift`
- Test: `VirgoTests/GameplayViewModelLayoutComputationsTests.swift`

This task concerns live resize **after** gameplay is prepared. Task 3's first-install width freshness is mandatory regardless of this measurement.

### Step 5.1 — Preserve the existing debounce first

- [ ] Keep trailing-edge row-width debounce and cached-width cancellation behavior.
- [ ] Do not add a second request/token mechanism.
- [ ] Ensure narrow-window 900 pt floor behavior is unchanged.

### Step 5.2 — Attempt a real Release relayout measurement

- [ ] Use a natural host/window width that actually changes row packing. Do not treat the prior synthetic 3,000 pt probe as proof of a real resize path.
- [ ] If the host still cannot produce a real row-packing change, record **not measurable / no off-main live-relayout change** and stop.
- [ ] If a real row-packing change occurs, profile the post-debounce layout call.

### Step 5.3 — Conditional implementation only if material

If and only if Step 5.2 shows material main-thread work:

- [ ] Route timeline live relayout through the existing `GameplayNotationPreparer`.
- [ ] Reuse the same notation generation; latest width wins.
- [ ] Cancellation remains cleanup only.
- [ ] Add deterministic out-of-order width completion coverage.
- [ ] Keep legacy relayout synchronous on-main.

If measurement is not material, do not add this async path.

### Step 5.4 — Commit only if production code changed

```bash
git add Virgo/viewmodels VirgoTests/GameplayViewModelLayoutComputationsTests.swift
git commit -m "perf(HPA-581): reuse notation worker for measured relayout"
```

Skip when no code change is justified.

---

## Task 6: Strict-concurrency, focused regressions, full suite, and Release profile

### Step 6.1 — Strict Swift concurrency build

```bash
xcodebuild build -project Virgo.xcodeproj -scheme Virgo \
  -destination 'platform=macOS' -configuration Debug \
  SWIFT_STRICT_CONCURRENCY=complete \
  ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath ./DerivedData
```

- [ ] Fix compiler-proven Sendable/actor issues by narrowing/copying immutable values, not `@unchecked Sendable`.
- [ ] Remember compiler success does not prove model identity is absent; Task 1's structural assertion remains required.

### Step 6.2 — Run focused high-value suites, including identity/geometry goldens

```bash
xcodebuild test -project Virgo.xcodeproj -scheme Virgo \
  -destination 'platform=macOS' -configuration Debug \
  -only-testing:VirgoTests/GameplayNotationPreparationTests \
  -only-testing:VirgoTests/RhythmLayoutSnapshotBuilderTests \
  -only-testing:VirgoTests/NotationLayoutEngineTests \
  -only-testing:VirgoTests/GameplayViewModelLayoutComputationsTests \
  -only-testing:VirgoTests/GameplaySheetMusicMountingTests \
  -only-testing:VirgoTests/DrumTabGoldenTests \
  -only-testing:VirgoTests/DrumTabRegressionInvariantTests \
  -only-testing:VirgoTests/DrumTabPlayheadAlignmentTests \
  -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -destination-timeout 300 -derivedDataPath ./DerivedData
```

### Step 6.3 — Run the full Virgo test suite

```bash
xcodebuild test -project Virgo.xcodeproj -scheme Virgo \
  -destination 'platform=macOS' -configuration Debug \
  -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -destination-timeout 300 -derivedDataPath ./DerivedData
```

- [ ] Do not classify a new concurrency/SwiftData crash as a baseline flake without stack comparison and focused reproduction.

### Step 6.4 — Repeat the HPA-579 Release baseline

Use the same representative identity when available:

- `soukyuu_e_no_shouka` MASTER / Expert;
- 2,870 notes, 156 measures;
- 900 pt baseline row width;
- Release macOS on the same machine/configuration when practical.

Record:

- [ ] chart selection → gameplay prepared;
- [ ] whether notation layout/beat-position CPU disappears from the main-thread preparation slice;
- [ ] whether any initial worker result was rejected for width freshness, and confirm no known-stale layout became visible;
- [ ] initial production `GameplayView` mount versus 4,890.729 ms baseline;
- [ ] playback main-thread/SwiftUI activity with the Equatable static subtree;
- [ ] auto-scroll correctness;
- [ ] live width-relayout result/limitation from Task 5.

Do not invent a universal threshold. Required proof is directional: measured timeline layout/beat-position work no longer blocks `@MainActor`, known-stale first-width results never mount, static notation is not broadly driven by playhead updates, and behavior remains correct.

If eager mount remains dominant, record it and leave virtualization to HPA-584.

### Step 6.5 — Record Linear result

Add a concise HPA-581 comment containing:

- implementation summary;
- before/after representative preparation and mount numbers;
- strict-concurrency/test result;
- first-install width freshness result;
- whether post-prepared live relayout changed or remained unproven;
- explicit handoff to HPA-584 if eager mount remains dominant;
- implementation PR link.

---

## Completion checklist

- [ ] Timeline-native `NotationLayoutEngine` work is dispatched off-main from initial gameplay setup.
- [ ] Timeline beat-position derivation is dispatched with it.
- [ ] SwiftData, resolver/snapshot building, runtime model lookup, and object identity stay on `@MainActor`.
- [ ] `sourceObjectID` is absent from the timeline/render worker graph, protected by explicit structural tests in addition to Sendable assertions.
- [ ] One Sendable request and one Sendable prepared state define the boundary.
- [ ] One generation counter rejects stale results.
- [ ] First install additionally rejects a result whose request width is no longer the latest normalized cached width and re-dispatches before readiness.
- [ ] Legacy layout remains on-main.
- [ ] Post-prepared live width relayout changes only if real evidence justifies it.
- [ ] Static notation is a separate Equatable child, equality = installed layout generation, and receives no `GameplayViewModel`.
- [ ] Static isolation does not use `.id(generation)`.
- [ ] Playhead receives position only; auto-scroll inputs remain narrow.
- [ ] `staticStaffLinesView` / `notationStaffLinesView` are removed.
- [ ] Drum-tab golden, invariant, and playhead-alignment suites run once immediately after identity removal and again in the final focused gate.
- [ ] No `@unchecked Sendable`, scheduler/actor framework, benchmark framework, or virtualization is added.
- [ ] Strict concurrency build passes.
- [ ] Focused and full regression suites pass, or any known baseline failure is specifically evidenced.
- [ ] HPA-579 representative Release profile is repeated and recorded for HPA-584.
