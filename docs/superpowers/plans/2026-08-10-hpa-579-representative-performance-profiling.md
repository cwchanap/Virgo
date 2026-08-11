# HPA-579 Representative Performance Profiling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Measure representative Virgo import, gameplay preparation, relayout, and rendering costs, then resolve the HPA-580/HPA-581 evidence gate and record the baseline HPA-584 will repeat.

**Architecture:** Use Xcode's Release Profile action and Instruments for end-to-end evidence. Add only disposable `Logger.info` / `ContinuousClock` markers that the trace actually needs, keep deliberate sleeps/debounces separate from processing cost, record the result in Linear, and return the branch to a docs-only diff unless one tiny retained signpost is explicitly justified.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, Xcode Profile action, Instruments Time Profiler / SwiftUI / Allocations, unified logging, `ContinuousClock`, Linear.

## Global Constraints

- Follow the measurement boundaries, decision rubric, result template, and non-goals in `docs/superpowers/specs/2026-08-10-hpa-579-representative-performance-profiling-design.md`; do not duplicate or reinterpret them here.
- HPA-579 does not optimize production code.
- Release macOS behavior is authoritative; `xcodebuild -configuration Release` is a compile check, not the profiled binary path.
- Use a real chart, not a synthetic golden fixture.
- Do not create benchmark, metrics, CI-gate, actor-pool, or virtualization infrastructure.
- Do not move SwiftData models or `ModelContext` across actors.
- Do not parallelize server chart downloads.
- Keep `.trace` bundles and temporary measurement artifacts out of git.
- macOS 14+ and iPadOS remain supported; never introduce an iPhone target.

---

## File Structure

**Planning docs:**

- `docs/superpowers/specs/2026-08-10-hpa-579-representative-performance-profiling-design.md` — owns the measurement contract, rubric, and Linear result template.
- `docs/superpowers/plans/2026-08-10-hpa-579-representative-performance-profiling.md` — owns the executable steps below.

**Temporary source instrumentation may touch:**

- `Virgo/views/GameplayView.swift` — one baseline marker and optional preparation clocks.
- `Virgo/utilities/LocalDTXFixtureImporter.swift` — optional fresh-import parse/projection clock.
- `Virgo/utilities/ServerSongDownloader.swift` — optional post-download decode/parse/projection clock.
- `Virgo/viewmodels/GameplayViewModel+Computations.swift` — optional width-relayout processing clock.

**Observed but normally unchanged:**

- `Virgo/viewmodels/GameplayViewModel.swift`
- `Virgo/views/subviews/GameplaySheetMusicView.swift`
- `Virgo/layout/gameplay.swift`
- `Virgo/components/DifficultyExpansionView.swift`

---

## Task 1: Establish a profileable Release baseline and choose the chart

**Files:**
- Read: `Virgo.xcodeproj/xcshareddata/xcschemes/Virgo.xcscheme`
- Read: `Virgo/Fixtures/soukyuu_e_no_shouka/SET.def`
- Read: `Virgo/Fixtures/soukyuu_e_no_shouka/mas.dtx`
- Temporarily modify: `Virgo/views/GameplayView.swift` for one baseline metadata marker

**Produces:** Verified Instruments attachment/symbolication, running info log stream, one representative chart, and repeatable chart metadata for HPA-584.

- [ ] **Step 1: Freeze source/toolchain context**

Run:

```bash
git status -sb
git rev-parse HEAD
git log -1 --oneline
sw_vers
system_profiler SPHardwareDataType | egrep 'Model Name|Model Identifier|Chip|Memory'
xcodebuild -version
xcrun xctrace version
```

Record the literal outputs for the Linear result.

- [ ] **Step 2: Compile-check Release**

Run:

```bash
xcodebuild \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath ./DerivedData-HPA579 \
  build
```

Expected: `** BUILD SUCCEEDED **`.

Do not launch this CLI-built app as the profiling baseline.

- [ ] **Step 3: Start the unified info log stream in a separate Terminal**

Run and leave it active during measured sessions:

```bash
log stream --level info --predicate 'subsystem == "com.cwchanap.Virgo"'
```

Temporary `Logger.info` markers must appear here. `Logger.debug` is not used for profiling markers.

- [ ] **Step 4: Prove the Profile action works before collecting numbers**

In Xcode:

1. Open `Virgo.xcodeproj` and select the shared `Virgo` scheme.
2. Choose **Product > Profile** (`⌘I`).
3. Choose **Time Profiler**.
4. Record a short interaction in Virgo.
5. Confirm the trace contains symbolicated frames such as `GameplayView`, `GameplayViewModel`, or another named Virgo function.

If Instruments cannot launch/attach or frames are not symbolicated, stop here and fix the profiling setup. Do not substitute Debug timings for the required result.

- [ ] **Step 5: Choose the representative chart from the UI**

Use the per-chart note count already rendered in the difficulty expansion UI. Inspect the real charts currently available in the library and choose the chart with the highest visible note count.

Do not build a secondary controls/measures/row ranking protocol. If no downloaded/current chart is clearly larger, use:

```text
song: soukyuu_e_no_shouka
chart: MASTER
file: Virgo/Fixtures/soukyuu_e_no_shouka/mas.dtx
```

`real.dtx` is referenced by `SET.def` but is not shipped, so it is not a valid fallback.

Record the chosen identity and visible note count.

- [ ] **Step 6: Add one disposable baseline metadata marker**

Immediately after `vm.setupGameplay()` succeeds in `GameplayView.prepareGameplay(initialRowWidth:)`, temporarily add:

```swift
let hpa579RenderedRows = (vm.cachedNotationLayout.measures.map(\.row).max() ?? -1) + 1
let hpa579MeasureCount = vm.cachedRhythmTimeline?.measures.count ?? vm.cachedLayoutMeasureCount
Logger.info(
    "HPA-579 baseline notes=\(vm.cachedNotes.count) " +
    "controls=\(vm.cachedControlEvents.count) measures=\(hpa579MeasureCount) " +
    "rowWidth=\(vm.cachedLayoutRowWidth) renderedRows=\(hpa579RenderedRows)"
)
```

This marker records baseline metadata for the already-selected chart; it is not used to rank candidates.

Re-profile the chosen chart once through Product > Profile and copy the marker values from the running log stream.

---

## Task 2: Measure chart selection to gameplay prepared

**Files:**
- Observe/temporarily modify: `Virgo/views/GameplayView.swift`
- Observe: `Virgo/viewmodels/GameplayViewModel.swift`
- Observe: `Virgo/viewmodels/GameplayViewModel+Computations.swift`

**Produces:** Median/range for preparation plus dominant-stage attribution for HPA-581.

- [ ] **Step 1: Capture one warm-up and three measured entries**

Using Product > Profile with Time Profiler, enter gameplay for the chosen chart one warm-up time, then perform three measured entries.

Measure the user-visible preparation boundary from `prepareGameplay(initialRowWidth:)` beginning real work through `isGameplayPrepared == true`.

Record median/range and whether the user sees a meaningful loading hitch.

- [ ] **Step 2: Attribute the trace to existing stages**

Use the call tree to identify whether cost is dominated by:

- relationship access/copy or note sorting in `loadChartData`;
- rhythm resolution / `makeRhythmRuntime` / `RhythmLayoutSnapshotBuilder`;
- `computeCachedLayoutData` / notation layout / beat-position caching;
- BGM or another named setup stage.

If the trace already answers this, do not add more clocks.

- [ ] **Step 3: If attribution is ambiguous, add only correctly labeled outer clocks**

Temporarily use:

```swift
let hpa579Clock = ContinuousClock()
let hpa579PrepareStart = hpa579Clock.now
await vm.loadChartData()
let hpa579AfterLoad = hpa579Clock.now

vm.updateRowWidth(initialRowWidth)
let hpa579AfterWidth = hpa579Clock.now

let hpa579SetupStart = hpa579Clock.now
vm.setupGameplay()
let hpa579Prepared = hpa579Clock.now

Logger.info(
    "HPA-579 gameplay loadChartData: \(hpa579PrepareStart.duration(to: hpa579AfterLoad))"
)
Logger.info(
    "HPA-579 gameplay updateRowWidth: \(hpa579AfterLoad.duration(to: hpa579AfterWidth))"
)
Logger.info(
    "HPA-579 gameplay setupGameplay: \(hpa579SetupStart.duration(to: hpa579Prepared))"
)
```

If `setupGameplay` dominates and the trace still cannot distinguish notation layout from other setup, add one additional clock around `computeCachedLayoutData()` only.

Repeat three measured entries and record the median/range for the required boundary.

---

## Task 3: Measure width relayout above the 900pt floor

**Files:**
- Observe/temporarily modify: `Virgo/viewmodels/GameplayViewModel+Computations.swift`
- Read: `Virgo/layout/gameplay.swift`

**Produces:** Post-debounce relayout processing cost plus a separate user-visible settling observation.

- [ ] **Step 1: Choose a real relayout transition**

`updateRowWidth` resolves width as:

```swift
max(GameplayLayout.maxRowWidth, width)
```

and `maxRowWidth == 900`.

Do not measure two widths that both resolve to 900. Choose endpoints where at least one width is **greater than 900pt**, and confirm the notation row packing visibly changes between the endpoints.

If the profiling machine cannot produce a row-packing change, record that limitation and do not time a no-op.

- [ ] **Step 2: Profile the post-debounce rebuild**

With Time Profiler, resize between the chosen endpoints and inspect the callback that performs:

```text
cacheNotationLayout
cacheBeatPositions
```

Keep the intentional 100 ms trailing-edge debounce separate from processing time.

- [ ] **Step 3: If Instruments cannot isolate the callback, add one temporary clock**

Inside the timer callback only:

```swift
let hpa579Clock = ContinuousClock()
let hpa579Start = hpa579Clock.now
self.cacheNotationLayout()
self.cacheBeatPositions()
let hpa579Duration = hpa579Start.duration(to: hpa579Clock.now)
Logger.info("HPA-579 width relayout processing: \(hpa579Duration)")
```

Perform one warm-up and three measured relayouts. Record median/range, the fixed debounce separately, and any visible hitch.

---

## Task 4: Measure initial mount, steady playback, scrolling, and memory

**Files:**
- Observe: `Virgo/views/subviews/GameplaySheetMusicView.swift`
- Observe: `Virgo/viewmodels/GameplayViewModel.swift`

**Produces:** SwiftUI invalidation evidence and the eager-render HPA-584 baseline.

- [ ] **Step 1: Capture initial mount separately from playback**

Using a SwiftUI + Time Profiler trace, open gameplay for the representative chart and let the full notation mount.

Record whether initial cost is primarily pre-mount notation preparation, static view construction/evaluation, or another named stack.

- [ ] **Step 2: Capture at least 30 seconds of steady playback**

Start playback and let the playhead cross rows. Inspect whether frequent state changes broadly re-evaluate:

- `sheetMusicView` / `staticSheetMusicContent`;
- `drumNotationView` and its full `ForEach` collections;
- or only the expected playhead/row/playing surfaces.

Record the observed update pattern and prominent main-thread stacks.

- [ ] **Step 3: Scroll while playback remains active**

Scroll vertically and horizontally while the playhead moves. Record one of:

- smooth;
- minor hitch;
- repeated hitch.

Note whether any hitch aligns with notation/SwiftUI work and whether auto-scroll materially worsens it.

Do not automate scrolling in HPA-579.

- [ ] **Step 4: Record peak live memory**

Use Allocations or the Xcode memory gauge during the same mount/playback session and record peak live memory.

This is a repeat baseline, not a leak investigation.

---

## Task 5: Measure fresh DTX import last, with an explicit reset before every run

**Files:**
- Observe/temporarily modify: `Virgo/utilities/LocalDTXFixtureImporter.swift`
- Observe/temporarily modify: `Virgo/utilities/ServerSongDownloader.swift`

**Produces:** Valid fresh-import evidence for HPA-580 without the existing-song fast path producing false near-zero timings.

This task is deliberately after Tasks 1-4 because it resets the local development store. Virgo's current pre-release data policy permits reset rather than migration/recovery.

- [ ] **Step 1: Measure the server post-download path first when available**

Before resetting local state, use an importable server song if one is available and not already downloaded. With Time Profiler, inspect `ServerSongDownloader.processChart` after `downloadData(from:)` returns through `persistenceProjection()`.

If the boundary is ambiguous, temporarily add:

```swift
let data = try await downloader.downloadData(from: url)
let hpa579Clock = ContinuousClock()
let hpa579Start = hpa579Clock.now

guard let content = Self.decode(data, encoding: chartSnapshot.fileEncoding) else {
    throw ServerSongImportError.decodeFailed(chartSnapshot.filename)
}
let chartData = try DTXFileParser.parseChartMetadata(from: content)
let projection = try chartData.persistenceProjection()

let hpa579Duration = hpa579Start.duration(to: hpa579Clock.now)
Logger.info(
    "HPA-579 server decode+parse+projection \(chartSnapshot.filename): \(hpa579Duration)"
)
```

If no usable server import exists, record that limitation. Do not spend the spike manufacturing one.

- [ ] **Step 2: Define the local fresh-store reset command**

Quit Virgo completely before each local-import run, then run:

```bash
APP_SUPPORT="$HOME/Library/Containers/cwchanap.Virgo/Data/Library/Application Support"
rm -rf "$APP_SUPPORT"/default.store*
defaults delete cwchanap.Virgo BundledFixtureDeletedSongIds 2>/dev/null || true
find "$APP_SUPPORT" -maxdepth 1 -name 'default.store*' -print
```

Expected before relaunch: the final `find` prints nothing.

If the store is still present, the reset failed; do not profile that run.

Run this reset before the warm-up and before **each** of the three measured local-import launches.

- [ ] **Step 3: Capture a fresh local-import warm-up trace**

After the reset, choose Product > Profile and record app startup through bundled Soukyuu import.

The trace must contain symbolicated `LocalDTXFixtureImporter.loadImportedCharts` / `DTXFileParser.parseChartMetadata` work. If those frames are absent, the run did not exercise the required fresh parse path and is void.

- [ ] **Step 4: Capture three measured fresh local imports**

For each measured run:

1. quit Virgo;
2. run the reset command from Step 2;
3. confirm no `default.store*` remains;
4. Product > Profile with Time Profiler;
5. record the fresh bundled import;
6. confirm the real parse path appears in the trace.

Record wall-clock import behavior and dominant main-thread stacks.

- [ ] **Step 5: If the local parse/projection boundary remains ambiguous, add one temporary clock**

In `LocalDTXFixtureImporter.loadImportedCharts`:

```swift
let hpa579Clock = ContinuousClock()
let hpa579Start = hpa579Clock.now
let data = try DTXFileParser.parseChartMetadata(from: chartURL)
let projection = try data.persistenceProjection()
let hpa579Duration = hpa579Start.duration(to: hpa579Clock.now)
Logger.info(
    "HPA-579 local parse+projection \(reference.filename): \(hpa579Duration)"
)
```

Re-run the three-reset protocol and record the per-chart values plus song-level median/range.

- [ ] **Step 6: Record the fixed inter-chart policy delay separately**

For `N` processed charts, record:

```text
max(0, N - 1) * 100 ms
```

Do not include it in parser/projection CPU time. Apply the HPA-580 decision later using the design rubric; do not invent a separate rule in this plan.

---

## Task 6: Clean up measurement code and resolve the Linear gate

**Files:**
- Restore any temporary changes in:
  - `Virgo/views/GameplayView.swift`
  - `Virgo/utilities/LocalDTXFixtureImporter.swift`
  - `Virgo/utilities/ServerSongDownloader.swift`
  - `Virgo/viewmodels/GameplayViewModel+Computations.swift`
- Update: Linear HPA-579
- Conditionally update/close: HPA-580 and HPA-581

**Produces:** A docs-only normal outcome, one authoritative HPA-579 result, explicit downstream decisions, and no accidental profiling artifacts.

- [ ] **Step 1: Save the disposable instrumentation before removing it**

Run:

```bash
git diff > /tmp/hpa579-instrumentation.patch
```

This preserves the exact temporary markers if a measurement must be repeated.

- [ ] **Step 2: Revert temporary source instrumentation**

Run:

```bash
git restore \
  Virgo/views/GameplayView.swift \
  Virgo/utilities/LocalDTXFixtureImporter.swift \
  Virgo/utilities/ServerSongDownloader.swift \
  Virgo/viewmodels/GameplayViewModel+Computations.swift
```

Only retain production instrumentation if the evidence proves a tiny `os_signpost` interval is necessary for future interpretation; document that exception explicitly in HPA-579.

- [ ] **Step 3: Verify repository hygiene**

Run:

```bash
git status -sb
git diff --check
git diff --stat main...HEAD
find . -name '*.trace' -o -name 'DerivedData-HPA579'
```

Normal expected outcome: only the two HPA-579 planning documents are committed and no profiling artifact is staged.

- [ ] **Step 4: Match verification to the final artifact**

If no production source diff remains, do not run the full unit suite solely for the measurement spike.

If a retained signpost source diff remains, run focused coverage for the owning gameplay/import area plus:

```bash
swiftlint lint --quiet
git diff --check
```

Expand testing only to the actual retained source change.

- [ ] **Step 5: Post the HPA-579 result using the design template**

Use the exact `## Result template` from the design spec. Fill it only with values/limitations observed in Tasks 1-5.

Do not restate a second template here and do not invent missing measurements.

- [ ] **Step 6: Apply the design rubric to HPA-580 and HPA-581**

Use the design spec's `## Decision rubric` verbatim:

- update a narrowed ticket before implementation so its problem/scope/acceptance criteria match the evidence;
- if HPA-580 is **Policy-only Narrow**, remove all off-main parser/projection requirements and leave only the measured sleep cleanup;
- close a ticket as unnecessary when that is the measured conclusion;
- leave HPA-584 unstarted and preserve only its repeat baseline in HPA-579.

- [ ] **Step 7: Final PR check**

Run:

```bash
git status -sb
git diff --check
git diff --stat main...HEAD
```

Confirm the planning PR remains reviewable and does not accidentally contain the temporary measurement code or trace artifacts.
