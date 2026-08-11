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

Replace the fixed sleep with a zero-latency cancellation checkpoint:

```swift
if index > 0 { try Task.checkCancellation() }
```

Keep the rest of `processCharts` unchanged.

This is the smallest change that satisfies both sides of HPA-580:

1. remove the unconditional 100 ms delay;
2. retain the explicit between-chart cancellation point that the throwing `Task.sleep` currently provides.

No concurrency abstraction, actor move, parallel downloader, injected sleeper, clock, or benchmark helper is needed.

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

The fixed `Task.sleep` currently has one useful semantic side effect: if the import task is canceled between charts, the sleep throws `CancellationError` before another chart starts.

Deleting the sleep with no replacement would remove that explicit checkpoint and make cancellation depend on the next downloader or parser boundary. That is unnecessary behavior drift.

`Task.checkCancellation()` preserves the checkpoint without imposing latency. Keep it only between charts (`index > 0`) so the first-chart behavior is not broadened beyond the ticket.

`processCharts` must continue treating `CancellationError` differently from ordinary chart failures:

- `CancellationError` aborts chart processing and reaches `downloadAndImportSong`'s outer failure path;
- a normal chart-specific error is logged, recorded in `failedCharts`, and the next chart is attempted;
- if every chart fails normally, the existing `chartFailure` error remains unchanged.

## Behavior that must stay unchanged

### Chart ordering

Process `snapshot.charts` in its existing order. Do not sort, reorder, fan out, or race requests.

### Partial failure

A bad chart must not prevent later valid charts from importing. Existing warning/failure collection remains untouched.

### All-chart failure

If no chart succeeds and the snapshot contained charts, continue throwing `ServerSongImportError.chartFailure` with the failed filenames.

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

   This confirms charts still run serially in snapshot order and audio still starts only after all chart work finishes.

2. Retain the existing cancellation test that proves `CancellationError` is not downgraded into a per-chart failure.

3. Re-run the existing partial-chart-failure and all-chart-failure tests; they already protect the continuation/aggregate-failure behavior this edit must not disturb.

4. Use a source audit after the production edit to prove the obsolete policy is gone. The production file should contain no inter-chart `Task.sleep`, `100_000_000`, or stale "throttle" comment.

Do not add an elapsed-time assertion such as "four charts complete in under 300 ms." SwiftData/parser work and host load would make that test flaky and would turn one measured policy decision into a permanent performance threshold.

## Approaches considered

### Replace sleep with `Task.checkCancellation()` — selected

Pros:

- removes the full 100 ms per-gap latency;
- preserves the useful cancellation checkpoint;
- keeps serial behavior obvious;
- changes no public interface;
- adds no production abstraction.

Cons:

- the exact latency deletion is verified by code inspection plus HPA-579 evidence rather than a wall-clock unit test.

That trade-off is correct for this ticket.

### Delete the sleep with no replacement — rejected

This is one line smaller, but it silently removes the explicit between-chart cancellation checkpoint. There is no reason to accept that behavior drift when `Task.checkCancellation()` is effectively free.

### Make throttling configurable or inject a sleeper/clock — rejected

A configurable delay, sleep closure, clock protocol, rate limiter, or request scheduler would add maintenance surface for a policy HPA-579 already decided to delete. There is no current server-rate-limit evidence requiring a replacement throttle.

### Parallelize chart downloads — rejected

Parallelism would change network pressure, mutation ordering, failure behavior, and SwiftData coordination. HPA-580 explicitly keeps downloads serial, and profiling did not justify a concurrency redesign.

## Files in scope

### Production

- `Virgo/utilities/ServerSongDownloader.swift`
  - replace the fixed inter-chart sleep/comment with `Task.checkCancellation()`;
  - do not otherwise restructure `processCharts` or `processChart`.

### Tests

- `VirgoTests/ServerSongDownloaderTests.swift`
  - strengthen the multi-chart request-order assertion;
  - rely on the existing cancellation, partial-failure, and all-failure coverage rather than creating timing infrastructure.

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
- A rate limiter, scheduler, actor pool, sleeper abstraction, or injected clock.
- Import progress UI or retry/recovery redesign.
- New benchmark/performance-test infrastructure.
- HPA-581 gameplay preparation/static rendering work.
- HPA-584 row virtualization work.
- HPA-85 BGM format compatibility.

## Acceptance criteria

- [ ] The fixed 100 ms inter-chart `Task.sleep` is removed.
- [ ] A zero-latency between-chart cancellation checkpoint remains.
- [ ] Chart requests remain serial and preserve `snapshot.charts` order.
- [ ] BGM/preview requests remain after chart requests.
- [ ] Cancellation is not converted into a per-chart warning/failure.
- [ ] Partial-chart and all-chart failure behavior remains unchanged.
- [ ] No elapsed-time unit test, sleeper abstraction, configurable throttle, or new concurrency framework is introduced.
- [ ] Focused `ServerSongDownloaderTests` pass nonparallel.
- [ ] The complete `VirgoTests` suite passes nonparallel before implementation review.
- [ ] Source audit confirms the obsolete inter-chart delay/comment is gone.
