# HPA-579: Representative Performance Profiling

**Date:** 2026-08-10
**Status:** Proposed

## Context

HPA-579 is the Phase B evidence gate in the Virgo runtime/performance roadmap. HPA-576, HPA-577, and HPA-578 have landed, so this is now the first unblocked roadmap item. Its purpose is not to optimize Virgo directly; it decides whether HPA-580 and HPA-581 are worth implementing, narrowing, or closing, and it establishes the baseline HPA-584 will use later.

The current code has several plausible costs, but the roadmap explicitly treats them as hypotheses rather than commitments:

- `ServerSongDownloader.processChart` is `@MainActor`. After `downloadData` returns it decodes DTX bytes, parses chart metadata, builds the persistence projection, creates SwiftData models, and inserts them. Its multi-chart loop also suspends for an unconditional 100 ms between charts.
- `LocalDTXFixtureImporter.importSongResult` and `loadImportedCharts` are `@MainActor`. Current local import performs SET/file checks, DTX file reads, parsing, projection, duration calculation, model construction, and save from that isolation context.
- `GameplayView.prepareGameplay` awaits `GameplayViewModel.loadChartData`, seeds row width, and calls `setupGameplay`. `loadChartData` traverses SwiftData relationships, sorts notes, resolves rhythm timing, and builds `GameplayRhythmRuntime`; `makeRhythmRuntime` builds note targets, a `RhythmLayoutSnapshot`, and a metronome schedule. `setupGameplay` then computes drum beats and cached layout data, including `NotationLayoutEngine` work.
- Width changes are intentionally trailing-edge debounced by 100 ms. After the debounce fires, `cacheNotationLayout` and `cacheBeatPositions` rebuild the notation-dependent caches on the main actor.
- `GameplaySheetMusicView` receives the broad `GameplayViewModel`. Its static notation subtree iterates the full cached notation layout while playback updates observable state frequently. `staticStaffLinesView` and `notationStaffLinesView` are cached as `AnyView`, which caches view descriptions rather than rendered output.

These facts make HPA-580/HPA-581 plausible, but not automatically justified.

## Decision summary

Use one small, repeatable, **Instruments-first** profiling pass on the largest/densest real chart currently available.

1. Make a Release macOS run the authoritative baseline. Record the exact commit, Mac hardware, OS, Xcode version, and configuration. Debug traces may be used for diagnosis but must be labeled and must not override Release behavior.
2. Select the representative chart by current chart complexity, not by filename alone. Prefer the real chart with the largest combination of note/control count and measure count that is available in the current app data. If no denser current server/downloaded chart is available, use the bundled Soukyuu fixture's REAL chart (`Virgo/Fixtures/soukyuu_e_no_shouka/real.dtx`).
3. Start with Time Profiler plus SwiftUI instrumentation. Add temporary `ContinuousClock` measurements only when Instruments cannot isolate a decision-relevant boundary cleanly.
4. Measure the four scenarios required by HPA-579:
   - DTX bytes/file available -> decode, parse, and persistence projection complete;
   - chart selection -> gameplay prepared;
   - width change -> notation relayout complete;
   - largest-chart mount/playback -> main-thread activity, SwiftUI update activity, scrolling responsiveness, and peak memory.
5. Treat the 100 ms inter-chart sleep as explicit wall-clock policy overhead, not parser CPU time. Report it separately.
6. Do not create a benchmark target, metrics service, CI performance gate, dashboard, generalized signpost layer, or retained trace repository.
7. Record final numbers and Proceed/Narrow/Close decisions in a Linear comment on HPA-579. Do not commit Instruments traces. Temporary source instrumentation is reverted before HPA-579 closes unless a retained signpost proves necessary to interpret an otherwise unmeasurable boundary.

## Approaches considered

### A. Build a permanent benchmark harness first

Create dedicated performance tests or a benchmark target for import, layout, and rendering.

**Rejected.** HPA-579 is a decision spike. A harness would front-load architecture and maintenance before proving any ongoing measurement need, and it still would not capture real SwiftUI invalidation or interactive scrolling well.

### B. Instruments first, temporary clocks only for ambiguous boundaries

Profile the real app in Release, use stack attribution for the broad behavior, and add local timing around only the boundaries that remain ambiguous.

**Selected.** This gives end-to-end evidence, preserves the real main-actor/SwiftUI behavior, and keeps instrumentation disposable.

### C. XCTest microbenchmarks only

Time parser/layout functions under tests and decide from those numbers.

**Rejected as the primary method.** Unit timing can isolate pure functions but misses the main questions in HPA-581: chart preparation on the UI actor, SwiftUI update fan-out, mounting, scrolling, and playback-time invalidation. A one-off test may still be used as a secondary aid if it is the fastest way to compare candidate real charts or isolate parser/projection cost.

## Representative chart selection

The benchmark input must be a real chart, not one of the small synthetic golden fixtures used to pin individual notation semantics.

Selection rules:

1. Use current app data available on the profiling machine.
2. Compare candidate real charts by at least:
   - note count;
   - control-event count;
   - measure count / rendered row count.
3. Use the candidate that is directionally largest/densest across those values. Exact weighting is unnecessary; the goal is to avoid accidentally profiling an easy chart.
4. Record the song/chart identity and the counts in the HPA-579 result comment so HPA-584 can repeat the same baseline.
5. If the current catalog has no locally available chart that is clearly denser, use the bundled Soukyuu REAL chart as the stable fallback.

Do not infer that `REAL` or `MASTER` is densest solely from the difficulty label when a quick count is available.

## Measurement protocol

### Environment capture

Before measuring, capture the literal output of:

```bash
git rev-parse HEAD
sw_vers
system_profiler SPHardwareDataType | egrep 'Model Name|Model Identifier|Chip|Memory'
xcodebuild -version
xcrun xctrace version
```

Build/profile the macOS target in Release. Simulator timings are not used as performance evidence; a physical iPad may be used as an optional confirmation if readily available, but it is not required for this spike.

For short duration boundaries, perform one warm-up and three measured runs. Record the median and observed range. If the three runs disagree on which stage is dominant, collect two additional runs rather than inventing a statistical framework.

### Scenario 1 — DTX file/bytes to persistence projection

This scenario decides the off-main portion of HPA-580.

#### Local fixture path

Measure the current work in `LocalDTXFixtureImporter.loadImportedCharts` from immediately before:

```swift
DTXFileParser.parseChartMetadata(from: chartURL)
```

through completion of:

```swift
let projection = try data.persistenceProjection()
```

This slice intentionally includes the local chart file read/decode performed by `parseChartMetadata(from:)` and the pure projection work, but not SwiftData model mutation/save.

#### Server path

Measure `ServerSongDownloader.processChart` from immediately after:

```swift
let data = try await downloader.downloadData(from: url)
```

through completion of:

```swift
let projection = try chartData.persistenceProjection()
```

This excludes network time while retaining the decode + parse + projection work HPA-580 could move off-main.

Use Time Profiler first. If the exact start/end is hard to distinguish, add temporary local `ContinuousClock` timestamps around only these slices.

Also inspect the whole import trace so the result can distinguish:

- parser/projection CPU;
- main-actor SwiftData model construction/save;
- network/file latency;
- the deliberate 100 ms inter-chart sleeps.

The fixed sleep is reported separately as `100 ms * (processed chart count - 1)`. It is a latency policy, not a main-thread CPU cost.

### Scenario 2 — chart selection to gameplay prepared

Measure the user-visible preparation interval beginning when `GameplayView.prepareGameplay(initialRowWidth:)` starts real work and ending when `GameplayViewModel.isGameplayPrepared` becomes true.

Use Time Profiler call stacks to attribute the interval to the existing stages:

1. `GameplayViewModel.loadChartData`
   - SwiftData relationship reads/copies;
   - note sorting;
   - `RhythmTimelineResolver.resolve`;
   - `makeRhythmRuntime`, including note targets, `RhythmLayoutSnapshotBuilder`, and `RhythmMetronomeSchedule`.
2. `GameplayViewModel.setupGameplay`
   - `computeDrumBeats`;
   - `computeCachedLayoutData` / `cacheNotationLayout` / `cacheBeatPositions`;
   - BGM setup and remaining timing/input setup.

Only add nested temporary clock measurements when the sampled stacks cannot answer which stage dominates.

Do not assume HPA-581 is justified merely because the total interval is noticeable. If BGM setup, SwiftData relationship loading, or another non-HPA-581 stage dominates, the HPA-581 decision must reflect that.

### Scenario 3 — width change to notation relayout

The current resize path intentionally waits for the 100 ms trailing-edge debounce before rebuilding. Measure two values and keep them conceptually separate:

- **processing cost:** time spent after the debounce callback enters `cacheNotationLayout` through completion of `cacheBeatPositions`;
- **user-visible settling time:** last width event to the completed layout, explicitly labeled as including the known 100 ms debounce.

HPA-581's off-main relayout decision is based on the processing cost and any observed main-thread hitch, not on the deliberate debounce constant.

Exercise at least one resize that changes row packing on the representative chart; a width change that produces an identical layout is not useful evidence.

### Scenario 4 — mount, playback, SwiftUI updates, scrolling, memory

Profile the representative chart while:

1. opening gameplay and letting the full notation mount;
2. starting playback;
3. allowing the playhead to advance across rows;
4. manually scrolling through the notation while playback remains active;
5. continuing long enough to observe steady-state update behavior.

Use the SwiftUI instrument plus Time Profiler to answer:

- Does the static notation subtree re-evaluate broadly on frequent playback changes, or are updates effectively limited to playhead/scroll state?
- Are notation `ForEach` construction/layout stacks repeatedly prominent during steady playback?
- Are there main-thread stalls that correspond to visible scrolling or playhead hitches?
- Is initial mount cost materially larger than steady playback cost?

Record peak live memory for this scenario using Instruments Allocations or the Xcode memory gauge. The goal is a repeatable HPA-584 baseline, not a leak audit.

Do not add row virtualization during this ticket.

## Decision rubric

No universal millisecond threshold is introduced from one developer machine. Decisions are based on trace-backed dominance and observable user impact.

### HPA-580 — DTX parsing/file work

Record one of:

- **Proceed** when decode/parse/projection or blocking file work is a material main-thread contributor on the representative import and moving that measured slice off-main is likely to remove a visible stall.
- **Narrow** when only a subset is justified—for example local file read + projection but not server parsing, or only the fixed inter-chart sleep is worth removing.
- **Close as unnecessary** when the representative import is responsive and the movable CPU/file slice is not a material main-thread cost.

Do not treat SwiftData mutation cost as evidence for moving SwiftData models off-main; HPA-580 explicitly keeps model mutation on the main actor.

### HPA-581 — gameplay preparation/static rendering

Record one of:

- **Proceed** when rhythm/layout preparation, relayout, or broad static-canvas invalidation is a material main-thread/rendering cost with visible impact.
- **Narrow** when only part of the proposed work is supported—for example layout preparation is fine but broad SwiftUI observation/`AnyView` cleanup has clear value, or only width relayout is expensive.
- **Close as unnecessary** when the largest real chart prepares, resizes, mounts, plays, and scrolls responsively without material rhythm/layout or broad static-rendering cost.

A maintainability-only narrowing must stay small: remove presentation caching or narrow observation only where the trace/code structure gives current value. Do not use HPA-579 as justification for a new screen architecture.

### HPA-584 — baseline only

HPA-579 does not decide virtualization. Record enough of the current eager-render baseline to repeat later:

- representative chart identity and complexity counts;
- initial mount behavior;
- steady playback SwiftUI update behavior;
- scrolling responsiveness observations;
- peak live memory;
- relevant trace notes.

## Result ownership

The authoritative result is one concise Linear comment on HPA-579. Use this structure:

```markdown
## Profiling result

### Environment
- Commit / machine / OS / Xcode / configuration

### Representative chart
- Song/chart identity
- Notes / controls / measures / rendered rows

### Measurements
- DTX file/bytes -> projection: median + range, dominant stacks
- Gameplay selection -> prepared: median + range, dominant stacks
- Width relayout processing: median + range; debounce reported separately
- Mount/playback: SwiftUI update behavior, scrolling observations, peak memory

### Decisions
- HPA-580: Proceed | Narrow | Close as unnecessary — evidence-backed reason
- HPA-581: Proceed | Narrow | Close as unnecessary — evidence-backed reason
- HPA-584 baseline: concise repeatable baseline
```

If a ticket is **Narrow**, update that ticket's description before implementation so its acceptance criteria match the evidence. If the decision is **Close as unnecessary**, close the ticket with the HPA-579 comment as the reason. If **Proceed**, leave the ticket scope intact unless the trace identifies a more precise boundary.

## Temporary instrumentation policy

Temporary timing code is acceptable only when Instruments cannot isolate an important boundary.

- Keep it local to the measured function.
- Do not add a generalized metrics helper.
- Do not change actor isolation merely to measure it.
- Do not commit Instruments `.trace` bundles.
- Revert temporary timing/logging code before HPA-579 closes unless a retained `os_signpost` interval is clearly necessary for future HPA-584 comparison and is negligible to maintain.
- If a retained signpost is justified, keep only the smallest named interval(s) around the ambiguous boundary and explain the retention in the HPA-579 result comment.

## Expected repository impact

This planning PR is documentation-only:

- `docs/superpowers/specs/2026-08-10-hpa-579-representative-performance-profiling-design.md`
- `docs/superpowers/plans/2026-08-10-hpa-579-representative-performance-profiling.md`

Execution of HPA-579 should normally finish with no production source diff. The measured findings live in Linear. A tiny retained signpost change is allowed only if the spike proves it necessary.

## Non-goals

- Production optimization in HPA-579.
- A permanent benchmark target or performance-test suite.
- CI performance gates or dashboards.
- Parallel chart downloads.
- Moving SwiftData models or `ModelContext` across actors.
- Rewriting rhythm, notation, metronome, or parser algorithms.
- BGM `.ogg` compatibility work; HPA-85 remains separate.
- Row virtualization; HPA-584 owns that later decision.
- Broad test/document cleanup; HPA-583 remains the closeout ticket.

## Acceptance criteria

- [ ] The largest/densest currently available real chart is identified and recorded with repeatable complexity counts.
- [ ] Commit, hardware/device, OS, Xcode, and build configuration are recorded.
- [ ] DTX file/bytes -> decode/parse/projection is measured without conflating network latency or the fixed inter-chart sleep.
- [ ] Chart selection -> gameplay prepared is measured and attributed to existing stages.
- [ ] Width relayout processing cost is measured separately from the intentional 100 ms debounce.
- [ ] Largest-chart mount/playback records main-thread activity, SwiftUI update behavior, scrolling responsiveness, and peak memory.
- [ ] HPA-580 and HPA-581 each receive an explicit Proceed, Narrow, or Close as unnecessary decision backed by observed evidence.
- [ ] A concise repeatable baseline is recorded for HPA-584.
- [ ] No benchmark framework, dashboard, CI gate, virtualization, or speculative production optimization is added.
- [ ] Temporary instrumentation is removed unless a minimal retained signpost is explicitly justified by the measurement itself.
