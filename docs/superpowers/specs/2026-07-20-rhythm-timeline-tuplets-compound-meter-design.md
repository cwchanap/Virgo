# Rhythm Timeline, Tuplets, Compound Meter, and Variable Measure Design

- **Date:** 2026-07-20
- **Status:** Design approved; revised after review and awaiting written-spec re-approval
- **Scope:** Give imported and manual charts one timing authority for non-power-of-two grids, dotted rhythms,
  triplets, compound meter, and variable DTX measure lengths, then derive notation, playback, and scoring from it.
- **Linear:** [HPA-145](https://linear.app/cwchanap/issue/HPA-145/handle-tuplets-dotted-rhythms-compound-meter-and-dtx-measure-length)
- **Parent:** [HPA-97](https://linear.app/cwchanap/issue/HPA-97/fix-drum-tab-rendering-spacing-beams-flags-rests-and-stop-note)
- **Blocks:** [HPA-144](https://linear.app/cwchanap/issue/HPA-144/add-drum-tab-rendering-regression-fixtures-and-golden-coverage)
  (HPA-145 is the upstream Linear dependency.)

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
   every generated `/8` gap. Compound meter is deterministic in position but incomplete in engraving.
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

enum RhythmTimelineAvailability: Hashable {
    case valid
    case legacy
    case fatal
}

enum RhythmDiagnosticSeverity: String, Codable, Hashable {
    case timingFatal
    case engravingOnly
}

enum RhythmDiagnosticCode: String, Codable, CaseIterable, Hashable {
    // Timing-fatal
    case malformedMeasureLength
    case nonpositiveMeasureLength
    case conflictingTimeSignature
    case conflictingFeel
    case conflictingMeasureLength
    case unsupportedMetadataVersion
    case arithmeticOverflow
    case resolutionLimitExceeded
    case inexactGridProjection
    case inconsistentPersistedTiming

    // Engraving-only
    case unsupportedTupletRatio
    case unsupportedDotCount
    case incompleteTuplet
    case ambiguousBeatGrouping
    case indeterminateTerminalDuration
    case manualTimelineUnavailable
}

struct PersistedRhythmDiagnostic: Codable, Hashable {
    let code: RhythmDiagnosticCode
    let severity: RhythmDiagnosticSeverity
    let sourceMeasureIndex: Int?
    let sourceLineNumber: Int?
}

enum RhythmSemanticSupport: Hashable {
    case supported
    case indeterminate(RhythmDiagnosticCode)
    case unsupported(RhythmDiagnosticCode)
}

enum RhythmEngravingSupport: Hashable {
    case supported
    case unsupported([RhythmDiagnosticCode])
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

`RhythmTimingStatus` is persisted only when a metadata payload exists. `RhythmTimelineAvailability.legacy` represents
the absence of a payload or a manual chart that cannot enter the synthesized exact path; it is never encoded as
corrupt metadata.

`RhythmRatio` requires positive values, reduces them with an overflow-safe greatest common divisor, and performs
checked multiplication and division. It does not accept zero, negative, or non-finite input and never retains
unreduced external state.
Checked arithmetic uses `Int.multipliedReportingOverflow(by:)` and `Int.dividedReportingOverflow(by:)`; addition and
subtraction use their reporting-overflow counterparts.

Those invariants also apply at the decoding boundary. `RhythmRatio` implements a custom `init(from:)` that decodes
into temporary integers and delegates to the same validating initializer used by parser input; synthesized
`Decodable` conformance must not permit a zero denominator or negative values, and it must normalize rather than
retain an unreduced representation.
`MeasureLengthOverride`, `PersistedRhythmDiagnostic`, and `ChartRhythmMetadata` likewise decode through validating
initializers for their nonnegative indices, code/severity pairing, supported version, sorted unique overrides, and
other collection invariants. `ChartRhythmMetadataCodec` maps an unsupported version specifically to
`unsupportedMetadataVersion`; any other invariant-bearing decode failure maps to `inconsistentPersistedTiming`.
Encoding is only possible from validated values.

`MeasureLengthOverride` uses zero-based measure indices to match normalized DTX timing. The collection is sorted and
unique by measure index before persistence so encoding and equality remain deterministic.

### 5.2 SwiftData integration

`Chart` gains one optional persisted `Data` property, `rhythmMetadataData`. A computed `rhythmMetadata` accessor
encodes and decodes the versioned value, including stable diagnostic codes and their source measure/line context. This
avoids a new relationship graph for a small chart-owned configuration that is always loaded as a unit.

Encoding and decoding live in a pure, non-`@MainActor` `ChartRhythmMetadataCodec`. SwiftData mutation calls the codec
before assignment; SwiftUI views receive decoded immutable snapshots and never invoke the encoder. Codec tests make
that separation explicit without relying on actor state.

The property is optional for additive compatibility:

- `nil` means legacy behavior, not corrupt data;
- valid data produces the new timeline;
- undecodable or unsupported-version data produces a timing-fatal status;
- encoding never occurs from SwiftUI rendering.

Adding one optional `Data?` property is a SwiftData lightweight migration and does not introduce a
`VersionedSchema`. A persistence test uses a temporary on-disk `ModelContainer`, saves a chart with and without the
payload, releases and reopens the container, and proves the fetched bytes decode to the same validated metadata.

`Chart.timeSignature` remains the compatibility facade. A fresh DTX import sets it to the explicit Virgo meter or
4/4 and persists the same value inside `ChartRhythmMetadata`. At runtime, a chart with no payload and only manual
notes synthesizes valid straight-feel metadata from `Chart.timeSignature` and uses the new timeline without requiring
a persistence migration. A chart with no payload and any DTX-origin note, including a mixed DTX/manual chart, is
treated as a legacy import and retains the existing fixed-measure path until source-backed backfill is available.
The data model does not prohibit mixed origins. When a valid payload exists, DTX source coordinates remain canonical
and every manual note/control offset must rationalize exactly into that same timeline; one inadmissible manual offset
makes the chart timing-fatal rather than silently mixing timing authorities.

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

1. A channel `02` value is an absolute measure duration relative to one whole note, meaning four quarter notes.
   `0.75` is three quarter notes, `1.0` four, and `1.5` six.
2. Without channel `02`, an explicit Virgo meter supplies nominal duration: numerator divided by denominator of a
   whole note. Therefore 6/8 defaults to `3/4` of a whole note.
3. Without either input, the chart remains 4/4 with one whole-note measure.
4. A duration that differs from the semantic meter is an intentional pickup, shortened bar, or extended bar. It is
   not coerced to nominal meter length.
5. A `0.75` duration without explicit meter remains a shortened 4/4 measure. It is never guessed to be 3/4 or 6/8.
6. Triplet-like spacing under `STRAIGHT` is literal triplet material. `SWING` or `SHUFFLE` must be explicit.
7. DTX `#BPM` is always quarter-notes per minute, regardless of semantic meter. In 6/8, 120 BPM therefore makes an
   eighth note 0.25 seconds, a dotted quarter 0.75 seconds, and a nominal measure 1.5 seconds.

The three `mmm` digits in `#mmm02` are the DTX zero-based measure index: `#00002` targets the first DTX measure and
`#01202` targets index 12. `MeasureLengthOverride.measureIndex` stores that integer unchanged, matching
`DTXNote.measureIndex`. Persisted/user-facing `Note.measureNumber` and diagnostic labels remain one-based, so the UI
adds one only at presentation boundaries.

Identical duplicate declarations are accepted. Conflicting duplicate meter, feel, or per-measure length declarations
produce a timing-fatal diagnostic rather than relying on file order.

### 6.3 Parser result

`DTXChartData` gains:

- `ChartRhythmMetadata` for valid or fatal explicit timing input, or `nil` for a metadata-free legacy chart;
- ordered `DTXRhythmDiagnostic` values;
- a timing-support status that distinguishes valid, legacy, and fatal timing.

Playable chips and control chips remain present even when timing metadata is fatal so the import can report what was
rejected. A fatal chart does not silently import an empty note array as if the file had no playable content.

`DTXRhythmDiagnostic` is the parser-local form of a diagnostic. It carries the stable code and severity plus the raw
source line for logs. Persistence drops raw chart text and stores only `PersistedRhythmDiagnostic` source coordinates.

## 7. Canonical Rhythm Timeline

### 7.1 Resolution

`RhythmTimelineBuilder` is a pure value-type builder. It accepts chart metadata plus immutable note and control source
coordinates and returns either a valid `RhythmTimeline` or a structured fatal error.

The builder computes one `ticksPerWholeNote` quantum capable of representing exactly:

- every measure duration;
- every DTX grid position inside its measure;
- every time-signature beat-group boundary;
- every manual fractional offset admitted by the exact-conversion path.

Resolution couples each measure length to the grids used inside that measure. For a reduced measure ratio `a / b`
and DTX `gridSize = g`, the selected whole-note quantum `W` must make both of these values integral:

```text
durationTicks = W * a / b
slotTicks = durationTicks / g
```

Equivalently, `W` must be a multiple of:

```text
(b * g) / gcd(a, b * g)
```

The builder computes that factor with checked arithmetic for every measure/grid pair and includes it in the bounded
LCM. For a manual offset `m / n` inside the same measure, the corresponding factor is
`(b * n) / gcd(a * m, b * n)`; reduced whole-note beat-group boundaries contribute their denominators. Every
intermediate multiplication is checked. For example, a
`0.75 = 3/4` measure containing a three-slot grid requires `W` to be a multiple of
`(4 * 3) / gcd(3, 12) = 4`; at `W = 4`, the measure is exactly three ticks and every grid slot is exactly one tick.
This prevents an algorithm that represents the measure duration and grid denominator separately but cannot divide
the resulting duration into exact slots.

It uses checked least-common-multiple operations and a new
`RhythmTimelineBuilder.maximumTicksPerWholeNote = 4_096` constant. This is a deliberate unit-semantic break from
`DTXChartData.maximumTicksPerMeasure`; the old symbol is not reused. Mixed ordinary and triplet 64th-note positions
require multiples of `lcm(64, 96) = 192` ticks per whole note; the largest such quantum below the cap is 4,032
(`192 * 21`). An extended measure may contain more than 4,096 ticks, but its duration
and every cumulative addition remain checked. Any overflow or cap breach is fatal. The builder never rounds an event
onto a neighboring tick. The final cumulative tick must also remain no greater than `2^53 - 1`, so conversion of the
integer coordinate to `Double` is exact before the final BPM division.

### 7.2 Manual-offset rationalization

Metadata-free manual charts attempt a deterministic exact-conversion path before receiving a synthesized timeline:

1. Require every `Note.measureOffset` to be finite and inside `0...1`.
2. Search reduced fractions in ascending denominator order through 4,096.
3. Accept the first fraction whose `Double` value differs from the source by at most `1e-9`; ties use the smaller
   numerator.
4. Feed every accepted denominator into the same bounded timeline-resolution calculation.
5. If any offset has no candidate or the combined resolution exceeds the cap, keep the entire chart on the existing
   legacy manual timing path. Do not partially project it or disable an otherwise playable legacy chart.

This admits common authored values such as `0.1` and approximated `0.333333333333` deterministically. For manual
notes, the stored `Note.interval` is authoritative engraving data. A sparse or terminal manual onset therefore does
not become indeterminate merely because no later onset exists.

### 7.3 Measure values

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

This is an intentional semantic overload of the existing normalized fields. On a valid timeline,
`normalizedTicksPerMeasure` is the resolved duration of that specific measure and `normalizedAbsoluteTick` is
cumulative. On the legacy path, they retain HPA-139/HPA-143's uniform-measure or native-control-grid meaning. No
consumer may infer the interpretation from a field tuple alone: the chart-level availability selector described in
Section 7.6 chooses the branch, and timeline-enabled readers consume resolved `RhythmEventPosition` snapshots rather
than reinterpreting persisted fields independently.

### 7.4 Beat groups

Beat groups are semantic ranges in measure-local ticks:

- X/4 meters use one quarter-note group per beat;
- 6/8, 9/8, and 12/8 use groups of three eighths, producing two, three, and four dotted-quarter groups;
- shortened or extended measures include every complete group and one explicit residual group when necessary;
- 7/8 remains timing-valid but engraving-unsupported because `2+2+3`, `3+2+2`, and `2+3+2` cannot be chosen safely;
- other existing simple signatures use their natural quarter-note groups.

Residual and ambiguous groups never borrow events from an adjacent measure.

### 7.5 Conversion API

`RhythmTimeline` is the only new-code boundary for:

- measure/tick to absolute tick;
- absolute tick to measure/tick;
- absolute tick to seconds at a constant quarter-note BPM;
- seconds to absolute tick;
- event target seconds;
- measure and beat-group lookup.

Seconds conversion deliberately avoids integer division by four:

```text
seconds = Double(absoluteTick) / Double(ticksPerWholeNote) * (240.0 / bpm) / playbackSpeed
```

The inverse keeps a continuous `Double` tick for playhead interpolation and uses bounded binary search for discrete
measure/pulse lookup. Rational construction and integer event coordinates remain exact until this API boundary.
Because cumulative ticks are bounded to exact-`Double` integers and the final floating-point error is many orders of
magnitude below the existing +/-25 ms Perfect window, `Double` target seconds are the explicit scoring contract.
There is no requirement that `ticksPerWholeNote` be divisible by four.

### 7.6 One chart-level availability selector

`RhythmTimelineResolver` computes `RhythmTimelineAvailability` once while gameplay data is cached and stores it beside
the optional immutable timeline. Layout, gameplay, scoring, metronome, BGM, validation, and resume state all switch on
that cached value; individual consumers do not repeat origin or payload checks.

| Input/result | Timing status | Availability | Semantic support | Measure engraving | Severity |
| --- | --- | --- | --- | --- | --- |
| Valid payload and exact build | `.valid` | `.valid` | Per-event analysis | Aggregated from events | None unless analysis reports one |
| Exact onset and duration/group supported | `.valid` | `.valid` | `.supported` | `.supported` | None |
| Exact onset but source cannot determine duration | `.valid` | `.valid` | `.indeterminate(code)` | `.unsupported([code])` | `.engravingOnly` |
| Exact timing and known unsupported structure | `.valid` | `.valid` | `.unsupported(code)` | `.unsupported([code])` | `.engravingOnly` |
| Payload/version/invariant/timeline failure | `.fatal` | `.fatal` | Not run | Not rendered | `.timingFatal` |
| No payload plus any DTX-origin event | Not persisted | `.legacy` | Not run | Existing layout | None |
| Manual-only synthesis succeeds | Runtime-valid, not persisted | `.valid` | Stored interval plus analysis | Aggregated from events | As produced by analysis |
| Manual-only synthesis fails | Not persisted | `.legacy` | Not run | Existing layout | Runtime `manualTimelineUnavailable` only |

The table's timing-status column is the resolver's effective status. It does not rewrite a previously persisted
`.valid` payload when later source-coordinate validation fails; that cached runtime result is still `.fatal`.
`manualTimelineUnavailable` is runtime-only and is not added to a missing payload.

`.indeterminate` means the source does not contain enough information to name a duration even though its onset is
exact. `.unsupported` means the duration or grouping is known but outside HPA-145's engraving vocabulary. Both are
engraving-only and aggregate to measure-level `.unsupported`, while neither disables exact playback or scoring.

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
2. A manual note's stored `Note.interval` is authoritative; source onsets determine its position, not its base
   duration.
3. Consecutive DTX onsets in that voice define candidate rhythmic spans.
4. A terminal DTX onset may retain an existing persisted `.quarter` `visualDurationCandidate` only when one exact
   quarter fits before its beat-group or measure boundary. An absent/untrusted candidate remains indeterminate; the
   analyzer does not invent a quarter merely because space is available.
5. Exact binary spans map to the existing base intervals.
6. A span exactly `3/2` of a supported base maps to one dotted duration.
7. Three equal slots occupying the duration of two corresponding binary values form one `3:2` tuplet.
8. A triplet group may contain note or rest slots; the three-slot group remains explicit even when one slot is silent.
9. Incomplete, overlapping, or non-`3:2` tuplets are engraving-unsupported but keep exact onset positions.

The analysis output supplies both note rhythm and rest topology. HPA-143's rest builder is adapted to measure-local
durations and semantic rhythm values instead of separately rejecting `/8` meters.

This preserves HPA-143's uncertain-span contract. When analysis returns `.indeterminate`, the active voice remains
occupied through its next onset or the resolved measure end, and internal complements remain hidden spacing. The
existing `compoundMeterUncertainDurationExtendsToMeasureEnd` and `compoundMeterHidesInternalComplements` assertions
are retained with timeline-local tick inputs; HPA-145 adds separate tests for a trusted terminal quarter that fits and
one that crosses a group boundary.

### 8.3 Feel

For `.straight`, supported triplet groups receive literal tuplet notation.

For `.swing` and `.shuffle`:

- exact event timing remains unchanged;
- a long-short `2:1` pair occupying one notated beat is treated as the declared feel and does not receive a triplet
  bracket;
- one chart-level feel mark is rendered above the first visible staff;
- a complete three-equal-slot `3:2` group does not match the feel pair and always receives a literal triplet bracket;
- no feel is inferred when metadata is absent.

### 8.4 Rest decomposition

Rest synthesis no longer uses one greedy power-of-two-only `decompositionOrder`. It processes each voice and resolved
beat group in two phases:

1. Reserve recognized tuplet groups first. Every silent slot inside a reserved `3:2` group becomes a tuplet-associated
   rest with the same group identifier and slot duration as its neighboring notes.
2. Decompose remaining silence with a deterministic dynamic-programming sweep whose tokens are supported binary and
   single-dotted rests. A token cannot cross a beat-group or measure boundary. The selected path minimizes printed
   symbols, then prefers longer values, then prefers an undotted value on an exact tie.

A dotted token is eligible only when its exact tick duration fits and its start is aligned to that duration's
notational subdivision. Silence that has no supported decomposition becomes hidden spacing plus the measure's
`Unsupported rhythm` annotation; it is never greedily rewritten as several rests with a different grouping.
The minimum-symbol objective is intentionally deterministic and bounded, not a general-purpose engraving optimizer;
it may choose a less idiomatic but semantically exact spelling when several legal decompositions exist.

## 9. Layout and Engraving

### 9.1 Variable grid

`TabGrid` evolves from one fixed `ticksPerMeasure` value to a chart quantum with per-measure duration:

- the grid owns `ticksPerWholeNote`, `tickWidth`, and left padding;
- each `RenderedMeasure` owns `startTick`, `durationTicks`, and width;
- x-position uses the measure-local tick and a shared `tickWidth`;
- row packing uses each measure's actual width;
- ordinary equal-duration measures remain identical in width;
- noteheads, controls, rests, beams, tuplets, dots, and the playhead call the same x-position method.

The timeline API is `xPosition(in:localTick:)` and clamps against that `RenderedMeasure.durationTicks`, not a
chart-wide tick count. The current `tickIndex(forBeatWithinMeasure:beatsPerMeasure:)` helper and the fixed
`ticksPerMeasure` clamp remain legacy-only compatibility APIs. Timeline-enabled code obtains a local tick from
`RhythmTimeline`; it never converts a `Double` beat fraction back through the legacy helper. The implementation-plan
audit must enumerate every current `TabGrid` conversion/x-position production and test call site and classify it as
timeline migration, deliberate legacy wrapper, or deleted assertion. `TabGrid.fallback` keeps its current legacy
semantics.

The layout chooses a tick width that preserves existing minimum note-column and quarter-beat gaps. Dense measures may
expand, but the engine never compresses distinct exact ticks onto the same x-coordinate.

Row capacity remains a pixel budget equal to `NotationLayoutStyle.rowWidth` (with the existing 900-point floor), not
a count of measure-equivalent slots. A measure's claim is its fixed bar/padding geometry plus
`durationTicks * tickWidth`; a `1.5` measure therefore consumes 1.5 times the timeline span of a `1.0` measure and can
cause the row to pack fewer measures. Timeline-enabled layout derives its measure count from the highest resolved
timeline measure plus the configured minimum. `cachedLayoutMeasureCount` remains a legacy fallback and is not
estimated from track-duration seconds for a valid timeline.

### 9.2 Render primitives

`NotationLayout` gains:

- `RenderedRhythmDot` attached to a source notehead or rendered rest;
- `RenderedTuplet` containing voice, ratio, member columns, bracket geometry, label position, and row;
- `RenderedFeelMark` for swing or shuffle;
- `RenderedRhythmWarning` for affected measures or chart-fatal timing.

Dots and tuplet marks are vector-based. Tuplet placement follows voice and stem direction, uses beam geometry when a
group is beamed, and otherwise draws a bracket. Geometry accounts for painted extents in `topContentInset` and
`contentWidth`.

Persisted diagnostics store stable codes, never English display text. A `RhythmDiagnosticPresentation` maps each code
to a `String(localized:)` user-facing label and accessibility description. Logs include the stable code plus source
coordinates; views render the localized presentation and one-based measure number.

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

DTX `#BPM` remains quarter-notes per minute in every meter. The existing `MetronomeBeatSchedule` computes
`origin + beatNumber * beatInterval` and cannot represent variable measure boundaries or semantic accent groups.
Timeline-enabled gameplay therefore adds a `RhythmMetronomeSchedule` containing ordered pulse offsets and accent
levels derived from the resolved timeline. The timer consumes a schedule cursor rather than reconstructing time from
one `beatInterval`; the existing schedule remains the legacy path.

Pulse policy is deterministic:

- X/4 meters pulse on quarter-note units and accent each resolved group start, with the measure downbeat strongest;
- 6/8, 9/8, and 12/8 pulse on eighth-note units and accent dotted-quarter group starts;
- shortened or extended measures emit only pulses inside their resolved duration and accent complete/residual group
  starts;
- ambiguous 7/8 emits seven isochronous eighth-note pulses with only the measure downbeat accented. Virgo does not
  claim a `2+2+3`, `3+2+2`, or `2+3+2` grouping.

This keeps 7/8 timing valid while making its grouping limitation audible and visible without inventing unequal
accents. The offset-table design also supports future explicit asymmetric grouping without another scheduler rewrite.

BGM and metronome retain the existing shared scheduled start time. The timeline changes event scheduling, not the
common clock or `CFAbsoluteTime` synchronization strategy.

`RhythmScheduleCursor` follows the existing manual Sendable discipline used by `MetronomePlaybackToken` and
`MetronomeBeatCounter`: it is a small `@unchecked Sendable` reference whose mutable pulse index is protected by one
`NSLock`. Its schedule value is immutable. Only the serial `timerQueue` consumes the next pulse; MainActor control
paths may cancel or reseat the cursor only through lock-guarded methods. Timer callbacks capture the playback token
and cursor for that generation, then hop to MainActor for published state/audio work, so a cancelled generation
cannot advance a replacement cursor.

Pause, resume, seek, and speed changes do not increment from the cursor's prior index. They cancel the active token,
derive elapsed musical seconds from the shared BGM/metronome clock, binary-search the immutable offset table for the
first pulse at or after that position, install a newly seated cursor under the same lock discipline, and only then
restart scheduling. Focused race tests cover cancellation between pulse lookup and callback delivery, plus reseating
on both sides of a shortened barline.

### 10.4 Fixed-measure call-site audit

Implementation must migrate every current `beatsPerMeasure`, `secondsPerMeasure`, and fixed `beatInterval` reader for
timeline-enabled charts:

- setup-time `secondsPerMeasure`, `trackDurationInSeconds`, and `cachedLayoutMeasureCount` calculations resolve from
  timeline duration and measure count;
- `cacheNotationBeatPositions` uses each cached beat's absolute timeline tick, while `cacheLegacyBeatPositions`
  remains unchanged;
- `calculateTrackDurationInSeconds` falls back to the final timeline end second rather than measure count times one
  duration;
- `calculateBGMOffset` converts the authoritative BGM source position or earliest note through the timeline;
- `recordHit` and `scanForMissedNotes` compare target seconds, and the late window remains milliseconds rather than a
  measure fraction;
- `restoreResumeState` resolves measure, measure-local tick, pulse index, closest beat, and row from elapsed seconds;
- continuous visual updates and purple-bar calculations resolve the same elapsed-seconds position;
- `MetronomeBeatCounter`, `MetronomeBeatSchedule`, current-beat wrapping, and pause/resume offsets use the rhythm
  schedule cursor and offset table.

The legacy branches retain their current formulas. Tests must enumerate this audit so a remaining fixed-measure
reader cannot silently diverge from the timeline.

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
note/control timing together. It skips any chart whose payload is already non-`nil`; HPA-145 has no manual
rhythm-metadata editor, so preserving edited metadata is a forward-looking concern rather than a current branch.

The backfill runs from the existing `ContentView.seedLocalDTXFixtures()` app-launch import path after the bundled song
is found or created. An injectable `RhythmBackfillVersionStore` uses a versioned `UserDefaults` key. The importer skips
all DTX reparsing when the stored version equals the current backfill version, and records that version only after the
complete chart scan and `ModelContext.save()` succeed. A failed or interrupted pass retries on the next launch. Tests
use an isolated store rather than the developer's standard defaults.

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

`RhythmTimelineBuilder` performs consistency validation at three boundaries: before a fresh import is persisted,
during source-backed backfill, and whenever gameplay data loading builds a cached timeline from a persisted chart. On
load it recomputes canonical fields from metadata plus source grid coordinates and compares every present
`normalizedMeasureIndex`, `normalizedTickWithinMeasure`, `normalizedTicksPerMeasure`, and `normalizedAbsoluteTick`.
A partial or mismatched tuple is `inconsistentPersistedTiming`. The check is not repeated during SwiftUI rendering or
every visual timer tick.

The chart remains identifiable in the library, but its sheet is replaced by a fatal timing panel and practice is
disabled. The gameplay entry point presents a localized concise reason such as
`Unsupported chart timing: measure 13 length is invalid` for zero-based source index 12. No notation primitives,
scoring session, metronome, or BGM playback start from placeholder note intervals.

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
- Assert `#00002` maps to measure index 0 and user-facing measure 1 without an off-by-one conversion.
- Preserve raw lane, chip ID, grid position, and grid size.
- Keep a 12-grid chart nonempty and deterministic.
- Round-trip `ChartRhythmMetadataCodec` outside SwiftUI and actor-dependent state.

### 13.2 Timeline

- Build cumulative ticks for ordinary, `0.75`, `1.0`, and `1.5` measures.
- Convert event tick to seconds and back at representative BPM and speed values.
- Pin compound tempo semantics: at DTX 120 BPM, a nominal 6/8 measure is 1.5 seconds, an eighth-note pulse is
  0.25 seconds, and a dotted-quarter group is 0.75 seconds.
- Prove a note after a short measure has the expected earlier target time.
- Cover simple 2/4, 3/4, 4/4, and 5/4 grouping.
- Cover compound 6/8, 9/8, and 12/8 dotted-quarter grouping.
- Cover residual groups in pickup and extended measures.
- Reject overflow, cap breach, inexact projection, and invalid metadata versions.
- Decode hostile persisted ratios/overrides/diagnostics through validating initializers; reject zero denominators,
  negative indices, duplicate overrides, and mismatched code/severity pairs.
- Round-trip `rhythmMetadataData` through a temporary on-disk `ModelContainer` reopened from the same store URL.
- Prove a `3/4`-whole measure with `gridSize = 3` selects a quantum whose three slots are exact, and cover the general
  measure-ratio/grid coupling formula near the 4,096 cap.
- Prove missing metadata preserves the legacy fixed-measure result.
- Rationalize manual `0.1` and approximated one-third offsets deterministically, preserve authoritative manual
  intervals for terminal notes, and retain the whole legacy path when one manual offset is inadmissible.
- Prove the chart-level selector is computed once: metadata-free mixed DTX/manual data stays legacy, while a valid
  payload accepts only manual additions that rationalize into its canonical timeline.
- Detect a persisted canonical-field mismatch when gameplay data loading rebuilds the timeline.

### 13.3 Rhythm semantics and topology

- Recognize every power-of-two duration through 64th.
- Recognize single-dotted notes and rests.
- Recognize complete `3:2` triplets in each voice.
- Recognize a triplet containing a rest.
- Keep simultaneous upper/lower voice rhythms independent.
- Suppress feel-derived triplet brackets under swing and shuffle.
- Always bracket a complete three-equal-slot literal triplet under swing or shuffle.
- Prove the two-phase rest algorithm reserves tuplet rests before dotted/binary dynamic-programming decomposition.
- Mark quintuplets, double dots, incomplete triplets, and ambiguous 7/8 groups unsupported.
- Preserve HPA-142 beam/hook matrices and the named HPA-143
  `compoundMeterUncertainDurationExtendsToMeasureEnd` and `compoundMeterHidesInternalComplements` behaviors.

### 13.4 Layout and SwiftUI

- Assert proportional short, normal, and extended measure widths.
- Assert a `1.5` measure consumes 1.5 times the timeline span of a `1.0` measure and can reduce measures per row under
  the same pixel budget.
- Assert identical width for equal-duration measures.
- Assert note, control, rest, and playhead x-alignment at shared ticks.
- Assert timeline x-position clamps each local tick to that measure's duration while the legacy beat-fraction helper
  and `TabGrid.fallback` retain current behavior.
- Assert compound beams remain inside dotted-quarter groups.
- Assert dot, tuplet, feel, and warning primitives have stable geometry and accessibility labels.
- Assert unsupported measures omit misleading beams, dots, tuplets, and generated internal rests.
- Render one focused SwiftUI fixture for each new primitive family.

### 13.5 Gameplay and import

- Advance the playhead and current row across a shortened barline.
- Match hits on both sides of a variable-length measure using unchanged accuracy windows.
- Scale BGM, metronome, playhead, and target times consistently at practice speed.
- Compare timeline-derived `Double` target seconds against exact rational expectations and prove conversion error is
  negligible relative to the +/-25 ms Perfect window at supported bounds.
- Accent compound primary beats at the resolved group boundaries.
- Drive 7/8 with seven isochronous eighth-note pulses and only a downbeat accent.
- Race cursor cancellation/reseating against queued pulse callbacks and resume/speed changes around a short measure.
- Exercise every fixed-measure call site listed in Section 10.4 through timeline and legacy branches.
- Persist fresh local and server rhythm metadata and canonical note/control timing.
- Trigger app-launch backfill once, set the version only after a successful save, prove a second launch skips DTX
  parsing, and prove a failed pass retries.
- Disable practice for timing-fatal charts while allowing engraving-only fallback charts.
- Prove a timing-fatal chart remains visible in the library with a localized reason and disabled practice control.

### 13.6 Verification ladder

Run focused suites first, then:

1. full `VirgoTests` on macOS with `-parallel-testing-enabled NO`;
2. `swiftlint lint`;
3. macOS build;
4. build for an available iPad simulator, never an iPhone destination.

Xcode build and test commands that share a derived-data path run sequentially.

## 14. Implementation Boundaries

The implementation should remain reviewable in these semantic slices:

1. persisted metadata, exact ratios, codec, and parser diagnostics;
2. canonical timeline, manual rationalization, validation, and variable-measure normalization;
3. dotted/triplet/compound note and rest topology;
4. variable-width grid, row packing, beam integration, and render geometry;
5. SwiftUI dot, tuplet, feel, warning, fatal-panel, localization, and accessibility views;
6. playback, playhead, offset-table metronome, scoring, and fixed-measure call-site migration;
7. import/backfill integration and final regression coverage.

The new SwiftUI primitives should live in a focused `NotationRhythmPrimitiveViews.swift` (or comparably scoped
files), rather than pushing the existing `NotationPrimitiveViews.swift` across SwiftLint size limits.

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
