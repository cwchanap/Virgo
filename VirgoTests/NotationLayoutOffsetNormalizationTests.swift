import Testing
import SwiftUI
@testable import Virgo

@Suite("Offset-1 Normalization Tests")
struct NotationLayoutOffsetNormalizationTests {
    @Test("note with measureOffset 1.0 renders in next measure")
    func noteWithOffsetOneRendersInNextMeasure() throws {
        let note = Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 1.0)
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: [note], timeSignature: .fourFour, minimumMeasureCount: 3)
        )
        let head = try #require(layout.noteHeads.first)

        #expect(head.measureIndex == 1)
        #expect(head.timePosition == 1.0)
        let measure1 = try #require(layout.measures.first { $0.measureIndex == 1 })
        let expectedX = measure1.xOffset + GameplayLayout.barLineWidth + GameplayLayout.uniformSpacing
        #expect(abs(head.position.x - expectedX) < 0.001)
    }

    @Test("offset-1 note collision column uses normalized measure")
    func offsetOneNoteCollisionColumnUsesNormalizedMeasure() throws {
        let notes = [
            Note(interval: .quarter, noteType: .snare, measureNumber: 2, measureOffset: 0.0),
            Note(interval: .quarter, noteType: .bass, measureNumber: 1, measureOffset: 1.0)
        ]
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour, minimumMeasureCount: 3)
        )
        let snare = try #require(layout.noteHeads.first { $0.drumType == .snare })
        let kick = try #require(layout.noteHeads.first { $0.drumType == .kick })

        #expect(snare.measureIndex == 1)
        #expect(kick.measureIndex == 1)
        #expect(abs(snare.timePosition - kick.timePosition) < 0.001)
    }

    @Test("offset-1 note in last measure is not dropped when minimumMeasureCount is tight")
    func offsetOneNoteInLastMeasureNotDroppedWithTightMeasureCount() throws {
        let note = Note(interval: .quarter, noteType: .snare, measureNumber: 2, measureOffset: 1.0)
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: [note], timeSignature: .fourFour, minimumMeasureCount: 1)
        )
        let msg = "Note must not be dropped — measure count must account for normalized position"
        let head = try #require(layout.noteHeads.first, "Note must not be dropped — measure count must account for normalized position")

        #expect(head.measureIndex == 2)
        #expect(head.timePosition == 2.0)
        #expect(layout.measures.count >= 3, "At least 3 measures needed for the normalized position")
    }

    @Test("column offsets for measure use normalized positions not raw measureNumber")
    func columnOffsetsUseNormalizedPositions() throws {
        let notes = [
            Note(interval: .sixteenth, noteType: .snare, measureNumber: 1, measureOffset: 1.0),
            Note(interval: .sixteenth, noteType: .snare, measureNumber: 2, measureOffset: 0.0625)
        ]
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour, minimumMeasureCount: 3)
        )

        let measure1Heads = layout.noteHeads.filter { $0.measureIndex == 1 }
        #expect(measure1Heads.count == 2, "Both notes should render in normalized measure index 1")
        let uniqueX = Set(measure1Heads.map { $0.position.x })
        #expect(uniqueX.count == 2, "Two different offsets should produce two distinct x positions")
    }
}
