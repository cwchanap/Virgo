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
}
