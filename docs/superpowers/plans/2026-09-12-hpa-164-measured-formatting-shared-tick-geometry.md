# HPA-164 Measured Formatting and Shared Tick Geometry Implementation Plan

**Goal:** Replace Virgo's chart-wide fixed `TabGrid` with one package-owned measured formatter, make package tick geometry authoritative for notation/playhead X, reserve visible flag footprint, preserve one undisplaced stem axis for displaced seconds, and remove fixed-grid notation without pulling HPA-166's topology/static-view migration into this PR.

**Architecture:** `RhythmLayoutSnapshot` remains Virgo's analyzed timing boundary. Virgo performs an X-independent beam-topology prepass, expands trailing measures, applies staff overrides, filters formatter input, resolves visible flag footprint, and maps one numeric style through `VirgoNotationAdapter`. `DrumNotation.NotationFormatter` owns logical columns, staff-second head displacement, note/dot/rest/visible-flag collision measurement, per-measure width, row packing and tick lookup. `GameplayNotationPreparer` composes that geometry with existing Virgo Y/stem/beam/tuplet/control rendering and returns one `NotationLayout`.

**Baseline:** `main` at `8a29b68f7afeb29c162e2587fad26c192d71beda` after HPA-163 / PR #65.

**Spec:** `docs/superpowers/specs/2026-09-12-hpa-164-measured-formatting-shared-tick-geometry-design.md`

## Global constraints

- Exactly one PR for HPA-164; implementation continues on this draft PR.
- Keep the existing single `DrumNotation` library target and package test target.
- No second formatter, fallback grid, feature flag, old/new toggle, or generalized solver.
- Package code receives already-resolved exact measure/local ticks; no DTX parsing, rhythm inference, BPM/seconds conversion or re-quantization.
- Keep `RhythmLayoutSnapshot`, source voice/tuplet/control semantics, SwiftData and staff-override persistence in Virgo.
- Do not publish package `NotationVoice`, engraving-support mirror, beat groups, tuplets, redundant absolute tick, or stringified event IDs.
- Keep `GameplayNotationPreparer` as the single pure-value preparation/composition operation used by both detached initial preparation and synchronous relayout.
- Keep beam topology in Virgo. A pre-format topology pass may classify visible flag footprint because it is X-independent; actual topology/drawing still stays app-owned.
- Same-stem staff seconds may displace noteheads, but stems/beams remain on the undisplaced stem-side axis.
- HPA-164 collision measurement covers noteheads, dots, printed rests and visible uncovered flags. Tuplets, stop/control marks, articulations, warnings and feel marks stay HPA-166/app scope.
- `minimumInterColumnClearance` is edge-to-edge clearance; default 8pt. Never map old 28pt center pitch into it directly.
- Every package X is sheet-local and includes `rowLeadingInset`; Virgo applies no post-format X transform.
- Delete fixed-grid notation rather than preserving compatibility.
- Do not reintroduce `cachedBeatPositions`.
- Preserve the app's existing 900pt row-width floor before formatting.
- All app `xcodebuild` tests remain serial/non-parallel.

---

## File map

**Create in `Packages/DrumNotation/Sources/DrumNotation/`**

- `Model/ResolvedNotation.swift` — compact formatter-only input values.
- `Layout/FormattedNotation.swift` — immutable measure/column/head/event geometry and tick lookup.
- `Layout/NotationFormatter.swift` — validation, displacement, measurement, spacing and row packing.

**Create/modify package tests**

- `Packages/DrumNotation/Tests/DrumNotationTests/NotationFormatterTests.swift`.
- Add one small fixture helper only if the test file becomes unwieldy.

**Modify in package**

- `README.md` for the HPA-164 formatter/tick contract.
- Existing primitive metrics only when needed; do not add a parallel glyph geometry API.

**Modify in Virgo**

- `Virgo/layout/VirgoNotationAdapter.swift`
- `Virgo/layout/GameplayNotationPreparation.swift`
- `Virgo/layout/NotationLayout.swift`
- `Virgo/layout/NotationLayoutEngine.swift`
- `Virgo/layout/NotationLayoutEngine+Rests.swift`
- `Virgo/layout/NotationLayoutEngine+Controls.swift`
- `Virgo/layout/NotationLayoutEngine+Beams.swift` for stem-axis coordinate assumptions only
- `Virgo/layout/NotationLayoutEngine+RhythmRendering.swift` where existing marks consume positioned primitives
- `Virgo/viewmodels/GameplayViewModel+Notation.swift`
- `Virgo/viewmodels/GameplayViewModel+VisualUpdates.swift`
- affected Virgo tests/goldens/raster fixtures

**Delete or retire**

- `Virgo/layout/NotationLayoutEngine+TabGrid.swift` once useful helpers move to real owners.
- `.legacy` notation members in `NotationLayout` / `NotationLayoutEngine`.
- fixed-grid-only tests and compatibility overloads.

---

## Task 1: Freeze the minimal package model and coordinate space

**Files:** `ResolvedNotation.swift`, `FormattedNotation.swift`, package README/tests.

- [ ] **Step 1: Add red public-boundary tests**

Construct one package-only document with:

- positive `ticksPerWholeNote`;
- exact measure index/start/duration;
- one note with integer ID, measure/local tick, stem direction, staff step, notehead style, duration, dots, optional visible flag duration;
- one **printed** rest with integer ID, timing/duration/dots/full-measure state;
- one control onset with integer ID.

Add compile-time `Sendable` coverage.

- [ ] **Step 2: Add only formatter-needed types**

Use the compact shape:

```swift
public struct NotationTickPosition: Hashable, Sendable {
    public let measureIndex: Int
    public let localTick: Int
}

public struct ResolvedMeasure: Hashable, Sendable {
    public let index: Int
    public let startTick: Int
    public let durationTicks: Int
}

public struct ResolvedNote: Hashable, Sendable {
    public let id: Int
    public let position: NotationTickPosition
    public let stemDirection: NotationStemDirection
    public let staffStep: Int
    public let noteheadStyle: PercussionNoteheadStyle
    public let duration: NotationDuration
    public let dotCount: Int
    public let visibleFlagDuration: NotationFlagDuration?
}
```

`ResolvedRest` contains integer ID, position, duration, dot count, and `isFullMeasure`. Do not add `isPrinted`; Virgo filters hidden rests. `ResolvedControl` contains integer ID + position.

Do not add package voice, engraving support, beat groups, tuplets, app diagnostics, absolute tick, BPM/seconds, DTX lanes, or source models.

- [ ] **Step 3: Define numeric style with named units**

```swift
public struct NotationFormattingStyle: Hashable, Sendable {
    public let availableRowWidth: CGFloat
    public let rowLeadingInset: CGFloat
    public let staffSpace: CGFloat
    public let stemWidth: CGFloat
    public let minimumInterColumnClearance: CGFloat
    public let minimumQuarterNoteSpacing: CGFloat
    public let measureSpacing: CGFloat
    public let leadingMeasureInset: CGFloat
    public let trailingMeasureInset: CGFloat
    public let rhythmDotRadius: CGFloat
    public let rhythmDotSpacing: CGFloat
}
```

Contract tests pin the default mapping used by Virgo:

```text
rowLeadingInset = 100
staffSpace = 20
stemWidth = 2
minimumInterColumnClearance = 8
minimumQuarterNoteSpacing = 50
measureSpacing = 12
leadingMeasureInset = 52
trailingMeasureInset = 0
```

Document that 8pt is edge-to-edge and derives from the old 28pt center pitch minus the common 20pt X-black width at staff-space 20. This is **not** a direct field rename.

- [ ] **Step 4: Define immutable output**

Expose ordered formatted measures/columns, per-note `headCenterX`, logical onset X, package-owned rest visual X, and `position(measureIndex:localTick:) -> row/X`.

Do **not** expose `stemColumnX` initially. The existing Virgo stem representative remains the shared stem-axis owner. Add such output only if a supported reference fixture proves the existing representative cannot express the stem axis.

- [ ] **Step 5: Add validation**

Reject invalid resolution, duplicate/invalid measures, and event `localTick` outside the owning measure. Derive absolute tick internally from measure start + local tick rather than accepting redundant input.

- [ ] **Step 6: Document and commit**

Suggested commit:

```text
feat: add compact DrumNotation formatter model
```

---

## Task 2: Build logical columns, displacement, and visible flag footprint

**Files:** formatter/output/package tests; package primitives reused as-is.

- [ ] **Step 1: Add exact-column tests**

Prove same-tick kick/snare/hi-hat share one `logicalColumnX`, mixed stem directions receive no voice-based offset, integer IDs/ticks are unchanged, and input order does not affect output.

- [ ] **Step 2: Add VexFlow-reference staff-second tests**

Pin only the percussion cases HPA-164 needs:

- up-stem second: bottom/stem-side head remains on base X; adjacent upper head displaces to the VexFlow side;
- down-stem second: top/stem-side head remains on base X; adjacent lower head displaces to the VexFlow side;
- non-adjacent same-stem heads remain centered;
- longer adjacent chains follow the same deterministic VexFlow alternation;
- mixed-stem same-tick chord remains on one logical timing column.

Assert the shifted amount preserves slight overlap/touch with the shared stem axis rather than moving the stem itself.

- [ ] **Step 3: Implement the closed displacement rule**

Use `NotationStemDirection`, `staffStep`, HPA-163 natural head bounds and `stemWidth`; no package voice enum and no generic chord solver.

Store only visual `headCenterX`; `logicalColumnX` is unchanged.

- [ ] **Step 4: Add red flag-footprint tests**

Package-only cases:

- isolated eighth/sixteenth/32nd/64th visible flag expands the correct side of the column using `PercussionGlyphMetrics.flag`;
- fully beamed note (`visibleFlagDuration = nil`) pays no flag width;
- partially uncovered flag reserves one eighth-component horizontal footprint;
- adjacent next column clears visible flag ink by at least `minimumInterColumnClearance`.

- [ ] **Step 5: Measure collision geometry**

Union:

- displaced notehead bounds;
- dot footprint;
- printed-rest bounds;
- visible flag bounds positioned from the shared stem axis and package flag attachment metrics.

Controls add timing anchors but zero collision width. Keep tuplets, stop/choke/damp marks, articulations, warnings and feel marks out of this formatter.

- [ ] **Step 6: Commit**

Suggested commit:

```text
feat: measure percussion onset columns
```

---

## Task 3: Add per-measure spacing, row packing and tick lookup

- [ ] **Step 1: Add sparse-vs-dense tests**

Assert dense local content can expand without imposing its scale on a sparse neighbor.

- [ ] **Step 2: Implement one-pass gap rule**

```text
rhythmicGap = minimumQuarterNoteSpacing * deltaTicks * 4 / ticksPerWholeNote
collisionGap = previous.rightExtent + minimumInterColumnClearance + next.leftExtent
requiredGap = max(rhythmicGap, collisionGap)
```

Keep integer/rational safety until final `CGFloat`. No global density scan or iterative relaxation.

- [ ] **Step 3: Lock the 16-sixteenth numeric regression before integration**

At the default style, construct the same content as `sixteenth-run-4-4` measure 0 and assert:

```text
leading inset                         52
15 X-black note intervals   15 * 28 = 420
last head -> end anchor               18
----------------------------------------
measure width                        490
```

Use a small floating tolerance. Also assert a measure at X=100 ends at X=590, safely inside the 900pt row.

This test exists before any golden regeneration.

- [ ] **Step 4: Finalize special rest geometry**

Center full-measure rests only after width is known while preserving their logical timing anchor.

- [ ] **Step 5: Reuse greedy row packing with package widths**

First measure X = `rowLeadingInset`; include `measureSpacing`; never split a measure; allow one over-wide measure alone. Package output includes final row origin.

- [ ] **Step 6: Implement the only tick lookup**

Exact anchor → logical X; between anchors → in-measure interpolation only; empty/trailing/control-only measures resolve through start/end anchors; no row/measure crossing; non-finite input rejected.

- [ ] **Step 7: Add reflow identity tests and commit**

IDs/ticks remain stable at two widths; row assignments may change; lookup follows the new row.

Suggested commit:

```text
feat: add measured notation rows and tick lookup
```

---

## Task 4: Add the Virgo pre-format projection and one preparation route

**Files:** adapter, preparer, focused tests.

- [ ] **Step 1: Add adapter tests for trimmed input**

Assert:

- `RhythmEventID.rawValue` maps directly to integer note/control IDs;
- measure/local tick survives; absolute tick is derivable, not copied;
- staff override → `staffStep` survives;
- notehead style, stem direction, duration/dots survive;
- hidden rests are filtered; printed/full-measure rest geometry survives;
- package model contains no voice/tuplet/beat-group/engraving-support copy.

- [ ] **Step 2: Move trailing-measure expansion before package conversion**

Reuse the current `expandedRhythmMeasures` behavior. The package receives the complete requested measure list but does not synthesize app timing policy.

- [ ] **Step 3: Compute visible flag classification before formatting**

Reuse the current timing/voice/beat-group topology inputs without X coordinates. Build the same `BeamTimelineEvent` semantics from the snapshot with provisional row identity, run `NotationBeamTopologyBuilder`, and derive per-stem-group uncovered levels.

Map those to `visibleFlagDuration`:

- none / fully covered → nil;
- all expected levels uncovered → canonical duration flag;
- partial uncovered → `.eighth` component footprint.

Do not move topology types into `DrumNotation`.

- [ ] **Step 4: Add topology/flag-policy consistency tests**

Cover isolated, fully beamed and partially beamed cases. Assert the pre-format `visibleFlagDuration` classification agrees with the horizontal glyph family that current post-format `VirgoNotationAdapter.flagPaintCommands` will paint.

- [ ] **Step 5: Make `VirgoNotationAdapter.formattingStyle(...)` the only style mapper**

It maps resolved row width plus the exact default values pinned in Task 1. No other app site constructs `NotationFormattingStyle`.

- [ ] **Step 6: Route both invocation contexts through one `GameplayNotationPreparer.prepare`**

Detached initial preparation and synchronous `cacheNotationLayout()` relayout must both use:

```swift
let prepared = GameplayNotationPreparer.prepare(request)
```

Inside that operation only:

```swift
let input = VirgoNotationAdapter.resolvedNotation(...)
let style = VirgoNotationAdapter.formattingStyle(...)
let formatted = try NotationFormatter.format(input, style: style)
let layout = composeVirgoLayout(snapshot: ..., formatted: formatted, ...)
```

No direct second `NotationLayoutEngine.layout` path may recreate style/formatting.

- [ ] **Step 7: Add route-equivalence test**

For the same request, synchronous and detached preparation produce identical package measure geometry, row-leading origin and logical tick lookup.

- [ ] **Step 8: Commit**

Suggested commit:

```text
feat: prepare measured notation through one adapter route
```

---

## Task 5: Compose package geometry without moving the stem axis

**Files:** `NotationLayout`, engine, beam/rest/control/rhythm rendering, focused tests.

- [ ] **Step 1: Copy package output directly**

| Value | Source |
| --- | --- |
| `RenderedMeasure.row/xOffset/width` | package formatted measure |
| `RenderedNoteHead.position.x` | package `headCenterX` |
| `RenderedNoteHead.position.y` | Virgo row + staff position |
| rest/control X | package timing/special visual geometry |
| measure bars | package measure bounds |
| installed live lookup | embedded same `FormattedNotation` |

No `contentStartX`, `tickWidth`, `leftMargin` or post-format X transform.

- [ ] **Step 2: Keep shared stem/beam X on the undisplaced representative**

Do **not** use the displaced head as the stem-axis source. Keep current `stemRepresentative` ordering and verify the VexFlow displacement rule leaves that stem-side representative undisplaced:

- up stem → current representative is lowest/stem-side head;
- down stem → current representative is highest/stem-side head.

`stemAnchor` remains representative head position + HPA-163 glyph stem anchor. Beam endpoints use the same axis.

- [ ] **Step 3: Add displaced-second regression**

For both up and down stems assert:

- one head has `headCenterX != logicalColumnX`;
- `stemRepresentative` is the undisplaced stem-side head;
- stem X equals the undisplaced representative's glyph anchor, not the displaced head center;
- both heads touch/overlap the shared stem by the pinned geometry rule;
- beam endpoint X equals that same stem X;
- playhead/logical onset X remains unchanged.

If this fails for a supported chord despite correct VexFlow ordering, stop and revisit the package output; do not silently teach `stemRepresentative` a second spacing algorithm.

- [ ] **Step 4: Compose existing app-only semantics**

Use the original snapshot for voice grouping, tuplets, warning/control semantics and other deferred marks. They consume positioned primitives but do not alter package spacing.

- [ ] **Step 5: Keep HPA-581 worker contract intact and commit**

Suggested commit:

```text
feat: compose measured notation geometry in gameplay
```

---

## Task 6: Dedicated legacy-test migration and fixed-grid deletion

This remains inside PR #66 as one separately reviewable commit. Do not split the ticket/PR and do not preserve a compatibility constructor just to reduce the diff.

- [ ] **Step 1: Freeze the current migration inventory before editing**

Run:

```bash
rg -n 'NotationLayoutInput\(notes:' VirgoTests
```

Start with this current-main disposition and append any additional exact matches:

| File | Disposition |
| --- | --- |
| `NotationLayoutEngineTests.swift` | move pure horizontal/measure-spacing cases to package; retained renderer/bounds behavior → snapshot/preparer; delete fallback/tickWidth compatibility |
| `NotationLayoutEngineChordAndBeamTests.swift` | snapshot/preparer integration; retain beam/stem topology and undisplaced-stem-axis regression |
| `NotationLayoutRestTests.swift` | pure horizontal rest geometry → package; voice/rest integration → snapshot |
| `NotationLayoutOffsetNormalizationTests.swift` | delete legacy-only normalization; relocate still-valid timing assertions to canonical rhythm tests |
| `NotationLayoutNotePositionOverrideTests.swift` | retain adapter/preparer integration for override → staff-step/Y |
| `NotationLayoutEngineTabGridOverflowTests.swift` | delete grid LCM/overflow behavior; relocate timing-limit validation if still meaningful |
| `BeamHookPreservationTests.swift` | retain app integration; migrate setup to snapshot/preparer; topology unchanged |
| `RhythmLayoutSnapshotBuilderTests.swift` | remove legacy layout construction; retain snapshot/adapter semantics |
| `RhythmRenderingTests.swift` | retain timeline integration; replace TabGrid X assertions with formatted lookup; tuplets/feel stay app-owned |

- [ ] **Step 2: Route live playhead through `FormattedNotation.position(...)`**

`calculateTimelinePurpleBarPosition` passes continuous `localTick: Double` directly. Delete the notation beat-fraction/grid conversion when no supported caller remains.

- [ ] **Step 3: Delete no-snapshot notation path**

Valid snapshot → same preparation route. No snapshot → empty notation + existing non-notation beat fallback. Do not format `cachedNotes`.

- [ ] **Step 4: Delete old notation geometry**

Remove when callers are gone:

- `NotationLayoutTimingInput.legacy` / obsolete enum;
- `NotationLayoutInput(notes:...)`;
- `layoutLegacy`;
- `TabGrid` / fallback;
- chart-wide `tickWidth` / compatibility `ticksPerMeasure`;
- `RenderedMeasure.contentStartX`;
- `NotationLayout.empty` fallback grid;
- `buildTabGrid(notes:)` / `buildTabGrid(snapshot:)`;
- fixed-grid measure builders;
- rest/control TabGrid overloads;
- old `cacheNotationLayout()` else branch.

Relocate surviving pure timing helpers to real owners.

- [ ] **Step 5: Replace old regression invariants**

Before any golden update assert:

- sparse named measure width < dense neighbor;
- adjacent note/dot/rest/**visible-flag** extents clear;
- default `sixteenth-run-4-4` first measure = 490pt and ends inside X=900;
- same tick → same logical X;
- mixed voices not shifted apart;
- displaced second keeps undisplaced shared stem/beam axis;
- playhead event tick = logical X;
- reflow preserves musical identity.

- [ ] **Step 6: Search audit**

Production should no longer depend on:

```text
TabGrid
tickWidth
RenderedMeasure.contentStartX
NotationLayoutTimingInput.legacy
layoutLegacy
cachedBeatPositions
```

Also search old rest/control TabGrid overloads, `TabGrid.tickIndex`, and fallback-grid state.

- [ ] **Step 7: Commit migration/deletion separately**

Suggested commit:

```text
refactor: remove fixed-grid notation layout
```

---

## Task 7: Visual, golden and real-chart verification

- [ ] **Step 1: Run numeric invariants first**

Do not enter golden update mode until the new formatter width/clearance/stem/flag assertions are green.

- [ ] **Step 2: Run focused real-DTX/HPA-581 integration suites**

Include rhythm timeline, `NotationLayoutRhythmTests`, playhead alignment, visual update, generation/isolation, beam/flag consistency and real-chart fixtures. Use one serial `xcodebuild` invocation with multiple `-only-testing:` selectors where practical.

- [ ] **Step 3: Run raster/render probes**

Check at least:

- sparse next to dense measure;
- 16-sixteenth run;
- isolated flagged notes;
- partially beamed uncovered flag;
- up/down displaced staff seconds;
- multi-row wrap.

Inspect the existing macOS preview path for spacing, bars, flag clearance, head/stem attachment and row origin. No new screenshot framework.

- [ ] **Step 4: Regenerate text goldens only after behavioral acceptance**

Use the existing `TEST_RUNNER_VIRGO_UPDATE_GOLDENS=1` path. Review the diff, then rerun without update mode.

The goldens are descriptive evidence after the numeric contracts, not the sole acceptance oracle.

- [ ] **Step 5: Commit**

Suggested commit:

```text
test: verify measured notation integration
```

---

## Task 8: Full verification and PR readiness

The PR remains draft until implementation and local verification are complete.

- [ ] `swift test --package-path Packages/DrumNotation`
- [ ] `swiftlint lint`
- [ ] Full serial macOS tests matching CI:

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

- [ ] iPad Simulator build:

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

- [ ] Scope audit: HPA-166 still owns beam-topology migration, tuplets/control/articulation footprint, full static sheet, and any broader VexFlow tooling.
- [ ] Update PR body with exact implementation/verification evidence, then mark this same PR ready and require GitHub Actions package/macOS/archive/iPad jobs to pass.

---

## Acceptance checklist

- [ ] One existing `DrumNotation` module; no target split.
- [ ] Package model is trimmed: integer IDs, no absolute tick, no engraving support, no hidden-rest bit, no voice/tuplet/beat-group copy.
- [ ] Visible uncovered flag footprint participates in measured column extents.
- [ ] Default edge-to-edge clearance is explicitly 8pt; old 28pt center pitch is not mapped directly.
- [ ] Default 16-sixteenth measure is 490pt and remains inside the 900pt row.
- [ ] Same-tick events share one logical column; mixed voices are not displaced apart.
- [ ] Same-stem adjacent staff steps may displace only their noteheads; shared stem/beam X remains on the undisplaced representative.
- [ ] Every package X is sheet-local through `rowLeadingInset`; Virgo adds no second offset.
- [ ] Dense measures do not globally widen sparse measures.
- [ ] Adjacent note/dot/rest/visible-flag extents satisfy clearance.
- [ ] `FormattedNotation.position(...)` is the sole supported notation tick→row/X lookup.
- [ ] Both synchronous relayout and detached initial preparation call the same `GameplayNotationPreparer.prepare` route and one `VirgoNotationAdapter.formattingStyle` mapper.
- [ ] No-snapshot gameplay invokes no notation formatter; non-notation beat fallback remains.
- [ ] `.legacy`, `TabGrid`, `contentStartX`, old beat-fraction notation conversion and compatibility-only overloads/tests are removed.
- [ ] Legacy-test migration is a dedicated commit with the per-file disposition reviewed independently.
- [ ] `cachedBeatPositions` is not reintroduced.
- [ ] Numeric invariants pass before golden regeneration.
- [ ] Package tests, focused visual/golden checks, full serial macOS tests, SwiftLint and iPad build pass.
- [ ] HPA-166 remains owner of topology migration, tuplets/control/articulation parity and final reusable static rendering.