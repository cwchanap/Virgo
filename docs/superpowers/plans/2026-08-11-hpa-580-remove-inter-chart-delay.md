# HPA-580 Remove Inter-Chart Delay Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the fixed 100 ms inter-chart delay and the cancellation branch/test that become production-dead with it.

**Architecture:** Keep the current serial, main-actor pipeline. Awaited `processChart(...)` provides serialization. Do not replace deleted policy with new timing, throttling, cancellation, or concurrency machinery.

**Tech Stack:** Swift, SwiftData, Swift Testing, xcodebuild, SwiftLint.

## Constraints

- HPA-579 is **Policy-only Narrow**; parser/projection/SwiftData stay where they are.
- `DTXAPIClient` wraps cancellation and `ServerSongsView` does not own the import task, so real cooperative cancellation is out of scope.
- The focused nonparallel `ServerSongDownloaderTests` suite is the required gate.
- Full `VirgoTests` is diagnostic only because clean `main` has the known nondeterministic `\Chart.difficulty` detached-context crash.

---

### Task 1: Pin request order

**File:** `VirgoTests/ServerSongDownloaderTests.swift`

- [ ] Replace the two BGM/preview `contains` checks in `testDownloadAndImportSongMapsDifficultiesAndDownloadsOptionalFiles()` with:

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

- [ ] Run:

```bash
xcodebuild test -project Virgo.xcodeproj -scheme Virgo \
  -destination 'platform=macOS' -configuration Debug \
  -only-testing:VirgoTests/ServerSongDownloaderTests \
  -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -destination-timeout 300 -derivedDataPath ./DerivedData
```

Expected: PASS. This is characterization only; it protects request order, not elapsed time.

- [ ] Commit:

```bash
git add VirgoTests/ServerSongDownloaderTests.swift
git commit -m "test: pin server chart request order"
```

---

### Task 2: Delete obsolete delay and cancellation code

**Files:**
- `Virgo/utilities/ServerSongDownloader.swift`
- `VirgoTests/ServerSongDownloaderTests.swift`

- [ ] Change:

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

- [ ] Delete the mock-only cancellation branch:

```swift
} catch is CancellationError {
    throw CancellationError()
```

- [ ] Delete `testCancellationErrorPropagation()` and its local `CancellingDownloader`. Do not add a replacement cancellation test; making cancellation real requires separate `DTXAPIClient` and caller task-ownership changes.

- [ ] Verify source deletion:

```bash
git grep -n -E 'Task\.sleep|100_000_000|Throttle chart downloads|catch is CancellationError' -- \
  Virgo/utilities/ServerSongDownloader.swift
git grep -n 'testCancellationErrorPropagation' -- VirgoTests/ServerSongDownloaderTests.swift
```

Expected: no output.

- [ ] Re-run the focused downloader suite from Task 1. Confirm exact request order plus existing partial-failure and all-chart-failure coverage pass.

- [ ] Run static checks:

```bash
swiftlint lint --quiet
git diff --check
```

- [ ] Optional: run full `VirgoTests`. If it fails, run the identical command on clean `main` before classifying the failure; do not fold the known shared-container crash into HPA-580.

- [ ] Commit:

```bash
git add Virgo/utilities/ServerSongDownloader.swift VirgoTests/ServerSongDownloaderTests.swift
git commit -m "perf: remove inter-chart import delay"
```

## Final check

`git diff main...HEAD` should show only:

- exact request-order characterization;
- sleep/comment/index deletion;
- dead cancellation catch/test deletion.

No changes to `DTXAPIClient`, `ServerSongsView`, actor isolation, parser/projection, SwiftData ownership, throttling, clocks, parallelism, or timing thresholds.
