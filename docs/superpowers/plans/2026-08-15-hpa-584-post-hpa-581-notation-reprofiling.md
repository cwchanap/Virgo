# HPA-584 Post-HPA-581 Notation Re-profiling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Re-profile Virgo's representative notation path after HPA-581 and make an evidence-backed keep-eager versus row-laziness decision without implementing virtualization in HPA-584.

**Architecture:** Reuse HPA-579's fixed Soukyuu MASTER Release comparison, but collect CPU, SwiftUI interaction, and memory evidence in separate sessions. Measure the current chart-wide eager primitive tree against viewport/content geometry, classify natural resize layout CPU separately from eager-tree cost, add only disposable markers when Instruments cannot isolate a boundary, record the result in Linear, and restore the repository to a clean source state.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, Xcode 26.x, Xcode Product > Profile, Instruments Time Profiler / SwiftUI / Allocations, Xcode memory gauge, unified logging, `ContinuousClock`, Linear.

## Global Constraints

- Follow the measurement contract and decision rubric in `docs/superpowers/specs/2026-08-15-hpa-584-post-hpa-581-notation-reprofiling-design.md`.
- HPA-584 is measurement and decision work only; do not implement row virtualization here.
- Use Soukyuu MASTER / Expert (`Virgo/Fixtures/soukyuu_e_no_shouka/mas.dtx`) as the fixed HPA-579 comparison chart: 2,870 notes, 0 controls, 156 measures, baseline 900 pt / 156 rows.
- HPA-579 comparison values are 267.857 ms median gameplay preparation (264.074-269.534 ms range) and 4,890.729 ms initial mount.
- Release macOS through Xcode Product > Profile is authoritative; a CLI Release build is a compile check only.
- A real unlocked GUI session is required for mount, scrolling, resize, and memory evidence. Do not substitute headless hooks or synthetic interaction.
- The current eager unit is the **full-chart static primitive tree** (`GameplayStaticNotationLayers` / `GameplayDrumNotationView` and sibling layers), not a pre-existing array of row views.
- Record rendered row count from `(layout.measures.map(\.row).max() ?? -1) + 1`; `measures.count` is not row count.
- Prefer Instruments before source markers. Reuse `Logger.info` / `ContinuousClock` only when needed; do not add a timing framework or permanent signposts.
- Do not create a benchmark target, metrics service, CI performance gate, custom renderer, canvas tiling, pagination, viewport cache, or virtualization prototype.
- Do not change actor isolation, SwiftData ownership, rhythm algorithms, notation geometry, stable notation IDs, or the current 900 pt row-width floor to make a measurement easier.
- Natural resize layout CPU is a separate classification from eager-tree cost. If material, reuse the existing `GameplayNotationPreparer` / notation-generation design; do not mis-file it as row laziness.
- Do not present iPad Simulator timings as physical iPad performance.
- Keep `.trace` bundles, profiler exports, screenshots, DerivedData, and temporary logs out of git.
- Do not depend on `.superpowers/sdd/...` reports; `.superpowers/` is gitignored.
- macOS 14+ and iPadOS remain supported; never introduce an iPhone target.

---

## File Structure

**Planning docs:**

- `docs/superpowers/specs/2026-08-15-hpa-584-post-hpa-581-notation-reprofiling-design.md` — owns the baseline, measurement contract, eager-tree decision rubric, resize classification, and Linear result template.
- `docs/superpowers/plans/2026-08-15-hpa-584-post-hpa-581-notation-reprofiling.md` — owns the executable steps below.

**Committed HPA-581 references:**

- `docs/superpowers/specs/2026-08-12-hpa-581-off-main-notation-preparation-design.md` — static isolation and worker-boundary design.
- `docs/superpowers/plans/2026-08-12-hpa-581-off-main-notation-preparation.md` — implementation order, including Task 7's evidence-gated width-relayout reuse of `GameplayNotationPreparer`.

**Temporary source instrumentation, only if Instruments cannot isolate required boundaries:**

- `Virgo/views/GameplayView.swift` — optional preparation-complete metadata/timing marker.
- `Virgo/views/subviews/GameplaySheetMusicView.swift` — optional static-subtree appearance and viewport/content-geometry marker.

**Observed but normally unchanged:**

- `Virgo/viewmodels/GameplayViewModel.swift` — `setupGameplay(loadPersistedSpeed:)`.
- `Virgo/viewmodels/GameplayViewModel+Notation.swift` — current detached preparation plus on-main post-ready width relayout.
- `Virgo/layout/GameplayNotationPreparation.swift` — existing pure worker preparer.
- `Virgo/layout/NotationLayoutEngine.swift` — layout engine.
- `Virgo/views/subviews/GameplaySheetMusicView.swift` — chart-wide static `ZStack`, primitive `ForEach`s, row anchors, playhead/auto-scroll container.
- `Virgo/views/GameplayView.swift` — `StaffLinesBackgroundView` unique-row loop and gameplay geometry.
- `Virgo/layout/gameplay.swift` — 900 pt row-width floor and row geometry constants.

**External result sink:**

- Linear `HPA-584` — authoritative evidence comment and eager-tree decision.
- Linear `HPA-583` — becomes actionable after performance/rendering follow-ups settle.

---

### Task 1: Establish the interactive Release evidence gate and committed references

**Files:**
- Read: `docs/superpowers/specs/2026-08-10-hpa-579-representative-performance-profiling-design.md`
- Read: `docs/superpowers/specs/2026-08-12-hpa-581-off-main-notation-preparation-design.md`
- Read: `docs/superpowers/plans/2026-08-12-hpa-581-off-main-notation-preparation.md`
- Read: `Virgo/views/GameplayView.swift`
- Read: `Virgo/views/subviews/GameplaySheetMusicView.swift`
- Read: `Virgo/viewmodels/GameplayViewModel+Notation.swift`

**Interfaces:**
- Consumes: current `main` after merged HPA-581, the committed HPA-579/HPA-581 docs, merged PR #61 / HPA-581 Linear discussion as optional supporting history.
- Produces: exact source/toolchain identity, a profileable Release app, a verified fixed comparison chart, and confirmation that the real GUI session can support HPA-584 measurements.

- [ ] **Step 1: Confirm source is current and the working tree is safe for disposable instrumentation**

Run:

```bash
git status -sb
git rev-parse HEAD
git log -1 --oneline
```

Record the exact current commit. If unrelated local changes exist in `GameplayView.swift` or `GameplaySheetMusicView.swift`, use a clean worktree rather than overwriting them.

- [ ] **Step 2: Read only committed HPA-581 handoff material**

Read the two committed HPA-581 documents listed above. Confirm the current source matches their key shipped boundaries:

```text
initial timeline notation preparation -> GameplayNotationPreparer on Task.detached
static notation -> GameplayStaticNotationView(...).equatable()
post-ready width update -> cacheNotationLayout() on @MainActor today
```

Do not require `.superpowers/sdd/.../task-8-profile-report.md`; a clean checkout may not have it.

- [ ] **Step 3: Freeze the current environment beside the HPA-579 baseline**

Run:

```bash
sw_vers
system_profiler SPHardwareDataType | egrep 'Model Name|Model Identifier|Chip|Memory'
xcodebuild -version
xcrun xctrace version
```

Record the literal outputs for the HPA-584 Linear result. Do not recreate old tool versions merely to match HPA-579.

- [ ] **Step 4: Compile-check current Release**

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

This is a compile check only; Product > Profile is the authoritative measurement launch.

- [ ] **Step 5: Start the info-level Virgo log stream**

In a separate Terminal:

```bash
log stream --level info --predicate 'subsystem == "com.cwchanap.Virgo"'
```

Leave it running only if temporary markers are needed.

- [ ] **Step 6: Prove Time Profiler can present the real interactive app**

In Xcode:

1. select the shared `Virgo` scheme;
2. choose **Product > Profile** (`⌘I`);
3. choose **Time Profiler**;
4. confirm the Virgo window is visible and interactive;
5. record a short normal interaction;
6. confirm symbolicated Virgo frames such as `GameplayView`, `GameplayViewModel`, or `GameplaySheetMusicView` appear.

If the session is locked/shielded, the app is not interactable, or symbols are unusable, stop and mark HPA-584 evidence-blocked. Do not switch to a headless hook.

- [ ] **Step 7: Verify the fixed Soukyuu MASTER identity**

Open the bundled Soukyuu song and select MASTER / Expert. Confirm it remains the same fixture/chart with the HPA-579 identity:

```text
file: Virgo/Fixtures/soukyuu_e_no_shouka/mas.dtx
notes: 2,870
controls: 0
measures: 156
baseline row width: 900 pt
baseline rendered rows: 156
```

The UI may confirm the visible note count, but it cannot by itself prove rendered row count. Re-record row count from the installed layout in Task 2.

**Checkpoint:** Task 1 finishes with either a valid interactive Release profiling environment or an explicit blocked result. It creates no source commit.

---

### Task 2: Time Profiler — preparation, first eager-tree mount, and steady playback CPU

**Files:**
- Observe: `Virgo/views/GameplayView.swift`
- Observe: `Virgo/viewmodels/GameplayViewModel.swift`
- Observe: `Virgo/viewmodels/GameplayViewModel+Notation.swift`
- Observe: `Virgo/layout/GameplayNotationPreparation.swift`
- Observe: `Virgo/layout/NotationLayoutEngine.swift`
- Observe: `Virgo/views/subviews/GameplaySheetMusicView.swift`
- Temporarily modify only if needed: `Virgo/views/GameplayView.swift`
- Temporarily modify only if needed: `Virgo/views/subviews/GameplaySheetMusicView.swift`

**Interfaces:**
- Consumes: valid Release GUI gate and Soukyuu MASTER from Task 1.
- Produces: preparation median/range, worker/main attribution, viewport/content metadata, first-mount full-chart primitive-tree attribution, and 30+ seconds of playback CPU evidence.

- [ ] **Step 1: Capture one warm-up entry with Time Profiler before adding markers**

Start Time Profiler before entering gameplay, open Soukyuu MASTER, and let the full sheet mount.

Confirm the current preparation call tree still includes the worker path:

```text
GameplayView.prepareGameplay
  -> GameplayViewModel.setupGameplay
  -> GameplayViewModel.prepareTimelineNotation
  -> Task.detached
  -> GameplayNotationPreparer.prepare
  -> NotationLayoutEngine.layout
```

`NotationLayoutEngine.layout` must not be a material main-thread initial-preparation stack for the timeline path.

Inspect the mount for the actual eager units:

```text
GameplayStaticNotationView.body
GameplayStaticNotationLayers.body
GameplayDrumNotationView.body
ForEach(layout.noteHeads / stems / beams / rests / ...)
StaffLinesBackgroundView
GameplayBarLinesView
GameplayClefsAndTimeSignaturesView
GameplayRowAnchorColumn
```

Do not search for a nonexistent per-row mounted view.

- [ ] **Step 2: If preparation timing/identity is ambiguous, add one disposable preparation metadata marker**

In `GameplayView.prepareGameplay(initialRowWidth:)`, after the early return and immediately before normal preparation begins:

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
let hpa584PrepareEnd = hpa584Clock.now
let hpa584RenderedRows = (vm.cachedNotationLayout.measures.map(\.row).max() ?? -1) + 1
Logger.info(
    "HPA-584 prepared " +
    "elapsed=\(hpa584PrepareStart.duration(to: hpa584PrepareEnd)) " +
    "notes=\(vm.cachedNotes.count) " +
    "controls=\(vm.cachedControlEvents.count) " +
    "measures=\(vm.cachedNotationLayout.measures.count) " +
    "rowWidth=\(vm.cachedLayoutRowWidth) " +
    "renderedRows=\(hpa584RenderedRows)"
)
```

This deliberately records both measure count and rendered row count. Do not infer one from the other.

- [ ] **Step 3: If viewport/content geometry or ready-to-static appearance is ambiguous, add one disposable static marker**

In `sheetMusicView(geometry:)`, attach one temporary marker to the mounted static notation surface where both `staticInput` and `geometry` are available:

```swift
GameplayStaticNotationView(input: staticInput)
    .equatable()
    .onAppear {
        Logger.info(
            "HPA-584 static appeared " +
            "generation=\(staticInput.generation) " +
            "rows=\(staticInput.rowCount) " +
            "viewportHeight=\(geometry.size.height) " +
            "contentHeight=\(staticInput.contentHeight) " +
            "layoutHeight=\(staticInput.layout.totalHeight)"
        )
    }
```

Use the preparation-complete and static-appearance timestamps only as **ready -> static subtree appearance** timing. Do not call the delta compositor-complete frame time.

- [ ] **Step 4: Capture one warm-up plus three measured preparation entries**

For each measured entry:

1. start/continue a Time Profiler run before entering gameplay;
2. open Soukyuu MASTER through the normal UI;
3. record preparation duration from Time Profiler or the disposable marker;
4. record prominent main-thread preparation stacks;
5. confirm `NotationLayoutEngine.layout` samples are on the worker path for initial timeline preparation;
6. record the metadata marker values, including rendered row count;
7. note whether the loading/window remains visibly responsive.

After three measured entries, use the middle duration as the median and minimum/maximum as the observed range. If dominant stages disagree, collect two more runs rather than adding statistics infrastructure.

- [ ] **Step 5: Attribute first mount against the chart-wide eager primitive tree**

Use a Time Profiler run that starts before entering gameplay and continues until the full sheet is visible.

Record:

- ready -> static-subtree appearance when a marker was required;
- viewport height versus `staticInput.contentHeight` / `layout.totalHeight`;
- rendered row count;
- whether visible first mount is immediate, briefly delayed, or materially delayed;
- which chart-wide primitive/layer stacks dominate the mount;
- whether the dominant work corresponds to full-chart primitive construction while most content height is outside the viewport.

Compare to HPA-579's 4,890.729 ms mount only if the boundary is materially comparable. Otherwise state the boundary difference and compare attribution/visible behavior without a percentage speedup claim.

- [ ] **Step 6: Continue at least 30 seconds of production playback in Time Profiler**

After the sheet is mounted, play for at least 30 seconds and let auto-scroll cross rows.

Record whether live updates repeatedly enter expensive chart-wide static work. Expected live paths such as playhead movement, `currentRow`, `isPlaying`, or the outer `sheetMusicView` are not sufficient evidence that the static primitive tree rebuilt.

- [ ] **Step 7: Preserve evidence without committing instrumentation**

Copy measured values and trace observations to local notes outside git or directly into the eventual Linear result draft. Leave markers disposable until cleanup.

**Checkpoint:** Task 2 answers the CPU/call-tree side of the decision using the renderer that actually exists: one eager full-chart primitive tree whose content can extend far beyond the viewport.

---

### Task 3: SwiftUI session — playback invalidation and real manual scrolling

**Files:**
- Observe: `Virgo/views/subviews/GameplaySheetMusicView.swift`
- Observe: `Virgo/viewmodels/GameplayViewModel+VisualUpdates.swift`

**Interfaces:**
- Consumes: the fixed chart and geometry identity from Task 2.
- Produces: a separate SwiftUI invalidation/update record plus real manual-scroll behavior.

- [ ] **Step 1: Start a distinct SwiftUI Instruments session before gameplay entry**

Use Xcode **Product > Profile** and select the SwiftUI template/instrument. Do not assume the Time Profiler run from Task 2 also captured SwiftUI invalidation evidence.

Open Soukyuu MASTER and let the full notation sheet mount.

- [ ] **Step 2: Observe at least 30 seconds of playback and auto-scroll**

Start playback and let the playhead/auto-scroll cross rows.

Inspect whether updates re-enter expensive static notation bodies or remain confined to expected live surfaces. Sampling/invalidating the outer `GameplayView.sheetMusicView` alone is not proof that `GameplayDrumNotationView` or all primitive `ForEach`s rebuilt.

Record the exact SwiftUI evidence the instrument exposes. If it does not provide useful invalidation rows, state that limitation explicitly.

- [ ] **Step 3: Manually scroll while playback remains active**

During the same SwiftUI session:

1. scroll vertically through distant notation content;
2. scroll horizontally when the real window/content permits it;
3. let normal auto-scroll resume afterward.

Classify the interaction exactly as:

```text
smooth
occasional minor hitch
repeated hitch
```

For a repeated hitch, record the simultaneous SwiftUI evidence and correlate with Task 2 Time Profiler stacks before attributing it to eager full-chart rendering.

Do not automate scrolling.

- [ ] **Step 4: Record instrumentation limitations instead of inferring success**

If the SwiftUI instrument cannot expose useful invalidation/update rows, preserve the real manual-scroll classification and explicitly mark invalidation attribution as unavailable. Do not convert missing rows into a "static isolation proven" conclusion.

**Checkpoint:** Task 3 closes HPA-579's missing real-manual-scroll evidence and provides a SwiftUI-specific update/invalidation view independent of Time Profiler.

---

### Task 4: Memory session — begin before gameplay and capture mount delta/live value

**Files:**
- No source changes required.

**Interfaces:**
- Consumes: Soukyuu MASTER and the real unlocked GUI session.
- Produces: a credible named live-memory observation that is mandatory for a keep-eager conclusion.

- [ ] **Step 1: Start a distinct Allocations session before gameplay entry**

Use Xcode **Product > Profile** and select **Allocations**. Begin recording before entering Soukyuu MASTER so pre-gameplay and mounted-chart states are both visible.

Do not reuse a Time Profiler export and call persistent bytes or VM-region totals "peak live memory."

- [ ] **Step 2: Record pre-gameplay and post-mount metrics by exact tool name**

Record the exact metric names/values the tool exposes before gameplay, then after the full sheet mounts.

Examples of acceptable reporting shape:

```text
Allocations <exact metric name>: pre-gameplay X -> post-mount Y
```

Do not rename the metric in the result.

- [ ] **Step 3: Continue 30+ seconds of playback and real scrolling**

Run playback for at least 30 seconds, manually traverse distant notation content, and record the live-memory value/range the tool exposes.

If Allocations explicitly provides a peak-live value, record it as peak. If it only provides snapshots or another aggregate, name that value accurately and keep "peak" unavailable.

- [ ] **Step 4: Fall back to the Xcode memory gauge only when Allocations is unusable**

If Allocations cannot attach or cannot expose a credible live value, run the same Release interaction using the Xcode memory gauge:

1. record the gauge before gameplay;
2. enter Soukyuu MASTER and let the full sheet mount;
3. record the gauge after mount;
4. run 30+ seconds of playback and manual scrolling;
5. record the highest **observed gauge reading** as such.

Do not call a manually observed maximum an Instruments peak unless the tool labels it that way.

- [ ] **Step 5: Enforce the memory gate**

If neither Allocations nor the Xcode memory gauge yields a credible named live-memory observation, mark HPA-584 evidence-blocked. Do not proceed to a keep-eager close with memory omitted.

**Checkpoint:** Task 4 is complete only when the result can name the memory tool, metric, and value(s) without pretending a snapshot is a peak.

---

### Task 5: Natural resize triage and optional physical iPad check

**Files:**
- Observe: `Virgo/viewmodels/GameplayViewModel+Notation.swift`
- Observe: `Virgo/layout/GameplayNotationPreparation.swift`
- Observe: `Virgo/layout/gameplay.swift`

**Interfaces:**
- Consumes: current mounted chart and the HPA-581 Task 7 width-relayout design.
- Produces: a resize classification that cannot be confused with row laziness, plus optional supported-device evidence.

- [ ] **Step 1: Attempt only a natural packing-changing macOS resize**

Resize the real window through practical widths.

Before profiling a resize, re-record rendered row count:

```swift
(cachedNotationLayout.measures.map(\.row).max() ?? -1) + 1
```

If practical widths never change the row count, record:

```text
Natural resize: no packing-changing host width available; no relayout timing claimed.
```

Do not use a synthetic 3,000 pt width.

- [ ] **Step 2: If row packing changes, run a dedicated Time Profiler resize capture**

Keep the fixed debounce latency separate from processing cost and classify the dominant post-debounce work as exactly one of:

```text
layout CPU dominates
SwiftUI full-tree rebuild dominates
neither material
```

Current source is expected to show `cacheNotationLayout()` -> `NotationLayoutEngine().layout(...)` on `@MainActor` for post-ready relayout.

- [ ] **Step 3: Route a layout-CPU finding to the existing preparer design, not row laziness**

If a real packing change is visibly/materially slow because layout CPU dominates, do **not** use that as evidence for the row-laziness follow-up.

The narrow follow-up shape is already defined by HPA-581 Task 7:

```text
route timeline relayout through existing GameplayNotationPreparer
reuse the same notation generation
latest width wins
cancellation is cleanup only
```

HPA-584 still implements zero production code.

- [ ] **Step 4: Treat a full-tree rebuild finding as eager-tree evidence**

If the layout calculation is not dominant but the real packing change rebuilds the full SwiftUI primitive tree with visible cost, carry that evidence into the Task 6 row-laziness decision.

- [ ] **Step 5: Run one physical iPad-class interaction slice when practical**

If a usable physical iPad is already available:

1. open the same Soukyuu MASTER chart;
2. observe first mount;
3. play for at least 30 seconds;
4. manually scroll through distant notation content;
5. record a credible live-memory value and any repeated hitch;
6. record device model and OS.

If no physical iPad is readily available, state that limitation. A simulator may be used for build/functional checks only; do not report its performance as device performance.

**Checkpoint:** Task 5 produces either a no-packing-change limitation or a correctly classified resize result. Layout CPU and eager-tree cost remain separate conclusions.

---

### Task 6: Apply the decision rubric, update Linear, and restore a clean repository

**Files:**
- Temporarily modified if markers were needed: `Virgo/views/GameplayView.swift`
- Temporarily modified if markers were needed: `Virgo/views/subviews/GameplaySheetMusicView.swift`
- No production file is committed by HPA-584.

**Interfaces:**
- Consumes: Tasks 1-5 evidence.
- Produces: one authoritative HPA-584 Linear result, optional narrowly scoped follow-up issue(s), correct HPA-583 dependency state, and a clean repository source diff.

- [ ] **Step 1: Save reusable disposable instrumentation, then revert it**

If temporary markers were added:

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

- [ ] **Step 2: Verify the repository is free of HPA-584 measurement changes**

Run:

```bash
git status --short
git diff --check
git diff -- \
  Virgo/views/GameplayView.swift \
  Virgo/views/subviews/GameplaySheetMusicView.swift
```

Expected: no HPA-584 source instrumentation remains and `git diff --check` exits 0.

Remove local compile-check DerivedData:

```bash
rm -rf ./DerivedData-HPA584
```

- [ ] **Step 3: Decide the eager-tree question before creating any row-laziness work**

Choose **Keep eager** when:

- first-mount cost is not dominated by chart-wide primitive construction for mostly off-screen content;
- 30+ seconds playback does not repeatedly rebuild expensive full-static content with visible impact;
- real manual scrolling is responsive or hitches are not attributable to the eager full-chart tree;
- credible live-memory evidence is reasonable on the tested supported hardware.

Choose **Create row-laziness follow-up** only when trace-backed evidence shows full-chart primitive construction is a dominant mount, scroll/frame, or memory problem.

Resize-only main-actor layout CPU does not change this binary eager-tree choice.

- [ ] **Step 4A: If row laziness is justified, create exactly one focused follow-up**

Create one Linear issue with this scope:

```markdown
## Objective

Reduce the trace-backed eager full-chart primitive-tree cost identified by HPA-584 using the smallest row-grouped lazy-rendering change.

## Required shape

- Pre-group immutable notation primitives by staff row.
- Render rows in a lazy vertical container.
- Keep horizontal geometry unchanged.
- Keep stable notation IDs unchanged.
- Preserve playhead alignment and auto-scroll.
- Preserve notation goldens/invariants and accessibility.
- The lazy container must own row-grouped primitives; wrapping the existing chart-wide `GameplayDrumNotationView` unchanged is not sufficient.

## Evidence

Link the HPA-584 result and quote only the trace/memory observations that justify this work.

## Non-goals

- Canvas tiling or custom drawing engine.
- Pagination or viewport cache.
- New rendering framework.
- Geometry redesign.
- Unrelated gameplay/view-model refactor.
```

Make this issue block HPA-583. Do not implement or further design it inside HPA-584.

- [ ] **Step 4B: If resize layout CPU is independently material, create one narrow existing-preparer follow-up**

Only when Task 5 found a real packing-changing width with visible/material main-thread layout CPU, create a separate narrow issue that references HPA-581 Task 7 and requires:

```text
post-ready timeline width relayout -> existing GameplayNotationPreparer
reuse current notation generation
latest width wins
no new worker framework or generation
```

Do not call this issue virtualization. Make it block HPA-583 while that rendering/performance change remains outstanding.

If Task 5 found no natural packing change or no material layout CPU, create no resize issue.

- [ ] **Step 5: Post the authoritative HPA-584 result comment**

Use the design spec's result template and fill every field with actual evidence, including:

- exact source/machine/OS/Xcode/Instruments identity;
- GUI gate status;
- physical iPad result or explicit unavailable limitation;
- notes / controls / measures / row width / **rendered row count**;
- viewport height / static content height;
- HPA-579 baseline values;
- Session A Time Profiler preparation/mount/playback results;
- Session B SwiftUI invalidation/manual-scroll results;
- Session C memory tool + exact metric/value;
- natural-resize classification;
- eager-tree decision;
- any row-laziness and/or resize follow-up identifiers;
- resulting HPA-583 blocker state.

- [ ] **Step 6: Close or leave HPA-584 blocked based on evidence completeness**

Close HPA-584 only when:

```text
interactive GUI gate passed
Time Profiler session complete
SwiftUI/manual-scroll session complete
credible memory session complete
natural resize result/limitation recorded
one eager-tree decision recorded
follow-up dependency state correct
temporary instrumentation removed
```

If credible live memory or real manual scrolling is missing, keep HPA-584 blocked/incomplete rather than waiving the gate.

- [ ] **Step 7: Final evidence review**

Check the design acceptance criteria line by line against the posted Linear result. Confirm there is no HPA-584 production source diff and no speculative renderer implementation.

**Checkpoint:** HPA-584 finishes as an evidence decision only. The next engineering action is HPA-583 when no rendering/performance follow-up remains, or a separately designed focused follow-up when the evidence requires one.
