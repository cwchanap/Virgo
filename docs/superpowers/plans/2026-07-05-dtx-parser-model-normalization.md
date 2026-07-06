# DTX Parser Model Normalization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Normalize DTX parser and persisted model data so raw chip identity, shared tick timing, and visual-duration candidates survive import for later drum-tab rendering work.

**Architecture:** Keep the implementation narrow: `DTXFileParser.swift` owns parser chips, normalized rhythmic events, lane mapping, tick normalization, and `DTXChartData.toNotes(for:)`; `DrumTrack.swift` owns persisted `Note` metadata. Existing gameplay/layout code continues to consume `Note.interval`, `noteType`, `measureNumber`, and `measureOffset` until HPA-140 through HPA-143 use the richer fields.

**Tech Stack:** Swift 5.9, SwiftData `@Model`, Swift Testing, Xcode/xcodebuild on macOS with parallel testing disabled.

---

## File Structure

- Modify `Virgo/models/DrumTrack.swift`
  - Add SwiftData-compatible enum metadata for note origin, notation voice candidate, and articulation candidate.
  - Extend `Note` with optional source/raw DTX fields and normalized timing fields.
  - Keep the existing initializer source-compatible by defaulting every new field.
  - Copy the new metadata in the existing template-note clone path.

- Modify `Virgo/utilities/DTXFileParser.swift`
  - Evolve `DTXNote` into parser-chip data by adding alias accessors: `measureIndex`, `gridPosition`, and `gridSize`.
  - Add `NormalizedRhythmicEvent`.
  - Add chart-level shared tick normalization using LCM of playable chip grid sizes.
  - Add visual-duration candidate inference from next-chip spacing, not raw grid size alone.
  - Map DTX lane `1C` to `.bass`.
  - Convert `DTXChartData.toNotes(for:)` through `normalizedRhythmicEvents()`.

- Modify `VirgoTests/DTXFileParserTests.swift`
  - Add failing tests for lane `1C`, raw identity persistence, shared tick normalization, non-power-of-two grids, sparse high-resolution grids, and BGM offset preservation.
  - Replace the old unknown-grid interval fallback assertion.

## Task 1: Add Failing Parser And Import Tests

**Files:**
- Modify: `VirgoTests/DTXFileParserTests.swift:220-228`
- Modify: `VirgoTests/DTXFileParserTests.swift:244-258`
- Modify: `VirgoTests/DTXFileParserTests.swift:434-457`

- [ ] **Step 1: Update parser-chip eighth-note expectations**

Replace `testParseEighthNotes()` with:

```swift
@Test func testParseEighthNotes() throws {
    // Test eighth-grid chips: #00211: 0I0J0I0J0I0J0I0J
    let eighthNoteLine = "#00211: 0I0J0I0J0I0J0I0J"
    let eighthNotes = try DTXFileParser.parseNoteLine(eighthNoteLine)

    #expect(eighthNotes.count == 8)
    #expect(eighthNotes[0].totalPositions == 8)
    #expect(eighthNotes[0].gridSize == 8)
    #expect(eighthNotes[0].gridPosition == 0)
}
```

- [ ] **Step 2: Update lane mapping expectations**

Replace `testDTXLaneMapping()` with:

```swift
@Test func testDTXLaneMapping() throws {
    #expect(DTXLane.bd.noteType == .bass)
    #expect(DTXLane.lb.noteType == .bass)
    #expect(DTXLane.sn.noteType == .snare)
    #expect(DTXLane.hhc.noteType == .hiHat)
    #expect(DTXLane.hh.noteType == .openHiHat)
    #expect(DTXLane.cy.noteType == .crash)
    #expect(DTXLane.rd.noteType == .ride)
    #expect(DTXLane.ht.noteType == .highTom)
    #expect(DTXLane.lt.noteType == .midTom)
    #expect(DTXLane.ft.noteType == .lowTom)

    // Non-playable lanes
    #expect(DTXLane.bpm.noteType == nil)
    #expect(DTXLane.bgm.noteType == nil)
}
```

- [ ] **Step 3: Replace the old unknown-grid interval test**

Delete `testDTXNoteIntervalConversions()` and add these tests at the end of `DTXFileParserTests` before the closing `}`:

```swift
@Test("lane 1C imports as bass and preserves DTX source identity")
func testLane1CImportsAsBassWithSourceIdentity() throws {
    let dtxContent = """
    #TITLE: Left Bass
    #ARTIST: Tester
    #BPM: 120
    #DLEVEL: 50
    #0011C: 000A0000
    """

    let chartData = try DTXFileParser.parseChartMetadata(from: dtxContent)
    let rawChip = try #require(chartData.notes.first)
    #expect(rawChip.laneID == "1C")
    #expect(rawChip.noteID == "0A")
    #expect(rawChip.measureIndex == 1)
    #expect(rawChip.gridPosition == 1)
    #expect(rawChip.gridSize == 4)
    #expect(rawChip.toNoteType() == .bass)

    let chart = Chart(difficulty: .medium)
    let note = try #require(chartData.toNotes(for: chart).first)

    #expect(note.noteType == .bass)
    #expect(note.originKind == .dtx)
    #expect(note.sourceLaneID == "1C")
    #expect(note.sourceNoteID == "0A")
    #expect(note.sourceGridPosition == 1)
    #expect(note.sourceGridSize == 4)
    #expect(note.normalizedMeasureIndex == 1)
    #expect(note.normalizedAbsoluteTick == 5)
    #expect(note.normalizedTickWithinMeasure == 1)
    #expect(note.normalizedTicksPerMeasure == 4)
    #expect(note.notationVoiceCandidate == .lower)
    #expect(note.visualDurationCandidate == .quarter)
    #expect(note.articulationCandidate == .some(.none))
}

@Test("normalized events use a shared chart-level tick scale across lane grids")
func testNormalizedEventsUseSharedChartTickScale() throws {
    let dtxContent = """
    #TITLE: Shared Tick Scale
    #ARTIST: Tester
    #BPM: 120
    #DLEVEL: 50
    #00113: 0101
    #00112: 00000001
    """

    let chartData = try DTXFileParser.parseChartMetadata(from: dtxContent)
    let events = chartData.normalizedRhythmicEvents()

    #expect(events.count == 3)
    #expect(Set(events.map(\.ticksPerMeasure)) == Set([4]))
    #expect(events.map(\.absoluteTick).sorted() == [4, 6, 7])

    let snare = try #require(events.first { $0.laneID == "12" })
    #expect(snare.gridSize == 4)
    #expect(snare.gridPosition == 3)
    #expect(snare.tickWithinMeasure == 3)
    #expect(snare.visualDurationCandidate == .quarter)
}

@Test("non-power-of-two grids preserve timing and avoid quarter fallback")
func testNonPowerOfTwoGridPreservesTicksAndVisualCandidate() throws {
    let dtxContent = """
    #TITLE: Triplet Grid
    #ARTIST: Tester
    #BPM: 120
    #DLEVEL: 50
    #00112: 010101000000000000000000
    """

    let chartData = try DTXFileParser.parseChartMetadata(from: dtxContent)
    let events = chartData.normalizedRhythmicEvents()

    #expect(events.count == 3)
    #expect(Set(events.map(\.ticksPerMeasure)) == Set([12]))
    #expect(events.map(\.tickWithinMeasure) == [0, 1, 2])
    #expect(events.map(\.absoluteTick) == [12, 13, 14])
    #expect(events.allSatisfy { $0.visualDurationCandidate != .quarter })

    let chart = Chart(difficulty: .medium)
    let notes = chartData.toNotes(for: chart)
    #expect(notes.count == 3)
    #expect(notes.allSatisfy { $0.normalizedTicksPerMeasure == 12 })
    #expect(notes.map(\.visualDurationCandidate) == [.some(.sixteenth), .some(.sixteenth), .some(.quarter)])
    #expect(notes.map(\.interval) == [.sixteenth, .sixteenth, .quarter])
}

@Test("sparse high-resolution grid preserves timing without forcing visual 32nd notes")
func testSparseHighResolutionGridKeepsTimingButReadableDuration() throws {
    let dtxContent = """
    #TITLE: Sparse High Resolution
    #ARTIST: Tester
    #BPM: 120
    #DLEVEL: 50
    #00113: 0000000000000000000000000000000000000000000000000000000000000001
    """

    let chartData = try DTXFileParser.parseChartMetadata(from: dtxContent)
    let event = try #require(chartData.normalizedRhythmicEvents().first)

    #expect(event.gridSize == 32)
    #expect(event.gridPosition == 31)
    #expect(event.ticksPerMeasure == 32)
    #expect(event.tickWithinMeasure == 31)
    #expect(event.absoluteTick == 63)
    #expect(event.visualDurationCandidate == .quarter)

    let chart = Chart(difficulty: .medium)
    let note = try #require(chartData.toNotes(for: chart).first)
    #expect(note.normalizedTicksPerMeasure == 32)
    #expect(note.normalizedTickWithinMeasure == 31)
    #expect(note.interval == .quarter)
    #expect(note.visualDurationCandidate == .quarter)
}
```

- [ ] **Step 4: Run the focused tests and verify they fail**

Run:

```bash
rtk xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' \
  -only-testing:VirgoTests/DTXFileParserTests \
  -parallel-testing-enabled NO test
```

Expected: FAIL at compile time because `DTXNote.measureIndex`, `DTXNote.gridPosition`, `DTXNote.gridSize`, `Note.originKind`, `Note.sourceLaneID`, `DTXChartData.normalizedRhythmicEvents()`, and related fields do not exist yet.

- [ ] **Step 5: Commit the failing tests**

```bash
rtk git add VirgoTests/DTXFileParserTests.swift
rtk git commit -m "test: cover DTX parser model normalization"
```

## Task 2: Extend The Persisted Note Model

**Files:**
- Modify: `Virgo/models/DrumTrack.swift:12-27`
- Modify: `Virgo/models/DrumTrack.swift:441-456`

- [ ] **Step 1: Add model enums above `@Model final class Note`**

Insert this code after the imports in `Virgo/models/DrumTrack.swift`:

```swift
enum NoteOriginKind: String, Codable, CaseIterable {
    case manual
    case dtx
}

enum NormalizedNotationVoice: String, Codable, CaseIterable {
    case upper
    case lower
}

enum NormalizedArticulation: String, Codable, CaseIterable {
    case none
}
```

- [ ] **Step 2: Replace the `Note` model declaration**

Replace the existing `Note` class with:

```swift
@Model
final class Note {
    var interval: NoteInterval
    var noteType: NoteType
    var measureNumber: Int
    var measureOffset: Double
    var chart: Chart?

    var originKind: NoteOriginKind
    var sourceLaneID: String?
    var sourceNoteID: String?
    var sourceGridPosition: Int?
    var sourceGridSize: Int?
    var normalizedMeasureIndex: Int?
    var normalizedAbsoluteTick: Int?
    var normalizedTickWithinMeasure: Int?
    var normalizedTicksPerMeasure: Int?
    var notationVoiceCandidate: NormalizedNotationVoice?
    var visualDurationCandidate: NoteInterval?
    var articulationCandidate: NormalizedArticulation?

    init(
        interval: NoteInterval,
        noteType: NoteType,
        measureNumber: Int,
        measureOffset: Double,
        chart: Chart? = nil,
        originKind: NoteOriginKind = .manual,
        sourceLaneID: String? = nil,
        sourceNoteID: String? = nil,
        sourceGridPosition: Int? = nil,
        sourceGridSize: Int? = nil,
        normalizedMeasureIndex: Int? = nil,
        normalizedAbsoluteTick: Int? = nil,
        normalizedTickWithinMeasure: Int? = nil,
        normalizedTicksPerMeasure: Int? = nil,
        notationVoiceCandidate: NormalizedNotationVoice? = nil,
        visualDurationCandidate: NoteInterval? = nil,
        articulationCandidate: NormalizedArticulation? = nil
    ) {
        self.interval = interval
        self.noteType = noteType
        self.measureNumber = measureNumber
        self.measureOffset = measureOffset
        self.chart = chart
        self.originKind = originKind
        self.sourceLaneID = sourceLaneID
        self.sourceNoteID = sourceNoteID
        self.sourceGridPosition = sourceGridPosition
        self.sourceGridSize = sourceGridSize
        self.normalizedMeasureIndex = normalizedMeasureIndex
        self.normalizedAbsoluteTick = normalizedAbsoluteTick
        self.normalizedTickWithinMeasure = normalizedTickWithinMeasure
        self.normalizedTicksPerMeasure = normalizedTicksPerMeasure
        self.notationVoiceCandidate = notationVoiceCandidate
        self.visualDurationCandidate = visualDurationCandidate
        self.articulationCandidate = articulationCandidate
    }
}
```

- [ ] **Step 3: Copy metadata in the template clone path**

In `Virgo/models/DrumTrack.swift`, find the `Note(` call inside `cloneTemplateSong` and replace it with:

```swift
Note(
    interval: templateNote.interval,
    noteType: templateNote.noteType,
    measureNumber: templateNote.measureNumber,
    measureOffset: templateNote.measureOffset,
    chart: chart,
    originKind: templateNote.originKind,
    sourceLaneID: templateNote.sourceLaneID,
    sourceNoteID: templateNote.sourceNoteID,
    sourceGridPosition: templateNote.sourceGridPosition,
    sourceGridSize: templateNote.sourceGridSize,
    normalizedMeasureIndex: templateNote.normalizedMeasureIndex,
    normalizedAbsoluteTick: templateNote.normalizedAbsoluteTick,
    normalizedTickWithinMeasure: templateNote.normalizedTickWithinMeasure,
    normalizedTicksPerMeasure: templateNote.normalizedTicksPerMeasure,
    notationVoiceCandidate: templateNote.notationVoiceCandidate,
    visualDurationCandidate: templateNote.visualDurationCandidate,
    articulationCandidate: templateNote.articulationCandidate
)
```

- [ ] **Step 4: Run tests and verify the model compiles**

Run:

```bash
rtk xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' \
  -only-testing:VirgoTests/NoteModelTests \
  -parallel-testing-enabled NO test
```

Expected: PASS for existing note model coverage. Existing manual notes should compile without passing any new initializer arguments.

- [ ] **Step 5: Commit the model changes**

```bash
rtk git add Virgo/models/DrumTrack.swift
rtk git commit -m "feat(model): persist DTX note normalization metadata"
```

## Task 3: Add Parser Chip Aliases And Normalized Event Types

**Files:**
- Modify: `Virgo/utilities/DTXFileParser.swift:29-40`
- Modify: `Virgo/utilities/DTXFileParser.swift:294-322`

- [ ] **Step 1: Replace `DTXNote` with chip-compatible fields and aliases**

Replace the existing `DTXNote` struct with:

```swift
struct DTXNote {
    let measureNumber: Int
    let laneID: String
    let noteID: String
    let notePosition: Int // Position within the measure (0-based)
    let totalPositions: Int // Total number of positions in this measure

    var measureIndex: Int {
        measureNumber
    }

    var gridPosition: Int {
        notePosition
    }

    var gridSize: Int {
        totalPositions
    }

    var measureOffset: Double {
        guard totalPositions > 0 else { return 0.0 }
        return Double(notePosition) / Double(totalPositions)
    }
}
```

- [ ] **Step 2: Add normalized event type after `DTXChartData`**

Insert this code after the closing brace of `DTXChartData`:

```swift
struct NormalizedRhythmicEvent: Hashable {
    let measureIndex: Int
    let absoluteTick: Int
    let tickWithinMeasure: Int
    let ticksPerMeasure: Int
    let voiceCandidate: NormalizedNotationVoice
    let laneID: String
    let noteID: String
    let gridPosition: Int
    let gridSize: Int
    let noteType: NoteType
    let visualDurationCandidate: NoteInterval
    let articulationCandidate: NormalizedArticulation
    let measureOffset: Double

    init?(
        chip: DTXNote,
        ticksPerMeasure: Int,
        visualDurationCandidate: NoteInterval,
        articulationCandidate: NormalizedArticulation = .none
    ) {
        guard let noteType = chip.toNoteType(),
              chip.gridSize > 0,
              ticksPerMeasure > 0,
              ticksPerMeasure.isMultiple(of: chip.gridSize) else {
            return nil
        }

        let tickScale = ticksPerMeasure / chip.gridSize
        let tickWithinMeasure = chip.gridPosition * tickScale

        self.measureIndex = chip.measureIndex
        self.absoluteTick = chip.measureIndex * ticksPerMeasure + tickWithinMeasure
        self.tickWithinMeasure = tickWithinMeasure
        self.ticksPerMeasure = ticksPerMeasure
        self.voiceCandidate = Self.voiceCandidate(for: noteType)
        self.laneID = chip.laneID.uppercased()
        self.noteID = chip.noteID.uppercased()
        self.gridPosition = chip.gridPosition
        self.gridSize = chip.gridSize
        self.noteType = noteType
        self.visualDurationCandidate = visualDurationCandidate
        self.articulationCandidate = articulationCandidate
        self.measureOffset = chip.measureOffset
    }

    private static func voiceCandidate(for noteType: NoteType) -> NormalizedNotationVoice {
        switch DrumType.from(noteType: noteType) {
        case .kick, .hiHatPedal:
            return .lower
        case .snare, .hiHat, .crash, .ride, .tom1, .tom2, .tom3, .cowbell, nil:
            return .upper
        }
    }
}
```

- [ ] **Step 3: Update `parseNoteLine` to normalize chip identity case**

Inside `parseNoteLine(_:)`, replace:

```swift
let laneIDString = String(headerPart.suffix(2))
```

with:

```swift
let laneIDString = String(headerPart.suffix(2)).uppercased()
```

and replace:

```swift
let noteID = String(noteArray[startIndex..<endIndex])
```

with:

```swift
let noteID = String(noteArray[startIndex..<endIndex]).uppercased()
```

- [ ] **Step 4: Run the focused tests and verify expected remaining failures**

Run:

```bash
rtk xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' \
  -only-testing:VirgoTests/DTXFileParserTests \
  -parallel-testing-enabled NO test
```

Expected: FAIL because `normalizedRhythmicEvents()` and `Note` conversion metadata are not implemented yet; parser aliases should no longer be missing.

- [ ] **Step 5: Commit parser event scaffolding**

```bash
rtk git add Virgo/utilities/DTXFileParser.swift
rtk git commit -m "feat(parser): add normalized rhythmic event model"
```

## Task 4: Implement Shared Tick Normalization And Visual Candidates

**Files:**
- Modify: `Virgo/utilities/DTXFileParser.swift:103-127`
- Modify: `Virgo/utilities/DTXFileParser.swift:294-357`

- [ ] **Step 1: Map DTX lane `1C` to bass**

In `DTXLane.noteType`, replace:

```swift
case .bd:
    return .bass
```

with:

```swift
case .bd, .lb:
    return .bass
```

Then replace:

```swift
case .bpm, .bgm, .lb:
    return nil // Not playable drum notes
```

with:

```swift
case .bpm, .bgm:
    return nil // Not playable drum notes
```

- [ ] **Step 2: Add normalized-event helpers to `DTXChartData`**

Inside `extension DTXChartData`, before `toNotes(for:)`, add:

```swift
func normalizedRhythmicEvents() -> [NormalizedRhythmicEvent] {
    let playableChips = notes.filter { $0.toNoteType() != nil }
    let ticksPerMeasure = Self.sharedTicksPerMeasure(for: playableChips)
    let visualDurations = Self.visualDurationCandidates(
        for: playableChips,
        ticksPerMeasure: ticksPerMeasure
    )

    return playableChips.compactMap { chip in
        NormalizedRhythmicEvent(
            chip: chip,
            ticksPerMeasure: ticksPerMeasure,
            visualDurationCandidate: visualDurations[Self.chipKey(chip)] ?? .quarter
        )
    }
}

private static func sharedTicksPerMeasure(for chips: [DTXNote]) -> Int {
    let gridSizes = chips
        .map(\.gridSize)
        .filter { $0 > 0 }

    guard !gridSizes.isEmpty else { return 1 }

    return gridSizes.reduce(1) { partialResult, gridSize in
        leastCommonMultiple(partialResult, gridSize)
    }
}

private static func leastCommonMultiple(_ lhs: Int, _ rhs: Int) -> Int {
    guard lhs > 0, rhs > 0 else { return 1 }
    return lhs / greatestCommonDivisor(lhs, rhs) * rhs
}

private static func greatestCommonDivisor(_ lhs: Int, _ rhs: Int) -> Int {
    var a = abs(lhs)
    var b = abs(rhs)

    while b != 0 {
        let remainder = a % b
        a = b
        b = remainder
    }

    return max(a, 1)
}

private static func visualDurationCandidates(
    for chips: [DTXNote],
    ticksPerMeasure: Int
) -> [String: NoteInterval] {
    let chipsByMeasure = Dictionary(grouping: chips, by: \.measureIndex)
    var result: [String: NoteInterval] = [:]

    for (_, measureChips) in chipsByMeasure {
        let sortedChips = measureChips.sorted {
            normalizedTick(for: $0, ticksPerMeasure: ticksPerMeasure)
            < normalizedTick(for: $1, ticksPerMeasure: ticksPerMeasure)
        }

        for (index, chip) in sortedChips.enumerated() {
            let currentTick = normalizedTick(for: chip, ticksPerMeasure: ticksPerMeasure)
            let nextTick = sortedChips.dropFirst(index + 1)
                .map { normalizedTick(for: $0, ticksPerMeasure: ticksPerMeasure) }
                .first { $0 > currentTick }

            let tickSpan = nextTick.map { $0 - currentTick } ?? max(ticksPerMeasure / 4, 1)
            result[chipKey(chip)] = closestInterval(toTickSpan: tickSpan, ticksPerMeasure: ticksPerMeasure)
        }
    }

    return result
}

private static func normalizedTick(for chip: DTXNote, ticksPerMeasure: Int) -> Int {
    guard chip.gridSize > 0, ticksPerMeasure > 0 else { return 0 }
    return chip.gridPosition * ticksPerMeasure / chip.gridSize
}

private static func chipKey(_ chip: DTXNote) -> String {
    "\(chip.measureIndex):\(chip.laneID.uppercased()):\(chip.noteID.uppercased()):\(chip.gridPosition):\(chip.gridSize)"
}

private static func closestInterval(toTickSpan tickSpan: Int, ticksPerMeasure: Int) -> NoteInterval {
    guard tickSpan > 0, ticksPerMeasure > 0 else { return .quarter }

    let target = Double(tickSpan) / Double(ticksPerMeasure)
    let supported: [(interval: NoteInterval, fraction: Double)] = [
        (.full, 1.0),
        (.half, 0.5),
        (.quarter, 0.25),
        (.eighth, 0.125),
        (.sixteenth, 0.0625),
        (.thirtysecond, 0.03125),
        (.sixtyfourth, 0.015625)
    ]

    return supported.min { lhs, rhs in
        abs(lhs.fraction - target) < abs(rhs.fraction - target)
    }?.interval ?? .quarter
}
```

- [ ] **Step 3: Update `DTXNote.toNoteInterval()` to route through the new candidate logic**

Replace `toNoteInterval()` with:

```swift
func toNoteInterval() -> NoteInterval {
    DTXChartData.closestVisualIntervalForSingleChip(self)
}
```

Then add this helper inside `extension DTXChartData`:

```swift
static func closestVisualIntervalForSingleChip(_ chip: DTXNote) -> NoteInterval {
    visualDurationCandidates(for: [chip], ticksPerMeasure: max(chip.gridSize, 1))[chipKey(chip)] ?? .quarter
}
```

This keeps existing callers compiling while removing the hard-coded unknown-grid quarter fallback from `DTXNote` itself.

- [ ] **Step 4: Run focused tests**

Run:

```bash
rtk xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' \
  -only-testing:VirgoTests/DTXFileParserTests \
  -parallel-testing-enabled NO test
```

Expected: FAIL in import conversion assertions because `toNotes(for:)` is still building notes directly from parser chips instead of normalized events.

- [ ] **Step 5: Commit normalization helpers**

```bash
rtk git add Virgo/utilities/DTXFileParser.swift
rtk git commit -m "feat(parser): normalize DTX chip timing"
```

## Task 5: Convert Imported DTX Notes Through Normalized Events

**Files:**
- Modify: `Virgo/utilities/DTXFileParser.swift:344-355`
- Test: `VirgoTests/DTXFileParserTests.swift`

- [ ] **Step 1: Replace `DTXChartData.toNotes(for:)`**

Replace `toNotes(for:)` with:

```swift
func toNotes(for chart: Chart) -> [Note] {
    normalizedRhythmicEvents().map { event in
        Note(
            interval: event.visualDurationCandidate,
            noteType: event.noteType,
            measureNumber: event.measureIndex + 1,
            measureOffset: event.measureOffset,
            chart: chart,
            originKind: .dtx,
            sourceLaneID: event.laneID,
            sourceNoteID: event.noteID,
            sourceGridPosition: event.gridPosition,
            sourceGridSize: event.gridSize,
            normalizedMeasureIndex: event.measureIndex,
            normalizedAbsoluteTick: event.absoluteTick,
            normalizedTickWithinMeasure: event.tickWithinMeasure,
            normalizedTicksPerMeasure: event.ticksPerMeasure,
            notationVoiceCandidate: event.voiceCandidate,
            visualDurationCandidate: event.visualDurationCandidate,
            articulationCandidate: event.articulationCandidate
        )
    }
}
```

- [ ] **Step 2: Run DTX parser tests**

Run:

```bash
rtk xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' \
  -only-testing:VirgoTests/DTXFileParserTests \
  -parallel-testing-enabled NO test
```

Expected: PASS.

- [ ] **Step 3: Run model tests for default compatibility**

Run:

```bash
rtk xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' \
  -only-testing:VirgoTests/NoteModelTests \
  -parallel-testing-enabled NO test
```

Expected: PASS. Existing manual notes should default to `.manual` and nil source metadata.

- [ ] **Step 4: Commit conversion changes**

```bash
rtk git add Virgo/utilities/DTXFileParser.swift
rtk git commit -m "feat(import): persist normalized DTX note metadata"
```

## Task 6: Run Full Focused Verification And Clean Up

**Files:**
- Modify only if compile/test failures identify mechanical follow-up in `Virgo/utilities/DTXFileParser.swift`, `Virgo/models/DrumTrack.swift`, or `VirgoTests/DTXFileParserTests.swift`.

- [ ] **Step 1: Run all Virgo unit tests with parallel testing disabled**

Run:

```bash
rtk xcodebuild test \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'platform=macOS' \
  -configuration Debug \
  -only-testing:VirgoTests \
  -parallel-testing-enabled NO \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  -enableCodeCoverage YES \
  -destination-timeout 300 \
  -derivedDataPath ./DerivedData
```

Expected: PASS.

- [ ] **Step 2: If SwiftLint is available, run lint**

Run:

```bash
rtk swiftlint lint
```

Expected: PASS or command unavailable. If unavailable, record that in the final implementation summary.

- [ ] **Step 3: Inspect the final diff**

Run:

```bash
rtk git diff --stat HEAD
rtk git diff HEAD -- Virgo/models/DrumTrack.swift Virgo/utilities/DTXFileParser.swift VirgoTests/DTXFileParserTests.swift
```

Expected: Only HPA-139 parser/model/test changes are present. No layout/rendering rewrite appears in the diff.

- [ ] **Step 4: Commit any cleanup from verification**

If Step 1 or Step 2 required mechanical fixes, commit them:

```bash
rtk git add Virgo/models/DrumTrack.swift Virgo/utilities/DTXFileParser.swift VirgoTests/DTXFileParserTests.swift
rtk git commit -m "fix: stabilize DTX normalization verification"
```

If no changes were required, skip this commit and keep the existing task commits.
