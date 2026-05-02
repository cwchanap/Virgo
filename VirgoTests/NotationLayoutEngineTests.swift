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
        let input = NotationLayoutInput(notes: [note], timeSignature: .fourFour, minimumMeasureCount: 3)

        #expect(input.notes.count == 1)
        #expect(input.timeSignature.beatsPerMeasure == 4)
        #expect(input.minimumMeasureCount == 3)
        #expect(input.style.minimumNoteColumnGap == 28)
    }

    @Test("minimum measure count preserves trailing empty measures")
    func minimumMeasureCountPreservesTrailingEmptyMeasures() {
        let note = Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0)
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: [note], timeSignature: .fourFour, minimumMeasureCount: 4)
        )

        #expect(layout.measures.map(\.measureIndex) == [0, 1, 2, 3])
        #expect(layout.measureBars.contains { $0.id == "bar_3_end" && $0.isFinal })
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

extension NotationLayoutEngineTests {
    @Test("high crash stem points down")
    func highCrashStemPointsDown() throws {
        let style = NotationLayoutStyle.gameplayDefault
        let note = Note(interval: .quarter, noteType: .crash, measureNumber: 1, measureOffset: 0)
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: [note], timeSignature: .fourFour, style: style)
        )
        let crash = try #require(layout.noteHeads.first { $0.drumType == .crash })
        let stem = try #require(layout.stems.first)

        #expect(crash.stemDirection == .down)
        #expect(stem.direction == .down)
        #expect(abs(stem.start.x - (crash.position.x - style.stemXInset)) < 0.001)
        #expect(stem.end.y > stem.start.y)
    }

    @Test("snare stem points up")
    func snareStemPointsUp() throws {
        let style = NotationLayoutStyle.gameplayDefault
        let note = Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0)
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: [note], timeSignature: .fourFour, style: style)
        )
        let snare = try #require(layout.noteHeads.first { $0.drumType == .snare })
        let stem = try #require(layout.stems.first)

        #expect(snare.stemDirection == .up)
        #expect(stem.direction == .up)
        #expect(abs(stem.start.x - (snare.position.x + style.stemXInset)) < 0.001)
        #expect(stem.end.y < stem.start.y)
    }

    @Test("quarter notes create stems but no beams")
    func quarterNotesCreateStemsButNoBeams() {
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

        #expect(layout.stems.count == 4)
        #expect(layout.beams.isEmpty)
    }

    @Test("full and half notes do not create stems")
    func fullAndHalfNotesDoNotCreateStems() {
        let notes = [
            Note(interval: .full, noteType: .snare, measureNumber: 1, measureOffset: 0),
            Note(interval: .half, noteType: .snare, measureNumber: 1, measureOffset: 0.5)
        ]
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
        )

        #expect(layout.stems.isEmpty)
        #expect(layout.beams.isEmpty)
    }

    @Test("consecutive sixteenths create two beam levels")
    func consecutiveSixteenthsCreateTwoBeamLevels() throws {
        let style = NotationLayoutStyle.gameplayDefault
        let notes = (0..<4).map { index in
            Note(
                interval: .sixteenth,
                noteType: .snare,
                measureNumber: 1,
                measureOffset: Double(index) / 16.0
            )
        }
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour, style: style)
        )
        let sortedHeads = layout.noteHeads.sorted { $0.timePosition < $1.timePosition }
        let firstHead = try #require(sortedHeads.first)
        let lastHead = try #require(sortedHeads.last)

        #expect(layout.beams.count == 2)
        #expect(Set(layout.beams.map(\.level)) == [0, 1])
        #expect(layout.beams.allSatisfy { $0.noteHeadIDs.count == 4 })
        #expect(layout.beams.allSatisfy { $0.direction == .up })
        #expect(layout.beams.allSatisfy { abs($0.start.x - (firstHead.position.x + style.stemXInset)) < 0.001 })
        #expect(layout.beams.allSatisfy { abs($0.end.x - (lastHead.position.x + style.stemXInset)) < 0.001 })
    }

    @Test("consecutive eighths create one beam level")
    func consecutiveEighthsCreateOneBeamLevel() throws {
        let notes = (0..<2).map { index in
            Note(
                interval: .eighth,
                noteType: .snare,
                measureNumber: 1,
                measureOffset: Double(index) / 8.0
            )
        }
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
        )
        let beam = try #require(layout.beams.first)

        #expect(layout.beams.count == 1)
        #expect(beam.level == 0)
        #expect(beam.noteHeadIDs.count == 2)
    }

    @Test("beams do not cross measure boundaries")
    func beamsDoNotCrossMeasureBoundaries() {
        let notes = [
            Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: 0.875),
            Note(interval: .eighth, noteType: .snare, measureNumber: 2, measureOffset: 0)
        ]
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
        )

        #expect(layout.stems.count == 2)
        #expect(layout.beams.isEmpty)
    }

    @Test("isolated eighth does not create beam")
    func isolatedEighthDoesNotCreateBeam() {
        let note = Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: 0)
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: [note], timeSignature: .fourFour)
        )

        #expect(layout.stems.count == 1)
        #expect(layout.beams.isEmpty)
    }

    @Test("cross voice notes do not beam together")
    func crossVoiceNotesDoNotBeamTogether() {
        let notes = [
            Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: 0),
            Note(interval: .eighth, noteType: .bass, measureNumber: 1, measureOffset: 0.125)
        ]
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
        )

        #expect(layout.stems.count == 2)
        #expect(layout.beams.isEmpty)
    }

    @Test("non-beamable note between eighths breaks beam run")
    func nonBeamableNoteBetweenEighthsBreaksBeamRun() {
        let notes = [
            Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: 0),
            Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0.125),
            Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: 0.25)
        ]
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
        )

        #expect(layout.stems.count == 3)
        #expect(layout.beams.isEmpty)
    }

    @Test("higher beam level does not span intervening lower duration note")
    func higherBeamLevelDoesNotSpanInterveningLowerDurationNote() {
        let notes = [
            Note(interval: .sixteenth, noteType: .snare, measureNumber: 1, measureOffset: 0),
            Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: 0.0625),
            Note(interval: .sixteenth, noteType: .snare, measureNumber: 1, measureOffset: 0.1875)
        ]
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
        )
        let levelZeroBeams = layout.beams.filter { $0.level == 0 }
        let levelOneBeams = layout.beams.filter { $0.level == 1 }

        #expect(levelZeroBeams.count == 1)
        #expect(levelZeroBeams.first?.noteHeadIDs.count == 3)
        #expect(levelOneBeams.isEmpty)
    }

    @Test("same time same voice duplicate eighths do not create zero length beam")
    func sameTimeSameVoiceDuplicateEighthsDoNotCreateZeroLengthBeam() {
        let notes = [
            Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: 0),
            Note(interval: .eighth, noteType: .highTom, measureNumber: 1, measureOffset: 0)
        ]
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
        )

        #expect(layout.stems.count == 2)
        #expect(layout.beams.isEmpty)
    }

    @Test("down stem beams align to down stem x coordinates")
    func downStemBeamsAlignToDownStemXCoordinates() throws {
        let style = NotationLayoutStyle.gameplayDefault
        let notes = [
            Note(interval: .eighth, noteType: .crash, measureNumber: 1, measureOffset: 0),
            Note(interval: .eighth, noteType: .crash, measureNumber: 1, measureOffset: 0.125)
        ]
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour, style: style)
        )
        let sortedHeads = layout.noteHeads.sorted { $0.timePosition < $1.timePosition }
        let firstHead = try #require(sortedHeads.first)
        let lastHead = try #require(sortedHeads.last)
        let beam = try #require(layout.beams.first)

        #expect(layout.beams.count == 1)
        #expect(beam.direction == .down)
        #expect(abs(beam.start.x - (firstHead.position.x - style.stemXInset)) < 0.001)
        #expect(abs(beam.end.x - (lastHead.position.x - style.stemXInset)) < 0.001)
        #expect(beam.start.y > firstHead.position.y)
    }

    // MARK: - Flag Rendering Tests

    @Test("isolated eighth note produces one flag")
    func isolatedEighthNoteProducesOneFlag() throws {
        let note = Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: 0)
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: [note], timeSignature: .fourFour)
        )

        #expect(layout.flags.count == 1)
        let flag = try #require(layout.flags.first)
        #expect(flag.flagIndex == 0)
        #expect(flag.stemDirection == .up)
        #expect(flag.noteHeadID == layout.noteHeads.first?.id)
    }

    @Test("isolated sixteenth note produces two flags")
    func isolatedSixteenthNoteProducesTwoFlags() throws {
        let note = Note(interval: .sixteenth, noteType: .snare, measureNumber: 1, measureOffset: 0)
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: [note], timeSignature: .fourFour)
        )

        #expect(layout.flags.count == 2)
        let indices = Set(layout.flags.map(\.flagIndex))
        #expect(indices == [0, 1])
    }

    @Test("beamed eighth notes produce no flags")
    func beamedEighthNotesProduceNoFlags() {
        let notes = (0..<2).map { index in
            Note(
                interval: .eighth,
                noteType: .snare,
                measureNumber: 1,
                measureOffset: Double(index) / 8.0
            )
        }
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
        )

        #expect(layout.beams.count == 1)
        #expect(layout.flags.isEmpty)
    }

    @Test("quarter notes produce no flags")
    func quarterNotesProduceNoFlags() {
        let note = Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0)
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: [note], timeSignature: .fourFour)
        )

        #expect(layout.flags.isEmpty)
    }

    @Test("mixed beamed and isolated notes produce flags only for isolated")
    func mixedBeamedAndIsolatedNotesProduceFlagsOnlyForIsolated() throws {
        let notes = [
            Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: 0),
            Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: 0.125),
            Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: 0.5)
        ]
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
        )

        // First two eighths are beamed, last one is isolated
        #expect(layout.beams.count == 1)
        #expect(layout.flags.count == 1)
        let isolatedHead = try #require(layout.noteHeads.first { $0.timePosition == 0.5 })
        let flag = try #require(layout.flags.first)
        #expect(flag.noteHeadID == isolatedHead.id)
    }

    @Test("down stem crash flag has down direction")
    func downStemCrashFlagHasDownDirection() throws {
        let note = Note(interval: .eighth, noteType: .crash, measureNumber: 1, measureOffset: 0)
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: [note], timeSignature: .fourFour)
        )

        let flag = try #require(layout.flags.first)
        #expect(flag.stemDirection == .down)
    }

    // MARK: - Barline Deduplication Tests

    @Test("adjacent measures on same row share single barline")
    func adjacentMeasuresOnSameRowShareSingleBarline() throws {
        let notes = (0..<8).map { index in
            Note(
                interval: .quarter,
                noteType: .snare,
                measureNumber: 1,
                measureOffset: Double(index % 4) / 4.0
            )
        }
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour, minimumMeasureCount: 3)
        )

        let sameRowMeasures = layout.measures.filter { $0.row == 0 }
        guard sameRowMeasures.count >= 2 else {
            Issue.record("Expected at least 2 measures on row 0")
            return
        }

        // Internal boundaries should have exactly one barline, not two
        let row0Bars = layout.measureBars.filter { $0.row == 0 }
        let barXPositions = Set(row0Bars.map(\.x))

        // For N measures on a row, we expect: 1 start bar + N end bars = N+1 bars
        // (start bar for first measure + end bar for each measure)
        // NOT 2*N bars (start + end for each)
        let expectedBarCount = sameRowMeasures.count + 1
        #expect(row0Bars.count == expectedBarCount)

        // No duplicate x positions
        #expect(barXPositions.count == row0Bars.count)
    }

    @Test("final measure barline is marked isFinal")
    func finalMeasureBarlineIsMarkedFinal() {
        let note = Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0)
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: [note], timeSignature: .fourFour, minimumMeasureCount: 2)
        )

        let finalBars = layout.measureBars.filter(\.isFinal)
        #expect(finalBars.count == 1)
        #expect(finalBars.first?.isFinal == true)
    }

    @Test("measure wrapping to new row gets separate start barline")
    func measureWrappingToNewRowGetsSeparateStartBarline() {
        // Create enough notes/measures to force a row wrap
        let notes = (0..<4).map { index in
            Note(
                interval: .quarter,
                noteType: .snare,
                measureNumber: 1,
                measureOffset: Double(index) / 4.0
            )
        }
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour, minimumMeasureCount: 20)
        )

        let rows = Set(layout.measures.map(\.row))
        guard rows.count >= 2 else {
            Issue.record("Expected measures to wrap to multiple rows")
            return
        }

        // Each row should have a start barline
        for row in rows {
            let rowMeasures = layout.measures.filter { $0.row == row }
            let rowBars = layout.measureBars.filter { $0.row == row }
            let hasStartBar = rowBars.contains { bar in
                abs(bar.x - (rowMeasures.first?.xOffset ?? -1)) < 0.001
            }
            #expect(hasStartBar)
        }
    }
}
