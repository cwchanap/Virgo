# Gameplay Note Rendering Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace view-inferred gameplay note geometry with a cached notation layout engine that improves dense-note readability, ledger lines, stem direction, beams, and lower/upper drum voice separation.

**Architecture:** Add a pure layout model in `Virgo/layout/` that turns SwiftData `Note` values into render primitives. `GameplayViewModel` caches the layout during setup, and `GameplaySheetMusicView` paints primitives instead of recalculating notation rules inside views.

**Tech Stack:** SwiftUI, SwiftData model types, Swift Testing, existing Xcode file-system-synchronized groups.

---

## File Structure

- Create `Virgo/layout/NotationLayout.swift`: value types for layout input, style, render primitives, voice, stem direction, and rendered geometry.
- Create `Virgo/layout/NotationLayoutEngine.swift`: pure engine for adaptive horizontal spacing, row wrapping, voice splitting, ledger lines, stems, and beams.
- Create `Virgo/views/NotationPrimitiveViews.swift`: small SwiftUI primitive painters for rendered noteheads, stems, beams, ledger lines, and measure bars.
- Modify `Virgo/viewmodels/GameplayViewModel.swift`: cache `NotationLayout`, expose lookup maps for active beat and progress indicator, and call `NotationLayoutEngine`.
- Modify `Virgo/views/subviews/GameplaySheetMusicView.swift`: render primitives from cached layout and keep existing staff/clef/time-signature layers.
- Modify `Virgo/layout/gameplay.swift`: keep existing constants, add only compatibility helpers if needed.
- Add `VirgoTests/NotationLayoutEngineTests.swift`: pure layout tests using Swift Testing.
- Existing `DrumBeatView.swift`, `BeamView.swift`, and `BeamGroupingLogic.swift` stay in the tree during migration. Remove or shrink them only after all rendering paths no longer depend on them.

Xcode uses `PBXFileSystemSynchronizedRootGroup`, so new Swift files under `Virgo/` and `VirgoTests/` should be picked up without editing `Virgo.xcodeproj/project.pbxproj`.

---

### Task 1: Add Layout Primitive Model

**Files:**
- Create: `Virgo/layout/NotationLayout.swift`
- Create: `VirgoTests/NotationLayoutEngineTests.swift`

- [ ] **Step 1: Write the failing primitive-model tests**

Create `VirgoTests/NotationLayoutEngineTests.swift` with:

```swift
import Testing
import SwiftUI
@testable import Virgo

@Suite("Notation Layout Engine Tests")
struct NotationLayoutEngineTests {
    @Test("default gameplay style preserves current low-density quarter spacing")
    func defaultStylePreservesQuarterSpacing() {
        let style = NotationLayoutStyle.gameplayDefault

        #expect(style.minimumNoteColumnGap == 28)
        #expect(style.minimumQuarterBeatGap == GameplayLayout.uniformSpacing)
        #expect(style.noteHeadWidth == GameplayLayout.beatColumnWidth)
    }

    @Test("drum types map to gameplay voices")
    func drumTypesMapToGameplayVoices() {
        #expect(NotationVoice.voice(for: .kick) == .lower)
        #expect(NotationVoice.voice(for: .hiHatPedal) == .lower)
        #expect(NotationVoice.voice(for: .snare) == .upper)
        #expect(NotationVoice.voice(for: .crash) == .upper)
    }

    @Test("layout input accepts notes and time signature")
    func layoutInputAcceptsNotesAndTimeSignature() {
        let note = Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0)
        let input = NotationLayoutInput(notes: [note], timeSignature: .fourFour)

        #expect(input.notes.count == 1)
        #expect(input.timeSignature.beatsPerMeasure == 4)
        #expect(input.style.minimumNoteColumnGap == 28)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' \
  -only-testing:VirgoTests/NotationLayoutEngineTests test
```

Expected: FAIL because `NotationLayoutStyle`, `NotationVoice`, and `NotationLayoutInput` are undefined.

- [ ] **Step 3: Add the primitive model**

Create `Virgo/layout/NotationLayout.swift`:

```swift
import CoreGraphics
import Foundation

struct NotationLayoutInput {
    let notes: [Note]
    let timeSignature: TimeSignature
    let style: NotationLayoutStyle

    init(
        notes: [Note],
        timeSignature: TimeSignature,
        style: NotationLayoutStyle = .gameplayDefault
    ) {
        self.notes = notes
        self.timeSignature = timeSignature
        self.style = style
    }
}

struct NotationLayoutStyle: Equatable {
    let minimumNoteColumnGap: CGFloat
    let minimumQuarterBeatGap: CGFloat
    let measurePadding: CGFloat
    let rowWidth: CGFloat
    let staffLineSpacing: CGFloat
    let noteHeadWidth: CGFloat
    let noteHeadHeight: CGFloat
    let stemLength: CGFloat
    let stemWidth: CGFloat
    let stemXInset: CGFloat
    let beamThickness: CGFloat
    let beamLevelSpacing: CGFloat
    let ledgerLineOverhang: CGFloat
    let voiceCollisionOffset: CGFloat

    static let gameplayDefault = NotationLayoutStyle(
        minimumNoteColumnGap: 28,
        minimumQuarterBeatGap: GameplayLayout.uniformSpacing,
        measurePadding: 16,
        rowWidth: GameplayLayout.maxRowWidth,
        staffLineSpacing: GameplayLayout.staffLineSpacing,
        noteHeadWidth: GameplayLayout.beatColumnWidth,
        noteHeadHeight: GameplayLayout.drumSymbolFontSize,
        stemLength: GameplayLayout.stemHeight,
        stemWidth: GameplayLayout.stemWidth,
        stemXInset: GameplayLayout.stemXOffset,
        beamThickness: 4,
        beamLevelSpacing: GameplayLayout.beamLevelSpacing,
        ledgerLineOverhang: 6,
        voiceCollisionOffset: 8
    )
}

enum NotationVoice: String, Hashable {
    case upper
    case lower

    static func voice(for drumType: DrumType) -> NotationVoice {
        switch drumType {
        case .kick, .hiHatPedal:
            return .lower
        case .crash, .hiHat, .tom1, .snare, .tom2, .tom3, .ride, .cowbell:
            return .upper
        }
    }
}

enum StemDirection: String, Hashable {
    case up
    case down
}

struct NotationLayout {
    var measures: [RenderedMeasure]
    var noteHeads: [RenderedNoteHead]
    var stems: [RenderedStem]
    var beams: [RenderedBeam]
    var ledgerLines: [RenderedLedgerLine]
    var measureBars: [RenderedMeasureBar]
    var beatLookup: [UInt64: CGPoint]
    var totalHeight: CGFloat
}

struct RenderedMeasure: Identifiable, Hashable {
    let id: Int
    let measureIndex: Int
    let row: Int
    let xOffset: CGFloat
    let width: CGFloat
}

struct RenderedNoteHead: Identifiable, Hashable {
    let id: UInt64
    let sourceNoteID: ObjectIdentifier
    let drumType: DrumType
    let voice: NotationVoice
    let timePosition: Double
    let measureIndex: Int
    let row: Int
    let position: CGPoint
    let staffStep: Int
    let stemDirection: StemDirection
    let interval: NoteInterval
}

struct RenderedStem: Identifiable, Hashable {
    let id: String
    let noteHeadIDs: [UInt64]
    let direction: StemDirection
    let start: CGPoint
    let end: CGPoint
}

struct RenderedBeam: Identifiable, Hashable {
    let id: String
    let noteHeadIDs: [UInt64]
    let direction: StemDirection
    let level: Int
    let start: CGPoint
    let end: CGPoint
    let thickness: CGFloat
}

struct RenderedLedgerLine: Identifiable, Hashable {
    let id: String
    let row: Int
    let start: CGPoint
    let end: CGPoint
}

struct RenderedMeasureBar: Identifiable, Hashable {
    let id: String
    let row: Int
    let x: CGFloat
    let isFinal: Bool
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:

```bash
xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' \
  -only-testing:VirgoTests/NotationLayoutEngineTests test
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Virgo/layout/NotationLayout.swift VirgoTests/NotationLayoutEngineTests.swift
git commit -m "Add notation layout primitives"
```

---

### Task 2: Implement Adaptive Measure Spacing

**Files:**
- Create: `Virgo/layout/NotationLayoutEngine.swift`
- Modify: `VirgoTests/NotationLayoutEngineTests.swift`

- [ ] **Step 1: Add failing spacing tests**

Append these tests inside `NotationLayoutEngineTests`:

```swift
@Test("sixteenth notes expand measure width for readable spacing")
func sixteenthNotesExpandMeasureWidthForReadableSpacing() {
    let notes = (0..<16).map { index in
        Note(
            interval: .sixteenth,
            noteType: .snare,
            measureNumber: 1,
            measureOffset: Double(index) / 16.0
        )
    }
    let layout = NotationLayoutEngine().layout(
        input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
    )
    let sortedX = layout.noteHeads.map(\.position.x).sorted()

    for index in 1..<sortedX.count {
        #expect(sortedX[index] - sortedX[index - 1] >= 28)
    }
    #expect(layout.measures.first?.width ?? 0 > GameplayLayout.measureWidth(for: .fourFour))
}

@Test("quarter notes keep existing spacing")
func quarterNotesKeepExistingSpacing() {
    let notes = (0..<4).map { index in
        Note(
            interval: .quarter,
            noteType: .snare,
            measureNumber: 1,
            measureOffset: Double(index) / 4.0
        )
    }
    let layout = NotationLayoutEngine().layout(
        input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
    )
    let sortedX = layout.noteHeads.map(\.position.x).sorted()

    #expect(sortedX.count == 4)
    #expect(abs((sortedX[1] - sortedX[0]) - GameplayLayout.uniformSpacing) < 0.001)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' \
  -only-testing:VirgoTests/NotationLayoutEngineTests test
```

Expected: FAIL because `NotationLayoutEngine` is undefined.

- [ ] **Step 3: Implement adaptive measure placement**

Create `Virgo/layout/NotationLayoutEngine.swift`:

```swift
import CoreGraphics
import Foundation

struct NotationLayoutEngine {
    func layout(input: NotationLayoutInput) -> NotationLayout {
        let normalizedNotes = input.notes.sorted {
            MeasureUtils.timePosition(measureNumber: $0.measureNumber, measureOffset: $0.measureOffset)
            < MeasureUtils.timePosition(measureNumber: $1.measureNumber, measureOffset: $1.measureOffset)
        }
        let totalMeasures = max(1, (normalizedNotes.map(\.measureNumber).max() ?? 1))
        let measures = buildMeasures(totalMeasures: totalMeasures, notes: normalizedNotes, input: input)
        let noteHeads = buildNoteHeads(notes: normalizedNotes, measures: measures, input: input)
        let measureBars = buildMeasureBars(measures: measures)
        let beatLookup = Dictionary(uniqueKeysWithValues: noteHeads.map { ($0.id, $0.position) })
        let totalHeight = GameplayLayout.totalHeight(
            for: measures.map {
                GameplayLayout.MeasurePosition(row: $0.row, xOffset: $0.xOffset, measureIndex: $0.measureIndex)
            }
        )

        return NotationLayout(
            measures: measures,
            noteHeads: noteHeads,
            stems: [],
            beams: [],
            ledgerLines: [],
            measureBars: measureBars,
            beatLookup: beatLookup,
            totalHeight: totalHeight
        )
    }

    private func buildMeasures(
        totalMeasures: Int,
        notes: [Note],
        input: NotationLayoutInput
    ) -> [RenderedMeasure] {
        var result: [RenderedMeasure] = []
        var currentRow = 0
        var currentX = GameplayLayout.leftMargin

        for measureIndex in 0..<totalMeasures {
            let width = measureWidth(measureIndex: measureIndex, notes: notes, input: input)
            if currentX + width > input.style.rowWidth, measureIndex > 0 {
                currentRow += 1
                currentX = GameplayLayout.leftMargin
            }
            result.append(
                RenderedMeasure(
                    id: measureIndex,
                    measureIndex: measureIndex,
                    row: currentRow,
                    xOffset: currentX,
                    width: width
                )
            )
            currentX += width + GameplayLayout.measureSpacing
        }

        return result
    }

    private func measureWidth(
        measureIndex: Int,
        notes: [Note],
        input: NotationLayoutInput
    ) -> CGFloat {
        let measureNumber = MeasureUtils.toOneBasedNumber(measureIndex)
        let offsets = notes
            .filter { $0.measureNumber == measureNumber }
            .map(\.measureOffset)
            .sorted()

        guard offsets.count > 1 else {
            return GameplayLayout.measureWidth(for: input.timeSignature)
        }

        let smallestGap = zip(offsets.dropFirst(), offsets)
            .map { later, earlier in later - earlier }
            .min() ?? 0.25
        let beatGap = max(
            input.style.minimumQuarterBeatGap,
            input.style.minimumNoteColumnGap / CGFloat(max(smallestGap * Double(input.timeSignature.beatsPerMeasure), 0.001))
        )
        return GameplayLayout.barLineWidth
            + input.style.measurePadding
            + CGFloat(input.timeSignature.beatsPerMeasure) * beatGap
            + input.style.measurePadding
    }

    private func buildNoteHeads(
        notes: [Note],
        measures: [RenderedMeasure],
        input: NotationLayoutInput
    ) -> [RenderedNoteHead] {
        var nextID: UInt64 = 0
        let measuresByIndex = Dictionary(uniqueKeysWithValues: measures.map { ($0.measureIndex, $0) })

        return notes.compactMap { note in
            guard let drumType = DrumType.from(noteType: note.noteType) else { return nil }
            let measureIndex = MeasureUtils.toZeroBasedIndex(note.measureNumber)
            guard let measure = measuresByIndex[measureIndex] else { return nil }
            let beatGap = beatGap(for: measure, input: input)
            let x = measure.xOffset + GameplayLayout.barLineWidth + input.style.measurePadding
                + CGFloat(note.measureOffset * Double(input.timeSignature.beatsPerMeasure)) * beatGap
            let y = GameplayLayout.StaffLinePosition.line1.absoluteY(for: measure.row)
                + drumType.notePosition.yOffset
            let id = nextID
            nextID += 1

            return RenderedNoteHead(
                id: id,
                sourceNoteID: ObjectIdentifier(note),
                drumType: drumType,
                voice: NotationVoice.voice(for: drumType),
                timePosition: MeasureUtils.timePosition(
                    measureNumber: note.measureNumber,
                    measureOffset: note.measureOffset
                ),
                measureIndex: measureIndex,
                row: measure.row,
                position: CGPoint(x: x, y: y),
                staffStep: staffStep(for: drumType.notePosition),
                stemDirection: .up,
                interval: note.interval
            )
        }
    }

    private func beatGap(for measure: RenderedMeasure, input: NotationLayoutInput) -> CGFloat {
        let drawableWidth = measure.width - GameplayLayout.barLineWidth - input.style.measurePadding * 2
        return drawableWidth / CGFloat(input.timeSignature.beatsPerMeasure)
    }

    private func staffStep(for position: GameplayLayout.NotePosition) -> Int {
        Int((position.yOffset / (GameplayLayout.staffLineSpacing / 2)).rounded())
    }

    private func buildMeasureBars(measures: [RenderedMeasure]) -> [RenderedMeasureBar] {
        measures.flatMap { measure in
            [
                RenderedMeasureBar(
                    id: "bar_\(measure.measureIndex)",
                    row: measure.row,
                    x: measure.xOffset,
                    isFinal: false
                ),
                RenderedMeasureBar(
                    id: "bar_\(measure.measureIndex)_end",
                    row: measure.row,
                    x: measure.xOffset + measure.width,
                    isFinal: measure.measureIndex == measures.last?.measureIndex
                )
            ]
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:

```bash
xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' \
  -only-testing:VirgoTests/NotationLayoutEngineTests test
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Virgo/layout/NotationLayoutEngine.swift VirgoTests/NotationLayoutEngineTests.swift
git commit -m "Add adaptive notation spacing"
```

---

### Task 3: Add Ledger Lines and Gameplay Voices

**Files:**
- Modify: `Virgo/layout/NotationLayoutEngine.swift`
- Modify: `VirgoTests/NotationLayoutEngineTests.swift`

- [ ] **Step 1: Add failing ledger and voice tests**

Append:

```swift
@Test("above-staff crash emits ledger line")
func aboveStaffCrashEmitsLedgerLine() {
    let note = Note(interval: .quarter, noteType: .crash, measureNumber: 1, measureOffset: 0)
    let layout = NotationLayoutEngine().layout(
        input: NotationLayoutInput(notes: [note], timeSignature: .fourFour)
    )

    #expect(layout.ledgerLines.count >= 1)
    #expect(layout.ledgerLines.allSatisfy { $0.end.x > $0.start.x })
}

@Test("kick and snare at same time get separate voices and readable x offsets")
func kickAndSnareAtSameTimeGetSeparateVoices() {
    let notes = [
        Note(interval: .eighth, noteType: .bass, measureNumber: 1, measureOffset: 0),
        Note(interval: .sixteenth, noteType: .snare, measureNumber: 1, measureOffset: 0)
    ]
    let layout = NotationLayoutEngine().layout(
        input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
    )

    let lower = layout.noteHeads.first { $0.voice == .lower }
    let upper = layout.noteHeads.first { $0.voice == .upper }

    #expect(lower != nil)
    #expect(upper != nil)
    #expect(abs((lower?.position.x ?? 0) - (upper?.position.x ?? 0)) >= 8)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' \
  -only-testing:VirgoTests/NotationLayoutEngineTests test
```

Expected: FAIL because ledger lines are empty and same-time voices have the same x position.

- [ ] **Step 3: Implement ledger lines and voice offsets**

In `NotationLayoutEngine.layout(input:)`, replace the `noteHeads` and return construction with:

```swift
let noteHeads = buildNoteHeads(notes: normalizedNotes, measures: measures, input: input)
let ledgerLines = buildLedgerLines(noteHeads: noteHeads, style: input.style)
let measureBars = buildMeasureBars(measures: measures)
let beatLookup = Dictionary(uniqueKeysWithValues: noteHeads.map { ($0.id, $0.position) })
```

Set `ledgerLines: ledgerLines` in the returned `NotationLayout`.

In `buildNoteHeads`, after calculating `x`, add voice collision offset:

```swift
let voice = NotationVoice.voice(for: drumType)
let collidesAcrossVoices = notes.contains { candidate in
    guard candidate !== note,
          candidate.measureNumber == note.measureNumber,
          abs(candidate.measureOffset - note.measureOffset) < 0.0001,
          let candidateDrum = DrumType.from(noteType: candidate.noteType) else {
        return false
    }
    return NotationVoice.voice(for: candidateDrum) != voice
}
let adjustedX = collidesAcrossVoices
    ? x + (voice == .upper ? input.style.voiceCollisionOffset : -input.style.voiceCollisionOffset)
    : x
```

Use `voice` and `adjustedX` in `RenderedNoteHead`.

Add this helper to `NotationLayoutEngine`:

```swift
private func buildLedgerLines(
    noteHeads: [RenderedNoteHead],
    style: NotationLayoutStyle
) -> [RenderedLedgerLine] {
    noteHeads.flatMap { head -> [RenderedLedgerLine] in
        let topStaffStep = -8
        let bottomStaffStep = 0
        let ledgerSteps: [Int]

        if head.staffStep < topStaffStep {
            ledgerSteps = stride(from: topStaffStep - 2, through: head.staffStep, by: -2).map { $0 }
        } else if head.staffStep > bottomStaffStep {
            ledgerSteps = stride(from: bottomStaffStep + 2, through: head.staffStep, by: 2).map { $0 }
        } else {
            ledgerSteps = []
        }

        return ledgerSteps.map { step in
            let y = GameplayLayout.StaffLinePosition.line1.absoluteY(for: head.row)
                + CGFloat(step) * (style.staffLineSpacing / 2)
            let halfWidth = style.noteHeadWidth / 2 + style.ledgerLineOverhang
            return RenderedLedgerLine(
                id: "ledger_\(head.id)_\(step)",
                row: head.row,
                start: CGPoint(x: head.position.x - halfWidth, y: y),
                end: CGPoint(x: head.position.x + halfWidth, y: y)
            )
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:

```bash
xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' \
  -only-testing:VirgoTests/NotationLayoutEngineTests test
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Virgo/layout/NotationLayoutEngine.swift VirgoTests/NotationLayoutEngineTests.swift
git commit -m "Add notation ledger lines and voices"
```

---

### Task 4: Add Stem Direction and Beam Primitives

**Files:**
- Modify: `Virgo/layout/NotationLayoutEngine.swift`
- Modify: `VirgoTests/NotationLayoutEngineTests.swift`

- [ ] **Step 1: Add failing stem and beam tests**

Append:

```swift
@Test("high crash stem points down")
func highCrashStemPointsDown() {
    let note = Note(interval: .eighth, noteType: .crash, measureNumber: 1, measureOffset: 0)
    let layout = NotationLayoutEngine().layout(
        input: NotationLayoutInput(notes: [note], timeSignature: .fourFour)
    )

    #expect(layout.noteHeads.first?.stemDirection == .down)
    #expect(layout.stems.first?.direction == .down)
}

@Test("consecutive sixteenths create two beam levels")
func consecutiveSixteenthsCreateTwoBeamLevels() {
    let notes = (0..<4).map { index in
        Note(
            interval: .sixteenth,
            noteType: .snare,
            measureNumber: 1,
            measureOffset: Double(index) / 16.0
        )
    }
    let layout = NotationLayoutEngine().layout(
        input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
    )

    #expect(layout.beams.contains { $0.level == 0 })
    #expect(layout.beams.contains { $0.level == 1 })
}

@Test("beams do not cross measure boundaries")
func beamsDoNotCrossMeasureBoundaries() {
    let notes = [
        Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: 0.75),
        Note(interval: .eighth, noteType: .snare, measureNumber: 2, measureOffset: 0)
    ]
    let layout = NotationLayoutEngine().layout(
        input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
    )

    #expect(layout.beams.isEmpty)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' \
  -only-testing:VirgoTests/NotationLayoutEngineTests test
```

Expected: FAIL because stems and beams are not emitted.

- [ ] **Step 3: Implement stem direction, stems, and beams**

In `buildNoteHeads`, compute direction before constructing `RenderedNoteHead`:

```swift
let direction = stemDirection(for: drumType, voice: voice)
```

Use `stemDirection: direction`.

Add helpers:

```swift
private func stemDirection(for drumType: DrumType, voice: NotationVoice) -> StemDirection {
    if voice == .lower {
        return .down
    }

    switch drumType.notePosition {
    case .aboveLine9, .aboveLine8, .aboveLine7, .aboveLine6, .aboveLine5, .line5:
        return .down
    case .spaceBetween4And5, .line4, .spaceBetween3And4, .line3,
         .spaceBetween2And3, .line2, .spaceBetween1And2, .line1,
         .spaceBetweenLine1AndBelow, .belowLine1, .belowLine2, .belowLine3,
         .belowLine4, .belowLine5, .belowLine6:
        return .up
    }
}

private func buildStems(noteHeads: [RenderedNoteHead], style: NotationLayoutStyle) -> [RenderedStem] {
    noteHeads
        .filter { $0.interval.needsStem }
        .map { head in
            let x = head.position.x + (head.stemDirection == .up ? style.stemXInset : -style.stemXInset)
            let endY = head.stemDirection == .up
                ? head.position.y - style.stemLength
                : head.position.y + style.stemLength
            return RenderedStem(
                id: "stem_\(head.id)",
                noteHeadIDs: [head.id],
                direction: head.stemDirection,
                start: CGPoint(x: x, y: head.position.y),
                end: CGPoint(x: x, y: endY)
            )
        }
}

private func buildBeams(noteHeads: [RenderedNoteHead], style: NotationLayoutStyle) -> [RenderedBeam] {
    let beamableHeads = noteHeads
        .filter { $0.interval.needsFlag }
        .sorted { $0.timePosition < $1.timePosition }
    let grouped = Dictionary(grouping: beamableHeads) { head in
        "\(head.measureIndex)_\(head.row)_\(head.voice.rawValue)_\(head.stemDirection.rawValue)"
    }

    return grouped.values.flatMap { heads in
        let sorted = heads.sorted { $0.timePosition < $1.timePosition }
        guard sorted.count >= 2 else { return [RenderedBeam]() }

        var beams: [RenderedBeam] = []
        let maxLevel = sorted.map(\.interval.flagCount).max() ?? 0
        for level in 0..<maxLevel {
            let levelHeads = sorted.filter { $0.interval.flagCount > level }
            guard levelHeads.count >= 2,
                  let first = levelHeads.first,
                  let last = levelHeads.last else { continue }
            let yOffset = first.stemDirection == .up
                ? -style.stemLength - CGFloat(level) * style.beamLevelSpacing
                : style.stemLength + CGFloat(level) * style.beamLevelSpacing
            beams.append(
                RenderedBeam(
                    id: "beam_\(first.id)_\(last.id)_\(level)",
                    noteHeadIDs: levelHeads.map(\.id),
                    direction: first.stemDirection,
                    level: level,
                    start: CGPoint(x: first.position.x, y: first.position.y + yOffset),
                    end: CGPoint(x: last.position.x, y: last.position.y + yOffset),
                    thickness: style.beamThickness
                )
            )
        }
        return beams
    }
}
```

In `layout(input:)`, compute stems and beams after noteheads:

```swift
let stems = buildStems(noteHeads: noteHeads, style: input.style)
let beams = buildBeams(noteHeads: noteHeads, style: input.style)
```

Set `stems: stems` and `beams: beams` in the returned `NotationLayout`.

- [ ] **Step 4: Run tests to verify they pass**

Run:

```bash
xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' \
  -only-testing:VirgoTests/NotationLayoutEngineTests test
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Virgo/layout/NotationLayoutEngine.swift VirgoTests/NotationLayoutEngineTests.swift
git commit -m "Add notation stems and beams"
```

---

### Task 5: Integrate Layout Cache Into GameplayViewModel

**Files:**
- Modify: `Virgo/viewmodels/GameplayViewModel.swift`
- Modify: `VirgoTests/GameplayViewModelTests.swift`

- [ ] **Step 1: Add failing view-model integration test**

Append to `VirgoTests/GameplayViewModelTests.swift`:

```swift
@Test("setupGameplay caches notation layout")
@MainActor
func testSetupGameplayCachesNotationLayout() async throws {
    let container = TestContainer.isolatedContainer(for: "testSetupGameplayCachesNotationLayout")
    let song = Song(title: "Layout Song", artist: "Artist", bpm: 120, duration: "0:04")
    let chart = Chart(difficulty: .medium, level: 20, song: song)
    chart.notes = [
        Note(interval: .sixteenth, noteType: .snare, measureNumber: 1, measureOffset: 0),
        Note(interval: .sixteenth, noteType: .bass, measureNumber: 1, measureOffset: 0)
    ]
    container.context.insert(song)
    container.context.insert(chart)
    try container.context.save()

    let viewModel = GameplayViewModel(chart: chart, metronome: MetronomeEngine())
    await viewModel.loadChartData()
    viewModel.setupGameplay(loadPersistedSpeed: false)

    #expect(viewModel.cachedNotationLayout.noteHeads.count == 2)
    #expect(viewModel.cachedNotationLayout.ledgerLines.count >= 0)
    #expect(!viewModel.cachedNotationBeatPositions.isEmpty)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' \
  -only-testing:VirgoTests/GameplayViewModelTests/testSetupGameplayCachesNotationLayout test
```

Expected: FAIL because `cachedNotationLayout` and `cachedNotationBeatPositions` are undefined.

- [ ] **Step 3: Add layout cache properties and compute them**

In `GameplayViewModel`, add near cached layout data:

```swift
private(set) var cachedNotationLayout = NotationLayout.empty
private(set) var cachedNotationBeatPositions: [UInt64: (x: Double, y: Double)] = [:]
```

Add `empty` to `NotationLayout` in `NotationLayout.swift`:

```swift
extension NotationLayout {
    static let empty = NotationLayout(
        measures: [],
        noteHeads: [],
        stems: [],
        beams: [],
        ledgerLines: [],
        measureBars: [],
        beatLookup: [:],
        totalHeight: 0
    )
}
```

In `GameplayViewModel.computeCachedLayoutData()`, after `measurePositionMap` setup and before `cacheBeatPositions()`, add:

```swift
cacheNotationLayout()
```

Add this method:

```swift
func cacheNotationLayout() {
    guard let track = track else {
        cachedNotationLayout = .empty
        cachedNotationBeatPositions = [:]
        return
    }

    let input = NotationLayoutInput(notes: cachedNotes, timeSignature: track.timeSignature)
    cachedNotationLayout = NotationLayoutEngine().layout(input: input)
    cachedNotationBeatPositions = Dictionary(
        uniqueKeysWithValues: cachedNotationLayout.beatLookup.map {
            ($0.key, (x: Double($0.value.x), y: Double($0.value.y)))
        }
    )
}
```

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' \
  -only-testing:VirgoTests/GameplayViewModelTests/testSetupGameplayCachesNotationLayout test
```

Expected: PASS.

- [ ] **Step 5: Run notation layout tests**

Run:

```bash
xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' \
  -only-testing:VirgoTests/NotationLayoutEngineTests test
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Virgo/layout/NotationLayout.swift Virgo/viewmodels/GameplayViewModel.swift VirgoTests/GameplayViewModelTests.swift
git commit -m "Cache notation layout for gameplay"
```

---

### Task 6: Render Notation Primitives in SwiftUI

**Files:**
- Create: `Virgo/views/NotationPrimitiveViews.swift`
- Modify: `Virgo/views/subviews/GameplaySheetMusicView.swift`
- Modify: `VirgoTests/SwiftUIRenderingCoverageTests.swift`

- [ ] **Step 1: Add primitive view rendering coverage**

Append to `VirgoTests/SwiftUIRenderingCoverageTests.swift`:

```swift
@Test("notation primitive views render expected symbols")
@MainActor
func testNotationPrimitiveViewsRenderExpectedSymbols() throws {
    let head = RenderedNoteHead(
        id: 1,
        sourceNoteID: ObjectIdentifier(Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0)),
        drumType: .snare,
        voice: .upper,
        timePosition: 0,
        measureIndex: 0,
        row: 0,
        position: CGPoint(x: 100, y: 100),
        staffStep: -4,
        stemDirection: .up,
        interval: .quarter
    )

    SwiftUITestUtilities.assertView(
        NotationNoteHeadView(noteHead: head, isActive: false),
        containsStrings: [DrumType.snare.symbol]
    )
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' \
  -only-testing:VirgoTests/SwiftUIRenderingCoverageTests/testNotationPrimitiveViewsRenderExpectedSymbols test
```

Expected: FAIL because `NotationNoteHeadView` is undefined.

- [ ] **Step 3: Add primitive views**

Create `Virgo/views/NotationPrimitiveViews.swift`:

```swift
import SwiftUI

struct NotationNoteHeadView: View {
    let noteHead: RenderedNoteHead
    let isActive: Bool

    var body: some View {
        Text(noteHead.drumType.symbol)
            .font(.system(size: GameplayLayout.drumSymbolFontSize, weight: .bold))
            .foregroundColor(isActive ? .yellow : .white)
            .position(noteHead.position)
    }
}

struct NotationStemView: View {
    let stem: RenderedStem
    let isActive: Bool

    var body: some View {
        Path { path in
            path.move(to: stem.start)
            path.addLine(to: stem.end)
        }
        .stroke(isActive ? Color.yellow : Color.white, lineWidth: GameplayLayout.stemWidth)
    }
}

struct NotationBeamView: View {
    let beam: RenderedBeam
    let isActive: Bool

    var body: some View {
        Path { path in
            path.move(to: beam.start)
            path.addLine(to: beam.end)
        }
        .stroke(isActive ? Color.yellow : Color.white, lineWidth: beam.thickness)
    }
}

struct NotationLedgerLineView: View {
    let ledgerLine: RenderedLedgerLine

    var body: some View {
        Path { path in
            path.move(to: ledgerLine.start)
            path.addLine(to: ledgerLine.end)
        }
        .stroke(Color.white, lineWidth: 2)
    }
}

struct NotationMeasureBarView: View {
    let measureBar: RenderedMeasureBar

    var body: some View {
        let centerY = GameplayLayout.StaffLinePosition.line3.absoluteY(for: measureBar.row)

        if measureBar.isFinal {
            HStack(spacing: GameplayLayout.doubleBarLineSpacing) {
                Rectangle()
                    .frame(width: GameplayLayout.doubleBarLineWidths.thin, height: GameplayLayout.staffHeight)
                Rectangle()
                    .frame(width: GameplayLayout.doubleBarLineWidths.thick, height: GameplayLayout.staffHeight)
            }
            .foregroundColor(.white)
            .position(x: measureBar.x, y: centerY)
        } else {
            Rectangle()
                .frame(width: GameplayLayout.barLineWidth, height: GameplayLayout.staffHeight)
                .foregroundColor(.white.opacity(0.8))
                .position(x: measureBar.x, y: centerY)
        }
    }
}
```

- [ ] **Step 4: Replace note/bar rendering path**

In `GameplaySheetMusicView.barLinesView`, prefer notation bars:

```swift
if !viewModel.cachedNotationLayout.measureBars.isEmpty {
    ForEach(viewModel.cachedNotationLayout.measureBars) { measureBar in
        NotationMeasureBarView(measureBar: measureBar)
    }
} else {
    existingBarLineFallback
}
```

Refactor the existing bar-line body into `existingBarLineFallback` as a local `Group`.

In `drumNotationView`, replace beam and `DrumBeatView` loops with:

```swift
ZStack {
    ForEach(viewModel.cachedNotationLayout.ledgerLines) { ledgerLine in
        NotationLedgerLineView(ledgerLine: ledgerLine)
    }

    ForEach(viewModel.cachedNotationLayout.beams) { beam in
        let isActive = !Set(beam.noteHeadIDs).isDisjoint(with: viewModel.activeNotationNoteHeadIDs)
        NotationBeamView(beam: beam, isActive: isActive)
    }

    ForEach(viewModel.cachedNotationLayout.stems) { stem in
        let isActive = !Set(stem.noteHeadIDs).isDisjoint(with: viewModel.activeNotationNoteHeadIDs)
        NotationStemView(stem: stem, isActive: isActive)
    }

    ForEach(viewModel.cachedNotationLayout.noteHeads) { noteHead in
        NotationNoteHeadView(
            noteHead: noteHead,
            isActive: viewModel.activeNotationNoteHeadIDs.contains(noteHead.id)
        )
    }
}
```

Add to `GameplayViewModel`:

```swift
var activeNotationNoteHeadIDs: Set<UInt64> {
    guard let activeBeatId else { return [] }
    return [activeBeatId]
}
```

This preserves current single-active-column behavior initially. Later tasks can map all noteheads at the active time position.

- [ ] **Step 5: Run rendering and layout tests**

Run:

```bash
xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' \
  -only-testing:VirgoTests/SwiftUIRenderingCoverageTests/testNotationPrimitiveViewsRenderExpectedSymbols \
  -only-testing:VirgoTests/NotationLayoutEngineTests test
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Virgo/views/NotationPrimitiveViews.swift Virgo/views/subviews/GameplaySheetMusicView.swift Virgo/viewmodels/GameplayViewModel.swift VirgoTests/SwiftUIRenderingCoverageTests.swift
git commit -m "Render gameplay notation primitives"
```

---

### Task 7: Align Active Highlight and Purple Progress Bar

**Files:**
- Modify: `Virgo/layout/NotationLayout.swift`
- Modify: `Virgo/viewmodels/GameplayViewModel.swift`
- Modify: `VirgoTests/GameplayViewModelTests.swift`

- [ ] **Step 1: Add failing active-position test**

Append to `VirgoTests/GameplayViewModelTests.swift`:

```swift
@Test("notation active lookup finds all noteheads at current time")
@MainActor
func testNotationActiveLookupFindsAllNoteheadsAtCurrentTime() async throws {
    let container = TestContainer.isolatedContainer(for: "testNotationActiveLookupFindsAllNoteheadsAtCurrentTime")
    let song = Song(title: "Active Layout", artist: "Artist", bpm: 120, duration: "0:04")
    let chart = Chart(difficulty: .medium, level: 20, song: song)
    chart.notes = [
        Note(interval: .sixteenth, noteType: .snare, measureNumber: 1, measureOffset: 0),
        Note(interval: .sixteenth, noteType: .bass, measureNumber: 1, measureOffset: 0)
    ]
    container.context.insert(song)
    container.context.insert(chart)
    try container.context.save()

    let viewModel = GameplayViewModel(chart: chart, metronome: MetronomeEngine())
    await viewModel.loadChartData()
    viewModel.setupGameplay(loadPersistedSpeed: false)
    viewModel.updateActiveNotation(forTimePosition: 0)

    #expect(viewModel.activeNotationNoteHeadIDs.count == 2)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' \
  -only-testing:VirgoTests/GameplayViewModelTests/testNotationActiveLookupFindsAllNoteheadsAtCurrentTime test
```

Expected: FAIL because `updateActiveNotation(forTimePosition:)` is undefined or only one ID is active.

- [ ] **Step 3: Add time-position lookup to `NotationLayout`**

In `NotationLayout`, add:

```swift
var noteHeadIDsByTimePosition: [Int: Set<UInt64>]
```

Update `NotationLayout.empty` with:

```swift
noteHeadIDsByTimePosition: [:]
```

In `NotationLayoutEngine.layout(input:)`, build:

```swift
let noteHeadIDsByTimePosition = Dictionary(grouping: noteHeads) {
    Int(($0.timePosition * 1_000_000).rounded())
}.mapValues { Set($0.map(\.id)) }
```

Pass it into `NotationLayout`.

- [ ] **Step 4: Add active notation state**

In `GameplayViewModel`, replace computed `activeNotationNoteHeadIDs` with stored state:

```swift
private(set) var activeNotationNoteHeadIDs: Set<UInt64> = []

func updateActiveNotation(forTimePosition timePosition: Double) {
    let key = Int((timePosition * 1_000_000).rounded())
    activeNotationNoteHeadIDs = cachedNotationLayout.noteHeadIDsByTimePosition[key] ?? []
}
```

Where `activeBeatId` is updated in `updateVisualElementsFromMetronome()`, also call:

```swift
updateActiveNotation(forTimePosition: currentTimePosition)
```

Where playback is reset, add:

```swift
activeNotationNoteHeadIDs = []
```

- [ ] **Step 5: Run active-position test**

Run:

```bash
xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' \
  -only-testing:VirgoTests/GameplayViewModelTests/testNotationActiveLookupFindsAllNoteheadsAtCurrentTime test
```

Expected: PASS.

- [ ] **Step 6: Run layout and gameplay view-model tests touched by this change**

Run:

```bash
xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' \
  -only-testing:VirgoTests/NotationLayoutEngineTests \
  -only-testing:VirgoTests/GameplayViewModelTests test
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Virgo/layout/NotationLayout.swift Virgo/layout/NotationLayoutEngine.swift Virgo/viewmodels/GameplayViewModel.swift VirgoTests/GameplayViewModelTests.swift
git commit -m "Align notation active highlighting"
```

---

### Task 8: Full Verification and Cleanup

**Files:**
- Modify if needed: `Virgo/views/DrumBeatView.swift`
- Modify if needed: `Virgo/views/BeamView.swift`
- Modify if needed: `Virgo/utilities/BeamGroupingLogic.swift`
- Modify if needed: `Virgo/viewmodels/GameplayViewModel.swift`

- [ ] **Step 1: Search for old rendering dependencies**

Run:

```bash
rg -n "cachedDrumBeats|cachedBeamGroups|beatToBeamGroupMap|DrumBeatView|BeamGroupView|BeamView" Virgo VirgoTests
```

Expected: Remaining references are either test-only, compatibility-only, or unrelated to the active gameplay rendering path.

- [ ] **Step 2: Remove dead active rendering code if references are gone**

If `DrumBeatView`, `BeamView`, or `BeamGroupingLogic` are unused by production code after the primitive rendering path, delete only the unused files and update tests that reference them. If tests still cover those types for compatibility, keep the files and add comments stating they are legacy fallback components.

Use this comment if files are kept:

```swift
// Legacy notation renderer retained for compatibility tests while gameplay uses NotationLayoutEngine.
```

- [ ] **Step 3: Run unit tests in CI format**

Run:

```bash
xcodebuild test \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'platform=macOS' \
  -configuration Debug \
  -only-testing:VirgoTests \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  -enableCodeCoverage YES \
  -destination-timeout 300 \
  -derivedDataPath ./DerivedData
```

Expected: PASS.

- [ ] **Step 4: Run macOS build**

Run:

```bash
xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' build
```

Expected: PASS.

- [ ] **Step 5: Commit cleanup**

If cleanup changed files:

```bash
git add Virgo VirgoTests
git commit -m "Clean up legacy notation rendering path"
```

If cleanup changed nothing, do not create an empty commit.

---

## Self-Review

- Spec coverage: adaptive spacing is covered by Task 2; ledger lines and voices by Task 3; stem direction and beams by Task 4; view-model caching by Task 5; SwiftUI rendering by Task 6; active highlighting/progress alignment by Task 7; verification/cleanup by Task 8.
- Placeholder scan: the plan intentionally avoids deferred implementation placeholders. Follow-up decisions from the spec remain out of scope.
- Type consistency: `NotationLayoutInput`, `NotationLayoutStyle`, `NotationVoice`, `StemDirection`, `NotationLayout`, and render primitive names are introduced in Task 1 and reused consistently in later tasks.
