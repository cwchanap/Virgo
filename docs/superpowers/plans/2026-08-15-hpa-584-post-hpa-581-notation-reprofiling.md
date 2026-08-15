# HPA-584 Post-HPA-581 Notation Re-profiling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to execute this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Re-profile Virgo's representative notation path after HPA-581 and make a bounded, evidence-backed row-laziness decision without implementing virtualization in HPA-584.

**Architecture:** Reuse HPA-579's Soukyuu MASTER baseline, first calibrate the real window until the installed layout reproduces 900 pt / 156 rows, then run separate Time Profiler, SwiftUI, and memory sessions. Treat geometry as exposure context rather than fabricated CPU attribution, classify resize layout CPU separately from eager-tree cost, and default to no speculative optimization only when two HPA-584 GUI attempts are environment-blocked.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, Xcode Product > Profile, Instruments Time Profiler / SwiftUI / Allocations, Xcode memory gauge, unified logging, `ContinuousClock`, Linear.

## Global Constraints

- Follow `docs/superpowers/specs/2026-08-15-hpa-584-post-hpa-581-notation-reprofiling-design.md`.
- HPA-584 is measurement/decision work only; do not implement row laziness or resize optimization here.
- Use `Virgo/Fixtures/soukyuu_e_no_shouka/mas.dtx` / MASTER / Expert: 2,870 notes, 0 controls, 156 measures.
- Direct comparison with HPA-579 is valid only when the installed layout again reports **900 pt resolved row width / 156 rendered rows**.
- HPA-579 baseline: preparation median 267.857 ms (264.074-269.534 ms), initial mount 4,890.729 ms.
- The current eager unit is the chart-wide static primitive tree, not mounted row views.
- Record row count with `(layout.measures.map(\.row).max() ?? -1) + 1`; `measures.count` is not row count.
- Row pitch is `GameplayLayout.rowHeight + GameplayLayout.rowVerticalSpacing == 320 pt`.
- Geometry exposure is context only; never multiply off-screen row fraction by CPU time.
- Time Profiler, SwiftUI, and memory are separate sessions.
- Prefer Instruments before temporary markers. Reuse `Logger.info` / `ContinuousClock`; add no timing framework/signpost layer.
- No benchmark target, metrics service, CI performance gate, custom renderer, canvas tiling, pagination, viewport cache, actor rewrite, or SwiftData ownership change.
- Post-ready resize layout CPU is separate from row laziness; if a follow-up is justified, reuse existing `GameplayNotationPreparer` + notation generation.
- Physical iPad evidence is advisory. If absent, report iPad performance as unverified; do not use Simulator numbers as device performance.
- Keep traces, profiler exports, screenshots, DerivedData, and temporary logs out of git.
- macOS 14+ and iPadOS remain supported; never add an iPhone target.

---

## File Structure

**Planning docs:**

- `docs/superpowers/specs/2026-08-15-hpa-584-post-hpa-581-notation-reprofiling-design.md`
- `docs/superpowers/plans/2026-08-15-hpa-584-post-hpa-581-notation-reprofiling.md`

**HPA-579 / HPA-581 references:**

- `docs/superpowers/specs/2026-08-10-hpa-579-representative-performance-profiling-design.md`
- `docs/superpowers/specs/2026-08-12-hpa-581-off-main-notation-preparation-design.md`
- `docs/superpowers/plans/2026-08-12-hpa-581-off-main-notation-preparation.md`
- `.superpowers/sdd/2026-08-12-hpa-581-off-main-notation-preparation/task-8-profile-report.md` — tracked supporting evidence for the worker-path/locked-GUI handoff; it does not own requirements.

**Temporary source instrumentation, only if needed:**

- `Virgo/views/GameplayView.swift` — preparation duration/identity marker.
- `Virgo/views/subviews/GameplaySheetMusicView.swift` — resolved geometry/static appearance marker.

**Observed production seams:**

- `Virgo/viewmodels/GameplayViewModel.swift` — `setupGameplay(loadPersistedSpeed:)`.
- `Virgo/viewmodels/GameplayViewModel+Notation.swift` — detached initial preparation and current on-main post-ready width relayout.
- `Virgo/layout/GameplayNotationPreparation.swift` — existing pure worker preparer.
- `Virgo/views/subviews/GameplaySheetMusicView.swift` — eager static `ZStack`, primitive `ForEach`s, row anchors, playhead/auto-scroll.
- `Virgo/views/GameplayView.swift` — gameplay geometry and `StaffLinesBackgroundView`.
- `Virgo/layout/gameplay.swift` — 900 pt floor and 320 pt row pitch.

**Result sink:**

- Linear HPA-584 — authoritative result/decision.
- Linear HPA-583 — unblocked after HPA-584 closes unless a trace-backed rendering follow-up or unresolved tooling blocker still applies.

---

### Task 1: Establish source, references, and the bounded interactive gate

**Files:** read only.

**Produces:** exact source/toolchain identity and either a usable Release GUI or a bounded environment-blocked outcome.

- [ ] **Step 1: Confirm source and worktree safety**

Run:

```bash
git status -sb
git rev-parse HEAD
git log -1 --oneline
```

Record the exact commit. If unrelated local edits exist in `GameplayView.swift` or `GameplaySheetMusicView.swift`, use a clean worktree for profiling rather than overwriting them.

- [ ] **Step 2: Read the baseline/handoff material**

Read the four references listed above.

Confirm current source still matches the HPA-581 shipped boundaries:

```text
initial timeline notation -> GameplayNotationPreparer on Task.detached
static notation -> GameplayStaticNotationView(...).equatable()
post-ready width relayout -> cacheNotationLayout() / NotationLayoutEngine on @MainActor
```

The `.superpowers/sdd/.../task-8-profile-report.md` file is tracked and available despite the broader ignore pattern. Use it only for its recorded worker-path/locked-GUI evidence.

- [ ] **Step 3: Freeze environment identity**

Run:

```bash
sw_vers
system_profiler SPHardwareDataType | egrep 'Model Name|Model Identifier|Chip|Memory'
xcodebuild -version
xcrun xctrace version
```

Record the literal outputs.

- [ ] **Step 4: Compile-check Release**

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

This is a compile check only. Product > Profile is authoritative for profiling.

- [ ] **Step 5: Attempt the real Time Profiler GUI gate**

In Xcode:

1. select the shared Virgo scheme;
2. choose **Product > Profile**;
3. choose **Time Profiler**;
4. confirm the Virgo window is visible and interactive;
5. record a short normal interaction;
6. confirm symbolicated Virgo frames appear.

If usable, continue to Task 2.

- [ ] **Step 6: If the first HPA-584 GUI attempt is environment-blocked, retry once**

For a lock/shield/input/session failure:

1. confirm the macOS session is actually unlocked;
2. confirm normal mouse/keyboard interaction with Virgo is possible outside Instruments;
3. restart Product > Profile once;
4. record this as HPA-584 GUI attempt 2.

Do not replace the attempt with a headless hook.

If attempt 2 is also environment-blocked, skip Tasks 2-5 and go to Task 6 **Blocked fallback**. The fallback closes without optimization and without claiming performance/memory/scrolling are acceptable.

**Checkpoint:** HPA-584 cannot stall indefinitely on GUI session state. There are at most two HPA-584 interactive attempts.

---

### Task 2: Calibrate the HPA-579 geometry, then run Time Profiler

**Files:** observe production seams; temporarily modify `GameplayView.swift` / `GameplaySheetMusicView.swift` only when needed.

**Produces:** a real 900 pt / 156-row comparison plus preparation/mount/playback CPU evidence.

- [ ] **Step 1: Start the info-level log stream only if markers are needed**

```bash
log stream --level info --predicate 'subsystem == "com.cwchanap.Virgo"'
```

- [ ] **Step 2: Add one disposable preparation metadata marker when Instruments cannot expose the required identity/boundary**

In `GameplayView.prepareGameplay(initialRowWidth:)`, after the early returns and before normal preparation begins:

```swift
let hpa584Clock = ContinuousClock()
let hpa584PrepareStart = hpa584Clock.now
```

Immediately after:

```swift
await vm.setupGameplay()
```

add:

```swift
let hpa584RenderedRows = (vm.cachedNotationLayout.measures.map(\.row).max() ?? -1) + 1
Logger.info(
    "HPA-584 prepared " +
    "elapsed=\(hpa584PrepareStart.duration(to: hpa584Clock.now)) " +
    "initialGeometryWidth=\(initialRowWidth) " +
    "resolvedRowWidth=\(vm.cachedLayoutRowWidth) " +
    "rows=\(hpa584RenderedRows) " +
    "notes=\(vm.cachedNotes.count) " +
    "controls=\(vm.cachedControlEvents.count) " +
    "measures=\(vm.cachedNotationLayout.measures.count)"
)
```

- [ ] **Step 3: Add one disposable geometry/static-appearance marker when needed**

In `sheetMusicView(geometry:)`, where both `staticInput` and `geometry` are available:

```swift
GameplayStaticNotationView(input: staticInput)
    .equatable()
    .onAppear {
        let rowPitch = GameplayLayout.rowHeight + GameplayLayout.rowVerticalSpacing
        let visibleRowCapacity = min(
            staticInput.rowCount,
            max(1, Int(ceil(geometry.size.height / rowPitch)) + 1)
        )
        let offscreenFraction = staticInput.rowCount > 0
            ? 1 - Double(visibleRowCapacity) / Double(staticInput.rowCount)
            : 0

        Logger.info(
            "HPA-584 static appeared " +
            "generation=\(staticInput.generation) " +
            "geometryWidth=\(geometry.size.width) " +
            "viewportHeight=\(geometry.size.height) " +
            "rows=\(staticInput.rowCount) " +
            "contentHeight=\(staticInput.contentHeight) " +
            "layoutHeight=\(staticInput.layout.totalHeight) " +
            "visibleRowCapacity=\(visibleRowCapacity) " +
            "offscreenRowFraction=\(offscreenFraction)"
        )
    }
```

Resolved row width comes from the preparation marker's existing `vm.cachedLayoutRowWidth`; do not add another API solely for profiling.

The `onAppear` timestamp marks **subtree insertion/appearance only**. It does not bracket descendant construction and cannot stand alone as mount-cost evidence.

- [ ] **Step 4: Run one untimed calibration entry and pin the baseline window**

Open Soukyuu MASTER once and record:

```text
initial/gameplay geometry width
cachedLayoutRowWidth
rendered row count
viewport height
static content height / layout total height
```

Manually narrow the real window until the installed layout reports exactly:

```text
cachedLayoutRowWidth = 900 pt
renderedRows = 156
```

Because 900 pt is a floor, any gameplay geometry width at or below 900 pt resolves to the same 900 pt layout width. Leave the window at this size for all HPA-579-comparable measured entries.

If the same chart no longer reproduces 900 pt / 156 rows, record the behavior change and do not claim a direct mount-time comparison.

- [ ] **Step 5: Record deterministic geometry exposure**

Using the calibrated metadata, record:

```text
rowPitch = 320 pt
visibleRowCapacity ~= min(renderedRows, ceil(viewportHeight / 320) + 1)
offscreenRowFraction ~= 1 - visibleRowCapacity / renderedRows
```

These are geometry estimates only. Do **not** multiply the fraction by measured static-tree CPU time.

- [ ] **Step 6: Run Time Profiler at the pinned baseline**

Run one warm-up/calibration trace if source markers changed, then **two measured gameplay entries** at the pinned 900 pt / 156-row window.

For each measured entry record:

- preparation duration;
- prominent main-thread preparation stacks;
- whether initial timeline `NotationLayoutEngine.layout` remains on the worker path;
- visible loading responsiveness;
- first-mount full-chart primitive-tree call paths;
- whether the 4,890.729 ms HPA-579 mount boundary is materially comparable.

If the two measured entries disagree materially in attribution or visible behavior, collect a third. Do not add more repetition solely for statistics.

- [ ] **Step 7: Continue at least 30 seconds of playback in Time Profiler**

Let auto-scroll cross rows. Record whether live changes repeatedly enter expensive full-static-tree work.

Expected live outer paths such as playhead/currentRow/isPlaying are not evidence that all primitive collections rebuilt.

**Checkpoint:** Task 2 owns CPU/call-tree evidence and a real baseline-geometry comparison. Geometry exposure is recorded, but no fake per-row CPU share is calculated.

---

### Task 3: Run a separate SwiftUI session for invalidation + real manual scrolling

**Files:** observe only.

**Produces:** the manual-scroll evidence HPA-579 lacked plus SwiftUI-specific update/invalidation observations.

- [ ] **Step 1: Start a distinct SwiftUI profiling session at the pinned window size**

Use Product > Profile with the SwiftUI template. Enter Soukyuu MASTER at the same calibrated window size.

- [ ] **Step 2: Observe 30+ seconds of playback/auto-scroll**

Record whether SwiftUI shows expensive static notation bodies re-evaluating or whether updates stay on expected live surfaces.

Outer `GameplayView.sheetMusicView` activity alone is not evidence that the full primitive tree rebuilt.

- [ ] **Step 3: Manually scroll while playback remains active**

1. scroll vertically through distant notation content;
2. scroll horizontally when the real window/content permits it;
3. let normal auto-scroll resume.

Classify exactly:

```text
smooth
occasional minor hitch
repeated hitch
```

For a repeated hitch, correlate the SwiftUI evidence with Task 2 Time Profiler call paths before blaming eager rendering.

- [ ] **Step 4: Preserve instrumentation limitations explicitly**

If the SwiftUI instrument does not expose useful invalidation detail, record that fact together with the real manual-scroll classification. Missing invalidation rows are not proof of static isolation.

**Checkpoint:** Task 3 closes the real-manual-scroll evidence gap without automating interaction.

---

### Task 4: Run a separate memory session starting before gameplay

**Files:** no source changes required.

**Produces:** named macOS live-memory evidence required for an evidence-backed keep-eager decision.

- [ ] **Step 1: Start Allocations before gameplay at the pinned window size**

Record exact tool metric names/values before entering Soukyuu MASTER.

- [ ] **Step 2: Record the post-mount value**

After the full sheet mounts, record the same metric(s). Do not rename snapshots/aggregates as peak memory.

- [ ] **Step 3: Run 30+ seconds playback and real scrolling**

Record the live-memory value/range available during/after the interaction.

If the tool explicitly exposes a peak-live metric, record it as peak. Otherwise leave peak unavailable.

- [ ] **Step 4: Use the Xcode memory gauge only when Allocations cannot provide credible live data**

Repeat the same Release sequence and record:

- gauge before gameplay;
- gauge after mount;
- highest **observed gauge reading** during playback/scroll.

Label it exactly as an observed gauge reading, not an Instruments peak.

- [ ] **Step 5: Enforce the memory gate separately from the GUI fallback**

If neither Allocations nor the memory gauge yields a credible named macOS live-memory observation **while the GUI itself is usable**, report HPA-584 as:

```text
Tooling-blocked — credible live-memory evidence unavailable
```

Do not use the two-attempt GUI fallback. HPA-583 remains blocked until a later memory measurement succeeds or Linear explicitly narrows the scope.

**Checkpoint:** Task 4 finishes only with a named metric/value or an explicit tooling blocker.

---

### Task 5: Sweep natural wider resize; run physical iPad only when available

**Files:** observe `GameplayViewModel+Notation.swift`, `GameplayNotationPreparation.swift`, `gameplay.swift`.

**Produces:** a correctly classified resize result plus optional device evidence.

- [ ] **Step 1: Start from the calibrated 900 pt / 156-row window**

Record the baseline resolved row width and row count once more.

- [ ] **Step 2: Widen the real window until the first packing change**

Because 900 pt is a floor, sweep **wider** through practical host widths.

At each meaningful width record:

```text
geometry width
cachedLayoutRowWidth
rendered row count
```

Stop at the first real row-count change and profile it. If the widest practical host window still leaves 156 rows, record that limitation only after completing the sweep.

Never use the synthetic 3,000 pt probe as natural resize evidence.

- [ ] **Step 3: For a real packing change, capture a dedicated Time Profiler resize trace**

Keep debounce latency separate from processing cost and classify the dominant post-debounce work as:

```text
layout CPU dominates
SwiftUI full-tree rebuild dominates
neither material
```

- [ ] **Step 4: Route layout CPU to the existing preparer design**

If main-actor `cacheNotationLayout()` / `NotationLayoutEngine.layout` is visibly/materially dominant, do not treat it as row-laziness evidence.

Any follow-up must reuse HPA-581 Task 7's shape:

```text
post-ready timeline relayout -> existing GameplayNotationPreparer
reuse existing notation generation
latest width wins
no new worker framework/generation
```

HPA-584 implements none of it.

- [ ] **Step 5: Treat full-tree rebuild as eager-tree evidence**

If the packing change's visible/material cost is primarily SwiftUI rebuilding the full static primitive tree, carry that evidence into Task 6's row-laziness decision.

- [ ] **Step 6: Run a physical iPad slice only when readily available**

If a usable physical iPad is available, repeat initial mount, 30 seconds playback, real scrolling, and live memory. Record device/OS. Any material device-specific problem counts toward the decision.

If no physical iPad is available, record:

```text
iPad performance: unverified
```

Do not block solely on hardware availability and do not claim iPad performance is verified.

**Checkpoint:** Resize and iPad evidence cannot silently change scope. Resize CPU and eager-tree cost remain separate; absent iPad hardware becomes an explicit limitation.

---

### Task 6: Apply the decision, update Linear, and restore the repository

**Files:** temporary source markers only if Task 2 needed them; no production code is committed by HPA-584.

**Produces:** one HPA-584 result, optional trace-backed follow-up(s), correct HPA-583 dependency state, and no measurement source diff.

- [ ] **Step 1: Save scoped reusable instrumentation, then revert it**

If markers were added:

```bash
git diff -- \
  Virgo/views/GameplayView.swift \
  Virgo/views/subviews/GameplaySheetMusicView.swift \
  > /tmp/hpa584-instrumentation.patch

git restore -- \
  Virgo/views/GameplayView.swift \
  Virgo/views/subviews/GameplaySheetMusicView.swift
```

Keep this scoped patch pattern rather than a broad `git stash`; it cannot hide unrelated worktree changes and matches HPA-579's disposable-instrumentation workflow.

- [ ] **Step 2: Verify measurement changes are gone**

Run:

```bash
git status --short
git diff --check
git diff -- \
  Virgo/views/GameplayView.swift \
  Virgo/views/subviews/GameplaySheetMusicView.swift
```

Expected: no HPA-584 source instrumentation remains; `git diff --check` exits 0.

Remove local compile-check DerivedData:

```bash
rm -rf ./DerivedData-HPA584
```

- [ ] **Step 3A: Evidence-backed Keep eager**

Choose **Keep eager** only when Tasks 2-4 completed and show:

- comparable 900 pt / 156-row mount is not a material eager-tree problem with visible impact;
- 30+ seconds playback does not repeatedly rebuild expensive full-static content with visible impact;
- real manual scrolling is responsive or hitches are unrelated to eager full-chart construction;
- credible macOS live memory is reasonable for this chart.

Geometry may show most row extent is off-screen; that fact alone does not justify laziness.

If no physical iPad was measured, explicitly scope the result to measured macOS hardware and state iPad performance is unverified.

- [ ] **Step 3B: Create one row-laziness follow-up only from positive evidence**

Create exactly one issue when eager full-chart primitive construction is a dominant mount, scroll/frame, or memory problem.

Required scope:

```markdown
## Objective

Reduce the trace-backed eager full-chart primitive-tree cost identified by HPA-584 using the smallest row-grouped lazy-rendering change.

## Required shape

- Pre-group immutable notation primitives by staff row.
- Render row-grouped primitives in a lazy vertical container.
- Keep horizontal geometry unchanged.
- Keep stable notation IDs unchanged.
- Preserve playhead alignment and auto-scroll.
- Preserve notation goldens/invariants and accessibility.
- Wrapping the existing chart-wide GameplayDrumNotationView unchanged is not sufficient.

## Non-goals

- Canvas/custom renderer.
- Pagination/viewport cache.
- New rendering framework.
- Geometry redesign.
- Unrelated gameplay/view-model refactor.
```

Make this issue block HPA-583. Do not design/implement it in HPA-584.

- [ ] **Step 3C: Create a separate resize-only follow-up only when Task 5 proved material main-actor layout CPU**

Use the existing `GameplayNotationPreparer` / notation-generation design from HPA-581 Task 7. Do not call it virtualization. Make it block HPA-583 until that rendering path settles.

- [ ] **Step 3D: Bounded GUI-environment fallback**

If both HPA-584 GUI attempts in Task 1 failed for environment/session reasons, close HPA-584 as:

```text
Close without optimization — interactive evidence unavailable
```

The result must say:

- HPA-581 headless worker evidence exists;
- deterministic chart facts remain context only;
- current HPA-584 mount, manual scrolling, and live memory were not verified;
- no claim is made that eager rendering is performant/memory-safe;
- no speculative row-laziness/resize issue is created;
- HPA-583 is unblocked by YAGNI because no evidence justifies rendering architecture work.

- [ ] **Step 3E: Tooling-blocked memory path**

If the GUI is usable but Task 4 cannot obtain credible live-memory evidence from Allocations or the Xcode memory gauge, post the partial evidence and keep HPA-584/HPA-583 blocked as:

```text
Tooling-blocked — credible live-memory evidence unavailable
```

Do not convert this into the GUI fallback. A later successful memory measurement or explicit Linear scope change is required.

- [ ] **Step 4: Post the authoritative HPA-584 result**

Use the design spec's result template. Fill every applicable field with actual evidence or explicit limitation.

- [ ] **Step 5: Final evidence review**

Confirm exactly one current state:

```text
A. evidence-backed Keep eager
B. trace-backed row-laziness follow-up
C. bounded GUI-environment close without optimization
D. tooling-blocked pending credible memory evidence
```

Also confirm:

```text
source/toolchain identity recorded
fixed chart recorded
900 pt / 156-row calibration used for direct comparison
viewport/content geometry recorded
separate Time Profiler / SwiftUI / memory sessions completed for A/B
manual scroll recorded for A/B
macOS live memory recorded for A/B
natural wider resize sweep recorded for A/B
iPad result or explicit unverified limitation recorded
no fabricated off-screen CPU calculation
temporary instrumentation removed
no production virtualization implemented
```

**Checkpoint:** HPA-584 ends with an explicit decision/limitation and no production source diff. The next work is HPA-583, a separately designed trace-backed follow-up, or a later memory evidence retry if state D applies.
