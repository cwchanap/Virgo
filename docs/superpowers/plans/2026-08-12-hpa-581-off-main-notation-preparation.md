# HPA-581 Off-Main Gameplay Notation Preparation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the measured timeline-native notation layout and beat-position preparation off the main actor, install prepared state safely, and isolate static sheet-music rendering from high-frequency playback observation without adding virtualization or a new UI/concurrency framework.

**Architecture:** Keep SwiftData extraction, `RhythmTimelineResolver`, model lookup maps, and observable/audio/input state on `@MainActor`. Convert the existing timeline layout snapshot/render value graph to normal `Sendable` values using `RhythmEventID` instead of `ObjectIdentifier`, pass one `GameplayNotationPreparationRequest` through a detached pure worker, and return one `GameplayNotationPreparedState`. A single generation counter rejects stale results. The static sheet-music child consumes immutable layout values and a cheap layout generation; playhead and auto-scroll keep only their narrow live inputs.

**Tech Stack:** Swift 6, SwiftUI Observation, SwiftData, Swift Concurrency, Swift Testing/XCTest, Xcode/macOS `xcodebuild`, Instruments for the final Release comparison.

## Global Constraints

- Follow the evidence recorded in HPA-579: initial gameplay preparation and static/eager notation rendering are in scope; parser/persistence work is not.
- Do not move SwiftData models, `ModelContext`, `ObjectIdentifier`, or SwiftUI views across actors.
- Do not make `NotationLayoutInput` Sendable; its legacy case contains `[Note]`.
- Do not use `@unchecked Sendable` to bypass compiler errors.
- Keep `RhythmTimelineResolver` and `RhythmLayoutSnapshotBuilder` on `@MainActor` unless new profiling in this ticket proves they are material.
- Reuse `NotationLayoutEngine` and the existing rhythm/layout algorithms exactly; no parallel implementation.
- Use one generation counter as the stale-result correctness mechanism. Cancellation is optional cleanup only.
- Keep the legacy SwiftData layout path synchronous on `@MainActor`.
- Keep the existing resize debounce. Off-main width relayout is conditional on real profiling evidence because HPA-579 could not trigger/measure a valid relayout.
- Do not add row virtualization; HPA-584 owns that decision.
- Do not add a performance service, scheduler, actor pool, benchmark framework, CI performance gate, or generic UI host.
- Run tests with parallel testing disabled because the existing suite contains shared SwiftData/audio/global-state seams.

---

## Task 1: Make the timeline layout value graph Sendable without object identity

**Files:**
- Modify: `Virgo/models/RhythmMetadata.swift`
- Modify: `Virgo/models/ChartControlEvent.swift`
- Modify: `Virgo/layout/RhythmLayoutSnapshotBuilder.swift`
- Modify: `Virgo/layout/NotationLayout.swift`
- Modify: `Virgo/layout/NotationRhythmRendering.swift`
- Modify: `Virgo/layout/NotationLayoutEngine.swift`
- Modify as compiler requires: immutable value-definition files referenced by the timeline layout graph (`DrumType`, `NoteType`, `NoteInterval`, notation enums, `GameplayLayout.NotePosition`, etc.)
- Modify: `Virgo/viewmodels/GameplayViewModel+Computations.swift`
- Test: `VirgoTests/RhythmLayoutSnapshotBuilderTests.swift`
- Test: `VirgoTests/NotationLayoutEngineTests.swift`

### Step 1.1 — Add compile-time boundary assertions first

- [ ] Add a tiny generic helper in the relevant test file:

```swift
private func requireSendable<T: Sendable>(_: T.Type) {}
```

- [ ] Add tests/compile assertions for the value types that must cross the worker boundary, starting with:

```swift
requireSendable(RhythmLayoutSnapshot.self)
requireSendable(NotationLayout.self)
requireSendable(NotationLayoutStyle.self)
```

- [ ] Run the focused test target and confirm compilation fails on the current non-Sendable/object-identity graph.

```bash
xcodebuild test -project Virgo.xcodeproj -scheme Virgo \
  -destination 'platform=macOS' -configuration Debug \
  -only-testing:VirgoTests/RhythmLayoutSnapshotBuilderTests \
  -only-testing:VirgoTests/NotationLayoutEngineTests \
  -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -destination-timeout 300 -derivedDataPath ./DerivedData
```

Expected: RED at compile time until the boundary is Sendable.

### Step 1.2 — Remove `ObjectIdentifier` from timeline/render values

- [ ] Remove `RhythmLayoutNote.sourceObjectID`.
- [ ] Stop passing `ObjectIdentifier(note)` from `RhythmLayoutSnapshotBuilder`.
- [ ] Remove `RenderedNoteHead.sourceObjectID` so a `NotationLayout` cannot accidentally carry model identity across actors.
- [ ] Keep `RhythmEventID` as the authoritative timeline source identity.
- [ ] Update timeline dropped-note diagnostics in `GameplayViewModel+Computations.swift` to compare rendered `eventID`s against the main-actor rhythm runtime/model lookup.
- [ ] For the legacy path, keep diagnostics main-actor local; if exact object matching has no stable value identifier, prefer a count plus representative source metadata over reintroducing object identity into rendered values.

### Step 1.3 — Propagate normal `Sendable` conformances

- [ ] Add `Sendable` only to immutable value enums/structs the compiler proves safe.
- [ ] Add `Sendable` to `NotationControlEventKind` / `NotationControlEvent` if their value-only fields require it; do **not** touch the SwiftData `ChartControlEvent` model.
- [ ] Add `Sendable` to rendered layout primitives and style/value definitions required for `NotationLayout` to synthesize Sendable.
- [ ] Do not use `@unchecked Sendable`.

### Step 1.4 — Preserve layout semantics

- [ ] Run the same focused tests and confirm GREEN.
- [ ] Run the existing note-position override/layout regression suite because `RenderedNoteHead` identity changes touch common layout output:

```bash
xcodebuild test -project Virgo.xcodeproj -scheme Virgo \
  -destination 'platform=macOS' -configuration Debug \
  -only-testing:VirgoTests/NotationLayoutNotePositionOverrideTests \
  -only-testing:VirgoTests/NotationLayoutEngineTests \
  -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -destination-timeout 300 -derivedDataPath ./DerivedData
```

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
- Modify: `Virgo.xcodeproj/project.pbxproj` (the project does not use file-system-synchronized groups; add both new Swift files to the correct groups/targets)
- Reuse: `Virgo/layout/NotationLayoutEngine.swift`

### Step 2.1 — Write failing pure-preparer tests

- [ ] Add `GameplayNotationPreparationTests` using a small timeline-native fixture/snapshot already supported by the existing rhythm test helpers.
- [ ] Test that the request and result compile as `Sendable`.
- [ ] Test that `GameplayNotationPreparer.prepare(request)` produces the same `NotationLayout` geometry/content as direct timeline `NotationLayoutEngine().layout(input:)` for the fixture.
- [ ] Test beat-position derivation for at least two rhythm positions across different measures/rows.
- [ ] Test empty/no-playable-content input preserves the current empty/renderable semantics.
- [ ] Do not use sleeps or wall-clock timing.

Run:

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

- [ ] Add `GameplayNotationPreparationRequest: Sendable` with only timeline-safe values:
  - `RhythmLayoutSnapshot`;
  - minimum measure count;
  - `NotationLayoutStyle` (including resolved row width);
  - note-position overrides;
  - beat rhythm positions keyed by existing beat ID, e.g. `[UInt64: RhythmEventPosition]`.
- [ ] Add one `GameplayNotationPreparedState: Sendable` used both as the worker result and the view model's coherently installed notation state.
- [ ] Store only values that are already hot/needed together. At minimum this is the `NotationLayout` plus timeline beat positions; keep existing lookup maps in the state only when that avoids repeated hot reconstruction.
- [ ] Add `GameplayNotationPreparer.prepare(_:)` as a synchronous, actor-independent pure function.
- [ ] Construct `NotationLayoutInput(timing: .timeline(...))` **inside** the preparer so the non-Sendable legacy enum never crosses actors.
- [ ] Reuse `NotationLayoutEngine` and its `TabGrid` calculations for beat positions; do not duplicate layout math.

### Step 2.3 — Verify and commit

- [ ] Run `GameplayNotationPreparationTests`; confirm GREEN.
- [ ] Run `NotationLayoutEngineTests` once more to prove the extracted path still shares the engine.

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

## Task 3: Dispatch initial timeline preparation off-main with one generation

**Files:**
- Modify: `Virgo/viewmodels/GameplayViewModel.swift`
- Modify: `Virgo/viewmodels/GameplayViewModel+Computations.swift`
- Modify: `Virgo/views/GameplayView.swift`
- Modify: all production/test call sites found by `rg -n 'setupGameplay\(' Virgo VirgoTests`
- Test: `VirgoTests/GameplayViewModelLayoutComputationsTests.swift`
- Test as compiler identifies: existing gameplay setup/cleanup/input/audio suites that call `setupGameplay()`

### Step 3.1 — Write stale-generation and integration tests first

- [ ] Add a deterministic test for the main-actor apply seam:
  1. allocate generation N;
  2. allocate generation N+1;
  3. try to apply an N result;
  4. assert active prepared state is unchanged;
  5. apply N+1 and assert it becomes active.
- [ ] Keep this test entirely deterministic. Test the generation/apply rule directly; do not race real tasks or sleep.
- [ ] Add/adjust a representative `GameplayViewModelLayoutComputationsTests` case to verify timeline setup still produces the expected layout, row map, note-head positions, and beat positions after preparation becomes async.

Run the targeted suite and confirm RED until the new generation/apply seam exists.

### Step 3.2 — Make setup awaitable

- [ ] Change `setupGameplay(loadPersistedSpeed:)` to `async`.
- [ ] Update `GameplayView.prepareGameplayIfNeeded()` to `await viewModel.setupGameplay(...)` before exposing prepared UI.
- [ ] Mechanically update all existing test call sites to `await` the setup method; do not add a second synchronous production API just to avoid test edits.
- [ ] If a test function is currently synchronous, make that test async rather than introducing a blocking bridge.

### Step 3.3 — Add one generation counter

- [ ] Add one monotonically increasing notation-preparation generation to `GameplayViewModel`.
- [ ] Increment it whenever starting an asynchronous timeline preparation and when invalidating/cleaning up a preparation.
- [ ] Optionally retain one in-flight task for cancellation/resource cleanup, but correctness must depend only on the generation comparison.
- [ ] Do not add UUID registries or separate stale tokens.

### Step 3.4 — Split timeline and legacy preparation

- [ ] Keep `computeDrumBeats()` on `@MainActor`.
- [ ] Build `GameplayNotationPreparationRequest` on `@MainActor` from the already-built timeline snapshot, resolved note-position overrides, row width, and beat rhythm positions.
- [ ] Execute exactly the expensive timeline value work with:

```swift
let prepared = await Task.detached(priority: .userInitiated) {
    GameplayNotationPreparer.prepare(request)
}.value
```

- [ ] Back on `@MainActor`, install only when the captured generation is still current.
- [ ] Install `GameplayNotationPreparedState` through one stored value/update so views never observe mismatched layout/lookup/beat-position generations.
- [ ] Keep the legacy SwiftData `NotationLayoutInput` path synchronous on `@MainActor` and build the same stored state locally.
- [ ] Keep fatal rhythm timing short-circuit behavior unchanged.
- [ ] Keep BGM/metronome/input configuration on `@MainActor`; preserve existing semantic ordering unless a test proves reordering is safe.

### Step 3.5 — Verify focused gameplay behavior

```bash
xcodebuild test -project Virgo.xcodeproj -scheme Virgo \
  -destination 'platform=macOS' -configuration Debug \
  -only-testing:VirgoTests/GameplayViewModelLayoutComputationsTests \
  -only-testing:VirgoTests/GameplayViewTests \
  -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -destination-timeout 300 -derivedDataPath ./DerivedData
```

- [ ] Also run any setup-related suites changed solely for the new `await`; those changes should be mechanical and behavior-neutral.

### Step 3.6 — Commit

```bash
git add Virgo/viewmodels Virgo/views/GameplayView.swift VirgoTests
git commit -m "feat(HPA-581): prepare timeline notation off main actor"
```

---

## Task 4: Remove `AnyView` caches and isolate the static notation subtree

**Files:**
- Modify: `Virgo/viewmodels/GameplayViewModel.swift`
- Modify: `Virgo/viewmodels/GameplayViewModel+Computations.swift`
- Modify: `Virgo/views/subviews/GameplaySheetMusicView.swift`
- Test: `VirgoTests/GameplaySheetMusicMountingTests.swift`
- Test: `VirgoTests/GameplayViewModelLayoutComputationsTests.swift`

### Step 4.1 — Add failing static-input regression tests

- [ ] Extend the mounting/layout tests to obtain the immutable/static values the new child will consume.
- [ ] Add a test that captures the static layout generation/input, mutates only high-frequency playback state (for example playhead position), and asserts the static layout generation/input is unchanged.
- [ ] Keep the existing raster smoke that proves production notation primitives are actually mounted.

Expected: RED until the view API/static value seam exists.

### Step 4.2 — Remove presentation caches from the view model

- [ ] Delete `staticStaffLinesView` and `notationStaffLinesView` from `GameplayViewModel`.
- [ ] Delete `cacheNotationStaffLinesView()` and the static staff-line `AnyView` construction from layout caching.
- [ ] Preserve staff-line geometry by constructing `StaffLinesBackgroundView` normally from immutable measure/layout values in the view layer.

### Step 4.3 — Split static and live rendering narrowly

- [ ] Keep `GameplaySheetMusicView` as the small container that can observe `GameplayViewModel`.
- [ ] Extract a private/file-local static notation child that receives immutable `NotationLayout`/measure/static inputs plus the active preparation generation and **does not receive the view model**.
- [ ] Make equality/identity cheap: compare the preparation/layout generation rather than deep-comparing the 2,870-note layout every playback tick.
- [ ] Pass only playhead position to the playhead child.
- [ ] Keep auto-scroll observation limited to `currentRow` and `isPlaying`.
- [ ] Do not move cheap row/rest/clef/time-signature derivations into a new cache unless they naturally belong to the existing layout value.
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

## Task 5: Keep width relayout evidence-gated; reuse the same preparer only if justified

**Files:**
- Potentially modify: `Virgo/viewmodels/GameplayViewModel+Computations.swift`
- Potentially modify: `Virgo/viewmodels/GameplayViewModel.swift`
- Test: `VirgoTests/GameplayViewModelLayoutComputationsTests.swift`

### Step 5.1 — Preserve the existing debounce first

- [ ] Keep the current trailing-edge row-width debounce and cached-width cancellation behavior.
- [ ] Do not add a second request mechanism.
- [ ] Ensure the earlier refactor did not change the current narrow-window 900 pt floor semantics.

Run the existing row-width tests before any optional performance change:

```bash
xcodebuild test -project Virgo.xcodeproj -scheme Virgo \
  -destination 'platform=macOS' -configuration Debug \
  -only-testing:VirgoTests/GameplayViewModelLayoutComputationsTests \
  -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -destination-timeout 300 -derivedDataPath ./DerivedData
```

### Step 5.2 — Attempt a real relayout measurement

- [ ] In Release macOS, use a natural host/window width that actually changes row packing. Do not use a synthetic 3,000 pt width as proof of a real user resize.
- [ ] If the host still cannot produce a real row-packing change, record **not measurable / no off-main relayout change** and stop this task here.
- [ ] If a real row-packing change occurs, profile the post-debounce layout call in Time Profiler.

### Step 5.3 — Conditional implementation only when material

If and only if Step 5.2 shows material main-thread layout work:

- [ ] Route timeline relayout through the existing `GameplayNotationPreparer`.
- [ ] Reuse the same notation-preparation generation; latest width wins.
- [ ] Cancel the prior task only for cleanup.
- [ ] Add a deterministic out-of-order completion test proving an older width result cannot overwrite a newer one.
- [ ] Keep the legacy relayout path synchronous on-main.

If the measurement is not material, do **not** add this async path.

### Step 5.4 — Commit only if production code changed

```bash
git add Virgo/viewmodels VirgoTests/GameplayViewModelLayoutComputationsTests.swift
git commit -m "perf(HPA-581): reuse notation worker for measured relayout"
```

Skip this commit when no code change is justified.

---

## Task 6: Strict-concurrency, regression, and Release profiling gate

**Files:**
- No new production architecture expected.
- Update only code/tests needed by real failures.
- Record measurements in HPA-581/HPA-579 Linear discussion rather than adding a permanent metrics subsystem.

### Step 6.1 — Strict Swift concurrency build

- [ ] Run a complete-concurrency build:

```bash
xcodebuild build -project Virgo.xcodeproj -scheme Virgo \
  -destination 'platform=macOS' -configuration Debug \
  SWIFT_STRICT_CONCURRENCY=complete \
  ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath ./DerivedData
```

- [ ] Fix compiler-proven Sendable/actor issues by narrowing/copying immutable values, not by adding `@unchecked Sendable` to model/reference types.

### Step 6.2 — Run focused high-value suites

```bash
xcodebuild test -project Virgo.xcodeproj -scheme Virgo \
  -destination 'platform=macOS' -configuration Debug \
  -only-testing:VirgoTests/GameplayNotationPreparationTests \
  -only-testing:VirgoTests/RhythmLayoutSnapshotBuilderTests \
  -only-testing:VirgoTests/NotationLayoutEngineTests \
  -only-testing:VirgoTests/GameplayViewModelLayoutComputationsTests \
  -only-testing:VirgoTests/GameplaySheetMusicMountingTests \
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

- [ ] Do not dismiss a new concurrency/SwiftData crash as an existing flake merely because the suite has had detached-context issues before. Compare the failing stack and reproduce the focused suite before classifying it.

### Step 6.4 — Repeat the HPA-579 Release baseline

Use the same representative identity when available:

- `soukyuu_e_no_shouka` MASTER / Expert;
- 2,870 notes, 156 measures;
- 900 pt baseline row width;
- Release macOS on the same machine/configuration when practical.

Record:

- [ ] chart selection → gameplay prepared;
- [ ] whether notation layout/beat-position CPU disappears from the main-thread portion of preparation;
- [ ] initial production `GameplayView` notation mount versus the 4,890.729 ms baseline;
- [ ] playback main-thread/SwiftUI activity with the static subtree isolated;
- [ ] auto-scroll correctness;
- [ ] width relayout result/limitation from Task 5.

Do not invent a universal performance threshold. The required proof is that the measured timeline layout/beat-position work no longer blocks `@MainActor`, the static subtree is no longer broadly driven by playhead updates, and behavior remains correct.

If initial eager mount remains dominant after this work, record that evidence and leave the virtualization decision to HPA-584.

### Step 6.5 — Record Linear result

- [ ] Add a concise HPA-581 comment containing:
  - implementation summary;
  - before/after representative preparation and mount numbers;
  - strict-concurrency/test result;
  - whether width relayout was changed or remained unproven;
  - explicit handoff to HPA-584 if eager mount remains dominant.
- [ ] Link the implementation PR when one exists.

### Step 6.6 — Final commit if verification required repo changes

```bash
git status --short
git add <only files changed to fix verified failures>
git commit -m "test(HPA-581): verify off-main notation preparation"
```

Skip this commit when verification produces no repository changes.

---

## Completion checklist

- [ ] Timeline-native `NotationLayoutEngine` work is dispatched off-main from initial gameplay setup.
- [ ] Timeline beat-position derivation is dispatched with it.
- [ ] SwiftData and object identity stay on `@MainActor`.
- [ ] One Sendable request and one Sendable prepared state define the boundary.
- [ ] One generation counter rejects stale results.
- [ ] Legacy layout remains on-main.
- [ ] Width relayout changes only if real evidence justifies them.
- [ ] Static notation receives immutable layout data and does not receive `GameplayViewModel`.
- [ ] Playhead and auto-scroll inputs are narrow.
- [ ] `staticStaffLinesView` / `notationStaffLinesView` are removed.
- [ ] No `@unchecked Sendable`, scheduler/actor framework, benchmark framework, or virtualization is added.
- [ ] Strict concurrency build passes.
- [ ] Focused and full regression suites pass, or any known baseline failure is specifically evidenced.
- [ ] HPA-579 representative Release profile is repeated and recorded for HPA-584.
