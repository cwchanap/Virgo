# HPA-584 Post-HPA-581 Notation Re-profiling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to execute this plan task-by-task.

**Goal:** Re-profile Virgo's representative notation path after HPA-581 and make a bounded row-laziness decision without implementing virtualization in HPA-584.

**Architecture:** Calibrate Soukyuu MASTER to HPA-579's installed 900 pt / 156-row baseline, then run separate Time Profiler, SwiftUI/manual-scroll, and memory sessions. Geometry is exposure context, not CPU attribution. Resize layout CPU is separate from row laziness. Two GUI environment failures close without speculative optimization; usable GUI + missing memory is a tooling blocker.

## Constraints

- Fixed chart: Soukyuu MASTER / Expert (`Virgo/Fixtures/soukyuu_e_no_shouka/mas.dtx`), 2,870 notes, 0 controls, 156 measures.
- Direct HPA-579 comparison requires installed **900 pt resolved width / 156 rows**.
- Baseline: preparation median 267.857 ms; initial mount 4,890.729 ms.
- Eager unit: chart-wide static primitive tree, not mounted row views.
- Row pitch: 320 pt. Geometry estimates are never CPU-share estimates.
- Separate Time Profiler, SwiftUI, memory sessions.
- No benchmark/metrics/signpost framework, virtualization prototype, custom renderer, actor rewrite, or SwiftData ownership change.
- Physical iPad advisory; if absent, `iPad performance: unverified`.

### Task 1: Source + bounded GUI gate
- [ ] Record source/toolchain identity; compile-check Release.
- [ ] Read HPA-579 spec, HPA-581 committed spec/plan, tracked HPA-581 task-8 report as supporting evidence.
- [ ] Confirm detached initial notation prep, Equatable static notation, on-main post-ready width relayout.
- [ ] GUI attempt 1: visible interactive Virgo + symbolicated Time Profiler frames.
- [ ] One retry for environment/session block; two failures => Task 6 GUI fallback, no headless substitute.

### Task 2: Pin 900/156 + Time Profiler
- [ ] Disposable markers only if needed: preparation elapsed/geometry/resolved width/rows/notes/controls/measures; static viewport/content geometry.
- [ ] Static `onAppear` is insertion/appearance only; not descendant construction/compositor timing.
- [ ] One untimed calibration. Narrow real window until installed `cachedLayoutRowWidth = 900 pt` and `renderedRows = 156`.
- [ ] Record geometry-only context: rowPitch 320 pt; visibleRowCapacity ≈ min(renderedRows, ceil(viewportHeight / 320) + 1); offscreenRowFraction ≈ 1 - visibleRowCapacity/renderedRows. Never multiply by CPU time.
- [ ] **Two measured Time Profiler entries**; third only on material disagreement. Record worker-path check, preparation, eager-tree mount call paths, loading responsiveness, baseline comparability.
- [ ] Continue 30+ seconds playback; record repeated expensive static-tree work if any.

### Task 3: Separate SwiftUI/manual-scroll session
- [ ] 30+ seconds playback/auto-scroll at pinned geometry; record update/invalidation evidence.
- [ ] Manual distant scrolling; classify smooth / occasional minor hitch / repeated hitch.
- [ ] Correlate hitches with Time Profiler; missing invalidation detail remains limitation.

### Task 4: Separate memory session
- [ ] Allocations before gameplay; exact pre-gameplay/post-mount/playback-scroll metrics; peak only if tool reports it.
- [ ] Xcode memory gauge fallback if needed; highest **observed gauge reading**, not peak.
- [ ] Usable GUI + no credible memory metric => `Tooling-blocked — credible live-memory evidence unavailable`; keep HPA-584/HPA-583 blocked pending later evidence or explicit scope change.

### Task 5: Natural wider resize + optional physical iPad
- [ ] Begin 900/156; widen through practical widths, stop at first row-count change; only call unavailable after widest practical width. No synthetic 3,000 pt.
- [ ] Classify packing change: layout CPU / SwiftUI full-tree rebuild / neither material.
- [ ] Material layout CPU => existing `GameplayNotationPreparer` + current generation follow-up; not virtualization.
- [ ] Material full-tree rebuild => row-laziness evidence.
- [ ] Physical iPad if readily available; otherwise unverified, no Simulator device-performance claim.

### Task 6: Decision + cleanup
- [ ] Save/revert scoped instrumentation to `/tmp/hpa584-instrumentation.patch`; avoid broad stash so unrelated worktree state is not hidden.
- [ ] Verify no measurement source changes; `git diff --check`; remove local DerivedData.
- [ ] **Keep eager:** only with complete macOS CPU/SwiftUI/manual-scroll/credible memory evidence. No iPad => macOS-scoped result, iPad unverified.
- [ ] **Row-laziness follow-up:** only positive evidence; row-group immutable primitives + lazy vertical row container; preserve geometry/IDs/playhead/auto-scroll/goldens/a11y; block HPA-583.
- [ ] **Resize-only follow-up:** only material layout CPU; reuse preparer/generation; block HPA-583.
- [ ] **GUI fallback:** after two environment/session GUI failures, close without optimization; state mount/scroll/memory unverified, no performance claim, no speculative issue, unblock HPA-583 by YAGNI.
- [ ] **Memory tooling blocker:** usable GUI + missing credible memory => tooling-blocked; no GUI fallback; HPA-583 stays blocked.
- [ ] Post HPA-584 result; final state exactly one of Keep eager / row-laziness follow-up / GUI-environment close / tooling-blocked memory.

**Checkpoint:** HPA-584 ends with explicit decision/limitation and no production source diff.
