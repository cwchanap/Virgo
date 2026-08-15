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

- [ ] Record `git status -sb`, `git rev-parse HEAD`, `git log -1 --oneline`, `sw_vers`, hardware, Xcode, xctrace versions.
- [ ] Read HPA-579 spec, HPA-581 spec/plan, and tracked HPA-581 task-8 profile report as supporting evidence.
- [ ] Confirm current seams: initial timeline prep uses `GameplayNotationPreparer`/`Task.detached`; static notation is Equatable; post-ready width relayout still calls `cacheNotationLayout()` on main actor.
- [ ] Compile-check Release with `xcodebuild`; Product > Profile remains authoritative.
- [ ] GUI attempt 1: visible interactive Virgo window + symbolicated Time Profiler frames.
- [ ] If attempt 1 is environment-blocked, verify unlock/input and retry once. If attempt 2 is also environment-blocked, skip interactive measurement and use Task 6 GUI fallback. Do not substitute headless interaction.

### Task 2: Calibrate 900 pt / 156 rows, then Time Profiler

- [ ] If needed, add disposable preparation marker after `await vm.setupGameplay()` recording elapsed time, initial geometry width, `cachedLayoutRowWidth`, rendered rows, notes, controls, measures.
- [ ] If needed, attach a disposable static `.onAppear` marker recording `geometry.size.width/height`, static row count/content height/layout height, plus:

```text
rowPitch = 320 pt
visibleRowCapacity ~= min(renderedRows, ceil(viewportHeight / 320) + 1)
offscreenRowFraction ~= 1 - visibleRowCapacity / renderedRows
```

`onAppear` is insertion/appearance only; it does not bracket descendant construction. Geometry estimates are context only and are never multiplied by CPU time.

- [ ] Run one untimed calibration entry. Narrow the real window until installed `cachedLayoutRowWidth = 900 pt` and `renderedRows = 156`. Keep that size for direct HPA-579 comparison.
- [ ] If current source cannot reproduce 900/156, record that and do not claim direct comparison to 4,890.729 ms.
- [ ] Collect **two measured Time Profiler entries** at pinned geometry; add a third only on material disagreement. Record preparation duration/stacks, initial worker-path check, loading responsiveness, eager-tree mount stacks, comparability.
- [ ] Continue 30+ seconds playback and record whether expensive full-static-tree work repeats.

### Task 3: Separate SwiftUI + real manual scrolling

- [ ] Start separate SwiftUI Product > Profile session at pinned geometry.
- [ ] Run 30+ seconds playback/auto-scroll and record update/invalidation evidence.
- [ ] Manually scroll distant content; classify `smooth`, `occasional minor hitch`, or `repeated hitch`.
- [ ] Correlate repeated hitching with Time Profiler before blaming eager rendering. Missing invalidation detail remains an explicit limitation.

### Task 4: Separate memory session

- [ ] Start Allocations before gameplay; record exact pre-gameplay metric names/values.
- [ ] Record the same metrics after mount and after 30+ seconds playback/manual scroll; call a value peak only if the tool does.
- [ ] If Allocations is unusable, repeat with Xcode memory gauge and record pre-gameplay, post-mount, highest **observed gauge reading**.
- [ ] Usable GUI + no credible memory metric => `Tooling-blocked — credible live-memory evidence unavailable`; do not use GUI fallback; HPA-584/HPA-583 stay blocked pending later evidence or explicit scope change.

### Task 5: Natural wider resize + optional physical iPad

- [ ] Begin at 900 pt / 156 rows.
- [ ] Widen through practical host widths, recording gameplay/resolved width and rendered row count. Stop at first row-count change; only call unavailable after widest practical width. Never use synthetic 3,000 pt.
- [ ] For packing change, Time Profiler classification: `layout CPU dominates`, `SwiftUI full-tree rebuild dominates`, or `neither material`.
- [ ] Material layout CPU => follow-up reuses existing `GameplayNotationPreparer`, current notation generation, latest-width-wins semantics; not virtualization.
- [ ] Material full-tree rebuild => row-laziness evidence.
- [ ] Physical iPad when readily available: mount/playback/scroll/memory. Otherwise `iPad performance: unverified`; no Simulator performance claim and no hardware-only block.

### Task 6: Decision, Linear handoff, cleanup

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

Use the scoped patch rather than broad stash so unrelated worktree state is not hidden.

- [ ] Verify no instrumentation remains with `git status --short`, `git diff --check`, scoped source diff; remove `./DerivedData-HPA584`.
- [ ] **Keep eager** only with completed Time Profiler, SwiftUI/manual-scroll, and credible macOS memory evidence showing no material eager-tree problem. If no iPad run, scope result to macOS and mark iPad unverified.
- [ ] **Row-laziness follow-up** only from positive evidence that full-chart primitive construction dominates mount/scroll/frame/memory. Scope: row-group immutable primitives, lazy vertical row container, unchanged horizontal geometry/stable IDs, preserve playhead/auto-scroll/goldens/accessibility; wrapping current full-chart view unchanged is insufficient. Block HPA-583.
- [ ] **Resize-only follow-up** only from material layout CPU; reuse preparer/generation design, not virtualization; block HPA-583 while outstanding.
- [ ] **GUI fallback:** after two HPA-584 environment/session GUI failures, close `Close without optimization — interactive evidence unavailable`; state mount/scroll/memory unverified, make no performance claim, create no speculative issue, unblock HPA-583 by YAGNI.
- [ ] **Memory tooling blocker:** usable GUI + missing credible memory => `Tooling-blocked — credible live-memory evidence unavailable`; do not use GUI fallback; HPA-583 stays blocked.
- [ ] Post the design result template to HPA-584 and confirm final state is exactly one of: Keep eager; row-laziness follow-up; GUI-environment no-optimization close; tooling-blocked pending memory.

**Checkpoint:** HPA-584 ends with an explicit decision/limitation and no production source diff.
