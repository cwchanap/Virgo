# HPA-164 Measured Formatting and Shared Tick Geometry Implementation Plan

**Goal:** Replace Virgo's chart-wide fixed `TabGrid` with one package-owned content-aware formatter, make package tick geometry authoritative for notation and playhead positioning, and remove the fixed-grid notation compatibility path without pulling HPA-166's final beam/modifier/static-view migration into this PR.

**Architecture:** `RhythmLayoutSnapshot` remains Virgo's analyzed timing boundary. `VirgoNotationAdapter` converts that snapshot and numeric app layout settings into package-owned resolved notation values. `DrumNotation.NotationFormatter` formats exact time columns, local chord displacement, measure widths, rows and tick lookup off-main. Virgo composes the returned geometry with its existing stem/beam/mark renderer until HPA-166. There is exactly one formatter and one tick map.

**Baseline:** `main` at `8a29b68f7afeb29c162e2587fad26c192d71beda` after HPA-163 / PR #65.

**Spec:** `docs/superpowers/specs/2026-09-12-hpa-164-measured-formatting-shared-tick-geometry-design.md`

## Global constraints

- Exactly one PR for HPA-164. Planning and implementation continue on this same draft PR.
- Keep the existing single `DrumNotation` library target and single package test target.
- No second formatter, fallback grid, renderer protocol, feature flag, or old/new layout toggle.
- Do not infer rhythm, quantize ticks, convert BPM/seconds, or parse DTX in the package.
- Keep `RhythmLayoutSnapshot`, `NotationRhythmAnalyzer`, SwiftData and staff override persistence in Virgo.
- Keep `GameplayNotationPreparer` as the existing off-main pure-value worker and preserve generation rejection/cancellation behavior.
- Keep current beam grouping/topology in Virgo. Adapt coordinates only enough for beams/stems/flags to remain attached to package-positioned heads.
- Do not move the complete static notation view, staff/clef/bar presentation, or final beam/modifier parity from HPA-166.
- Delete the fixed-grid notation path instead of maintaining compatibility.
- Do not reintroduce HPA-581's removed `cachedBeatPositions` cache.
- Keep the current resolved row-width floor behavior; changing narrow-window product policy is out of scope.
- Keep all app `xcodebuild` test runs serial / non-parallel.

---

## File map

The exact split may be adjusted to stay under repository file/function length rules, but keep one package module and avoid tiny abstraction files.

**Create in `Packages/DrumNotation/Sources/DrumNotation/`**

- `Model/ResolvedNotation.swift` — package input values needed by formatting.
- `Layout/FormattedNotation.swift` — immutable rows/measures/columns/head geometry and tick lookup.
- `Layout/NotationFormatter.swift` — validation, column measurement, local displacement, measure sizing and row packing.

**Create in `Packages/DrumNotation/Tests/DrumNotationTests/`**

- `NotationFormatterTests.swift` — package-only formatting/row/tick tests.
- Add a separate formatter fixture helper only if the test file becomes unwieldy; do not create a general fixture framework.

**Modify in package**

- `Model/PrimitiveTypes.swift` only for small reusable package semantics such as voice if they belong beside existing primitive enums.
- `README.md` to document the HPA-164 formatter/tick lookup boundary.

**Modify in Virgo**

- `Virgo/layout/VirgoNotationAdapter.swift`
- `Virgo/layout/GameplayNotationPreparation.swift`
- `Virgo/layout/NotationLayout.swift`
- `Virgo/layout/NotationLayoutEngine.swift`
- `Virgo/layout/NotationLayoutEngine+Rests.swift`
- `Virgo/layout/NotationLayoutEngine+Controls.swift`
- `Virgo/layout/NotationLayoutEngine+Beams.swift` only where displaced-head/package anchors require coordinate adaptation.
- `Virgo/layout/NotationLayoutEngine+RhythmRendering.swift` only for package-positioned dots/tuplets/marks.
- `Virgo/viewmodels/GameplayViewModel+Notation.swift`
- `Virgo/viewmodels/GameplayViewModel+VisualUpdates.swift`
- `VirgoTests/VirgoNotationAdapterTests.swift`
- `VirgoTests/GameplayNotationPreparationTests.swift`
- `VirgoTests/NotationLayoutRhythmTests.swift`
- `VirgoTests/DrumTabRegressionInvariantTests.swift`
- `VirgoTests/DrumTabPlayheadAlignmentTests.swift`
- `VirgoTests/GameplayViewModelVisualUpdatesTests.swift`
- relevant golden/raster tests and fixtures.

**Delete or substantially retire**

- `Virgo/layout/NotationLayoutEngine+TabGrid.swift` after any timing helpers that still have a real owner are moved or deleted.
- `.legacy` members in `NotationLayoutTimingInput` / `NotationLayoutEngine`.
- fixed-grid-only tests such as overflow/LCM/layout assertions when they no longer describe supported notation behavior.

Do not mechanically keep a file just because old tests import its helpers.

---

## Task 1: Add the package resolved-input and formatted-output contract

**Files:**
- Create: `Packages/DrumNotation/Sources/DrumNotation/Model/ResolvedNotation.swift`
- Create: `Packages/DrumNotation/Sources/DrumNotation/Layout/FormattedNotation.swift`
- Modify: `Packages/DrumNotation/Sources/DrumNotation/Model/PrimitiveTypes.swift` if needed
- Modify: `Packages/DrumNotation/README.md`
- Create/Modify: package formatter tests

**Interfaces:**
- Consumes only package-owned values.
- Produces immutable `Sendable` geometry values and an in-measure tick lookup.
- Carries opaque caller IDs; no Virgo types.

- [ ] **Step 1: Write red package-boundary tests**

Cover construction of a minimal document with:

- positive `ticksPerWholeNote`;
- one measure with exact start/duration/meter/beat groups;
- one note with string/scalar ID, exact position, voice, staff step, package notehead/duration/stem values;
- one rest and one control with package-only values.

Also add compile-time `Sendable` coverage for the new input and output types.

Run:

```bash
swift test --package-path Packages/DrumNotation --filter NotationFormatterTests
```

Expected initially: FAIL because the types do not exist.

- [ ] **Step 2: Implement only the required package semantics**

Add a compact model equivalent to:

```swift
public struct NotationTickPosition: Hashable, Sendable {
    public let measureIndex: Int
    public let localTick: Int
    public let absoluteTick: Int
}

public enum NotationVoice: String, Sendable { case upper, lower }

public struct ResolvedNotationInput: Hashable, Sendable {
    public let ticksPerWholeNote: Int
    public let measures: [ResolvedMeasure]
    public let notes: [ResolvedNote]
    public let rests: [ResolvedRest]
    public let controls: [ResolvedControl]
}
```

Use a minimal package-owned engraving-support value rather than copying Virgo's diagnostic taxonomy.

Do not add BPM, seconds, DTX lanes, source model objects, SwiftData IDs, colors or views.

- [ ] **Step 3: Define the numeric formatting style and immutable result**

Add only scalar formatting inputs used by the algorithm, for example:

```swift
public struct NotationFormattingStyle: Hashable, Sendable {
    public let availableRowWidth: CGFloat
    public let staffSpace: CGFloat
    public let minimumInterColumnGap: CGFloat
    public let minimumQuarterNoteSpacing: CGFloat
    public let measureSpacing: CGFloat
    public let leadingMeasureInset: CGFloat
    public let trailingMeasureInset: CGFloat
}
```

The formatted result must expose:

- ordered rows;
- ordered measures with row/x/width and exact timing;
- logical columns with exact ticks and X;
- per-note visual head center X distinct from logical X;
- per-event geometry needed by Virgo's transitional renderer;
- a single `position(measureIndex:localTick:)` lookup returning row/X.

Avoid a public class hierarchy or mutable caches.

- [ ] **Step 4: Add validation tests**

Reject or explicitly fail for:

- nonpositive tick resolution;
- duplicate/unsorted measure identity that cannot be normalized deterministically;
- event tick outside its measure;
- mismatched `absoluteTick != measure.startTick + localTick`;
- invalid meter/duration values.

Sort valid caller arrays deterministically inside the formatter rather than depending on incidental input order.

- [ ] **Step 5: Document the public boundary**

Update `Packages/DrumNotation/README.md` with:

- resolved input → format → immutable geometry;
- exact tick lookup semantics;
- explicit statement that Virgo/rhythm inference/seconds are outside the package;
- HPA-166 still owns the complete static sheet and final beam/modifier migration.

- [ ] **Step 6: Commit this slice**

Suggested commit:

```text
feat: add resolved DrumNotation layout model
```

---

## Task 2: Implement logical columns and local notehead displacement

**Files:**
- Create/Modify: `Layout/NotationFormatter.swift`
- Modify: `Layout/FormattedNotation.swift`
- Modify: `Tests/DrumNotationTests/NotationFormatterTests.swift`

**Interfaces:**
- Consumes HPA-163 `PercussionGlyphMetrics` for natural notehead bounds.
- Produces one logical column per exact onset and optional per-head displacement.

- [ ] **Step 1: Add red exact-column tests**

Build package-only cases proving:

- kick/snare/hi-hat at the same tick share one `logicalColumnX`;
- different voices at the same tick still share the same logical column;
- event IDs/ticks are unchanged by formatting;
- deterministic output is independent of input array ordering.

- [ ] **Step 2: Add red displacement reference cases before implementing the rule**

Use the pinned HPA-163 VexFlow 5.0.0 semantics as the reference and record only the percussion cases needed here:

- adjacent staff-step heads with up stems;
- adjacent staff-step heads with down stems;
- non-adjacent heads that require no displacement;
- a same-onset three-head percussion chord.

Tests should assert direction/amount relationships and collision clearance, not a large copied VexFlow implementation.

If exact expected offsets are derived during implementation, keep the fixture explanation next to the test so HPA-166 can distinguish intentional formatter behavior from later beam parity work.

- [ ] **Step 3: Implement the smallest closed displacement rule**

Algorithm:

1. group same-onset heads by the stem/voice relationship required by the approved reference case;
2. start every head at logical X;
3. use the HPA-163 natural glyph bounds to detect adjacent-head collision;
4. shift only the head(s) required by the reference rule by the minimum deterministic amount plus the package's small head-clearance gap;
5. retain logical X separately.

Do not move stems/beams or introduce generic chord-layout protocols.

- [ ] **Step 4: Compute column extents from actual geometry**

For each column, union horizontal requirements relative to logical X from:

- displaced notehead natural painted bounds;
- dots already declared by the resolved rhythm input;
- only the flag/control footprint needed to prevent adjacent-column collision in the current renderer.

Keep full-measure rest visual centering out of this pre-width column extent.

Add assertions that the stored extents contain every geometry item they claim to measure.

- [ ] **Step 5: Commit this slice**

Suggested commit:

```text
feat: format percussion time columns
```

---

## Task 3: Add per-measure spacing, row packing and authoritative tick lookup

**Files:**
- Modify: `Layout/NotationFormatter.swift`
- Modify: `Layout/FormattedNotation.swift`
- Modify: package formatter tests

**Interfaces:**
- Input: exact measure ticks + measured columns + available width.
- Output: independently sized measures, rows and the only tick→row/X mapping.

- [ ] **Step 1: Add red sparse-vs-dense width tests**

Construct adjacent measures where one has dense sixteenth-note content and the other has sparse quarter-note content.

Assert:

- the dense measure may grow locally;
- the sparse measure does not inherit the dense measure's spacing scale;
- both preserve exact logical time order;
- repeated formatting produces identical widths/positions.

This replaces the old chart-wide `tickWidth` invariant.

- [ ] **Step 2: Implement one-pass local spacing**

For each adjacent start/event/end anchor pair, use:

```text
rhythmicGap = minimumQuarterNoteSpacing * deltaTicks / quarter-note ticks
collisionGap = previous.rightExtent + minimumInterColumnGap + next.leftExtent
requiredGap = max(rhythmicGap, collisionGap)
```

Avoid assuming `ticksPerWholeNote % 4 == 0`; compute the ratio safely before converting to `CGFloat`.

Accumulate X left-to-right once. No global density scan and no iterative solver.

- [ ] **Step 3: Finalize measure-local special geometry**

After a measure width is known:

- center printed full-measure rests in the usable measure body;
- keep their logical tick anchor unchanged;
- finalize control/rest/note event X values that depend on the measure body;
- expose start/end anchors even for empty or control-only measures.

- [ ] **Step 4: Add greedy row packing**

Pack complete formatted measures using the caller-supplied resolved available width:

- preserve source order;
- include inter-measure spacing;
- never split measures;
- allow one over-wide measure to occupy a row alone at natural width.

Add controlled-width tests for one-row, wrap, alternating dense/sparse and over-wide cases.

- [ ] **Step 5: Implement the only tick lookup**

`FormattedNotation.position(measureIndex:localTick:)` must:

- return exact logical column X on exact anchors;
- linearly interpolate between nearest anchors inside the owning measure;
- resolve start/end of empty/control-only/trailing measures;
- never interpolate into another measure/row;
- reject non-finite input and define clamping behavior for tiny boundary drift explicitly.

Use `Double` local ticks for the live playhead while stored event anchors remain exact integer ticks.

Add tests for exact onset, between-onset, final-measure end and a row boundary.

- [ ] **Step 6: Add reflow identity tests**

Format the same resolved document at two widths and assert:

- event/column IDs and exact ticks are unchanged;
- row assignments may change;
- per-measure internal geometry remains deterministic for the same formatting style except row origin;
- tick lookup follows the new row after reflow.

- [ ] **Step 7: Commit this slice**

Suggested commit:

```text
feat: add measured notation rows and tick lookup
```

---

## Task 4: Extend VirgoNotationAdapter and route the off-main preparer through DrumNotation

**Files:**
- Modify: `Virgo/layout/VirgoNotationAdapter.swift`
- Modify: `Virgo/layout/GameplayNotationPreparation.swift`
- Modify: `Virgo/layout/NotationLayout.swift`
- Modify: `Virgo/layout/NotationLayoutEngine.swift`
- Modify/Create: `VirgoTests/VirgoNotationAdapterTests.swift`
- Modify: `VirgoTests/GameplayNotationPreparationTests.swift`

**Interfaces:**
- App snapshot/overrides/style → package resolved input/style.
- Package formatted result → existing app render primitives.
- No spacing policy in Virgo.

- [ ] **Step 1: Add red adapter preservation tests**

For representative snapshot values assert mapping preserves:

- `RhythmEventID` through a stable opaque scalar/string package ID;
- measure index, local tick and absolute tick;
- measure duration, meter and beat groups;
- upper/lower voice;
- staff step after applying app override;
- notehead family, duration, stem direction;
- dots and supported tuplet ratio/membership;
- rest visibility;
- stop/choke/damp/control identity needed by the transitional renderer;
- supported/unsupported engraving state.

Assert no test calls package rhythm inference because none should exist.

- [ ] **Step 2: Add adapter methods for resolved input and formatting style**

Keep the current primitive helpers; extend the same enum rather than creating a second adapter.

Suggested flow:

```swift
let packageInput = VirgoNotationAdapter.resolvedNotation(
    from: request.snapshot,
    notePositionOverrides: request.notePositionOverrides
)
let packageStyle = VirgoNotationAdapter.formattingStyle(from: request.style)
let formatted = try NotationFormatter.format(packageInput, style: packageStyle)
```

If the formatter uses a throwing validation API, treat invalid data as an explicit unsupported/fatal preparation result. Do not silently call old geometry.

- [ ] **Step 3: Embed/reference `FormattedNotation` in app `NotationLayout`**

The installed app layout needs direct access to the immutable package result for live tick lookup. Store that result (or a narrow immutable wrapper referencing the same anchor data) instead of reconstructing a second app tick table.

Keep existing app-rendered arrays for the transitional HPA-164 renderer.

- [ ] **Step 4: Compose package geometry into rendered app values**

Update timeline layout composition so:

- `RenderedMeasure` row/X/width comes from package formatted measures;
- `RenderedNoteHead.position.x` comes from package head geometry;
- app Y still derives from row + staff position;
- rests/controls use package event/logical geometry as appropriate;
- existing stems/beams/flags/ledger lines are built from the newly positioned heads;
- measure bars use formatted measure bounds, not a grid formula.

Do not copy the package spacing algorithm into `NotationLayoutEngine`.

- [ ] **Step 5: Keep the detached worker boundary intact**

`GameplayNotationPreparer.prepare` continues receiving only immutable request values and runs package formatting plus transitional app composition off-main.

Update comments/tests to assert the new package types and resulting app layout remain `Sendable` across this path.

- [ ] **Step 6: Run focused tests**

```bash
swift test --package-path Packages/DrumNotation

xcodebuild test \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'platform=macOS' \
  -parallel-testing-enabled NO \
  -only-testing:VirgoTests/VirgoNotationAdapterTests \
  -only-testing:VirgoTests/GameplayNotationPreparationTests \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

Expected: PASS before deleting old geometry.

- [ ] **Step 7: Commit this slice**

Suggested commit:

```text
feat: use DrumNotation formatter in gameplay preparation
```

---

## Task 5: Cut all live X consumers over and delete fixed-grid notation

**Files:**
- Modify: `Virgo/viewmodels/GameplayViewModel+VisualUpdates.swift`
- Modify: `Virgo/viewmodels/GameplayViewModel+Notation.swift`
- Modify: layout rests/controls/rhythm rendering files as needed
- Delete/retire: `NotationLayoutEngine+TabGrid.swift`
- Modify: `NotationLayout.swift` / `NotationLayoutEngine.swift`
- Modify affected app tests

**Interfaces:**
- Live playback seconds → existing timeline continuous tick → package `FormattedNotation.position(...)`.
- No `TabGrid.xPosition` or chart-wide `tickWidth` remains in supported notation.

- [ ] **Step 1: Route timeline purple playhead through the package mapping**

Replace:

```swift
cachedNotationLayout.tabGrid.xPosition(...)
```

with the installed formatted-notation lookup using the resolved timeline measure index/local continuous tick.

Use the returned row for the notation position where appropriate; do not calculate X independently.

- [ ] **Step 2: Update resize/reflow tests before broader deletion**

Add/adjust tests that:

1. prepare a timeline layout;
2. resolve an exact and an interpolated playhead X;
3. change row width through the existing deterministic test path;
4. verify layout reflows;
5. verify the playhead still resolves to the same musical tick/column in the newly installed layout.

Do not add a second playhead geometry cache.

- [ ] **Step 3: Remove production notation fallback to `.legacy`**

In `cacheNotationLayout()`:

- valid snapshot → package formatter path;
- no valid snapshot → keep the existing separate non-notation legacy beat presentation/runtime fallback, but do not invoke a second fixed-grid notation engine.

Preserve fatal/unsupported timing behavior already owned by the rhythm runtime; do not broaden this task into playback policy changes.

- [ ] **Step 4: Delete fixed-grid notation API and implementation**

Delete when callers are gone:

- `NotationLayoutTimingInput.legacy` and the enum itself if timeline is now the only notation input;
- `NotationLayoutInput(notes:...)` convenience initializer;
- `layoutLegacy`;
- `TabGrid`;
- global `tickWidth`, `ticksPerMeasure` compatibility wrappers and beat-fraction conversions;
- `buildTabGrid(notes:)`, `buildTabGrid(snapshot:)` and their fixed-grid width helpers;
- `buildMeasures` overloads whose only input is `TabGrid`.

If one math helper still has a legitimate caller after the cutover, move that helper to the true owner instead of leaving `NotationLayoutEngine+TabGrid.swift` as a compatibility shell.

- [ ] **Step 5: Migrate or delete legacy-constructor tests**

For every `NotationLayoutInput(notes:...)` test found on current main:

- geometry-only behavior → package formatter test;
- app integration behavior → build a minimal `RhythmLayoutSnapshot`/adapter request;
- fixed-grid overflow/LCM/tick-width compatibility behavior → delete unless the underlying timing validation is still owned elsewhere.

Do not preserve `legacyTicksPerMeasure` or `TabGrid.fallback` only to keep old unit tests green.

- [ ] **Step 6: Replace old regression invariant**

`DrumTabRegressionInvariantTests` should no longer assert one chart-wide tick scale.

Assert instead:

- logical X is monotonic inside each measure;
- same tick means same logical column;
- displaced head center may differ without changing logical X;
- neighboring formatted extents do not overlap;
- sparse measure width is independent from an unrelated dense measure;
- playhead lookup at an event tick equals that event's logical X;
- row wrapping does not change exact musical identity.

- [ ] **Step 7: Confirm no deleted cache is recreated**

Search for `cachedBeatPositions`; production should remain free of it. Tests should validate live lookup directly.

- [ ] **Step 8: Commit this slice**

Suggested commit:

```text
refactor: remove fixed-grid notation layout
```

---

## Task 6: Verify transitional beams, visual output and real-chart integration

**Files:**
- Modify only affected beam/rhythm-rendering code and tests
- Modify golden/raster fixtures as justified by intentional formatting changes

**Interfaces:**
- Existing beam topology consumes package-positioned heads.
- No HPA-166 topology rewrite.

- [ ] **Step 1: Add a displaced-head stem/beam attachment regression**

Use a same-onset chord that triggers package displacement and assert:

- stem starts from the package-derived displaced head anchor;
- existing beam/stem output remains finite and attached;
- the logical playhead column stays at the shared onset rather than following a displaced head.

If fixing the attachment requires changing beam grouping or secondary-hook policy, stop: that behavior belongs to HPA-166. Only correct coordinate assumptions in this PR.

- [ ] **Step 2: Run real-DTX and row/playhead integration tests**

At minimum run the suites covering:

- rhythm timeline → notation conversion;
- `NotationLayoutRhythmTests`;
- `DrumTabPlayheadAlignmentTests`;
- `GameplayViewModelVisualUpdatesTests`;
- real chart/golden fixture harness;
- generation/isolation tests from HPA-581.

Use multiple `-only-testing:` selectors in one serial invocation rather than separate parallel runs.

- [ ] **Step 3: Run raster/render probes before changing goldens**

Cover at least:

- sparse measure next to dense measure;
- same-onset chord with local displacement;
- multi-row wrap.

Inspect one generated macOS preview image from the existing rendering test/helper path. Verify spacing, bar boundaries, head/stem attachment and row transitions visually.

Do not introduce a new screenshot framework.

- [ ] **Step 4: Regenerate text goldens only after geometry is accepted**

Use the repository's existing golden update path, scoped to the golden suite, e.g.:

```bash
TEST_RUNNER_VIRGO_UPDATE_GOLDENS=1 xcodebuild test \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'platform=macOS' \
  -parallel-testing-enabled NO \
  -only-testing:VirgoTests/DrumTabGoldenTests \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

Review the diff; do not accept broad output churn unrelated to measured spacing/chord placement.

- [ ] **Step 5: Re-run focused render tests without update mode**

Expected: PASS with no golden mutation.

- [ ] **Step 6: Commit this slice**

Suggested commit:

```text
test: verify measured notation integration
```

---

## Task 7: Full verification and PR readiness

The draft PR does not run the normal CI jobs until it is marked ready, so local verification is the gate before that transition.

- [ ] **Step 1: Package tests**

```bash
swift test --package-path Packages/DrumNotation
```

Expected: PASS.

- [ ] **Step 2: SwiftLint**

```bash
swiftlint lint
```

Expected: no errors introduced by HPA-164.

- [ ] **Step 3: Full serial macOS unit/render suite**

Match CI:

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

Expected: PASS.

- [ ] **Step 4: iPad Simulator build**

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

Expected: PASS without changing deployment floors or device-family policy.

- [ ] **Step 5: Deletion/search audit**

Confirm production no longer contains supported notation dependencies on:

```text
TabGrid
tickWidth
NotationLayoutTimingInput.legacy
layoutLegacy
cachedBeatPositions
```

Historical docs may still mention them; do not rewrite old design history merely to make grep globally empty.

Also confirm package source does not import Virgo or app-specific modules/types.

- [ ] **Step 6: Scope audit against HPA-166**

Review the diff and remove/defer any change whose main purpose is:

- final beam grouping/parity;
- complete modifier migration;
- staff/clef/bar static drawing extraction;
- executable VexFlow tooling not consumed by HPA-164 tests;
- general renderer cleanup.

HPA-164 should end with one usable intermediate renderer, not the final HPA-166 architecture prematurely.

- [ ] **Step 7: Update PR body with verification evidence, then mark ready**

Keep this same PR for implementation. Once local verification passes, update the PR description with:

- final architecture decisions;
- intentional golden/visual changes;
- exact verification commands/results;
- anything explicitly deferred to HPA-166.

Then mark the PR ready and require GitHub Actions package tests, full macOS tests/archive and iPad build to pass.

---

## Acceptance checklist

- [ ] One `DrumNotation` package/module; no new target split.
- [ ] Package accepts resolved exact-tick percussion notation only.
- [ ] Same-tick events share one logical column.
- [ ] Required local head displacement is deterministic and does not change timing identity.
- [ ] Per-measure width comes from local rhythmic distance + measured collision needs.
- [ ] Dense measures do not globally widen sparse measures.
- [ ] Complete measures greedily wrap at available width; over-wide measures remain natural size.
- [ ] Exact/between-anchor tick lookup is package-owned and measure-local.
- [ ] Purple playhead and rendered event onsets use the same package geometry.
- [ ] Resize/reflow preserves event/tick identity and playhead alignment.
- [ ] Existing off-main preparation/generation rejection remains intact.
- [ ] Existing stems/beams remain attached to package-positioned heads without pulling final topology into this ticket.
- [ ] Fixed-grid `.legacy` notation renderer and `TabGrid` are deleted.
- [ ] No `cachedBeatPositions` cache is reintroduced.
- [ ] Pure formatter tests live in the package; DTX/playhead/mounted-sheet tests stay in Virgo.
- [ ] Package tests, focused visual/golden checks, full serial macOS tests, SwiftLint and iPad build pass.
- [ ] HPA-166 remains the clear owner of final reusable static rendering and beam/modifier parity.
