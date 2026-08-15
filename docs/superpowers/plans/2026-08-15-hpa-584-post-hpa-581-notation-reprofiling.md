# HPA-584 Post-HPA-581 Notation Re-profiling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to execute this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Re-profile Virgo's representative notation path after HPA-581 and make a bounded, evidence-backed row-laziness decision without implementing virtualization in HPA-584.

**Architecture:** Reuse HPA-579's Soukyuu MASTER baseline, calibrate the real window until the installed layout reproduces 900 pt / 156 rows, then run separate Time Profiler, SwiftUI, and memory sessions. Treat geometry as exposure context rather than CPU attribution, classify resize layout CPU separately from eager-tree cost, and use a bounded no-optimization fallback only when two HPA-584 GUI attempts are environment-blocked.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, Xcode Product > Profile, Instruments Time Profiler / SwiftUI / Allocations, Xcode memory gauge, unified logging, `ContinuousClock`, Linear.

## Global Constraints

- Follow `docs/superpowers/specs/2026-08-15-hpa-584-post-hpa-581-notation-reprofiling-design.md`.
- HPA-584 is measurement/decision work only; do not implement row laziness or resize optimization here.
- Fixed chart: Soukyuu MASTER / Expert (`Virgo/Fixtures/soukyuu_e_no_shouka/mas.dtx`), 2,870 notes, 0 controls, 156 measures.
- Direct HPA-579 comparison requires installed **900 pt resolved row width / 156 rendered rows**.
- HPA-579 baseline: preparation median 267.857 ms (264.074-269.534 ms), initial mount 4,890.729 ms.
- The eager unit is the chart-wide static primitive tree, not mounted row views.
- Record rendered row count separately from measure count.
- Row pitch is 320 pt (`rowHeight` 280 + `rowVerticalSpacing` 40).
- Geometry exposure is context only; never multiply off-screen row fraction by CPU time.
- Time Profiler, SwiftUI, and memory use separate sessions.
- Prefer Instruments before temporary `Logger.info` / `ContinuousClock` markers; add no timing framework/signpost layer.
- No benchmark target, metrics service, CI performance gate, custom renderer, pagination, viewport cache, actor rewrite, or SwiftData ownership change.
- Resize layout CPU is separate from row laziness; any justified resize follow-up reuses existing `GameplayNotationPreparer` + notation generation.
- Physical iPad evidence is advisory. If absent, report iPad performance unverified; Simulator data is not device performance.
- Keep profiler artifacts and temporary instrumentation out of git.

---

## File Structure

**Planning:**
- `docs/superpowers/specs/2026-08-15-hpa-584-post-hpa-581-notation-reprofiling-design.md`
- `docs/superpowers/plans/2026-08-15-hpa-584-post-hpa-581-notation-reprofiling.md`

**References:**
- `docs/superpowers/specs/2026-08-10-hpa-579-representative-performance-profiling-design.md`
- `docs/superpowers/specs/2026-08-12-hpa-581-off-main-notation-preparation-design.md`
- `docs/superpowers/plans/2026-08-12-hpa-581-off-main-notation-preparation.md`
- `.superpowers/sdd/2026-08-12-hpa-581-off-main-notation-preparation/task-8-profile-report.md` — tracked supporting evidence only.

**Temporary instrumentation, only if needed:**
- `Virgo/views/GameplayView.swift`
- `Virgo/views/subviews/GameplaySheetMusicView.swift`

**Observed seams:**
- `Virgo/viewmodels/GameplayViewModel.swift`
- `Virgo/viewmodels/GameplayViewModel+Notation.swift`
- `Virgo/layout/GameplayNotationPreparation.swift`
- `Virgo/views/subviews/GameplaySheetMusicView.swift`
- `Virgo/views/GameplayView.swift`
- `Virgo/layout/gameplay.swift`

---

### Task 1: Establish source, references, and the bounded GUI gate

**Produces:** exact source/toolchain identity plus a usable Release GUI or a bounded environment-blocked outcome.

- [ ] **Step 1: Confirm source/worktree**

```bash
git status -sb
git rev-parse HEAD
git log -1 --oneline
```

Use a clean worktree if unrelated edits exist in the temporary-instrumentation files.

- [ ] **Step 2: Read HPA-579/HPA-581 material and confirm current seams**

Confirm:

```text
initial timeline notation -> GameplayNotationPreparer on Task.detached
static notation -> GameplayStaticNotationView(...).equatable()
post-ready width relayout -> cacheNotationLayout() / NotationLayoutEngine on @MainActor
```

The tracked HPA-581 task-8 report is supporting evidence; requirements come from committed spec/plan docs.

- [ ] **Step 3: Record environment**

```bash
sw_vers
system_profiler SPHardwareDataType | egrep 'Model Name|Model Identifier|Chip|Memory'
xcodebuild -version
xcrun xctrace version
```

- [ ] **Step 4: Compile-check Release**

```bash
xcodebuild \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath ./DerivedData-HPA584 \
  build
```

Expected: `** BUILD SUCCEEDED **`. Product > Profile remains authoritative for measurement.

- [ ] **Step 5: GUI attempt 1**

Use Xcode Product > Profile / Time Profiler. Require a visible interactive Virgo window and symbolicated Virgo frames.

- [ ] **Step 6: Retry one environment-blocked GUI attempt**

If attempt 1 fails because of lock/shield/input/session state, verify the session is unlocked/input works and make one more HPA-584 Product > Profile attempt.

If attempt 2 also fails for environment/session reasons, skip Tasks 2-5 and use Task 6's **Close without optimization — interactive evidence unavailable** path. Do not substitute a headless run.

---

### Task 2: Calibrate 900 pt / 156 rows, then run Time Profiler

**Produces:** comparable baseline geometry plus preparation/mount/playback CPU evidence.

- [ ] **Step 1: Add disposable preparation metadata only if needed**

After the early returns in `GameplayView.prepareGameplay(initialRowWidth:)`:

```swift
let hpa584Clock = ContinuousClock()
let hpa584PrepareStart = hpa584Clock.now
```

Immediately after `await vm.setupGameplay()`:

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

- [ ] **Step 2: Add disposable viewport/static marker only if needed**

Where `staticInput` and `geometry` are available:

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

`onAppear` is subtree insertion/appearance evidence only. It does not bracket descendant construction and is not compositor-complete timing.

- [ ] **Step 3: Run one untimed calibration entry**

Record:

```text
gameplay geometry width
cachedLayoutRowWidth
rendered row count
viewport height
static content height / layout total height
```

Narrow the real window until:

```text
cachedLayoutRowWidth = 900 pt
renderedRows = 156
```

Leave the window there for comparable measured entries. If current source cannot reproduce 900/156, do not claim a direct HPA-579 mount comparison.

- [ ] **Step 4: Record geometry exposure**

```text
rowPitch = 320 pt
visibleRowCapacity ~= min(renderedRows, ceil(viewportHeight / 320) + 1)
offscreenRowFraction ~= 1 - visibleRowCapacity / renderedRows
```

These are estimates only; do not multiply them by CPU time.

- [ ] **Step 5: Run Time Profiler**

After calibration, collect **two measured gameplay entries**. Add a third only if attribution or visible behavior differs materially.

For each, record preparation duration/stacks, initial worker-path confirmation for `NotationLayoutEngine.layout`, loading responsiveness, first-mount eager-tree stacks, and whether the HPA-579 mount boundary is comparable.

- [ ] **Step 6: Continue 30+ seconds playback**

Let auto-scroll cross rows and record whether expensive full-static-tree work repeats. Outer playhead/currentRow/isPlaying paths alone are not eager-tree rebuild evidence.

---

### Task 3: Separate SwiftUI session + real manual scrolling

- [ ] **Step 1:** Start Product > Profile with the SwiftUI template at the pinned window size.
- [ ] **Step 2:** Run 30+ seconds playback/auto-scroll and record update/invalidation evidence.
- [ ] **Step 3:** Manually scroll distant vertical content (and horizontal content when real geometry permits), then classify: `smooth`, `occasional minor hitch`, or `repeated hitch`.
- [ ] **Step 4:** For repeated hitching, correlate with Task 2 call paths before blaming the eager tree. Missing detailed SwiftUI invalidation data remains an explicit limitation.

---

### Task 4: Separate memory session

- [ ] **Step 1:** Start Allocations before gameplay at the pinned window size; record exact pre-gameplay metric names/values.
- [ ] **Step 2:** Record the same metrics after full mount.
- [ ] **Step 3:** Run 30+ seconds playback/manual scroll and record the live value/range; call a value peak only if the tool does.
- [ ] **Step 4:** If Allocations is unusable, repeat with the Xcode memory gauge and record pre-gameplay, post-mount, and highest **observed gauge reading**.
- [ ] **Step 5:** If the GUI is usable but neither tool yields credible named macOS live-memory evidence, report `Tooling-blocked — credible live-memory evidence unavailable`; HPA-584/HPA-583 remain blocked pending later evidence or explicit Linear scope change.

---

### Task 5: Natural wider resize + optional physical iPad

- [ ] **Step 1:** Begin at the calibrated 900 pt / 156-row state.
- [ ] **Step 2:** Widen through practical host widths, recording gameplay/resolved width and rendered row count. Stop at the first row-count change; only call it unavailable after reaching the widest practical host width. Never use the synthetic 3,000 pt probe.
- [ ] **Step 3:** For a packing change, run a dedicated Time Profiler capture and classify `layout CPU dominates`, `SwiftUI full-tree rebuild dominates`, or `neither material`.
- [ ] **Step 4:** If layout CPU dominates materially, any follow-up reuses `GameplayNotationPreparer`, current notation generation, and latest-width-wins semantics. Do not treat it as virtualization.
- [ ] **Step 5:** If full-tree rebuild dominates materially, carry that into the row-laziness decision.
- [ ] **Step 6:** If a physical iPad is readily available, repeat mount/playback/scroll/memory and record device/OS. Otherwise record `iPad performance: unverified`; do not block solely on hardware availability or use Simulator numbers as device performance.

---

### Task 6: Decision, Linear handoff, cleanup

- [ ] **Step 1: Save/revert scoped disposable instrumentation**

```bash
git diff -- \
  Virgo/views/GameplayView.swift \
  Virgo/views/subviews/GameplaySheetMusicView.swift \
  > /tmp/hpa584-instrumentation.patch

git restore -- \
  Virgo/views/GameplayView.swift \
  Virgo/views/subviews/GameplaySheetMusicView.swift
```

Use the scoped patch rather than broad `git stash` so unrelated worktree changes are not hidden.

- [ ] **Step 2: Verify cleanup**

```bash
git status --short
git diff --check
git diff -- \
  Virgo/views/GameplayView.swift \
  Virgo/views/subviews/GameplaySheetMusicView.swift
rm -rf ./DerivedData-HPA584
```

Expected: no HPA-584 measurement source changes remain and `git diff --check` exits 0.

- [ ] **Step 3A: Evidence-backed Keep eager**

Requires completed Time Profiler, SwiftUI/manual-scroll, and credible macOS memory evidence showing no material eager-tree problem. If no physical iPad was tested, scope the result to macOS and say iPad performance is unverified.

- [ ] **Step 3B: Row-laziness follow-up only from positive evidence**

Create exactly one issue if full-chart primitive construction is a dominant mount/scroll/frame/memory problem. Required shape: row-group immutable primitives, lazy vertical row container, unchanged horizontal geometry/stable IDs, preserve playhead/auto-scroll/goldens/accessibility. Wrapping the existing full-chart view unchanged is insufficient. Make it block HPA-583.

- [ ] **Step 3C: Resize-only follow-up only from material layout CPU evidence**

Reuse the existing preparer/generation design; do not call it virtualization. Make it block HPA-583 while outstanding.

- [ ] **Step 3D: Bounded GUI fallback**

After two HPA-584 GUI attempts fail for environment/session reasons, close as `Close without optimization — interactive evidence unavailable`; state mount/scroll/memory are unverified, make no performance claim, create no speculative optimization issue, and unblock HPA-583 by YAGNI.

- [ ] **Step 3E: Memory tooling blocker**

Usable GUI + missing credible memory => `Tooling-blocked — credible live-memory evidence unavailable`; do not use the GUI fallback and keep HPA-583 blocked.

- [ ] **Step 4:** Post the design spec's result template to HPA-584 with actual evidence/limitations.
- [ ] **Step 5:** Confirm final state is exactly one of: evidence-backed Keep eager; trace-backed row-laziness follow-up; bounded GUI-environment close; or tooling-blocked pending memory evidence.

**Checkpoint:** HPA-584 ends with an explicit decision/limitation and no production source diff.
