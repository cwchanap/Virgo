import Testing
import SwiftUI
@testable import Virgo

@Suite("GameplayLayout Tests")
struct GameplayLayoutTests {
    @Test("totalHeight uses the highest occupied row")
    func testTotalHeightUsesMaxRow() {
        let positions = [
            GameplayLayout.MeasurePosition(row: 0, xOffset: 100, measureIndex: 0),
            GameplayLayout.MeasurePosition(row: 2, xOffset: 140, measureIndex: 5)
        ]

        let totalHeight = GameplayLayout.totalHeight(for: positions)
        let expectedHeight = GameplayLayout.baseStaffY +
            CGFloat(3) * (GameplayLayout.rowHeight + GameplayLayout.rowVerticalSpacing) +
            100

        #expect(totalHeight == expectedHeight)
    }

    @Test("totalHeight for empty positions uses row 0")
    func testTotalHeightForEmptyPositions() {
        let totalHeight = GameplayLayout.totalHeight(for: [])
        let expectedHeight = GameplayLayout.baseStaffY +
            CGFloat(1) * (GameplayLayout.rowHeight + GameplayLayout.rowVerticalSpacing) +
            100
        #expect(totalHeight == expectedHeight)
    }

    @Test("totalHeight for single row uses row 0")
    func testTotalHeightForSingleRow() {
        let positions = [GameplayLayout.MeasurePosition(row: 0, xOffset: 100, measureIndex: 0)]
        let totalHeight = GameplayLayout.totalHeight(for: positions)
        let expectedHeight = GameplayLayout.baseStaffY +
            CGFloat(1) * (GameplayLayout.rowHeight + GameplayLayout.rowVerticalSpacing) +
            100
        #expect(totalHeight == expectedHeight)
    }

    @Test("noteXPosition uses measure offset and beat spacing")
    func testNoteXPositionForMeasurePosition() {
        let measurePosition = GameplayLayout.MeasurePosition(row: 1, xOffset: 220, measureIndex: 3)

        let xPosition = GameplayLayout.noteXPosition(
            measurePosition: measurePosition,
            beatIndex: 2,
            timeSignature: .fourFour
        )

        let expected = measurePosition.xOffset +
            GameplayLayout.barLineWidth +
            GameplayLayout.uniformSpacing +
            CGFloat(2) * GameplayLayout.uniformSpacing

        #expect(xPosition == expected)
    }

    @Test("noteXPosition beat index 0 is at leftmost beat position")
    func testNoteXPositionBeatIndexZero() {
        let measurePosition = GameplayLayout.MeasurePosition(row: 0, xOffset: 100, measureIndex: 0)
        let xPosition = GameplayLayout.noteXPosition(
            measurePosition: measurePosition,
            beatIndex: 0,
            timeSignature: .fourFour
        )
        let expected = measurePosition.xOffset + GameplayLayout.barLineWidth + GameplayLayout.uniformSpacing
        #expect(xPosition == expected)
    }

    @Test("noteXPosition lookup by measure index returns fallback for missing measures")
    func testNoteXPositionLookupAndFallback() {
        let positions = [
            GameplayLayout.MeasurePosition(row: 0, xOffset: 100, measureIndex: 0),
            GameplayLayout.MeasurePosition(row: 1, xOffset: 180, measureIndex: 2)
        ]

        let matchedXPosition = GameplayLayout.noteXPosition(
            measureIndex: 2,
            beatIndex: 1,
            timeSignature: .fourFour,
            positions: positions
        )
        let expectedMatchedX = positions[1].xOffset +
            GameplayLayout.barLineWidth +
            GameplayLayout.uniformSpacing +
            GameplayLayout.uniformSpacing

        let fallbackXPosition = GameplayLayout.noteXPosition(
            measureIndex: 99,
            beatIndex: 0,
            timeSignature: .fourFour,
            positions: positions
        )

        #expect(matchedXPosition == expectedMatchedX)
        #expect(fallbackXPosition == GameplayLayout.leftMargin)
    }

    @Test("rowWidth and noteYPosition reuse layout constants")
    func testRowWidthAndNoteYPosition() {
        let rowWidth = GameplayLayout.rowWidth(for: .threeFour)
        let noteYPosition = GameplayLayout.noteYPosition(row: 2, notePosition: .line3)
        let expectedNoteY = GameplayLayout.NotePosition.line3.absoluteY(for: 2)

        #expect(rowWidth == GameplayLayout.maxRowWidth)
        #expect(noteYPosition == expectedNoteY)
    }

    // MARK: - measureWidth

    @Test("measureWidth for 4/4 uses 5 uniformSpacing intervals plus barLineWidth")
    func testMeasureWidthFourFour() {
        let width = GameplayLayout.measureWidth(for: .fourFour)
        let expected = GameplayLayout.barLineWidth + CGFloat(5) * GameplayLayout.uniformSpacing
        #expect(width == expected)
    }

    @Test("measureWidth for 3/4 uses 4 uniformSpacing intervals plus barLineWidth")
    func testMeasureWidthThreeFour() {
        let width = GameplayLayout.measureWidth(for: .threeFour)
        let expected = GameplayLayout.barLineWidth + CGFloat(4) * GameplayLayout.uniformSpacing
        #expect(width == expected)
    }

    @Test("measureWidth for 3/4 is less than for 4/4")
    func testMeasureWidthThreeFourLessThanFourFour() {
        let threeFourWidth = GameplayLayout.measureWidth(for: .threeFour)
        let fourFourWidth = GameplayLayout.measureWidth(for: .fourFour)
        #expect(threeFourWidth < fourFourWidth)
    }

    // MARK: - preciseNoteXPosition

    @Test("preciseNoteXPosition at beat 0.0 matches noteXPosition at beatIndex 0")
    func testPreciseNoteXPositionAtBeatZero() {
        let measurePosition = GameplayLayout.MeasurePosition(row: 0, xOffset: 100, measureIndex: 0)
        let precise = GameplayLayout.preciseNoteXPosition(
            measurePosition: measurePosition,
            beatPosition: 0.0,
            timeSignature: .fourFour
        )
        let discrete = GameplayLayout.noteXPosition(
            measurePosition: measurePosition,
            beatIndex: 0,
            timeSignature: .fourFour
        )
        #expect(precise == discrete)
    }

    @Test("preciseNoteXPosition at beat 1.0 matches noteXPosition at beatIndex 1")
    func testPreciseNoteXPositionAtBeatOne() {
        let measurePosition = GameplayLayout.MeasurePosition(row: 0, xOffset: 100, measureIndex: 0)
        let precise = GameplayLayout.preciseNoteXPosition(
            measurePosition: measurePosition,
            beatPosition: 1.0,
            timeSignature: .fourFour
        )
        let discrete = GameplayLayout.noteXPosition(
            measurePosition: measurePosition,
            beatIndex: 1,
            timeSignature: .fourFour
        )
        #expect(precise == discrete)
    }

    @Test("preciseNoteXPosition interpolates fractional beat positions")
    func testPreciseNoteXPositionFractional() {
        let measurePosition = GameplayLayout.MeasurePosition(row: 0, xOffset: 100, measureIndex: 0)
        let preciseHalf = GameplayLayout.preciseNoteXPosition(
            measurePosition: measurePosition,
            beatPosition: 0.5,
            timeSignature: .fourFour
        )
        let atZero = GameplayLayout.preciseNoteXPosition(
            measurePosition: measurePosition,
            beatPosition: 0.0,
            timeSignature: .fourFour
        )
        let atOne = GameplayLayout.preciseNoteXPosition(
            measurePosition: measurePosition,
            beatPosition: 1.0,
            timeSignature: .fourFour
        )
        // Half-beat position should be exactly between beat 0 and beat 1
        let expectedHalf = (atZero + atOne) / 2
        #expect(abs(preciseHalf - expectedHalf) < 0.001)
    }

    // MARK: - StaffLinePosition.absoluteY

    @Test("StaffLinePosition.absoluteY for row 0 reflects baseStaffY offset")
    func testStaffLinePositionAbsoluteYRow0() {
        let row = 0
        let line1Y = GameplayLayout.StaffLinePosition.line1.absoluteY(for: row)
        let expectedLine1Y = GameplayLayout.baseStaffY + GameplayLayout.StaffLinePosition.line1.yOffset
        #expect(line1Y == expectedLine1Y)
    }

    @Test("StaffLinePosition.absoluteY increases by rowHeight + rowVerticalSpacing per row")
    func testStaffLinePositionAbsoluteYRowIncrement() {
        let line3Row0 = GameplayLayout.StaffLinePosition.line3.absoluteY(for: 0)
        let line3Row1 = GameplayLayout.StaffLinePosition.line3.absoluteY(for: 1)
        let rowIncrement = GameplayLayout.rowHeight + GameplayLayout.rowVerticalSpacing
        #expect(abs((line3Row1 - line3Row0) - rowIncrement) < 0.001)
    }

    @Test("StaffLinePosition.line5 is above line1 (smaller Y because of top-down coordinates)")
    func testStaffLinePositionVerticalOrdering() {
        let line1Y = GameplayLayout.StaffLinePosition.line1.absoluteY(for: 0)
        let line5Y = GameplayLayout.StaffLinePosition.line5.absoluteY(for: 0)
        // Higher staff lines have smaller Y values (positioned higher on screen)
        #expect(line5Y < line1Y)
    }

    // MARK: - NotePosition.absoluteY

    @Test("NotePosition.absoluteY for row 0 uses baseStaffY")
    func testNotePositionAbsoluteYRow0() {
        let line3Y = GameplayLayout.NotePosition.line3.absoluteY(for: 0)
        let expected = GameplayLayout.baseStaffY + GameplayLayout.NotePosition.line3.yOffset
        #expect(line3Y == expected)
    }

    @Test("NotePosition above-staff positions have smaller Y than line5")
    func testNotePositionAboveStaffIsHigher() {
        let aboveLine5Y = GameplayLayout.NotePosition.aboveLine5.absoluteY(for: 0)
        let line5Y = GameplayLayout.NotePosition.line5.absoluteY(for: 0)
        #expect(aboveLine5Y < line5Y)
    }

    @Test("NotePosition below-staff positions have larger Y than line1")
    func testNotePositionBelowStaffIsLower() {
        let belowLine1Y = GameplayLayout.NotePosition.belowLine1.absoluteY(for: 0)
        let line1Y = GameplayLayout.NotePosition.line1.absoluteY(for: 0)
        #expect(belowLine1Y > line1Y)
    }

    // MARK: - calculateMeasurePositions

    @Test("calculateMeasurePositions returns correct count")
    func testCalculateMeasurePositionsCount() {
        let positions = GameplayLayout.calculateMeasurePositions(totalMeasures: 4, timeSignature: .fourFour)
        #expect(positions.count == 4)
    }

    @Test("calculateMeasurePositions first measure starts at leftMargin")
    func testCalculateMeasurePositionsFirstMeasureOffset() {
        let positions = GameplayLayout.calculateMeasurePositions(totalMeasures: 4, timeSignature: .fourFour)
        #expect(positions.first?.xOffset == GameplayLayout.leftMargin)
        #expect(positions.first?.row == 0)
        #expect(positions.first?.measureIndex == 0)
    }

    @Test("calculateMeasurePositions for 0 measures returns empty array")
    func testCalculateMeasurePositionsEmpty() {
        let positions = GameplayLayout.calculateMeasurePositions(totalMeasures: 0, timeSignature: .fourFour)
        #expect(positions.isEmpty)
    }

    @Test("calculateMeasurePositions assigns correct sequential measure indices")
    func testCalculateMeasurePositionsMeasureIndices() {
        let positions = GameplayLayout.calculateMeasurePositions(totalMeasures: 3, timeSignature: .fourFour)
        for (i, position) in positions.enumerated() {
            #expect(position.measureIndex == i)
        }
    }

    @Test("calculateMeasurePositions wraps to next row when width exceeded")
    func testCalculateMeasurePositionsRowWrapping() {
        // Derive how many measures fit in a single row from the layout constants,
        // then request one more to guarantee wrapping regardless of future constant changes.
        let measureWidth = GameplayLayout.measureWidth(for: .fourFour)
        let availableWidth = GameplayLayout.maxRowWidth - GameplayLayout.leftMargin
        let measuresPerRow = Int(availableWidth / (measureWidth + GameplayLayout.measureSpacing))
        // Guard against measuresPerRow == 0 (single measure wider than available width):
        // in that case 2 measures still forces wrapping because the second always exceeds the row.
        let totalMeasures = measuresPerRow == 0 ? 2 : measuresPerRow + 1
        let positions = GameplayLayout.calculateMeasurePositions(totalMeasures: totalMeasures, timeSignature: .fourFour)
        let maxRow = positions.map { $0.row }.max() ?? 0
        // With more measures than fit in one row, wrapping must have occurred
        #expect(maxRow > 0)
        // All measures in row > 0 should restart at leftMargin
        let secondRowPositions = positions.filter { $0.row > 0 }
        if let firstInRow1 = secondRowPositions.first {
            #expect(firstInRow1.xOffset == GameplayLayout.leftMargin)
        }
    }

    // MARK: - DrumType notePosition and yPosition

    @Test("DrumType.snare maps to NotePosition.line3")
    func testSnareNotePosition() {
        #expect(DrumType.snare.notePosition == .line3)
    }

    @Test("DrumType.kick maps to NotePosition.belowLine2")
    func testKickNotePosition() {
        #expect(DrumType.kick.notePosition == .belowLine2)
    }

    @Test("DrumType.hiHat maps to NotePosition.line5")
    func testHiHatNotePosition() {
        #expect(DrumType.hiHat.notePosition == .line5)
    }

    @Test("DrumType.yPosition delegates to notePosition.absoluteY")
    func testDrumTypeYPositionDelegatesToNotePosition() {
        let row = 1
        let snareY = DrumType.snare.yPosition(for: row)
        let expectedY = DrumType.snare.notePosition.absoluteY(for: row)
        #expect(snareY == expectedY)
    }

    @Test("All DrumType note positions map to distinct NotePosition values")
    func testAllDrumTypeNotePositions() {
        let expected: [(DrumType, GameplayLayout.NotePosition)] = [
            (.crash, .aboveLine5),
            (.hiHat, .line5),
            (.ride, .spaceBetween4And5),
            (.cowbell, .line4),
            (.tom1, .spaceBetween3And4),
            (.snare, .line3),
            (.tom2, .spaceBetween2And3),
            (.tom3, .line2),
            (.hiHatPedal, .belowLine1),
            (.kick, .belowLine2)
        ]
        #expect(expected.count == DrumType.allCases.count)
        for (drumType, expectedPosition) in expected {
            #expect(drumType.notePosition == expectedPosition)
        }
    }

    @Test("DrumType note positions form a top-down ordering")
    func testDrumTypeNotePositionVerticalOrdering() {
        // From top to bottom: crash > hiHat > ride > cowbell > tom1 > snare > tom2 > tom3 > hiHatPedal > kick
        let orderedFromTop: [DrumType] = [.crash, .hiHat, .ride, .cowbell, .tom1, .snare, .tom2, .tom3, .hiHatPedal, .kick]
        let row = 0
        var previousY = CGFloat.leastNormalMagnitude
        for drumType in orderedFromTop {
            let currentY = drumType.yPosition(for: row)
            #expect(currentY > previousY, "Expected \(drumType) to be below previous drum type (larger Y)")
            previousY = currentY
        }
    }

    @Test("DrumType.yPosition differs by row for the same drum type")
    func testDrumTypeYPositionChangesAcrossRows() {
        for drumType in DrumType.allCases {
            let row0Y = drumType.yPosition(for: 0)
            let row1Y = drumType.yPosition(for: 1)
            let rowIncrement = GameplayLayout.rowHeight + GameplayLayout.rowVerticalSpacing
            #expect(abs((row1Y - row0Y) - rowIncrement) < 0.001)
        }
    }

    @Test("NotePosition yOffset ordering: above positions < staff positions < below positions")
    func testNotePositionYOffsetOrdering() {
        let abovePositions: [GameplayLayout.NotePosition] = [.aboveLine9, .aboveLine8, .aboveLine7, .aboveLine6, .aboveLine5]
        let staffPositions: [GameplayLayout.NotePosition] = [.line5, .line4, .line3, .line2, .line1]
        let belowPositions: [GameplayLayout.NotePosition] = [.belowLine1, .belowLine2, .belowLine3, .belowLine4, .belowLine5, .belowLine6]

        // All above-staff positions should have smaller yOffset than line5
        let line5Offset = GameplayLayout.NotePosition.line5.yOffset
        for pos in abovePositions {
            #expect(pos.yOffset < line5Offset)
        }

        // All below-staff positions should have larger yOffset than line1
        let line1Offset = GameplayLayout.NotePosition.line1.yOffset
        for pos in belowPositions {
            #expect(pos.yOffset > line1Offset)
        }

        // Within above-staff positions, higher numbers should be farther above (smaller yOffset)
        for i in 0..<(abovePositions.count - 1) {
            #expect(abovePositions[i].yOffset < abovePositions[i + 1].yOffset)
        }

        // Within below-staff positions, higher numbers should be farther below (larger yOffset)
        for i in 0..<(belowPositions.count - 1) {
            #expect(belowPositions[i].yOffset < belowPositions[i + 1].yOffset)
        }
    }

    @Test("StaffLinePosition yOffset values match expected multiples of staffLineSpacing")
    func testStaffLinePositionYOffsets() {
        let spacing = GameplayLayout.staffLineSpacing
        #expect(GameplayLayout.StaffLinePosition.line1.yOffset == 0)
        #expect(GameplayLayout.StaffLinePosition.line2.yOffset == -spacing)
        #expect(GameplayLayout.StaffLinePosition.line3.yOffset == -2 * spacing)
        #expect(GameplayLayout.StaffLinePosition.line4.yOffset == -3 * spacing)
        #expect(GameplayLayout.StaffLinePosition.line5.yOffset == -4 * spacing)
    }

    @Test("StaffLinePosition rawValues are sequential 0 through 4")
    func testStaffLinePositionRawValues() {
        #expect(GameplayLayout.StaffLinePosition.line1.rawValue == 0)
        #expect(GameplayLayout.StaffLinePosition.line2.rawValue == 1)
        #expect(GameplayLayout.StaffLinePosition.line3.rawValue == 2)
        #expect(GameplayLayout.StaffLinePosition.line4.rawValue == 3)
        #expect(GameplayLayout.StaffLinePosition.line5.rawValue == 4)
    }

    @Test("GameplayLayout derived constants have expected values")
    func testGameplayLayoutDerivedConstants() {
        // staffHeight = (staffLineCount - 1) * staffLineSpacing
        let expectedStaffHeight = CGFloat(GameplayLayout.staffLineCount - 1) * GameplayLayout.staffLineSpacing
        #expect(GameplayLayout.staffHeight == expectedStaffHeight)

        // baseStaffY = 150 + staffHeight / 2
        let expectedBaseStaffY = CGFloat(150) + GameplayLayout.staffHeight / 2
        #expect(GameplayLayout.baseStaffY == expectedBaseStaffY)
    }

    @Test("calculateMeasurePositions with 1 measure stays on row 0")
    func testCalculateMeasurePositionsOneMeasure() {
        let positions = GameplayLayout.calculateMeasurePositions(totalMeasures: 1, timeSignature: .fourFour)
        #expect(positions.count == 1)
        #expect(positions[0].row == 0)
        #expect(positions[0].measureIndex == 0)
        #expect(positions[0].xOffset == GameplayLayout.leftMargin)
    }

    @Test("calculateMeasurePositions xOffset increases monotonically within each row")
    func testCalculateMeasurePositionsXOffsetMonotonic() {
        let positions = GameplayLayout.calculateMeasurePositions(totalMeasures: 3, timeSignature: .fourFour)
        let row0Positions = positions.filter { $0.row == 0 }.sorted { $0.measureIndex < $1.measureIndex }
        for i in 0..<(row0Positions.count - 1) {
            #expect(row0Positions[i].xOffset < row0Positions[i + 1].xOffset)
        }
    }

    @Test("measureWidth scales proportionally with beatsPerMeasure")
    func testMeasureWidthScalesWithBeatsPerMeasure() {
        // 12/8 has 12 beats per measure, 2/4 has 2 beats - 12/8 should be wider
        let wideWidth = GameplayLayout.measureWidth(for: .twelveEight)
        let narrowWidth = GameplayLayout.measureWidth(for: .twoFour)
        #expect(wideWidth > narrowWidth)
    }
}
