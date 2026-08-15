# HPA-584 Post-HPA-581 Notation Re-profiling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to execute this plan task-by-task.

**Goal:** Re-profile Virgo's representative notation path after HPA-581 and make a bounded row-laziness decision without implementing virtualization in HPA-584.

**Architecture:** Calibrate Soukyuu MASTER to HPA-579's installed 900 pt / 156-row baseline, then run separate Time Profiler, SwiftUI/manual-scroll, and memory sessions. Geometry is exposure context, not CPU attribution. Resize layout CPU is separate from row laziness. Two GUI environment failures close without speculative optimization; usable GUI + missing memory is a tooling blocker instead.

## Global constraints

- Fixed chart: `Virgo/Fixtures/soukyuu_e_no_shouka/mas.dtx`, MASTER / Expert, 2,870 notes, 0 controls, 156 measures.
- Direct HPA-579 comparison requires installed **900 pt resolved width / 156 rows**.
- Baseline: preparation median 267.857 ms; initial mount 4,890.729 ms.
- Eager unit is the chart-wide static primitive tree, not mounted row views.
- Row pitch is 320 pt; geometry estimates never become CPU-share estimates.
- Separate Time Profiler, SwiftUI, and memory sessions.
- No benchmark/metrics/signpost framework, virtualization prototype, custom renderer, actor rewrite, or SwiftData ownership change.
- Physical iPad is advisory; absent device => `iPad performance: unverified`.

---

### Task 1: Source + bounded GUI gate

- [ ] Record exact commit, worktree, OS/hardware/Xcode/xctrace identity.
- [ ] Read HPA-579 spec, HPA-581 committed spec/plan, and tracked HPA-581 task-8 profile report as supporting evidence.
- [ ] Confirm current seams: detached initial notation prep; Equatable static notation; on-main post-ready width relayout.
- [ ] Compile-check Release; Product > Profile remains authoritative.
- [ ] GUI attempt 1: require visible interactive Virgo + symbolicated Time Profiler frames.
- [ ] If environment-blocked, verify unlock/input and retry once. If attempt 2 also fails for environment/session reasons, skip interactive tasks and use Task 6 GUI fallback. No headless substitute.

### Task 2: Pin 900/156 + Time Profiler

- [ ] Add disposable markers only if needed. Preparation marker records elapsed, gameplay geometry width, `cachedLayoutRowWidth`, rendered rows, notes/controls/measures.
- [ ] Optional static marker records viewport height, row count, content/layout height, visible-row-capacity/off-screen-row-fraction. Its `onAppear` is insertion/appearance only, not descendant-construction/compositor timing.
- [ ] Run one untimed calibration entry and narrow real window until installed `cachedLayoutRowWidth = 900 pt` and `renderedRows = 156`. Leave that size for direct comparison.
- [ ] Record:

```text
rowPitch = 320 pt
visibleRowCapacity ~= min(renderedRows, ceil(viewportHeight / 320) + 1)
offscreenRowFraction ~= 1 - visibleRowCapacity / renderedRows
```

Do not multiply geometry fraction by CPU time.

- [ ] Collect **two measured Time Profiler entries**; third only if attribution/visible behavior materially disagrees. Record worker-path check, preparation, mount eager-tree call paths, loading responsiveness, and baseline comparability.
- [ ] Continue 30+ seconds playback and record repeated expensive static-tree work if any.

### Task 3: Separate SwiftUI/manual-scroll session

- [ ] Start SwiftUI Product > Profile at pinned geometry.
- [ ] Run 30+ seconds playback/auto-scroll and record update/invalidation evidence.
- [ ] Manually scroll distant content; classify `smooth`, `occasional minor hitch`, or `repeated hitch`.
- [ ] Correlate hitches with Task 2 Time Profiler before blaming eager rendering. Missing detailed invalidation data is an explicit limitation.

### Task 4: Separate memory session

- [ ] Start Allocations before gameplay; record exact pre-gameplay/post-mount/playback-scroll metrics.
- [ ] Call a value peak only if the tool does.
- [ ] If Allocations is unusable, repeat with Xcode memory gauge; record pre-gameplay/post-mount/highest **observed gauge reading**.
- [ ] Usable GUI + no credible metric from either tool => `Tooling-blocked — credible live-memory evidence unavailable`; do not use GUI fallback; keep HPA-584/HPA-583 blocked pending later evidence or explicit scope change.

### Task 5: Natural wider resize + optional physical iPad

- [ ] Begin at 900/156 and widen through practical widths, recording geometry/resolved width/row count. Stop at first packing change; only call unavailable after widest practical host width. No synthetic 3,000 pt.
- [ ] Packing change Time Profiler classification: `layout CPU dominates`, `SwiftUI full-tree rebuild dominates`, or `neither material`.
- [ ] Material layout CPU => any follow-up reuses existing `GameplayNotationPreparer` + current generation; not virtualization.
- [ ] Material full-tree rebuild => row-laziness evidence.
- [ ] Physical iPad when readily available; otherwise record unverified and make no device claim from Simulator.

### Task 6: Decision + cleanup

- [ ] Save/revert scoped disposable instrumentation:

```bash
git diff -- \
  Virgo/views/GameplayView.swift \
  Virgo/views/subviews/GameplaySheetMusicView.swift \
  > /tmp/hpa584-instrumentation.patch

git restore -- \
  Virgo/views/GameplayView.swift \
  Virgo/views/subviews/GameplaySheetMusicView.swift
```

Keep the scoped patch rather than broad stash so unrelated worktree state is not hidden.

- [ ] Verify no measurement source changes remain; `git diff --check`; remove local DerivedData.
- [ ] **Keep eager:** only with complete macOS CPU/SwiftUI/manual-scroll/credible memory evidence showing no material eager-tree problem. No iPad run => result scoped to macOS, iPad unverified.
- [ ] **Row-laziness follow-up:** only from positive evidence. Scope: row-group immutable primitives, lazy vertical row container, unchanged horizontal geometry/stable IDs, preserve playhead/auto-scroll/goldens/accessibility; wrapping current full-chart view unchanged is insufficient. Block HPA-583.
- [ ] **Resize-only follow-up:** only from material layout CPU; reuse preparer/generation; not virtualization; block HPA-583 while outstanding.
- [ ] **GUI fallback:** after two HPA-584 environment/session GUI failures, close `Close without optimization — interactive evidence unavailable`; state mount/scroll/memory unverified, make no performance claim, create no speculative optimization, unblock HPA-583 by YAGNI.
- [ ] **Memory tooling blocker:** usable GUI + missing credible memory => `Tooling-blocked — credible live-memory evidence unavailable`; no GUI fallback; HPA-583 remains blocked.
- [ ] Post HPA-584 result and confirm final state is exactly one of: Keep eager / row-laziness follow-up / GUI-environment no-optimization close / tooling-blocked memory.

**Checkpoint:** HPA-584 ends with an explicit decision/limitation and no production source diff.
