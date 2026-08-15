# HPA-584 Post-HPA-581 Notation Re-profiling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Re-profile Virgo's representative notation path after HPA-581 and make an evidence-backed keep-eager versus row-laziness decision without implementing virtualization in HPA-584.

**Architecture:** Reuse HPA-579's real Release Instruments protocol and fixed Soukyuu MASTER comparison chart. Measure the current interactive preparation, first static mount, playback invalidation, scrolling, memory, and natural resize behavior; add only disposable local markers where Instruments cannot isolate a boundary; record the decision in Linear and restore the repository to a clean source state.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, Xcode 26.x, Xcode Product > Profile, Instruments Time Profiler / SwiftUI / Allocations, unified logging, `ContinuousClock`, Linear.

## Global Constraints

- Follow the measurement contract and decision rubric in `docs/superpowers/specs/2026-08-15-hpa-584-post-hpa-581-notation-reprofiling-design.md`.
- HPA-584 is measurement and decision work only; do not implement row virtualization here.
- Use Soukyuu MASTER / Expert (`Virgo/Fixtures/soukyuu_e_no_shouka/mas.dtx`) as the fixed HPA-579 comparison chart: 2,870 notes, 0 controls, 156 measures, baseline 900 pt / 156 rows.
- HPA-579 comparison values are 267.857 ms median gameplay preparation (264.074-269.534 ms range) and 4,890.729 ms initial mount.
- Release macOS through Xcode Product > Profile is authoritative; a CLI Release build is a compile check only.
- A real unlocked GUI session is required for mount, scrolling, resize, and memory evidence. Do not substitute headless hooks or synthetic interaction.
- Prefer Instruments before source markers. Reuse `Logger.info` / `ContinuousClock` only when needed; do not add a timing framework or permanent signposts.
- Do not create a benchmark target, metrics service, CI performance gate, custom renderer, canvas tiling, pagination, viewport cache, or virtualization prototype.
- Do not change actor isolation, SwiftData ownership, rhythm algorithms, notation geometry, stable notation IDs, or the current 900 pt row-width floor to make a measurement easier.
- Do not present iPad Simulator timings as physical iPad performance.
- Keep `.trace` bundles, profiler exports, screenshots, DerivedData, and temporary logs out of git.
- macOS 14+ and iPadOS remain supported; never introduce an iPhone target.

---

## File Structure

**Planning docs (already committed by the planning PR):**

- `docs/superpowers/specs/2026-08-15-hpa-584-post-hpa-581-notation-reprofiling-design.md` — owns the comparison baseline, measurement contract, decision rubric, and Linear result template.
- `docs/superpowers/plans/2026-08-15-hpa-584-post-hpa-581-notation-reprofiling.md` — owns the executable measurement steps below.

**Temporary source instrumentation, only if Instruments cannot isolate the required boundary:**

- `Virgo/views/GameplayView.swift` — optional preparation-finished marker/timing.
- `Virgo/views/subviews/GameplaySheetMusicView.swift` — optional first `GameplayStaticNotationView` appearance marker.

**Observed but normally unchanged:**

- `Virgo/viewmodels/GameplayViewModel.swift` — `setupGameplay(loadPersistedSpeed:)` and the HPA-581 worker handoff.
- `Virgo/viewmodels/GameplayViewModel+Notation.swift` — notation generation / preparation install path.
- `Virgo/layout/GameplayNotationPreparation.swift` — pure worker preparer.
- `Virgo/layout/NotationLayoutEngine.swift` — layout work that should remain off-main for the timeline path.
- `Virgo/views/subviews/GameplaySheetMusicView.swift` — Equatable static notation boundary plus playhead/auto-scroll container.
- `Virgo/layout/gameplay.swift` — row-width floor and geometry constants.

**External result sink:**

- Linear `HPA-584` — authoritative evidence comment and final decision.
- Linear `HPA-583` — becomes actionable after a keep-eager close, or gains one new blocker only if HPA-584 creates a trace-backed row-laziness follow-up.

---

### Task 1: Establish the interactive Release evidence gate

**Files:**
- Read: `docs/superpowers/specs/2026-08-10-hpa-579-representative-performance-profiling-design.md`
- Read: `.superpowers/sdd/2026-08-12-hpa-581-off-main-notation-preparation/task-8-profile-report.md`
- Read: `Virgo/views/GameplayView.swift`
- Read: `Virgo/views/subviews/GameplaySheetMusicView.swift`

**Interfaces:**
- Consumes: current `main` after merged HPA-581; HPA-579 baseline values; HPA-581 headless worker-path evidence.
- Produces: exact source/toolchain identity, a profileable Release app, and confirmation that the real GUI session can support HPA-584's interaction measurements.

- [ ] **Step 1: Confirm source is current and the working tree is safe for disposable instrumentation**

Run:

```bash
git status -sb
git rev-parse HEAD
git log -1 --oneline
```

Expected: record the exact current commit. If unrelated local changes exist in `GameplayView.swift` or `GameplaySheetMusicView.swift`, do not overwrite them; use a clean worktree for the profiling run.

- [ ] **Step 2: Freeze the current environment beside the HPA-579 baseline**

Run:

```bash
sw_vers
system_profiler SPHardwareDataType | egrep 'Model Name|Model Identifier|Chip|Memory'
xcodebuild -version
xcrun xctrace version
```

Record the literal outputs for the HPA-584 Linear result. Do not downgrade or recreate the HPA-579 toolchain merely to match its version numbers.

- [ ] **Step 3: Compile-check current Release**

Run:

```bash
xcodebuild \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath ./DerivedData-HPA584 \
  build
```

Expected: `** BUILD SUCCEEDED **`.

This proves the current source builds in Release. It is not the authoritative profiled launch.

- [ ] **Step 4: Start the info-level Virgo log stream**

In a separate Terminal, run and leave it active during measured sessions:

```bash
log stream --level info --predicate 'subsystem == "com.cwchanap.Virgo"'
```

If no temporary source markers are ultimately needed, this stream may remain unused.

- [ ] **Step 5: Prove Xcode Product > Profile can present the real interactive app**

In Xcode:

1. Select the shared `Virgo` scheme.
2. Choose **Product > Profile** (`⌘I`).
3. Choose **Time Profiler**.
4. Confirm the Virgo window is visible and interactive.
5. Open a normal screen and record a short trace.
6. Confirm symbolicated Virgo frames such as `GameplayView`, `GameplayViewModel`, or `GameplaySheetMusicView` appear.

Expected: a real visible Virgo window plus symbolicated frames.

If the macOS session is locked/shielded, the app window is not usable, or the trace cannot symbolize Virgo, stop the HPA-584 measurement run and record the gate as blocked. Do not switch to the HPA-581 headless hook as a substitute.

- [ ] **Step 6: Verify the fixed comparison chart before measuring**

Open the bundled Soukyuu song and select MASTER / Expert.

Confirm the current chart still corresponds to:

```text
file: Virgo/Fixtures/soukyuu_e_no_shouka/mas.dtx
notes: 2,870
measures: 156
baseline row width: 900 pt
baseline rendered rows: 156
```

If the fixture identity or counts changed, stop and document the repository change before continuing. Do not silently compare a different chart with HPA-579.

**Checkpoint:** Task 1 creates no source commit. The deliverable is a valid interactive Release profiling environment or an explicit evidence-blocked result.

---

### Task 2: Re-measure gameplay preparation and first static mount

**Files:**
- Observe: `Virgo/views/GameplayView.swift`
- Observe: `Virgo/viewmodels/GameplayViewModel.swift`
- Observe: `Virgo/layout/GameplayNotationPreparation.swift`
- Observe: `Virgo/layout/NotationLayoutEngine.swift`
- Observe: `Virgo/views/subviews/GameplaySheetMusicView.swift`
- Temporarily modify only if needed: `Virgo/views/GameplayView.swift`
- Temporarily modify only if needed: `Virgo/views/subviews/GameplaySheetMusicView.swift`

**Interfaces:**
- Consumes: Soukyuu MASTER and the valid Release profiling environment from Task 1.
- Produces: one warm-up + three measured preparation runs, main/background attribution, and first-mount evidence that distinguishes preparation from the static SwiftUI mount.

- [ ] **Step 1: Capture one warm-up gameplay entry without adding instrumentation**

Using Product > Profile with Time Profiler, open Soukyuu MASTER and let gameplay become ready.

Inspect the call tree first. Confirm the current HPA-581 path still includes:

```text
GameplayView.prepareGameplay
  -> GameplayViewModel.setupGameplay
  -> GameplayViewModel.prepareTimelineNotation
  -> Task.detached
  -> GameplayNotationPreparer.prepare
  -> NotationLayoutEngine.layout
```

Expected: `NotationLayoutEngine.layout` is not a material main-thread preparation stack for the timeline path.

If Instruments already exposes repeatable preparation and mount boundaries, keep source untouched and proceed to Step 4.

- [ ] **Step 2: If preparation timing is ambiguous, add one disposable outer preparation marker**

In `GameplayView.prepareGameplay(initialRowWidth:)`, add a clock at the beginning of the real preparation path and log immediately after `await vm.setupGameplay()` returns:

```swift
let hpa584Clock = ContinuousClock()
let hpa584PrepareStart = hpa584Clock.now
```

Place it after the early `usesInjectedViewModel` / already-prepared return and before the normal setup work. Then, immediately after:

```swift
await vm.setupGameplay()
```

add:

```swift
let hpa584PrepareEnd = hpa584Clock.now
Logger.info(
    "HPA-584 gameplay prepared elapsed=\(hpa584PrepareStart.duration(to: hpa584PrepareEnd)) " +
    "notes=\(vm.cachedNotes.count) measures=\(vm.cachedNotationLayout.measures.count)"
)
```

Do not add per-stage clocks unless the Time Profiler call tree still cannot identify the dominant main-thread stage. HPA-584 does not need another instrumentation subsystem.

- [ ] **Step 3: If first-mount timing is ambiguous, add one disposable static-subtree appearance marker**

In `GameplayStaticNotationView.body`, append one temporary `onAppear` marker to the returned static layer:

```swift
GameplayStaticNotationLayers(
    input: input,
    measurePositions: measurePositions,
    contentWidth: input.contentWidth,
    contentTopInset: input.contentTopInset,
    rowCount: input.rowCount
)
.onAppear {
    Logger.info("HPA-584 static notation appeared generation=\(input.generation)")
}
```

Use the prepared log timestamp and this `onAppear` timestamp only to report **ready -> static subtree appearance**. Do not label that delta compositor-complete frame time.

- [ ] **Step 4: Capture one warm-up plus three measured preparation entries**

For each measured entry:

1. open Soukyuu MASTER through the normal UI;
2. let gameplay reach prepared state;
3. record the preparation duration from the trace or temporary marker;
4. record the prominent main-thread stacks;
5. confirm any `NotationLayoutEngine.layout` samples belong to the worker path rather than the main thread;
6. note whether the loading surface/window remains visibly responsive.

After three measured entries, sort the three duration values and use the middle value as the median; record the minimum and maximum as the range.

If the three traces disagree on the dominant stage, collect two additional entries and document the disagreement rather than introducing statistics infrastructure.

- [ ] **Step 5: Capture initial mount separately with SwiftUI + Time Profiler**

Run a trace that begins before entering gameplay and continues until the full notation sheet is visible.

Record:

- ready -> first static-subtree appearance when the temporary marker is needed;
- whether the visible mount is immediate, briefly delayed, or materially delayed;
- whether the dominant mount stacks are `GameplayStaticNotationView`, `GameplayStaticNotationLayers`, `GameplayDrumNotationView`, large notation `ForEach` construction, or something unrelated;
- whether off-screen row construction is visible as a dominant cost.

Compare with HPA-579's 4,890.729 ms initial-mount observation only if the new boundary is comparable. Otherwise state the instrumentation difference and compare trace attribution/visible behavior instead of calculating a speedup percentage.

- [ ] **Step 6: Preserve evidence but do not commit instrumentation**

Copy the measured preparation values and trace observations into working notes outside git or directly into the eventual Linear comment draft.

Do not commit the temporary markers. They remain disposable until Task 4 cleanup.

**Checkpoint:** Task 2 is independently reviewable when it can answer whether HPA-581 removed the measured main-thread notation-preparation slice and whether the remaining first mount is dominated by eager off-screen rows.

---

### Task 3: Measure playback invalidation, manual scrolling, memory, and natural resize

**Files:**
- Observe: `Virgo/views/subviews/GameplaySheetMusicView.swift`
- Observe: `Virgo/viewmodels/GameplayViewModel+VisualUpdates.swift`
- Observe: `Virgo/layout/gameplay.swift`

**Interfaces:**
- Consumes: the mounted Soukyuu MASTER session and current static-generation architecture.
- Produces: the evidence that directly decides whether eager 156-row mounting remains acceptable.

- [ ] **Step 1: Capture at least 30 seconds of steady production playback**

With the real sheet mounted, start playback and let auto-scroll cross rows for at least 30 seconds while Time Profiler and the SwiftUI instrument observe the app.

Record whether live updates repeatedly enter expensive static work, especially:

```text
GameplayStaticNotationView.body
GameplayStaticNotationLayers.body
GameplayDrumNotationView.body
large notation ForEach construction
```

Also record expected live paths such as the playhead, `currentRow`, `isPlaying`, and outer `GameplayView.sheetMusicView` evaluation.

Frequent outer-container sampling is not sufficient evidence for virtualization. The relevant finding is repeated expensive full-static-row work with visible impact.

- [ ] **Step 2: Manually scroll vertically and horizontally during playback**

While playback remains active:

1. scroll vertically through distant notation rows;
2. scroll horizontally when the content/window permits it;
3. let auto-scroll resume/cross rows afterward.

Classify the real interaction as exactly one of:

```text
smooth
occasional minor hitch
repeated hitch
```

For `repeated hitch`, inspect the simultaneous Time Profiler/SwiftUI stacks and record whether notation-row work is actually responsible.

Do not automate scrolling.

- [ ] **Step 3: Record credible live-memory behavior**

Use Allocations and/or the Xcode memory gauge while:

1. the 156-row chart first mounts;
2. playback runs for at least 30 seconds;
3. manual scrolling traverses distant rows.

Record the exact metric the tool exposes and its value. Prefer peak live memory when available.

If only an end snapshot or another non-peak metric is exposed, name it accurately. If no credible live-memory observation can be obtained at all, mark the HPA-584 decision evidence-blocked; do not close as keep-eager with memory silently omitted.

- [ ] **Step 4: Test only natural packing-changing macOS resize**

Resize the real window through practical widths.

Before timing any resize, confirm the rendered row count changes. The current layout has a 900 pt floor, so a resize that remains 156 rows is a no-op for HPA-584's row-packing question.

If practical widths never change row count, record:

```text
Natural resize: no packing-changing host width available; no relayout timing claimed.
```

Do not use a synthetic 3,000 pt width.

If a real width changes row count, profile the post-debounce preparation/reinstall path and record the fixed debounce latency separately from processing cost.

- [ ] **Step 5: Run one physical iPad-class interaction slice when practical**

If a usable physical iPad is already available:

1. run/profile the current Release-capable app on that device;
2. open the same Soukyuu MASTER chart;
3. observe initial mount;
4. run 30 seconds of playback;
5. scroll across distant rows;
6. record live memory and any repeated hitch.

Record device model and OS.

If no physical iPad is readily available, state that limitation in the result. A simulator may still be used for build/functional checking, but do not use its timings or memory as device-performance evidence.

- [ ] **Step 6: Apply the decision rubric before creating any new work**

Choose **Keep eager** when:

- remaining first-mount cost is not dominated by off-screen notation rows;
- steady playback does not repeatedly execute expensive full-static-row work with visible impact;
- manual scrolling is responsive or observed hitches are not attributable to eager rows;
- mounted-chart memory is reasonable on the tested supported hardware;
- no real resize evidence reveals a row-repacking problem worth new architecture.

Choose **Create row-laziness follow-up** only when trace-backed evidence shows eager full-chart row mounting remains a dominant mount, scrolling, or supported-device memory problem.

Do not implement the chosen follow-up in HPA-584.

**Checkpoint:** Task 3 is complete only when the keep-eager versus row-laziness choice can be defended from real interaction traces and live-memory evidence, not from the fact that the current code contains a large `ZStack`.

---

### Task 4: Record the Linear decision and restore a clean repository

**Files:**
- Temporarily modified if markers were needed: `Virgo/views/GameplayView.swift`
- Temporarily modified if markers were needed: `Virgo/views/subviews/GameplaySheetMusicView.swift`
- No production file is committed by HPA-584.

**Interfaces:**
- Consumes: all Task 1-3 evidence.
- Produces: one authoritative HPA-584 Linear result, optional single row-laziness follow-up, correct HPA-583 dependency state, and a clean repository source diff.

- [ ] **Step 1: Save reusable disposable instrumentation, then revert it**

If temporary source markers were added, run:

```bash
git diff -- \
  Virgo/views/GameplayView.swift \
  Virgo/views/subviews/GameplaySheetMusicView.swift \
  > /tmp/hpa584-instrumentation.patch

git restore -- \
  Virgo/views/GameplayView.swift \
  Virgo/views/subviews/GameplaySheetMusicView.swift
```

If no markers were added, skip the patch file.

Do not add `.trace`, log, screenshot, profiler-export, or DerivedData artifacts to git.

- [ ] **Step 2: Verify the repository is free of HPA-584 measurement changes**

Run:

```bash
git status --short
git diff --check
git diff -- \
  Virgo/views/GameplayView.swift \
  Virgo/views/subviews/GameplaySheetMusicView.swift
```

Expected: no HPA-584 source instrumentation remains; `git diff --check` exits 0.

Remove the local compile-check DerivedData when no longer needed:

```bash
rm -rf ./DerivedData-HPA584
```

- [ ] **Step 3: Post the authoritative HPA-584 result comment**

Use the `## Result template` from the design spec and fill every field with the measured evidence.

The comment must include:

- exact source/machine/OS/Xcode/Instruments identity;
- GUI gate status;
- physical iPad result or explicit unavailable limitation;
- fixed Soukyuu MASTER identity and HPA-579 baseline values;
- post-HPA-581 preparation median/range and main/background attribution;
- ready -> static appearance value or exact instrumentation limitation;
- initial-mount trace attribution and visible observation;
- playback static-tree update pattern;
- manual-scroll classification and attribution;
- exact live-memory metric/value;
- natural-resize result or explicit no-valid-packing-change limitation;
- exactly one `Keep eager` or `Create row-laziness follow-up` decision.

- [ ] **Step 4A: If the decision is Keep eager, close HPA-584 without production work**

Update HPA-584 to completed after the evidence comment is posted.

Do not create a speculative performance ticket. HPA-583 is now the next roadmap closeout task.

- [ ] **Step 4B: If the decision requires row laziness, create exactly one focused follow-up before closing HPA-584**

Create one Linear issue under the Virgo / HPA roadmap with this scope:

```markdown
## Objective

Reduce the trace-backed eager full-chart row cost identified by HPA-584 using the smallest row-based lazy-rendering change.

## Required shape

- Pre-group immutable notation primitives by staff row.
- Render rows in a lazy vertical container.
- Keep horizontal geometry unchanged.
- Keep stable notation IDs unchanged.
- Preserve playhead alignment and auto-scroll.
- Preserve notation goldens/invariants and accessibility.

## Evidence

Link the HPA-584 profiling result and quote only the trace/memory observations that justify this work.

## Non-goals

- Canvas tiling or custom drawing engine.
- Pagination or viewport cache.
- New rendering framework.
- Geometry redesign.
- Unrelated gameplay/view-model refactor.
```

Set that new issue to block HPA-583. Then close HPA-584 as the completed decision ticket.

Do not write the follow-up's implementation design inside HPA-584; it gets its own brainstorming/spec cycle.

- [ ] **Step 5: Final evidence review**

Before reporting completion, check the HPA-584 acceptance criteria line by line against the posted Linear result.

Confirm:

```text
source/toolchain identity recorded
interactive Release gate passed
fixed comparison chart recorded
preparation evidence recorded
first-mount attribution recorded
30+ s playback evidence recorded
manual scrolling evidence recorded
credible live memory recorded
resize result/limitation recorded
iPad result/limitation recorded
one decision recorded
temporary instrumentation removed
no production virtualization implemented
```

If any required evidence is missing, report HPA-584 as blocked/incomplete rather than inferring a keep-eager conclusion.

**Checkpoint:** HPA-584 finishes with a Linear evidence decision and no production source diff. The next engineering action is either HPA-583 or a separately designed row-laziness follow-up.
