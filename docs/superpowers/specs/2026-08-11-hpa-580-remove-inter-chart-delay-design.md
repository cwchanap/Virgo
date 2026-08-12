# HPA-580: Remove the Fixed Inter-Chart Import Delay

**Date:** 2026-08-11  
**Status:** Proposed

## Context

HPA-579 recorded **Policy-only Narrow** for HPA-580. On the representative four-chart import it measured about 29 ms of aggregate parse/projection work, about 7.14 s for the full fresh import dominated by SwiftData persistence, and 300 ms of deliberate inter-chart sleep. That evidence does not justify moving parser, projection, file, or SwiftData work off the main actor.

Current `ServerSongDownloader.processCharts` waits 100 ms before every chart after the first even though each `processChart(...)` call is already awaited to completion.

## Decision

Make HPA-580 a deletion-only cleanup:

1. Change `for (index, chartSnapshot) in snapshot.charts.enumerated()` to `for chartSnapshot in snapshot.charts`.
2. Delete the throttle comment and fixed `Task.sleep`.
3. Delete the now-dead `catch is CancellationError` branch in `processCharts` and its synthetic `testCancellationErrorPropagation` test.
4. Leave the rest of the serial import pipeline unchanged.

No replacement delay, cancellation checkpoint, rate limiter, scheduler, clock, actor move, or parallel downloader is introduced.

## Why the cancellation branch is dead

After the sleep is removed, production has no path that can raise a bare `CancellationError` inside `processCharts`:

- the only production `FileDownloading` implementation is `DTXAPIClient`;
- `DTXAPIClient.downloadData` wraps every non-`DTXAPIError` failure in `DTXAPIError.networkError`, including URL-session cancellation;
- `ServerSongsView` launches the import with an untracked `Task { ... }`, so no production caller owns a task handle to cancel;
- repository search finds no other production `CancellationError()` source in this path.

The existing cancellation test passes only because its mock throws `CancellationError()` directly. Keeping that test and catch would preserve behavior that production cannot exercise.

If real cooperative cancellation is wanted later, it belongs in a separate change that preserves cancellation through `DTXAPIClient` and gives the caller task ownership. HPA-580 does not add that work.

## Why no throttle replaces the sleep

Serialization already comes from awaiting `processChart(...)`; removing the sleep does not overlap chart imports.

The same downloader already performs optional BGM and preview requests consecutively with no policy delay after chart processing, and the default `DTXAPIClient` URL session caps connections per host at 2. There is no need to replace a fixed pause with new rate-limiting infrastructure.

## Regression contract

Strengthen the existing four-chart test to assert this exact request sequence:

```text
easy.dtx -> medium.dtx -> hard.dtx -> expert.dtx -> bgm.ogg -> preview.mp3
```

That assertion protects snapshot order and the chart-before-audio boundary. It does **not** prove latency removal; source inspection does.

Keep the existing partial-chart-failure and all-chart-failure tests as the behavior gates around the edited loop.

## Verification

Required gate:

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

Source/static checks:

```bash
git grep -n -E 'Task\.sleep|100_000_000|Throttle chart downloads|catch is CancellationError' -- \
  Virgo/utilities/ServerSongDownloader.swift
git grep -n 'testCancellationErrorPropagation' -- VirgoTests/ServerSongDownloaderTests.swift
swiftlint lint --quiet
git diff --check
```

Both `git grep` commands should return no output.

A full `VirgoTests` run is optional for this three-line policy deletion because clean `main` already has a documented nondeterministic SwiftData `\Chart.difficulty` detached-context crash. If a full run is executed and fails, compare the same command on clean `main`; the focused downloader suite remains the HPA-580 regression gate.

## Non-goals

- Off-main parser/projection/file/SwiftData work.
- Parallel chart downloads or rate-limiting/scheduler abstractions.
- Timing thresholds, sleeper/clock injection, or benchmark infrastructure.
- Fixing real production cancellation in `DTXAPIClient`/task ownership.
- HPA-581 gameplay preparation or HPA-584 virtualization work.

## Acceptance criteria

- [ ] The fixed inter-chart sleep, throttle comment, and unused loop index are removed.
- [ ] The mock-only `CancellationError` catch/test are removed rather than documented as a production contract.
- [ ] Chart requests remain serial and preserve snapshot order; BGM/preview remain after charts.
- [ ] Partial-chart and all-chart failure behavior remain unchanged.
- [ ] Focused `ServerSongDownloaderTests` pass nonparallel.
- [ ] Source/static checks pass with no new timing or concurrency infrastructure.
