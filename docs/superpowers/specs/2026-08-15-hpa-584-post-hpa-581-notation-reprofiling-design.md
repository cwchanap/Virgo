# HPA-584: Post-HPA-581 Notation Re-profiling and Row-Laziness Decision

**Date:** 2026-08-15  
**Status:** Proposed

## Context

HPA-584 is the Phase D evidence closeout for Virgo's notation-rendering performance work. It answers one narrow question after HPA-581: **does eager construction of the full-chart static notation tree still create enough real mount, scrolling, or memory cost to justify restructuring that tree by staff row and mounting rows lazily?**

The answer may be **no**. HPA-584 is a measurement/decision ticket and normally ships no production code.

HPA-579 established the Release macOS comparison baseline on Soukyuu MASTER (`Virgo/Fixtures/soukyuu_e_no_shouka/mas.dtx`): 2,870 notes, 0 controls, 156 measures, resolved row width **900 pt**, 156 rendered rows, preparation median **267.857 ms** (264.074-269.534 ms), and initial mount **4,890.729 ms**. Manual scrolling and reliable peak-live-memory evidence were unavailable.

HPA-581 moved initial timeline notation layout through `GameplayNotationPreparer` on a detached worker and isolated static notation behind `GameplayStaticNotationView(input:).equatable()`.

The tracked HPA-581 final profiling report records the worker-path handoff and locked-GUI limitation:

- `.superpowers/sdd/2026-08-12-hpa-581-off-main-notation-preparation/task-8-profile-report.md`

The broader `.superpowers/` pattern is ignored for new local files, but this report itself is already tracked. It is supporting evidence only; the committed HPA-581 design/plan remain the architectural sources of truth.

## Current eager-rendering mechanism

Production gameplay mounts one chart-wide static `ZStack`. `GameplayDrumNotationView` builds full-chart primitive `ForEach` collections; row numbers are layout/anchor data, not existing row views. Therefore HPA-584 combines total eager-tree CPU/call paths, deterministic viewport/content geometry, real scrolling behavior, and live memory. Geometry is context, not CPU attribution: rows have different primitive density, so **do not multiply off-screen row fraction by total CPU time**.

## Goal

Use the same **900 pt / 156-row** geometry for direct HPA-579 comparison and decide:

- **Keep eager rendering**; or
- **Create one focused row-laziness follow-up** only from positive trace/interaction/memory evidence.

A bounded YAGNI fallback applies only to repeated GUI environment/session failure. A usable GUI with missing memory evidence is a separate tooling blocker.

Natural resize is classified independently so post-ready main-actor layout CPU is not mislabeled as row laziness.

## Non-goals

No virtualization implementation, benchmark/metrics infrastructure, custom renderer, pagination, viewport cache, actor rewrite, SwiftData ownership change, synthetic resize width, or unrelated HPA-583 cleanup.

## Selected measurement shape

1. **Time Profiler** — preparation, first mount, and 30+ seconds playback CPU/call paths.
2. **SwiftUI** — playback, invalidation/update evidence, and real manual scrolling.
3. **Allocations** or a separately named Xcode memory-gauge fallback — begin before gameplay.
4. **Time Profiler resize capture** — only after natural widening changes row packing.

## Representative comparison contract

Use Soukyuu MASTER / Expert (`mas.dtx`), 2,870 notes, 0 controls, 156 measures.

`updateRowWidth(_:)` resolves `max(900, width)`, so HPA-579's **900 pt / 156 rows** is comparable only when the current installed layout matches those values.

Before comparable timing:

1. run one untimed calibration entry;
2. record gameplay geometry width, `cachedLayoutRowWidth`, and rendered row count;
3. narrow the real window until `cachedLayoutRowWidth = 900 pt` and `renderedRows = 156`;
4. keep that window size for measured baseline runs.

If current source cannot reproduce 900/156, do not claim a direct mount-time comparison.

### Geometry exposure

Record viewport width/height, resolved row width, rendered row count, static content height/layout total height, and row pitch **320 pt**.

For context only:

```text
visibleRowCapacity ~= min(renderedRows, ceil(viewportHeight / 320) + 1)
offscreenRowFraction ~= 1 - visibleRowCapacity / renderedRows
```

Do not turn the fraction into a CPU estimate.

## Environment and blockers

### GUI gate

A usable unlocked GUI is required for an evidence-backed decision.

If HPA-584 attempt 1 fails because of lock/shield/input/session state, verify the session and retry once. If attempt 2 is also environment-blocked, close as:

```text
Close without optimization — interactive evidence unavailable
```

This is not Keep eager. It must state mount/scroll/memory remain unverified, create no speculative optimization issue, and unblock HPA-583 by YAGNI because there is no evidence justifying rendering architecture work.

### Memory tooling blocker

If the GUI is usable but neither Allocations nor the memory-gauge fallback yields a credible named macOS live-memory metric, record:

```text
Tooling-blocked — credible live-memory evidence unavailable
```

Do not use the GUI fallback. HPA-584/HPA-583 remain blocked pending later memory evidence or explicit Linear scope change.

## Measurement contract

### Session A — Time Profiler

Use one calibration/warm-up plus **two measured entries** at 900 pt / 156 rows. Add a third only if attribution or visible behavior differs materially.

Confirm initial timeline `NotationLayoutEngine.layout` remains on the worker path. Attribute first mount via the actual eager static bodies/primitive `ForEach`s. Any disposable `onAppear` marker is **subtree insertion/appearance only**; it does not bracket descendant construction or compositor completion. Continue 30+ seconds playback.

Compare HPA-579's 4,890.729 ms mount only when chart, 900/156 geometry, and measurement boundary are materially comparable.

### Session B — SwiftUI/manual scrolling

Run a separate SwiftUI session at the pinned geometry. Play 30+ seconds, let auto-scroll cross rows, manually scroll distant content, and classify smooth / occasional minor hitch / repeated hitch. Missing detailed invalidation rows are a stated limitation, not evidence of success.

### Session C — live memory

Run Allocations before gameplay at the pinned geometry. Record exact pre-gameplay, post-mount, and playback/scroll metric names/values. Use "peak" only if the tool reports peak. If needed, use the Xcode memory gauge and label its highest observed reading accurately.

Credible macOS live memory is required for evidence-backed Keep eager.

### Natural resize

Start at **900 pt / 156 rows**, then widen through practical widths. Record width/row count and stop at the first real packing change. Only if the widest practical host window still remains 156 rows may the result say no packing-changing width was available. Never use the synthetic 3,000 pt probe.

Classify a real packing change:

1. **Layout CPU dominates** — existing main-actor `cacheNotationLayout()` / `NotationLayoutEngine.layout`; create only a narrow follow-up reusing `GameplayNotationPreparer` + current generation if material.
2. **Full SwiftUI primitive-tree rebuild dominates** — contributes to row-laziness evidence.
3. **Neither material** — no follow-up.

### Physical iPad policy

Physical iPad evidence is advisory, not blocking for this hobby project. If available, repeat mount/playback/scroll/memory. If unavailable, record `iPad performance: unverified`; do not claim iPad performance from Simulator data. Any Keep eager conclusion without a device run is scoped to measured macOS hardware.

## Decision rubric

### Evidence-backed Keep eager

Requires the completed macOS sessions to show no material user-visible eager-tree mount issue, no repeated expensive static rebuild during playback, responsive/manual scrolling or unrelated hitches, and reasonable credible macOS live memory. Geometry may show most row extent is off-screen, but that fact alone does not justify laziness.

### Create one row-laziness follow-up

Only from positive evidence that full-chart primitive construction is a dominant mount, scroll/frame, or memory problem. Scope remains: pre-group immutable primitives by staff row, lazy vertical row container, unchanged horizontal geometry/stable IDs, preserve playhead/auto-scroll/goldens/accessibility. Wrapping the current full-chart view unchanged is insufficient.

### Close without optimization — interactive evidence unavailable

Only after two HPA-584 GUI attempts fail for environment/session reasons. Not an evidence-backed Keep eager result; HPA-583 becomes unblocked.

### Tooling-blocked — credible live-memory evidence unavailable

Use when GUI works but required memory evidence cannot be obtained. HPA-583 remains blocked.

### Resize-only layout CPU follow-up

Orthogonal to row laziness; reuse existing preparer/generation design and block HPA-583 until settled if created.

## Temporary instrumentation policy

Prefer Instruments. Reuse `Logger.info` / `ContinuousClock`; no permanent timing layer. `onAppear` is insertion-only evidence. Keep the scoped `/tmp/hpa584-instrumentation.patch` backup before reverting rather than a broad stash, so unrelated worktree state is not hidden. Commit no profiler artifacts or temporary source instrumentation.

## Acceptance criteria

- [ ] Fixed Soukyuu MASTER chart and exact source/toolchain identity recorded.
- [ ] Direct HPA-579 comparison uses real installed **900 pt / 156 rows**.
- [ ] Viewport/content geometry and 320 pt row pitch recorded; off-screen geometry is not converted into CPU share.
- [ ] Separate Time Profiler, SwiftUI, and memory sessions.
- [ ] Preparation uses one warm-up + two measured runs; third only on material disagreement.
- [ ] First-mount evidence uses Time Profiler; `onAppear` is insertion-only.
- [ ] 30+ seconds playback + real manual scrolling for evidence-backed decisions.
- [ ] Credible macOS live-memory evidence for Keep eager.
- [ ] Resize widens from 900/156 to first real packing change or widest practical host width.
- [ ] Resize layout CPU kept separate from row-laziness evidence.
- [ ] iPad evidence when available; otherwise explicit unverified limitation.
- [ ] Two GUI environment failures close without speculative optimization or performance claim.
- [ ] Usable GUI + missing memory reports Tooling-blocked, not GUI fallback.
- [ ] No production virtualization/benchmark/custom-renderer work in HPA-584.
- [ ] Tracked HPA-581 profile report is supporting evidence; committed specs/plans own architecture.
- [ ] Temporary instrumentation/profiler artifacts removed before close.
