# HPA-581: Off-Main Gameplay Notation Preparation and Static Rendering Design

**Date:** 2026-08-12  
**Status:** Proposed

## Context

HPA-579 established the evidence gate for this work on Release macOS using `soukyuu_e_no_shouka` MASTER (2,870 notes, 156 measures, 900 pt row width):

- chart selection → gameplay prepared: median **267.857 ms**;
- production `GameplayView` initial mount: **4,890.729 ms**;
- named Release frames showed cached layout/notation and beat-position preparation as the dominant preparation stage;
- rhythm resolution and BGM setup were secondary;
- parser/projection work was not the gameplay hot path;
- width-relayout processing was not measured because real display widths tested remained at the 900 pt layout floor;
- HPA-579 therefore marked **HPA-581 = Proceed**, limited to measured gameplay preparation/static-render work.

The current code matches that profile:

- `GameplayViewModel` is `@MainActor` and `setupGameplay()` synchronously calls `computeCachedLayoutData()`;
- `cacheNotationLayout()` invokes `NotationLayoutEngine().layout(input:)` on the main actor;
- `cacheBeatPositions()` then walks the rendered layout on the main actor;
- timeline-native layout already consumes `RhythmLayoutSnapshot`, but that snapshot still carries `ObjectIdentifier` through `RhythmLayoutNote.sourceObjectID`, and `RenderedNoteHead` carries it into rendered values;
- the legacy `NotationLayoutInput` case still contains SwiftData `Note` objects and must not cross actors;
- `GameplaySheetMusicView` renders its static sheet through methods on `GameplayView` while the view model also caches staff-line SwiftUI views as `AnyView`.

This design targets those seams only. It does not introduce a new screen architecture and does not attempt row virtualization; HPA-584 owns that decision after re-profiling.

## Goals

1. Move the measured timeline-native notation layout and beat-position derivation off `@MainActor`.
2. Keep SwiftData relationship access, rhythm resolution, model lookup maps, observable state changes, and audio/input setup on `@MainActor`.
3. Cross the actor boundary through one immutable Sendable request and one immutable prepared result.
4. Use one generation counter to prevent stale asynchronous preparation from becoming active.
5. Never publish a first layout whose request width is already known to be stale.
6. Install the complete prepared notation state coherently.
7. Make the static notation subtree a real Equatable child that depends on immutable layout data rather than the full gameplay view model.
8. Keep playhead and auto-scroll dependencies narrow.
9. Remove `staticStaffLinesView`, `notationStaffLinesView`, and their `AnyView` caching.
10. Preserve notation geometry, timing/input mappings, resize behavior, accessibility, and existing rendering regressions.

## Non-goals

- Moving SwiftData `Chart`, `Song`, `Note`, `ChartControlEvent`, `ModelContext`, or model identity across actors.
- Moving `RhythmTimelineResolver` or `RhythmLayoutSnapshotBuilder` off-main without new profiling evidence. HPA-579 found rhythm resolution secondary to notation preparation.
- Making the legacy `NotationLayoutInput` Sendable. Its `.legacy` case intentionally contains SwiftData `Note` values.
- Rewriting `NotationLayoutEngine`, `NotationRhythmAnalyzer`, `RhythmTimelineBuilder`, or gameplay timing algorithms.
- Creating a notation actor, scheduler, repository/use-case layer, worker pool, or generic async job framework.
- Adding a permanent benchmark harness or CI performance gate.
- Adding lazy row virtualization. HPA-584 owns that decision.
- Moving post-prepared live width relayout off-main without evidence. The mandatory width rule in this design concerns freshness across the new **initial async preparation gap**, not speculative live-resize optimization.
- Promising that this ticket removes the 4.89 s eager initial mount. Static-observation isolation should stop broad repeated work during playback, but the initial 2,870-note tree remains eager until post-change profiling justifies HPA-584.

## Decision

### 1. Keep extraction, rhythm resolution, and runtime model lookup on MainActor

`loadChartData()` continues to:

1. read SwiftData relationships;
2. copy the model values already used by gameplay;
3. run `RhythmTimelineResolver`;
4. build `GameplayRhythmRuntime` and `RhythmLayoutSnapshot`;
5. retain `noteByEventID`, `positionByNoteObjectID`, and other model-reference lookup dictionaries only in the main-actor runtime.

This is intentionally narrower than the conceptual maximum scope in HPA-581. HPA-579 did not show rhythm resolution as the dominant cost, so moving it would add Sendable surface without evidence.

`RhythmLayoutSnapshotBuilder` also remains on `@MainActor`. The worker begins only after the timeline snapshot exists.

### 2. Make the timeline layout value graph semantically safe for the worker

`RhythmLayoutSnapshot` is the right conceptual boundary, but the current graph still contains model identity:

- `RhythmLayoutNote.sourceObjectID`;
- `RenderedNoteHead.sourceObjectID`.

The important rule is semantic, not merely compiler-driven. `ObjectIdentifier` itself is Sendable, so a generic `T: Sendable` assertion is **not sufficient** to prove the worker graph is free of model identity.

For the timeline path:

- use `RhythmEventID` as the stable source identity;
- remove `sourceObjectID` from `RhythmLayoutNote` and `RenderedNoteHead`;
- keep model lookup by `RhythmEventID` in `GameplayRhythmRuntime` on `@MainActor`;
- update timeline dropped-note diagnostics to compare rendered `eventID`s with `GameplayRhythmRuntime.noteByEventID`/its keys;
- keep legacy-only fallback diagnostics main-actor local rather than preserving object identity in rendered values.

Add normal `Sendable` conformances to immutable enums/structs needed by the timeline request/result graph. Do **not** use `@unchecked Sendable` to silence compiler errors, and do not add Sendable conformance to SwiftData model classes.

The whole `NotationLayoutInput` remains non-Sendable because `.legacy(notes:...)` owns SwiftData references. The worker constructs a timeline-only `NotationLayoutInput` locally from its Sendable request.

Verification must include both:

1. compile-time `Sendable` assertions for the request/result graph; and
2. a structural regression assertion that timeline/render worker values no longer expose a `sourceObjectID` field. Reuse the repository's existing `Mirror`-based omitted-API test style rather than relying on the compiler to reject `ObjectIdentifier`.

### 3. Add one pure timeline preparation boundary

Introduce one value request and one value result, conceptually:

```swift
struct GameplayNotationPreparationRequest: Sendable {
    let snapshot: RhythmLayoutSnapshot
    let minimumMeasureCount: Int
    let style: NotationLayoutStyle
    let notePositionOverrides: [DrumType: GameplayLayout.NotePosition]
    let beatPositionsByID: [UInt64: RhythmEventPosition]
}

struct GameplayNotationPreparedState: Sendable {
    let layout: NotationLayout
    let beatPositionsByID: [UInt64: CGPoint]
    // Existing hot lookup maps may live here when coherent installation benefits.
}

struct GameplayNotationPreparer {
    static func prepare(
        _ request: GameplayNotationPreparationRequest
    ) -> GameplayNotationPreparedState
}
```

The exact field spelling may change during implementation, but the boundary stays one request and one prepared value.

`GameplayNotationPreparer.prepare` is synchronous, pure value work. It:

1. constructs `NotationLayoutInput(timing: .timeline(...))` locally;
2. calls the existing `NotationLayoutEngine`;
3. derives timeline beat positions using the same `TabGrid`/rendered-measure math as `cacheTimelineNotationBeatPositions()`;
4. derives only the existing lookup caches that are genuinely hot or needed for coherent installation;
5. returns one prepared value.

No SwiftData object, model identity, SwiftUI `View`, `AnyView`, `ModelContext`, observable reference, or actor-isolated service appears in either boundary value.

### 4. Dispatch only the measured timeline path

`setupGameplay()` becomes async so the production call site can await preparation before exposing `isGameplayPrepared = true`.

For a valid timeline runtime:

```text
@MainActor
  compute drum beats
  resolve current floored row width
  build Sendable request
  increment generation
        |
        v
Task.detached(.userInitiated)
  NotationLayoutEngine.layout
  beat-position derivation
        |
        v
@MainActor
  generation still current?
  request row width still current?
  yes + yes -> install prepared state
  otherwise -> discard/re-dispatch latest request
```

The legacy path remains synchronous on `@MainActor` because its layout input contains SwiftData `Note`s. This avoids manufacturing a second model-copy system for an unmeasured compatibility path.

Audio/input/metronome configuration remains main-actor code. Preserve existing semantic ordering unless a test proves a reordering is safe.

### 5. One generation is the stale-result correctness mechanism

`GameplayViewModel` owns one monotonically increasing notation-preparation generation. Starting an asynchronous preparation increments it; completion applies only when its captured generation equals the current generation.

Cancellation may be used to reduce wasted work when a view disappears or a newer request supersedes an older one, but cancellation is not a second correctness mechanism. The generation check remains authoritative.

Do not add request registries, actor mailboxes, UUID maps, or multiple tokens.

### 6. Treat row width as request input through first install

The new async initial-preparation gap introduces a correctness case that does not exist in the current synchronous setup.

Today `GameplayView.prepareGameplay(initialRowWidth:)` seeds width immediately before `setupGameplay()`. After HPA-581, the worker may spend material time preparing that layout while the outer `GeometryReader` changes size. The sheet-music subtree is not mounted until `isGameplayPrepared` becomes true, so its current `onAppear` / `onChange(of: geometry.size.width)` handlers cannot keep the in-flight request fresh.

Therefore initial preparation has this mandatory rule:

1. the outer `GeometryReader` keeps `cachedLayoutRowWidth` updated even while gameplay is loading;
2. every timeline preparation request owns its **floored row width** through `NotationLayoutStyle.rowWidth`;
3. when a worker result returns, apply requires both:
   - the captured generation is current; and
   - `request.style.rowWidth == max(GameplayLayout.maxRowWidth, cachedLayoutRowWidth)` using the same width tolerance/normalization semantics as the existing cache;
4. if the width no longer matches, invalidate/bump generation and dispatch a new request using the latest width **before** setting `isGameplayPrepared = true`;
5. never mount a layout at a width already known to be stale and then immediately repack it on the first visible frame.

Use the same generation counter. Width freshness is an apply predicate, not a second stale-token system.

Add a deterministic regression: start from request generation N at 900 pt, update the cached loading width to a packing-changing width, prove N cannot become prepared, then prove generation N+1/latest width is the state that installs.

This rule is distinct from live resize after gameplay is prepared.

### 7. Post-prepared width relayout remains evidence-gated

HPA-579 could not measure a real post-prepared width relayout because tested display widths stayed at the 900 pt floor. Therefore HPA-581 should **not** add a new asynchronous live-relayout lifecycle solely because one was proposed earlier.

During HPA-581 verification:

- keep the existing trailing-edge debounce;
- attempt a natural width change that actually changes row packing;
- if a real host change exists and profiling shows material layout work blocking the main actor, route that relayout through the **same** preparer and generation counter;
- otherwise leave post-prepared relayout synchronous and record that it remained unproven/untriggerable under the baseline host.

This does not weaken the first-install width rule above: known stale initial results are always rejected.

### 8. Store/install prepared notation coherently

The worker result should also be the unit installed by the view model, rather than copying one field at a time from unrelated temporary objects.

Prefer one stored prepared-notation value with narrow computed accessors for existing consumers when that avoids half-built combinations of:

- notation layout;
- measure lookup maps;
- note-head positions;
- beat positions.

Do not force cheap one-off render descriptors or row counts into the prepared value only for architectural symmetry.

Fatal/empty layout behavior remains explicit and main-actor controlled.

### 9. Isolate the static notation subtree as a real Equatable child

Current static rendering lives in `GameplayView` methods such as `staticSheetMusicContent` and `drumNotationView`. Merely passing fewer values to another helper method does not create a SwiftUI invalidation boundary; parent body evaluation can still rebuild the static tree.

Refactor the sheet into a small observable container plus file-local child views:

```text
sheet container(viewModel)
  |- GameplayStaticNotationView(layout/static values, generation)
  |- GameplayPlayheadBarView(position: CGPoint?)
  `- auto-scroll hooks(currentRow + isPlaying)
```

`GameplayStaticNotationView` must:

- be a separate file-local `View` type;
- conform to `Equatable` with `==` comparing the active prepared-layout generation, not deep-comparing `NotationLayout`;
- be used through SwiftUI's equatable boundary (for example `.equatable()`), so unchanged generation skips static body re-evaluation;
- receive immutable layout/static values and **not receive `GameplayViewModel`**;
- rely on the invariant that every installed layout change advances the generation.

Do **not** use `.id(generation)` as the optimization. `.id` changes identity and remounts the subtree when the layout changes; the goal is to skip reevaluation while identity remains stable.

`GameplayPlayheadBarView` receives only `CGPoint?` (or the existing equivalent value tuple) rather than the full view model. Auto-scroll `onChange` hooks stay on the observable container and read only `currentRow` / `isPlaying` plus the minimal static predicate needed for scrolling.

`StaffLinesBackgroundView` is built normally from immutable measure/layout values inside the static child. Remove `staticStaffLinesView` and `notationStaffLinesView` from `GameplayViewModel`; caching `AnyView` does not cache pixels and mixes presentation into orchestration.

Do not precompute printed-rest filters, clef/time-signature labels, row count, or similar cheap SwiftUI values unless profiling or a natural API boundary justifies them.

## Data and actor flow

```text
@MainActor
SwiftData Chart/Note/Control
      |
      v
RhythmTimelineResolver + GameplayRhythmRuntime
      |
      v
RhythmLayoutSnapshot (Sendable, RhythmEventID identity only)
      |
      + note-position overrides
      + beat rhythm positions
      + current floored row width
      |
      v
GameplayNotationPreparationRequest(generation N)
      |
      v
Task.detached(.userInitiated)
NotationLayoutEngine + timeline beat-position derivation
      |
      v
GameplayNotationPreparedState
      |
      v
@MainActor generation + row-width freshness check
      | stale -> dispatch N+1 before ready
      | current
      v
one coherent install -> isGameplayPrepared = true
      |
      +--> Equatable static notation child (immutable layout, equality = generation)
      +--> playhead position-only child
      `--> auto-scroll row/playing state
```

## Failure and cancellation behavior

`NotationLayoutEngine.layout` is currently nonthrowing. Keep the worker nonthrowing unless implementation uncovers a real failure that must propagate.

- Fatal rhythm timing continues to short-circuit on `@MainActor` before worker dispatch.
- Empty layout remains a valid prepared result.
- A cancelled or stale-generation result cannot install state.
- A result whose request width is no longer current cannot install state; preparation repeats with the latest known width before readiness.
- Do not add retries for computation failure; the one re-dispatch case above is input freshness, not retry policy.

## Verification contract

### Task-1 identity and layout gate

Before wiring the worker into `setupGameplay`, run the identity-sensitive rendering suites after removing `sourceObjectID`:

- `RhythmLayoutSnapshotBuilderTests`;
- `NotationLayoutEngineTests`;
- `NotationLayoutNotePositionOverrideTests`;
- `DrumTabGoldenTests`;
- `DrumTabRegressionInvariantTests`;
- `DrumTabPlayheadAlignmentTests`.

This catches a silent Hashable/digest/geometry identity change before async setup is layered on top. If the digest never emitted object identity, the suites should remain green and prove that immediately.

### New focused seam tests

Add focused tests for:

1. compile-time Sendable assertions for request/prepared boundary values;
2. structural absence of `sourceObjectID` from timeline/render worker values;
3. pure preparer equivalence with the current timeline layout/beat-position results;
4. stale generation completion cannot replace newer prepared state;
5. stale **initial row width** completion cannot become ready and re-dispatches the latest width before first install;
6. static child equality remains true when only high-frequency playback state changes and false when layout generation changes;
7. existing mounting/raster smoke still proves the production notation primitives are actually mounted.

Do not use wall-clock sleeps to test concurrency. Drive request generation/application deterministically.

### Swift concurrency compile check

Build with complete strict concurrency checking. Treat any attempted SwiftData/model-identity crossing as a design failure rather than adding `@unchecked Sendable`.

Compiler success alone does not prove the semantic identity rule; keep the explicit structural assertion.

### Focused end-to-end regression gate

The final focused gate includes at least:

- `GameplayNotationPreparationTests`;
- `RhythmLayoutSnapshotBuilderTests`;
- `NotationLayoutEngineTests`;
- `GameplayViewModelLayoutComputationsTests`;
- `GameplaySheetMusicMountingTests`;
- `DrumTabGoldenTests`;
- `DrumTabRegressionInvariantTests`;
- `DrumTabPlayheadAlignmentTests`.

Then run the full Virgo suite.

### Performance re-profile

Repeat HPA-579's Release macOS representative chart and record:

- chart selection → gameplay prepared;
- whether the expensive notation layout/beat-position work is absent from main-thread samples;
- whether first install required a width re-dispatch and whether any stale layout became visible (it must not);
- initial production notation mount;
- playback SwiftUI/main-thread activity with the Equatable static subtree isolated;
- post-prepared width relayout only if a natural host width can actually change row packing.

Success is directional and evidence-based rather than a fabricated universal millisecond threshold:

- measured timeline layout/beat-position CPU should no longer block the main actor during timeline-native initial preparation;
- a known-stale first-width result never becomes visible;
- static notation should not broadly re-evaluate because the playhead moves;
- notation/timing behavior remains equivalent;
- if eager initial mount remains dominant, record that result and let HPA-584 decide virtualization.

## Alternatives considered

### Move all rhythm resolution and model extraction off-main

Rejected. HPA-579 did not identify resolution as the dominant cost, and doing this safely would require a much larger scalar-copy boundary for SwiftData relationships.

### Create a dedicated notation actor/service

Rejected. The operation is deterministic request → result CPU work. A detached task plus one generation counter provides the needed concurrency and stale-result protection with less lifecycle/state.

### Make `NotationLayoutInput` Sendable

Rejected. Its legacy case intentionally owns `[Note]`, so forcing Sendable would either be unsafe or require a second data model. The worker constructs a timeline-only input locally.

### Rely only on `Sendable` compilation to remove `ObjectIdentifier`

Rejected. `ObjectIdentifier` itself can satisfy Sendable, so compilation is not the semantic boundary check. The source field must be removed explicitly and protected by structural tests.

### Keep static rendering as methods on `GameplayView`

Rejected. Passing values into helper methods does not form the intended Equatable child boundary. Use a separate file-local Equatable `View` keyed by prepared-layout generation.

### Use `.id(generation)` for static isolation

Rejected. That forces remounting on generation changes rather than skipping unchanged static reevaluation.

### Cache more `AnyView`s or cache the complete sheet as `AnyView`

Rejected. Type erasure does not create a rendered-output cache and keeps view concerns in the view model.

### Add row virtualization now

Rejected. The 4.89 s eager mount makes virtualization a plausible next step, but HPA-584 deliberately owns the post-change decision.

## Acceptance criteria

- [ ] HPA-579's **Proceed** decision remains the scope authority.
- [ ] Timeline-native notation layout and beat-position preparation run outside `@MainActor`.
- [ ] Rhythm resolver, snapshot builder, SwiftData extraction, model lookup maps, and observable assignment remain `@MainActor`.
- [ ] The off-main boundary is one Sendable request and one Sendable prepared value.
- [ ] No SwiftData model, `ModelContext`, model `ObjectIdentifier`, or SwiftUI view crosses that boundary.
- [ ] `sourceObjectID` is explicitly absent from timeline/render worker values; compiler Sendable checks are not the only guard.
- [ ] No `@unchecked Sendable` is introduced to bypass the boundary.
- [ ] One generation counter prevents stale preparation from becoming active.
- [ ] Initial preparation also rejects a result whose request row width no longer matches the latest cached floored width, re-dispatching before readiness.
- [ ] Post-prepared width relayout is moved off-main only if HPA-581 verification produces real evidence for it; otherwise the existing debounce/path remains.
- [ ] Static notation is a separate Equatable child whose equality is prepared-layout generation and whose input contains no `GameplayViewModel`.
- [ ] The static child is not keyed with `.id(generation)`.
- [ ] Playhead observation is position-only and auto-scroll remains row/playing-only.
- [ ] `staticStaffLinesView` and `notationStaffLinesView` are removed.
- [ ] Task-1 golden/invariant/playhead suites pass immediately after identity removal.
- [ ] Existing notation, timing, mounting, scroll, accessibility, and input behavior remains covered.
- [ ] Release re-profiling records the post-change preparation/mount result for HPA-584.
