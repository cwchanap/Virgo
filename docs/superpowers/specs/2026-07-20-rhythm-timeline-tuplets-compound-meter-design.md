# Rhythm Timeline, Tuplets, Compound Meter, and Variable Measure Design

- **Date:** 2026-07-20
- **Status:** Design approved; awaiting written-spec review
- **Scope:** Give imported and manual charts one timing authority for non-power-of-two grids, dotted rhythms,
  triplets, compound meter, and variable DTX measure lengths, then derive notation, playback, and scoring from it.
- **Linear:** [HPA-145](https://linear.app/cwchanap/issue/HPA-145/handle-tuplets-dotted-rhythms-compound-meter-and-dtx-measure-length)
- **Parent:** [HPA-97](https://linear.app/cwchanap/issue/HPA-97/fix-drum-tab-rendering-spacing-beams-flags-rests-and-stop-note)
- **Blocks:** [HPA-144](https://linear.app/cwchanap/issue/HPA-144/add-drum-tab-rendering-regression-fixtures-and-golden-coverage)

## 1. Context

HPA-139 through HPA-143 established source-preserving DTX notes, a fixed notation grid, catalog-owned drum
notation, semantic beam topology, voice-aware rests, and separate control events. Those contracts remain valid, but
their timing assumptions stop at fixed-length measures and power-of-two visual durations.

The current implementation has four gaps:

1. `DTXFileParser` treats playable grid positions as normalized fractions, computes one shared resolution for every
   measure, and does not parse DTX channel `02` measure-length directives.
2. `VisualDurationLookup` snaps every onset span to the nearest whole, half, quarter, eighth, sixteenth,
   thirty-second, or sixty-fourth interval. A triplet or dotted duration can therefore acquire a different musical
   meaning.
3. `NotationBeamTopologyBuilder` intentionally returns no beam topology for `/8` meters, while rest topology hides
   internal `/8` rests. Compound meter is deterministic in position but incomplete in engraving.
4. `GameplayViewModel` converts elapsed time through one chart-wide `beatsPerMeasure` value. Variable measure lengths,
   compound primary pulses, visual x-position, and scoring targets do not share one timing authority.

HPA-145 closes these gaps with an additive rhythm timeline. The raw DTX chip coordinates remain lossless source data;
the new timeline defines their cumulative musical time.

## 2. Goals

- Parse standard DTX channel `02` measure-length directives without treating them as chip arrays.
- Accept explicit Virgo meter and feel metadata without guessing musical intent from onset spacing.
- Represent every supported measure, note, rest, control event, and beat group in one bounded integer timeline.
- Keep playback, scoring, playhead movement, row transitions, and notation x-position derived from that timeline.
- Render single-dotted notes and rests explicitly.
- Render `3:2` triplets, including groups containing rests, with explicit tuplet geometry.
- Use dotted-quarter primary grouping for 6/8, 9/8, and 12/8.
- Preserve correct 32nd- and 64th-note stems, beams, hooks, and flags.
- Give unsupported rhythm semantics a visible, deterministic fallback without changing known event timing.
- Preserve existing manual charts and older imported charts whose rhythm metadata is absent.
- Provide deterministic parser, timeline, topology, layout, gameplay, persistence, and import coverage.

## 3. Non-Goals

- No BPM-change-lane implementation. HPA-145 preserves the existing constant-BPM contract.
- No per-measure time-signature changes. The first pass has one semantic time signature per chart plus per-measure
  duration overrides.
- No heuristic inference of 3/4 versus 6/8, swing versus literal triplets, or asymmetric-meter grouping.
- No arbitrary tuplet engraving beyond `3:2` triplets.
- No double-dotted or higher-dot-count engraving.
- No new manual rhythm-metadata editor.
- No broad screenshot/golden matrix. HPA-144 owns that layer and may reuse HPA-145's deterministic fixtures.
- No font or SMuFL dependency; new notation marks remain vector-based.
- No iPhone destination, targeting, or UI assumptions.

## 4. Approved Product Decisions

1. **One additive timing authority:** a resolved rhythm timeline feeds notation, playback, scoring, and playhead state.
2. **Actual engraving:** supported dotted values receive dots and supported triplets receive tuplet brackets and labels.
3. **Explicit meter:** `#VIRGO_TIME_SIGNATURE` supplies compound-meter meaning. Measure length alone never chooses a
   numerator or denominator.
4. **Explicit feel:** `#VIRGO_FEEL` supplies straight, swing, or shuffle meaning. Onset spacing alone never chooses
   swing.
5. **DTX timing remains authoritative:** channel `02` controls actual measure duration relative to a 4/4 whole-note
   measure. Meter controls notation grouping.
6. **Variable width follows variable time:** ordinary measures stay equal-width, while shortened and extended measures
   become proportionally narrower or wider.
7. **Conservative semantics:** exact timing may remain playable when engraving is unsupported, but unknown timing
   disables practice rather than inventing score targets.
8. **Legacy compatibility:** missing rhythm metadata activates the current fixed-measure interpretation.

## 5. Persisted Rhythm Metadata

### 5.1 Pure values

Add geometry-free, SwiftData-free value types under `Virgo/models` or `Virgo/utilities`:

```swift
struct RhythmRatio: Codable, Hashable {
    let numerator: Int
    let denominator: Int
}

enum RhythmicFeel: String, Codable, CaseIterable, Hashable {
    case straight
    case swing
    case shuffle
}

struct MeasureLengthOverride: Codable, Hashable {
    let measureIndex: Int
    let ratioToWholeNote: RhythmRatio
}

enum RhythmTimingStatus: String, Codable, Hashable {
    case valid
    case fatal
}

struct ChartRhythmMetadata: Codable, Hashable {
    let version: Int
    let timeSignature: TimeSignature
    let feel: RhythmicFeel
    let measureLengthOverrides: [MeasureLengthOverride]
    let timingStatus: RhythmTimingStatus
    let diagnostics: [PersistedRhythmDiagnostic]
}
```

`RhythmRatio` requires positive values, reduces them with an overflow-safe greatest common divisor, and performs
checked multiplication and division. It does not accept zero, negative, non-finite, or unreduced external state.

`MeasureLengthOverride` uses zero-based measure indices to match normalized DTX timing. The collection is sorted and
unique by measure index before persistence so encoding and equality remain deterministic.

### 5.2 SwiftData integration

`Chart` gains one optional persisted `Data` property, `rhythmMetadataData`. A computed `rhythmMetadata` accessor
encodes and decodes the versioned value, including stable diagnostic codes and their source measure/line context. This
avoids a new relationship graph for a small chart-owned configuration that is always loaded as a unit.

The property is optional for additive compatibility:

- `nil` means legacy behavior, not corrupt data;
- valid data produces the new timeline;
- undecodable or unsupported-version data produces a timing-fatal status;
- encoding never occurs from SwiftUI rendering.

`Chart.timeSignature` remains the compatibility facade. A fresh DTX import sets it to the explicit Virgo meter or
4/4 and persists the same value inside `ChartRhythmMetadata`. At runtime, a chart with no payload and only manual
notes synthesizes valid straight-feel metadata from `Chart.timeSignature` and uses the new timeline without requiring
a persistence migration. A chart with no payload and any DTX-origin note is treated as a legacy import and retains the
existing fixed-measure path until source-backed backfill is available.

No new `@Model` type or schema registration is required.

## 6. DTX Parsing Contract

### 6.1 Recognized syntax

`DTXFileParser` recognizes:

```text
#VIRGO_TIME_SIGNATURE: 6/8
#VIRGO_FEEL: STRAIGHT
#01202: 0.75
```

`#mmm02` is detected before the general `#mmmYY` chip-line branch. Its payload is one positive decimal measure-length
ratio, not a two-character chip array. Decimal input is converted into an exact reduced `RhythmRatio`; it is never
stored first as binary floating point.

The supported explicit signatures are the existing `TimeSignature` cases. Keywords and feel values are parsed
case-insensitively after whitespace trimming.

### 6.2 Meaning and precedence

The timing rules are:

1. A channel `02` value is an absolute measure duration relative to a 4/4 whole-note measure. `0.75` is three quarter
   notes, `1.0` four, and `1.5` six.
2. Without channel `02`, an explicit Virgo meter supplies nominal duration: numerator divided by denominator of a
   whole note. Therefore 6/8 defaults to `3/4` of a whole note.
3. Without either input, the chart remains 4/4 with one whole-note measure.
4. A duration that differs from the semantic meter is an intentional pickup, shortened bar, or extended bar. It is
   not coerced to nominal meter length.
5. A `0.75` duration without explicit meter remains a shortened 4/4 measure. It is never guessed to be 3/4 or 6/8.
6. Triplet-like spacing under `STRAIGHT` is literal triplet material. `SWING` or `SHUFFLE` must be explicit.

Identical duplicate declarations are accepted. Conflicting duplicate meter, feel, or per-measure length declarations
produce a timing-fatal diagnostic rather than relying on file order.

### 6.3 Parser result

`DTXChartData` gains:

- `ChartRhythmMetadata` for valid or fatal explicit timing input, or `nil` for a metadata-free legacy chart;
- ordered `DTXRhythmDiagnostic` values;
- a timing-support status that distinguishes valid, legacy, and fatal timing.

Playable chips and control chips remain present even when timing metadata is fatal so the import can report what was
rejected. A fatal chart does not silently import an empty note array as if the file had no playable content.

## 7. Canonical Rhythm Timeline

### 7.1 Resolution

`RhythmTimelineBuilder` is a pure value-type builder. It accepts chart metadata plus immutable note and control source
coordinates and returns either a valid `RhythmTimeline` or a structured fatal error.

The builder computes one `ticksPerWholeNote` quantum capable of representing exactly:

- every measure duration;
- every DTX grid position inside its measure;
- every time-signature beat-group boundary;
- every manual fractional offset admitted by the exact-conversion path.

It uses checked least-common-multiple operations and caps `ticksPerWholeNote` at 4,096. This reuses the current numeric
normalization guard as a chart-wide quantum cap; it does not reinterpret the old per-measure field. An extended
measure may therefore contain more than 4,096 ticks, but its duration and every cumulative addition remain checked.
Any overflow or cap breach is fatal. The builder never rounds an event onto a neighboring tick.

### 7.2 Measure values

Each `RhythmMeasure` contains:

```swift
struct RhythmMeasure: Hashable {
    let measureIndex: Int
    let startTick: Int
    let durationTicks: Int
    let timeSignature: TimeSignature
    let beatGroups: [RhythmBeatGroup]
    let engravingSupport: RhythmEngravingSupport
}
```

`startTick` is the checked cumulative sum of preceding measure durations. `durationTicks` is exact in the chart-wide
quantum. A source position `gridPosition / gridSize` projects to:

```text
tickWithinMeasure = durationTicks * gridPosition / gridSize
absoluteTick = startTick + tickWithinMeasure
```

The division must be exact. `normalizedTicksPerMeasure` is therefore allowed to differ between measures, and
`normalizedAbsoluteTick` is cumulative rather than `measureIndex * ticksPerMeasure + tick`.

New DTX imports persist these resolved values on `Note` and `ChartControlEvent` while retaining
`sourceGridPosition` and `sourceGridSize` unchanged. Existing records without rhythm metadata retain their current
normalized-field interpretation.

### 7.3 Beat groups

Beat groups are semantic ranges in measure-local ticks:

- X/4 meters use one quarter-note group per beat;
- 6/8, 9/8, and 12/8 use groups of three eighths, producing two, three, and four dotted-quarter groups;
- shortened or extended measures include every complete group and one explicit residual group when necessary;
- 7/8 remains timing-valid but engraving-unsupported because `2+2+3`, `3+2+2`, and `2+3+2` cannot be chosen safely;
- other existing simple signatures use their natural quarter-note groups.

Residual and ambiguous groups never borrow events from an adjacent measure.

### 7.4 Conversion API

`RhythmTimeline` is the only new-code boundary for:

- measure/tick to absolute tick;
- absolute tick to measure/tick;
- absolute tick to seconds at a constant quarter-note BPM;
- seconds to absolute tick;
- event target seconds;
- measure and beat-group lookup.

The seconds conversion uses `ticksPerWholeNote / 4` as ticks per quarter note. Playback speed scales returned seconds
uniformly and does not change musical positions.

## 8. Rhythm Semantics

### 8.1 Additive duration value

`NoteInterval` remains the power-of-two base vocabulary used for stem and flag counts. Add:

```swift
struct NotationRhythm: Hashable {
    let baseInterval: NoteInterval
    let dotCount: Int
    let tuplet: TupletRatio?
    let support: RhythmSemanticSupport
}

struct TupletRatio: Hashable {
    let actual: Int
    let normal: Int
}
```

HPA-145 emits `dotCount` values of zero or one and a tuplet ratio of either `nil` or `3:2`. The types remain capable
of representing future extensions without changing `NoteInterval` or its existing callers.

### 8.2 Voice-aware analysis

`NotationRhythmAnalyzer` operates on integer timeline events grouped by measure, notation voice, and beat group. It
never uses another voice's onset to shorten a note.

The analyzer forms occupied and silent slots from onset streams:

1. Same-time notes in one voice form one chord onset.
2. Consecutive onsets in that voice define candidate rhythmic spans.
3. A terminal onset may use the existing quarter fallback only when one exact quarter fits before its beat-group or
   measure boundary. Otherwise its duration is indeterminate.
4. Exact binary spans map to the existing base intervals.
5. A span exactly `3/2` of a supported base maps to one dotted duration.
6. Three equal slots occupying the duration of two corresponding binary values form one `3:2` tuplet.
7. A triplet group may contain note or rest slots; the three-slot group remains explicit even when one slot is silent.
8. Incomplete, overlapping, or non-`3:2` tuplets are engraving-unsupported but keep exact onset positions.

The analysis output supplies both note rhythm and rest topology. HPA-143's rest builder is adapted to measure-local
durations and semantic rhythm values instead of separately rejecting `/8` meters.

### 8.3 Feel

For `.straight`, supported triplet groups receive literal tuplet notation.

For `.swing` and `.shuffle`:

- exact event timing remains unchanged;
- a long-short `2:1` pair occupying one notated beat is treated as the declared feel and does not receive a triplet
  bracket;
- one chart-level feel mark is rendered above the first visible staff;
- a complete three-equal-slot `3:2` group remains a literal triplet and may still receive a bracket;
- no feel is inferred when metadata is absent.

## 9. Layout and Engraving

### 9.1 Variable grid

`TabGrid` evolves from one fixed `ticksPerMeasure` value to a chart quantum with per-measure duration:

- the grid owns `ticksPerWholeNote`, `tickWidth`, and left padding;
- each `RenderedMeasure` owns `startTick`, `durationTicks`, and width;
- x-position uses the measure-local tick and a shared `tickWidth`;
- row packing uses each measure's actual width;
- ordinary equal-duration measures remain identical in width;
- noteheads, controls, rests, beams, tuplets, dots, and the playhead call the same x-position method.

The layout chooses a tick width that preserves existing minimum note-column and quarter-beat gaps. Dense measures may
expand, but the engine never compresses distinct exact ticks onto the same x-coordinate.

### 9.2 Render primitives

`NotationLayout` gains:

- `RenderedRhythmDot` attached to a source notehead or rendered rest;
- `RenderedTuplet` containing voice, ratio, member columns, bracket geometry, label position, and row;
- `RenderedFeelMark` for swing or shuffle;
- `RenderedRhythmWarning` for affected measures or chart-fatal timing.

Dots and tuplet marks are vector-based. Tuplet placement follows voice and stem direction, uses beam geometry when a
group is beamed, and otherwise draws a bracket. Geometry accounts for painted extents in `topContentInset` and
`contentWidth`.

### 9.3 Beams, flags, and rests

`NotationBeamTopologyBuilder` accepts resolved beat groups instead of recalculating fixed beats from one
`ticksPerMeasure` and chart signature. It retains all HPA-142 boundaries: measure, row, voice, stem direction, and beat
group. Triplet members may beam inside one group; they never connect across a group or measure boundary.

Existing three- and four-level behavior covers 32nd and 64th notes. HPA-145 adds compound-meter and tuplet matrices
without changing those level contracts.

Rest topology consumes `NotationRhythm`, so supported dotted and triplet rests print explicitly. Full-measure rests
remain semantic whole-bar rests regardless of the measure's actual duration.

### 9.4 Conservative fallback

If timing is exact but engraving is unsupported, the affected measure:

- keeps noteheads and controls at exact x-positions;
- suppresses duration-bearing beams, dots, tuplet brackets, and generated internal rests that would assert a false
  rhythm;
- renders one accessible `Unsupported rhythm` annotation;
- remains playable and scoreable from exact target times.

The warning is measure-scoped so one unsupported passage does not degrade the rest of the chart.

## 10. Playback, Playhead, and Scoring

### 10.1 Gameplay state

`GameplayViewModel` caches an immutable `RhythmTimeline` beside the notation layout. It stops converting elapsed time
through `elapsed / secondsPerBeat / beatsPerMeasure` for timeline-enabled charts.

Instead:

- elapsed seconds resolve to one absolute tick;
- that tick resolves to the current measure and measure-local tick;
- row changes use the resolved measure;
- purple-bar x-position uses the grid's measure-local x conversion;
- cached note targets store timeline-derived seconds;
- closest-note and missed-note scans compare absolute ticks or target seconds, not fractional measure numbers.

Legacy DTX charts without rhythm metadata retain the current path. Metadata-free manual charts use synthesized
straight-feel metadata and the new timeline as defined in Section 5.2.

### 10.2 Input timing and scoring

`InputTimingMatcher` receives target timing derived from the timeline. Its Perfect, Great, Good, and Miss windows do
not change. A hit immediately after a shortened barline is compared against its true cumulative target time rather
than a fixed-measure estimate.

Practice-speed changes scale BGM, metronome, playhead, and target seconds through the same speed multiplier. Score
semantics, combo tiers, and persistence remain unchanged.

### 10.3 Metronome and BGM

DTX BPM is quarter-note based. Primary metronome accents follow `RhythmBeatGroup` starts:

- 4/4 yields four quarter groups;
- 6/8 yields two dotted-quarter groups;
- 12/8 yields four dotted-quarter groups;
- a shortened or extended measure follows its complete and residual groups.

BGM and metronome retain the existing shared scheduled start time. The timeline changes event scheduling, not the
common clock or `CFAbsoluteTime` synchronization strategy.

## 11. Import and Backfill

Fresh local and server DTX imports perform one transaction-shaped sequence:

1. parse chart metadata, measure lengths, chips, and diagnostics;
2. build the canonical timeline;
3. create `Chart` with matching `timeSignature` and `rhythmMetadataData`;
4. when timing is valid, create notes and controls with canonical cumulative timing;
5. when timing is fatal, persist the chart, diagnostics, and source-identity notes/controls with canonical timing
   fields left `nil`, then prevent notation/gameplay from treating their required placeholder interval as semantic;
6. return a specific import warning or failure when timing is fatal.

The bundled/local fixture importer gains an idempotent backfill analogous to control-event backfill. For a chart with
missing rhythm metadata and an available original DTX file, it reparses and rewrites rhythm metadata plus normalized
note/control timing together. It skips a chart that already has valid metadata and does not overwrite user-authored
manual metadata.

Existing server charts are updated on a fresh download. HPA-145 does not invent a background network migration for
server charts whose source file is unavailable locally.

## 12. Error Handling and User-Visible Status

Errors are divided by whether event timing is trustworthy.

### 12.1 Timing-fatal

Examples:

- malformed or nonpositive channel `02` value;
- conflicting duplicate timing metadata;
- unsupported persisted metadata version;
- integer overflow or resolution-cap breach;
- inexact grid projection;
- inconsistent cumulative persisted timing.

The chart remains identifiable in the library, but its sheet is replaced by a fatal timing panel and practice is
disabled. The gameplay entry point presents a concise reason such as
`Unsupported chart timing: measure 12 length is invalid`. No notation primitives, scoring session, metronome, or BGM
playback start from placeholder note intervals.

### 12.2 Engraving-only

Examples:

- quintuplet-like or other unsupported tuplet spacing;
- double-dotted duration;
- ambiguous 7/8 beat grouping;
- a terminal onset whose visual duration cannot be determined exactly.

Playback and scoring remain enabled because target time is exact. The affected measure uses the conservative layout
fallback and an accessible warning.

Diagnostics are deterministically ordered by measure, source line, and diagnostic code. Repeated layout passes do not
emit repeated logs for the same persisted condition.

## 13. Testing Strategy

### 13.1 Parser and metadata

- Parse valid `#VIRGO_TIME_SIGNATURE` and every supported signature.
- Parse straight, swing, and shuffle case-insensitively.
- Parse `#mmm02` before chip arrays and reduce decimal ratios exactly.
- Reject zero, negative, malformed, oversized, and conflicting values.
- Preserve raw lane, chip ID, grid position, and grid size.
- Keep a 12-grid chart nonempty and deterministic.

### 13.2 Timeline

- Build cumulative ticks for ordinary, `0.75`, `1.0`, and `1.5` measures.
- Convert event tick to seconds and back at representative BPM and speed values.
- Prove a note after a short measure has the expected earlier target time.
- Cover simple 2/4, 3/4, 4/4, and 5/4 grouping.
- Cover compound 6/8, 9/8, and 12/8 dotted-quarter grouping.
- Cover residual groups in pickup and extended measures.
- Reject overflow, cap breach, inexact projection, and invalid metadata versions.
- Prove missing metadata preserves the legacy fixed-measure result.

### 13.3 Rhythm semantics and topology

- Recognize every power-of-two duration through 64th.
- Recognize single-dotted notes and rests.
- Recognize complete `3:2` triplets in each voice.
- Recognize a triplet containing a rest.
- Keep simultaneous upper/lower voice rhythms independent.
- Suppress feel-derived triplet brackets under swing and shuffle.
- Mark quintuplets, double dots, incomplete triplets, and ambiguous 7/8 groups unsupported.
- Preserve HPA-142 beam/hook matrices and HPA-143 rest visibility behavior.

### 13.4 Layout and SwiftUI

- Assert proportional short, normal, and extended measure widths.
- Assert identical width for equal-duration measures.
- Assert note, control, rest, and playhead x-alignment at shared ticks.
- Assert compound beams remain inside dotted-quarter groups.
- Assert dot, tuplet, feel, and warning primitives have stable geometry and accessibility labels.
- Assert unsupported measures omit misleading beams, dots, tuplets, and generated internal rests.
- Render one focused SwiftUI fixture for each new primitive family.

### 13.5 Gameplay and import

- Advance the playhead and current row across a shortened barline.
- Match hits on both sides of a variable-length measure using unchanged accuracy windows.
- Scale BGM, metronome, playhead, and target times consistently at practice speed.
- Accent compound primary beats at the resolved group boundaries.
- Persist fresh local and server rhythm metadata and canonical note/control timing.
- Backfill a legacy local fixture once and prove a second pass is a no-op.
- Disable practice for timing-fatal charts while allowing engraving-only fallback charts.

### 13.6 Verification ladder

Run focused suites first, then:

1. full `VirgoTests` on macOS with `-parallel-testing-enabled NO`;
2. `swiftlint lint`;
3. macOS build;
4. build for an available iPad simulator, never an iPhone destination.

Xcode build and test commands that share a derived-data path run sequentially.

## 14. Implementation Boundaries

The implementation should remain reviewable in these semantic slices:

1. persisted metadata, exact ratios, and parser diagnostics;
2. canonical timeline and variable-measure normalization;
3. dotted/triplet/compound semantic topology;
4. variable-width layout and vector primitives;
5. playback, playhead, metronome, and scoring integration;
6. import/backfill integration and final regression coverage.

Each slice receives focused tests before the next integration boundary. A final whole-branch review and fresh full
verification run occur after all review fixes, not before them.

## 15. Acceptance Mapping

- **Non-power-of-two grid:** 12-grid events project exactly and supported `3:2` groups render as tuplets; other grids
  retain exact timing with a visible fallback.
- **6/8 and 12/8:** explicit meter produces dotted-quarter beat groups used by beams, rests, metronome, and playhead.
- **Variable measure length:** channel `02` is parsed into exact rational duration and cumulative timeline positions.
- **Dotted and tuplet-like rhythms:** supported values receive explicit dots or tuplet geometry and never snap silently
  to quarter notes.
- **Shared timing:** layout x-position, BGM/metronome playback, hit targets, missed-note scans, and score timing use the
  same `RhythmTimeline`.
- **Deferred cases:** unsupported engraving is measure-scoped, visible, accessible, and covered by tests; unknown
  timing disables practice.
