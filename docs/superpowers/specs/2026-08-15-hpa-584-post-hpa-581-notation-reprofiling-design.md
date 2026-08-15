# HPA-584: Post-HPA-581 Notation Re-profiling and Row-Laziness Decision

**Date:** 2026-08-15  
**Status:** Proposed

## Context

HPA-584 is the Phase D evidence closeout for Virgo's notation-rendering performance work. It answers one narrow question after HPA-581: **does eager construction of the full-chart static notation tree still create enough real mount, scrolling, or memory cost to justify restructuring that tree by staff row and mounting rows lazily?**

The answer may be **no**. HPA-584 is a measurement/decision ticket and normally ships no production code.

HPA-579 established the Release macOS comparison baseline on Soukyuu MASTER (`Virgo/Fixtures/soukyuu_e_no_shouka/mas.dtx`):

- 2,870 notes;
- 0 controls;
- 156 measures;
- resolved row width **900 pt**;
- 156 rendered rows;
- chart selection -> gameplay prepared: median **267.857 ms**, range **264.074-269.534 ms**;
- production `GameplayView` initial mount: **4,890.729 ms**;
- production playback advanced through row 34 during a 49.717 s in-trace opportunity;
- manual scrolling was unavailable;
- a reliable peak-live-memory value was not captured.

HPA-581 then changed the two measured areas HPA-584 must re-check:

1. initial timeline notation layout now runs through `GameplayNotationPreparer` on a detached worker and installs through the existing notation generation;
2. static notation is isolated behind `GameplayStaticNotationView(input:).equatable()`, while playhead and auto-scroll remain live.

The tracked HPA-581 final profiling report records the worker-path handoff and the locked-GUI limitation:

- `.superpowers/sdd/2026-08-12-hpa-581-off-main-notation-preparation/task-8-profile-report.md`

`.superpowers/` is ignored for newly-created local files, but this specific report is already tracked and is available in a normal checkout. It is supporting evidence only. The committed HPA-581 design and plan remain the architectural sources of truth:

- `docs/superpowers/specs/2026-08-12-hpa-581-off-main-notation-preparation-design.md`
- `docs/superpowers/plans/2026-08-12-hpa-581-off-main-notation-preparation.md`

HPA-584 blocks HPA-583, the final test/documentation cleanup. The intended closeout remains:

```text
HPA-581 implementation -> HPA-584 evidence decision -> HPA-583 cleanup
```

## Current eager-rendering mechanism

The production renderer is **not** a list of 156 mounted row views.

`GameplayStaticNotationLayers` mounts one chart-wide `ZStack`. `GameplayDrumNotationView` then builds full-chart `ForEach` collections for:

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

Therefore the trace cannot expose a useful hypothetical `row 140` stack. HPA-584 instead combines:

1. **total eager-tree CPU/call-path evidence** from the real chart-wide primitive tree;
2. **deterministic geometry exposure** showing how much row extent lies outside the viewport;
3. visible scroll behavior and live-memory evidence.

Geometry is context, not a CPU partition. Rows have different primitive density and cost, so HPA-584 must **not** multiply an off-screen row fraction by total static-tree CPU time and call the product "off-screen cost."

## Goal

Re-run the HPA-579 notation scenarios against current `main`, using the same resolved **900 pt / 156-row** baseline geometry for any direct mount comparison, then make one evidence-backed eager-tree decision:

- **Keep eager rendering** — no row-laziness implementation; or
- **Create one focused row-laziness follow-up** — only when real evidence shows the eager full-chart primitive tree is a dominant mount, scroll/frame, or memory problem.

A separate YAGNI fallback exists only for repeated environment failure: if HPA-584 cannot obtain a usable GUI after two HPA-584 attempts, close without optimization and without claiming performance is acceptable.

Natural resize is classified independently so post-ready main-actor layout CPU cannot be mistaken for row-laziness evidence.

## Non-goals

- Implementing row virtualization inside HPA-584.
- Designing a virtualization framework in advance.
- Canvas tiling, custom drawing engines, pagination, viewport caches, display lists, or retained-mode renderers.
- A benchmark target, metrics service, dashboard, or CI performance gate.
- Universal timing or memory thresholds from one machine.
- Re-opening HPA-581 actor boundaries or moving more SwiftData/rhythm work across actors.
- Import work from HPA-580.
- Broad test/document cleanup from HPA-583.
- Synthetic resize widths used to manufacture a row-count change.
- Simulator performance numbers presented as physical iPad performance.
- Unit tests or coverage work as a substitute for interactive profiling.

## Approaches considered

### Fixed-baseline Release profiling, split by Instruments template — selected

Use the fixed Soukyuu MASTER chart and run distinct sessions:

1. **Time Profiler** — initial preparation, first mount, and 30+ seconds of playback CPU/call-tree evidence;
2. **SwiftUI** — playback plus real manual scrolling and update/invalidation evidence;
3. **Allocations**, or a separately named Xcode memory-gauge fallback — start before gameplay so mount delta/live memory are observable;
4. **Time Profiler resize capture** — only after a natural width increase actually changes row packing.

This directly closes HPA-579's missing scroll/memory evidence without creating measurement infrastructure.

### One combined profiling session — rejected

Product > Profile selects one template. Treating Time Profiler, SwiftUI, and Allocations as one implied session risks repeating HPA-579's incomplete close.

### Derive an "off-screen CPU cost" from row fraction — rejected

The row pitch and viewport can estimate how much row extent is off-screen, but primitive density differs by row and the current renderer iterates primitive collections, not row collections. Geometry can strengthen or weaken the case for laziness; it cannot apportion CPU deterministically.

### Prototype row virtualization first — rejected

A lazy-row prototype would design the optimization before evidence justifies it and could hide the current eager mechanism rather than measure it.

## Representative comparison contract

### Fixed chart

```text
song: soukyuu_e_no_shouka
chart: MASTER / Expert
file: Virgo/Fixtures/soukyuu_e_no_shouka/mas.dtx
notes: 2,870
controls: 0
measures: 156
HPA-579 resolved row width: 900 pt
HPA-579 rendered rows: 156
```

Do not re-rank the catalog. This is a before/after comparison.

### Baseline window geometry is controlled

`GameplayViewModel.updateRowWidth(_:)` resolves width as:

```swift
max(GameplayLayout.maxRowWidth, width)
```

with `GameplayLayout.maxRowWidth == 900`.

Therefore HPA-579's **900 pt / 156-row** baseline is comparable only when the current run also resolves to 900 pt and renders 156 rows.

Before any HPA-579-comparable preparation/mount timing:

1. run one untimed calibration entry;
2. record the real gameplay `geometry.size.width`, `cachedLayoutRowWidth`, and rendered row count;
3. manually narrow the real window until the installed layout reports:

```text
cachedLayoutRowWidth = 900 pt
renderedRows = 156
```

4. leave the window at that size for the comparable measured entries.

Do not infer the baseline from the outer window's nominal size. The logged gameplay geometry/resolved width is authoritative.

If current source can no longer reproduce 900 pt / 156 rows for the same chart, record that repository behavior change and do not claim a direct 4,890.729 ms mount comparison.

### Geometry exposure

For the calibrated run, record:

- gameplay viewport width/height;
- resolved row width;
- rendered row count;
- `staticInput.contentHeight` and/or `layout.totalHeight`;
- row pitch: `GameplayLayout.rowHeight + GameplayLayout.rowVerticalSpacing == 320 pt`.

Derive a conservative visible-row-capacity estimate only for context:

```text
visibleRowCapacity ~= min(renderedRows, ceil(viewportHeight / 320) + 1)
offscreenRowFraction ~= 1 - visibleRowCapacity / renderedRows
```

The extra row allows for partial-row exposure/top spacing. Label both values as geometry estimates. Do **not** multiply `offscreenRowFraction` by measured CPU time.

## Environment and interactive gate

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

Compile-check Release with `xcodebuild`; the authoritative measurement launch is Xcode Product > Profile.

A usable unlocked GUI is required for an **evidence-backed** keep-eager or row-laziness decision.

### Bounded environment-block fallback

HPA-581 already demonstrated that a locked/shielded session can defeat the interactive handoff. HPA-584 must not stall the roadmap forever on host state.

- If the first HPA-584 interactive attempt is blocked by environment/session state, explicitly verify the session is unlocked and input is available, then make **one** more HPA-584 attempt.
- If the second HPA-584 attempt is also environment-blocked, close HPA-584 as:

```text
Close without optimization — interactive evidence unavailable
```

That fallback:

- may cite the tracked HPA-581 worker-path report and deterministic geometry as context;
- must state that manual scrolling and live memory remain unverified;
- must not claim eager rendering is performant or memory-safe;
- creates no speculative row-laziness/resize optimization issue;
- unblocks HPA-583 by YAGNI: there is still no evidence justifying rendering architecture work.

This fallback is an execution escape hatch, not a substitute for successful profiling.

## Measurement contract

### Session A — Time Profiler at the pinned 900 pt / 156-row baseline

Start Time Profiler before entering gameplay.

Preparation is context rather than the main HPA-584 decision, so use:

- one warm-up/calibration entry;
- two measured entries at the pinned baseline window;
- a third measured entry only if the two measurements disagree materially in attribution or visible behavior.

Record the measured durations/range, prominent main-thread stacks, and confirmation that initial timeline `NotationLayoutEngine.layout` remains on the detached worker path.

Capture first mount separately. If a disposable `onAppear` marker is needed, it only marks **static-subtree insertion/appearance**. SwiftUI does not guarantee that a parent/container `onAppear` brackets descendant construction, so the marker cannot stand alone as mount-cost evidence and is never compositor-complete timing.

First-mount attribution comes from Time Profiler call paths through the actual eager units:

- `GameplayStaticNotationView.body`;
- `GameplayStaticNotationLayers.body`;
- `GameplayDrumNotationView.body`;
- full-chart primitive `ForEach`s;
- staff lines, bar lines, clefs/time signatures, and row anchors.

Continue at least 30 seconds of playback and note whether live updates repeatedly enter expensive full-static-tree construction.

Compare the old **4,890.729 ms** mount value only when the current chart, resolved 900 pt width, 156 rows, and measurement boundary are materially comparable.

### Session B — SwiftUI + real manual scrolling

Start a separate SwiftUI profiling session before entering gameplay at the pinned baseline window.

After mount:

1. play for at least 30 seconds;
2. let auto-scroll cross rows;
3. manually scroll vertically through distant content;
4. scroll horizontally when real content/window permits it;
5. let normal auto-scroll resume.

Classify interaction as:

- smooth;
- occasional minor hitch;
- repeated hitch.

Record the exact SwiftUI update/invalidation evidence available. Outer `sheetMusicView` activity alone is not proof that all primitive `ForEach`s rebuilt. If the SwiftUI instrument cannot expose useful invalidation detail, state that limitation instead of inferring success.

### Session C — live memory

Run a distinct Allocations session before entering gameplay at the pinned baseline window.

Record exact metric names/values for:

- pre-gameplay;
- post-mount;
- after 30+ seconds playback/manual scrolling;
- peak only when the tool explicitly reports a peak.

If Allocations cannot expose a credible live metric, use the Xcode memory gauge in a separate Release interaction and label the highest observed gauge value exactly as that.

For an evidence-backed macOS keep-eager close, credible macOS live-memory evidence is required. Missing macOS live-memory evidence blocks the evidence-backed decision and may only exit through the bounded environment/tooling fallback above.

### Natural resize / row repacking

Start from the calibrated **900 pt / 156-row** baseline, then widen the real macOS window through practical widths.

Because 900 pt is a floor, the packing-changing direction is **wider**, not narrower.

1. record resolved row width and rendered row count at each practical width;
2. stop at the first real row-count change and profile that resize;
3. if the widest practical host window still produces 156 rows, record the limitation only then;
4. never use the synthetic 3,000 pt probe as user-resize evidence.

For a real packing change, classify the dominant post-debounce cost:

1. **Layout CPU dominates** — current `cacheNotationLayout()` / `NotationLayoutEngine.layout` on `@MainActor`; not row-laziness evidence. A narrow follow-up reuses `GameplayNotationPreparer` plus the existing notation generation exactly as HPA-581 Task 7 already scoped.
2. **Full SwiftUI primitive-tree rebuild dominates** — contributes to the eager-tree evidence.
3. **Neither is material** — no follow-up.

### Physical iPad policy

A physical iPad run remains **advisory, not blocking** for this hobby-project decision.

If a usable physical iPad is readily available, repeat mount, 30 seconds playback, manual scrolling, and live memory. Any material device-specific evidence counts toward the decision.

If no physical iPad is available:

- do not block HPA-584 solely on hardware availability;
- do not claim iPad memory/frame performance is verified;
- record `iPad performance: unverified` in the result.

Simulator numbers remain functional/build evidence only.

This explicitly scopes an evidence-backed keep-eager result to the measured macOS hardware unless a physical iPad run is present.

## Decision rubric

### 1. Evidence-backed Keep eager

Choose **Keep eager** when the completed macOS sessions show:

- the calibrated 900 pt / 156-row first mount is not materially dominated by the eager primitive tree with visible impact;
- 30+ seconds playback does not repeatedly rebuild expensive full-static content with visible impact;
- real manual scrolling is responsive or hitches are not attributable to eager full-chart construction;
- credible macOS live memory is reasonable for the measured chart;
- geometry confirms the eager tree extends beyond the viewport, but the measured total eager-tree cost/interaction/memory does not justify new row grouping/laziness.

If no physical iPad was measured, the result must explicitly avoid any iPad performance claim.

### 2. Create one row-laziness follow-up

Create one focused follow-up only when real evidence shows the eager full-chart primitive tree is a dominant mount, scrolling/frame, or memory problem.

The follow-up is constrained to:

- pre-group immutable notation primitives by staff row;
- render row-grouped primitives in a lazy vertical container;
- keep horizontal geometry and stable notation IDs unchanged;
- preserve playhead alignment, auto-scroll, goldens/invariants, and accessibility.

Wrapping the current chart-wide `GameplayDrumNotationView` unchanged in a lazy container is not sufficient.

### 3. Close without optimization — interactive evidence unavailable

Use only after the two bounded HPA-584 GUI attempts both fail for environment/session reasons.

This is **not** an evidence-backed keep-eager claim. It records that interactive/memory evidence remained unavailable and defaults to no speculative optimization. HPA-583 becomes unblocked.

### Resize-only layout CPU follow-up

A material packing-changing resize dominated by main-actor layout CPU is orthogonal to the three outcomes above. If needed, create one narrow follow-up reusing `GameplayNotationPreparer` and the existing notation generation. It blocks HPA-583 until that rendering path settles.

## Result template

```markdown
## Post-HPA-581 notation profile

### Environment
- Commit / machine / OS / Xcode / Instruments / Release macOS
- HPA-584 GUI attempts: 1 | 2
- GUI session usable: yes/no
- Physical iPad: device + OS | unavailable

### Representative chart / pinned geometry
- soukyuu_e_no_shouka / MASTER / Expert
- Notes / controls / measures
- Gameplay geometry width / resolved row width
- Rendered rows
- Viewport height / static content height / layout total height
- Row pitch: 320 pt
- Visible-row-capacity estimate / off-screen-row-fraction estimate

### HPA-579 baseline
- Resolved row width / rows: 900 pt / 156
- Gameplay prepared: 267.857 ms median (264.074-269.534 ms)
- Initial mount: 4,890.729 ms
- Manual scroll: unavailable
- Peak live memory: unavailable

### Session A — Time Profiler
- Preparation runs + range; dominant main/background stacks
- Initial timeline layout worker check
- Ready -> static-subtree appearance marker: value or not used; insertion-only caveat
- First mount: full-chart primitive-tree attribution and visible observation
- 30+ s playback: static-tree call-path behavior

### Session B — SwiftUI
- Playback invalidation/update evidence
- Manual scrolling: smooth | occasional minor hitch | repeated hitch
- Attribution or instrumentation limitation

### Session C — memory
- Tool: Allocations | Xcode memory gauge
- Pre-gameplay / post-mount / playback+scroll values
- Peak: exact tool-reported value | unavailable

### Natural resize/repacking
- Width sweep / first row-count change, or widest-practical-width limitation
- If packing changed: layout CPU | SwiftUI full-tree rebuild | neither material
- Resize follow-up: issue identifier | none

### Decision
- HPA-584: Keep eager | Create row-laziness follow-up | Close without optimization — interactive evidence unavailable
- Scope: macOS measured; iPad verified/unverified
- Evidence/limitation: concise reason
- Row-laziness follow-up: issue identifier | none
- HPA-583: unblocked now | blocked by follow-up issue(s)
```

## Temporary instrumentation policy

- Prefer Instruments first.
- Reuse `Logger.info`; do not add a timing helper/permanent signpost layer.
- Use `ContinuousClock` only around a boundary the trace cannot isolate.
- Keep markers local to `GameplayView` / `GameplaySheetMusicView` where possible.
- A temporary `onAppear` marker is insertion/appearance evidence only, not a descendant-construction bracket.
- Keep the scoped `/tmp/hpa584-instrumentation.patch` backup pattern before reverting. It avoids hiding unrelated worktree changes in a broad stash and matches HPA-579's disposable-instrumentation workflow.
- Do not commit traces, screenshots, DerivedData, profiler exports, or ad-hoc metrics files.
- Restore all temporary instrumentation before the ticket closes.

## Acceptance criteria

- [ ] Current source/toolchain identity is recorded.
- [ ] The fixed Soukyuu MASTER chart is used.
- [ ] Before direct HPA-579 comparison, the real window is calibrated until resolved row width / rendered rows are **900 pt / 156**.
- [ ] Gameplay geometry width, resolved row width, rendered row count, viewport height, static content height, and 320 pt row pitch are recorded.
- [ ] Visible-row/off-screen-row geometry estimates are recorded as context and are **not** converted into a fabricated CPU share.
- [ ] Time Profiler, SwiftUI, and memory evidence use separate sessions.
- [ ] Preparation uses one warm-up plus two measured runs; a third is added only when attribution/visible behavior disagrees materially.
- [ ] First-mount evidence uses Time Profiler; any `onAppear` marker is explicitly insertion-only.
- [ ] At least 30 seconds of playback and real manual scrolling are observed.
- [ ] Credible macOS live-memory evidence is present for an evidence-backed keep-eager close.
- [ ] Natural resize begins from 900 pt / 156 rows and widens until the first real packing change or the widest practical host width.
- [ ] Resize layout CPU is kept separate from row-laziness evidence.
- [ ] Physical iPad evidence is included when available; absence is explicit and does not become an iPad performance claim.
- [ ] If two HPA-584 GUI attempts both fail for environment/session reasons, the ticket closes without speculative optimization and without claiming performance is acceptable.
- [ ] HPA-584 implements no virtualization, benchmark framework, CI performance gate, custom renderer, or unrelated optimization.
- [ ] The tracked HPA-581 profile report may be read as supporting evidence, but architectural requirements come from committed specs/plans.
- [ ] Temporary instrumentation/profiler artifacts are removed before close.
