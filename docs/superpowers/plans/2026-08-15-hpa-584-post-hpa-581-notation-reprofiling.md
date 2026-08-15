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

### Task 1: Establish source, references, and bounded GUI gate

- [ ] Record source/toolchain identity and compile-check Release.
- [ ] Read HPA-579/HPA-581 committed docs and tracked HPA-581 task-8 report as supporting evidence.
- [ ] Confirm current seams: detached initial notation prep; Equatable static notation; on-main post-ready width relayout.
- [ ] GUI attempt 1 requires visible interactive Virgo + symbolicated Time Profiler frames.
- [ ] If environment-blocked, verify unlock/input and retry once. Two environment failures use Task 6 GUI fallback; no headless substitute.

### Task 2: Calibrate 900 pt / 156 rows, then Time Profiler

- [ ] Add disposable preparation/geometry markers only if Instruments cannot expose identity/boundaries. Record elapsed, geometry/resolved width, rendered rows, notes/controls/measures, viewport/content/layout height.
- [ ] Any static `onAppear` marker is insertion/appearance only; it does not bracket descendant construction/compositor completion.
- [ ] Run one untimed calibration entry. Narrow real window until installed `cachedLayoutRowWidth = 900 pt` and `renderedRows = 156`; keep that size for comparable runs.
- [ ] Record row pitch 320 pt and geometry-only estimates:

```text
visibleRowCapacity ~= min(renderedRows, ceil(viewportHeight / 320) + 1)
offscreenRowFraction ~= 1 - visibleRowCapacity / renderedRows
```

Never convert geometry fraction into CPU share.

- [ ] Collect **two measured Time Profiler entries**; third only on material disagreement. Record preparation/stacks, worker-path check, loading responsiveness, eager-tree mount stacks, mount-boundary comparability.
- [ ] Continue 30+ seconds playback and record repeated expensive static-tree work if any.

### Task 3: Separate SwiftUI + real manual scrolling

- [ ] Separate SwiftUI session at pinned geometry.
- [ ] 30+ seconds playback/auto-scroll; record update/invalidation evidence.
- [ ] Manual distant scrolling; classify smooth / occasional minor hitch / repeated hitch.
- [ ] Correlate hitches with Time Profiler before blaming eager tree; missing invalidation detail is a limitation.

### Task 4: Separate memory session

- [ ] Allocations starts before gameplay; exact pre-gameplay/post-mount/playback-scroll metrics.
- [ ] Call a value peak only if the tool does.
- [ ] If Allocations unusable, Xcode memory gauge fallback with pre-gameplay/post-mount/highest **observed gauge reading**.
- [ ] Usable GUI + neither memory source credible => `Tooling-blocked — credible live-memory evidence unavailable`; keep HPA-584/HPA-583 blocked pending later evidence or explicit Linear scope change.

### Task 5: Natural wider resize + optional physical iPad

- [ ] Begin at 900/156 and widen through practical host widths. Record resolved width/row count; stop at first packing change; only call unavailable after widest practical width. No synthetic 3,000 pt.
- [ ] Packing change Time Profiler classification: layout CPU / SwiftUI full-tree rebuild / neither material.
- [ ] Material layout CPU follow-up reuses existing `GameplayNotationPreparer` + current generation; not virtualization.
- [ ] Material full-tree rebuild contributes to row-laziness evidence.
- [ ] Physical iPad when readily available; otherwise `iPad performance: unverified`, no device claim from Simulator, no hardware-only block.

### Task 6: Decision, Linear handoff, cleanup

- [ ] Save/revert scoped disposable instrumentation with `/tmp/hpa584-instrumentation.patch`; avoid broad stash so unrelated worktree state is not hidden.
- [ ] Verify no measurement source changes remain and `git diff --check` passes; remove local DerivedData.
- [ ] **Keep eager:** only with complete macOS CPU/SwiftUI/manual-scroll/credible memory evidence showing no material eager-tree problem. Without iPad run, scope result to macOS and mark iPad unverified.
- [ ] **Row-laziness follow-up:** only from positive evidence. Scope: row-group immutable primitives, lazy vertical row container, unchanged horizontal geometry/stable IDs, preserve playhead/auto-scroll/goldens/accessibility; wrapping current full-chart view unchanged insufficient. Block HPA-583.
- [ ] **Resize-only follow-up:** only from material layout CPU; reuse preparer/generation, not virtualization; block HPA-583 while outstanding.
- [ ] **GUI fallback:** after two environment/session GUI failures, close `Close without optimization — interactive evidence unavailable`; state mount/scroll/memory unverified, make no performance claim, create no speculative optimization, unblock HPA-583 by YAGNI.
- [ ] **Memory tooling blocker:** usable GUI + missing credible memory => `Tooling-blocked — credible live-memory evidence unavailable`; no GUI fallback; HPA-583 stays blocked.
- [ ] Post design result template; final state exactly one of Keep eager / row-laziness follow-up / GUI-environment no-optimization close / tooling-blocked memory.

**Checkpoint:** HPA-584 ends with an explicit decision/limitation and no production source diff.
