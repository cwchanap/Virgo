# Rhythm Timeline, Tuplets, Compound Meter, and Variable Measures Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make one exact, bounded rhythm timeline the timing authority for DTX measure-length overrides, dotted rhythms, 3:2 tuplets, compound meter, notation layout, gameplay, input scoring, metronome pulses, and BGM anchoring while preserving the existing legacy path.

**Architecture:** Add validated chart-owned rhythm metadata, parse DTX rhythm directives into exact rational values, and resolve immutable event snapshots through a pure integer timeline. Semantic rhythm analysis and layout consume those snapshots; gameplay installs the same event IDs and one-X target times into notation, input, scoring, metronome, playhead, and BGM systems. Missing metadata retains legacy behavior, while invalid non-`nil` metadata is timing-fatal and can never fall through to legacy.

**Tech Stack:** Swift 5.9+, SwiftData, SwiftUI, AVFoundation, CoreMIDI, Swift Testing (`import Testing`), Xcode 16+/`xcodebuild`, SwiftLint.

## Global Constraints

- Preserve HPA-139 source identity and additive normalized timing fields, HPA-140 fixed-grid legacy layout, HPA-141 catalog-owned notation semantics, HPA-142 beam boundaries, and HPA-143 uncertain-duration/rest/control behavior.
- A chart has exactly one cached timing selection: `.valid`, `.legacy`, or `.fatal`. No downstream subsystem may independently infer timing mode from note origins or normalized-field tuples.
- `rhythmMetadataData == nil` is the only missing-metadata state. Every non-`nil` payload that fails version or invariant validation is `.invalid` and resolves to `.fatal`.
- Exact rational and integer arithmetic is mandatory until the `RhythmTimeline` seconds/playhead conversion boundary. Never round an event to a neighboring tick.
- Enforce `RhythmTimelineBuilder.maximumTicksPerWholeNote == 4_096`, `RhythmLimits.maximumMeasureCount == 4_096`, `RhythmLimits.maximumMaterializedRhythmUnitCount == 49_152` per eager collection, and cumulative ticks `<= 2^53 - 1`.
- Treat DTX `#BPM` as quarter notes per minute in every meter. Channel `02` changes measure duration; it never changes BPM or infers meter.
- Fresh parser results are timing-valid or timing-fatal, never legacy. Base DTX identity failures still throw; recognized rhythm failures return persistable fatal chart data.
- `Note.interval == .quarter` may remain a compatibility placeholder for an indeterminate or fatal DTX note, but timeline semantic analysis must use the optional `visualDurationCandidate`, never that placeholder.
- Timeline callbacks retain only immutable, model-free values. SwiftData `Note` objects remain MainActor-owned and are reached from a `[RhythmEventID: Note]` lookup after callback delivery.
- Timeline session duration comes from `RhythmTimeline.endSeconds`. `AVAudioPlayer.duration` is media length only, and `Song.duration`/`Song.bgmStartOffsetSeconds` remain legacy or library-display values.
- Use Swift Testing (`import Testing`), not XCTest.
- Run every `xcodebuild test` with `-parallel-testing-enabled NO`; run Xcode commands sequentially against `./DerivedData`.
- Any iOS-family build must target an available iPad simulator. Never target an iPhone or change `TARGETED_DEVICE_FAMILY = 2`.
- Prefix every shell command with `rtk`.
- The project uses `PBXFileSystemSynchronizedRootGroup`; add Swift files under `Virgo/` or `VirgoTests/` without editing `Virgo.xcodeproj/project.pbxproj`.
- Keep each task limited to its named files, run its focused suites, inspect `rtk git diff --check` and `rtk git diff`, and commit before starting the next task.

---

## File Structure

### New production files

- `Virgo/models/RhythmMetadata.swift` — validated persisted values, diagnostics, load state, and codec; Task 6 adds presentation mapping.
- `Virgo/utilities/DTXRhythmParser.swift` — exact decimal/directive parsing and parser-local diagnostics.
- `Virgo/utilities/RhythmTimeline.swift` — measures, positions, beat groups, conversions, and bounded lookup APIs.
- `Virgo/utilities/RhythmTimelineBuilder.swift` — checked LCM resolution, source projection, manual-offset rationalization, and exact build errors.
- `Virgo/utilities/RhythmTimelineResolver.swift` — chart-level tri-state selection, deterministic event IDs, layout/input snapshots, and MainActor note lookup.
- `Virgo/layout/NotationRhythm.swift` — additive rhythm values, semantic support, and tuplet identifiers.
- `Virgo/layout/NotationRhythmAnalyzer.swift` — voice/group onset analysis and two-phase exact rest decomposition.
- `Virgo/utilities/RhythmMetronomeSchedule.swift` — immutable pulse table and lock-protected schedule cursor.
- `Virgo/utilities/RhythmBackfillVersionStore.swift` — injectable, versioned local backfill completion state.

### New test files

- `VirgoTests/RhythmMetadataTests.swift`
- `VirgoTests/RhythmMetadataPersistenceTests.swift`
- `VirgoTests/DTXRhythmParserTests.swift`
- `VirgoTests/RhythmTimelineBuilderTests.swift`
- `VirgoTests/RhythmTimelineResolverTests.swift`
- `VirgoTests/NotationRhythmAnalyzerTests.swift`
- `VirgoTests/NotationLayoutRhythmTests.swift`
- `VirgoTests/RhythmRenderingTests.swift`
- `VirgoTests/RhythmInputTimingTests.swift`
- `VirgoTests/RhythmMetronomeScheduleTests.swift`
- `VirgoTests/RhythmImportBackfillTests.swift`
- `VirgoTests/RhythmTimelineIntegrationTests.swift`

### Existing files modified across tasks

- Model/parser/import: `Virgo/models/DrumTrack.swift`, `Virgo/utilities/DTXFileParser.swift`, `Virgo/utilities/VisualDurationLookup.swift`, `Virgo/utilities/LocalDTXFixtureImporter.swift`, `Virgo/utilities/ServerSongDownloader.swift`, `Virgo/views/ContentView.swift`.
- Layout/rendering: `Virgo/layout/NotationLayout.swift`, `Virgo/layout/NotationLayoutEngine.swift`, `Virgo/layout/NotationLayoutEngine+TabGrid.swift`, `Virgo/layout/NotationLayoutEngine+Controls.swift`, `Virgo/layout/NotationLayoutEngine+Rests.swift`, `Virgo/layout/NotationLayoutEngine+Beams.swift`, `Virgo/layout/NotationRestTopology.swift`, `Virgo/layout/NotationBeamTopology.swift`, `Virgo/views/NotationPrimitiveViews.swift`, `Virgo/views/subviews/GameplaySheetMusicView.swift`.
- Gameplay/input/audio: `Virgo/utilities/InputTimingMatcher.swift`, `Virgo/utilities/InputManager.swift`, `Virgo/utilities/MetronomeTimingEngine.swift`, `Virgo/utilities/MetronomeEngine.swift`, `Virgo/viewmodels/GameplayViewModel.swift`, `Virgo/viewmodels/GameplayViewModel+Computations.swift`, `Virgo/viewmodels/GameplayViewModel+VisualUpdates.swift`, `Virgo/viewmodels/GameplayViewModel+Playback.swift`, `Virgo/viewmodels/GameplayViewModel+SpeedControl.swift`, `Virgo/viewmodels/GameplayViewModel+BGM.swift`, `Virgo/views/GameplayView+InputManagerDelegate.swift`.
- Fatal-status UI: `Virgo/components/DifficultyExpansionView.swift`, `Virgo/views/GameplayView.swift`.
- Existing regression suites named in the tasks below.

---

### Task 1: Validated Rhythm Metadata and SwiftData Tri-State

**Files:**
- Create: `Virgo/models/RhythmMetadata.swift`
- Modify: `Virgo/models/DrumTrack.swift`
- Create: `VirgoTests/RhythmMetadataTests.swift`
- Create: `VirgoTests/RhythmMetadataPersistenceTests.swift`
- Modify: `VirgoTests/TestHelpers.swift`

**Interfaces:**
- Produces: `RhythmRatio`, `RhythmicFeel`, `MeasureLengthOverride`, `RhythmSourceAnchor`, `RhythmTimingStatus`, `RhythmTimelineAvailability`, diagnostic/support types, `ChartRhythmMetadata`, `ChartRhythmMetadataLoadState`, `ChartRhythmMetadataCodec`.
- Produces: `Chart.rhythmMetadataData: Data?`, `Chart.rhythmMetadataState`, `Chart.setRhythmMetadata(_:) throws`.
- Consumes: existing `TimeSignature` from `Virgo/constants/Drum.swift`.

- [ ] **Step 1: Write failing value-invariant tests**

Create `RhythmMetadataTests` with table-driven cases proving positive reduction, checked arithmetic, custom decoding, sorted unique overrides, source-anchor bounds, diagnostic severity/code agreement, supported version `1`, valid metadata requiring meter and feel, and fatal metadata permitting a rejected field to be `nil`.

```swift
@Suite("Rhythm metadata")
struct RhythmMetadataTests {
    @Test("ratios reduce and reject invalid components")
    func ratioValidation() throws {
        #expect(try RhythmRatio(numerator: 6, denominator: 8) == .init(numerator: 3, denominator: 4))
        #expect(throws: RhythmMetadataValidationError.self) {
            _ = try RhythmRatio(numerator: 1, denominator: 0)
        }
    }

    @Test("decoded metadata validates instead of trusting synthesized Decodable")
    func decodingRejectsInvalidPayloads() throws {
        let corruptRatio = Data(#"{"numerator":1,"denominator":0}"#.utf8)
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(RhythmRatio.self, from: corruptRatio)
        }
    }
}
```

- [ ] **Step 2: Run the focused suite and confirm it fails to compile**

Run:

```bash
rtk xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' -configuration Debug -only-testing:VirgoTests/RhythmMetadataTests -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -derivedDataPath ./DerivedData
```

Expected: failure because the rhythm metadata types do not exist.

- [ ] **Step 3: Implement pure validated values and stable diagnostics**

In `RhythmMetadata.swift`, make construction throwing and route every `init(from:)` through the same validators. Use reporting-overflow APIs for addition, subtraction, multiplication, division, GCD normalization, and LCM helpers. Keep display strings out of persisted diagnostics.

```swift
enum RhythmLimits {
    static let maximumMeasureCount = 4_096
    static let maximumExactDoubleInteger = 9_007_199_254_740_991
}

struct RhythmRatio: Codable, Hashable, Sendable {
    let numerator: Int
    let denominator: Int

    init(numerator: Int, denominator: Int) throws {
        guard numerator > 0, denominator > 0 else {
            throw RhythmMetadataValidationError.nonpositiveRatio
        }
        let divisor = Self.greatestCommonDivisor(numerator, denominator)
        self.numerator = numerator / divisor
        self.denominator = denominator / divisor
    }
}
```

Define every diagnostic code from the approved spec, and make `PersistedRhythmDiagnostic` reject engraving codes paired with `.timingFatal` and timing codes paired with `.engravingOnly`.

- [ ] **Step 4: Add codec mapping and round-trip tests**

Implement `ChartRhythmMetadataCodec.encode(_:)` and `decode(_:)`. Map an unsupported version only to `.unsupportedMetadataVersion`; map all other invariant-bearing decode errors to `.inconsistentPersistedTiming`.

```swift
enum ChartRhythmMetadataCodec {
    static func encode(_ metadata: ChartRhythmMetadata) throws -> Data
    static func decode(_ data: Data) -> ChartRhythmMetadataLoadState
}
```

Add tests for deterministic encoding, corrupt bytes, unsupported version bytes, and valid/fatal round trips.

- [ ] **Step 5: Add the optional SwiftData payload and tri-state accessor**

Add `var rhythmMetadataData: Data?` to `Chart`, default it to `nil` in the initializer, and expose only the nonoptional state boundary:

```swift
var rhythmMetadataState: ChartRhythmMetadataLoadState {
    guard let rhythmMetadataData else { return .missing }
    return ChartRhythmMetadataCodec.decode(rhythmMetadataData)
}

func setRhythmMetadata(_ metadata: ChartRhythmMetadata) throws {
    rhythmMetadataData = try ChartRhythmMetadataCodec.encode(metadata)
}
```

Do not add an optional decoded accessor. Add a migration-only internal clearing method only if the persistence test needs to prove the `nil` state.

- [ ] **Step 6: Prove on-disk persistence distinguishes missing, valid, corrupt, and unsupported-version bytes**

Add a temporary-directory container helper to `RhythmMetadataPersistenceTests`; do not reuse the in-memory `TestContainer` for this proof. Save four charts, release the container, reopen the same store, fetch by difficulty, and assert `.missing`, `.valid`, `.invalid(.inconsistentPersistedTiming)`, and `.invalid(.unsupportedMetadataVersion)`.

- [ ] **Step 7: Run metadata/model regressions**

Run:

```bash
rtk xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' -configuration Debug -only-testing:VirgoTests/RhythmMetadataTests -only-testing:VirgoTests/RhythmMetadataPersistenceTests -only-testing:VirgoTests/NoteModelTests -only-testing:VirgoTests/DrumTrackTests -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -derivedDataPath ./DerivedData
rtk git diff --check
```

Expected: all selected suites pass; no whitespace errors.

- [ ] **Step 8: Commit the metadata boundary**

```bash
rtk git add Virgo/models/RhythmMetadata.swift Virgo/models/DrumTrack.swift VirgoTests/RhythmMetadataTests.swift VirgoTests/RhythmMetadataPersistenceTests.swift VirgoTests/TestHelpers.swift
rtk git commit -m "feat: add validated chart rhythm metadata"
```

---

### Task 2: DTX Rhythm Directives, Fatal Results, and Duration Evidence

**Files:**
- Create: `Virgo/utilities/DTXRhythmParser.swift`
- Modify: `Virgo/utilities/DTXFileParser.swift`
- Modify: `Virgo/utilities/VisualDurationLookup.swift`
- Create: `VirgoTests/DTXRhythmParserTests.swift`
- Modify: `VirgoTests/DTXFileParserTests.swift`
- Modify: `VirgoTests/DTXNoteLineParsingTests.swift`
- Modify: `VirgoTests/DTXNormalizationTests.swift`

**Interfaces:**
- Produces: `DTXRhythmDiagnostic`, exact decimal parsing, recognized `#VIRGO_TIME_SIGNATURE`, `#VIRGO_FEEL`, and `#mmm02` values.
- Changes: `DTXChartData.rhythmMetadata`, `.rhythmDiagnostics`, and raw BGM anchor ownership; removes parser-derived BGM seconds from the timeline path.
- Changes: `NormalizedRhythmicEvent.visualDurationCandidate` to `NoteInterval?`.

- [ ] **Step 1: Write failing directive and precedence tests**

Cover case-insensitive valid directives; exact `0.75 -> 3/4`; nominal 6/8 duration; channel `02` overriding nominal meter duration; identical duplicates; conflicting duplicates; malformed versus unsupported meter and feel; malformed/nonpositive/conflicting measure length; and `#mmm02` being consumed before chip parsing.

```swift
@Test("channel 02 is an exact measure ratio, not a chip array")
func parsesMeasureLengthExactly() throws {
    let chart = try DTXFileParser.parseChartMetadata(from: """
    #TITLE: Pickup
    #ARTIST: Tester
    #BPM: 120
    #DLEVEL: 50
    #VIRGO_TIME_SIGNATURE: 6/8
    #00002: 0.75
    #00011: 01000100
    """)

    #expect(chart.rhythmMetadata.measureLengthOverrides == [
        try MeasureLengthOverride(measureIndex: 0, ratioToWholeNote: .init(numerator: 3, denominator: 4))
    ])
    #expect(chart.rhythmMetadata.timingStatus == .valid)
}
```

- [ ] **Step 2: Add parser-local exact values and diagnostics**

Implement decimal-to-ratio parsing from trimmed character components, including checked power-of-ten construction. Never parse a channel `02` payload through `Double`.

```swift
struct DTXRhythmDiagnostic: Hashable {
    let code: RhythmDiagnosticCode
    let severity: RhythmDiagnosticSeverity
    let sourceLineNumber: Int?
    let sourceLine: String
}
```

Accumulate ordered diagnostics and accept identical duplicates while producing stable conflict codes for different values.

- [ ] **Step 3: Integrate rhythm parsing before the generic note-line branch**

Extend `DTXMetadata` with parsed meter, feel, overrides, diagnostics, and earliest lane-01 anchor state. Build a nonoptional `ChartRhythmMetadata` after base title/artist/BPM/difficulty validation. Use 4/4 and straight defaults only when authors supplied no invalid explicit value.

Keep `DTXParseError` behavior for unreadable data, missing title/artist/BPM/difficulty, invalid base BPM, and invalid DLEVEL. Recognized rhythm failures return `DTXChartData` with `.fatal` metadata and raw playable/control chips.

- [ ] **Step 4: Replace fixed-4/4 BGM seconds with the earliest raw lane-01 anchor**

For every lane-01 chip, construct `RhythmSourceAnchor(measureIndex:gridPosition:gridSize:)`; keep the earliest by source order, then persist it inside metadata. Remove `DTXChartData.bgmStartOffsetSeconds` from new parser consumers. Keep a deprecated legacy adapter only until Task 9 migrates all importer call sites.

- [ ] **Step 5: Make terminal visual duration evidence optional**

Change the normalized event initializer and property:

```swift
struct NormalizedRhythmicEvent: Hashable {
    // existing source/canonical fields
    let visualDurationCandidate: NoteInterval?
}
```

In `normalizedRhythmicEvents()`, pass `visualDurationCandidates[VisualDurationLookup.chipKey(chip)]` directly and delete `?? .quarter`. In `toNotes`, keep `interval: candidate ?? .quarter` only as the compatibility/model placeholder and assign `visualDurationCandidate: candidate` unchanged.

- [ ] **Step 6: Add fatal-result tests**

Prove malformed meter and unsupported feel preserve all playable chips and controls, carry ordered stable diagnostics, produce source-identity notes with `.quarter` storage interval, and leave `visualDurationCandidate`, `normalizedMeasureIndex`, `normalizedAbsoluteTick`, `normalizedTickWithinMeasure`, and `normalizedTicksPerMeasure` nil. Also prove invalid base BPM still throws instead of producing a fatal rhythm chart.

- [ ] **Step 7: Run parser/normalization regressions**

```bash
rtk xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' -configuration Debug -only-testing:VirgoTests/DTXRhythmParserTests -only-testing:VirgoTests/DTXFileParserTests -only-testing:VirgoTests/DTXNoteLineParsingTests -only-testing:VirgoTests/DTXNormalizationTests -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -derivedDataPath ./DerivedData
rtk git diff --check
```

Expected: all selected suites pass, including the old ordinary-grid fixtures.

- [ ] **Step 8: Commit parser semantics**

```bash
rtk git add Virgo/utilities/DTXRhythmParser.swift Virgo/utilities/DTXFileParser.swift Virgo/utilities/VisualDurationLookup.swift VirgoTests/DTXRhythmParserTests.swift VirgoTests/DTXFileParserTests.swift VirgoTests/DTXNoteLineParsingTests.swift VirgoTests/DTXNormalizationTests.swift
rtk git commit -m "feat: parse exact DTX rhythm metadata"
```

---

### Task 3: Canonical Timeline Builder, Resolver, and Event Identity

**Files:**
- Modify: `Virgo/models/RhythmMetadata.swift`
- Create: `Virgo/utilities/RhythmTimeline.swift`
- Create: `Virgo/utilities/RhythmTimelineBuilder.swift`
- Create: `Virgo/utilities/RhythmTimelineResolver.swift`
- Create: `VirgoTests/RhythmTimelineBuilderTests.swift`
- Create: `VirgoTests/RhythmTimelineResolverTests.swift`
- Modify: `VirgoTests/NotationLayoutEngineTabGridOverflowTests.swift`

**Interfaces:**
- Produces: `RhythmMeasure`, `RhythmBeatGroup`, `RhythmEventPosition`, `RhythmTimeline`, `RhythmEventID`, immutable source-event inputs, `ResolvedChartRhythm`.
- Produces: `RhythmTimelineBuilder.maximumTicksPerWholeNote == 4_096` and shared `RhythmLimits.maximumMeasureCount` / `maximumMaterializedRhythmUnitCount` use.
- Consumes: validated metadata and immutable source coordinates, never SwiftData inside the pure builder.

- [ ] **Step 1: Write failing resolution and conversion tests**

Cover ordinary 4/4, 6/8, a `3/4` pickup followed by `3/2` extended measure, grids 3/6/12/64/96, cumulative absolute positions, quarter-note BPM seconds, inverse continuous tick conversion, measure-end canonicalization, and exact x-safe `Double` bounds.

```swift
@Test("shortened measure changes the following absolute tick and seconds")
func cumulativeVariableMeasures() throws {
    let timeline = try RhythmTimelineBuilder().build(fixture: .pickupThenFourFour)
    #expect(timeline.measures[0].durationTicks == timeline.ticksPerWholeNote * 3 / 4)
    #expect(timeline.measures[1].startTick == timeline.measures[0].durationTicks)
    #expect(timeline.seconds(forAbsoluteTick: timeline.measures[1].startTick, bpm: 120, speed: 1) == 1.5)
}
```

- [ ] **Step 2: Implement checked bounded resolution**

For each reduced measure ratio `a/b` and source grid `g`, include this factor in the checked LCM:

```swift
let bg = try checkedMultiply(b, g)
let factor = bg / greatestCommonDivisor(a, bg)
resolution = try checkedLCM(resolution, factor)
guard resolution <= Self.maximumTicksPerWholeNote else {
    throw RhythmTimelineBuildError.resolutionLimitExceeded
}
```

Include manual-fraction and beat-group denominators; reject overflow, inexact division, out-of-range measures, and cumulative ticks beyond `RhythmLimits.maximumExactDoubleInteger`.

Before allocating beat groups, compute their exact chart-wide count with checked arithmetic. Reject counts above
`RhythmLimits.maximumMaterializedRhythmUnitCount` using `RhythmTimelineBuildError.materializationLimitExceeded`, mapped
to timing-fatal `RhythmDiagnosticCode.rhythmMaterializationLimitExceeded`. Never materialize a prefix or coarsen the
semantic grouping.

- [ ] **Step 3: Materialize measures, beat groups, and event positions**

Define:

```swift
struct RhythmEventPosition: Hashable, Sendable {
    let measureIndex: Int
    let localTick: Int
    let absoluteTick: Int
}

struct RhythmMeasure: Hashable, Sendable {
    let measureIndex: Int
    let startTick: Int
    let durationTicks: Int
    let timeSignature: TimeSignature
    let beatGroups: [RhythmBeatGroup]
    let engravingSupport: RhythmEngravingSupport
}
```

Use quarter groups for X/4; dotted-quarter groups for 6/8, 9/8, and 12/8; complete groups plus one residual group for shortened/extended measures; timing-valid but engraving-unsupported groups for 7/8.

- [ ] **Step 4: Implement the only seconds/lookup boundary**

Add bounded binary-search APIs for absolute tick to measure/local tick, seconds to continuous tick, measure/beat-group lookup, and event target seconds. Use:

```swift
Double(absoluteTick) / Double(ticksPerWholeNote) * (240.0 / bpm) / speed
```

Do not require `ticksPerWholeNote` to be divisible by four.

- [ ] **Step 5: Implement manual-offset rationalization and boundary rollover**

Search denominators `1...4_096` in ascending order, accept the first reduced fraction within `1e-9`, and feed it into the same resolution calculation. Canonicalize `measureOffset == 1.0` to zero in the following measure. Manual-only failure returns `.legacy`; the same failure under valid persisted metadata is `.fatal`. Reject final-measure rollover beyond index 4095.

- [ ] **Step 6: Implement tri-state resolver and deterministic event IDs**

Define one cached result:

```swift
struct ResolvedChartRhythm {
    let availability: RhythmTimelineAvailability
    let timeline: RhythmTimeline?
    let orderedEvents: [ResolvedRhythmEvent]
    let noteByEventID: [RhythmEventID: Note]
    let runtimeDiagnostics: [PersistedRhythmDiagnostic]
}
```

Switch on `chart.rhythmMetadataState` before checking origins. `.invalid` and decoded `.fatal` return `.fatal`; missing plus any DTX event returns `.legacy`; manual-only charts attempt synthesis. Sort valid events by absolute tick, source identity, drum lane, and a stable insertion ordinal, then assign session-local IDs once.

- [ ] **Step 7: Persist canonical normalized values only through an explicit projection helper**

Add a pure `CanonicalRhythmProjection` mapping source event IDs to event positions. Importers will use it in Task 9 to write per-measure `normalizedTicksPerMeasure` and cumulative `normalizedAbsoluteTick`; legacy readers must not call it.

- [ ] **Step 8: Test hostile limits and selector precedence**

Cover override/source/manual indices `4095` and `4096`, a final `measureOffset == 1`, resolution `4032` accepted, resolution beyond `4096` rejected, checked multiplication/cumulative overflow, a hostile simple-meter group count rejected before allocation, corrupt payload never legacy, missing mixed DTX/manual remaining legacy, and valid metadata plus one inadmissible manual event becoming fatal. Test the `2^53 - 1` cumulative boundary with a bounded-group fixture so the proof itself cannot allocate unbounded rhythm units.

- [ ] **Step 9: Run timeline suites**

```bash
rtk xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' -configuration Debug -only-testing:VirgoTests/RhythmTimelineBuilderTests -only-testing:VirgoTests/RhythmTimelineResolverTests -only-testing:VirgoTests/RhythmMetadataTests -only-testing:VirgoTests/NotationLayoutEngineTabGridOverflowTests -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -derivedDataPath ./DerivedData
rtk git diff --check
```

- [ ] **Step 10: Commit the timing authority**

```bash
rtk git add Virgo/models/RhythmMetadata.swift Virgo/utilities/RhythmTimeline.swift Virgo/utilities/RhythmTimelineBuilder.swift Virgo/utilities/RhythmTimelineResolver.swift VirgoTests/RhythmTimelineBuilderTests.swift VirgoTests/RhythmTimelineResolverTests.swift VirgoTests/NotationLayoutEngineTabGridOverflowTests.swift
rtk git commit -m "feat: add canonical rhythm timeline"
```

---

### Task 4: Semantic Rhythm, Tuplets, Dots, Beams, and Exact Rests

**Files:**
- Create: `Virgo/layout/NotationRhythm.swift`
- Create: `Virgo/layout/NotationRhythmAnalyzer.swift`
- Modify: `Virgo/layout/NotationRestTopology.swift`
- Modify: `Virgo/layout/NotationBeamTopology.swift`
- Create: `VirgoTests/NotationRhythmAnalyzerTests.swift`
- Modify: `VirgoTests/NotationRestTopologyTests.swift`
- Modify: `VirgoTests/NotationBeamTopologyTests.swift`
- Modify: `VirgoTests/NotationBeamTopologyMeterTests.swift`

**Interfaces:**
- Produces: `NotationRhythm`, `TupletRatio`, `RhythmTupletID`, analyzed note/rest/group snapshots.
- Changes: beam topology consumes resolved `RhythmBeatGroup`; rest topology consumes exact `NotationRhythm` values.

- [ ] **Step 1: Write failing semantic matrices**

Cover every binary value from whole through 64th, every single-dotted value that fits, complete 3:2 triplets, triplets with each of the three slots silent, incomplete/overlapping/non-3:2 groups, straight versus swing/shuffle long-short pairs, trusted versus absent terminal candidates, and voice isolation for simultaneous upper/lower streams.

```swift
@Test("a silent middle triplet slot remains part of the tuplet")
func tripletWithMiddleRest() throws {
    let analysis = try NotationRhythmAnalyzer().analyze(.tripletWithMiddleRest)
    #expect(analysis.tuplets.count == 1)
    #expect(analysis.rests.single?.tupletID == analysis.tuplets.single?.id)
    #expect(analysis.rests.single?.rhythm.tuplet == TupletRatio(actual: 3, normal: 2))
}
```

- [ ] **Step 2: Add additive rhythm values and support states**

```swift
struct NotationRhythm: Hashable, Sendable {
    let baseInterval: NoteInterval
    let dotCount: Int
    let tuplet: TupletRatio?
    let support: RhythmSemanticSupport
}

struct TupletRatio: Hashable, Sendable {
    let actual: Int
    let normal: Int
}
```

Validate HPA-145 output to dot counts 0/1 and tuplets nil/3:2 while leaving the value types extensible.

- [ ] **Step 3: Implement voice/group onset analysis**

Group same-time notes into chord onsets by measure, notation voice, and resolved beat group. Manual notes use stored interval for duration; DTX spans use consecutive same-voice onsets. A terminal DTX note uses optional `visualDurationCandidate` only when it fits inside its group/measure. Missing evidence produces `.indeterminate(.indeterminateTerminalDuration)` and remains occupied to the next onset or measure end.

- [ ] **Step 4: Recognize dotted and 3:2 structures without changing exact positions**

Map exact `3/2 * base` spans to one dot. Reserve three equal slots occupying two binary base values as one explicit triplet, including silent slots. For swing/shuffle, suppress the bracket only for an exact declared 2:1 beat pair; a complete equal-slot triplet remains literal.

- [ ] **Step 5: Replace greedy rest decomposition with a two-phase bounded solver**

Reserve tuplet groups first. For remaining gaps, use dynamic programming over exact tick positions. Compare candidate paths by `(symbolCount, descendingDurations, undottedTieBreak)`; never cross a beat-group/measure boundary. If no exact supported path exists, return hidden spacing and one measure warning.

- [ ] **Step 6: Migrate beam grouping to resolved beat groups**

Change `NotationBeamTopologyBuilder` to receive the measure's group ranges. Retain boundaries for measure, row, voice, stem direction, and group. Preserve current three-/four-level 32nd/64th beam/hook behavior and allow triplet members within one group.

- [ ] **Step 7: Preserve HPA-143 uncertain-duration assertions**

Adapt `compoundMeterUncertainDurationExtendsToMeasureEnd` and `compoundMeterHidesInternalComplements` to measure-local timeline ticks. Add a trusted terminal quarter that fits and a trusted terminal quarter crossing a group boundary.

- [ ] **Step 8: Run semantic/topology suites**

```bash
rtk xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' -configuration Debug -only-testing:VirgoTests/NotationRhythmAnalyzerTests -only-testing:VirgoTests/NotationRestTopologyTests -only-testing:VirgoTests/NotationBeamTopologyTests -only-testing:VirgoTests/NotationBeamTopologyMeterTests -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -derivedDataPath ./DerivedData
rtk git diff --check
```

- [ ] **Step 9: Commit semantic analysis**

```bash
rtk git add Virgo/layout/NotationRhythm.swift Virgo/layout/NotationRhythmAnalyzer.swift Virgo/layout/NotationRestTopology.swift Virgo/layout/NotationBeamTopology.swift VirgoTests/NotationRhythmAnalyzerTests.swift VirgoTests/NotationRestTopologyTests.swift VirgoTests/NotationBeamTopologyTests.swift VirgoTests/NotationBeamTopologyMeterTests.swift
rtk git commit -m "feat: analyze dotted and tuplet rhythms"
```

---

### Task 5: Timeline Layout Snapshot, Variable Grid, and Row Packing

**Files:**
- Modify: `Virgo/models/RhythmMetadata.swift`
- Modify: `Virgo/layout/NotationLayout.swift`
- Modify: `Virgo/layout/NotationLayoutEngine.swift`
- Modify: `Virgo/layout/NotationLayoutEngine+TabGrid.swift`
- Modify: `Virgo/layout/NotationLayoutEngine+Controls.swift`
- Modify: `Virgo/layout/NotationLayoutEngine+Rests.swift`
- Modify: `Virgo/layout/NotationLayoutEngine+Beams.swift`
- Create: `VirgoTests/NotationLayoutRhythmTests.swift`
- Modify: `VirgoTests/NotationLayoutEngineTests.swift`
- Modify: `VirgoTests/NotationLayoutRestTests.swift`
- Modify: `VirgoTests/NotationLayoutControlTests.swift`
- Modify: `VirgoTests/NotationLayoutOffsetNormalizationTests.swift`
- Modify: `VirgoTests/NotationLayoutNotePositionOverrideTests.swift`

**Interfaces:**
- Produces: `RhythmLayoutNote`, `RhythmLayoutControl`, `RhythmLayoutSnapshot`, `NotationLayoutTimingInput`.
- Changes: `TabGrid` owns `ticksPerWholeNote` and `tickWidth`; `RenderedMeasure` owns `startTick`, `durationTicks`, and actual width.
- Consumes: resolver-assigned event IDs/positions and analyzer-assigned rhythms.

- [ ] **Step 1: Write failing snapshot and grid tests**

Prove that timeline layout positions notes and controls from `RhythmEventPosition` even when their legacy fractions disagree; equal-duration measures have equal width; `0.75` and `1.5` measures scale proportionally; distinct exact ticks never share x; row packing uses pixel claims; and per-measure clamping accepts `durationTicks` only for measure-end queries.

- [ ] **Step 2: Add the immutable timing boundary**

```swift
enum NotationLayoutTimingInput {
    case timeline(RhythmLayoutSnapshot)
    case legacy(notes: [Note], controls: [NotationControlEvent], timeSignature: TimeSignature)
}

struct RhythmLayoutSnapshot: Hashable {
    let measures: [RhythmMeasure]
    let notes: [RhythmLayoutNote]
    let controls: [RhythmLayoutControl]
    let feel: RhythmicFeel
}
```

Make `NotationLayoutInput` own this enum plus style, minimum measure count, and note-position overrides. Keep model relationships only in the legacy case.

- [ ] **Step 3: Migrate `TabGrid` to chart quantum plus per-measure duration**

Add:

```swift
func xPosition(in measure: RenderedMeasure, localTick: Int) -> CGFloat {
    let clampedTick = min(max(localTick, 0), measure.durationTicks)
    return measure.contentStartX + CGFloat(clampedTick) * tickWidth
}
```

Keep `tickIndex(forBeatWithinMeasure:beatsPerMeasure:)`, fixed `ticksPerMeasure`, and `TabGrid.fallback` only as explicit legacy wrappers. Timeline call sites may not convert back through `Double` beat fractions.

- [ ] **Step 4: Build timeline measures and pack rows by actual pixel width**

Give each rendered measure fixed bar/padding geometry plus `durationTicks * tickWidth`. Preserve the 900-point row-width floor. Derive timeline measure count from resolved measures plus configured minimum; retain `cachedLayoutMeasureCount` only for legacy.

- [ ] **Step 5: Thread event position/rhythm into rendered note and rest structures**

Add timeline fields to `RenderedNoteHead` and `RenderedRest`; provide legacy adapters that construct compatible values from current time columns and intervals. Controls, rests, beam endpoints, and later playhead code must all use the same `TabGrid.xPosition(in:localTick:)` call.

- [ ] **Step 6: Complete the TabGrid call-site audit**

Use:

```bash
rtk rg -n "tickIndex|ticksPerMeasure|xPosition|beatWithinMeasure|measureOffset" Virgo/layout Virgo/views/subviews/GameplaySheetMusicView.swift Virgo/viewmodels
```

Classify each hit in the implementation diff as migrated timeline production, retained legacy wrapper, or removed assertion. Add a regression for every timeline production path: notehead, control, rest, beam endpoint, measure bar, and playhead input coordinate.

- [ ] **Step 7: Run layout regressions**

```bash
rtk xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' -configuration Debug -only-testing:VirgoTests/NotationLayoutRhythmTests -only-testing:VirgoTests/NotationLayoutEngineTests -only-testing:VirgoTests/NotationLayoutRestTests -only-testing:VirgoTests/NotationLayoutControlTests -only-testing:VirgoTests/NotationLayoutOffsetNormalizationTests -only-testing:VirgoTests/NotationLayoutNotePositionOverrideTests -only-testing:VirgoTests/NotationLayoutEngineTabGridOverflowTests -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -derivedDataPath ./DerivedData
rtk git diff --check
```

- [ ] **Step 8: Commit variable timeline layout**

```bash
rtk git add Virgo/layout/NotationLayout.swift Virgo/layout/NotationLayoutEngine.swift Virgo/layout/NotationLayoutEngine+TabGrid.swift Virgo/layout/NotationLayoutEngine+Controls.swift Virgo/layout/NotationLayoutEngine+Rests.swift Virgo/layout/NotationLayoutEngine+Beams.swift VirgoTests/NotationLayoutRhythmTests.swift VirgoTests/NotationLayoutEngineTests.swift VirgoTests/NotationLayoutRestTests.swift VirgoTests/NotationLayoutControlTests.swift VirgoTests/NotationLayoutOffsetNormalizationTests.swift VirgoTests/NotationLayoutNotePositionOverrideTests.swift
rtk git commit -m "feat: lay out variable rhythm measures"
```

---

### Task 6: Dots, Tuplet/Feel Marks, Warnings, and Painted Bounds

**Files:**
- Modify: `Virgo/layout/NotationLayout.swift`
- Modify: `Virgo/layout/NotationLayoutEngine.swift`
- Modify: `Virgo/views/NotationPrimitiveViews.swift`
- Modify: `Virgo/views/subviews/GameplaySheetMusicView.swift`
- Create: `VirgoTests/RhythmRenderingTests.swift`
- Modify: `VirgoTests/SwiftUIRenderingNotationTests.swift`
- Modify: `VirgoTests/NotationLayoutControlRenderingTests.swift`
- Modify: `VirgoTests/NotationLayoutDefensiveGuardTests.swift`

**Interfaces:**
- Produces: `RenderedRhythmDot`, `RenderedTuplet`, `RenderedFeelMark`, `RenderedRhythmWarning`, `RhythmDiagnosticPresentation`.
- Changes: every rendered primitive implements `paintedBounds(style:)`; `NotationLayout` derives scroll extents from one union.

- [ ] **Step 1: Write failing render-structure and bounds tests**

Cover one dotted note, one dotted rest, stem-up and stem-down triplets, beamed versus bracketed triplets, swing and shuffle first-staff feel marks, measure-scoped unsupported warning, fatal chart warning, and accessibility labels. Assert that every mark expands the union when it protrudes above/after existing content.

- [ ] **Step 2: Add rendered rhythm primitives**

Define stable IDs and geometry values in `NotationLayout.swift`:

```swift
struct RenderedTuplet: Identifiable, Hashable {
    let id: RhythmTupletID
    let voice: NotationVoice
    let ratio: TupletRatio
    let memberEventIDs: [RhythmEventID]
    let bracketPoints: [CGPoint]
    let isBracketVisible: Bool
    let labelPosition: CGPoint
    let rowIndex: Int
}
```

Attach `RenderedRhythmDot` to a source event/rest ID. Emit one chart-level feel mark above the first visible staff and one warning per affected measure.

- [ ] **Step 3: Render vector dots, tuplets, feel marks, and warnings**

Use existing vector/path conventions; do not add a font or SMuFL dependency. Use beam geometry for beamed triplets and a bracket otherwise. Place by voice/stem direction and expose localized accessibility descriptions.

- [ ] **Step 4: Centralize stable-code presentation**

Map every persisted code in `RhythmDiagnosticPresentation` to `String(localized:)` title and description. Log stable code plus zero-based source coordinates; display a one-based measure number. Never persist the English string.

- [ ] **Step 5: Add `paintedBounds(style:)` to every primitive**

Implement bounds for noteheads, rests, controls/stop marks, articulations, stems, beams, flags, ledger lines, measure bars, dots, tuplets, feel marks, and warnings. Union once in `NotationLayout` and derive `topContentInset`, `contentWidth`, and total height from that rectangle. Delete the prior hand-maintained omissions.

- [ ] **Step 6: Implement conservative unsupported engraving**

For an exact but unsupported measure, retain exact notehead/control x positions; suppress duration-bearing beams, dots, tuplets, and generated internal rests; emit one accessible warning. Do not disable playback/scoring.

- [ ] **Step 7: Run rendering regressions**

```bash
rtk xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' -configuration Debug -only-testing:VirgoTests/RhythmRenderingTests -only-testing:VirgoTests/SwiftUIRenderingNotationTests -only-testing:VirgoTests/NotationLayoutControlRenderingTests -only-testing:VirgoTests/NotationLayoutDefensiveGuardTests -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -derivedDataPath ./DerivedData
rtk git diff --check
```

- [ ] **Step 8: Commit rhythm engraving**

```bash
rtk git add Virgo/layout/NotationLayout.swift Virgo/layout/NotationLayoutEngine.swift Virgo/views/NotationPrimitiveViews.swift Virgo/views/subviews/GameplaySheetMusicView.swift VirgoTests/RhythmRenderingTests.swift VirgoTests/SwiftUIRenderingNotationTests.swift VirgoTests/NotationLayoutControlRenderingTests.swift VirgoTests/NotationLayoutDefensiveGuardTests.swift
rtk git commit -m "feat: render tuplets dots and rhythm warnings"
```

---

### Task 7: Model-Free Input Targets, Scoring Identity, and Speed Reconfiguration

**Files:**
- Modify: `Virgo/utilities/InputTimingMatcher.swift`
- Modify: `Virgo/utilities/InputManager.swift`
- Modify: `Virgo/views/GameplayView+InputManagerDelegate.swift`
- Modify: `Virgo/viewmodels/GameplayViewModel.swift`
- Modify: `Virgo/viewmodels/GameplayViewModel+Computations.swift`
- Modify: `Virgo/viewmodels/GameplayViewModel+SpeedControl.swift`
- Create: `VirgoTests/RhythmInputTimingTests.swift`
- Modify: `VirgoTests/InputTimingMatcherTests.swift`
- Modify: `VirgoTests/InputManagerConfigurationTests.swift`
- Modify: `VirgoTests/InputManagerBoundaryTests.swift`
- Modify: `VirgoTests/GameplayViewModelScoringTests.swift`
- Modify: `VirgoTests/GameplayViewModelSpeedTests.swift`

**Interfaces:**
- Produces: `RhythmNoteTarget`, `InputTimingConfiguration.timeline/legacy`.
- Changes: `NoteMatchResult` carries event/tick/seconds fields; timeline matching contains no `Note` reference.

- [ ] **Step 1: Write failing shortened-bar and snapshot-isolation tests**

Prove a hit immediately after a shortened bar matches its cumulative target; same-time different-drum targets remain distinct; duplicate scoring keys use event IDs; a target exactly 100 ms late becomes a miss at the existing boundary; and timeline callback matching succeeds after original SwiftData objects are released from the runtime queue's scope.

- [ ] **Step 2: Add immutable target/configuration values**

```swift
struct RhythmNoteTarget: Hashable, Sendable {
    let eventID: RhythmEventID
    let drumType: DrumType
    let position: RhythmEventPosition
    let targetSecondsAtOneX: Double
}

enum InputTimingConfiguration {
    case timeline(targets: [RhythmNoteTarget], timeline: RhythmTimeline, speed: Double)
    case legacy(bpm: Double, timeSignature: TimeSignature, notes: [Note])
}
```

Validate positive finite speed. Timeline matcher sorts by effective target seconds then event ID and computes `targetSecondsAtOneX / speed`.

- [ ] **Step 3: Make `NoteMatchResult` timing-complete**

Add optional timeline fields `matchedEventID`, `matchedTargetPosition`, `matchedTargetSeconds`, `hitSongSeconds`, and `hitPosition`. Retain `matchedNote`, `measureNumber`, and `measureOffset` only for the legacy result. Keep accuracy windows and millisecond-error sign unchanged.

- [ ] **Step 4: Atomically replace the matcher in `InputManager.configure(_:)`**

Build the immutable matcher before entering `runtimeStateQueue`, then replace configuration and elapsed origin in one queue mutation. Keep `configure(bpm:timeSignature:notes:)` as a legacy forwarding wrapper so existing callers/tests remain source-compatible during migration.

- [ ] **Step 5: Migrate gameplay scoring and missed-note scans**

Cache `[RhythmEventID: Note]` on MainActor. For timeline results, use event ID for duplicate suppression/UI lookup, call `scanForMissedNotes(upToSeconds:)`, and advance a target-seconds-sorted cursor with the unchanged 100 ms late window. Do not reconstruct fractional measure positions.

- [ ] **Step 6: Reconfigure atomically on speed changes**

In `applySpeedChangeInternal`, capture current musical elapsed seconds using the old configuration, install identical one-X targets with new speed, and reseat the input elapsed origin together with BGM/metronome/playhead restart. Paused changes install immediately and defer only the shared-clock reseat until resume. Never regenerate event IDs or briefly configure legacy matching.

- [ ] **Step 7: Run input/scoring regressions**

```bash
rtk xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' -configuration Debug -only-testing:VirgoTests/RhythmInputTimingTests -only-testing:VirgoTests/InputTimingMatcherTests -only-testing:VirgoTests/InputManagerConfigurationTests -only-testing:VirgoTests/InputManagerBoundaryTests -only-testing:VirgoTests/GameplayViewModelScoringTests -only-testing:VirgoTests/GameplayViewModelSpeedTests -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -derivedDataPath ./DerivedData
rtk git diff --check
```

- [ ] **Step 8: Commit timeline input/scoring**

```bash
rtk git add Virgo/utilities/InputTimingMatcher.swift Virgo/utilities/InputManager.swift Virgo/views/GameplayView+InputManagerDelegate.swift Virgo/viewmodels/GameplayViewModel.swift Virgo/viewmodels/GameplayViewModel+Computations.swift Virgo/viewmodels/GameplayViewModel+SpeedControl.swift VirgoTests/RhythmInputTimingTests.swift VirgoTests/InputTimingMatcherTests.swift VirgoTests/InputManagerConfigurationTests.swift VirgoTests/InputManagerBoundaryTests.swift VirgoTests/GameplayViewModelScoringTests.swift VirgoTests/GameplayViewModelSpeedTests.swift
rtk git commit -m "feat: score immutable rhythm targets"
```

---

### Task 8: Timeline Gameplay, Metronome Schedule, BGM Anchor, and Duration Precedence

**Files:**
- Create: `Virgo/utilities/RhythmMetronomeSchedule.swift`
- Modify: `Virgo/utilities/MetronomeTimingEngine.swift`
- Modify: `Virgo/utilities/MetronomeEngine.swift`
- Modify: `Virgo/viewmodels/GameplayViewModel.swift`
- Modify: `Virgo/viewmodels/GameplayViewModel+Computations.swift`
- Modify: `Virgo/viewmodels/GameplayViewModel+VisualUpdates.swift`
- Modify: `Virgo/viewmodels/GameplayViewModel+Playback.swift`
- Modify: `Virgo/viewmodels/GameplayViewModel+SpeedControl.swift`
- Modify: `Virgo/viewmodels/GameplayViewModel+BGM.swift`
- Modify: `Virgo/views/subviews/GameplaySheetMusicView.swift`
- Create: `VirgoTests/RhythmMetronomeScheduleTests.swift`
- Create: `VirgoTests/RhythmTimelineIntegrationTests.swift`
- Modify: `VirgoTests/MetronomeTimingEngineTests.swift`
- Modify: `VirgoTests/MetronomeEngineTests.swift`
- Modify: `VirgoTests/GameplayViewModelComputationsTests.swift`
- Modify: `VirgoTests/GameplayViewModelVisualUpdatesTests.swift`
- Modify: `VirgoTests/GameplayViewModelPlaybackTimingTests.swift`
- Modify: `VirgoTests/GameplayViewModelPlaybackResumeTests.swift`
- Modify: `VirgoTests/GameplayViewModelBGMTimelineTests.swift`
- Modify: `VirgoTests/GameplayViewModelPlaybackBGMCoverageTests.swift`

**Interfaces:**
- Produces: `RhythmMetronomeSchedule`, `RhythmMetronomePulse`, `RhythmScheduleCursor`.
- Changes: valid-timeline gameplay state uses resolved elapsed tick/measure/local tick everywhere.

- [ ] **Step 1: Write failing pulse-policy and cursor-race tests**

Cover quarter pulses/accented group starts for X/4; eighth pulses/dotted-quarter accents for 6/8, 9/8, and 12/8; only downbeat accent in 7/8; residual group accents in shortened/extended bars; and no pulse outside a measure's duration. Cover cancellation between lookup and callback and reseating immediately before/after a shortened barline.
Also prove an exact pulse count of 49,152 is accepted and 49,153 is rejected before allocation with
`rhythmMaterializationLimitExceeded`.

- [ ] **Step 2: Implement immutable schedule and locked cursor**

```swift
struct RhythmMetronomeSchedule: Hashable, Sendable {
    let pulses: [RhythmMetronomePulse]
}

final class RhythmScheduleCursor: @unchecked Sendable {
    private let lock = NSLock()
    private let schedule: RhythmMetronomeSchedule
    private var nextPulseIndex: Int
}
```

Preflight the chart-wide pulse count with checked arithmetic before constructing the array. Apply
`RhythmLimits.maximumMaterializedRhythmUnitCount` independently from the already-materialized beat-group count; never
emit a truncated schedule.

Only the serial timer queue consumes next pulses. MainActor cancellation/reseat uses lock-guarded methods. Every callback captures the playback token and cursor generation so cancelled work cannot advance a replacement.

- [ ] **Step 3: Add timeline schedule support beside legacy beat scheduling**

Keep `MetronomeBeatSchedule` and fixed beat counters for `.legacy`. Add a timeline configuration to `MetronomeTimingEngine`/`MetronomeEngine` that schedules immutable pulse offsets from the shared start time. Pause/resume/seek/speed changes create a newly binary-seated cursor; they never increment the old cursor index.

- [ ] **Step 4: Cache one resolved timeline during gameplay setup**

In `GameplayViewModel`, store availability, immutable timeline, resolved layout snapshot, target snapshot, metronome schedule, event-ID note lookup, and diagnostics together before layout/input/audio setup. Fatal availability must short-circuit every gameplay starter.

- [ ] **Step 5: Migrate elapsed position, row, playhead, and miss scan**

For valid timelines, convert shared elapsed seconds to a continuous absolute tick, binary-search its measure, and calculate measure-local x through `TabGrid.xPosition(in:localTick:)`. Use the resolved measure for row transitions and cached beat positions. Leave all fixed `secondsPerMeasure` and beat-fraction formulas inside named legacy branches.

- [ ] **Step 6: Resolve BGM from the chart-owned raw anchor**

Project `metadata.bgmStartAnchor` through `RhythmTimeline`. If absent, use the earliest playable event position, then zero. Consult `Song.bgmStartOffsetSeconds` only in legacy mode. Preserve the shared `CFAbsoluteTime` start and current AVAudio scheduling strategy.

- [ ] **Step 7: Enforce duration precedence and resume semantics**

Make `RhythmTimeline.endSeconds` authoritative for session progress, score completion, notation measure count, metronome schedule, and stopping long audio. Allow short audio to end while the shared metronome clock continues. Use `AVAudioPlayer.duration` only to bound media operations and `Song.duration` only for library/legacy behavior. Resume maps media time plus the chart anchor back to musical elapsed seconds; after early media completion, use the shared clock.

- [ ] **Step 8: Complete the fixed-measure reader audit**

Run:

```bash
rtk rg -n "beatsPerMeasure|secondsPerMeasure|beatInterval|trackDurationInSeconds|cachedLayoutMeasureCount|bgmStartOffsetSeconds|Song\.duration|\.duration" Virgo/viewmodels Virgo/utilities/InputTimingMatcher.swift Virgo/utilities/InputManager.swift Virgo/utilities/MetronomeTimingEngine.swift Virgo/utilities/MetronomeEngine.swift
```

For every hit, add an explicit `.valid` timeline branch, retain it inside a clearly named legacy helper, or remove it. Add integration assertions for setup duration, cached beats, BGM offset, resume, continuous playhead, row changes, miss scan, current-beat wrapping, and pause/resume offsets.

- [ ] **Step 9: Run gameplay/audio regressions sequentially**

```bash
rtk xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' -configuration Debug -only-testing:VirgoTests/RhythmMetronomeScheduleTests -only-testing:VirgoTests/RhythmTimelineIntegrationTests -only-testing:VirgoTests/MetronomeTimingEngineTests -only-testing:VirgoTests/MetronomeEngineTests -only-testing:VirgoTests/GameplayViewModelComputationsTests -only-testing:VirgoTests/GameplayViewModelVisualUpdatesTests -only-testing:VirgoTests/GameplayViewModelPlaybackTimingTests -only-testing:VirgoTests/GameplayViewModelPlaybackResumeTests -only-testing:VirgoTests/GameplayViewModelBGMTimelineTests -only-testing:VirgoTests/GameplayViewModelPlaybackBGMCoverageTests -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -derivedDataPath ./DerivedData
rtk git diff --check
```

- [ ] **Step 10: Commit gameplay scheduling**

```bash
rtk git add Virgo/utilities/RhythmMetronomeSchedule.swift Virgo/utilities/MetronomeTimingEngine.swift Virgo/utilities/MetronomeEngine.swift Virgo/viewmodels/GameplayViewModel.swift Virgo/viewmodels/GameplayViewModel+Computations.swift Virgo/viewmodels/GameplayViewModel+VisualUpdates.swift Virgo/viewmodels/GameplayViewModel+Playback.swift Virgo/viewmodels/GameplayViewModel+SpeedControl.swift Virgo/viewmodels/GameplayViewModel+BGM.swift Virgo/views/subviews/GameplaySheetMusicView.swift VirgoTests/RhythmMetronomeScheduleTests.swift VirgoTests/RhythmTimelineIntegrationTests.swift VirgoTests/MetronomeTimingEngineTests.swift VirgoTests/MetronomeEngineTests.swift VirgoTests/GameplayViewModelComputationsTests.swift VirgoTests/GameplayViewModelVisualUpdatesTests.swift VirgoTests/GameplayViewModelPlaybackTimingTests.swift VirgoTests/GameplayViewModelPlaybackResumeTests.swift VirgoTests/GameplayViewModelBGMTimelineTests.swift VirgoTests/GameplayViewModelPlaybackBGMCoverageTests.swift
rtk git commit -m "feat: drive gameplay from rhythm timeline"
```

---

### Task 9: Transactional Import, Fatal Library Records, and Idempotent Backfill

**Files:**
- Create: `Virgo/utilities/RhythmBackfillVersionStore.swift`
- Modify: `Virgo/utilities/DTXFileParser.swift`
- Modify: `Virgo/utilities/LocalDTXFixtureImporter.swift`
- Modify: `Virgo/utilities/ServerSongDownloader.swift`
- Modify: `Virgo/views/ContentView.swift`
- Modify: `Virgo/components/DifficultyExpansionView.swift`
- Modify: `Virgo/views/GameplayView.swift`
- Create: `VirgoTests/RhythmImportBackfillTests.swift`
- Modify: `VirgoTests/LocalDTXFixtureImporterTests.swift`
- Modify: `VirgoTests/LocalDTXControlBackfillTests.swift`
- Modify: `VirgoTests/ServerSongDownloaderNormalizationTests.swift`
- Modify: `VirgoTests/ContentViewTests.swift`
- Modify: `VirgoTests/GameplayViewTests.swift`

**Interfaces:**
- Produces: transactional projection/persistence helper shared by local and server importers.
- Produces: injectable `RhythmBackfillVersionStore` with current version and completion-after-save semantics.
- Changes: fatal rhythm charts remain visible but practice controls are disabled.

- [ ] **Step 1: Write failing local/server import tests**

For fresh valid imports, assert matching `Chart.timeSignature`, non-`nil` metadata, raw BGM anchor, canonical cumulative note/control fields, optional terminal duration evidence, and no update to `Song.bgmStartOffsetSeconds`. For fatal rhythm imports, assert the chart persists with diagnostics and source-identity notes/controls whose canonical fields are nil.

- [ ] **Step 2: Extract one transaction-shaped chart projection**

Implement one helper used by both importers:

```swift
struct DTXChartPersistenceProjection {
    let chartMetadata: ChartRhythmMetadata
    let timeSignature: TimeSignature
    let notes: [ImportedNoteValues]
    let controls: [ImportedControlValues]
    let warning: DTXImportWarning?
}
```

The helper parses, builds the timeline, and emits canonical values before either importer mutates SwiftData. Valid projection writes per-measure `normalizedTicksPerMeasure` and cumulative `normalizedAbsoluteTick`. Fatal projection writes source identity and placeholder intervals but leaves all canonical timing nil.

- [ ] **Step 3: Wire fresh local and server imports**

Persist chart metadata before notes/controls, then save the complete graph. Return a specific fatal-rhythm warning while keeping the library record. Preserve throwing behavior for base identity failures. Existing server charts receive new metadata only on a fresh download; add no background network migration.

- [ ] **Step 4: Add versioned local backfill state**

```swift
protocol RhythmBackfillVersionStoring {
    func completedVersion() -> Int
    func markCompleted(version: Int)
}

struct RhythmBackfillVersionStore: RhythmBackfillVersionStoring {
    static let currentVersion = 1
}
```

Use an injected isolated `UserDefaults` in tests. If stored version equals current, skip all reparsing. During a pass, skip every chart whose `rhythmMetadataData` is non-`nil`, including corrupt bytes. Reparse missing-payload charts with available local sources and rewrite metadata plus note/control normalized timing together.

- [ ] **Step 5: Mark completion only after the entire save succeeds**

Run backfill from `ContentView.seedLocalDTXFixtures()` after the bundled song is found or created. Scan all eligible charts, call `ModelContext.save()`, then mark the version. Inject a failing save/parser seam and prove failure leaves the version unset so the next launch retries. Prove a second successful launch performs zero DTX reparses.

- [ ] **Step 6: Disable practice without hiding fatal charts**

Expose a chart practice state derived from `rhythmMetadataState`/resolver availability. In `ChartSelectionCard`, retain the row and score button, display a localized warning badge, disable the play button, and provide an accessibility explanation. In `GameplayView`, guard direct/deep-linked entry with a fatal status panel and no play, input, metronome, or BGM startup.

- [ ] **Step 7: Remove the parser/import legacy BGM adapter**

After both importers and backfill use the raw anchor, remove `DTXChartData.bgmStartOffsetSeconds` and every fixed `4 * 60 / bpm` parser calculation. Confirm `Song.setBGMStartOffsetIfUnset` remains reachable only from explicitly legacy import/fixture code or remove its newly dead timeline call sites without changing existing stored songs.

- [ ] **Step 8: Run import/UI regressions**

```bash
rtk xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' -configuration Debug -only-testing:VirgoTests/RhythmImportBackfillTests -only-testing:VirgoTests/LocalDTXFixtureImporterTests -only-testing:VirgoTests/LocalDTXControlBackfillTests -only-testing:VirgoTests/ServerSongDownloaderNormalizationTests -only-testing:VirgoTests/ContentViewTests -only-testing:VirgoTests/GameplayViewTests -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -derivedDataPath ./DerivedData
rtk git diff --check
```

- [ ] **Step 9: Commit importer/backfill integration**

```bash
rtk git add Virgo/utilities/RhythmBackfillVersionStore.swift Virgo/utilities/DTXFileParser.swift Virgo/utilities/LocalDTXFixtureImporter.swift Virgo/utilities/ServerSongDownloader.swift Virgo/views/ContentView.swift Virgo/components/DifficultyExpansionView.swift Virgo/views/GameplayView.swift VirgoTests/RhythmImportBackfillTests.swift VirgoTests/LocalDTXFixtureImporterTests.swift VirgoTests/LocalDTXControlBackfillTests.swift VirgoTests/ServerSongDownloaderNormalizationTests.swift VirgoTests/ContentViewTests.swift VirgoTests/GameplayViewTests.swift
rtk git commit -m "feat: persist and backfill chart rhythm timelines"
```

---

### Task 10: Cross-System Fixtures, Legacy Proof, and Final Verification

**Files:**
- Modify: `VirgoTests/RhythmTimelineIntegrationTests.swift`
- Modify: `VirgoTests/DTXControlImportIntegrationTests.swift`
- Modify: `VirgoTests/ScoringIntegrationTests.swift`
- Modify: `VirgoTests/GameplayViewModelLayoutComputationsTests.swift`
- Modify: `VirgoTests/SwiftUIRenderingCoverageTests.swift`
- Modify: production files only when a failing integration assertion exposes a contract violation.

**Interfaces:**
- Verifies: one event ID/position/seconds path across parser, persistence, resolver, semantic analysis, layout, input, scoring, metronome, BGM, playhead, and completion.

- [ ] **Step 1: Add a deterministic valid integration fixture**

Use one DTX string containing explicit 6/8 straight feel, a `0.75` pickup, a later `1.5` extended measure, dotted material, a note/rest/note triplet, a control chip, a raw lane-01 anchor, 32nd notes, and 64th notes. Parse and persist it through the real projection helper.

- [ ] **Step 2: Assert identity and time agreement end to end**

For selected events, assert the same `RhythmEventID` and `RhythmEventPosition` appear in resolved events, `RhythmLayoutNote`, `RenderedNoteHead`, `RhythmNoteTarget`, cached gameplay beats, and scoring results. Assert layout x, target seconds, metronome pulse offset, BGM anchor seconds, playhead position, missed-note scan, and session completion all derive from the same timeline values.

- [ ] **Step 3: Add exact-but-unsupported and fatal fixtures**

Use a timing-valid 7/8 fixture to prove exact playback/scoring, seven isochronous pulses with only downbeat accent, exact notehead positions, and measure warning without duration-bearing engraving. Use corrupt persisted bytes and malformed explicit feel fixtures to prove fatal state, visible library row, and zero layout/input/metronome/BGM startup.

- [ ] **Step 4: Prove legacy behavior remains intact**

Create a missing-payload DTX chart and assert the existing fixed-measure layout/input/metronome/BGM path. Create a metadata-free manual chart whose offsets rationalize and assert synthesized timeline behavior. Create a manual chart whose offsets cannot fit the bounded resolution and assert it remains playable through legacy with runtime `manualTimelineUnavailable` only.

- [ ] **Step 5: Run the focused integration matrix**

```bash
rtk xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' -configuration Debug -only-testing:VirgoTests/RhythmTimelineIntegrationTests -only-testing:VirgoTests/DTXControlImportIntegrationTests -only-testing:VirgoTests/ScoringIntegrationTests -only-testing:VirgoTests/GameplayViewModelLayoutComputationsTests -only-testing:VirgoTests/SwiftUIRenderingCoverageTests -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -derivedDataPath ./DerivedData
```

Expected: every integration suite passes with no legacy fixture expectation changed unless it explicitly opts into metadata.

- [ ] **Step 6: Run the full macOS unit suite**

```bash
rtk xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' -configuration Debug -only-testing:VirgoTests -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -enableCodeCoverage YES -destination-timeout 300 -derivedDataPath ./DerivedData
```

Expected: all `VirgoTests` pass; the result reports a nonzero executed-test count.

- [ ] **Step 7: Run lint and macOS build**

```bash
rtk swiftlint lint
rtk xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' -parallel-testing-enabled NO build
```

Expected: no SwiftLint errors and `** BUILD SUCCEEDED **`.

- [ ] **Step 8: Discover and build an available iPad simulator**

```bash
rtk xcrun simctl list devices available
```

Choose an available iPad name from the command output, then run:

```bash
rtk xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M4)' -parallel-testing-enabled NO build
```

If that exact iPad is unavailable, substitute only another listed iPad simulator. Expected: `** BUILD SUCCEEDED **`; do not use an iPhone destination.

- [ ] **Step 9: Scan for forbidden fallbacks and fixed-timing leakage**

```bash
rtk rg -n "visualDurationCandidates.*\?\? \.quarter|4\.0 \* 60\.0 / bpm|rhythmMetadataData.*nil|try\? ChartRhythmMetadataCodec|secondsPerMeasure|beatsPerMeasure|tickIndex\(forBeatWithinMeasure" Virgo
```

Review every hit. The first four patterns must have no timeline-path matches. Fixed-measure/tick-index hits must be tests or clearly named legacy helpers.

- [ ] **Step 10: Review the final diff and commit integration coverage**

```bash
rtk git diff --check
rtk git status --short
rtk git diff --stat
rtk git add Virgo VirgoTests
rtk git commit -m "test: verify rhythm timeline integration"
```

Expected: the commit contains only HPA-145 production/test changes and leaves the worktree clean.

---

## Acceptance Mapping

- **Tuplets:** Task 4 recognizes/rest-reserves 3:2 groups; Tasks 5–6 lay out and paint them; Task 10 verifies identity and timing end to end.
- **Dotted rhythms:** Task 4 names exact single-dotted values and decomposes rests; Task 6 paints dots and accounts for their bounds.
- **Compound meter:** Tasks 2–4 parse explicit meter and create dotted-quarter beat groups; Task 8 creates matching audible pulses/accents.
- **DTX measure length:** Tasks 2–3 parse exact channel `02` ratios and build cumulative variable measures; Task 5 scales widths and row packing.
- **Corrupt payload safety:** Tasks 1 and 3 preserve missing/valid/invalid state and forbid invalid-to-legacy fallback; Tasks 9–10 disable fatal practice while keeping library records.
- **Input/scoring:** Task 7 carries immutable event/tick/seconds snapshots and atomically reseats them on speed changes.
- **BGM/duration:** Task 8 resolves the raw chart anchor and makes timeline end authoritative; Task 9 removes fixed-4/4 parser seconds.
- **Painted extents:** Task 6 makes every primitive report bounds and derives all layout extents from one union.
- **Terminal provenance:** Task 2 removes `?? .quarter`; Task 4 distinguishes trusted candidate from indeterminate onset.
- **Resource/boundary safety:** Tasks 1, 3, and 8 validate 4,096 limits, the 49,152 per-collection materialization cap, checked arithmetic, exact-Double bounds, and `measureOffset == 1.0` rollover.
- **Legacy compatibility:** Tasks 3, 5, 7, 8, and 10 retain and explicitly test the existing fixed-measure path.
