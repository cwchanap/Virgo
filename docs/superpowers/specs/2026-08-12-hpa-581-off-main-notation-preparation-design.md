# HPA-581: Gameplay Notation Preparation and Static Rendering Design

**Date:** 2026-08-12  
**Status:** Proposed

## Context

HPA-579 profiled Release macOS with `soukyuu_e_no_shouka` MASTER (2,870 notes, 156 measures, 900 pt row width) and recorded:

- chart selection → gameplay prepared: median **267.857 ms**;
- production `GameplayView` initial mount: **4,890.729 ms**;
- layout/notation and beat-position preparation dominated the preparation slice;
- rhythm resolution and BGM setup were secondary;
- real host widths tested did not produce a measurable packing-changing relayout;
- HPA-581: **Proceed**, limited to measured gameplay preparation/static-render work and explicitly excluding virtualization/new screen architecture.

The current code has two separate costs:

1. **Recurring playback invalidation:** `GameplaySheetMusicView` is an extension on `GameplayView`; its container reads live `GameplayViewModel` state while static helpers still traverse/derive from `cachedNotationLayout`. The view model also caches staff-line `AnyView`s that do not cache rendered pixels.
2. **One-time preparation stall:** `setupGameplay()` performs notation layout and beat-position preparation synchronously on `@MainActor` before the prepared sheet becomes visible.

The first cost has a direct recurring user-visible payoff and can be fixed without concurrency. The second has measured main-actor CPU cost, but moving it off-main does **not by itself shorten the loading wait** if readiness still awaits the result. Its user benefit is main-actor responsiveness during loading, not a guaranteed lower chart-selection-to-ready duration.

HPA-581 itself allows narrowing to the smallest maintainability subset when broader work no longer has clear value. Therefore implementation is deliberately ordered so the cheap recurring win lands first and Release profiling decides whether the async migration remains worth its call-site/lifecycle churn.

## Goals

1. Remove broad static-notation observation from the 30 Hz playback path.
2. Make every installed notation-layout change advance one enforced notation generation.
3. Remove `staticStaffLinesView` / `notationStaffLinesView` and their `AnyView` caching.
4. Keep O(note/measure) static derivations behind the Equatable static-child boundary rather than recomputing them on every playhead update.
5. Re-profile before introducing async setup churn.
6. If the measured preparation work remains material, move only timeline-native notation layout + beat-position derivation off `@MainActor` through one immutable value boundary.
7. Keep SwiftData extraction, rhythm resolution, model lookup maps, observable assignment, legacy layout, audio, and input on `@MainActor`.
8. Reuse the **same notation generation** for static-view equality, async request freshness, resets, and cleanup invalidation; do not add a second preparation token/counter.
9. Preserve notation geometry, timing/input mappings, resize behavior, accessibility, fatal timing, and session controls.

## Non-goals

- Row virtualization. HPA-584 owns that post-HPA-581 decision.
- A notation actor, scheduler, registry, repository/use-case layer, worker pool, benchmark harness, or CI performance gate.
- `@unchecked Sendable`.
- Making `NotationLayoutInput` Sendable; its legacy case contains SwiftData `Note` models.
- Moving `RhythmTimelineResolver` or `RhythmLayoutSnapshotBuilder` off-main without new evidence.
- Moving SwiftData models, `ModelContext`, `ObjectIdentifier`, or SwiftUI views across actors.
- Adding a second stale-request generation/token in addition to the layout generation.
- Adding a pre-readiness row-width retry/state machine. Initial preparation uses the width seeded immediately before setup; if geometry changes while an async request is in flight, the existing post-ready debounce performs the normal repack.
- Preserving exact per-model legacy dropped-note identity after `sourceObjectID` is removed. Legacy diagnostics may degrade to count + representative metadata; timeline diagnostics retain stable `RhythmEventID` identity.
- Promising that HPA-581 eliminates the **4.89 s** eager initial mount. Static isolation targets repeated invalidation; HPA-584 decides virtualization from the post-change profile.

## Decision

### 1. Ship static isolation first, without concurrency

The first implementation phase is intentionally synchronous.

`GameplaySheetMusicView` becomes a small observable container that extracts only:

- live playhead position;
- `currentRow` / `isPlaying` for auto-scroll;
- immutable installed notation/static input;
- O(1) content frame scalars derived directly from the installed layout.

A file-local `GameplayStaticNotationView: View, Equatable` owns the complete static tree.

It receives immutable values, never `GameplayViewModel`, and equality compares only the installed notation generation. It is used through `.equatable()` (or the equivalent EquatableView boundary). Do **not** use `.id(generation)`; changing identity remounts the tree instead of suppressing body evaluation.

The playhead child receives only `CGPoint?` (or the existing equivalent tuple).

Auto-scroll remains in the container.

### 2. Put all O(n) static derivation behind that boundary

The current sheet container computes values that are pure functions of installed layout:

- notation measure-position mapping;
- row count;
- `spacingAboveLine5`, which scans note heads;
- printed-rest filtering;
- row-anchor construction.

If the container continues doing this while reading live playhead state, the Equatable child only avoids the large `ForEach` tree; it does not avoid those scans/allocations.

Therefore:

- move `rowAnchorColumn` inside `GameplayStaticNotationView`;
- compute notation measure positions, row count, top spacing, printed rests, bar/clef descriptors, and similar O(n) static values inside the static child's body so they execute only when its generation changes;
- keep the container's frame calculations limited to O(1) stored layout properties (`contentWidth`, `totalHeight`, `paintedBounds`/top inset) plus legacy fallback scalars;
- do **not** duplicate all of those derivations into a second cache merely for architecture symmetry.

If implementation naturally produces one small immutable static-projection value at the install seam, storing it is acceptable, but the required invariant is **no O(note/measure) walk in the 30 Hz container body**, not a particular cache type.

This is narrower than precomputing every row/rest/clef value into `GameplayNotationPreparedState`, while addressing the actual cost.

### 3. Enforce notation generation through one install funnel

Equatable correctness cannot depend on every current/future writer remembering to bump a separate counter.

Current production layout resets/installs happen through multiple paths (normal layout, no-track reset, fatal-timing reset). Introduce one view-model install seam, conceptually:

```swift
func installNotationLayout(_ layout: NotationLayout) {
    notationLayoutGeneration &+= 1
    notationLayoutStorage = layout
}
```

Exact storage spelling may differ, but:

- `notationLayoutGeneration` is not externally settable;
- production code cannot assign the backing notation layout without going through the install seam;
- normal install, empty/no-track reset, fatal-timing reset, and later worker install all use the same funnel;
- tests cover each reset/install path advancing generation.

A read-only `cachedNotationLayout` compatibility accessor may remain if that avoids unnecessary consumer churn.

If the worker phase proceeds, it does **not** add `notationPreparationGeneration`. Instead it allocates/advances this same notation generation before dispatch and captures N. A successful result installs the prepared layout tagged with N without incrementing a second time; any reset/new request/cleanup advances the same counter and makes N stale.

This single point/counter is the correctness contract for both `GameplayStaticNotationView.==` and stale async completion.

### 4. Remove presentation caches

Delete:

- `staticStaffLinesView`;
- `notationStaffLinesView`;
- `cacheNotationStaffLinesView()` and its `AnyView` creation.

`StaffLinesBackgroundView` is already a normal SwiftUI value view. Construct it from immutable static inputs inside `GameplayStaticNotationView`.

### 5. Re-profile before async setup migration

After static isolation, repeat the representative Release profile before changing `setupGameplay()` to async.

Record separately:

- chart selection → gameplay prepared;
- main-thread samples during preparation;
- initial notation mount;
- playback/static-body activity.

The decision is:

- **Proceed with off-main preparation** if timeline notation layout + beat-position work is still a material main-actor stall. The expected user benefit is a responsive loading/window/dismiss surface while CPU work runs, not necessarily shorter readiness wall-clock.
- **Narrow/close HPA-581 after static isolation** only if the new evidence shows that preparation work is no longer material enough to justify the widespread async call-site/lifecycle change. This is allowed by HPA-581's own implementation gate.

HPA-584 does **not** jump ahead merely because its 4.89 s baseline is larger. It remains the follow-up once HPA-581 reaches its evidence-based close point.

### 6. If async preparation proceeds, make the timeline graph semantically worker-safe

`RhythmLayoutSnapshot` is the conceptual value boundary, but today the graph carries model identity through:

- `RhythmLayoutNote.sourceObjectID`;
- `RenderedNoteHead.sourceObjectID`.

`ObjectIdentifier` can itself satisfy `Sendable`, so compiler Sendable checks cannot prove semantic removal.

For the timeline path:

- remove those `sourceObjectID` fields;
- use `RhythmEventID` as authoritative source identity;
- keep `GameplayRhythmRuntime.noteByEventID` on `@MainActor` for model reattachment/diagnostics;
- timeline dropped-note diagnostics compare rendered event IDs with the runtime event-ID map;
- legacy dropped-note diagnostics explicitly degrade to count + representative metadata if exact object identity is unavailable.

`RenderedNoteHead.id: UInt64` remains the rendered identity used by `Identifiable`/`Hashable` consumers. Removing `sourceObjectID` does not remove that stable rendered ID; the early golden/invariant run confirms geometry/digest behavior rather than serving as the only reason equality remains discriminating.

Add normal `Sendable` conformances only to immutable value types needed by the worker graph. In `ChartControlEvent.swift`, only `NotationControlEventKind` / `NotationControlEvent` may gain `Sendable`; the SwiftData `ChartControlEvent` model remains untouched.

Verification includes both:

1. generic compile-time `Sendable` assertions; and
2. the repository's existing Mirror/omitted-API style assertion that worker timeline/render values do not expose `sourceObjectID`.

### 7. Reuse one pure preparer; do not test it tautologically

If the async phase proceeds, add one pure value helper:

```swift
struct GameplayNotationPreparationRequest: Sendable {
    let snapshot: RhythmLayoutSnapshot
    let minimumMeasureCount: Int
    let style: NotationLayoutStyle
    let notePositionOverrides: [DrumType: GameplayLayout.NotePosition]
}

struct GameplayNotationPreparedState: Sendable {
    let layout: NotationLayout
}

struct GameplayNotationPreparer {
    static func prepare(_ request: GameplayNotationPreparationRequest) -> GameplayNotationPreparedState
}
```

The earlier `beatPositionsByID` field was dropped during implementation: the
`cachedBeatPositions` / `cachedNotationNoteHeadPositions` caches it fed had no
production reader (only tests), so carrying beat positions across the worker
boundary was unused optimization state. Section 2's "do not duplicate
derivations into a second cache for architecture symmetry" governs here.

It constructs timeline-only `NotationLayoutInput` internally and calls the existing `NotationLayoutEngine`. No engine fork.

Do **not** add a test whose only assertion is that `prepare(request).layout` equals `NotationLayoutEngine().layout` for the same input; that only proves the wrapper calls its dependency.

New seam tests instead cover:

- request/result Sendability;
- structural absence of object identity;
- beat-position derivation against pinned expected coordinates;
- empty/no-playable semantics;
- view-model installed state after the new setup path matching the synchronous baseline/golden expectations already protected by existing suites.

Existing `DrumTabGoldenTests`, `DrumTabRegressionInvariantTests`, and `DrumTabPlayheadAlignmentTests` remain the authority for layout equivalence.

### 8. Reuse the same notation generation for async freshness and cleanup

If off-main setup proceeds:

```text
@MainActor
  compute drum beats
  seed current row width
  allocate notation generation N
  build timeline request
        |
        v
Task.detached(.userInitiated)
  NotationLayoutEngine.layout
  timeline beat-position derivation
        |
        v
@MainActor
  notation generation still N?
    yes -> install prepared layout/state tagged N
    no  -> discard
```

There is no second request-generation mechanism. Cancellation is resource cleanup only.

`cleanup()` advances the same notation generation before/while tearing down gameplay. A completion arriving after cleanup therefore cannot reinstall notation or set `isGameplayPrepared = true`.

Add a deterministic regression for “completion after cleanup cannot resurrect readiness.” Do not race real tasks or use sleeps; test the apply rule directly.

### 9. Do not add pre-readiness width retries

The previous design added a generation + width-freshness re-dispatch rule across the async gap. Drop it.

Why:

- current setup seeds width synchronously immediately before layout;
- `updateRowWidth` already uses a **0.5 pt** tolerance plus a 100 ms trailing-edge debounce;
- a separate exact/request-width apply predicate creates mismatched semantics and can repeatedly re-dispatch while the user is resizing;
- the rare cost of one first-frame repack is smaller than another loading-state lifecycle.

If the async phase proceeds, install the current-generation initial result. Once the prepared sheet mounts, its existing `onAppear` / geometry-width update runs through the existing debounce and repacks if the window changed during the worker interval.

Post-prepared relayout remains evidence-gated exactly as HPA-579 required. If a real packing-changing resize later proves material, route it through the **same** preparer and notation generation; otherwise change nothing.

## Data / phase flow

```text
Phase A — no concurrency
@MainActor layout
  -> one installNotationLayout funnel (notation generation++)
  -> GameplayStaticNotationView(layout/static values, generation).equatable()
       -> measure mapping / row count / top-spacing scan / row anchors / notation ForEach
  -> GameplayPlayheadBarView(position only)
  -> auto-scroll(currentRow, isPlaying)

Phase B — Release re-profile
  -> if preparation no longer justifies churn: close HPA-581 narrow
  -> if still material: continue

Phase C/D — conditional worker
@MainActor SwiftData + resolver + snapshot
  -> allocate same notation generation N
  -> Sendable request (RhythmEventID identity only)
  -> Task.detached pure layout + beat positions
  -> same-generation check
  -> one coherent install tagged N
  -> cleanup/newer work advances same generation
  -> existing width debounce handles any geometry drift
```

## Failure and lifecycle behavior

- Fatal rhythm timing stays main-actor controlled and resets notation through the one install funnel, advancing the notation generation.
- Empty layout is a valid installed state and advances the generation.
- No-track reset advances the generation.
- Normal synchronous/static-phase layout install advances the generation.
- A stale async generation cannot install.
- `cleanup()` advances the same generation so an in-flight completion cannot make gameplay ready again.
- There is no async width retry loop.
- `NotationLayoutEngine.layout` remains nonthrowing unless implementation uncovers a real failure requiring propagation.

## Verification contract

### Static phase

Run focused mounting/layout/playback tests proving:

- all notation layout install/reset paths advance generation;
- playhead-only updates leave static generation/input unchanged;
- a new layout generation compares unequal;
- row anchors remain functional after moving under the static child;
- raster/mounting behavior remains correct;
- no O(note/measure) static derivation remains in the live container body.

### Identity phase (only if worker proceeds)

Immediately after removing `sourceObjectID`, before async setup wiring, run:

- `RhythmLayoutSnapshotBuilderTests`;
- `NotationLayoutEngineTests`;
- `NotationLayoutNotePositionOverrideTests`;
- `DrumTabGoldenTests`;
- `DrumTabRegressionInvariantTests`;
- `DrumTabPlayheadAlignmentTests`.

### Async phase (only if worker proceeds)

Add deterministic tests for:

- stale generation cannot replace newer state;
- current result installs without allocating a second apply generation;
- completion after `cleanup()` cannot set `isGameplayPrepared` or reinstall notation;
- installed timeline setup state matches existing pinned layout/beat expectations;
- no wall-clock sleeps.

### Strict concurrency

If the worker phase proceeds, build with complete Swift concurrency checking. Fix violations by narrowing/copying immutable values, never `@unchecked Sendable`.

### Full-suite baseline

The full `VirgoTests` run is diagnostic because clean `main` has the known nondeterministic detached-context SwiftData crash involving `\Chart.difficulty`.

If the full suite hits that exact failure:

1. reproduce the identical command on clean `main` before classifying it as baseline;
2. record the matching stack/signature;
3. do not use that known failure to waive any different HPA-581 regression.

### Release profile

Repeat HPA-579's representative chart and record:

- chart selection → gameplay prepared;
- main-thread preparation samples;
- initial mount versus **4,890.729 ms**;
- playback/static-body activity;
- row auto-scroll correctness;
- any real width-relayout evidence.

If async preparation proceeds, success means the measured timeline layout/beat-position CPU no longer blocks `@MainActor`; it is **not** required to claim the loading wait itself becomes shorter.

## Alternatives considered

### Do async preparation first

Rejected as ordering. It introduces broad `setupGameplay()` async call-site/lifecycle churn before the independent recurring rendering win is measured. HPA-579 still authorizes it if the Phase-B re-profile says the main-actor preparation stall remains worth removing.

### Use separate layout and request generations

Rejected. The same monotonically increasing notation generation can identify the static layout and invalidate stale workers/resets/cleanup. A second token would violate the ticket's one-mechanism guardrail without adding correctness.

### Defer HPA-581 immediately to HPA-584 because 4.89 s > 267.857 ms

Rejected. HPA-579 explicitly marked both preparation and mount as HPA-581 Proceed inputs, and HPA-584 is defined as the post-HPA-581 virtualization decision. HPA-581 may narrow after its own re-profile, but HPA-584 does not preempt that evidence gate.

### Precompute every static descriptor into prepared state

Rejected as unnecessary duplication. Move O(n) derivations under the Equatable static child first; store a derived projection only if it naturally simplifies the install seam or profiling proves remaining work material.

### Keep the pre-readiness width freshness/re-dispatch loop

Rejected. Existing width normalization/debounce already repairs geometry drift after the prepared sheet mounts; the extra loading-state retry loop is not worth its edge cases.

### Keep `AnyView` caches

Rejected. Type erasure is not raster caching and keeps presentation in the view model.

### Add virtualization now

Rejected. HPA-584 owns it from post-change evidence.

## Acceptance criteria

- [ ] HPA-579 remains the evidence authority; static isolation lands before async setup churn.
- [ ] Every installed/reset notation layout goes through one enforced install funnel and advances one notation generation.
- [ ] That same notation generation is the only stale-worker mechanism if async work proceeds.
- [ ] Static notation is a file-local Equatable child receiving immutable values and no `GameplayViewModel`.
- [ ] O(note/measure) static derivations and row anchors live behind that Equatable boundary.
- [ ] Playhead receives position only; auto-scroll remains narrowly driven by row/playing state.
- [ ] `staticStaffLinesView` / `notationStaffLinesView` and staff-line `AnyView` caching are removed.
- [ ] Release is re-profiled after static isolation before deciding whether async setup migration proceeds.
- [ ] If preparation remains material, timeline-native layout + beat-position preparation move off-main through one Sendable request/result and the same notation generation.
- [ ] If worker phase proceeds, `cleanup()` advances the same generation and stale completion cannot resurrect gameplay.
- [ ] No pre-readiness width retry state machine is added; existing 0.5 pt tolerance + debounce remains the width policy.
- [ ] No SwiftData model, `ModelContext`, `ObjectIdentifier`, or SwiftUI view crosses the worker boundary.
- [ ] No `@unchecked Sendable` is introduced.
- [ ] `sourceObjectID` removal is structurally tested; timeline diagnostics use `RhythmEventID`, while legacy diagnostic degradation is explicit.
- [ ] Identity-sensitive drum-tab goldens/invariants/playhead tests run before async wiring if worker work proceeds.
- [ ] Full-suite known `\Chart.difficulty` baseline failure is explicitly reproduced on clean `main` before classification.
- [ ] HPA-584 remains the post-HPA-581 virtualization decision.