# Drum Tab Rendering Regression Fixtures and Golden Coverage

**Linear:** [HPA-144](https://linear.app/cwchanap/issue/HPA-144/add-drum-tab-rendering-regression-fixtures-and-golden-coverage)
**Parent:** HPA-97 — Fix drum tab rendering: spacing, beams, flags, rests, and stop-note semantics
**Date:** 2026-07-24
**Status:** Approved (revised after design review)

Citations below name symbols rather than line numbers wherever the symbol is unambiguous; line pins
rot as the files move.

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

HPA-97 states golden/fixture coverage for the screenshot failure modes must exist before the parent
is considered complete. This spec defines that coverage.

## 2. Problem: what existing tests do not cover

The suite already has ~1,847 tests and ~10,500 lines of notation/rhythm test code. The individual
mechanisms are well covered. Two gaps remain, and they are the gaps that matter.

### 2.1 The production timing path is the least covered

`NotationLayoutEngine.layout(input:)` branches on `NotationLayoutTimingInput`:

- `.timeline(RhythmLayoutSnapshot)` — what production gameplay uses (`GameplayViewModel+Computations`)
- `.legacy(notes:controls:timeSignature:)` — the fixed-measure compatibility path

`NotationLayoutTestSupport.layout(...)` routes through the **legacy** convenience initializer, so the
large layout suites depending on it exercise the compatibility path rather than the production one.
`NotationLayoutRhythmTests` does use the timeline path, but hand-constructs `RhythmLayoutSnapshot`
from tick literals, bypassing `NotationRhythmAnalyzer` and everything upstream of it.

The result: no test drives realistic DTX input through parse → project → resolve → analyze → layout.
That full path is exactly what the HPA-97 screenshots broke.

### 2.2 No broad output lock

Every current assertion names a specific property. A spacing or beaming regression in a dimension
nobody thought to assert passes silently.

The goal here is a *broad* geometry lock, not a total one, and the distinction is worth stating
plainly: the digest (§6) pins every primitive collection on `NotationLayout`, the grid, the resolved
style, and the layout's own dimensions. It does not pin anything downstream of layout — SwiftUI view
modifiers, colours, z-order, font rasterization, or the sheet chrome around the notation overlay. A
regression confined to those is out of the digest's reach by design (§7.3's probe covers the narrow
case of a primitive computed but never mounted). Claiming a "whole-output lock" would overstate it.

## 3. Approach

Three decisions were settled during design review.

**Golden form: textual layout digest.** Serialize the render result to stable, human-readable text;
commit one golden file per fixture; diff in tests. Deterministic, reviewable as a PR diff, and free of
font-rasterization and OS-version drift. HPA-144 explicitly permits this as "a documented
alternative … if CI cannot support snapshot rendering reliably". Pixel-image goldens were rejected:
bundled `.ttf` rasterization and antialiasing vary by macOS/Xcode version, and a one-pixel shift
fails with no readable diff.

**Fixture input: DTX text.** Each fixture is a small DTX string run through the real parser and the
real persistence projection. Several required scenarios (lane `1C`, sparse high-resolution lanes,
non-power-of-two grids) are parser-and-normalization concerns that hand-built `[Note]` arrays would
bypass entirely. The reference pattern is the timeline-path test in
`DTXControlImportIntegrationTests` that calls `chartData.persistenceProjection()` and
`chart.setRhythmMetadata(...)` before standing up a view model — **not** the first test in that file,
which uses `NotationLayoutTestSupport.layout(...)` and is therefore on the legacy path.

**View layer: a differential ink probe.** A digest tests the layout engine, not whether the SwiftUI
views mount what it produced. Two fixtures additionally render through `ImageRenderer` twice — once
normally, once with `noteHeads` emptied — and require a positive ink delta inside each head's painted
bounds (§7.3). It compares two live renders against each other rather than against a stored image, so
it stays tolerant of antialiasing and font drift while still catching "primitive computed but never
mounted".

## 4. Architecture

### 4.1 Pipeline

The harness mirrors the production import and layout path stage for stage:

```
DTX text
  → DTXFileParser.parseChartMetadata(from:)
  → DTXChartData.persistenceProjection()                  → DTXChartPersistenceProjection
  → Song + Chart(timeSignature: projection.timeSignature) [TestContainer, inserted + saved]
      chart.setRhythmMetadata(projection.chartMetadata)
      chart.notes         = projection.notes.map    { $0.makeNote(for: chart) }
      chart.controlEvents = projection.controls.map { $0.makeControl(for: chart) }
  → RhythmTimelineResolver().resolve(chart:)               → ResolvedChartRhythm
  → RhythmLayoutSnapshotBuilder().build(...)               → RhythmLayoutSnapshot
  → NotationLayoutEngine().layout(input: .init(
        timing: .timeline(snapshot),
        minimumMeasureCount: <fixture>,
        style: lockedStyle,                                 § 4.4
        notePositionOverrides: lockedOverrides))             § 4.4
  → NotationLayoutDigest.make(result)                      → String
  → compare against VirgoTests/Goldens/<fixture>.txt
```

**Why `persistenceProjection()` and not `toNotes`/`toControlEvents`.** This was corrected in review
and is load-bearing:

1. Without `setRhythmMetadata`, `chart.rhythmMetadataState` is `.missing`, so
   `RhythmTimelineResolver.resolve(chart:)` takes `resolveMissing` instead of `resolveValid` — a
   different code path from any real imported chart.
2. `toControlEvents` stamps `normalizedTicksPerMeasure` from the chip's **native `gridSize`**. Its own
   source comment states the value "is NOT comparable across control chips with different grid sizes"
   (`DTXFileParser.toControlEvents`). `persistenceProjection()` instead rescales every event onto the
   shared LCM timeline via `CanonicalRhythmProjection.normalizedTiming(for:)`. Fixture 8
   (stop/choke/damp) would therefore have exercised non-production control placement.
3. `persistenceProjection()` is what production actually calls — `LocalDTXFixtureImporter` and
   `ServerSongDownloader` both use it.

The harness must assert `resolved.availability == .valid` and `resolved.timeline != nil` **before**
any geometry assertion, so a fixture that silently degrades cannot pass vacuously (§5.1).

### 4.2 New components

| Component | Location | Kind | Purpose |
| --- | --- | --- | --- |
| `RhythmLayoutSnapshotBuilder` | `Virgo/layout/` | production | Snapshot assembly, shared by the view model and the harness |
| `DrumTabFixtureCatalog` (+`…+Rhythm`) | `VirgoTests/Fixtures/` | test | The 11 fixtures as DTX text + expectations |
| `DrumTabFixtureHarness` | `VirgoTests/Fixtures/` | test | Runs a fixture through §4.1, returns `FixtureRenderResult` |
| `NotationLayoutDigest` | `VirgoTests/` | test | `FixtureRenderResult` → stable text |

The harness returns a composite, not a bare layout — the §7.1 beam invariants and the digest header
need beat-group and engraving data that lives on the snapshot, not on the layout, and the §8 playhead
tests need the attached chart:

```swift
struct FixtureRenderResult {
    let chart: Chart                     // attached + saved; for view-model-level tests (§8)
    let layout: NotationLayout
    let snapshot: RhythmLayoutSnapshot   // beat groups, engraving support, feel
    let timeline: RhythmTimeline
    let style: NotationLayoutStyle
}
```

The `ModelContainer` backing `chart` must outlive the result, so the harness keeps it alive for the
duration of the test rather than letting it deallocate when `render(...)` returns.

### 4.3 The one production change

`makeRhythmLayoutSnapshot` is currently `private` on `GameplayViewModel`
(`GameplayViewModel+Computations`), together with its helper `rhythmMeasuresApplyingWarnings`. Its
only view-model dependency is `resolvedRhythmFeel()`; passing `feel` in as a parameter removes it.

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
unchanged: this is a move, not a rewrite.

Two constraints on the extraction, so it stays behavior-neutral:

- The current path calls `snapshot.logDiagnostics()` before returning. Keep that inside the builder.
- `@MainActor` is required because `ResolvedChartRhythm` is `@MainActor` and the builder reads
  SwiftData `Note` objects by identity through `noteByEventID`. It is not a pure free function and
  should not be described as one.

**Why this is load-bearing, not incidental refactoring.** Without it the harness must reimplement the
analyzer wiring, the warning merge, and the three `compactMap` projections. A divergence between that
copy and production would leave the goldens passing while production rendering broke, which defeats
the ticket. One code path is the only configuration in which a green golden suite means anything.

Secondary benefit: `GameplayViewModel` is already split across six files for SwiftLint's type-body
limit (per `CLAUDE.md`), and this removes ~100 lines from that budget.

### 4.4 Locked layout style

Production resolves style as
`NotationLayoutStyle.gameplayDefault.with(rowWidth: max(GameplayLayout.maxRowWidth, cachedLayoutRowWidth))`
and passes `notePositionOverrides`, which in normal operation come from
`DrumNotationSettingsManager.loadPositions()` — i.e. **user settings can perturb layout geometry**.

Goldens must not depend on ambient state. The harness pins both:

- `rowWidth` = `GameplayLayout.maxRowWidth` (900) exactly, declared as a named constant in the
  harness. Fixture 10 wraps rows and is width-sensitive; an unpinned width makes its golden
  machine-dependent.
- `notePositionOverrides` = `Dictionary(uniqueKeysWithValues: DrumType.allCases.map { ($0, $0.notePosition) })`,
  the same defaults production uses in its test-mode branch — never `loadPositions()`.

Any fixture needing a different width declares it explicitly in the catalog and encodes it in the
golden header.

## 5. Fixture catalog

Eleven fixtures: one per scenario in HPA-144, plus fixture 11 added in review (§5, note below). DTX lane IDs per `DTXLane`: `11` hi-hat closed, `12`
snare, `13` bass drum, `14` high tom, `16` crash, `18` hi-hat open, `19` ride, `1A` left crash,
`1B` left pedal, `1C` left bass. Control lanes `21` stop / `22` choke / `23` damp require
`#VIRGO_CONTROL: 1`. Measure length is channel `02`.

| # | Fixture | Exercises | Primary assertion |
| --- | --- | --- | --- |
| 1 | `same-time-trio` | Lanes 13+12+11 simultaneous on beats 1 and 3 | All three heads share one x column |
| 2 | `sixteenth-run-4-4` | 16 chips on lane 11 across one 4/4 measure | Four beat-scoped beam groups, not one full-measure beam |
| 3 | `mixed-eighth-sixteenth` | Eighth + two sixteenths per beat | Primary beams plus partial secondary beams and hooks |
| 4 | `sparse-hi-res-lane` | 64-position grid, 2 chips | Timing preserved; notes not degraded to 64ths |
| 5 | `triplet-grid` | 12-position (non-power-of-two) grid | Deterministic tuplet representation or documented fallback |
| 6 | `hihat-open-closed-pedal` | Lanes 18, 11, 1B | Three distinct mappings and glyphs |
| 7 | `left-bass-1c` | Lane 1C | Imports as a playable bass/kick event, not dropped |
| 8 | `stop-choke-damp` | Control lanes 21, 22, 23 | Three stop marks, modeled separately from rests |
| 9 | `voice-rests` | Independent upper/lower voice gaps | Per-voice rests, computed independently |
| 10 | `multi-row-stable-widths` | ≥2 wrapped rows, **mixing sparse and dense measures** | Uniform tick scale across all measures and rows |
| 11 | `isolated-flagged-notes` | One lone eighth and one lone sixteenth, each alone in its beat | Each renders a flag/tail; no zero-length beam |

Fixture 10 deliberately contains both a sparse and a dense measure so it can serve as the subject of
the spacing invariant in §7.1 without a further fixture.

**Fixture 11 exists because review found a real hole.** HPA-144 requires geometry tests to lock
"flags/tails", and HPA-142's criteria include "isolated eighth/sixteenth notes render tails/flags" —
but none of fixtures 1–10 is guaranteed to emit a single `RenderedFlag`. Fixture 1 is quarter notes
(no flag), fixture 2's sixteenths are fully beamed, and fixture 3's mixed beat beams within the beat
group. Supporting a `flag` digest line (§6.1) does not help if no golden ever contains one: a renderer
emitting zero flags could have established the initial goldens and satisfied every gate.
`NotationBeamTopologyTests` pins the upstream behavior — "Single eighth alone in a beat produces no
beam group (flag, not zero-length beam)" — so a lone beamable note is the input that forces the flag
path in `NotationLayoutEngine+Beams`.

**Catalog file split** (SwiftLint 600-line file / 300-line type-body warnings):

- `DrumTabFixtureCatalog.swift` — fixtures 1, 2, 3, 6, 7, 8, 11 (mapping, beaming, flags)
- `DrumTabFixtureCatalog+Rhythm.swift` — fixtures 4, 5, 9, 10 (grid resolution, rests, wrapping)

### 5.1 Per-fixture validity gates

A non-zero note count is necessary but not sufficient — a fixture that silently drops lane `1C` can
still have other notes and pass a count check. Each fixture therefore declares expected values, and
the harness asserts them before any geometry comparison:

| Fixture | Gate beyond `availability == .valid` |
| --- | --- |
| 1 | ≥6 heads across exactly 2 distinct `timeColumn` values |
| 2 | 16 heads, one measure, ≥4 beam groups |
| 3 | ≥1 beam with `kind == .forwardHook` or `.backwardHook` |
| 4 | exactly 2 heads; neither `rhythm.baseInterval == .sixtyfourth` |
| 5 | See §5.2 — **not** a free choice between tuplet and diagnostic |
| 6 | 3 heads with 3 distinct `(drumType, glyph)` pairs |
| 7 | ≥1 head with `drumType == .kick` **and** `sourceLaneID == "1C"` |
| 8 | exactly 3 stop notes, kinds `{stop, choke, damp}`; rest separation per §5.3 |
| 9 | ≥1 printed rest in each of `.upper` and `.lower` |
| 10 | `Set(measures.map(\.row)).count >= 2`; one `tickWidth` chart-wide |
| 11 | exactly 2 flags: one with `flagIndex` count matching an eighth, one matching a sixteenth; `layout.beams.isEmpty` |

### 5.2 Fixture 5: the fallback must not be a free pass

An earlier draft let fixture 5 pass on "≥1 `RenderedTuplet`, **or** an engraving-unsupported
diagnostic". Review correctly identified that as a hole: a future regression that degraded genuine
triplet engraving into the unsupported fallback would satisfy the second branch and pass, and the
golden would pin the degraded output as correct.

The gate is therefore conditional on engraving support, not a choice:

- The test first reads `snapshot.measures[triplet].engravingSupport`.
- If `.supported`, the fixture **must** produce ≥1 `RenderedTuplet` whose `ratio` matches the
  fixture's declared triplet ratio. A diagnostic instead is a failure, not an alternative.
- Only if `.unsupported(codes)` may it assert the diagnostic branch, and then it must additionally
  assert the specific expected `RhythmDiagnosticCode` — not merely that *some* diagnostic exists — and
  the golden carries a `# SUSPECT:` trailer (§11) recording that this fixture pins a fallback.

This keeps HPA-145's "documented conservative fallback" license intact without letting it silently
absorb a real regression. Which branch is live today is determined during implementation by running
the fixture; the spec deliberately does not guess.

### 5.3 Fixture 8: rest separation as a differential test

An earlier draft gated fixture 8 on "`layout.rests` unaffected", which review correctly identified as
not executable — unaffected relative to what? No baseline was defined, so an implementation could not
objectively demonstrate that control events stay separate from rest inference (HPA-143's core
requirement).

The gate is a differential render instead. The catalog declares fixture 8 as a DTX body plus a
*separable* control block, and the harness renders it twice:

1. **with** the `21`/`22`/`23` control chips;
2. **without** them, the playable lanes byte-identical.

The `rest`-line subsection of the digest must be **identical** across both renders, while run 1 has
exactly 3 `stop` lines and run 2 has none. This proves separation by construction rather than by
assertion, and fails loudly if control chips ever start feeding rest inference.

The committed golden is run 1. Run 2 is computed in-test and never committed, so this costs no extra
golden file.

## 6. Digest format

The digest has two clearly separated sections. Review established that beat-group, time-signature,
and engraving-support data live on `RhythmMeasure` inside the snapshot, **not** on `RenderedMeasure` —
so the earlier "derived from `NotationLayout` and `TabGrid` only" rule was self-contradictory. The
digest is therefore defined over `FixtureRenderResult` (§4.2), with each line labelled by its source.

### 6.1 Normative line kinds

Section `timeline` — from `RhythmLayoutSnapshot` / `RhythmTimeline`:

| Line | Fields |
| --- | --- |
| `tl-grid` | `ticksPerWholeNote`, `feel` |
| `tl-meas` | `measureIndex`, `startTick`, `durationTicks`, `sig`, `groups=[startTicks]`, `engraving` |

Section `layout` — from `NotationLayout`, `TabGrid`, and the locked style:

| Line | Source type | Fields |
| --- | --- | --- |
| `grid` | `TabGrid` | `ticksPerWholeNote`, `tickWidth`, `leftPadding` |
| `style` | `NotationLayoutStyle` | `rowWidth`, `overrides=default`, plus every geometry-affecting field: `minimumNoteColumnGap`, `minimumQuarterBeatGap`, `staffLineSpacing`, `noteHeadWidth`, `noteHeadHeight`, `stemLength` |
| `dims` | `NotationLayout` | `noteHeadSize`, `totalHeight`, `paintedBounds` |
| `row` | derived | `row`, `measures=[…]`, `contentWidth` |
| `meas` | `RenderedMeasure` | `measureIndex`, `row`, `xOffset`, `width`, `startTick`, `durationTicks`, `contentStartX` |
| `head` | `RenderedNoteHead` | `timeColumn`, `position`, `drumType`, `glyph`, `variant`, `voice`, `stemDirection`, `row`, `sourceLaneID` |
| `stem` | `RenderedStem` | `noteHeadIDs`, `direction`, `start`, `end` |
| `beam` | `RenderedBeam` | `noteHeadIDs`, `direction`, `level`, **`kind`**, `start`, `end`, `thickness` |
| `flag` | `RenderedFlag` | `noteHeadID`, `stemDirection`, `flagIndex`, `origin` |
| `rest` | `RenderedRest` | `timeColumn`, `voice`, `duration`, `durationTicks`, `visibility`, `position`, `tupletID` |
| `stop` | `RenderedStopNote` | `kind`, `targetLaneID`, `timeColumn`, `position`, `sourceLaneID` |
| `artic` | `RenderedArticulation` | `kind`, `sourceNoteHeadID`, `row`, `position` |
| `dot` | `RenderedRhythmDot` | `source`, `position`, `rowIndex` |
| `tuplet` | `RenderedTuplet` | `id`, `voice`, `ratio`, `memberEventIDs`, `isBracketVisible`, `labelPosition`, **`bracketPoints`**, `rowIndex` |
| `ledger` | `RenderedLedgerLine` | `row`, `start`, `end` |
| `bar` | `RenderedMeasureBar` | `row`, `x`, `isFinal` |
| `feel` | `RenderedFeelMark` | `feel`, `position`, `rowIndex` |
| `warn` | `RenderedRhythmWarning` | `scope`, `codes`, `rowIndex`, `displayMeasureNumber` |

`beam.kind` (`full` / `forwardHook` / `backwardHook`) and the `flag` line are mandatory: they are
precisely the partial-beam and tail behavior HPA-142 introduced, and a head/stem-only digest would
match despite a hook or flag regression.

`stem` serializes its own `start`/`end`, which are **not** the head centre — beam geometry operates on
`stemAnchor(for:).x` (`NotationLayoutEngine+Beams`), and the defensive-guard tests document that
distinction. Serializing the head x for a stem would make the goldens lie about alignment.

### 6.2 Illustrative example

Field names are normative. Numbers are illustrative but internally consistent, so the format can be
checked by hand. The `style` and `dims` lines are **abridged** here to keep the example readable — the
normative field lists are in §6.1:

```
tl-grid ticksPerWholeNote=960 feel=straight
tl-meas m0 startTick=0 durationTicks=960 sig=4/4 groups=[0,240,480,720] engraving=supported

grid    ticksPerWholeNote=960 tickWidth=0.2500 leftPadding=12.00
style   rowWidth=900.00 overrides=default
row     0 measures=[0] contentWidth=900.00
meas    m0 row=0 xOffset=0.00 width=252.00 startTick=0 durationTicks=960 contentStartX=12.00
head    m0 t0000 abs0000 x=12.00 y=140.00 kick  glyph=filled variant=normal voice=lower stem=up  row=0 lane=13
head    m0 t0000 abs0000 x=12.00 y=100.00 snare glyph=filled variant=normal voice=upper stem=up  row=0 lane=12
head    m0 t0000 abs0000 x=12.00 y=60.00  hiHat glyph=cross  variant=normal voice=upper stem=up  row=0 lane=11
stem    ids=[1,2] dir=up start=(17.50,60.00) end=(17.50,110.00)
beam    ids=[3,4] dir=up level=1 kind=full start=(17.50,58.00) end=(77.50,58.00) thickness=3.00
flag    head=7 dir=up index=0 origin=(137.50,40.00)
rest    m0 t0240 abs0240 voice=upper dur=quarter ticks=240 vis=printed pos=(72.00,90.00) tuplet=-
stop    m0 t0480 abs0480 kind=choke target=16 pos=(132.00,40.00) lane=22
bar     row=0 x=0.00 isFinal=false
```

Every note-column x satisfies `x = contentStartX + tickWithinMeasure × tickWidth` (tick 0 → 12.00,
240 → 72.00, 480 → 132.00) — the §7.1 alignment invariant restated as a readable file. Note that
`row.contentWidth` is 900.00 rather than 252.00 because `NotationLayout.contentWidth` is floored at
`GameplayLayout.maxRowWidth`; stem/beam x values are offset from head x by the stem anchor.

### 6.3 Determinism rules

- Coordinates rounded to 2 decimals and formatted with an explicit
  `Locale(identifier: "en_US_POSIX")` formatter, so a host locale can never emit `,` for `.`.
- Every collection sorted by an explicit total order before serialization. Tick-bearing primitives
  sort by `(measureIndex, tickWithinMeasure, y, id)`. Tickless primitives — `stem`, `beam`, `flag`,
  `ledger`, `bar`, `dot`, `tuplet` — have no `timeColumn` and sort by
  `(start.x | origin.x | position.x, then y, then discriminator, then id)`. This is required, not
  cosmetic: `noteHeadIDsByLayoutTick` is a `[Int: Set<UInt64>]` and SwiftData relationship order is
  not guaranteed.
- No font metrics, no text measurement, no colors.
- Style is serialized (`style` line) so a golden can never silently depend on an unpinned width.

### 6.4 Golden files and regeneration

Goldens live at `VirgoTests/Goldens/<fixture>.txt`, located via a `#filePath`-relative URL. This
avoids adding test resources to the Xcode project, matching how the suite already sidesteps bundling
concerns.

Regeneration is opt-in via `VIRGO_UPDATE_GOLDENS=1`. When set, the test writes the new golden **and
still fails**, recording an `Issue` naming the rewritten file. CI never sets it, so a regression
cannot silently self-approve, and a developer regenerating locally always sees which files changed
before committing. A missing golden fails with an explicit "run with `VIRGO_UPDATE_GOLDENS=1` to
create" message rather than passing.

### 6.5 Comparison failure output

A boolean `#expect(actual == expected)` on a multi-hundred-line string is close to undiagnosable, and
these digests are long by design. The comparison helper therefore does not compare whole strings — it
splits both sides on newlines and reports, in this order:

1. the fixture name and golden path;
2. a count of differing lines, and the line numbers of the first and last divergence — so a
   one-primitive shift is instantly distinguishable from a whole-chart reflow;
3. a unified-style diff limited to divergent lines with two lines of surrounding context, capped at 40
   emitted lines with an "and N more differing lines" tail so a total reflow cannot flood the log;
4. if lengths differ, the count on each side, stated separately from content differences — a missing
   `flag` line and a moved `flag` line are different bugs.

The cap exists so CI output stays usable; the full actual digest is always recoverable by rerunning
with `VIRGO_UPDATE_GOLDENS=1` and reading `git diff`.

## 7. Test files

Three new files, each under the 600-line SwiftLint file warning.

### 7.1 `DrumTabRegressionInvariantTests.swift`

The two screenshot failure modes from HPA-97, as named tests:

**Inconsistent spacing** — fixture 10 (mixed sparse/dense, multi-row):
- exactly one distinct `tickWidth` chart-wide;
- equal tick deltas produce equal x deltas, compared between the sparse and the dense measure;
- per measure, `(contentEndX - contentStartX) == CGFloat(durationTicks) * tickWidth` within tolerance.
  Expressed against `contentStartX` and the tick span, **not** `RenderedMeasure.width`, which
  includes bar-line and padding allowance and would fail for the wrong reason.

**Overlong connection bars** — fixtures 2, 3, 10. Review asked whether the cross-voice clause was
falsifiable. It is not, and the problem is broader than voice: `NotationBeamTopology`'s private
`GroupKey` partitions events by `measureIndex`, `row`, `voice`, `direction`, `beatGroupIndex`,
`beatGroupStartTick`, and `beatGroupDurationTicks`. A beam therefore **cannot** contain heads from two
measures, rows, voices, stem directions, or beat groups — that is dictionary-key construction, not
behavior. Asserting it over `noteHeadIDs` membership would be tautological and would read as stronger
coverage than it is.

The invariants are therefore split by what they can actually catch:

*Geometric (falsifiable — this is the screenshot failure mode).* The bug in the screenshots was beam
**geometry** extending past its members while membership stayed correct, so these carry the weight:
- each beam's `[start.x, end.x]` lies within the x-range spanned by its own members' stem anchors,
  plus at most the style's hook length for `forwardHook`/`backwardHook` kinds;
- each beam's x-span ≤ its containing beat group's x extent, derived from
  `snapshot.measures[…].beatGroups` via `TabGrid.xPosition(in:localTick:)` (beat groups are not on
  `RenderedBeam`);
- secondary beams (`level > 1`) do not span heads lacking that level.

*Structural partition guard (tautological today, kept deliberately).* One test asserts that every
beam's member heads agree on measure, row, voice, and stem direction. It is labelled in-code as a
guard against a future change removing a field from `GroupKey`, not as a behavioral invariant — so
nobody reads it as proof that cross-voice beaming was tested.

Cross-cutting invariants over all eleven fixtures, parameterized:
- every head's x equals `TabGrid.xPosition(in:localTick:)` for its own measure and tick;
- simultaneous events share one x column;
- `layout.paintedBounds` **contains** every primitive's `paintedBounds(style:)` — containment, as in
  `NotationLayoutDefensiveGuardTests`, not equality.

### 7.2 `DrumTabGoldenTests.swift`

Eleven digest comparisons, parameterized over the catalog, each preceded by its §5.1 validity gate (and
§5.2 for fixture 5). Mismatches report via the §6.5 diff helper, never a bare string equality.

### 7.3 `DrumTabRenderProbeTests.swift`

Ink probes on fixtures 2 (dense row) and 10 (multi-row), `#if os(macOS)`, using the `ImageRenderer`
approach in `SwiftUIRenderingNotationTests`. The existing helper there counts *yellow* pixels for a
different assertion and is not reusable as-is.

**Why this is a differential test, not a column probe.** An earlier draft asserted "ink count within a
±`noteHeadWidth/2` column band is `> 0`". Review showed that is satisfiable without any notehead:
`drumNotationView` stacks `ledgerLines`, rests, `beams`, `flags`, `stems`, *then* `noteHeads` in one
`ZStack`, and stems and beams occupy the same x bands as the heads they belong to. Deleting every
`NotationNoteHeadView` would leave that probe green — precisely the "computed but never mounted" bug
the probe exists to catch.

The probe therefore renders the same layout twice and requires a positive delta:

1. Render `drumNotationView` for the fixture's layout at the locked `rowWidth` and the layout's
   `totalHeight`, `scale = 1`, on a transparent background — the notation overlay only, not the sheet
   background or staff lines, so staff ink cannot mask a missing head.
2. Render a second image from `var stripped = layout; stripped.noteHeads = []`, everything else equal.
3. Draw both into `CGContext`s with `CGColorSpaceCreateDeviceRGB` and `premultipliedLast`.
4. Classify a pixel as **ink** when `alpha > 20` — colour-agnostic, so theme changes do not break it.
5. Assert total ink in image 1 `>` total ink in image 2, so a wholly unmounted head layer fails first
   with one clear message rather than as N confusing per-head failures.
6. For each head, assert the ink delta **inside that head's `paintedBounds(style:)`** — a 2-D rect, not
   a full-height column — is `> 0`. Stems and beams are present in both images, so they cancel; only
   the head contributes to the delta.

Thresholds are `> 0` on a delta, never exact counts, so antialiasing and font drift cannot flake it.
Because `drumNotationView` resolves its own `NotationLayoutStyle.gameplayDefault` internally, the probe
uses that same style when computing `paintedBounds` rather than the harness's locked style, which
matters only if the two ever diverge — asserted equal in the probe's setup so a future divergence
fails loudly instead of silently misplacing the sample rects.

## 8. Playhead alignment

HPA-144 requires tests verifying playhead x alignment against rendered note columns. This is
**already partially covered**: `RhythmTimelineIntegrationTests` asserts
`viewModel.purpleBarPosition?.x == Double(laterHead.position.x)`.

`purpleBarPosition` is computed in `GameplayViewModel+VisualUpdates` and requires a full view model —
SwiftData container, metronome, practice settings. Rather than build a second playhead harness,
extend that pattern to the dense-row and multi-row fixtures.

**Chart provenance (the seam review flagged as unresolved).** These tests must consume the *same*
fixtures as the goldens, or they verify alignment for a chart nobody else tests. `DrumTabFixtureHarness`
therefore exposes the attached, persisted `Chart` it built in §4.1 — DTX text through
`persistenceProjection()`, `setRhythmMetadata`, inserted and saved in a `TestContainer` — and the
playhead tests hand that chart straight to
`GameplayViewModel(chart:metronome: GameplayViewModelTestHarness.createTestMetronome())`.

Explicitly **not** `GameplayViewModelTestHarness.createTestChart(...)`: it does not run DTX through the
projection, so it would leave `rhythmMetadataState == .missing`, route `resolve(chart:)` through
`resolveMissing`, and land the test on the legacy layout path with a chart that may be detached — the
hazard §9 exists to avoid. This is why `FixtureRenderResult` carries `chart` (§4.2).

Because these tests enter through the view model rather than `DrumTabFixtureHarness.render(...)`, they
do **not** inherit the §5.1 validity gates automatically. Each must re-assert
`availability == .valid`, `timeline != nil`, and a non-zero head count before comparing
`purpleBarPosition?.x` against a rendered column — otherwise a fixture that degrades to
`resolveMissing` yields `nil` on both sides and passes vacuously.

`RhythmTimelineIntegrationTests.swift` is already 602 lines, over the 600-line warning. The two new
tests go in a sibling file, `DrumTabPlayheadAlignmentTests.swift`, not into the existing file.

## 9. Determinism and CI

- All tests use Swift Testing (`@Test`, `#expect`, `#require`, `@Suite`), never XCTest.
- Fixtures are inserted into a per-test in-memory `ModelContainer` via `TestContainer`, then saved.
  `RhythmTimelineResolver.resolve(chart:)` reads `chart.safeNotes`/`chart.safeControlEvents`, so a
  detached `Chart` is not safe here — this also steers clear of the known flaky
  detached-`Chart.difficulty` crash that is red on `main` independent of this work.
- Suites touching `@MainActor` view models or `ImageRenderer` are `.serialized`, matching
  `SwiftUIRenderingNotationTests`.
- Run with `-parallel-testing-enabled NO` per `CLAUDE.md`.
- No network. No file writes except goldens under `VIRGO_UPDATE_GOLDENS=1`.

## 10. Acceptance criteria mapping

| HPA-144 criterion | Satisfied by |
| --- | --- |
| Geometry tests lock x alignment, beam grouping, flags/tails, rests, stop/choke | §6.1 normative line kinds (incl. `flag`, `beam.kind`, `artic`, `tuplet`) + §7.1 invariants over all 11 fixtures, with fixture 11 forcing a non-empty `layout.flags` |
| Fixture tests cover both screenshot failure modes | §7.1, explicitly named |
| Visual/snapshot coverage for a dense row and a multi-row chart, or a documented alternative | §7.3 ink probes, plus the textual digest as the documented alternative to pixel goldens (§3) |
| Playhead x alignment against rendered note columns | §8 |
| Deterministic in the existing Swift Testing setup | §6.3, §9 |

## 11. Scope boundaries

**In scope:** the four components in §4.2, the three test files in §7, the playhead file in §8, eleven
golden files (one per fixture), and the `RhythmLayoutSnapshotBuilder` extraction.

**Out of scope:**
- Changing rendering behavior. This ticket adds coverage. If a fixture reveals a genuine rendering
  bug, it is recorded as a follow-up Linear issue against HPA-97 and the golden captures current
  behavior with a trailer comment `# SUSPECT: HPA-<id> <one-line description>` — greppable, so blessed
  bugs cannot hide. Goldens must not quietly bless a bug, nor block this ticket on an unrelated fix.
- Migrating the existing legacy-path layout suites to the timeline path. Worth doing, but it is a
  large mechanical change across ~10,500 lines of tests and belongs in its own ticket.
- Pixel-image golden comparison, rejected in §3.
- iPhone or iPad-simulator test targets; macOS is the development and CI target per `CLAUDE.md`.

**Accepted overlap:** some assertions restate what the blocker PRs' unit tests already check. That is
intentional — these operate end-to-end at a different level, and HPA-144 asks for a coherent named
regression suite rather than the minimum non-redundant set.

## 12. Risks

| Risk | Mitigation |
| --- | --- |
| Goldens become noise developers regenerate reflexively | Regeneration always fails and names the file; digest diffs are readable so real changes are reviewable |
| Floating-point instability at the 2dp rounding boundary | Digest rounds via a POSIX-locale formatter; §7.1 property assertions use explicit tolerances rather than string equality |
| A fixture does not parse as intended, passing vacuously | §5.1 gates: `availability == .valid`, `timeline != nil`, plus per-fixture expected counts *and kinds* (e.g. fixture 7 asserts a head with both `drumType == .kick` and `sourceLaneID == "1C"`) |
| Goldens depend on ambient machine or user state | §4.4 pins `rowWidth` and `notePositionOverrides`; the `style` line serializes them into the golden |
| Extraction changes view-model behavior | Pure move with `feel` parameterized and `logDiagnostics()` retained; existing `GameplayViewModel` suites are the regression check |
| Ink probe flakiness on CI | Alpha-based, colour-agnostic classification; `> 0` thresholds, never exact counts |
| A golden blesses a degraded fallback instead of real engraving | §5.2 makes fixture 5's gate conditional on `engravingSupport` rather than an either/or, requires the specific diagnostic code, and forces a `# SUSPECT:` trailer when the fallback branch is pinned |
| An invariant reads as stronger coverage than it provides | §7.1 separates falsifiable geometric assertions from the `GroupKey` partition guard, which is labelled in-code as tautological under current construction |
| Playhead tests silently diverge from the golden fixtures | §8 requires the attached chart from `DrumTabFixtureHarness`, forbids `createTestChart`, and re-asserts the §5.1 gates so a `nil == nil` comparison cannot pass |
| A digest line kind is supported but no golden ever contains one | Fixture 11 forces a non-empty `layout.flags` with an exact gate; the §5.1 table pins at least one fixture per required primitive rather than relying on the schema alone |
| Ink probe green with noteheads unmounted | §7.3 is differential — heads-present vs `noteHeads = []` — sampled inside each head's 2-D `paintedBounds`, so stems and beams sharing the x band cancel out |
| Digest overclaims what it locks | §2.2 states the boundary explicitly: layout geometry, grid, style and dimensions are pinned; view modifiers, colour, z-order and rasterization are not |
