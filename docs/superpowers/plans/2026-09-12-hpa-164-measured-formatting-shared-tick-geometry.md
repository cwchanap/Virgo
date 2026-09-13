# HPA-164 Measured Formatting and Shared Tick Geometry Implementation Plan

**Goal:** Replace Virgo's chart-wide fixed `TabGrid` with one package-owned measured formatter, make package tick geometry authoritative for notation/playhead X, and remove the fixed-grid notation compatibility path without pulling HPA-166's final beam/modifier/static-view work into this PR.

**Architecture:** `RhythmLayoutSnapshot` remains Virgo's analyzed timing boundary. `VirgoNotationAdapter` expands trailing measures, applies staff overrides, and maps only HPA-164 formatter inputs into `DrumNotation`. `NotationFormatter` owns logical columns, same-stem second displacement, note/dot/rest collision measurement, per-measure width, row packing and tick lookup. `GameplayNotationPreparer` then composes that geometry with the existing Virgo Y/stem/beam/mark renderer and returns one `NotationLayout`.

**Baseline:** `main` at `8a29b68f7afeb29c162e2587fad26c192d71beda` after HPA-163 / PR #65.

**Spec:** `docs/superpowers/specs/2026-09-12-hpa-164-measured-formatting-shared-tick-geometry-design.md`

## Global constraints

- Exactly one PR for HPA-164; implementation continues on this draft PR.
- Keep the existing single `DrumNotation` library target and package test target.
- No second formatter, fallback grid, feature flag, old/new toggle, or generalized solver.
- Package code receives already-resolved exact ticks; no DTX parsing, rhythm inference, BPM/seconds conversion or re-quantization.
- Keep `RhythmLayoutSnapshot`, source voice/tuplet/control semantics, SwiftData and staff-override persistence in Virgo.
- Do not publish a package `NotationVoice`; HPA-164 displacement uses package `NotationStemDirection` + `staffStep` only.
- Keep `GameplayNotationPreparer` as the off-main pure-value worker and preserve generation rejection/cancellation.
- Keep beam grouping/topology in Virgo. HPA-164 changes only coordinate assumptions needed to follow package-positioned heads.
- HPA-164 collision measurement covers noteheads, dots and printed rests only. Flags, tuplets, stop/control marks and articulation footprint stay HPA-166 scope.
- Every package X is sheet-local and already includes `rowLeadingInset`; Virgo must not apply an X transform after formatting.
- Delete fixed-grid notation rather than preserving compatibility.
- Do not reintroduce `cachedBeatPositions`.
- Preserve the app's current 900pt row-width floor before package formatting.
- All app `xcodebuild` tests remain serial/non-parallel.

---

## File map

**Create in `Packages/DrumNotation/Sources/DrumNotation/`**

- `Model/ResolvedNotation.swift` — compact formatter-only input values.
- `Layout/FormattedNotation.swift` — immutable measure/column/head/event geometry and tick lookup.
- `Layout/NotationFormatter.swift` — validation, measurement, displacement, spacing and row packing.

**Create/modify package tests**

- `Tests/DrumNotationTests/NotationFormatterTests.swift`.
- Add one small fixture helper only if the test file becomes unwieldy.

**Modify in package**

- `README.md` for HPA-164 public/layout contract.
- Existing primitive metric types only when the formatter needs an already-approved reusable scalar type.

**Modify in Virgo**

- `Virgo/layout/VirgoNotationAdapter.swift`
- `Virgo/layout/GameplayNotationPreparation.swift`
- `Virgo/layout/NotationLayout.swift`
- `Virgo/layout/NotationLayoutEngine.swift`
- `Virgo/layout/NotationLayoutEngine+Rests.swift`
- `Virgo/layout/NotationLayoutEngine+Controls.swift`
- `Virgo/layout/NotationLayoutEngine+Beams.swift` only for displaced-head coordinate assumptions
- `Virgo/layout/NotationLayoutEngine+RhythmRendering.swift` only where existing marks consume newly positioned primitives
- `Virgo/viewmodels/GameplayViewModel+Notation.swift`
- `Virgo/viewmodels/GameplayViewModel+VisualUpdates.swift`
- affected Virgo tests/goldens/raster fixtures

**Delete or retire**

- `Virgo/layout/NotationLayoutEngine+TabGrid.swift` once useful helpers are relocated.
- `.legacy` notation members in `NotationLayout` / `NotationLayoutEngine`.
- fixed-grid-only tests and compatibility overloads.

---

## Task 1: Freeze the package contract and coordinate space

**Files:**
- Create `Model/ResolvedNotation.swift`
- Create `Layout/FormattedNotation.swift`
- Modify package README/tests

**Interfaces:** package values only; immutable `Sendable`; no Virgo types.

- [ ] **Step 1: Add red public-boundary tests**

Construct one package-only document with:

- positive `ticksPerWholeNote`;
- exact measure start/duration;
- one note with opaque ID, tick, stem direction, staff step, notehead style, duration and dot count;
- one printed rest;
- one control onset;
- a minimal supported/warning/unsupported measure state if retained.

Add compile-time `Sendable` coverage.

- [ ] **Step 2: Add only formatter-needed input types**

Use a compact model equivalent to:

```swift
public struct NotationTickPosition: Hashable, Sendable {
    public let measureIndex: Int
    public let localTick: Int
    public let absoluteTick: Int
}

public struct ResolvedMeasure: Hashable, Sendable {
    public let index: Int
    public let startTick: Int
    public let durationTicks: Int
    public let engravingSupport: NotationEngravingSupport
}

public struct ResolvedNote: Hashable, Sendable {
    public let id: String
    public let position: NotationTickPosition
    public let stemDirection: NotationStemDirection
    public let staffStep: Int
    public let noteheadStyle: PercussionNoteheadStyle
    public let duration: NotationDuration
    public let dotCount: Int
}
```

`ResolvedRest` needs only opaque ID, exact position, glyph duration, dot count, printed/full-measure state. `ResolvedControl` needs only opaque ID + exact position for HPA-164.

Do **not** add package `NotationVoice`, beat-group arrays, tuplet membership, articulation/stop footprint, Virgo diagnostic arrays, BPM, seconds, DTX lanes or model IDs.

- [ ] **Step 3: Define the numeric style with one coordinate origin**

```swift
public struct NotationFormattingStyle: Hashable, Sendable {
    public let availableRowWidth: CGFloat
    public let rowLeadingInset: CGFloat
    public let staffSpace: CGFloat
    public let minimumInterColumnGap: CGFloat
    public let minimumQuarterNoteSpacing: CGFloat
    public let measureSpacing: CGFloat
    public let leadingMeasureInset: CGFloat
    public let trailingMeasureInset: CGFloat
    public let rhythmDotRadius: CGFloat
    public let rhythmDotSpacing: CGFloat
}
```

Contract tests must prove first-measure X, logical-column X, displaced-head X and `position(...)` X are all in the same sheet-local space and already include `rowLeadingInset`.

- [ ] **Step 4: Define immutable formatted output**

Expose:

- ordered formatted rows/measures;
- measure row/x/width/timing;
- exact logical columns;
- per-note `headCenterX` distinct from `logicalColumnX`;
- any package-owned special visual X needed for full-measure rests;
- `position(measureIndex:localTick:) -> row/X`.

Do not expose mutable caches or a second anchor API.

- [ ] **Step 5: Add validation**

Reject invalid tick resolution, measure duration/identity, out-of-measure event ticks, and inconsistent `absoluteTick`. Normalize valid caller array ordering deterministically.

- [ ] **Step 6: Document the boundary and commit**

Suggested commit:

```text
feat: add compact DrumNotation formatter model
```

---

## Task 2: Build logical columns and pin second-note displacement

**Files:** `NotationFormatter.swift`, `FormattedNotation.swift`, package tests.

- [ ] **Step 1: Add exact-column tests**

Prove:

- kick/snare/hi-hat at the same tick share one logical column;
- mixed stems/voices do not receive a timing/visual X offset merely because they are different voices;
- IDs/ticks are unchanged;
- input order does not affect output.

- [ ] **Step 2: Add VexFlow-reference tests for the only displacement HPA-164 owns**

Cover:

- same-stem adjacent `staffStep` heads with up stems;
- same-stem adjacent `staffStep` heads with down stems;
- non-adjacent same-stem heads staying centered;
- same-tick mixed-stem percussion chord staying on the shared center.

Record the small expected relationship/offset with the fixture. Do not import general chord-layout behavior.

- [ ] **Step 3: Implement the closed second rule**

Algorithm:

1. group same-onset notes by `stemDirection`;
2. sort by `staffStep`;
3. only adjacent staff steps (`abs(delta) == 1`) are displacement candidates;
4. use HPA-163 natural notehead bounds to compute the minimum deterministic shift matching the pinned reference;
5. store the shifted value as `headCenterX`; leave `logicalColumnX` untouched.

There is no package voice enum and no upper-left/lower-right voice offset.

- [ ] **Step 4: Measure only owned collision geometry**

Union horizontal extents from:

- displaced notehead natural bounds;
- dot footprint from `rhythmDotRadius`/`rhythmDotSpacing`;
- printed rest glyph bounds.

Controls create timing anchors but add zero collision width in HPA-164.

Explicitly do **not** measure flags, beams, tuplets, stop/choke/damp marks, articulations, warnings or feel marks.

- [ ] **Step 5: Commit**

Suggested commit:

```text
feat: format percussion onset columns
```

---

## Task 3: Add per-measure spacing, row packing and tick lookup

- [ ] **Step 1: Add sparse-vs-dense tests**

Assert a dense measure can expand without changing the width scale of a sparse neighbor.

- [ ] **Step 2: Implement the one-pass gap rule**

For adjacent anchors:

```text
rhythmicGap = minimumQuarterNoteSpacing * deltaTicks * 4 / ticksPerWholeNote
collisionGap = previous.rightExtent + minimumInterColumnGap + next.leftExtent
requiredGap = max(rhythmicGap, collisionGap)
```

Keep integer/rational safety until final `CGFloat` conversion. No global density scan or iterative relaxation.

- [ ] **Step 3: Finalize measure width and full-measure-rest visual X**

After internal columns are placed:

- include leading/trailing measure insets;
- center printed full-measure rests in the final measure body;
- keep their logical timing anchor unchanged;
- preserve explicit start/end anchors for empty/trailing/control-only measures.

- [ ] **Step 4: Greedily pack rows in the final coordinate space**

- first measure X on every row = `rowLeadingInset`;
- compare measure right edge against `availableRowWidth`;
- preserve measure order;
- include `measureSpacing`;
- never split a measure;
- an over-wide first measure stays natural width on its own row.

Package output X values already contain this origin.

- [ ] **Step 5: Implement the only tick lookup**

`FormattedNotation.position(measureIndex:localTick:)`:

- exact anchor → exact logical X;
- between anchors → linear interpolation inside that measure only;
- empty/trailing/control-only measures resolve through start/end anchors;
- no cross-measure or cross-row interpolation;
- reject non-finite input and document any tiny-boundary clamping.

Use `Double` for live local ticks; stored anchors remain exact integers.

- [ ] **Step 6: Add reflow identity tests**

Format the same input at two widths. IDs/ticks stay fixed; rows may change; lookup follows the new row. Do not assert one X-per-tick rate across the whole measure because collision-expanded intervals intentionally vary.

- [ ] **Step 7: Commit**

Suggested commit:

```text
feat: add measured notation rows and tick lookup
```

---

## Task 4: Extend VirgoNotationAdapter and make the composition seam explicit

**Files:** adapter, preparer, `NotationLayout`, `NotationLayoutEngine`, focused tests.

- [ ] **Step 1: Add adapter tests for formatter-needed values**

Assert:

- `RhythmEventID.rawValue` maps to a deterministic reversible opaque note ID;
- exact measure/local/absolute ticks survive;
- staff override → `staffStep` survives;
- notehead style, stem direction, duration/dots survive;
- printed/full-measure rest state survives;
- control onset identity survives;
- package input contains no copied voice/tuplet/beat-group model.

App source voice, tuplets, warning/control semantics remain available in the original snapshot for post-format composition.

- [ ] **Step 2: Move trailing-measure expansion before package formatting**

Reuse/move the current `expandedRhythmMeasures` behavior into the adapter/preparer side so the package receives the complete requested measure list, including empty trailing measures.

Do not make the package synthesize app timing policy.

- [ ] **Step 3: Map formatting style once**

`VirgoNotationAdapter` maps:

- resolved row width;
- `GameplayLayout.leftMargin` → `rowLeadingInset`;
- staff space;
- measure/content gaps/insets;
- rhythm-dot metrics.

The adapter contains no spacing algorithm.

- [ ] **Step 4: Route the preparer through package formatting**

```swift
let packageInput = VirgoNotationAdapter.resolvedNotation(...)
let packageStyle = VirgoNotationAdapter.formattingStyle(...)
let formatted = try NotationFormatter.format(packageInput, style: packageStyle)
```

Invalid package input becomes an explicit unsupported/fatal preparation result. Never call old geometry.

- [ ] **Step 5: Compose the exact output table**

Implement and test:

| Value | Source |
| --- | --- |
| `RenderedMeasure.row/xOffset/width` | copy package formatted measure |
| `RenderedNoteHead.position.x` | package `headCenterX` by opaque event ID |
| `RenderedNoteHead.position.y` | Virgo row + staff position |
| rests/controls X | package logical/special geometry |
| stems/beams/flags | current Virgo builders after heads are positioned |
| measure bars | package measure bounds |
| installed live tick lookup | embedded same `FormattedNotation` |

No `contentStartX`, `tickWidth`, `leftMargin` or other post-format X transform is allowed.

- [ ] **Step 6: Verify displaced-head beam attachment**

Current `stemAnchor` already derives X from `RenderedNoteHead.position.x`. Add a regression proving `stemRepresentative`/beam attachment continues using displaced head-center geometry and never logical-column X.

If a fix changes grouping/topology or hook policy, defer it to HPA-166.

- [ ] **Step 7: Keep the detached worker boundary unchanged**

The request/result remain immutable and `Sendable`; generation rejection/cancellation/install behavior stays HPA-581's design.

- [ ] **Step 8: Run focused tests and commit**

Suggested commit:

```text
feat: compose DrumNotation measured geometry in gameplay
```

---

## Task 5: Cut live X consumers over and delete the fixed-grid notation path

- [ ] **Step 1: Route timeline playhead directly through `FormattedNotation.position(...)`**

`calculateTimelinePurpleBarPosition` already has continuous `localTick: Double`; pass that directly to package lookup. Use returned X/row with no app-side offset.

Do not recreate a beat-position cache.

- [ ] **Step 2: Remove the legacy beat-fraction notation lookup**

Delete `TabGrid.tickIndex(forBeatWithinMeasure:)` and `calculateNotationPurpleBarPosition`'s beat-fraction/grid path when no supported notation caller remains.

The non-notation legacy beat UI may keep its own existing position logic.

- [ ] **Step 3: Remove the no-snapshot notation branch**

In `cacheNotationLayout()`:

- valid snapshot → package formatter path;
- no snapshot → clear/install `.empty` notation and leave existing non-notation beat fallback active.

Do not build `NotationLayoutInput(notes:cachedNotes...)`.

- [ ] **Step 4: Delete old notation geometry**

Remove when callers are gone:

- `NotationLayoutTimingInput.legacy` / timing enum if obsolete;
- `NotationLayoutInput(notes:...)`;
- `layoutLegacy`;
- `TabGrid` / `TabGrid.fallback`;
- chart-wide `tickWidth` and compatibility `ticksPerMeasure`;
- `RenderedMeasure.contentStartX`;
- `NotationLayout.empty`'s `tabGrid` field;
- `buildTabGrid(notes:)` / `buildTabGrid(snapshot:)`;
- fixed-grid measure builders;
- rest/control overloads that take `TabGrid`;
- `cacheNotationLayout()`'s old else branch.

Move any surviving pure timing helper to its true owner instead of preserving a compatibility file.

- [ ] **Step 5: Migrate/delete old tests**

For every `NotationLayoutInput(notes:...)` test:

- pure horizontal geometry → package test;
- app integration → snapshot + adapter/preparer test;
- fixed-grid LCM/tickWidth compatibility → delete unless its underlying timing validation has another real owner.

- [ ] **Step 6: Replace regression invariants**

Assert:

- logical X monotonic inside each measure;
- same tick → same logical column;
- mixed voices are not shifted apart;
- approved same-stem seconds may have displaced `headCenterX`;
- measured note/dot/rest extents do not overlap adjacent columns;
- sparse measure width is independent of unrelated dense measure;
- playhead at an event tick equals that event's logical X;
- row wrap/reflow preserves musical identity.

Do not assert uniform X-per-tick across collision-expanded intervals.

- [ ] **Step 7: Deletion search audit**

Production should no longer depend on:

```text
TabGrid
tickWidth
RenderedMeasure.contentStartX
NotationLayoutTimingInput.legacy
layoutLegacy
cachedBeatPositions
```

Also search for old `buildStopNotes` / rest overloads taking `TabGrid`, `TabGrid.tickIndex`, and `NotationLayout.empty` fallback grid state.

- [ ] **Step 8: Commit**

Suggested commit:

```text
refactor: remove fixed-grid notation layout
```

---

## Task 6: Verify real-chart and visual behavior without stealing HPA-166

- [ ] **Step 1: Focused composition regressions**

Cover:

- same-tick kick/snare/hi-hat logical alignment;
- same-stem second displacement + stem/beam attachment;
- sparse next to dense measure;
- controlled multi-row wrap;
- exact/interpolated playhead alignment before and after resize.

- [ ] **Step 2: Keep expected modifier limitations explicit**

If flags, tuplets, stop marks or articulations expose a horizontal collision because their footprint is not part of HPA-164 measurement, record/defer that parity issue to HPA-166. Fix only wrong coordinate transforms/anchors in HPA-164.

- [ ] **Step 3: Run real-DTX and HPA-581 integration suites**

At minimum include the existing rhythm timeline, `NotationLayoutRhythmTests`, playhead alignment, visual update, generation/isolation and real-chart/golden suites.

Use one serial `xcodebuild` invocation with multiple `-only-testing:` selectors where practical.

- [ ] **Step 4: Run raster/render probes before golden regeneration**

Inspect the existing macOS preview path. Check spacing, bars, head/stem attachment, row origin and row transitions.

No new screenshot framework.

- [ ] **Step 5: Regenerate text goldens only after visual acceptance**

Use the existing `TEST_RUNNER_VIRGO_UPDATE_GOLDENS=1` path, review the diff, then rerun without update mode.

- [ ] **Step 6: Commit**

Suggested commit:

```text
test: verify measured notation integration
```

---

## Task 7: Full verification and PR readiness

The PR remains draft while implementation is in progress, so local verification is the gate before marking it ready.

- [ ] **Package tests**

```bash
swift test --package-path Packages/DrumNotation
```

- [ ] **SwiftLint**

```bash
swiftlint lint
```

- [ ] **Full serial macOS suite**

```bash
xcodebuild test \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'platform=macOS' \
  -configuration Debug \
  -only-testing:VirgoTests \
  -parallel-testing-enabled NO \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  -destination-timeout 300
```

- [ ] **iPad Simulator build**

```bash
xcodebuild build \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO
```

- [ ] **Scope audit against HPA-166**

Remove/defer changes whose main purpose is final beam grouping/parity, flag collision layout, tuplet/stop/articulation footprint, complete staff/clef/meter/static-view extraction, or general renderer cleanup.

- [ ] **Update PR body with implementation/verification evidence, then mark ready**

Require GitHub Actions package tests, macOS tests/archive and iPad build to pass after the draft transition.

---

## Acceptance checklist

- [ ] One existing `DrumNotation` module; no target split.
- [ ] Package input contains only formatter-needed exact-tick values; no package voice/tuplet/beat-group copy.
- [ ] `rowLeadingInset` makes every package X directly sheet-local; Virgo adds no X offset.
- [ ] Same-tick events share one logical column; mixed voices are not displaced apart.
- [ ] Only approved same-stem adjacent staff-step heads receive local displacement.
- [ ] Formatter collision extents include noteheads, dots and printed rests only.
- [ ] Dense measures do not globally widen sparse measures.
- [ ] Complete measures wrap greedily; over-wide measures retain natural width.
- [ ] `FormattedNotation.position(...)` is the sole supported notation tick→row/X lookup.
- [ ] `RenderedMeasure` geometry is copied from package output.
- [ ] Stems/beams attach through displaced `RenderedNoteHead.position.x` without topology changes.
- [ ] No valid snapshot invokes no notation formatter; non-notation legacy beat fallback remains.
- [ ] `.legacy`, `TabGrid`, `contentStartX`, old beat-fraction notation conversion and compatibility-only overloads/tests are removed.
- [ ] `cachedBeatPositions` is not reintroduced.
- [ ] Pure formatter tests live in package; DTX/playhead/mounted-sheet tests stay in Virgo.
- [ ] Package tests, visual/golden checks, full serial macOS tests, SwiftLint and iPad build pass.
- [ ] HPA-166 remains owner of final reusable static rendering and beam/modifier/tuplet/mark parity.