# HPA-580: Remove the Fixed Inter-Chart Import Delay

**Date:** 2026-08-11
**Status:** Proposed

## Context

HPA-579 recorded **Policy-only Narrow** for HPA-580: a representative four-chart import spent about 29 ms in aggregate parse/projection, about 7.14 s in the full fresh import dominated by SwiftData, and 300 ms in deliberate inter-chart sleeps. No off-main refactor is justified.

`processCharts` currently sleeps 100 ms before every chart after the first even though each `processChart(...)` is awaited serially.

## Decision

Delete only obsolete policy/dead code:

- change `for (index, chartSnapshot) in snapshot.charts.enumerated()` to `for chartSnapshot in snapshot.charts`;
- delete the throttle comment and `Task.sleep`;
- delete `catch is CancellationError` and `testCancellationErrorPropagation`;
- leave the remaining serial import pipeline unchanged.

No replacement checkpoint, throttle, scheduler, clock, parallel downloader, or actor move.

## Why delete the cancellation branch

After the sleep is removed, production cannot surface a bare `CancellationError` here:

- `DTXAPIClient` is the only production `FileDownloading` implementation and wraps non-`DTXAPIError` failures in `DTXAPIError.networkError`;
- `ServerSongsView` discards the import `Task` handle;
- no other production cancellation source exists in this path.

The existing cancellation test is therefore mock-only. Real cooperative cancellation would require separate `DTXAPIClient` and caller task-ownership changes and is out of scope.

## Why no replacement throttle

Awaiting `processChart(...)` already serializes charts. Optional BGM/preview downloads already run consecutively without a fixed pause, and the default URL session caps connections per host at 2. New rate-limiting machinery is unnecessary.

## Verification contract

Strengthen the current four-chart test to assert:

```text
easy.dtx -> medium.dtx -> hard.dtx -> expert.dtx -> bgm.ogg -> preview.mp3
```

This protects request order, not timing. Source audit proves the delay is gone.

Required gate:

```bash
xcodebuild test -project Virgo.xcodeproj -scheme Virgo \
  -destination 'platform=macOS' -configuration Debug \
  -only-testing:VirgoTests/ServerSongDownloaderTests \
  -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -destination-timeout 300 -derivedDataPath ./DerivedData
```

Also run `swiftlint lint --quiet`, `git diff --check`, and grep the edited files for the removed sleep/throttle/cancellation-test symbols.

A full `VirgoTests` run is optional: clean `main` already has a documented nondeterministic SwiftData `\Chart.difficulty` detached-context crash. If run and red, compare with the same command on clean `main`; the focused downloader suite is the HPA-580 gate.

## Non-goals

- Off-main parser/projection/file/SwiftData work or parallel downloads.
- Any timing/throttle/scheduler abstraction or elapsed-time assertion.
- Making production import cancellation cooperative.
- HPA-581/HPA-584 work.

## Acceptance criteria

- [ ] Sleep/comment/index and mock-only cancellation catch/test are removed.
- [ ] Chart order and chart-before-audio behavior remain unchanged.
- [ ] Partial/all-chart failure behavior remains unchanged.
- [ ] Focused downloader tests and source/static checks pass.
