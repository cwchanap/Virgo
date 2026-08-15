# HPA-584: Post-HPA-581 Notation Re-profiling and Row-Virtualization Decision

**Date:** 2026-08-15  
**Status:** Proposed

## Context

HPA-584 is the Phase D evidence closeout for Virgo's notation-rendering performance work. It exists to answer one question after HPA-581: **does eager full-chart notation rendering still create enough real mount, scrolling, or memory cost to justify row virtualization?**

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

HPA-581 then changed exactly the two measured areas HPA-584 must re-check:

1. timeline notation layout now runs through `GameplayNotationPreparer` on a detached worker and is installed only if its notation generation is still current;
2. the static notation tree is isolated behind `GameplayStaticNotationView(input:).equatable()`, while the playhead and auto-scroll continue to observe live gameplay state.

HPA-581's final headless Release profile confirmed `NotationLayoutEngine.layout` was sampled off the main thread, but the profiling host was locked. That run could not establish visible mount time, static-body presentation, manual scrolling, natural resize behavior, or live memory. HPA-584 should close those interactive evidence gaps rather than repeat headless worker validation.

HPA-584 blocks HPA-583, the final test/documentation cleanup. The closeout order remains:

```text
HPA-581 implementation -> HPA-584 evidence decision -> HPA-583 cleanup
```

## Goal

Re-run the HPA-579 notation scenarios against current `main`, compare the post-HPA-581 behavior with the recorded baseline, and make one explicit decision:

- **Keep eager rendering** and close HPA-584 with no production implementation; or
- **Create one focused row-laziness follow-up** only when real traces show eager off-screen rows remain a dominant user-visible or supported-device cost.

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

## Approaches considered

### Repeat the established Release Instruments protocol — selected

Use the exact HPA-579 chart and comparable environment, profile the real interactive Release app, and focus only on preparation, first mount, steady playback, manual scrolling, live memory, and natural resize/repacking.

This is the smallest approach that can answer the ticket. It preserves direct comparison with HPA-579 and avoids a new measurement system.

### Reuse only the HPA-581 headless profile — rejected

The headless run already proved the worker handoff: `NotationLayoutEngine.layout` was sampled off-main. It did not present a usable Virgo window, so it cannot decide whether full eager row construction still causes visible mount delay, scrolling hitching, or memory pressure.

Headless evidence is supporting context, not the HPA-584 decision.

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

Compile-check Release with `xcodebuild`, but profile the app through Xcode Product > Profile. Before collecting numbers, a short Time Profiler run must show symbolicated Virgo frames.

Use an info-level unified log stream only when temporary markers are needed:

```bash
log stream --level info --predicate 'subsystem == "com.cwchanap.Virgo"'
```

### 2. Chart selection -> gameplay prepared

Run one warm-up plus three measured entries for Soukyuu MASTER.

Measure the user-visible boundary from `GameplayView.prepareGameplay(initialRowWidth:)` beginning real work until `vm.isGameplayPrepared == true` after `await vm.setupGameplay()`.

Record:

- median and observed range;
- main-thread attribution during the interval;
- whether `NotationLayoutEngine.layout` remains on the worker path;
- whether another named main-thread stage is now dominant;
- a concrete visible loading observation.

Do not assume HPA-581 should reduce wall-clock readiness. Its intended benefit includes moving timeline layout work off-main so the UI stays responsive while preparation awaits the result.

If three runs disagree on the dominant stage, collect two more runs rather than adding statistical infrastructure.

### 3. Ready -> first static-notation appearance

Capture the first notation mount separately from preparation.

Prefer SwiftUI + Time Profiler attribution. If the trace cannot give a repeatable boundary, add only disposable info markers:

- one immediately after `await vm.setupGameplay()` returns prepared;
- one temporary `.onAppear` marker on `GameplayStaticNotationView`.

Use the log timestamps only as **ready-to-static-subtree-appearance** timing. Do not relabel that value as compositor-complete frame time.

The trace must answer the more important question: is the remaining visible first-mount cost dominated by constructing/evaluating the complete static notation tree, including off-screen rows?

Compare against HPA-579's 4,890.729 ms initial-mount observation only when the new trace boundary is materially comparable. If the instrumentation differs, report the two values with that limitation instead of claiming a precise speedup percentage.

### 4. Steady playback and static-tree invalidation

Profile at least 30 seconds of production playback after the sheet has mounted and let auto-scroll cross rows.

Inspect whether live changes broadly re-enter expensive static notation work. Pay attention to:

- `GameplayStaticNotationView.body`;
- `GameplayStaticNotationLayers.body`;
- `GameplayDrumNotationView.body`;
- large notation `ForEach` construction;
- `GameplayView.sheetMusicView`;
- expected playhead/row/playing update paths.

Frequent sampling of the outer gameplay container is not by itself a problem. Row virtualization is justified only by expensive full-static-row work that remains attributable to eager off-screen content.

If the SwiftUI instrument cannot export invalidation rows, use Time Profiler call-path evidence plus the visible interaction result and state that instrumentation limitation explicitly.

### 5. Manual scrolling while playback is active

With the real window visible, scroll vertically and horizontally while playback continues.

Record one concrete classification:

- smooth;
- occasional minor hitch;
- repeated hitch.

For any repeated hitch, correlate it with Time Profiler/SwiftUI stacks before attributing it to eager notation rows. A hitch caused by unrelated audio, windowing, or another live state path is not evidence for row virtualization.

Do not automate scrolling in this ticket.

### 6. Live memory

Use Allocations and/or the live Xcode memory gauge during initial mount, 30+ seconds of playback, and manual scrolling.

Record at least one credible live-memory observation for the representative chart. Prefer peak live memory when the tool exposes it. If only snapshots are available, record the exact metric that is available and do not call it a peak.

A keep-eager decision needs enough memory evidence to say the mounted 156-row chart is reasonable on the tested supported device. If the tooling cannot produce any credible live-memory observation, HPA-584 remains evidence-blocked rather than silently treating memory as acceptable.

### 7. Natural resize / row repacking

Resize the real macOS window through practical widths.

The current layout resolves row width through the existing 900 pt floor. A resize is relevant only if the real window reaches a distinct resolved width and the notation row packing actually changes.

If practical host widths still leave the chart at 156 rows, record **no natural packing-changing resize available** and stop. Do not repeat HPA-579's synthetic 3,000 pt probe and do not authorize resize-specific architecture from a no-op.

If a real packing change is available, profile the post-debounce preparation/reinstall path and keep the existing debounce latency separate from processing cost.

### 8. iPad-class check when practical

HPA-584 should include one iPad-class run when a usable physical device is readily available, because macOS may understate memory/frame pressure.

Record the device model/OS and repeat a reduced interaction slice: mount, 30 seconds playback, scrolling, and live memory.

If no physical iPad is available, state that limitation. An iPad Simulator may be used for functional/build verification but its host-backed performance numbers must not be presented as device performance.

## Decision rubric

No fixed universal timing or memory threshold is introduced.

### Keep eager rendering

Close HPA-584 with no production code when the representative evidence shows all of the following:

- preparation no longer contains a material main-thread timeline-layout stall attributable to the work HPA-581 moved;
- any remaining first-mount delay is not materially dominated by construction/evaluation of off-screen notation rows;
- steady playback does not repeatedly execute expensive full-static-tree work with visible impact;
- manual scrolling is responsive, or any observed hitch is not trace-attributable to eager off-screen rows;
- mounted-chart live memory is reasonable on the tested supported hardware;
- no natural resize evidence reveals a row-repacking problem worth a new architecture.

The app may still have measurable work. HPA-584 asks whether **row laziness** is justified, not whether every frame is free.

### Create one row-laziness follow-up

Create one focused implementation ticket only when real evidence shows eager full-chart mounting remains a dominant problem, for example:

- first mount is visibly delayed and traces are dominated by building/evaluating off-screen row primitives;
- repeated scrolling/frame hitches correlate with eager off-screen row work;
- full-chart eager mounting creates meaningful memory pressure on supported hardware.

The follow-up is constrained to the smallest row-based shape already named by HPA-584:

- pre-group immutable notation primitives by staff row;
- render rows in a lazy vertical container;
- keep horizontal geometry and stable notation IDs unchanged;
- preserve playhead alignment, auto-scroll, goldens, and accessibility.

Do **not** design the implementation further in HPA-584. The follow-up gets its own design cycle.

If a row-laziness follow-up is created, make it a blocker of HPA-583 before closing HPA-584 so the final cleanup does not race a new rendering change.

## Result template

Post one authoritative HPA-584 comment:

```markdown
## Post-HPA-581 notation profile

### Environment
- Commit / machine / OS / Xcode / Instruments / Release macOS
- GUI session usable: yes/no
- Physical iPad run: device + OS, or explicit unavailable limitation

### Representative chart
- soukyuu_e_no_shouka / MASTER / Expert
- 2,870 notes / 0 controls / 156 measures
- Baseline 900 pt / 156 rows

### HPA-579 baseline
- Gameplay prepared: 267.857 ms median (264.074-269.534 ms)
- Initial mount: 4,890.729 ms
- Playback: production auto-scroll observed through row 34 over 49.717 s
- Manual scroll: unavailable
- Peak live memory: unavailable

### Post-HPA-581 measurements
- Gameplay prepared: median + range; dominant main/background stacks
- Ready -> static subtree appearance: value or instrumentation limitation
- Initial mount: trace attribution and visible observation
- Steady playback: static-tree update pattern and prominent stacks
- Manual scrolling: smooth | occasional minor hitch | repeated hitch; attribution
- Live memory: exact observed metric and value
- Natural resize/repacking: result or no valid packing-changing width
- iPad-class result: observation or explicit limitation

### Decision
- HPA-584: Keep eager | Create row-laziness follow-up
- Evidence: concise trace-backed reason
- Follow-up: issue identifier if created; otherwise none
- HPA-583: unblocked now | blocked by new follow-up
```

## Temporary instrumentation policy

- Prefer Instruments before adding source markers.
- Reuse `Logger.info`; do not add a timing helper or permanent signpost framework.
- Use `ContinuousClock` only around a boundary the trace cannot isolate.
- Keep temporary markers local to `GameplayView` / `GameplaySheetMusicView` when possible.
- Do not change actor isolation or view architecture merely to measure it.
- Do not commit `.trace` bundles, screenshots, DerivedData, profiler exports, or ad-hoc metrics files.
- If temporary source changes would be useful for a repeated session, save them to `/tmp/hpa584-instrumentation.patch` before reverting.
- Restore all temporary source instrumentation before closing the ticket.

## Acceptance criteria

- [ ] The profile uses current `main` after HPA-581 and records exact source/toolchain identity.
- [ ] The real interactive Release app is profileable with symbolicated Virgo frames in an unlocked GUI session.
- [ ] Soukyuu MASTER is re-run as the fixed HPA-579 comparison chart with its 2,870-note / 156-measure / 156-row baseline recorded.
- [ ] Chart-selection-to-prepared timing and main/background attribution are captured.
- [ ] Initial static-notation mount is profiled separately enough to identify whether eager off-screen rows are a dominant cost.
- [ ] At least 30 seconds of playback records static-tree update behavior.
- [ ] Real manual scrolling is observed and any hitch is trace-attributed before being blamed on eager rows.
- [ ] A credible live-memory observation is captured; missing memory evidence blocks a keep-eager conclusion.
- [ ] Natural resize is measured only when a real packing-changing width exists; no synthetic width authorizes architecture work.
- [ ] A physical iPad-class run is included when practical, otherwise the limitation is explicit and simulator numbers are not treated as device performance.
- [ ] HPA-584 records exactly one `Keep eager` or `Create row-laziness follow-up` decision.
- [ ] No virtualization, benchmark framework, CI performance gate, custom renderer, or unrelated optimization is implemented in HPA-584.
- [ ] Temporary instrumentation and profiler artifacts are removed from the repository working tree before the ticket closes.
