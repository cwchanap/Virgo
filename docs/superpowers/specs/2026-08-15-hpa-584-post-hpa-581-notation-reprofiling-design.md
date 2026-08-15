# HPA-584: Post-HPA-581 Notation Re-profiling and Row-Laziness Decision

**Date:** 2026-08-15  
**Status:** Proposed

## Context

HPA-584 asks whether Virgo's eager full-chart static notation tree still causes enough real mount, scrolling, or memory cost after HPA-581 to justify row-grouped lazy rendering.

HPA-579's Release baseline on Soukyuu MASTER (`mas.dtx`) was 2,870 notes, 0 controls, 156 measures, **900 pt** resolved row width, **156 rows**, preparation median **267.857 ms**, and initial mount **4,890.729 ms**. Manual scrolling and reliable live-memory evidence were unavailable.

HPA-581 moved initial timeline notation layout through `GameplayNotationPreparer` on a detached worker and isolated static notation behind `GameplayStaticNotationView(...).equatable()`. Its tracked task-8 profile report is supporting evidence for the worker path and the locked-GUI limitation; committed HPA-581 specs/plans remain authoritative.

## Current eager mechanism

Gameplay mounts one chart-wide static `ZStack`; `GameplayDrumNotationView` iterates full-chart primitive collections. Rows are layout/anchor data, not existing row views.

HPA-584 combines total eager-tree CPU/call paths, deterministic viewport/content geometry, real scrolling, and live memory. Geometry is **not** CPU attribution: primitive density differs per row, so never multiply an off-screen row fraction by total CPU time.

## Non-goals

No production virtualization, benchmark/metrics infrastructure, custom renderer, pagination, viewport cache, actor rewrite, SwiftData ownership change, synthetic resize width, or unrelated HPA-583 cleanup.

## Fixed comparison geometry

`updateRowWidth(_:)` resolves `max(900, width)`. Direct HPA-579 comparison is valid only when current installed layout also reports **900 pt / 156 rows**.

Before comparable timing: one untimed calibration; record gameplay geometry/resolved width/rendered rows; narrow real window to `cachedLayoutRowWidth = 900 pt` and `renderedRows = 156`; keep that size for measured runs. If current source cannot reproduce 900/156, do not claim direct 4,890.729 ms comparison.

Record viewport width/height, resolved row width, rendered rows, static content height/layout total height, and row pitch **320 pt**. Geometry-only context:

```text
visibleRowCapacity ~= min(renderedRows, ceil(viewportHeight / 320) + 1)
offscreenRowFraction ~= 1 - visibleRowCapacity / renderedRows
```

Do not convert fraction into CPU cost.

## Sessions

### Time Profiler
Pinned 900/156; one warm-up/calibration + **two measured entries**; third only on material disagreement. Confirm initial `NotationLayoutEngine.layout` remains off-main. Time Profiler owns mount attribution. Any disposable `onAppear` is insertion/appearance only, not descendant-construction/compositor timing. Continue 30+ seconds playback.

### SwiftUI/manual scroll
Separate session at pinned geometry; 30+ seconds playback/auto-scroll; real manual distant scrolling; classify smooth / occasional minor hitch / repeated hitch; missing invalidation detail is limitation, not success evidence.

### Live memory
Separate Allocations session before gameplay; exact pre-gameplay/post-mount/playback-scroll metrics; peak only if tool reports it. Xcode memory-gauge fallback allowed with accurately labeled highest observed reading. Credible macOS live memory required for evidence-backed Keep eager.

## Natural resize

Start **900 pt / 156 rows**, widen practical host widths, stop at first real row-count change. Only after widest practical width may result say no packing-changing width. No synthetic 3,000 pt.

Classify: layout CPU dominates (existing preparer/generation follow-up; not virtualization), full SwiftUI primitive-tree rebuild dominates (row-laziness evidence), or neither material.

## Physical iPad

Advisory, not blocking. If available, repeat mount/playback/scroll/memory. If absent, `iPad performance: unverified`; no Simulator device-performance claim. Keep eager without iPad is macOS-scoped.

## Outcomes

- **Keep eager:** requires complete macOS CPU/SwiftUI/manual-scroll/live-memory evidence showing no material eager-tree problem.
- **Row-laziness follow-up:** only positive evidence; row-group immutable primitives + lazy vertical row container; preserve horizontal geometry/stable IDs/playhead/auto-scroll/goldens/a11y; wrapping current full-chart view unchanged insufficient.
- **GUI environment fallback:** first environment/session GUI failure => verify + retry once; second => `Close without optimization — interactive evidence unavailable`, not Keep eager; state mount/scroll/memory unverified, no speculative optimization, HPA-583 unblocks by YAGNI.
- **Memory tooling blocker:** usable GUI but no credible memory from Allocations/gauge => `Tooling-blocked — credible live-memory evidence unavailable`; no GUI fallback; HPA-584/HPA-583 stay blocked pending later evidence/explicit scope change.
- **Resize-only follow-up:** orthogonal; reuse preparer/generation design; block HPA-583 while outstanding.

## Temporary instrumentation

Prefer Instruments. Reuse `Logger.info` / `ContinuousClock`; no permanent timing layer. `onAppear` insertion-only. Keep scoped `/tmp/hpa584-instrumentation.patch` rather than broad stash so unrelated worktree state is not hidden. Commit no profiler artifacts or temporary source instrumentation.

## Acceptance criteria

- [ ] Fixed chart + exact source/toolchain.
- [ ] Direct comparison uses installed **900 pt / 156 rows**.
- [ ] Viewport/content geometry + 320 pt row pitch, no fabricated CPU share.
- [ ] Separate Time Profiler/SwiftUI/memory sessions.
- [ ] One warm-up + two measured entries; third only on material disagreement.
- [ ] `onAppear` insertion-only; Time Profiler owns mount attribution.
- [ ] 30+ seconds playback + real manual scroll.
- [ ] Credible macOS live memory for Keep eager.
- [ ] Resize widens from 900/156 to first real packing change or widest practical width.
- [ ] Resize CPU separate from row-laziness evidence.
- [ ] iPad when available; otherwise explicit unverified limitation.
- [ ] Two GUI environment failures close without speculative optimization/performance claim.
- [ ] Usable GUI + missing memory => Tooling-blocked.
- [ ] No production virtualization/benchmark/custom-renderer work.
- [ ] Tracked HPA-581 report supporting only; committed specs/plans authoritative.
- [ ] Temporary instrumentation/profiler artifacts removed before close.
