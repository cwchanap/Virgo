# HPA-580 Remove Inter-Chart Delay Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the unconditional 100 ms delay between serial server-chart imports while preserving request order, cancellation error classification, failure semantics, SwiftData ownership, and post-chart audio downloads.

**Architecture:** Keep `ServerSongDownloader` as the current serial main-actor pipeline. Delete the fixed sleep and stale throttle comment with no replacement cancellation primitive; serialization already comes from awaiting `processChart(...)`. Strengthen existing downloader tests around exact request order; do not add timing thresholds, injected clocks, configurable throttles, or concurrency infrastructure.

**Tech Stack:** Swift, Swift Concurrency, SwiftData, Swift Testing, Xcode/xcodebuild, SwiftLint.

## Global Constraints

- HPA-579's decision is **Policy-only Narrow**: do not move parser/projection/file/SwiftData work off-main.
- Chart downloads/imports remain serial and preserve `snapshot.charts` order.
- Keep `ServerSongDownloader.processCharts` and `processChart` on the main actor.
- Preserve the existing error classification: `CancellationError` thrown by chart processing aborts the import rather than becoming a chart-specific failure.
- Do not create a new between-chart cancellation checkpoint or test contract after deleting the sleep.
- Preserve partial-chart success, all-chart failure, warning aggregation, save/rollback, and audio behavior.
- Do not add parallel downloads, a rate limiter, scheduler, sleeper abstraction, injected clock, or performance benchmark framework.
- Do not add elapsed-time assertions for the removed 100 ms policy delay.
- Run tests with `-parallel-testing-enabled NO` per repository policy.

---

## File map

- Modify `VirgoTests/ServerSongDownloaderTests.swift`
  - strengthen the existing four-difficulty import test so request order is explicit.
  - existing cancellation/partial-failure/all-failure tests remain the behavioral regression gates.
- Modify `Virgo/utilities/ServerSongDownloader.swift`
  - remove only the fixed inter-chart sleep/comment and the now-unused `enumerated()` index.
- No new production or test files.

---

### Task 1: Pin the existing request-order contract

**Files:**
- Modify: `VirgoTests/ServerSongDownloaderTests.swift:73-141`

**Interfaces:**
- Consumes: existing `MockFileDownloader.requestedURLs`, `makeMultiDifficultyServerSong()`, and `ServerSongDownloader.downloadAndImportSong(_:container:)`.
- Produces: an exact request-order assertion protecting snapshot order and the chart-before-audio boundary.

This ticket removes intentional latency rather than fixing incorrect output. Do not create a production timing seam merely to force a red test. First strengthen the existing characterization test; it is expected to pass on current `main` and after the production edit.

- [ ] **Step 1: Replace loose audio-request checks with the exact request sequence**

In `testDownloadAndImportSongMapsDifficultiesAndDownloadsOptionalFiles()`, replace:

```swift
#expect(mock.requestedURLs.contains("\(r2Base)/multi-diff/bgm.ogg"))
#expect(mock.requestedURLs.contains("\(r2Base)/multi-diff/preview.mp3"))
```

with:

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

Do not describe this assertion as proof that the 100 ms delay was removed. It protects only the semantic request sequence; the source audit in Task 2 proves the policy deletion.

- [ ] **Step 2: Run the focused characterization suite before production changes**

Run:

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

Expected: PASS. In particular, confirm these existing tests remain green:

- `testDownloadAndImportSongMapsDifficultiesAndDownloadsOptionalFiles`
- `testDownloadAndImportSongSucceedsWithPartialChartFailure`
- `testDownloadAndImportSongFailsWhenAllChartsFail`
- `testCancellationErrorPropagation`

The cancellation test proves only that a `CancellationError` thrown during chart processing aborts the import. It does not exercise the inter-chart sleep and must not be used to justify a replacement checkpoint.

- [ ] **Step 3: Commit the characterization change**

```bash
git add VirgoTests/ServerSongDownloaderTests.swift
git commit -m "test: pin server chart request order"
```

---

### Task 2: Delete the fixed inter-chart delay

**Files:**
- Modify: `Virgo/utilities/ServerSongDownloader.swift:101-123`
- Test: `VirgoTests/ServerSongDownloaderTests.swift`

**Interfaces:**
- Consumes: `snapshot.charts` and existing `processChart(_:for:in:serverDurationSeconds:)`.
- Produces: the same serial `[String]` warning result from `processCharts`, but without the fixed 100 ms pause between chart iterations.

- [ ] **Step 1: Delete the throttle policy and now-unused index**

Change this loop prefix:

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

Leave the loop body and catch ordering unchanged.

Do **not** insert `Task.checkCancellation()` as a replacement. Once the deliberate 100 ms gap is deleted, HPA-580 does not require a new between-chart cancellation observation point. Do not add cancellation-gap test machinery to manufacture that requirement.

Do not change the loop to parallel tasks. Do not move `processChart` off-main.

- [ ] **Step 2: Audit that the deleted policy is actually gone**

Run:

```bash
git grep -n -E 'Task\.sleep|100_000_000|Throttle chart downloads' -- Virgo/utilities/ServerSongDownloader.swift
```

Expected: no output.

Also inspect the diff:

```bash
git diff -- Virgo/utilities/ServerSongDownloader.swift VirgoTests/ServerSongDownloaderTests.swift
```

Expected production diff: the loop no longer uses `enumerated()`, and the stale throttle comment plus fixed sleep are gone. There should be no replacement checkpoint or unrelated refactor.

- [ ] **Step 3: Run the focused downloader suite**

Run:

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

Expected: PASS.

The exact-order assertion must still report:

```text
easy.dtx -> medium.dtx -> hard.dtx -> expert.dtx -> bgm.ogg -> preview.mp3
```

The existing cancellation test must still fail the import when its downloader throws `CancellationError`, rather than counting cancellation as a recoverable chart failure. Do not claim it verifies any between-chart cancellation window.

- [ ] **Step 4: Run the complete nonparallel unit suite**

Run:

```bash
xcodebuild test \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'platform=macOS' \
  -configuration Debug \
  -only-testing:VirgoTests \
  -parallel-testing-enabled NO \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  -enableCodeCoverage YES \
  -destination-timeout 300 \
  -derivedDataPath ./DerivedData
```

Expected: all non-known-issue unit tests pass.

- [ ] **Step 5: Run static checks**

```bash
swiftlint lint --quiet
git diff --check
git grep -n -E 'Task\.sleep|100_000_000|Throttle chart downloads' -- Virgo/utilities/ServerSongDownloader.swift
```

Expected:

- SwiftLint exits successfully; pre-existing warning-level debt may be reported but no new serious violation is introduced.
- `git diff --check` prints nothing.
- the final `git grep` prints nothing.

- [ ] **Step 6: Commit the production change**

```bash
git add Virgo/utilities/ServerSongDownloader.swift
git commit -m "perf: remove inter-chart import delay"
```

---

## Final review checklist

Before making the implementation PR ready for review, compare the complete branch against `main`:

```bash
git diff --stat main...HEAD
git diff main...HEAD -- Virgo/utilities/ServerSongDownloader.swift VirgoTests/ServerSongDownloaderTests.swift
git log --oneline main..HEAD
```

Confirm:

- [ ] the only production behavior change is deletion of the fixed inter-chart delay and now-unused loop index;
- [ ] no replacement cancellation checkpoint was introduced;
- [ ] request ordering remains exact and serial;
- [ ] optional audio still follows all chart requests;
- [ ] `CancellationError` thrown by chart processing still aborts the import rather than becoming a recoverable chart failure;
- [ ] no actor isolation, parser/projection, SwiftData, retry, or concurrency architecture changed;
- [ ] no timing threshold, cancellation-gap test, or sleeper/clock abstraction was added;
- [ ] focused downloader tests passed nonparallel;
- [ ] full `VirgoTests` passed nonparallel;
- [ ] SwiftLint and `git diff --check` completed successfully;
- [ ] source audit finds no stale inter-chart delay constant/comment.

## Linear closeout

After implementation verification, post the implementation PR and verification summary to HPA-580. The issue can move to Done when the implementation PR lands. HPA-581 remains the next independent Phase C performance task; do not fold gameplay preparation/static rendering into this branch.
