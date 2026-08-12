# HPA-580 Remove Inter-Chart Delay Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the fixed 100 ms delay between serial server-chart imports and delete the cancellation branch that becomes production-dead with it.

**Architecture:** Keep the existing main-actor, serial `ServerSongDownloader` pipeline. Awaiting `processChart(...)` provides serialization. Do not replace the deleted sleep with any checkpoint, throttle, scheduler, timing seam, or concurrency abstraction.

**Tech Stack:** Swift, SwiftData, Swift Testing, xcodebuild, SwiftLint.

## Scope facts

- HPA-579 decided **Policy-only Narrow**: parser/projection/SwiftData stay where they are.
- `DTXAPIClient` is the only production `FileDownloading` implementation and wraps cancellation as `DTXAPIError.networkError`.
- `ServerSongsView` discards the import `Task` handle, so the current UI cannot cancel an in-flight import.
- Therefore, after deleting the throwing sleep, `catch is CancellationError` in `processCharts` is mock-only dead code. Real cancellation support is a separate ticket if ever needed.
- The default URL session already caps connections per host at 2, and optional BGM/preview downloads run consecutively without an artificial delay. Do not invent a replacement throttle.

---

### Task 1: Pin request order before changing production

**Files:**
- Modify: `VirgoTests/ServerSongDownloaderTests.swift`

- [ ] **Step 1: Tighten the existing four-chart request assertion**

In `testDownloadAndImportSongMapsDifficultiesAndDownloadsOptionalFiles()`, replace the two `contains` assertions for BGM/preview with:

```swift
#expect(
    mock.requestedURLs == [
        "\(r2Base)/multi-diff/easy.dtx",
        "\(r2Base)/multi-diff/medium.dtx",
        "\(r2Base)/multi-diff/hard.dtx",
        "\(r2Base)/multi-diff/expert.dtx",
        "\(r2Base)/multi-diff/bgm.ogg",
        "\(r2Base)/multi-diff/preview.mp3"
    ]
)
```

This is characterization only. It should pass before and after HPA-580 and protects request order, not elapsed time.

- [ ] **Step 2: Run the focused suite**

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

Expected: PASS, including the existing partial-failure and all-chart-failure tests.

- [ ] **Step 3: Commit the characterization change**

```bash
git add VirgoTests/ServerSongDownloaderTests.swift
git commit -m "test: pin server chart request order"
```

---

### Task 2: Delete the delay and mock-only cancellation branch

**Files:**
- Modify: `Virgo/utilities/ServerSongDownloader.swift`
- Modify: `VirgoTests/ServerSongDownloaderTests.swift`

- [ ] **Step 1: Simplify the chart loop**

Change:

```swift
for (index, chartSnapshot) in snapshot.charts.enumerated() {
    // Throttle chart downloads to avoid overwhelming the server.
    if index > 0 { try await Task.sleep(nanoseconds: 100_000_000) }
    do {
```

to:

```swift
for chartSnapshot in snapshot.charts {
    do {
```

Leave `processChart(...)`, warning collection, success counting, and all-chart failure logic unchanged.

- [ ] **Step 2: Delete the dead cancellation special case**

Remove:

```swift
} catch is CancellationError {
    throw CancellationError()
```

The production downloader cannot currently surface a bare `CancellationError`; do not replace this branch with another cancellation mechanism in HPA-580.

- [ ] **Step 3: Delete the synthetic cancellation test**

Remove `testCancellationErrorPropagation()` and its local `CancellingDownloader` mock from `ServerSongDownloaderTests.swift`.

Do not add a new cancellation-gap test. Making production cancellation real requires separate changes in `DTXAPIClient` and caller task ownership.

- [ ] **Step 4: Source-audit the deletion**

```bash
git grep -n -E 'Task\.sleep|100_000_000|Throttle chart downloads|catch is CancellationError' -- \
  Virgo/utilities/ServerSongDownloader.swift
git grep -n 'testCancellationErrorPropagation' -- VirgoTests/ServerSongDownloaderTests.swift
```

Expected: both commands return no output.

- [ ] **Step 5: Run the required regression gate**

Run the same nonparallel `ServerSongDownloaderTests` command from Task 1.

Expected: PASS. Confirm:

- exact chart request order remains easy → medium → hard → expert;
- BGM then preview remain after all charts;
- partial chart failure still imports the valid chart;
- all-chart failure still fails the import.

- [ ] **Step 6: Run static checks**

```bash
swiftlint lint --quiet
git diff --check
```

Expected: no new serious SwiftLint violation and no whitespace errors.

- [ ] **Step 7: Optional full-suite diagnostic**

A full `VirgoTests` run is **not** the HPA-580 gate because clean `main` has a documented nondeterministic SwiftData `\Chart.difficulty` detached-context crash.

If you run the full suite and it fails, run the identical command on a clean `main` worktree/check-out before classifying the failure. Treat focused downloader failures or failures reproducible only on the HPA-580 branch as regressions; do not spend this ticket fixing the known shared-container flake.

- [ ] **Step 8: Commit the production/dead-test deletion**

```bash
git add Virgo/utilities/ServerSongDownloader.swift VirgoTests/ServerSongDownloaderTests.swift
git commit -m "perf: remove inter-chart import delay"
```

---

## Final review

```bash
git diff main...HEAD -- Virgo/utilities/ServerSongDownloader.swift VirgoTests/ServerSongDownloaderTests.swift
git diff --check
```

Confirm:

- [ ] no inter-chart delay, throttle comment, or unused loop index remains;
- [ ] no mock-only cancellation catch/test remains;
- [ ] chart processing is still serial through awaited `processChart(...)`;
- [ ] no changes were made to `DTXAPIClient`, `ServerSongsView`, actor isolation, parser/projection, or SwiftData ownership;
- [ ] no clock/sleeper, rate limiter, parallel downloader, or elapsed-time threshold was added;
- [ ] focused `ServerSongDownloaderTests` passed nonparallel.

## Non-goals

- Off-main import work.
- Parallel downloads or replacement throttling infrastructure.
- Timing/benchmark infrastructure.
- Making production import cancellation cooperative; that requires separate `DTXAPIClient` and task-ownership work.
