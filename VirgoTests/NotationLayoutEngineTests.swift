import Testing
import SwiftUI
@testable import Virgo
// swiftlint:disable file_length

@Suite("Notation Layout Engine Tests")
struct NotationLayoutEngineTests {
    @Test("default gameplay style preserves current low-density quarter spacing")
    func defaultStylePreservesQuarterSpacing() {
        let style = NotationLayoutStyle.gameplayDefault

        #expect(style.minimumNoteColumnGap == 28)
        #expect(style.minimumQuarterBeatGap == GameplayLayout.uniformSpacing)
        #expect(style.noteHeadWidth == GameplayLayout.beatColumnWidth)
    }

    @Test("notation layout style omits unused measure padding API")
    func notationLayoutStyleOmitsUnusedMeasurePaddingAPI() {
        let labels = Set(Mirror(reflecting: NotationLayoutStyle.gameplayDefault).children.compactMap(\.label))

        #expect(!labels.contains("measurePadding"))
    }

    @Test("notation layout exposes note head positions by note head ID")
    func notationLayoutExposesNoteHeadPositionsByNoteHeadID() {
        let labels = Set(Mirror(reflecting: NotationLayout.empty).children.compactMap(\.label))

        #expect(labels.contains("noteHeadPositionsByID"))
        #expect(!labels.contains("beatLookup"))
    }

    @Test("layout exposes a tab grid built from normalized note metadata")
    func layoutExposesTabGridFromNormalizedMetadata() throws {
        let note = Note(
            interval: .quarter,
            noteType: .snare,
            measureNumber: 1,
            measureOffset: 31.0 / 32.0,
            originKind: .dtx,
            normalizedMeasureIndex: 0,
            normalizedAbsoluteTick: 31,
            normalizedTickWithinMeasure: 31,
            normalizedTicksPerMeasure: 32
        )

        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: [note], timeSignature: .fourFour)
        )

        #expect(layout.tabGrid.ticksPerMeasure == 32)
        #expect(layout.tabGrid.leftPadding == GameplayLayout.barLineWidth + GameplayLayout.uniformSpacing)
        #expect(layout.tabGrid.measureWidth > GameplayLayout.measureWidth(for: .fourFour))
        #expect(layout.tabGrid.measureWidth < 700)
    }

    @Test("invalid normalized metadata falls back to deterministic 960 tick grid")
    func invalidNormalizedMetadataFallsBackToDeterministicGrid() {
        let notes = [
            Note(
                interval: .quarter,
                noteType: .snare,
                measureNumber: 1,
                measureOffset: 0.25,
                originKind: .dtx,
                normalizedMeasureIndex: 0,
                normalizedAbsoluteTick: 8,
                normalizedTickWithinMeasure: nil,
                normalizedTicksPerMeasure: 32
            ),
            Note(
                interval: .quarter,
                noteType: .bass,
                measureNumber: 1,
                measureOffset: 0.5,
                originKind: .dtx,
                normalizedMeasureIndex: 0,
                normalizedAbsoluteTick: 48,
                normalizedTickWithinMeasure: 40,
                normalizedTicksPerMeasure: 32
            )
        ]

        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
        )

        #expect(layout.tabGrid.ticksPerMeasure == TabGrid.fallbackTicksPerMeasure)
    }

    @Test("tab grid fallback measure width uses the shared grid formula")
    func tabGridFallbackMeasureWidthUsesSharedGridFormula() {
        #expect(
            TabGrid.fallback.measureWidth
                == TabGrid.fallback.leftPadding
                + CGFloat(TabGrid.fallback.ticksPerMeasure) * TabGrid.fallback.tickWidth
        )
    }

    @Test("tab grid maps beat boundaries to deterministic tick columns")
    func tabGridMapsBeatBoundariesToDeterministicTickColumns() throws {
        let note = Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0.0)
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: [note], timeSignature: .fourFour)
        )
        let measure = try #require(layout.measures.first)

        let startTick = layout.tabGrid.tickIndex(forBeatWithinMeasure: 0.0, beatsPerMeasure: 4)
        let secondBeatTick = layout.tabGrid.tickIndex(forBeatWithinMeasure: 1.0, beatsPerMeasure: 4)
        let startX = layout.tabGrid.xPosition(in: measure, tickIndex: startTick)
        let secondBeatX = layout.tabGrid.xPosition(in: measure, tickIndex: secondBeatTick)

        #expect(startTick == 0)
        #expect(secondBeatTick == layout.tabGrid.ticksPerMeasure / 4)
        #expect(abs(startX - (measure.xOffset + layout.tabGrid.leftPadding)) < 0.001)
        #expect(secondBeatX > startX)
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

    @Test("sixteenth notes use fixed grid spacing for readable columns")
    func sixteenthNotesUseFixedGridSpacingForReadableColumns() {
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

        #expect(layout.measures.first?.width == layout.tabGrid.measureWidth)
        for index in 1..<sortedX.count {
            #expect(sortedX[index] - sortedX[index - 1] >= 28)
        }
    }

    @Test("sparse and dense measures share fixed grid width")
    func sparseAndDenseMeasuresShareFixedGridWidth() throws {
        let notes = [
            Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0.0),
            Note(interval: .quarter, noteType: .snare, measureNumber: 2, measureOffset: 0.0),
            Note(interval: .sixteenth, noteType: .bass, measureNumber: 2, measureOffset: 1.0 / 16.0),
            Note(interval: .sixteenth, noteType: .snare, measureNumber: 2, measureOffset: 2.0 / 16.0),
            Note(interval: .sixteenth, noteType: .bass, measureNumber: 2, measureOffset: 3.0 / 16.0)
        ]
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour, minimumMeasureCount: 2)
        )
        let measure0 = try #require(layout.measures.first { $0.measureIndex == 0 })
        let measure1 = try #require(layout.measures.first { $0.measureIndex == 1 })

        #expect(measure0.width == measure1.width)
        #expect(measure0.width == layout.tabGrid.measureWidth)
    }

    @Test("sparse high resolution imported notes do not inflate from source resolution alone")
    func sparseHighResolutionImportedNotesDoNotInflateFromSourceResolutionAlone() throws {
        let notes = [
            Note(
                interval: .quarter,
                noteType: .snare,
                measureNumber: 1,
                measureOffset: 0.0,
                originKind: .dtx,
                normalizedMeasureIndex: 0,
                normalizedAbsoluteTick: 0,
                normalizedTickWithinMeasure: 0,
                normalizedTicksPerMeasure: 64
            ),
            Note(
                interval: .quarter,
                noteType: .bass,
                measureNumber: 1,
                measureOffset: 63.0 / 64.0,
                originKind: .dtx,
                normalizedMeasureIndex: 0,
                normalizedAbsoluteTick: 63,
                normalizedTickWithinMeasure: 63,
                normalizedTicksPerMeasure: 64
            )
        ]
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
        )
        let measure = try #require(layout.measures.first)
        let sortedX = layout.noteHeads.map(\.position.x).sorted()

        #expect(layout.tabGrid.ticksPerMeasure == 64)
        #expect(measure.width < 700)
        #expect(sortedX.last ?? 0 > sortedX.first ?? 0)
    }

    @Test("quarter notes align to fixed grid quarter columns")
    func quarterNotesAlignToFixedGridQuarterColumns() {
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
        let expectedGap = CGFloat(layout.tabGrid.ticksPerMeasure / 4) * layout.tabGrid.tickWidth

        #expect(sortedX.count == 4)
        #expect(abs((sortedX[1] - sortedX[0]) - expectedGap) < 0.001)
    }

    @Test("sparse quarter notes use fixed grid width and preserve first column")
    func sparseQuarterNotesUseFixedGridWidthAndPreserveFirstColumn() {
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

        #expect(measure?.width == layout.tabGrid.measureWidth)
        #expect(abs(firstX - expectedFirstX) < 0.001)
    }

    @Test("near identical simultaneous offsets keep fixed grid width")
    func nearIdenticalSimultaneousOffsetsKeepFixedGridWidth() {
        let notes = [
            Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0.0),
            Note(interval: .quarter, noteType: .bass, measureNumber: 1, measureOffset: 0.0004)
        ]
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
        )
        let uniqueX = Array(Set(layout.noteHeads.map(\.position.x))).sorted()

        #expect(layout.measures.first?.width == layout.tabGrid.measureWidth)
        #expect(uniqueX.count == 2)
        #expect((uniqueX.last ?? 0) - (uniqueX.first ?? 0) >= 16)
    }

    @Test("near identical cross voice offsets split heads within fixed grid width")
    func nearIdenticalCrossVoiceOffsetsSplitHeadsWithinFixedGridWidth() {
        let notes = [
            Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0.25),
            Note(interval: .quarter, noteType: .bass, measureNumber: 1, measureOffset: 0.24999999999999997)
        ]
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
        )
        let uniqueX = Array(Set(layout.noteHeads.map(\.position.x))).sorted()

        #expect(layout.measures.first?.width == layout.tabGrid.measureWidth)
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

    @Test("simultaneous quarter notes split voices within fixed grid width")
    func simultaneousQuarterNotesSplitVoicesWithinFixedGridWidth() {
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
        #expect(layout.measures.first?.width == layout.tabGrid.measureWidth)
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

        // Same-time, same-voice note heads share a single stem (chord grouping).
        #expect(layout.stems.count == 1)
        #expect(layout.stems.first?.noteHeadIDs.count == 2)
        #expect(layout.beams.isEmpty)
    }

    @Test("same voice chord notes share a single stem")
    func sameVoiceChordNotesShareSingleStem() throws {
        // Snare (.line3, up-stem) and highTom (.spaceBetween3And4, up-stem) are both
        // upper-voice drums with up-stems. When simultaneous, they share one stem.
        let notes = [
            Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0),
            Note(interval: .quarter, noteType: .highTom, measureNumber: 1, measureOffset: 0)
        ]
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
        )

        #expect(layout.stems.count == 1, "Chord notes at the same position should share one stem")
        let stem = try #require(layout.stems.first)
        #expect(stem.noteHeadIDs.count == 2, "Shared stem should reference both note head IDs")
        #expect(stem.direction == .up)
    }

    @Test("equidistant chord notes from middle line resolve deterministically")
    func equidistantChordNotesResolveDeterministically() throws {
        // Override crash to line4 (staffStep -6, distance 2, down-stem) and
        // highTom to line2 (staffStep -2, distance 2, up-stem).  Both are upper
        // voice, equidistant from middleStaffStep (-4), but different stem
        // directions.  The tie-break must deterministically pick the higher
        // staffStep (line2 → up-stem).
        let notes = [
            Note(interval: .quarter, noteType: .crash, measureNumber: 1, measureOffset: 0),
            Note(interval: .quarter, noteType: .highTom, measureNumber: 1, measureOffset: 0)
        ]
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(
                notes: notes,
                timeSignature: .fourFour,
                notePositionOverrides: [.crash: .line4, .tom1: .line2]
            )
        )

        // Both notes should share a single stem with unified direction.
        // Tie-break prefers higher staffStep (line2, step -2 > line4, step -6)
        // so the chord unifies to up-stem.
        #expect(layout.stems.count == 1, "Equidistant chord should share one stem")
        let stem = try #require(layout.stems.first)
        #expect(stem.direction == .up, "Tie-break should prefer higher staffStep (up)")
        let heads = layout.noteHeads.sorted { $0.staffStep < $1.staffStep }
        #expect(heads.allSatisfy { $0.stemDirection == .up })
    }

    @Test("different voice notes at same time get separate stems")
    func differentVoiceNotesAtSameTimeGetSeparateStems() {
        // Snare (upper voice) and bass (lower voice) at the same time
        // should get separate stems due to voice collision offset.
        let notes = [
            Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0),
            Note(interval: .quarter, noteType: .bass, measureNumber: 1, measureOffset: 0)
        ]
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
        )

        #expect(layout.stems.count == 2, "Different-voice notes should get separate stems")
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

    // MARK: - Beamed Stem Rendering Tests

    @Test("all notes in up-stem beam group have stems reaching beam level 0")
    func allUpStemBeamedNotesReachBeam() throws {
        let style = NotationLayoutStyle.gameplayDefault
        let notes = (0..<4).map { index in
            Note(
                interval: .eighth,
                noteType: .snare,
                measureNumber: 1,
                measureOffset: Double(index) / 8.0
            )
        }
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour, style: style)
        )
        let beam = try #require(layout.beams.first { $0.level == 0 })

        // Every note head in the beam must have a stem whose end Y matches the beam Y at that stem x.
        for noteHeadID in beam.noteHeadIDs {
            let noteHead = try #require(layout.noteHeads.first { $0.id == noteHeadID })
            let stem = try #require(layout.stems.first { $0.noteHeadIDs.contains(noteHeadID) })
            let stemX = noteHead.position.x + style.stemXInset  // up-stem inset
            let t = (stemX - beam.start.x) / (beam.end.x - beam.start.x)
            let expectedY = beam.start.y + t * (beam.end.y - beam.start.y)
            #expect(abs(stem.end.y - expectedY) < 0.5,
                    "Stem for noteHead \(noteHeadID) end.y \(stem.end.y) should reach beam Y \(expectedY)")
        }
    }

    @Test("all notes in down-stem beam group have stems reaching beam")
    func allDownStemBeamedNotesReachBeam() throws {
        let style = NotationLayoutStyle.gameplayDefault
        let notes = (0..<4).map { index in
            Note(
                interval: .eighth,
                noteType: .crash,
                measureNumber: 1,
                measureOffset: Double(index) / 8.0
            )
        }
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour, style: style)
        )
        let beam = try #require(layout.beams.first { $0.level == 0 })

        for noteHeadID in beam.noteHeadIDs {
            let noteHead = try #require(layout.noteHeads.first { $0.id == noteHeadID })
            let stem = try #require(layout.stems.first { $0.noteHeadIDs.contains(noteHeadID) })
            let stemX = noteHead.position.x - style.stemXInset  // down-stem inset
            let t = (stemX - beam.start.x) / (beam.end.x - beam.start.x)
            let expectedY = beam.start.y + t * (beam.end.y - beam.start.y)
            #expect(abs(stem.end.y - expectedY) < 0.5,
                    "Stem for noteHead \(noteHeadID) end.y \(stem.end.y) should reach beam Y \(expectedY)")
        }
    }

    @Test("all sixteenth notes in beam group have stems reaching outermost beam level")
    func allSixteenthBeamedNotesReachBothBeamLevels() throws {
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

        // Find the outermost beam (highest level = furthest from note heads for up-stems)
        let outermostBeam = try #require(layout.beams.max { $0.level < $1.level })

        // Every stem must reach the outermost beam at its stem x position
        for noteHeadID in outermostBeam.noteHeadIDs {
            let noteHead = try #require(layout.noteHeads.first { $0.id == noteHeadID })
            let stem = try #require(layout.stems.first { $0.noteHeadIDs.contains(noteHeadID) })
            let stemX = noteHead.position.x + style.stemXInset
            let t = (stemX - outermostBeam.start.x) / (outermostBeam.end.x - outermostBeam.start.x)
            let expectedY = outermostBeam.start.y + t * (outermostBeam.end.y - outermostBeam.start.y)
            #expect(abs(stem.end.y - expectedY) < 0.5,
                    "Stem for sixteenth noteHead \(noteHeadID) should reach outermost beam")
        }
    }

    @Test("down-stem sixteenth notes reach outermost beam level")
    func downStemSixteenthNotesReachOutermostBeam() throws {
        let style = NotationLayoutStyle.gameplayDefault
        let notes = (0..<4).map { index in
            Note(
                interval: .sixteenth,
                noteType: .crash,
                measureNumber: 1,
                measureOffset: Double(index) / 16.0
            )
        }
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour, style: style)
        )

        // Crash notes have down-stems; verify two beam levels exist
        #expect(layout.beams.count == 2)
        #expect(Set(layout.beams.map(\.level)) == [0, 1])

        // The outermost beam (level 1) is farthest from the note heads in stem direction.
        // For down-stems that means it has the highest Y value.
        let outermostBeam = try #require(layout.beams.max { $0.level < $1.level })
        #expect(outermostBeam.direction == .down)

        // Every stem must reach the outermost beam at its stem x position
        for noteHeadID in outermostBeam.noteHeadIDs {
            let noteHead = try #require(layout.noteHeads.first { $0.id == noteHeadID })
            let stem = try #require(layout.stems.first { $0.noteHeadIDs.contains(noteHeadID) })
            let stemX = noteHead.position.x - style.stemXInset  // down-stem inset
            let t = (stemX - outermostBeam.start.x) / (outermostBeam.end.x - outermostBeam.start.x)
            let expectedY = outermostBeam.start.y + t * (outermostBeam.end.y - outermostBeam.start.y)
            #expect(abs(stem.end.y - expectedY) < 0.5)
        }
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

    @Test("internal barline aligns with next same-row measure's xOffset")
    func internalBarlineAlignsWithNextSameRowMeasureXOffset() throws {
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
        let sameRowBars = layout.measureBars.filter { $0.row == 0 }
        guard sameRowMeasures.count >= 2 else {
            Issue.record("Expected at least 2 measures on row 0")
            return
        }

        // For each pair of consecutive same-row measures, the end barline of the
        // earlier measure must sit exactly at the later measure's xOffset — not
        // at the earlier measure's right edge, which would leave a measureSpacing
        // gap between the drawn bar and the next measure.
        for index in 0..<(sameRowMeasures.count - 1) {
            let current = sameRowMeasures[index]
            let next = sameRowMeasures[index + 1]
            let endBar = try #require(
                sameRowBars.first { $0.id == "bar_\(current.measureIndex)_end" }
            )

            #expect(abs(endBar.x - next.xOffset) < 0.001)
        }

        // The last measure's end barline should remain at its right edge
        let lastMeasure = sameRowMeasures[sameRowMeasures.count - 1]
        let lastEndBar = try #require(
            sameRowBars.first { $0.id == "bar_\(lastMeasure.measureIndex)_end" }
        )
        #expect(abs(lastEndBar.x - (lastMeasure.xOffset + lastMeasure.width)) < 0.001)
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

    // MARK: - Mixed-Duration Beam Flag Tests

    @Test("sixteenth in mixed sixteenth-eighth beam run produces one flag for uncovered level")
    func sixteenthInMixedBeamRunProducesFlagForUncoveredLevel() throws {
        // sixteenth (flagCount=2) + eighth (flagCount=1) in the same beam run.
        // Level-0 beam covers both notes; level-1 has only the sixteenth
        // (< 2 notes, so no beam emitted).  The sixteenth needs a flag at
        // index 1 to represent the uncovered second level.
        let notes = [
            Note(interval: .sixteenth, noteType: .snare, measureNumber: 1, measureOffset: 0),
            Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: 0.0625)
        ]
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
        )

        // One level-0 beam spanning both notes
        let levelZeroBeams = layout.beams.filter { $0.level == 0 }
        #expect(levelZeroBeams.count == 1)
        #expect(levelZeroBeams.first?.noteHeadIDs.count == 2)

        // No level-1 beam (only one sixteenth qualifies, < 2 minimum)
        let levelOneBeams = layout.beams.filter { $0.level == 1 }
        #expect(levelOneBeams.isEmpty)

        // The sixteenth should have one flag (for the uncovered level 1)
        // The eighth should have no flags (fully covered by level-0 beam)
        let sixteenthHead = try #require(layout.noteHeads.first { $0.interval == .sixteenth })
        let eighthHead = try #require(layout.noteHeads.first { $0.interval == .eighth })
        let sixteenthFlags = layout.flags.filter { $0.noteHeadID == sixteenthHead.id }
        let eighthFlags = layout.flags.filter { $0.noteHeadID == eighthHead.id }

        #expect(sixteenthFlags.count == 1)
        #expect(sixteenthFlags.first?.flagIndex == 1)
        #expect(eighthFlags.isEmpty)
    }

    @Test("thirty-second in mixed beam run produces flags for all uncovered levels")
    func thirtySecondInMixedBeamRunProducesFlagsForAllUncoveredLevels() throws {
        // thirty-second (flagCount=3) + eighth (flagCount=1).
        // Level-0 beam covers both; levels 1-2 have only the thirty-second.
        // Two flags should be emitted for the thirty-second (indices 1 and 2).
        let notes = [
            Note(interval: .thirtysecond, noteType: .snare, measureNumber: 1, measureOffset: 0),
            Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: 0.03125)
        ]
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
        )

        let thirtySecondHead = try #require(layout.noteHeads.first { $0.interval == .thirtysecond })
        let eighthHead = try #require(layout.noteHeads.first { $0.interval == .eighth })
        let thirtySecondFlags = layout.flags.filter { $0.noteHeadID == thirtySecondHead.id }
        let eighthFlags = layout.flags.filter { $0.noteHeadID == eighthHead.id }

        #expect(thirtySecondFlags.count == 2)
        let flagIndices = Set(thirtySecondFlags.map(\.flagIndex))
        #expect(flagIndices == [1, 2])
        #expect(eighthFlags.isEmpty)
    }

    @Test("uniform sixteenths in beam run produce no flags")
    func uniformSixteenthsInBeamRunProduceNoFlags() {
        // All sixteenths: both level-0 and level-1 beams are emitted, so no flags.
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

        #expect(layout.beams.count == 2)
        #expect(layout.flags.isEmpty)
    }

    // MARK: - Content Width

    @Test("contentWidth is at least maxRowWidth for any layout")
    func contentWidthAtLeastMaxRowWidth() {
        let layout = NotationLayout.empty
        #expect(layout.contentWidth == GameplayLayout.maxRowWidth)
    }

    @Test("contentWidth expands for notes beyond default row width")
    func contentWidthExpandsForDenseNotes() throws {
        // Use sixteenth (0.0625) spacing for denser notes that exceed default row width.
        let notes = (0..<8).map { i in
            Note(interval: .sixteenth, noteType: .snare, measureNumber: 1, measureOffset: Double(i) * 0.0625)
        }
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
        )
        let lastNoteHead = try #require(layout.noteHeads.max(by: { $0.position.x < $1.position.x }))
        #expect(layout.contentWidth > lastNoteHead.position.x)
        // Width expands to accommodate dense notes - at minimum equals max row width.
        #expect(layout.contentWidth >= GameplayLayout.maxRowWidth)
    }

    @Test("notes in different rows get separate stems even at same x position")
    func notesInDifferentRowsGetSeparateStems() throws {
        let notes = [
            Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0),
            Note(interval: .quarter, noteType: .snare, measureNumber: 4, measureOffset: 0)
        ]
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour, minimumMeasureCount: 5)
        )
        let heads = layout.noteHeads.sorted { $0.measureIndex < $1.measureIndex }
        #expect(heads.count == 2)
        let first = try #require(heads.first), second = try #require(heads.last)
        #expect(first.row != second.row)
        #expect(abs(first.position.x - second.position.x) < 1.0)
        #expect(layout.stems.count == 2, "Notes in different rows should get separate stems")
        for stem in layout.stems {
            #expect(stem.noteHeadIDs.count == 1)
        }
    }

}
