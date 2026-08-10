# HPA-579 Representative Performance Profiling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Measure Virgo's current representative import, gameplay preparation, relayout, and steady rendering costs, then make explicit Proceed/Narrow/Close decisions for HPA-580 and HPA-581 and capture the baseline HPA-584 will repeat.

**Architecture:** This is an evidence spike, not a production refactor. Profile the real Release app with Instruments first, add temporary local `ContinuousClock` measurements only when a decision-relevant boundary is ambiguous, record findings in Linear, and revert temporary instrumentation before closing the ticket unless the measurement itself proves one tiny retained signpost is necessary.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, Instruments/Time Profiler, SwiftUI instrument, Allocations/Xcode memory gauge, `ContinuousClock`, Xcode/xcodebuild, Linear.

## Global Constraints

- HPA-579 does not optimize production code.
- Use the largest/densest real chart currently available; do not substitute a small synthetic golden fixture.
- Release macOS behavior is the authoritative baseline. Label any Debug trace separately.
- Record the exact commit, Mac hardware, OS, Xcode version, configuration, and representative chart complexity.
- Start with Instruments. Add temporary timing code only when stack attribution is insufficient.
- Do not create a benchmark target, metrics backend, dashboard, CI performance gate, generalized signpost framework, or permanent trace repository.
- Do not move SwiftData models or `ModelContext` across actors.
- Do not rewrite rhythm, notation, metronome, parser, or import algorithms.
- Do not parallelize chart downloads.
- Report the fixed 100 ms inter-chart sleep separately from parser/projection CPU time.
- Do not add row virtualization; HPA-584 owns that later decision.
- Do not change BGM `.ogg` compatibility behavior; HPA-85 remains separate.
- Do not commit Instruments `.trace` bundles.
- Temporary timing/logging changes must be reverted before HPA-579 closes unless a minimal retained `os_signpost` interval is explicitly justified by the result.
- macOS 14+ and iPadOS remain supported; never add or benchmark an iPhone target.

---

## File Structure

**Planning documents already on the HPA-579 branch:**

- `docs/superpowers/specs/2026-08-10-hpa-579-representative-performance-profiling-design.md` — measurement design, boundaries, and decision rubric.
- `docs/superpowers/plans/2026-08-10-hpa-579-representative-performance-profiling.md` — this execution plan.

**Existing production files that may receive temporary, uncommitted timing statements during the spike:**

- `Virgo/utilities/LocalDTXFixtureImporter.swift` — local file -> parse -> projection boundary.
- `Virgo/utilities/ServerSongDownloader.swift` — downloaded bytes -> decode -> parse -> projection boundary.
- `Virgo/views/GameplayView.swift` — chart selection -> prepared outer boundary.
- `Virgo/viewmodels/GameplayViewModel.swift` — `loadChartData` / `setupGameplay` attribution if needed.
- `Virgo/viewmodels/GameplayViewModel+Computations.swift` — layout build and width-relayout attribution if needed.

**Observed rendering surface, normally unchanged:**

- `Virgo/views/subviews/GameplaySheetMusicView.swift` — static notation, playhead, auto-scroll, and broad view-model observation.

**Result destination:**

- Linear HPA-579 comment — authoritative benchmark context, measurements, decisions, and HPA-584 baseline.
- Linear HPA-580 / HPA-581 — update scope or close only after the HPA-579 evidence supports that action.

No new production file is expected.

---

## Task 1: Freeze the baseline and select the representative real chart

**Files:**
- Read: `Virgo/Fixtures/soukyuu_e_no_shouka/SET.def`
- Read: current locally available/imported chart data through the app
- No source modification expected

**Produces:** A recorded environment block and one named representative chart with note/control/measure/row counts.

- [ ] **Step 1: Start from the current HPA-579 branch and confirm the source baseline**

Run:

```bash
git status -sb
git rev-parse HEAD
git log -1 --oneline
```

Expected: the working tree contains no unrelated source edits before profiling starts. Record the commit SHA used for measurement.

- [ ] **Step 2: Capture machine/toolchain context verbatim**

Run:

```bash
sw_vers
system_profiler SPHardwareDataType | egrep 'Model Name|Model Identifier|Chip|Memory'
xcodebuild -version
xcrun xctrace version
```

Save the literal outputs in the working notes that will become the HPA-579 Linear result comment.

- [ ] **Step 3: Build the macOS app in Release with a dedicated DerivedData directory**

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

Do not use simulator timings as performance evidence.

- [ ] **Step 4: Identify the densest currently available real chart**

Open the current app data and compare real chart candidates by:

- note count;
- control-event count;
- measure count;
- rendered row count after gameplay preparation.

Use the candidate that is directionally largest/densest across those values. Do not choose by difficulty label alone.

If the current server/downloaded library has no clearly denser real chart, use the bundled fixture:

```text
song: soukyuu_e_no_shouka
chart: REAL
file: Virgo/Fixtures/soukyuu_e_no_shouka/real.dtx
```

Record the selected song/chart identity and all four complexity counts. The same identity/counts become the HPA-584 repeat baseline.

- [ ] **Step 5: Warm the app once before timed runs**

Launch the Release app, open/import the representative chart once, enter gameplay once, then close back to the starting screen. The first run is a warm-up and is not included in medians.

Do not warm away the behavior being measured when testing a cold import path; for import, restore the normal pre-import state before each measured run.

---

## Task 2: Measure DTX file/bytes -> decode/parse/projection and decide what HPA-580 could actually move

**Files:**
- Observe/temporarily modify: `Virgo/utilities/LocalDTXFixtureImporter.swift`
- Observe/temporarily modify: `Virgo/utilities/ServerSongDownloader.swift`

**Produces:** Import timing evidence that separates movable parsing/file work, SwiftData mutation, network/file latency, and the fixed inter-chart sleep.

- [ ] **Step 1: Capture a whole-import Time Profiler trace before adding source instrumentation**

Profile the Release app with Instruments **Time Profiler** while importing the representative real song/chart through the normal path available on the machine.

Perform one warm-up and three measured imports. For each measured run, note:

- wall-clock import duration;
- whether the main thread visibly stalls;
- dominant main-thread stacks;
- whether `DTXFileParser`, `persistenceProjection`, SwiftData insert/save, or unrelated work dominates.

If Time Profiler already makes the movable slice obvious, skip temporary source clocks and continue to Step 4.

- [ ] **Step 2: If local file parsing is ambiguous, add one temporary `ContinuousClock` interval**

In `LocalDTXFixtureImporter.loadImportedCharts`, wrap only the existing parse/projection pair:

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

Do not move the code, change isolation, or introduce a timing helper. This is disposable measurement code.

Rebuild Release and repeat three measured imports. Record the per-chart durations and the song-level median/range.

- [ ] **Step 3: If the server bytes path is ambiguous, time only the post-download CPU slice**

In `ServerSongDownloader.processChart`, start timing **after** the existing network await and stop immediately after projection:

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

This interval intentionally excludes `downloadData` network time and all later SwiftData mutation.

Use a currently available server song when the configured endpoint is usable. If no server import is available on the profiling machine, do not fabricate network measurements; record that limitation and base the movable parser/projection decision on the real local-file path plus sampled parser stacks.

- [ ] **Step 4: Account for the fixed inter-chart sleep separately**

For a song with `N` processed charts, calculate the current policy delay as:

```text
max(0, N - 1) * 100 ms
```

Record it as **inter-chart policy latency**, not parse/projection CPU and not main-thread blocking time because `Task.sleep` suspends.

- [ ] **Step 5: Record the HPA-580 evidence classification, but do not edit HPA-580 yet**

Classify the observed import work using the design rubric:

- **Proceed candidate:** movable file/decode/parse/projection work is a material main-thread contributor with visible impact.
- **Narrow candidate:** only a subset is justified, such as local file/projection work or removal of the fixed sleep.
- **Close candidate:** representative import is responsive and the movable slice is not material.

Also explicitly note if SwiftData mutation/save dominates, because HPA-580 cannot solve that by moving models across actors.

---

## Task 3: Measure chart selection -> `isGameplayPrepared`

**Files:**
- Observe/temporarily modify: `Virgo/views/GameplayView.swift`
- Observe/temporarily modify: `Virgo/viewmodels/GameplayViewModel.swift`
- Observe: `Virgo/viewmodels/GameplayViewModel+Computations.swift`

**Produces:** A preparation median/range and attribution to relationship/rhythm/layout/BGM stages.

- [ ] **Step 1: Profile the outer preparation path with Time Profiler**

Use the same Release build and representative chart. Measure from the start of real work in:

```swift
GameplayView.prepareGameplay(initialRowWidth:)
```

through the point where:

```swift
vm.isGameplayPrepared == true
```

Perform one warm-up and three measured entries into gameplay. Record median/range and visible loading/hitch behavior.

- [ ] **Step 2: Attribute the sampled stacks to existing stages**

Use Time Profiler to distinguish:

```text
GameplayView.prepareGameplay
  -> GameplayViewModel.loadChartData
       -> relationship copies
       -> note sort
       -> RhythmTimelineResolver.resolve
       -> makeRhythmRuntime
            -> note target construction
            -> RhythmLayoutSnapshotBuilder.build
            -> RhythmMetronomeSchedule
  -> updateRowWidth
  -> GameplayViewModel.setupGameplay
       -> computeDrumBeats
       -> computeCachedLayoutData
            -> cacheNotationLayout
            -> cacheBeatPositions
       -> setupBGMPlayer
       -> remaining timing/input setup
```

Do not add clocks if the call tree already identifies the dominant stage.

- [ ] **Step 3: If attribution remains ambiguous, add temporary outer/nested clocks only around existing calls**

For the outer view boundary, temporarily record:

```swift
let hpa579Clock = ContinuousClock()
let hpa579PrepareStart = hpa579Clock.now
await vm.loadChartData()
let hpa579AfterLoad = hpa579Clock.now
vm.updateRowWidth(initialRowWidth)
vm.setupGameplay()
let hpa579Prepared = hpa579Clock.now

Logger.info(
    "HPA-579 gameplay loadChartData: \(hpa579PrepareStart.duration(to: hpa579AfterLoad))"
)
Logger.info(
    "HPA-579 gameplay setupGameplay: \(hpa579AfterLoad.duration(to: hpa579Prepared))"
)
```

If `setupGameplay` is the expensive half and Time Profiler still cannot distinguish layout from BGM/timing setup, add a temporary clock immediately around `computeCachedLayoutData()` only. Do not instrument every helper.

- [ ] **Step 4: Record what HPA-581 can and cannot improve**

Explicitly record whether the dominant preparation cost is:

- rhythm resolution / `RhythmLayoutSnapshotBuilder`;
- notation layout / cache building;
- SwiftData relationship access;
- BGM setup;
- another named stage.

Do not count total preparation latency as HPA-581 evidence when the dominant stage is outside HPA-581's proposed boundary.

---

## Task 4: Measure width relayout without confusing the 100 ms debounce with layout CPU

**Files:**
- Observe/temporarily modify: `Virgo/viewmodels/GameplayViewModel+Computations.swift`
- Observe: `Virgo/views/subviews/GameplaySheetMusicView.swift`

**Produces:** Processing cost for `cacheNotationLayout` + `cacheBeatPositions`, user-visible settling behavior, and a clear HPA-581 relayout conclusion.

- [ ] **Step 1: Choose two widths that actually change row packing**

With the representative chart open, resize the macOS window between widths that produce different rendered row counts or measure packing. Verify the notation layout visibly changes.

Do not measure a no-op width transition.

- [ ] **Step 2: Profile the post-debounce callback with Time Profiler**

The current path is:

```text
updateRowWidth
  -> scheduleRowWidthUpdate
       -> 100 ms trailing-edge Timer
            -> cacheNotationLayout
            -> cacheBeatPositions
```

Record the processing stack after the timer fires. Keep the intentional 100 ms debounce separate from processing time.

- [ ] **Step 3: If the callback boundary is hard to isolate, add one temporary clock around the two rebuild calls**

Inside the timer callback only, temporarily use:

```swift
let hpa579Clock = ContinuousClock()
let hpa579Start = hpa579Clock.now
self.cacheNotationLayout()
self.cacheBeatPositions()
let hpa579Duration = hpa579Start.duration(to: hpa579Clock.now)
Logger.info("HPA-579 width relayout processing: \(hpa579Duration)")
```

Do not change the debounce interval and do not use the tests' immediate-layout branch as performance evidence.

- [ ] **Step 4: Repeat one warm-up plus three measured relayouts**

Record:

- processing median/range;
- the fixed 100 ms debounce separately;
- whether the main thread visibly hitches when the rebuild runs;
- whether row packing/scroll position remains responsive.

This evidence determines whether HPA-581 should move width relayout off-main, keep it on-main, or close that sub-scope.

---

## Task 5: Measure initial mount, steady playback updates, scrolling, and memory

**Files:**
- Observe: `Virgo/views/subviews/GameplaySheetMusicView.swift`
- Observe: `Virgo/viewmodels/GameplayViewModel.swift`
- No source modification expected

**Produces:** SwiftUI invalidation evidence and the eager-render baseline HPA-584 will repeat.

- [ ] **Step 1: Capture a SwiftUI + Time Profiler trace for initial mount**

Open gameplay for the representative chart from the library and let the full notation appear.

Record whether initial work is dominated by:

- notation layout preparation before the view mounts;
- construction/evaluation of the static notation subtree;
- other SwiftUI/layout stacks.

Keep initial mount observations separate from steady playback.

- [ ] **Step 2: Capture steady playback for at least 30 seconds**

Start playback and allow the playhead to advance across rows. In the SwiftUI instrument, inspect whether frequent playback changes cause broad re-evaluation of:

- `sheetMusicView` / `staticSheetMusicContent`;
- `drumNotationView` and its full `ForEach` collections;
- or only the expected playhead/row/playing surfaces.

Record the relevant view update pattern and any prominent Time Profiler stacks.

- [ ] **Step 3: Manually scroll while playback remains active**

Scroll vertically and horizontally through the representative chart while the playhead is moving.

Record concrete observations:

- smooth / minor hitch / repeated hitch;
- whether hitches line up with main-thread notation or SwiftUI work;
- whether auto-scroll transitions make the problem materially worse.

Do not convert this into an automated scrolling benchmark in HPA-579.

- [ ] **Step 4: Record peak live memory**

Use Instruments Allocations or the Xcode memory gauge during the same representative mount/playback session. Record peak live memory and enough context to repeat the observation later.

This is a baseline, not a leak investigation.

- [ ] **Step 5: Classify the HPA-581 rendering evidence**

Use the trace to distinguish:

- broad static notation invalidation during frequent playback -> evidence for narrowing observation / static canvas isolation;
- expensive initial static mount but quiet steady playback -> evidence relevant to HPA-584, not automatically HPA-581 off-main work;
- quiet static subtree and responsive scrolling -> evidence against speculative rendering refactors.

Do not add row virtualization here.

---

## Task 6: Remove temporary instrumentation and verify the profiling branch is clean

**Files:**
- Restore if modified:
  - `Virgo/utilities/LocalDTXFixtureImporter.swift`
  - `Virgo/utilities/ServerSongDownloader.swift`
  - `Virgo/views/GameplayView.swift`
  - `Virgo/viewmodels/GameplayViewModel.swift`
  - `Virgo/viewmodels/GameplayViewModel+Computations.swift`

**Produces:** A clean branch with no accidental profiling code or trace artifacts.

- [ ] **Step 1: Revert disposable timing/logging edits**

Run:

```bash
git restore \
  Virgo/utilities/LocalDTXFixtureImporter.swift \
  Virgo/utilities/ServerSongDownloader.swift \
  Virgo/views/GameplayView.swift \
  Virgo/viewmodels/GameplayViewModel.swift \
  Virgo/viewmodels/GameplayViewModel+Computations.swift
```

If a measured boundary genuinely could not be interpreted without a retained signpost, do **not** silently keep the temporary clocks. Replace them with the smallest explicit `os_signpost` interval, explain why retention is necessary in the HPA-579 result, and treat that as a real production change requiring focused tests/lint.

- [ ] **Step 2: Confirm no trace bundles or DerivedData are staged**

Run:

```bash
git status --short
git diff --check
```

Expected: no `.trace` bundle, no `DerivedData-HPA579`, and no accidental source timing diff.

- [ ] **Step 3: If the execution leaves no production diff, do not run the full 1,800+ unit suite solely for the measurement**

The measurements exercised the Release app directly. A docs-only/result-only HPA-579 completion does not gain value from a full unit run.

If a retained signpost production diff exists, run at minimum:

```bash
xcodebuild test \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'platform=macOS' \
  -configuration Debug \
  -only-testing:VirgoTests/GameplayViewModelDataLoadingTests \
  -only-testing:VirgoTests/GameplayViewModelLayoutComputationsTests \
  -parallel-testing-enabled NO \
  -derivedDataPath ./DerivedData

swiftlint lint --quiet
git diff --check
```

Expand focused coverage only to the file whose retained instrumentation changed.

---

## Task 7: Record the evidence in Linear and update the gated tickets

**Files:**
- No repository source file required
- Update: Linear HPA-579
- Conditionally update: Linear HPA-580
- Conditionally update: Linear HPA-581
- Reference baseline: Linear HPA-584

**Produces:** The roadmap gate is resolved with explicit evidence-backed decisions.

- [ ] **Step 1: Post one complete HPA-579 result comment**

Use exactly these sections and fill them with the measured values from Tasks 1-5:

```markdown
## Profiling result

### Environment
- Commit: <literal measured commit SHA>
- Machine: <literal hardware summary>
- OS: <literal macOS version>
- Xcode/Instruments: <literal versions>
- Configuration: Release / macOS

### Representative chart
- Song/chart: <literal identity>
- Notes: <measured count>
- Controls: <measured count>
- Measures: <measured count>
- Rendered rows: <measured count>

### Measurements
- Local DTX file -> parse/projection: <median and range>; dominant stacks: <named stacks>
- Server bytes -> decode/parse/projection: <median and range or explicit unavailable limitation>; dominant stacks: <named stacks>
- Inter-chart policy delay: <chart-count-derived fixed delay>
- Chart selection -> gameplay prepared: <median and range>; dominant stage: <named stage>
- Width relayout processing: <median and range>; 100 ms debounce reported separately
- Mount/playback: <SwiftUI invalidation pattern and main-thread observations>
- Scrolling: <concrete responsiveness observation>
- Peak live memory: <measured value>

### Decisions
- HPA-580: Proceed | Narrow | Close as unnecessary — <evidence-backed reason>
- HPA-581: Proceed | Narrow | Close as unnecessary — <evidence-backed reason>
- HPA-584 baseline: <concise repeatable baseline>
```

The angle-bracket entries above are the **result values produced by the preceding tasks**, not planning guesses. Do not invent missing numbers; when a server-specific measurement cannot be run, state the concrete limitation and what evidence was available instead.

- [ ] **Step 2: Apply the HPA-580 decision**

If **Proceed**:
- keep HPA-580 open;
- update its description only if the trace identifies a narrower exact boundary than the current issue already states.

If **Narrow**:
- update HPA-580's problem/scope/acceptance criteria so implementation contains only the measured justified slice;
- explicitly remove unmeasured off-main work from its required scope.

If **Close as unnecessary**:
- close HPA-580 as canceled/not planned according to the team's normal status semantics;
- reference the HPA-579 result comment in the closing reason.

- [ ] **Step 3: Apply the HPA-581 decision**

If **Proceed**:
- keep HPA-581 open;
- retain only the measured preparation/relayout/rendering scope.

If **Narrow**:
- update HPA-581 to the smallest justified subset, for example:
  - static-view observation/`AnyView` cleanup only;
  - width relayout only;
  - initial preparation only.
- do not retain unmeasured off-main work as a future requirement inside the same ticket.

If **Close as unnecessary**:
- close HPA-581 with the HPA-579 evidence as the reason.

- [ ] **Step 4: Preserve the HPA-584 baseline without starting HPA-584**

Ensure the HPA-579 result contains the representative chart identity/counts, mount behavior, steady playback update behavior, scrolling observation, and peak memory. HPA-584 will repeat those values after any approved gameplay work.

Do not implement or design virtualization in this task.

- [ ] **Step 5: Mark HPA-579 complete only after both downstream decisions are explicit**

HPA-579 is complete when:

- all four required scenarios have evidence;
- HPA-580 has Proceed/Narrow/Close;
- HPA-581 has Proceed/Narrow/Close;
- HPA-584 has a repeatable baseline;
- temporary instrumentation is removed or a retained signpost is explicitly justified.

---

## Task 8: Final repository and PR hygiene

**Files:**
- Verify: the two HPA-579 planning documents
- Conditionally verify: any intentionally retained signpost source diff

**Produces:** A reviewable HPA-579 documentation/measurement history with no accidental implementation scope.

- [ ] **Step 1: Inspect the final branch diff**

Run:

```bash
git status -sb
git diff --check
git diff --stat main...HEAD
git diff main...HEAD -- \
  docs/superpowers/specs/2026-08-10-hpa-579-representative-performance-profiling-design.md \
  docs/superpowers/plans/2026-08-10-hpa-579-representative-performance-profiling.md
```

Expected for the normal outcome: only the HPA-579 planning documents are committed; measured values and decisions live in Linear.

- [ ] **Step 2: Keep large profiling artifacts out of git**

Confirm no `.trace`, exported Instruments package, screenshots, DerivedData, or ad-hoc CSV is committed. The Linear result comment is sufficient for the roadmap decision unless a small textual note is later shown to have clear maintenance value.

- [ ] **Step 3: Review the decision against YAGNI before starting HPA-580/HPA-581**

For each downstream ticket, ask one final question: does the measured problem justify the architectural cost currently proposed?

If not, narrow or close it now. Do not implement a prewritten performance architecture merely because the ticket exists.
