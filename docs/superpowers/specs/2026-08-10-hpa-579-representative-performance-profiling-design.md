# HPA-579: Representative Performance Profiling

**Date:** 2026-08-10
**Status:** Proposed

## Context

HPA-579 is the Phase B evidence gate in the Virgo runtime/performance roadmap. HPA-576, HPA-577, and HPA-578 have landed. This spike decides whether HPA-580 and HPA-581 should proceed, narrow, or close, and records the eager-render baseline HPA-584 will repeat later.

The suspected costs are real code paths, not conclusions:

- `ServerSongDownloader.processChart` is `@MainActor`; after network download it decodes, parses, projects, creates SwiftData models, and the multi-chart loop also suspends for a fixed 100 ms between charts.
- `LocalDTXFixtureImporter.importSongResult` / `loadImportedCharts` are `@MainActor`; a fresh import reads and parses files, projects rhythm data, creates models, and saves. Re-importing the same `serverSongId` exits early after audio-path refresh, so repeat measurements require a genuinely fresh store.
- `GameplayView.prepareGameplay` runs `loadChartData`, seeds row width, then calls `setupGameplay`; rhythm resolution and notation layout are therefore plausible main-actor costs.
- Width changes are trailing-edge debounced by 100 ms, and `updateRowWidth` clamps widths to `GameplayLayout.maxRowWidth` (900pt) before deciding whether a relayout is needed.
- `GameplaySheetMusicView` receives the broad observable view model while playback changes live state frequently, so broad static-canvas invalidation is plausible but must be measured.

## Decision

Use one small, repeatable **Instruments-first** profiling session.

1. **Profile through Xcode's Profile action.** Virgo's shared scheme profiles the `Release` configuration. `xcodebuild -configuration Release` remains a compile check only; the authoritative traces come from Product > Profile so the app is built and signed for profiling.
2. **Require an attach/symbolication gate before collecting numbers.** Time Profiler must record the Profile-action app and show symbolicated Virgo frames. If it cannot, fix the profiling setup before measuring.
3. **Run an info-level unified log stream while measuring.** Temporary `Logger.info` markers use the existing `com.cwchanap.Virgo` subsystem and are visible with:

   ```bash
   log stream --level info --predicate 'subsystem == "com.cwchanap.Virgo"'
   ```

4. **Pick the representative chart using the visible per-chart note count.** Do not build a selection metric system. Choose the highest-note-count real chart available in the current library. If no downloaded/current chart is clearly larger, use the present bundled Soukyuu MASTER chart (`Virgo/Fixtures/soukyuu_e_no_shouka/mas.dtx`). `SET.def` references REAL / `real.dtx`, but that file is absent and the importer drops it.
5. **Capture the remaining baseline counts only after the chart is selected.** One disposable `Logger.info` marker after `setupGameplay()` records note count, control count, measure count, row width, and rendered rows for HPA-584. These values are baseline metadata, not candidate-selection machinery.
6. **Measure only four decisions:** fresh DTX parse/projection, gameplay preparation, width relayout, and largest-chart mount/playback/scrolling/memory.
7. **Keep deliberate latency separate from CPU work.** The 100 ms inter-chart `Task.sleep` and 100 ms width debounce are reported separately from parse/layout processing.
8. **Record one evidence-backed decision for HPA-580 and HPA-581 in Linear.** The repository should normally return to a docs-only diff when the spike is finished.

## Approaches considered

### Instruments first, disposable local markers — selected

Profile the real Release app, use Time Profiler / SwiftUI / Allocations for end-to-end behavior, and add local `ContinuousClock` or `Logger.info` markers only where the trace cannot isolate a required boundary.

This preserves the real actor and SwiftUI behavior without creating a performance subsystem.

### Permanent benchmark harness — rejected

A benchmark target, metrics layer, CI gate, dashboard, or generalized signpost framework would be new machinery for a one-shot decision and would still miss real SwiftUI invalidation and interactive scrolling.

### XCTest timing only — rejected as primary method

Microbenchmarks can isolate pure functions but cannot answer the main HPA-581 questions about main-thread preparation, SwiftUI updates, mounting, and scrolling. They may be used only as a secondary aid if an existing test already exposes a useful pure boundary.

## Representative chart contract

- Use a real chart available in the current app data, not a small synthetic golden fixture.
- Choose by the largest visible `Chart.notesCount`; do not infer density from BASIC/MASTER/REAL labels.
- Do not add a multi-metric ranking or rendered-row tie-breaker. The goal is a representative worst current chart, not an exact benchmark leaderboard.
- If no current/downloaded chart is clearly larger, use Soukyuu MASTER / `mas.dtx`, the densest chart file actually shipped in that bundled fixture today.
- After the chosen chart is prepared, record:
  - notes;
  - controls;
  - measures;
  - concrete profiling row width;
  - rendered rows.

If two visible candidates are effectively tied, pick either consistently and record which one was used. Do not spend the spike proving an exact ordering.

## Measurement contract

### Environment and profiling mode

Record:

```bash
git rev-parse HEAD
sw_vers
system_profiler SPHardwareDataType | egrep 'Model Name|Model Identifier|Chip|Memory'
xcodebuild -version
xcrun xctrace version
```

Run one warm-up and three measured repetitions for short boundaries. Use the median and observed range. If the three runs disagree on the dominant stage, collect two additional runs rather than introducing statistical infrastructure.

### Scenario 1 — fresh DTX file/bytes to persistence projection

**Local path:** measure `LocalDTXFixtureImporter.loadImportedCharts` from immediately before `DTXFileParser.parseChartMetadata(from:)` through completion of `persistenceProjection()`.

A fresh local import is mandatory. `importSongResult` exits early when the same `serverSongId` already exists, so each local warm-up/measured run must start after the app is quit and the development SwiftData store plus bundled-fixture tombstone have been cleared. This destructive reset is intentionally performed only after the gameplay scenarios are complete.

A local-import run is valid only if the Time Profiler trace contains the symbolicated `LocalDTXFixtureImporter.loadImportedCharts` / DTX parser path (or a temporary parse marker when source timing is required). A run that takes the existing-song fast path is void and must not contribute to the HPA-580 decision.

**Server path:** when an importable server song is available, measure `ServerSongDownloader.processChart` after `downloadData(from:)` returns through `persistenceProjection()`. Network time is excluded. If no usable server import exists on the profiling machine, state that limitation instead of fabricating a measurement.

Report the fixed inter-chart delay separately as `max(0, processedChartCount - 1) * 100 ms`.

### Scenario 2 — chart selection to gameplay prepared

Measure from real work beginning in `GameplayView.prepareGameplay(initialRowWidth:)` through `isGameplayPrepared == true`.

Use Time Profiler to attribute the interval among the existing stages:

- SwiftData relationship access/copy;
- note sorting;
- `RhythmTimelineResolver.resolve` / `makeRhythmRuntime` / `RhythmLayoutSnapshotBuilder`;
- `computeCachedLayoutData` / `cacheNotationLayout` / `cacheBeatPositions`;
- BGM and remaining setup.

If temporary clocks are required, label `loadChartData`, `updateRowWidth`, and `setupGameplay` separately. Do not log a combined interval as `setupGameplay`.

### Scenario 3 — width change to notation relayout

The resolved width is `max(900, width)`. A sequence that stays entirely at or below 900pt is a guaranteed no-op.

Choose resize endpoints that cross distinct resolved widths and visibly change row packing. At least one endpoint must exceed 900pt. Measure:

- processing cost from `cacheNotationLayout` through `cacheBeatPositions` after the debounce fires;
- user-visible settling time separately, labeled as including the fixed 100 ms debounce.

If the profiling machine cannot produce a width transition that changes row packing, record the limitation instead of timing a no-op.

### Scenario 4 — mount, playback, scrolling, memory

On the representative chart:

1. open gameplay and let the notation mount;
2. start playback;
3. let the playhead advance across rows;
4. manually scroll while playback remains active;
5. observe at least 30 seconds of steady playback.

Use SwiftUI + Time Profiler to determine whether the static notation subtree broadly re-evaluates on live playback changes and whether any main-thread notation stacks correlate with visible hitches. Record peak live memory using Allocations or the Xcode memory gauge.

This is the HPA-584 eager-render baseline, not a leak audit and not permission to add virtualization.

## Decision rubric

No universal millisecond threshold is introduced from one machine. Decisions depend on trace-backed dominance and visible impact.

### HPA-580 — DTX parsing/file work

- **Proceed:** decode/parse/projection or blocking file work is a material main-thread contributor and moving that measured slice off-main is likely to remove a visible stall.
- **Narrow:** only a measured subset of the proposed off-main work is justified.
- **Policy-only Narrow:** movable parse/file work is not material, but removing the fixed 100 ms inter-chart sleep is worthwhile. In this case HPA-580 is rewritten to sleep removal only and all off-main parser/projection requirements are removed.
- **Close as unnecessary:** the representative import is responsive and neither the movable slice nor a small policy cleanup has sufficient value.

The sleep alone can never justify an off-main **Proceed**. SwiftData mutation cost is not evidence for moving SwiftData models across actors.

### HPA-581 — gameplay preparation/static rendering

- **Proceed:** measured rhythm/layout preparation, relayout, or broad static-canvas invalidation is a material current cost with visible impact.
- **Narrow:** only a smaller measured subset has value, such as width relayout or static-view observation cleanup.
- **Close as unnecessary:** the largest real chart prepares, resizes, mounts, plays, and scrolls responsively without material rhythm/layout or broad static-rendering cost.

A maintainability-only narrowing must stay small; HPA-579 does not justify a new screen architecture.

### HPA-584 — baseline only

Record the chosen chart identity, note/control/measure counts, profiling width, rendered rows, initial mount behavior, steady playback update behavior, scrolling observation, peak memory, and relevant trace notes. HPA-579 does not decide virtualization.

## Result template

Post one authoritative comment on HPA-579:

```markdown
## Profiling result

### Environment
- Commit / machine / OS / Xcode / Instruments / Release macOS

### Representative chart
- Song/chart
- Notes / controls / measures
- Profiling row width / rendered rows

### Measurements
- Local DTX file -> parse/projection: median + range, dominant stacks
- Server bytes -> decode/parse/projection: median + range or explicit unavailable limitation
- Inter-chart policy delay: fixed delay reported separately
- Chart selection -> gameplay prepared: median + range, dominant stage
- Width relayout processing: median + range; 100 ms debounce reported separately
- Mount/playback: SwiftUI update pattern and main-thread observations
- Scrolling: concrete responsiveness observation
- Peak live memory

### Decisions
- HPA-580: Proceed | Narrow | Policy-only Narrow | Close as unnecessary — reason
- HPA-581: Proceed | Narrow | Close as unnecessary — reason
- HPA-584 baseline: concise repeatable baseline
```

When a downstream ticket is Narrow, update its description and acceptance criteria before implementation. When it is Close as unnecessary, close it with the HPA-579 evidence as the reason.

## Temporary instrumentation policy

- Reuse `Logger.info`; do not add a timing helper.
- Add `ContinuousClock` only around a boundary Instruments cannot isolate cleanly.
- Keep temporary instrumentation local to the measured function.
- Do not change actor isolation to measure it.
- Do not commit `.trace` bundles, DerivedData, screenshots, or ad-hoc metrics exports.
- Before discarding temporary source changes, save a patch to `/tmp/hpa579-instrumentation.patch` so a repeated run does not require recreating the markers.
- Revert temporary timing/logging before HPA-579 closes unless a tiny retained signpost is explicitly justified by the evidence and is negligible to maintain.

## Non-goals

- Production optimization inside HPA-579.
- Permanent benchmark/performance-test infrastructure.
- CI performance gates, dashboards, or metrics services.
- Parallel chart downloads.
- Moving SwiftData models or `ModelContext` across actors.
- Rewriting parser, rhythm, notation, or metronome algorithms.
- BGM `.ogg` compatibility work; HPA-85 remains separate.
- Row virtualization; HPA-584 owns that decision.
- Broad test/document cleanup; HPA-583 remains the closeout ticket.

## Acceptance criteria

- [ ] Product > Profile records the Release app and shows symbolicated Virgo frames before measurements begin.
- [ ] An info-level `com.cwchanap.Virgo` log stream is running for temporary markers.
- [ ] The representative real chart is selected by visible note count, with Soukyuu MASTER / `mas.dtx` as the current bundled fallback.
- [ ] Baseline control/measure/width/rendered-row values are recorded only after the chart is selected.
- [ ] Every measured local import starts from a fresh store/tombstone state and proves the real parse path executed.
- [ ] DTX CPU/file work is not conflated with network time or the fixed inter-chart sleep.
- [ ] Gameplay preparation is attributed to existing stages with correctly labeled temporary intervals when needed.
- [ ] Width relayout uses distinct resolved widths; an all-<=900pt no-op is never counted as a measurement.
- [ ] Mount/playback records SwiftUI update behavior, scrolling responsiveness, and peak memory.
- [ ] HPA-580 and HPA-581 receive explicit evidence-backed decisions using the rubric above.
- [ ] HPA-584 receives a repeatable eager-render baseline.
- [ ] Temporary instrumentation is removed by default and no benchmark framework, CI gate, or virtualization is introduced.
