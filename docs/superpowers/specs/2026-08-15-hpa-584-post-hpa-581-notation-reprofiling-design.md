# HPA-584: Post-HPA-581 Notation Re-profiling and Row-Laziness Decision

**Date:** 2026-08-15  
**Status:** Proposed

## Context

HPA-584 is the Phase D evidence closeout for Virgo's notation-rendering performance work. It answers one narrow question after HPA-581: **does eager construction of the full-chart static notation tree still create enough real mount, scrolling, or memory cost to justify restructuring that tree by staff row and mounting rows lazily?**

HPA-579's Release macOS baseline on Soukyuu MASTER (`Virgo/Fixtures/soukyuu_e_no_shouka/mas.dtx`) was: 2,870 notes, 0 controls, 156 measures, **900 pt** resolved row width, **156 rows**, preparation median **267.857 ms** (264.074-269.534 ms), and initial mount **4,890.729 ms**. Manual scrolling and reliable peak-live-memory evidence were unavailable.

HPA-581 moved initial timeline notation layout through `GameplayNotationPreparer` on a detached worker and isolated static notation behind `GameplayStaticNotationView(input:).equatable()`.

The tracked HPA-581 final profiling report records the worker-path handoff and locked-GUI limitation:

- `.superpowers/sdd/2026-08-12-hpa-581-off-main-notation-preparation/task-8-profile-report.md`

The broader `.superpowers/` pattern is ignored for new local files, but this report itself is tracked. It is supporting evidence only; committed HPA-581 specs/plans own architecture.

## Current eager mechanism

Production mounts one chart-wide static `ZStack`; `GameplayDrumNotationView` builds full-chart primitive `ForEach` collections. Rows are layout/anchor data, not existing mounted row views.

HPA-584 therefore combines total eager-tree CPU/call paths, deterministic viewport/content geometry, real scrolling behavior, and live memory. Geometry is context, not CPU attribution. Primitive density differs by row, so **do not multiply off-screen row fraction by total static-tree CPU time**.

## Goal

Use the same **900 pt / 156-row** geometry for direct HPA-579 comparison, then decide:

- **Keep eager**; or
- **Create one row-laziness follow-up** only from positive evidence.

A bounded no-optimization fallback exists only for repeated GUI environment/session failure. Usable GUI + missing memory evidence is a separate tooling blocker. Resize layout CPU is classified separately from row-laziness evidence.

## Non-goals

No production virtualization, benchmark/metrics infrastructure, custom renderer, pagination, viewport cache, actor rewrite, SwiftData ownership change, synthetic resize width, or unrelated HPA-583 cleanup.

## Measurement shape

1. **Time Profiler** — preparation, first mount, 30+ seconds playback.
2. **SwiftUI** — playback, invalidation/update evidence, real manual scrolling.
3. **Allocations** or separately named Xcode memory-gauge fallback — start before gameplay.
4. **Time Profiler resize capture** — only after natural widening changes row packing.

## Fixed comparison geometry

`updateRowWidth(_:)` resolves `max(900, width)`, so HPA-579's 900/156 comparison is valid only when the current installed layout also reports 900/156.

Before comparable timing:

1. run one untimed calibration entry;
2. record gameplay geometry width, `cachedLayoutRowWidth`, rendered row count;
3. narrow the real window until `cachedLayoutRowWidth = 900 pt` and `renderedRows = 156`;
4. keep that size for measured baseline runs.

If current source cannot reproduce 900/156, do not claim a direct 4,890.729 ms mount comparison.

### Geometry exposure

Record viewport width/height, resolved row width, rendered rows, static content height/layout total height, and row pitch **320 pt**.

For context only:

```text
visibleRowCapacity ~= min(renderedRows, ceil(viewportHeight / 320) + 1)
offscreenRowFraction ~= 1 - visibleRowCapacity / renderedRows
```

Do not convert the fraction into CPU cost.

## Environment outcomes

### Evidence-backed GUI path

A usable unlocked GUI is required for Keep eager / row-laziness decisions.

If HPA-584 GUI attempt 1 fails because of lock/shield/input/session state, verify the environment and retry once. If attempt 2 also fails for environment/session reasons, close:

```text
Close without optimization — interactive evidence unavailable
```

This is **not** Keep eager. State mount/scroll/memory remain unverified, create no speculative optimization, and unblock HPA-583 by YAGNI because no evidence justifies rendering architecture work.

### Memory tooling blocker

If GUI works but neither Allocations nor Xcode memory gauge yields credible named macOS live-memory evidence:

```text
Tooling-blocked — credible live-memory evidence unavailable
```

Do not use the GUI fallback. HPA-584/HPA-583 remain blocked pending later evidence or explicit Linear scope change.

## Session A — Time Profiler

At pinned 900/156 geometry, use one warm-up/calibration + **two measured entries**. Add a third only on material disagreement in attribution/visible behavior.

Confirm initial timeline `NotationLayoutEngine.layout` remains off-main. Attribute mount through actual eager static bodies/primitive collections. Any disposable `onAppear` marker is **subtree insertion/appearance only**; it does not bracket descendant construction or compositor completion.

Continue 30+ seconds playback. Compare the old 4,890.729 ms mount only when chart, 900/156 geometry, and boundary are materially comparable.

## Session B — SwiftUI/manual scroll

Run separately at pinned geometry. Play 30+ seconds, let auto-scroll cross rows, manually scroll distant content, classify smooth / occasional minor hitch / repeated hitch, and record exact invalidation/update evidence. Missing detailed invalidation data is a limitation, not success evidence.

## Session C — live memory

Run Allocations before gameplay at pinned geometry. Record exact pre-gameplay, post-mount, and playback/scroll metric names/values. Use "peak" only if the tool reports it. If needed, use Xcode memory gauge and label the highest observed reading accurately.

Credible macOS live memory is required for evidence-backed Keep eager.

## Natural resize

Start at **900 pt / 156 rows**, then widen through practical widths. Record resolved width and rendered row count and stop at the first real packing change. Only after reaching the widest practical host width may the result say no packing-changing width was available. Never use synthetic 3,000 pt evidence.

For a packing change:

1. **Layout CPU dominates** — existing main-actor layout path; any follow-up reuses `GameplayNotationPreparer` + current generation and is not virtualization.
2. **Full SwiftUI primitive-tree rebuild dominates** — contributes to row-laziness evidence.
3. **Neither material** — no follow-up.

## Physical iPad policy

Physical iPad evidence is advisory, not blocking for this hobby project. If available, repeat mount/playback/scroll/memory. If absent, record `iPad performance: unverified`; do not claim device performance from Simulator data. Keep eager without an iPad run is scoped to measured macOS hardware.

## Decision rubric

### Keep eager

Requires completed macOS CPU/SwiftUI/manual-scroll/live-memory evidence showing no material eager-tree problem. Off-screen geometry alone does not justify laziness.

### Row-laziness follow-up

Only from positive evidence that full-chart primitive construction dominates mount/scroll/frame/memory. Scope: row-group immutable primitives, lazy vertical row container, unchanged horizontal geometry/stable IDs, preserve playhead/auto-scroll/goldens/accessibility. Wrapping the existing full-chart view unchanged is insufficient.

### Close without optimization — interactive evidence unavailable

Only after two HPA-584 GUI environment/session failures. Not Keep eager; HPA-583 unblocks.

### Tooling-blocked — credible live-memory evidence unavailable

GUI usable, memory evidence unavailable. Not a row-laziness decision; HPA-583 remains blocked.

### Resize-only layout CPU follow-up

Orthogonal; reuse existing preparer/generation design and block HPA-583 while outstanding.

## Temporary instrumentation

Prefer Instruments. Reuse `Logger.info` / `ContinuousClock`; no permanent timing layer. `onAppear` is insertion-only evidence. Keep scoped `/tmp/hpa584-instrumentation.patch` before reverting rather than broad stash, so unrelated worktree state is not hidden. Commit no profiler artifacts or temporary source instrumentation.

## Acceptance criteria

- [ ] Fixed Soukyuu MASTER + exact source/toolchain identity.
- [ ] Direct HPA-579 comparison uses installed **900 pt / 156 rows**.
- [ ] Viewport/content geometry + 320 pt row pitch recorded; no fabricated CPU share.
- [ ] Separate Time Profiler, SwiftUI, memory sessions.
- [ ] One warm-up + two measured preparation runs; third only on material disagreement.
- [ ] `onAppear` explicitly insertion-only; Time Profiler owns mount attribution.
- [ ] 30+ seconds playback + real manual scrolling for evidence-backed decision.
- [ ] Credible macOS live memory for Keep eager.
- [ ] Resize widens from 900/156 to first real packing change or widest practical width.
- [ ] Resize layout CPU separate from row-laziness evidence.
- [ ] iPad evidence when available; otherwise explicit unverified limitation.
- [ ] Two GUI environment failures close without speculative optimization/performance claim.
- [ ] Usable GUI + missing memory => Tooling-blocked, not GUI fallback.
- [ ] No production virtualization/benchmark/custom-renderer work.
- [ ] HPA-581 tracked report supporting only; committed specs/plans own architecture.
- [ ] Temporary instrumentation/profiler artifacts removed before close.
