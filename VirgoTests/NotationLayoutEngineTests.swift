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
        #expect(uniqueX.count == 2)
        #expect((uniqueX.last ?? 0) - (uniqueX.first ?? 0) >= 16)
    }

    @Test("near identical cross voice offsets split heads without expanding measure")
    func nearIdenticalCrossVoiceOffsetsSplitHeadsWithoutExpandingMeasure() {
        let notes = [
            Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0.25),
            Note(interval: .quarter, noteType: .bass, measureNumber: 1, measureOffset: 0.24999999999999997)
        ]
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
        )
        let uniqueX = Array(Set(layout.noteHeads.map(\.position.x))).sorted()

        #expect(layout.measures.first?.width == GameplayLayout.measureWidth(for: .fourFour))
        #expect(uniqueX.count == 2)
        #expect((uniqueX.last ?? 0) - (uniqueX.first ?? 0) >= 16)
    }

    @Test("dense adjacent cross voice columns preserve readable final gap")
    func denseAdjacentCrossVoiceColumnsPreserveReadableFinalGap() throws {
        let style = NotationLayoutStyle.gameplayDefault
        let notes = [
            Note(interval: .sixteenth, noteType: .bass, measureNumber: 1, measureOffset: 0.0),
            Note(interval: .sixteenth, noteType: .snare, measureNumber: 1, measureOffset: 0.0),
            Note(interval: .sixteenth, noteType: .bass, measureNumber: 1, measureOffset: 1.0 / 16.0),
            Note(interval: .sixteenth, noteType: .snare, measureNumber: 1, measureOffset: 1.0 / 16.0)
        ]
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour, style: style)
        )
        let firstColumnRightmostX = try #require(
            layout.noteHeads
                .filter { $0.timePosition == 0.0 }
                .map(\.position.x)
                .max()
        )
        let secondColumnLeftmostX = try #require(
            layout.noteHeads
                .filter { $0.timePosition == 0.0625 }
                .map(\.position.x)
                .min()
        )

        #expect(secondColumnLeftmostX - firstColumnRightmostX >= style.minimumNoteColumnGap)
    }

    @Test("simultaneous quarter notes split voices without expanding measure")
    func simultaneousQuarterNotesSplitVoicesWithoutExpandingMeasure() {
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
        #expect(uniqueX.count == 8)
        #expect((layout.measures.first?.width ?? 0) <= GameplayLayout.measureWidth(for: .fourFour))
        #expect(abs((uniqueX[2] - uniqueX[0]) - GameplayLayout.uniformSpacing) < 0.001)
    }

    @Test("above staff crash emits ledger line")
    func aboveStaffCrashEmitsLedgerLine() {
        let note = Note(interval: .quarter, noteType: .crash, measureNumber: 1, measureOffset: 0)
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: [note], timeSignature: .fourFour)
        )

        #expect(layout.ledgerLines.count >= 1)
        #expect(layout.ledgerLines.allSatisfy { $0.end.x > $0.start.x })
    }

    @Test("below staff kick emits ledger lines")
    func belowStaffKickEmitsLedgerLines() {
        let note = Note(interval: .quarter, noteType: .bass, measureNumber: 1, measureOffset: 0)
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: [note], timeSignature: .fourFour)
        )

        #expect(layout.ledgerLines.count >= 1)
        #expect(layout.ledgerLines.allSatisfy { $0.end.x > $0.start.x })
    }

    @Test("kick and snare at same time get separate voices")
    func kickAndSnareAtSameTimeGetSeparateVoices() throws {
        let notes = [
            Note(interval: .quarter, noteType: .bass, measureNumber: 1, measureOffset: 0.25),
            Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0.25)
        ]
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
        )
        let kick = try #require(layout.noteHeads.first { $0.drumType == .kick })
        let snare = try #require(layout.noteHeads.first { $0.drumType == .snare })

        #expect(kick.voice == .lower)
        #expect(snare.voice == .upper)
        #expect(abs(snare.position.x - kick.position.x) >= 16)
        #expect(kick.position.x < snare.position.x)
    }

    @Test("same voice simultaneous notes do not split")
    func sameVoiceSimultaneousNotesDoNotSplit() throws {
        let notes = [
            Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0.5),
            Note(interval: .quarter, noteType: .crash, measureNumber: 1, measureOffset: 0.5)
        ]
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
        )
        let snare = try #require(layout.noteHeads.first { $0.drumType == .snare })
        let crash = try #require(layout.noteHeads.first { $0.drumType == .crash })

        #expect(snare.voice == .upper)
        #expect(crash.voice == .upper)
        #expect(abs(snare.position.x - crash.position.x) < 0.001)
    }

    @Test("near identical cross voice offsets split by quantized column")
    func nearIdenticalCrossVoiceOffsetsSplitByQuantizedColumn() throws {
        let notes = [
            Note(interval: .quarter, noteType: .bass, measureNumber: 1, measureOffset: 0.25),
            Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0.24999999999999997)
        ]
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
        )
        let kick = try #require(layout.noteHeads.first { $0.drumType == .kick })
        let snare = try #require(layout.noteHeads.first { $0.drumType == .snare })

        #expect(kick.position.x < snare.position.x)
        #expect(abs(snare.position.x - kick.position.x) >= 16)
    }
}
