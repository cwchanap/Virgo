# HPA-584: Post-HPA-581 Notation Re-profiling and Row-Laziness Decision

**Date:** 2026-08-15  
**Status:** Proposed

## Context

HPA-584 asks whether Virgo's eager full-chart static notation tree still causes enough real mount, scrolling, or memory cost after HPA-581 to justify row-grouped lazy rendering.

HPA-579's Release baseline on Soukyuu MASTER (`mas.dtx`) was 2,870 notes, 0 controls, 156 measures, **900 pt** resolved row width, **156 rows**, preparation median **267.857 ms**, and initial mount **4,890.729 ms**. Manual scrolling and reliable live-memory evidence were unavailable.

HPA-581 moved initial timeline notation layout through `GameplayNotationPreparer` on a detached worker and isolated static notation behind `GameplayStaticNotationView(...).equatable()`. Its tracked task-8 profile report is supporting evidence for the worker path and the locked-GUI limitation; committed HPA-581 specs/plans remain authoritative.

## Current eager mechanism

Gameplay mounts one chart-wide static `ZStack`; `GameplayDrumNotationView` iterates full-chart primitive collections. Rows are layout/anchor data, not existing row views.

HPA-584 therefore combines total eager-tree CPU/call paths, deterministic viewport/content geometry, real scrolling, and live memory. Geometry is **not** CPU attribution: primitive density differs per row, so never multiply an off-screen row fraction by total CPU time.

## Non-goals

No production virtualization, benchmark/metrics infrastructure, custom renderer, pagination, viewport cache, actor rewrite, SwiftData ownership change, synthetic resize width, or unrelated HPA-583 cleanup.

## Fixed comparison geometry

`updateRowWidth(_:)` resolves `max(900, width)`. Direct HPA-579 comparison is valid only when current installed layout also reports **900 pt / 156 rows**.

Before comparable timing:

1. one untimed calibration entry;
2. record gameplay geometry width, `cachedLayoutRowWidth`, rendered rows;
3. narrow real window until `cachedLayoutRowWidth = 900 pt` and `renderedRows = 156`;
4. keep that size for measured baseline runs.

If current source cannot reproduce 900/156, do not claim direct comparison to 4,890.729 ms.

Record viewport width/height, resolved row width, rendered rows, static content height/layout total height, row pitch **320 pt**.

For context only:

```text
visibleRowCapacity ~= min(renderedRows, ceil(viewportHeight / 320) + 1)
offscreenRowFraction ~= 1 - visibleRowCapacity / renderedRows
```

Do not convert the fraction into CPU cost.

## Measurement sessions

### A. Time Profiler

Pinned 900/156 geometry; one warm-up/calibration + **two measured entries**; third only on material disagreement.

Confirm initial `NotationLayoutEngine.layout` remains off-main. Time Profiler owns mount attribution through actual eager static bodies/primitive collections. Any disposable `onAppear` marker is **subtree insertion/appearance only**, not descendant-construction/compositor timing.

Continue 30+ seconds playback. Compare HPA-579's mount only when geometry and boundary are materially comparable.

### B. SwiftUI/manual scroll

Separate SwiftUI session at pinned geometry. Play 30+ seconds, auto-scroll, manually scroll distant content, classify smooth / occasional minor hitch / repeated hitch, record exact invalidation/update evidence. Missing detail is a limitation, not success evidence.

### C. Live memory

Separate Allocations session starting before gameplay. Record exact pre-gameplay/post-mount/playback-scroll metrics; use "peak" only if the tool does. Xcode memory-gauge fallback is allowed but must label highest observed reading accurately.

Credible macOS live memory is required for evidence-backed Keep eager.

## Natural resize

Start **900 pt / 156 rows**, widen through practical host widths, stop at first real row-count change. Only after widest practical host width may the result say no packing-changing width was available. Never use synthetic 3,000 pt evidence.

Packing-change classifications:

1. **Layout CPU dominates** — existing main-actor layout; follow-up, if material, reuses `GameplayNotationPreparer` + current generation and is not virtualization.
2. **Full SwiftUI primitive-tree rebuild dominates** — row-laziness evidence.
3. **Neither material** — no follow-up.

## Physical iPad policy

Advisory, not blocking. If available, repeat mount/playback/scroll/memory. If absent, record `iPad performance: unverified`; no Simulator device-performance claim. Keep eager without device profiling is scoped to macOS hardware measured.

## Outcomes

### Keep eager

Requires complete macOS CPU/SwiftUI/manual-scroll/live-memory evidence showing no material eager-tree problem. Off-screen geometry alone does not justify laziness.

### Row-laziness follow-up

Only positive evidence that full-chart primitive construction dominates mount/scroll/frame/memory. Scope: row-group immutable primitives, lazy vertical row container, unchanged horizontal geometry/stable IDs, preserve playhead/auto-scroll/goldens/accessibility. Wrapping current full-chart view unchanged is insufficient.

### GUI environment fallback

GUI attempt 1 blocked by lock/shield/input/session => verify environment and retry once. Attempt 2 also environment-blocked => close:

```text
Close without optimization — interactive evidence unavailable
```

Not Keep eager. State mount/scroll/memory unverified, create no speculative optimization, unblock HPA-583 by YAGNI.

### Memory tooling blocker

GUI usable but Allocations + Xcode gauge both fail to produce credible named macOS memory evidence =>

```text
Tooling-blocked — credible live-memory evidence unavailable
```

No GUI fallback; HPA-584/HPA-583 stay blocked pending later evidence or explicit scope change.

### Resize-only follow-up

Orthogonal; reuse existing preparer/generation design and block HPA-583 while outstanding.

## Temporary instrumentation

Prefer Instruments. Reuse `Logger.info` / `ContinuousClock`; no permanent timing layer. `onAppear` insertion-only. Keep scoped `/tmp/hpa584-instrumentation.patch` rather than broad stash so unrelated worktree state is not hidden. Commit no profiler artifacts or temporary source instrumentation.

## Acceptance criteria

- [ ] Fixed Soukyuu MASTER + exact source/toolchain identity.
- [ ] Direct HPA-579 comparison uses installed **900 pt / 156 rows**.
- [ ] Viewport/content geometry + 320 pt row pitch recorded; no fabricated CPU share.
- [ ] Separate Time Profiler, SwiftUI, memory sessions.
- [ ] One warm-up + two measured entries; third only on material disagreement.
- [ ] `onAppear` insertion-only; Time Profiler owns mount attribution.
- [ ] 30+ seconds playback + real manual scrolling for evidence-backed decision.
- [ ] Credible macOS live memory for Keep eager.
- [ ] Resize widens from 900/156 to first real packing change or widest practical width.
- [ ] Resize layout CPU separate from row-laziness evidence.
- [ ] iPad when available; otherwise explicit unverified limitation.
- [ ] Two GUI environment failures close without speculative optimization/performance claim.
- [ ] Usable GUI + missing memory => Tooling-blocked, not GUI fallback.
- [ ] No production virtualization/benchmark/custom-renderer work.
- [ ] Tracked HPA-581 report supporting only; committed specs/plans own architecture.
- [ ] Temporary instrumentation/profiler artifacts removed before close.
