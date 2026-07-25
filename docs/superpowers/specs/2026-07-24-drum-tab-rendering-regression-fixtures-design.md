# Drum Tab Rendering Regression Fixtures and Golden Coverage

**Linear:** [HPA-144](https://linear.app/cwchanap/issue/HPA-144/add-drum-tab-rendering-regression-fixtures-and-golden-coverage)
**Parent:** HPA-97 — Fix drum tab rendering: spacing, beams, flags, rests, and stop-note semantics
**Date:** 2026-07-24
**Status:** Approved

## 1. Context

HPA-144 is the last open child of HPA-97. All six implementation blockers are Done:

| Issue | Subject | PR |
| --- | --- | --- |
| HPA-139 | Normalize DTX parser/model data | #41 |
| HPA-140 | Fixed drum-tab grid and shared timeline-to-x mapping | #42 |
| HPA-141 | Same-time drum voices, notehead/stem placement | #43 |
| HPA-142 | Beat-group beaming, partial beams, hooks, flags, tails | #44 |
| HPA-143 | Voice-aware rests, stop/choke events, articulations | #45 |
| HPA-145 | Tuplets, dotted rhythms, compound meter, measure-length timing | #47 |

HPA-97 states golden/fixture coverage for the screenshot failure modes must exist before the
parent is considered complete. This spec defines that coverage.

## 2. Problem: what existing tests do not cover

The suite already has ~1,847 tests and ~10,500 lines of notation/rhythm test code. The individual
mechanisms are well covered. Two gaps remain, and they are the gaps that matter.

### 2.1 The production timing path is the least covered

`NotationLayoutEngine.layout(input:)` branches on `NotationLayoutTimingInput`
(`Virgo/layout/NotationLayout.swift:85`):

- `.timeline(RhythmLayoutSnapshot)` — what production gameplay uses
  (`Virgo/viewmodels/GameplayViewModel+Computations.swift:437`)
- `.legacy(notes:controls:timeSignature:)` — the fixed-measure compatibility path

`NotationLayoutTestSupport.layout(...)` routes through the **legacy** convenience initializer
(`Virgo/layout/NotationLayout.swift:138`), so the large layout suites that depend on it exercise the
compatibility path rather than the production one. `NotationLayoutRhythmTests` does use the timeline
path, but hand-constructs `RhythmLayoutSnapshot` from tick literals, bypassing
`NotationRhythmAnalyzer` and everything upstream of it.

The result: no test drives realistic DTX input through parse → normalize → resolve → analyze →
layout. That full path is exactly what the HPA-97 screenshots broke.

### 2.2 No whole-output lock

Every current assertion names a specific property. A spacing or beaming regression in a dimension
nobody thought to assert passes silently. Nothing pins the complete rendered geometry of a chart.

## 3. Approach

Three decisions were settled during design review.

**Golden form: textual layout digest.** Serialize `NotationLayout` to a stable, human-readable text
digest; commit one golden file per fixture; diff in tests. Deterministic, reviewable as a PR diff,
and free of font-rasterization and OS-version drift. HPA-144's acceptance criteria explicitly permit
this as "a documented alternative … if CI cannot support snapshot rendering reliably". Pixel-image
goldens were rejected: bundled `.ttf` rasterization and antialiasing vary by macOS/Xcode version,
and a one-pixel shift fails with no readable diff.

**Fixture input: DTX text.** Each fixture is a small DTX string run through the real parser. Several
required scenarios (lane `1C`, sparse high-resolution lanes, non-power-of-two grids) are
parser-and-normalization concerns that hand-built `[Note]` arrays would bypass entirely. This follows
the pattern already proven in `VirgoTests/DTXControlImportIntegrationTests.swift:19`.

**View layer: a thin ink probe.** A digest tests the layout engine, not whether the SwiftUI views
mount what it produced. Two fixtures additionally render through `ImageRenderer` and assert ink is
present in the expected note columns. This counts ink rather than comparing images, so it stays
tolerant of antialiasing and font drift while still catching "primitive computed but never mounted".

## 4. Architecture

### 4.1 Pipeline

The harness mirrors production stage for stage:

```
DTX text
  → DTXFileParser.parseChartMetadata(from:)
  → Chart + DTXChartData.toNotes(for:) / .toControlEvents(for:)   [inserted into a TestContainer]
  → RhythmTimelineResolver().resolve(chart:)                       → ResolvedChartRhythm
  → RhythmLayoutSnapshotBuilder.build(...)                         → RhythmLayoutSnapshot
  → NotationLayoutEngine().layout(input: .init(timing: .timeline(snapshot)))
  → NotationLayoutDigest.make(layout)                              → String
  → compare against VirgoTests/Goldens/<fixture>.txt
```

### 4.2 New components

| Component | Location | Kind | Purpose |
| --- | --- | --- | --- |
| `RhythmLayoutSnapshotBuilder` | `Virgo/layout/` | production | Snapshot assembly, shared by the view model and the harness |
| `DrumTabFixtureCatalog` | `VirgoTests/Fixtures/` | test | The 10 fixtures as DTX text + expectations |
| `DrumTabFixtureHarness` | `VirgoTests/Fixtures/` | test | Runs a fixture through the pipeline above |
| `NotationLayoutDigest` | `VirgoTests/` | test | `NotationLayout` → stable text |

### 4.3 The one production change

`makeRhythmLayoutSnapshot` is currently `private` on `GameplayViewModel`
(`Virgo/viewmodels/GameplayViewModel+Computations.swift:86–157`), together with its helper
`rhythmMeasuresApplyingWarnings` (`:166–188`). Its only view-model dependency is
`resolvedRhythmFeel()`; passing `feel` in as a parameter makes the whole thing pure.

Extract both into `Virgo/layout/RhythmLayoutSnapshotBuilder.swift`:

```swift
@MainActor
struct RhythmLayoutSnapshotBuilder {
    func build(
        resolvedRhythm: ResolvedChartRhythm,
        timeline: RhythmTimeline,
        feel: RhythmicFeel
    ) throws -> RhythmLayoutSnapshot
}
```

`GameplayViewModel+Computations` then calls it, passing `resolvedRhythmFeel()`. Behavior is
unchanged; this is a move, not a rewrite.

**Why this is load-bearing, not incidental refactoring.** Without it the harness must reimplement
~60 lines of snapshot assembly — the analyzer wiring, the warning merge, the three `compactMap`
projections. A divergence between that copy and production would leave the goldens passing while
production rendering broke, which defeats the purpose of the ticket. One code path is the only
configuration in which a green golden suite means anything.

Secondary benefit: `GameplayViewModel` is already split across six files for SwiftLint's type-body
limit (per `CLAUDE.md`), and this removes ~100 lines from that budget.

## 5. Fixture catalog

Ten fixtures, one per scenario in HPA-144. DTX lane IDs per `DTXLane`
(`Virgo/utilities/DTXFileParser.swift:161`): `11` hi-hat closed, `12` snare, `13` bass drum,
`14` high tom, `16` crash, `18` hi-hat open, `19` ride, `1A` left crash, `1B` left pedal,
`1C` left bass. Control lanes `21` stop / `22` choke / `23` damp require `#VIRGO_CONTROL: 1`
(`:236`). Measure length is channel `02` (`Virgo/utilities/DTXRhythmParser.swift:270`).

| # | Fixture | Exercises | Primary assertion |
| --- | --- | --- | --- |
| 1 | `same-time-trio` | Lanes 13+12+11 simultaneous on beats 1 and 3 | All three heads share one x column |
| 2 | `sixteenth-run-4-4` | 16 chips on lane 11 across one 4/4 measure | Four beat-scoped beam groups, not one full-measure beam |
| 3 | `mixed-eighth-sixteenth` | Eighth + two sixteenths per beat | Primary beams plus partial secondary beams/hooks |
| 4 | `sparse-hi-res-lane` | 64-position grid, 2 chips | Timing preserved; notes not degraded to 64ths |
| 5 | `triplet-grid` | 12-position (non-power-of-two) grid | Deterministic tuplet representation or documented fallback |
| 6 | `hihat-open-closed-pedal` | Lanes 18, 11, 1B | Three distinct mappings, distinct glyphs |
| 7 | `left-bass-1c` | Lane 1C | Imports as a playable bass/kick event, not dropped |
| 8 | `stop-choke-damp` | Control lanes 21, 22, 23 | Three stop marks, modeled separately from rests |
| 9 | `voice-rests` | Independent upper/lower voice gaps | Per-voice rests, computed independently |
| 10 | `multi-row-stable-widths` | Enough measures to wrap ≥2 rows, **mixing sparse and dense measures** | Uniform tick scale across all measures and rows |

Fixture 10 deliberately contains both a sparse and a dense measure so it can serve as the subject of
the spacing invariant in §7.1 without an eleventh fixture.

The catalog is split across two files (`DrumTabFixtureCatalog.swift`,
`DrumTabFixtureCatalog+Rhythm.swift`) to stay under SwiftLint's 600-line file warning and 300-line
type-body warning.

## 6. Digest format

One line per primitive, grouped by kind, with a header carrying grid and row structure.

Illustrative example (field names are normative; y values and staff steps are placeholders, x values
are arithmetically consistent with the header so the format can be checked by hand):

```
grid   ticksPerWholeNote=960 tickWidth=0.2500 leftPadding=12.00
row 0  measures=[0] contentWidth=252.00
meas   m0 ticks=960 sig=4/4 startX=12.00 groups=[0,240,480,720] engraving=supported
head   m0 t0000 x=12.00  y=140.00 kick   voice=lower glyph=filled step=0
head   m0 t0000 x=12.00  y=100.00 snare  voice=upper glyph=filled step=-4
head   m0 t0000 x=12.00  y=60.00  hiHat  voice=upper glyph=cross  step=-8
stem   m0 t0000 x=12.00  y0=60.00 y1=110.00 dir=up
beam   m0 level=1 x0=12.00 x1=72.00 y=58.00 group=0
rest   m0 t0240 x=72.00  dur=quarter voice=upper printed=true
stop   m0 t0480 x=132.00 y=40.00 kind=choke target=16
```

Every x above satisfies `x = startX + localTick × tickWidth` (tick 0 → 12.00, tick 240 → 72.00,
tick 480 → 132.00), which is the §7.1 alignment invariant restated as a readable file.

Determinism rules:

- Coordinates rounded to 2 decimal places, formatted with an explicit `%.2f` (no locale dependence).
- Primitives sorted by an explicit total-order key — `(kind, measureIndex, localTick, y, id)` — so
  neither SwiftData relationship ordering nor dictionary iteration can perturb output.
- No font metrics, no text measurement, no color values in the digest.
- Every field is derived from `NotationLayout` and `TabGrid` only.

### 6.1 Golden files and regeneration

Goldens live at `VirgoTests/Goldens/<fixture>.txt`, located via a `#filePath`-relative URL. This
avoids adding test resources to the Xcode project, matching how the suite already avoids bundling
concerns.

Regeneration is opt-in via the `VIRGO_UPDATE_GOLDENS=1` environment variable. When set, the test
writes the new golden **and still fails**, recording an `Issue` that names the rewritten file. CI
never sets the variable, so a regression cannot silently self-approve, and a developer regenerating
locally always sees which files changed before committing.

A missing golden file fails with an explicit "run with VIRGO_UPDATE_GOLDENS=1 to create" message
rather than silently passing.

## 7. Test files

Three new files, each kept under the 600-line SwiftLint file warning.

### 7.1 `DrumTabRegressionInvariantTests.swift`

The two screenshot failure modes from HPA-97, as named tests:

**Inconsistent spacing.** Using fixture 10 (mixed sparse/dense, multi-row):
- exactly one distinct `tickWidth` across the whole chart;
- equal tick deltas produce equal x deltas, compared between the sparse and the dense measure;
- `RenderedMeasure.durationTicks × tickWidth` matches measured content width per measure.

**Overlong connection bars.** Using fixtures 2, 3, 10:
- every beam's x-span ≤ its containing beat group's width, within a float tolerance;
- no beam crosses a beat-group, measure, row, or voice boundary;
- secondary beams do not span notes that lack that beam level.

Cross-cutting invariants over all ten fixtures, as a parameterized test:
- every note head's x equals `TabGrid.xPosition(in:localTick:)` for its own measure and tick;
- simultaneous events share one x column;
- `layout.paintedBounds` contains every primitive's `paintedBounds(style:)` — the containment
  property already used by `NotationLayoutDefensiveGuardTests.swift:117`.

### 7.2 `DrumTabGoldenTests.swift`

Ten digest comparisons, one per fixture, parameterized over the catalog.

### 7.3 `DrumTabRenderProbeTests.swift`

Ink probes on fixtures 2 (dense row) and 10 (multi-row), reusing the `ImageRenderer` approach at
`VirgoTests/SwiftUIRenderingNotationTests.swift:27`. For each expected note column x, assert ink
pixel count near that x is greater than zero. Guarded `#if os(macOS)`, consistent with the existing
render probes.

## 8. Playhead alignment

HPA-144 requires tests verifying playhead x alignment against rendered note columns. This is
**already partially covered**: `VirgoTests/RhythmTimelineIntegrationTests.swift:154` asserts
`viewModel.purpleBarPosition?.x == Double(laterHead.position.x)`.

`purpleBarPosition` is computed in `GameplayViewModel+VisualUpdates.swift:159` and requires a full
view model — SwiftData container, metronome, practice settings. Rather than build a second playhead
harness, extend the existing integration pattern to the dense-row and multi-row fixtures using
`GameplayViewModelTestHarness`. Two additional tests, added to
`RhythmTimelineIntegrationTests.swift` or a sibling file if it would exceed the line limit.

## 9. Determinism and CI

- All tests use Swift Testing (`@Test`, `#expect`, `#require`, `@Suite`), never XCTest.
- Fixtures are inserted into a per-test in-memory `ModelContainer` via `TestContainer`
  (`VirgoTests/TestHelpers.swift`). `RhythmTimelineResolver.resolve(chart:)` reads
  `chart.safeNotes` (`Virgo/utilities/RhythmTimelineResolver.swift:55`), so a detached `Chart` is not
  safe here — this also steers clear of the known flaky detached-`Chart.difficulty` crash that is red
  on `main` independent of this work.
- Suites that touch `@MainActor` view models or `ImageRenderer` are marked `.serialized`, matching
  `SwiftUIRenderingNotationTests`.
- Tests are run with `-parallel-testing-enabled NO` per `CLAUDE.md`.
- No network, no file system writes outside the goldens path under `VIRGO_UPDATE_GOLDENS=1`.

## 10. Acceptance criteria mapping

| HPA-144 criterion | Satisfied by |
| --- | --- |
| Geometry tests lock x alignment, beam grouping, flags/tails, rests, stop/choke | §7.1 invariants + §7.2 digests over all 10 fixtures |
| Fixture tests cover both screenshot failure modes | §7.1, explicitly named |
| Visual/snapshot coverage for a dense row and a multi-row chart, or a documented alternative | §7.3 ink probes, plus the textual digest as the documented alternative to pixel goldens (§3) |
| Playhead x alignment against rendered note columns | §8 |
| Deterministic in the existing Swift Testing setup | §9 |

## 11. Scope boundaries

**In scope:** the four components in §4.2, the three test files in §7, ten golden files, two playhead
tests, and the `RhythmLayoutSnapshotBuilder` extraction.

**Out of scope:**
- Changing rendering behavior. This ticket adds coverage. If a fixture reveals a genuine rendering
  bug, it is recorded as a follow-up Linear issue against HPA-97 and the golden captures current
  behavior with a comment marking it as suspect — goldens must not be used to quietly bless a bug,
  nor to block this ticket on an unrelated fix.
- Migrating the existing legacy-path layout suites to the timeline path. Worth doing, but it is a
  large mechanical change across ~10,500 lines of tests and belongs in its own ticket.
- Pixel-image golden comparison, rejected in §3.
- iPhone or iPad-simulator test targets; macOS is the development and CI target per `CLAUDE.md`.

**Accepted overlap:** some assertions will restate what the blocker PRs' unit tests already check.
That is intentional — these operate end-to-end at a different level, and HPA-144 asks for a coherent
named regression suite rather than the minimum non-redundant set.

## 12. Risks

| Risk | Mitigation |
| --- | --- |
| Goldens become noise developers regenerate reflexively | Regeneration always fails the test and names the file; digest diffs are readable so real changes are reviewable |
| Floating-point instability at the 2dp rounding boundary | Digest rounds via `%.2f`; the §7.1 property assertions use explicit tolerances rather than string equality |
| Fixture DTX does not parse as intended, producing vacuously passing tests | Each fixture asserts a non-zero expected note/control count before any geometry assertion, so a mis-authored fixture fails loudly |
| Extraction changes view-model behavior | Pure move with `feel` parameterized; existing `GameplayViewModel` suites act as the regression check |
| Ink probe flakiness on CI | Probe counts ink near expected columns rather than comparing images; thresholds are `> 0`, not exact |
