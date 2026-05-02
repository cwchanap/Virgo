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

    @Test("sparse quarter notes preserve legacy measure width and first column")
    func sparseQuarterNotesPreserveLegacyMeasureWidthAndFirstColumn() {
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
        let measure = layout.measures.first
        let firstX = layout.noteHeads.map(\.position.x).min() ?? 0
        let expectedFirstX = (measure?.xOffset ?? 0)
            + GameplayLayout.barLineWidth
            + GameplayLayout.uniformSpacing

        #expect(measure?.width == GameplayLayout.measureWidth(for: .fourFour))
        #expect(abs(firstX - expectedFirstX) < 0.001)
    }

    @Test("near identical simultaneous offsets do not expand simple measure")
    func nearIdenticalSimultaneousOffsetsDoNotExpandSimpleMeasure() {
        let notes = [
            Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0.0),
            Note(interval: .quarter, noteType: .bass, measureNumber: 1, measureOffset: 0.0004)
        ]
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
        )
        let uniqueX = Array(Set(layout.noteHeads.map(\.position.x))).sorted()

        #expect(layout.measures.first?.width == GameplayLayout.measureWidth(for: .fourFour))
        #expect(uniqueX.count == 1)
    }

    @Test("simultaneous quarter notes share columns without expanding measure")
    func simultaneousQuarterNotesShareColumnsWithoutExpandingMeasure() {
        let notes = (0..<4).flatMap { index in
            [
                Note(
                    interval: .quarter,
                    noteType: .snare,
                    measureNumber: 1,
                    measureOffset: Double(index) / 4.0
                ),
                Note(
                    interval: .quarter,
                    noteType: .bass,
                    measureNumber: 1,
                    measureOffset: Double(index) / 4.0
                )
            ]
        }
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
        )
        let uniqueX = Array(Set(layout.noteHeads.map(\.position.x))).sorted()

        #expect(layout.noteHeads.count == 8)
        #expect(uniqueX.count == 4)
        #expect((layout.measures.first?.width ?? 0) <= GameplayLayout.measureWidth(for: .fourFour))
        #expect(abs((uniqueX[1] - uniqueX[0]) - GameplayLayout.uniformSpacing) < 0.001)
    }
}
