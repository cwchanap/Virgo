# HPA-584: Post-HPA-581 Notation Re-profiling and Row-Laziness Decision

**Date:** 2026-08-15  
**Status:** Proposed

## Context

HPA-584 is the Phase D evidence closeout for Virgo's notation-rendering performance work. It exists to answer one question after HPA-581: **does eager construction of the full-chart static notation tree still create enough real mount, scrolling, or memory cost to justify restructuring that tree by staff row and mounting rows lazily?**

The answer is allowed to be **no**. If the post-HPA-581 app is responsive on the representative chart, this ticket closes without production code.

HPA-579 established the comparison baseline on Release macOS using Soukyuu MASTER (`Virgo/Fixtures/soukyuu_e_no_shouka/mas.dtx`):

- 2,870 notes;
- 0 controls;
- 156 measures;
- 900 pt profiling row width;
- 156 rendered rows;
- chart selection -> gameplay prepared: median **267.857 ms**, range **264.074-269.534 ms**;
- production `GameplayView` initial mount: **4,890.729 ms**;
- production playback advanced through row 34 during a 49.717 s in-trace opportunity;
- manual scrolling was unavailable in that session;
- a reliable peak-live-memory value was not captured.

HPA-581 changed the two measured areas HPA-584 must re-check:

1. timeline notation layout now runs through `GameplayNotationPreparer` on a detached worker and is installed only if its notation generation is still current;
2. the static notation tree is isolated behind `GameplayStaticNotationView(input:).equatable()`, while the playhead and auto-scroll continue to observe live gameplay state.

HPA-581's final Release evidence confirmed the worker handoff but could not finish the interactive rendering evidence because the macOS GUI session was locked. HPA-584 closes the mount, scrolling, memory, and natural-resize gaps in a real unlocked session rather than repeating a headless worker proof.

The committed HPA-581 design and plan are the repository sources of truth for that handoff:

- `docs/superpowers/specs/2026-08-12-hpa-581-off-main-notation-preparation-design.md`
- `docs/superpowers/plans/2026-08-12-hpa-581-off-main-notation-preparation.md`

Merged PR #61 and the HPA-581 Linear discussion are supporting history. HPA-584 does **not** depend on `.superpowers/sdd/...` task reports because `.superpowers/` is gitignored and a clean checkout may not contain them.

HPA-584 blocks HPA-583, the final test/documentation cleanup. The closeout order remains:

```text
HPA-581 implementation -> HPA-584 evidence decision -> HPA-583 cleanup
```

## Current eager-rendering mechanism

The production renderer is not a list of 156 row views.

`GameplayStaticNotationLayers` mounts one chart-wide `ZStack`. Inside it, `GameplayDrumNotationView` builds full-chart `ForEach` collections for the current `NotationLayout`, including:

- ledger lines;
- printed rests;
- beams;
- flags;
- stems;
- note heads;
- rhythm dots;
- articulations;
- stop notes;
- tuplets;
- feel marks;
- rhythm warnings.

`StaffLinesBackgroundView` loops over unique row numbers and `GameplayRowAnchorColumn` creates invisible row anchors, but there is no row-grouped primitive model and no lazy gameplay container today.

Therefore HPA-584 cannot decide row laziness by looking for a hypothetical "row 140" stack frame. The evidence question is instead:

> Is mount, hitch, or memory cost dominated by constructing/evaluating the **full-chart primitive tree** while most of the resulting sheet height lies outside the current viewport?

Every representative run records both sides of that comparison:

- chart identity: notes / controls / measures / row width / rendered row count;
- visible geometry: viewport height versus static notation `contentHeight` / `layout.totalHeight`.

This makes the existing eager mechanism explicit. A future row-laziness ticket, if justified, must first introduce row grouping; wrapping the existing chart-wide `ZStack` in a lazy container would not satisfy the evidence.

## Goal

Re-run the HPA-579 notation scenarios against current `main`, compare post-HPA-581 behavior with the recorded baseline, and make one explicit eager-tree decision:

- **Keep eager rendering** and close HPA-584 with no production implementation; or
- **Create one focused row-laziness follow-up** only when real traces show full-chart primitive construction remains a dominant user-visible or supported-device cost.

Natural resize is classified separately so main-actor layout CPU cannot be mistaken for a row-laziness problem.

## Non-goals

- Implementing row virtualization inside HPA-584.
- Designing a virtualization framework in advance.
- Canvas tiling, custom drawing engines, pagination, viewport caches, display lists, or retained-mode renderers.
- A benchmark target, metrics service, performance dashboard, or CI performance gate.
- Universal millisecond or memory thresholds derived from one machine.
- Re-opening HPA-581 architecture or moving more SwiftData/rhythm work across actors.
- Import throughput work from HPA-580.
- Broad test/document cleanup from HPA-583.
- Synthetic resize widths used to manufacture a row-count change.
- Simulator performance numbers presented as physical iPad performance.
- Unit-test or coverage work as a substitute for interactive profiling.

## Approaches considered

### Repeat the established Release protocol, split by Instruments template — selected

Use the exact HPA-579 chart and comparable environment, profile the real interactive Release app, and run distinct sessions for distinct questions:

1. **Time Profiler** — preparation, first mount, and 30+ seconds of playback CPU/call-tree evidence;
2. **SwiftUI** — playback plus real manual scrolling and invalidation/update behavior;
3. **Allocations**, or the Xcode memory gauge if Allocations cannot provide a usable run — begin before entering gameplay so mount delta and live memory are observable.

A fourth Time Profiler resize run is performed only if a real host width actually changes row packing.

This is slightly more interaction time than HPA-579, but it directly closes the two HPA-579 gaps that matter to HPA-584: manual scrolling and credible live memory. It adds no production machinery.

### One combined profiling session — rejected

Product > Profile selects one Instruments template. Treating Time Profiler, SwiftUI, and Allocations as if they were one run risks repeating HPA-579's outcome: good CPU evidence with manual-scroll and live-memory gaps.

The sessions may use the same chart and interaction sequence, but their evidence is collected independently and named explicitly.

### Reuse only HPA-581's non-interactive profile — rejected

The worker-path evidence is already sufficient to establish that `NotationLayoutEngine.layout` moved off the main-thread preparation path. It cannot establish visible mount behavior, manual scrolling, or supported-device memory pressure.

### Build a benchmark harness or prototype virtualization first — rejected

A benchmark target or speculative lazy-row prototype would add machinery before evidence says the current eager renderer is a problem. It would also risk optimizing a synthetic path instead of the production SwiftUI interaction HPA-584 actually owns.

## Representative comparison contract

### Primary chart

Use the same HPA-579 chart:

```text
song: soukyuu_e_no_shouka
chart: MASTER / Expert
file: Virgo/Fixtures/soukyuu_e_no_shouka/mas.dtx
notes: 2,870
controls: 0
measures: 156
baseline row width: 900 pt
baseline rendered rows: 156
```

Do not re-run a catalog-wide ranking exercise merely because time has passed. The purpose is a before/after comparison against the known HPA-579 baseline.

If the fixture is unexpectedly unavailable or no longer imports as the same chart, stop and document that repository change before substituting another chart. A different chart is not an apples-to-apples HPA-579 comparison.

The current run must re-record the rendered row count from the installed layout:

```swift
(cachedNotationLayout.measures.map(\.row).max() ?? -1) + 1
```

`measures.count` is **not** a substitute for row count.

### Environment

Prefer the same class of host as HPA-579 where practical:

- MacBookPro18,3 / Apple M1 Pro / 32 GB;
- macOS 26.5.2 baseline;
- Xcode 26.6 baseline;
- xctrace/Instruments 16.0 baseline;
- Release macOS through Xcode Product > Profile.

Exact OS/tool versions may move. Record the current values instead of trying to recreate old tooling.

An **unlocked, usable GUI session is a hard gate** for the interactive evidence. If the screen is locked, the Virgo window cannot present, or accessibility/input is shielded, record HPA-584 as blocked and stop. Do not substitute a headless hook, synthetic scrolling, or a fake window resize for the required interaction result.

## Measurement contract

### 1. Establish source and profiling identity

Record:

```bash
git status -sb
git rev-parse HEAD
git log -1 --oneline
sw_vers
system_profiler SPHardwareDataType | egrep 'Model Name|Model Identifier|Chip|Memory'
xcodebuild -version
xcrun xctrace version
```

Compile-check Release with `xcodebuild`, but profile the app through Xcode Product > Profile. Before collecting numbers, a short Time Profiler run must show symbolicated Virgo frames and a usable window.

Use an info-level unified log stream only when temporary markers are needed:

```bash
log stream --level info --predicate 'subsystem == "com.cwchanap.Virgo"'
```

### 2. Record chart and viewport geometry

Once Soukyuu MASTER is prepared, record one metadata line containing:

- notes;
- controls;
- measures;
- `cachedLayoutRowWidth`;
- rendered row count from `measures.map(\.row)`;
- viewport height from the real gameplay geometry;
- static notation `contentHeight` or `layout.totalHeight`.

This is the basis for saying how much eagerly constructed content is outside the viewport. It is metadata, not a performance threshold and not a new cache.

### 3. Time Profiler session — preparation, first mount, steady playback

Start Time Profiler **before entering gameplay**.

For chart selection -> gameplay prepared, run one warm-up plus three measured entries and record:

- median and observed range;
- main-thread attribution during the interval;
- whether `NotationLayoutEngine.layout` remains on the worker path;
- whether another named main-thread stage is now dominant;
- a concrete visible loading observation.

Do not assume HPA-581 should reduce wall-clock readiness. Its intended benefit includes moving timeline layout work off-main so the UI stays responsive while preparation awaits the result.

Capture the first static-notation mount separately from preparation. If Time Profiler cannot expose a repeatable ready-to-static boundary, use only disposable `Logger.info` / `ContinuousClock` markers around the existing preparation completion and static-subtree appearance.

Use any marker delta only as **ready -> static-subtree appearance**. Do not relabel it compositor-complete frame time.

For first-mount attribution, inspect the actual eager units:

- `GameplayStaticNotationView.body`;
- `GameplayStaticNotationLayers.body`;
- `GameplayDrumNotationView.body`;
- the full-chart primitive `ForEach` collections;
- sibling full-chart layers such as staff lines, bar lines, clefs/time signatures, and row anchors.

Then continue at least 30 seconds of production playback and record whether live updates repeatedly enter expensive static-tree construction.

Compare against HPA-579's 4,890.729 ms initial-mount observation only when the boundary is materially comparable. Otherwise report the old and new evidence with the boundary limitation and do not calculate a precise speedup percentage.

### 4. SwiftUI session — invalidation and real manual scrolling

Start a separate Product > Profile session with the SwiftUI template before entering gameplay.

After the sheet mounts:

1. play for at least 30 seconds;
2. let auto-scroll cross rows;
3. manually scroll vertically through distant notation content;
4. scroll horizontally when the real content/window permits it;
5. let normal auto-scroll resume.

Record one interaction classification:

- smooth;
- occasional minor hitch;
- repeated hitch.

Use the SwiftUI instrument to determine whether expensive static notation work invalidates/re-evaluates during playback or scrolling. Sampling the outer `sheetMusicView` alone is not evidence that the full static primitive tree rebuilt.

If the SwiftUI instrument cannot expose useful invalidation rows, record that limitation and correlate visible behavior with the Time Profiler call trees. Do not silently treat missing invalidation data as proof of isolation.

### 5. Memory session — start before gameplay entry

Run a third session with **Allocations**. Start recording before entering Soukyuu MASTER so the mounted-chart delta is visible.

Record the exact metric names and values available for:

- pre-gameplay baseline;
- after first mount;
- during/after 30+ seconds of playback and manual scrolling;
- peak live memory if the tool explicitly exposes a peak.

If Allocations cannot attach or cannot expose a credible live metric, use the Xcode memory gauge in a separate Release interaction and name the gauge value exactly. Do not call an end snapshot, persistent-byte value, or virtual-memory-region total a peak.

A keep-eager decision requires enough memory evidence to say the full-chart eager tree is reasonable on the tested supported hardware. If no credible live-memory observation can be obtained, HPA-584 remains evidence-blocked.

### 6. Natural resize / row repacking

Resize the real macOS window through practical widths.

A resize is relevant only if the resolved width changes and the installed notation row count actually changes. If practical host widths still leave the chart at 156 rows, record **no natural packing-changing resize available** and stop. Do not repeat HPA-579's synthetic 3,000 pt probe.

If a real packing change exists, run a dedicated Time Profiler resize capture and classify the dominant cost:

1. **Layout CPU dominates** — `cacheNotationLayout()` / `NotationLayoutEngine.layout` on `@MainActor` is the issue. This is **not** row-laziness evidence. Reuse the already-designed HPA-581 path: route timeline relayout through `GameplayNotationPreparer` with the existing notation generation if the visible/main-thread cost is material.
2. **Full SwiftUI primitive-tree rebuild dominates** — this contributes to the same eager-tree evidence used for the row-laziness decision.
3. **Neither is material** — record the packing change and make no follow-up.

Resize evidence is therefore orthogonal to the binary HPA-584 eager-tree decision. A resize-only layout-CPU problem must not be filed as virtualization.

### 7. iPad-class check when practical

Include one iPad-class run when a usable physical device is readily available, because macOS may understate memory/frame pressure.

Record device model/OS and repeat a reduced interaction slice: mount, 30 seconds playback, real scrolling, and live memory.

If no physical iPad is available, state that limitation. An iPad Simulator may be used for functional/build verification but its host-backed performance numbers must not be presented as device performance.

## Decision rubric

No fixed universal timing or memory threshold is introduced.

### Keep eager rendering

Close the eager-tree question with no row-laziness implementation when the representative evidence shows all of the following:

- preparation no longer contains a material main-thread timeline-layout stall attributable to the work HPA-581 moved;
- any remaining first-mount delay is not materially dominated by construction/evaluation of the full-chart primitive collections for mostly off-screen content;
- steady playback does not repeatedly execute expensive full-static-tree work with visible impact;
- manual scrolling is responsive, or any observed hitch is not trace-attributable to eager full-chart primitive construction;
- mounted-chart live memory is reasonable on the tested supported hardware.

The app may still have measurable work. HPA-584 asks whether **row laziness** is justified, not whether every frame is free.

A material resize-only layout-CPU result does not change this eager-tree answer; it follows the separate existing-preparer path above.

### Create one row-laziness follow-up

Create one focused implementation ticket only when real evidence shows eager full-chart primitive mounting remains a dominant problem, for example:

- first mount is visibly delayed and traces are dominated by building/evaluating full-chart primitives while most `contentHeight` lies outside the viewport;
- repeated scrolling/frame hitches correlate with full static primitive work;
- full-chart eager mounting creates meaningful memory pressure on supported hardware.

The follow-up is constrained to the smallest row-based shape already named by HPA-584:

- pre-group immutable notation primitives by staff row;
- render rows in a lazy vertical container;
- keep horizontal geometry and stable notation IDs unchanged;
- preserve playhead alignment, auto-scroll, goldens, and accessibility.

The follow-up must actually introduce row grouping before laziness. Simply wrapping the existing chart-wide `GameplayDrumNotationView`/`ZStack` in a lazy container is not sufficient.

Do **not** design the implementation further in HPA-584. The follow-up gets its own design cycle.

If a row-laziness follow-up is created, make it a blocker of HPA-583 before closing HPA-584 so the final cleanup does not race a new rendering change.

### Resize-only layout CPU follow-up

If a natural packing-changing resize is visibly/materially expensive because the current post-debounce path runs `NotationLayoutEngine.layout` on `@MainActor`, do not call that row-laziness.

Record a narrow follow-up that reuses `GameplayNotationPreparer` and the existing notation generation exactly as already scoped by HPA-581 Task 7. Do not redesign the preparer, add another generation, or implement that change inside HPA-584.

If such a follow-up is created, it also blocks HPA-583 until the rendering/performance path settles.

## Result template

Post one authoritative HPA-584 comment:

```markdown
## Post-HPA-581 notation profile

### Environment
- Commit / machine / OS / Xcode / Instruments / Release macOS
- GUI session usable: yes/no
- Physical iPad run: device + OS, or explicit unavailable limitation

### Representative chart / geometry
- soukyuu_e_no_shouka / MASTER / Expert
- Notes / controls / measures
- Row width / rendered row count
- Viewport height / static content height

### HPA-579 baseline
- Gameplay prepared: 267.857 ms median (264.074-269.534 ms)
- Initial mount: 4,890.729 ms
- Playback: production auto-scroll observed through row 34 over 49.717 s
- Manual scroll: unavailable
- Peak live memory: unavailable

### Session A — Time Profiler
- Gameplay prepared: median + range; dominant main/background stacks
- Ready -> static subtree appearance: value or instrumentation limitation
- First mount: full-chart primitive-tree attribution and visible observation
- 30+ s playback: static-tree call-path behavior

### Session B — SwiftUI
- Playback invalidation/update result
- Manual scrolling: smooth | occasional minor hitch | repeated hitch
- Hitch attribution or instrumentation limitation

### Session C — memory
- Tool: Allocations | Xcode memory gauge
- Pre-gameplay metric/value
- Post-mount metric/value
- Playback/scroll metric/value
- Peak: exact tool-reported value, or explicitly unavailable

### Natural resize/repacking
- Row-count change: yes/no
- If yes: layout CPU | SwiftUI full-tree rebuild | neither material
- Separate resize follow-up: issue identifier or none

### Decision
- HPA-584 eager-tree decision: Keep eager | Create row-laziness follow-up
- Evidence: concise trace/memory reason
- Row-laziness follow-up: issue identifier or none
- HPA-583: unblocked now | blocked by follow-up issue(s)
```

## Temporary instrumentation policy

- Prefer Instruments before adding source markers.
- Reuse `Logger.info`; do not add a timing helper or permanent signpost framework.
- Use `ContinuousClock` only around a boundary the trace cannot isolate.
- Keep temporary markers local to `GameplayView` / `GameplaySheetMusicView` when possible.
- Reuse the HPA-579/HPA-581 disposable patch pattern; save useful temporary source changes to `/tmp/hpa584-instrumentation.patch` before reverting.
- Do not change actor isolation or view architecture merely to measure it.
- Do not commit `.trace` bundles, screenshots, DerivedData, profiler exports, or ad-hoc metrics files.
- Restore all temporary source instrumentation before closing the ticket.

## Acceptance criteria

- [ ] The profile uses current `main` after HPA-581 and records exact source/toolchain identity.
- [ ] The real interactive Release app is profileable with symbolicated Virgo frames in an unlocked GUI session.
- [ ] Soukyuu MASTER is re-run as the fixed HPA-579 comparison chart with notes, controls, measures, row width, **rendered row count**, viewport height, and static content height recorded.
- [ ] Time Profiler, SwiftUI, and Allocations/memory-gauge evidence are collected as explicitly separate sessions.
- [ ] Chart-selection-to-prepared timing and main/background attribution are captured.
- [ ] Initial mount is attributed against the actual eager full-chart primitive tree, not hypothetical row-view frames.
- [ ] At least 30 seconds of playback records static-tree CPU/update behavior.
- [ ] Real manual scrolling is observed in the SwiftUI session and any hitch is attributed before being blamed on eager rendering.
- [ ] A credible live-memory observation is captured from a session that begins before gameplay entry; missing memory evidence blocks a keep-eager conclusion.
- [ ] Natural resize is measured only when a real packing-changing width exists; layout CPU is classified separately from full SwiftUI tree rebuild cost.
- [ ] A physical iPad-class run is included when practical, otherwise the limitation is explicit and simulator numbers are not treated as device performance.
- [ ] HPA-584 records exactly one `Keep eager` or `Create row-laziness follow-up` eager-tree decision.
- [ ] Any material resize-only layout follow-up reuses the existing `GameplayNotationPreparer`/generation design instead of being mis-filed as virtualization.
- [ ] No virtualization, benchmark framework, CI performance gate, custom renderer, or unrelated optimization is implemented in HPA-584.
- [ ] The execution plan does not depend on gitignored `.superpowers/` task reports.
- [ ] Temporary instrumentation and profiler artifacts are removed from the repository working tree before the ticket closes.
