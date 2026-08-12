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
- timeline-native layout already consumes `RhythmLayoutSnapshot`, but that snapshot still carries `ObjectIdentifier` through `RhythmLayoutNote` / `RenderedNoteHead`;
- the legacy `NotationLayoutInput` case still contains SwiftData `Note` objects and must not cross actors;
- `GameplaySheetMusicView` mixes broad `GameplayViewModel` observation with static notation rendering, while the view model caches staff-line SwiftUI views as `AnyView`.

This design targets those seams only. It does not introduce a new screen architecture and does not attempt row virtualization; HPA-584 owns that decision after re-profiling.

## Goals

1. Move the measured timeline-native notation layout and beat-position derivation off `@MainActor`.
2. Keep SwiftData relationship access, rhythm resolution, model lookup maps, observable state changes, and audio/input setup on `@MainActor`.
3. Cross the actor boundary through one immutable Sendable request and one immutable prepared result.
4. Use one generation counter to prevent stale asynchronous preparation from becoming active.
5. Install the complete prepared notation state coherently.
6. Make the static notation subtree depend on immutable layout data rather than the full gameplay view model.
7. Keep playhead and auto-scroll dependencies narrow.
8. Remove `staticStaffLinesView`, `notationStaffLinesView`, and their `AnyView` caching.
9. Preserve notation geometry, timing/input mappings, resize behavior, accessibility, and existing rendering regressions.

## Non-goals

- Moving SwiftData `Chart`, `Song`, `Note`, `ChartControlEvent`, `ModelContext`, or `ObjectIdentifier` across actors.
- Moving `RhythmTimelineResolver` or `RhythmLayoutSnapshotBuilder` off-main without new profiling evidence. HPA-579 found rhythm resolution secondary to notation preparation.
- Making the legacy `NotationLayoutInput` Sendable. Its `.legacy` case intentionally contains SwiftData `Note` values.
- Rewriting `NotationLayoutEngine`, `NotationRhythmAnalyzer`, `RhythmTimelineBuilder`, or gameplay timing algorithms.
- Creating a notation actor, scheduler, repository/use-case layer, worker pool, or generic async job framework.
- Adding a permanent benchmark harness or CI performance gate.
- Adding lazy row virtualization. HPA-584 owns that decision.
- Promising that this ticket removes the 4.89 s eager initial mount. Static-observation isolation should stop repeated broad work during playback, but the initial 2,870-note tree remains eager until post-change profiling justifies HPA-584.

## Decision

### 1. Keep extraction and rhythm resolution on MainActor

`loadChartData()` continues to:

1. read SwiftData relationships;
2. copy model values already used by gameplay;
3. run `RhythmTimelineResolver`;
4. build `GameplayRhythmRuntime` and `RhythmLayoutSnapshot`;
5. retain model-reference lookup dictionaries only in the main-actor runtime.

This is intentionally narrower than the conceptual maximum scope in HPA-581. HPA-579 did not show rhythm resolution as the dominant cost, so moving it would add Sendable surface without evidence.

### 2. Make the existing timeline layout value graph genuinely Sendable

`RhythmLayoutSnapshot` is already the correct conceptual boundary, but today it is not a valid worker payload because `RhythmLayoutNote.sourceObjectID` carries `ObjectIdentifier` into layout and `RenderedNoteHead` carries it back out.

For the timeline path:

- use `RhythmEventID` as the stable source identity;
- remove `ObjectIdentifier` from `RhythmLayoutNote` and from the rendered value graph that crosses the worker boundary;
- keep model lookup by `RhythmEventID` in `GameplayRhythmRuntime` on `@MainActor`;
- update dropped-note diagnostics to compare timeline render results by `RhythmEventID` on the main actor;
- keep any legacy-only fallback diagnostics main-actor local rather than preserving object identity in worker values.

Add normal `Sendable` conformances to immutable enums/structs needed by the timeline request/result graph. Do **not** use `@unchecked Sendable` to silence compiler errors, and do not add Sendable conformance to SwiftData model classes.

The whole `NotationLayoutInput` must remain non-Sendable because `.legacy(notes:...)` owns SwiftData references. The worker constructs a timeline-only `NotationLayoutInput` locally from its Sendable request.

### 3. Add one pure timeline preparation boundary

Introduce a small value-oriented helper, conceptually:

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
    // Existing hot lookup maps derived from layout may live here when needed.
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
3. derives timeline beat positions from the completed layout;
4. derives only the existing lookup caches that are genuinely hot or needed for coherent installation;
5. returns one prepared value.

No SwiftData object, `ObjectIdentifier`, SwiftUI `View`, `AnyView`, `ModelContext`, observable reference, or actor-isolated service appears in either boundary value.

### 4. Dispatch only the measured timeline path

`setupGameplay()` becomes async so the production call site can await preparation before exposing `isGameplayPrepared = true`.

For a valid timeline runtime:

```text
MainActor
  compute drum beats
  build Sendable request
  increment generation
        |
        v
Task.detached(.userInitiated)
  NotationLayoutEngine.layout
  beat-position derivation
        |
        v
MainActor
  generation still current?
  yes -> install prepared state
  no  -> discard
```

The legacy path remains synchronous on `@MainActor` because its layout input contains SwiftData `Note`s. This avoids manufacturing a second model-copy system for an unmeasured compatibility path.

Audio/input/metronome configuration remains main-actor code. It may execute before or after the detached result is awaited according to existing ordering constraints; do not reorder observable playback semantics merely to overlap a few cheap operations.

### 5. One generation is the stale-result correctness mechanism

`GameplayViewModel` owns one monotonically increasing notation-preparation generation. Starting a preparation increments it; completion applies only when its captured generation equals the current generation.

Cancellation may be used to reduce wasted work when a view disappears or a newer request supersedes an older one, but cancellation is not a second correctness mechanism. The generation check remains authoritative.

Do not add request registries, actor mailboxes, UUID maps, or multiple tokens.

### 6. Width relayout remains evidence-gated

HPA-579 could not measure a real width relayout because tested display widths stayed at the 900 pt floor. Therefore HPA-581 should **not** add a new asynchronous relayout lifecycle solely because one was proposed earlier.

Implementation should still extract the timeline layout calculation behind `GameplayNotationPreparer`, so width relayout has one reusable path if later evidence justifies it.

During HPA-581 verification:

- keep the existing small trailing-edge debounce;
- attempt a natural width change that actually changes row packing;
- if the real host can produce such a change and Time Profiler shows the same material layout work blocking the main actor, route that relayout through the **same** preparer and generation counter;
- otherwise leave width relayout synchronous and record that it remained unproven/untriggerable under the baseline host.

This keeps the ticket faithful to HPA-579 instead of converting an unmeasured resize hypothesis into mandatory architecture.

### 7. Store/install prepared notation coherently

The result returned by the worker should also be the unit installed by the view model, rather than copying one field at a time from unrelated temporary objects.

Prefer one stored prepared-notation value with narrow computed accessors for existing consumers when that avoids half-built combinations of:

- notation layout;
- measure lookup maps;
- note-head positions;
- beat positions.

Do not force cheap one-off render descriptors or row counts into the prepared value only for architectural symmetry.

Fatal/empty layout behavior remains explicit and main-actor controlled.

### 8. Isolate the static notation subtree without a new UI framework

Refactor `GameplaySheetMusicView` into a small observable container plus value-driven children:

```text
GameplaySheetMusicView(viewModel)
  |- static notation child(layout/static values, preparation generation)
  |- playhead child(position only)
  `- auto-scroll container(currentRow + isPlaying only)
```

The static child receives immutable layout/static inputs and **does not receive `GameplayViewModel`**.

Use the existing preparation generation (or another already-existing stable layout identity if one naturally fits) as the cheap equality key for the static child. Do not compare the full 2,870-note layout every 30 Hz merely to prove equality.

The playhead child receives only its current position. Auto-scroll remains isolated to the row/playing state it actually needs.

`StaffLinesBackgroundView` is built normally from layout/measure values inside the static subtree. Remove `staticStaffLinesView` and `notationStaffLinesView` from `GameplayViewModel`; caching `AnyView` does not cache pixels and mixes presentation into orchestration.

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
RhythmLayoutSnapshot (Sendable, stable value identity only)
      |
      + note-position overrides + beat rhythm positions
      |
      v
GameplayNotationPreparationRequest
      |
      v
Task.detached(.userInitiated)
NotationLayoutEngine + timeline beat-position derivation
      |
      v
GameplayNotationPreparedState
      |
      v
@MainActor generation check -> one coherent install
      |
      +--> static notation subtree (immutable layout values)
      +--> playhead position overlay
      `--> auto-scroll row/playing state
```

## Failure and cancellation behavior

`NotationLayoutEngine.layout` is currently nonthrowing. Keep the worker nonthrowing unless implementation uncovers a real failure that must propagate.

- Fatal rhythm timing continues to short-circuit on `@MainActor` before worker dispatch.
- Empty layout remains a valid prepared result.
- A cancelled or stale task cannot install state because the generation check rejects it.
- Do not add retries; layout preparation is deterministic local CPU work.

## Verification contract

### Functional regressions

Keep existing coverage as the primary proof:

- `RhythmLayoutSnapshotBuilderTests` for timeline snapshot semantics;
- `NotationLayoutEngineTests` and existing notation geometry/golden tests for engraving/layout behavior;
- `GameplayViewModelLayoutComputationsTests` for row maps, cached beat positions, duration and layout integration;
- `GameplaySheetMusicMountingTests` for the production notation subtree raster smoke;
- existing playhead/input/timing tests for behavior outside the static refactor.

Add focused tests only for the new seam:

1. compile-time Sendable assertions for request/prepared boundary values;
2. pure preparer equivalence with the current timeline layout/beat-position results;
3. stale generation completion cannot replace newer prepared state;
4. static render input/generation remains unchanged when only high-frequency playback fields change.

Do not use wall-clock sleeps to test concurrency. Drive generation/application deterministically.

### Swift concurrency compile check

Build with complete strict concurrency checking and treat any attempted SwiftData/object-identity crossing as a design failure rather than adding `@unchecked Sendable`.

### Performance re-profile

Repeat HPA-579's Release macOS representative chart and record:

- chart selection → gameplay prepared;
- whether the expensive notation layout/beat-position work is absent from main-thread samples;
- initial production notation mount;
- playback SwiftUI/main-thread activity with the static subtree isolated;
- width relayout only if a natural host width can actually change row packing.

Success is directional and evidence-based rather than a fabricated universal millisecond threshold:

- the measured layout/beat-position CPU should no longer block the main actor during timeline-native initial preparation;
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

### Keep `ObjectIdentifier` in the worker result

Rejected. HPA-581 explicitly forbids it, and timeline-native rendering already has stable `RhythmEventID` identity.

### Cache more `AnyView`s or cache the complete sheet as `AnyView`

Rejected. Type erasure does not create a rendered-output cache and keeps view concerns in the view model. Immutable value inputs plus narrow observation are simpler and testable.

### Add row virtualization now

Rejected. The 4.89 s eager mount makes virtualization a plausible next step, but HPA-584 deliberately owns the post-change decision.

## Acceptance criteria

- [ ] HPA-579's **Proceed** decision remains the scope authority.
- [ ] Timeline-native notation layout and beat-position preparation run outside `@MainActor`.
- [ ] Rhythm resolver, SwiftData extraction, model lookup maps, and observable assignment remain `@MainActor`.
- [ ] The off-main boundary is one Sendable request and one Sendable prepared value.
- [ ] No SwiftData model, `ModelContext`, `ObjectIdentifier`, or SwiftUI view crosses that boundary.
- [ ] No `@unchecked Sendable` is introduced to bypass the boundary.
- [ ] One generation counter prevents stale preparation from becoming active.
- [ ] Width relayout is moved off-main only if HPA-581 verification produces real evidence for it; otherwise the existing debounce/path remains.
- [ ] The static notation subtree receives immutable layout/static values and no `GameplayViewModel`.
- [ ] Playhead observation is position-only and auto-scroll remains row/playing-only.
- [ ] `staticStaffLinesView` and `notationStaffLinesView` are removed.
- [ ] Existing notation, timing, mounting, scroll, accessibility, and input behavior remains covered.
- [ ] Release re-profiling records the post-change preparation/mount result for HPA-584.
