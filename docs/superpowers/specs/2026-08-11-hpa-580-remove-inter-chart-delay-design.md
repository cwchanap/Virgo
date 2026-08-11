# HPA-580: Remove the Fixed Inter-Chart Import Delay

**Date:** 2026-08-11
**Status:** Proposed

## Context

HPA-580 is the first Phase C follow-up after HPA-579's profiling gate.

HPA-579 measured the representative four-chart local import in an optimized Release build and found:

- aggregate DTX parse/projection: **29.073002 ms median**;
- whole fresh import: **7,138.560166 ms median**, dominated by SwiftData model creation, relationship insertion, and save;
- fixed inter-chart policy delay: **300 ms** for four charts.

The server post-download path could not be profiled on that host, so the evidence does **not** justify moving parser/projection work, file work, SwiftData models, or `ModelContext` off the main actor. HPA-579 therefore narrowed HPA-580 to one policy cleanup: remove the unconditional 100 ms delay between serial chart imports.

Today `ServerSongDownloader.processCharts` does this before every chart after the first:

```swift
// Throttle chart downloads to avoid overwhelming the server.
if index > 0 { try await Task.sleep(nanoseconds: 100_000_000) }
```

Because each iteration already awaits `processChart(...)` to completion before advancing, the loop is serial independently of that sleep. The sleep adds latency; it does not provide serialization.

## Decision

Delete the fixed delay and its stale throttle comment with **no replacement cancellation primitive**.

The loop becomes a direct serial iteration over `snapshot.charts`:

```swift
for chartSnapshot in snapshot.charts {
    do {
        // existing processChart call and error handling remain unchanged
    }
}
```

The previous `enumerated()` index exists only to support the delay and should disappear with it.

This is the smallest change that matches the HPA-579 evidence. Do not replace the deleted policy with `Task.checkCancellation()`, an injected sleeper, a clock, a rate limiter, or any other new invariant.

## Why the loop remains serial

The existing loop awaits one complete chart import before starting the next:

```text
chart 1 download -> decode -> parse -> project -> SwiftData mutation
    await completion
chart 2 download -> decode -> parse -> project -> SwiftData mutation
    await completion
...
```

Removing the delay does not overlap those operations. The next `processChart(...)` call is not made until the previous call returns.

Optional BGM/preview downloads also remain after chart processing, exactly as today.

## Cancellation contract

HPA-580 does not need a new between-chart cancellation contract.

The current meaningful behavior is inside `processCharts` error classification:

- a `CancellationError` thrown by chart processing aborts chart processing and reaches `downloadAndImportSong`'s outer failure path;
- a normal chart-specific error is logged, recorded in `failedCharts`, and the next chart is attempted;
- if every chart fails normally, the existing `chartFailure` error remains unchanged.

The existing `testCancellationErrorPropagation` exercises this real path by having the second chart download throw `CancellationError`. It does **not** exercise the current inter-chart sleep, and the implementation plan must not claim that it verifies a replacement checkpoint.

The throwing sleep incidentally observed cancellation while spending 100 ms between charts. Once that intentional delay is removed, preserving that exact observation window is not a product requirement. Adding `Task.checkCancellation()` only to retain it would turn an incidental implementation detail into a new explicit invariant without evidence or regression coverage.

Do not add a dedicated "cancel in the gap" test. The gap has no deliberate work after this change, and test machinery for it would cost more than the behavior it protects.

## Behavior that must stay unchanged

### Chart ordering

Process `snapshot.charts` in its existing order. Do not sort, reorder, fan out, or race requests.

### Partial failure

A bad chart must not prevent later valid charts from importing. Existing warning/failure collection remains untouched.

### All-chart failure

If no chart succeeds and the snapshot contained charts, continue throwing `ServerSongImportError.chartFailure` with the failed filenames.

### Cancellation classification

A `CancellationError` thrown by `processChart(...)` or its downloader must continue to abort the import rather than being downgraded into a recoverable chart failure.

### Warnings

Projection warnings continue to be collected and returned in chart order.

### SwiftData ownership

`processCharts`, `processChart`, model construction, relationship mutation, insertion, and save remain on the main actor. HPA-579 did not justify moving them.

### Audio/download status

BGM and preview download behavior remains after chart processing. No file-path, save, rollback, or server-download-status behavior changes here.

## Test strategy

This is intentional-latency deletion. Do **not** create production timing seams just to manufacture a red unit test for the removed 100 ms wait.

Use the existing `ServerSongDownloaderTests` seam and protect the surrounding behavior instead:

1. Strengthen the existing four-difficulty import test to assert the exact request sequence:
   - easy chart;
   - medium chart;
   - hard chart;
   - expert chart;
   - BGM;
   - preview.

   This pins snapshot request order and the chart-before-audio boundary. It is a semantic regression guard, not proof of latency removal.

2. Re-run the existing cancellation test that proves a `CancellationError` thrown from chart processing is not downgraded into a per-chart failure.

3. Re-run the existing partial-chart-failure and all-chart-failure tests; they already protect the continuation/aggregate-failure behavior this edit must not disturb.

4. Use a source audit after the production edit to prove the obsolete policy is gone. The production file should contain no inter-chart `Task.sleep`, `100_000_000`, or stale "throttle" comment.

The source audit, not the URL-order assertion, verifies that the deliberate delay was actually removed.

Do not add an elapsed-time assertion such as "four charts complete in under 300 ms." SwiftData/parser work and host load would make that test flaky and would turn one measured policy decision into a permanent performance threshold.

## Approaches considered

### Delete the sleep with no replacement — selected

Pros:

- removes the full 100 ms per-gap latency;
- leaves serialization with the existing awaited `processChart(...)` call;
- preserves the actual cancellation error-classification contract;
- deletes the now-unused loop index;
- changes no public interface;
- adds no production abstraction or ceremonial invariant.

Cons:

- the exact latency deletion is verified by source inspection plus HPA-579 evidence rather than a wall-clock unit test.

That trade-off is correct for this ticket.

### Replace sleep with `Task.checkCancellation()` — rejected

This would preserve an explicit cancellation observation point only if cancellation is already pending at the top of a later chart iteration. The existing cancellation regression does not exercise that point, and HPA-580 does not require a between-chart cancellation window once the 100 ms delay disappears.

Keeping the check would therefore make a new line load-bearing in the documentation without evidence that the behavior matters. Do not add a new cancel-task test merely to justify it.

### Make throttling configurable or inject a sleeper/clock — rejected

A configurable delay, sleep closure, clock protocol, rate limiter, or request scheduler would add maintenance surface for a policy HPA-579 already decided to delete. There is no current server-rate-limit evidence requiring a replacement throttle.

### Parallelize chart downloads — rejected

Parallelism would change network pressure, mutation ordering, failure behavior, and SwiftData coordination. HPA-580 explicitly keeps downloads serial, and profiling did not justify a concurrency redesign.

## Files in scope

### Production

- `Virgo/utilities/ServerSongDownloader.swift`
  - remove the fixed inter-chart sleep/comment;
  - simplify `for (index, chartSnapshot) in snapshot.charts.enumerated()` to `for chartSnapshot in snapshot.charts`;
  - do not otherwise restructure `processCharts` or `processChart`.

### Tests

- `VirgoTests/ServerSongDownloaderTests.swift`
  - strengthen the multi-chart request-order assertion;
  - rely on the existing cancellation, partial-failure, and all-failure coverage rather than creating timing or gap-cancellation infrastructure.

No other production or test file should need changes unless implementation reveals a direct compile/test dependency.

## Verification

Focused verification should run with parallel testing disabled per the repository policy:

```bash
xcodebuild test \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'platform=macOS' \
  -configuration Debug \
  -only-testing:VirgoTests/ServerSongDownloaderTests \
  -parallel-testing-enabled NO \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  -destination-timeout 300 \
  -derivedDataPath ./DerivedData
```

Then run the complete nonparallel `VirgoTests` suite before the implementation PR is made ready for review.

Also run:

```bash
swiftlint lint --quiet
git diff --check
git grep -n -E 'Task\.sleep|100_000_000|Throttle chart downloads' -- Virgo/utilities/ServerSongDownloader.swift
```

The final `git grep` should return no match for the removed inter-chart policy.

## Non-goals

- Off-main DTX parsing, projection, file work, or SwiftData work.
- Moving SwiftData models or `ModelContext` across actors.
- Parallel chart downloads.
- A rate limiter, scheduler, actor pool, sleeper abstraction, injected clock, or replacement cancellation primitive.
- Import progress UI or retry/recovery redesign.
- New benchmark/performance-test infrastructure.
- HPA-581 gameplay preparation/static rendering work.
- HPA-584 row virtualization work.
- HPA-85 BGM format compatibility.

## Acceptance criteria

- [ ] The fixed 100 ms inter-chart `Task.sleep` and stale throttle comment are removed with no replacement delay/checkpoint abstraction.
- [ ] The loop remains serial and preserves `snapshot.charts` request order.
- [ ] BGM/preview requests remain after chart requests.
- [ ] A `CancellationError` thrown by chart processing is not converted into a per-chart warning/failure.
- [ ] Partial-chart and all-chart failure behavior remains unchanged.
- [ ] No elapsed-time unit test, gap-cancellation test, sleeper abstraction, configurable throttle, or new concurrency framework is introduced.
- [ ] Focused `ServerSongDownloaderTests` pass nonparallel.
- [ ] The complete `VirgoTests` suite passes nonparallel before implementation review.
- [ ] Source audit confirms the obsolete inter-chart delay/comment is gone.
