import Testing
import SwiftUI
@testable import Virgo
// swiftlint:disable file_length

@Suite("Notation Layout Engine Tests")
// swiftlint:disable:next type_body_length
struct NotationLayoutEngineTests {
    @Test("default gameplay style preserves current low-density quarter spacing")
    func defaultStylePreservesQuarterSpacing() {
        let style = NotationLayoutStyle.gameplayDefault

        #expect(style.minimumNoteColumnGap == 28)
        #expect(style.minimumQuarterBeatGap == GameplayLayout.uniformSpacing)
        #expect(style.noteHeadWidth == GameplayLayout.beatColumnWidth)
    }

    @Test("row-width style copy preserves hook length")
    func rowWidthStyleCopyPreservesHookLength() {
        let style = NotationLayoutStyle.gameplayDefault
        let resized = style.with(rowWidth: 2_000)

        #expect(style.beamHookLength == 12)
        #expect(resized.beamHookLength == style.beamHookLength)
        #expect(resized.rowWidth == 2_000)
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

    @Test("mixed normalized and fallback notes use fallback grid resolution")
    func mixedNormalizedAndFallbackNotesUseFallbackGridResolution() throws {
        let fallbackNote = Note(
            interval: .quarter,
            noteType: .bass,
            measureNumber: 1,
            measureOffset: 0.1
        )
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
                normalizedTicksPerMeasure: 32
            ),
            fallbackNote
        ]

        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
        )
        let measure = try #require(layout.measures.first)
        let fallbackHead = try #require(layout.noteHeads.first { abs($0.timePosition - 0.1) < 0.0001 })
        let fallbackTick = Int((0.1 * Double(TabGrid.fallbackTicksPerMeasure)).rounded())
        let expectedX = layout.tabGrid.xPosition(in: measure, tickIndex: fallbackTick)

        #expect(layout.tabGrid.ticksPerMeasure == TabGrid.fallbackTicksPerMeasure)
        #expect(abs(fallbackHead.position.x - expectedX) < 0.001)
    }

    @Test("tab grid fallback measure width uses the shared grid formula")
    func tabGridFallbackMeasureWidthUsesSharedGridFormula() {
        #expect(
            TabGrid.fallback.measureWidth
                == TabGrid.fallback.leftPadding
                + CGFloat(TabGrid.fallback.ticksPerMeasure) * TabGrid.fallback.tickWidth
        )
    }

    @Test("tab grid does not inflate from adjacent ticks in different measures")
    func tabGridDoesNotInflateFromAdjacentTicksInDifferentMeasures() throws {
        // Two measures on a high-resolution 4096-tick grid, each holding a
        // single sparse note at adjacent tick columns (tick 0 in measure 0,
        // tick 1 in measure 1). The per-measure gap is undefined (one note
        // per measure), so the grid must fall back to the baseline gap rather
        // than treating the cross-measure tick difference of 1 as the spacing
        // gap — which would inflate every measure to ~4096 * tickWidth points.
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
                normalizedTicksPerMeasure: 4096
            ),
            Note(
                interval: .quarter,
                noteType: .bass,
                measureNumber: 2,
                measureOffset: 1.0 / 4096.0,
                originKind: .dtx,
                normalizedMeasureIndex: 1,
                normalizedAbsoluteTick: 4097,
                normalizedTickWithinMeasure: 1,
                normalizedTicksPerMeasure: 4096
            )
        ]
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
        )

        #expect(layout.tabGrid.ticksPerMeasure == 4096)
        #expect(layout.tabGrid.measureWidth < 700)
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

    @Test("fixed grid wrapping is deterministic across local note density")
    func fixedGridWrappingIsDeterministicAcrossLocalNoteDensity() throws {
        let notes = [
            Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0.0),
            Note(interval: .sixteenth, noteType: .snare, measureNumber: 2, measureOffset: 0.0),
            Note(interval: .sixteenth, noteType: .bass, measureNumber: 2, measureOffset: 1.0 / 16.0),
            Note(interval: .sixteenth, noteType: .snare, measureNumber: 2, measureOffset: 2.0 / 16.0),
            Note(interval: .quarter, noteType: .bass, measureNumber: 3, measureOffset: 0.0),
            Note(interval: .quarter, noteType: .snare, measureNumber: 4, measureOffset: 0.0)
        ]
        let style = NotationLayoutStyle.gameplayDefault.with(rowWidth: 620)
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(
                notes: notes,
                timeSignature: .fourFour,
                minimumMeasureCount: 4,
                style: style
            )
        )

        let widths = Set(layout.measures.map(\.width))
        #expect(widths.count == 1)
        #expect(layout.measures.map(\.row) == [0, 1, 2, 3])
    }

    @Test("sparse degenerate imported grid is raised to meter baseline for beat mapping")
    func sparseDegenerateImportedGridIsRaisedToMeterBaselineForBeatMapping() throws {
        // A chart where every playable line has one chip produces
        // `normalizedTicksPerMeasure == 1` from the parser. Without a meter
        // baseline, the canonical grid would be 1, `measureWidth` would be
        // roughly one tick wide, and `tickIndex(forBeatWithinMeasure:)` would
        // collapse every 4/4 beat to tick 0 or 1 — breaking the playhead and
        // beat cache and packing many tiny measures on one row.
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
                normalizedTicksPerMeasure: 1
            ),
            Note(
                interval: .quarter,
                noteType: .bass,
                measureNumber: 2,
                measureOffset: 0.0,
                originKind: .dtx,
                normalizedMeasureIndex: 1,
                normalizedAbsoluteTick: 1,
                normalizedTickWithinMeasure: 0,
                normalizedTicksPerMeasure: 1
            )
        ]
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
        )
        let measure = try #require(layout.measures.first)

        // 4/4 sixteenth baseline = 4 * 16 / 4 = 16.
        #expect(layout.tabGrid.ticksPerMeasure == 16)
        #expect(measure.width > GameplayLayout.barLineWidth + GameplayLayout.uniformSpacing)

        // Every beat in 4/4 must map to a distinct tick column.
        let beatTicks = (0...4).map {
            layout.tabGrid.tickIndex(forBeatWithinMeasure: Double($0), beatsPerMeasure: 4)
        }
        #expect(beatTicks == [0, 4, 8, 12, 16])
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

    @Test("same-time kick snare and hi-hat share the exact grid column")
    func sameTimeKickSnareAndHiHatShareExactGridColumn() throws {
        let notes = [
            Note(interval: .quarter, noteType: .bass, measureNumber: 1, measureOffset: 0.25),
            Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0.25),
            Note(interval: .quarter, noteType: .hiHat, measureNumber: 1, measureOffset: 0.25)
        ]
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
        )
        let heads = layout.noteHeads
        let firstHead = try #require(heads.first)
        let measure = try #require(
            layout.measures.first { $0.measureIndex == firstHead.timeColumn.measureIndex }
        )
        let expectedX = layout.tabGrid.xPosition(
            in: measure,
            tickIndex: firstHead.timeColumn.tickWithinMeasure
        )

        #expect(heads.count == 3)
        #expect(heads.allSatisfy { $0.timeColumn == firstHead.timeColumn })
        #expect(heads.allSatisfy { $0.position.x == expectedX })
        #expect(Set(heads.map(\.position.x)).count == 1)
    }

    @Test("near-equal offsets resolving to one tick share x")
    func nearEqualOffsetsResolvingToOneTickShareX() throws {
        let notes = [
            Note(interval: .quarter, noteType: .bass, measureNumber: 1, measureOffset: 0.25),
            Note(
                interval: .quarter,
                noteType: .snare,
                measureNumber: 1,
                measureOffset: 0.249_999_999_999_999_97
            )
        ]
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
        )
        let kick = try #require(layout.noteHeads.first { $0.drumType == .kick })
        let snare = try #require(layout.noteHeads.first { $0.drumType == .snare })

        #expect(kick.timeColumn == snare.timeColumn)
        #expect(kick.position.x == snare.position.x)
    }

    @Test("simultaneous quarter pairs produce four time columns")
    func simultaneousQuarterPairsProduceFourTimeColumns() {
        let notes = (0..<4).flatMap { index in
            [
                Note(
                    interval: .quarter,
                    noteType: .snare,
                    measureNumber: 1,
                    measureOffset: Double(index) / 4
                ),
                Note(
                    interval: .quarter,
                    noteType: .bass,
                    measureNumber: 1,
                    measureOffset: Double(index) / 4
                )
            ]
        }
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
        )

        #expect(layout.noteHeads.count == 8)
        #expect(Set(layout.noteHeads.map(\.timeColumn)).count == 4)
        #expect(Set(layout.noteHeads.map(\.position.x)).count == 4)
    }

    @Test("cross-voice chords do not inflate fixed-grid metrics")
    func crossVoiceChordsDoNotInflateFixedGridMetrics() {
        let style = NotationLayoutStyle.gameplayDefault
        let singleVoice = [
            Note(interval: .sixteenth, noteType: .snare, measureNumber: 1, measureOffset: 0),
            Note(interval: .sixteenth, noteType: .snare, measureNumber: 1, measureOffset: 0.0625)
        ]
        let mixedVoice = singleVoice + [
            Note(interval: .sixteenth, noteType: .bass, measureNumber: 1, measureOffset: 0),
            Note(interval: .sixteenth, noteType: .bass, measureNumber: 1, measureOffset: 0.0625)
        ]

        let singleLayout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: singleVoice, timeSignature: .fourFour, style: style)
        )
        let mixedLayout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: mixedVoice, timeSignature: .fourFour, style: style)
        )
        let columns = Array(Set(mixedLayout.noteHeads.map(\.position.x))).sorted()

        #expect(mixedLayout.tabGrid.tickWidth == singleLayout.tabGrid.tickWidth)
        #expect(mixedLayout.tabGrid.measureWidth == singleLayout.tabGrid.measureWidth)
        #expect(columns.count == 2)
        #expect(columns[1] - columns[0] >= style.minimumNoteColumnGap)
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

    @Test("rendered head preserves source and notation identity")
    func renderedHeadPreservesSourceAndNotationIdentity() throws {
        let note = Note(
            interval: .quarter,
            noteType: .openHiHat,
            measureNumber: 1,
            measureOffset: 0,
            originKind: .dtx,
            sourceLaneID: "18",
            sourceNoteID: "A1"
        )
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: [note], timeSignature: .fourFour)
        )
        let head = try #require(layout.noteHeads.first)

        #expect(head.sourceObjectID == ObjectIdentifier(note))
        #expect(head.sourceLaneID == "18")
        #expect(head.sourceChipID == "A1")
        #expect(head.noteType == .openHiHat)
        #expect(head.drumType == .hiHat)
        #expect(head.glyph == .cross)
        #expect(head.variant == .openHiHat)
        #expect(head.voice == .upper)
        #expect(head.stemDirection == .up)
    }

    @Test("unknown lane fallback preserves raw rendered identity")
    func unknownLaneFallbackPreservesRawRenderedIdentity() throws {
        let note = Note(
            interval: .quarter,
            noteType: .ride,
            measureNumber: 1,
            measureOffset: 0,
            originKind: .dtx,
            sourceLaneID: "AA",
            sourceNoteID: "7F"
        )
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: [note], timeSignature: .fourFour)
        )
        let head = try #require(layout.noteHeads.first)

        #expect(head.sourceObjectID == ObjectIdentifier(note))
        #expect(head.sourceLaneID == "AA")
        #expect(head.sourceChipID == "7F")
        #expect(head.noteType == .ride)
        #expect(head.drumType == .ride)
        #expect(head.variant == .ride)
    }

    @Test("identical heads retain distinct identities and lookup entries")
    func identicalHeadsRetainDistinctIdentitiesAndLookupEntries() {
        let notes = [
            Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0),
            Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0)
        ]
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
        )
        let heads = layout.noteHeads
        let renderedIDs = Set(heads.map(\.id))
        let tickKey = 0

        #expect(heads.count == 2)
        #expect(renderedIDs.count == 2)
        #expect(Set(heads.map(\.sourceObjectID)).count == 2)
        #expect(layout.noteHeadPositionsByID.count == 2)
        #expect(layout.noteHeadIDsByLayoutTick[tickKey] == renderedIDs)
    }

    @Test("ledger width follows authored glyph bounds")
    func ledgerWidthFollowsAuthoredGlyphBounds() throws {
        let style = NotationLayoutStyle.gameplayDefault
        let note = Note(interval: .quarter, noteType: .crash, measureNumber: 1, measureOffset: 0)
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: [note], timeSignature: .fourFour, style: style)
        )
        let head = try #require(layout.noteHeads.first)
        let ledger = try #require(layout.ledgerLines.first)
        let glyphBounds = head.glyph.bounds(
            centeredAt: head.position,
            size: layout.noteHeadSize
        )

        #expect(ledger.start.x == glyphBounds.minX - style.ledgerLineOverhang)
        #expect(ledger.end.x == glyphBounds.maxX + style.ledgerLineOverhang)
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

    @Test("fine grid distinct ticks do not receive voice collision offsets")
    func fineGridDistinctTicksDoNotReceiveVoiceCollisionOffsets() throws {
        // Imported chart with a 4096-tick normalized grid: snare at tick 0 and
        // kick at tick 1 occupy distinct tab-grid columns, so they must NOT be
        // treated as a voice collision. The legacy 960-column quantization rounds
        // both offsets to column 0, which would wrongly apply collision offsets
        // and shift the noteheads off their grid/playhead columns.
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
                normalizedTicksPerMeasure: 4096
            ),
            Note(
                interval: .quarter,
                noteType: .bass,
                measureNumber: 1,
                measureOffset: 1.0 / 4096.0,
                originKind: .dtx,
                normalizedMeasureIndex: 0,
                normalizedAbsoluteTick: 1,
                normalizedTickWithinMeasure: 1,
                normalizedTicksPerMeasure: 4096
            )
        ]
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
        )
        let measure = try #require(layout.measures.first)
        let snare = try #require(layout.noteHeads.first { $0.drumType == .snare })
        let kick = try #require(layout.noteHeads.first { $0.drumType == .kick })

        let snareExpectedX = layout.tabGrid.xPosition(in: measure, tickIndex: 0)
        let kickExpectedX = layout.tabGrid.xPosition(in: measure, tickIndex: 1)

        #expect(abs(snare.position.x - snareExpectedX) < 0.001)
        #expect(abs(kick.position.x - kickExpectedX) < 0.001)
    }

}

extension NotationLayoutEngineTests {
    @Test("crash stem uses catalog up direction")
    func crashStemUsesCatalogUpDirection() throws {
        let style = NotationLayoutStyle.gameplayDefault
        let note = Note(interval: .quarter, noteType: .crash, measureNumber: 1, measureOffset: 0)
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: [note], timeSignature: .fourFour, style: style)
        )
        let crash = try #require(layout.noteHeads.first { $0.drumType == .crash })
        let stem = try #require(layout.stems.first)
        let anchorOffset = crash.glyph.stemAnchorOffset(
            direction: crash.stemDirection,
            in: style.noteHeadSize
        )
        let expectedAnchor = CGPoint(
            x: crash.position.x + anchorOffset.x,
            y: crash.position.y + anchorOffset.y
        )

        #expect(crash.stemDirection == .up)
        #expect(stem.direction == .up)
        #expect(stem.start == expectedAnchor)
        #expect(stem.end.y < stem.start.y)
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
        let anchorOffset = snare.glyph.stemAnchorOffset(
            direction: snare.stemDirection,
            in: style.noteHeadSize
        )
        let expectedAnchor = CGPoint(
            x: snare.position.x + anchorOffset.x,
            y: snare.position.y + anchorOffset.y
        )

        #expect(snare.stemDirection == .up)
        #expect(stem.direction == .up)
        #expect(stem.start == expectedAnchor)
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
        let firstAnchorOffset = firstHead.glyph.stemAnchorOffset(
            direction: firstHead.stemDirection,
            in: style.noteHeadSize
        )
        let lastAnchorOffset = lastHead.glyph.stemAnchorOffset(
            direction: lastHead.stemDirection,
            in: style.noteHeadSize
        )
        let expectedFirstAnchor = CGPoint(
            x: firstHead.position.x + firstAnchorOffset.x,
            y: firstHead.position.y + firstAnchorOffset.y
        )
        let expectedLastAnchor = CGPoint(
            x: lastHead.position.x + lastAnchorOffset.x,
            y: lastHead.position.y + lastAnchorOffset.y
        )

        #expect(layout.beams.count == 2)
        #expect(Set(layout.beams.map(\.level)) == [0, 1])
        #expect(layout.beams.allSatisfy { $0.noteHeadIDs.count == 4 })
        #expect(layout.beams.allSatisfy { $0.direction == .up })
        #expect(layout.beams.allSatisfy { $0.start.x == expectedFirstAnchor.x })
        #expect(layout.beams.allSatisfy { $0.end.x == expectedLastAnchor.x })
    }

    @Test("consecutive eighths create one beam level")
    func consecutiveEighthsCreateOneBeamLevel() throws {
        let style = NotationLayoutStyle.gameplayDefault
        let notes = (0..<2).map { index in
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
        let beam = try #require(layout.beams.first)
        let sortedHeads = layout.noteHeads.sorted { $0.timePosition < $1.timePosition }
        let firstHead = try #require(sortedHeads.first)
        let lastHead = try #require(sortedHeads.last)
        let firstAnchorOffset = firstHead.glyph.stemAnchorOffset(
            direction: firstHead.stemDirection,
            in: style.noteHeadSize
        )
        let lastAnchorOffset = lastHead.glyph.stemAnchorOffset(
            direction: lastHead.stemDirection,
            in: style.noteHeadSize
        )

        #expect(layout.beams.count == 1)
        #expect(beam.level == 0)
        #expect(beam.noteHeadIDs.count == 2)
        #expect(beam.start.x == firstHead.position.x + firstAnchorOffset.x)
        #expect(beam.end.x == lastHead.position.x + lastAnchorOffset.x)
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

    @Test("higher beam level uses hooks around intervening lower duration note")
    func higherBeamLevelUsesHooksAroundInterveningLowerDurationNote() {
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
        #expect(levelOneBeams.count == 2)
        #expect(Set(levelOneBeams.map(\.kind)) == [.forwardHook, .backwardHook])
        #expect(levelOneBeams.allSatisfy { $0.noteHeadIDs.count == 1 })
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

        let renderedHeadIDs = Set(layout.noteHeads.map(\.id))

        #expect(renderedHeadIDs.count == 2)
        #expect(Set(layout.noteHeads.map(\.timeColumn)).count == 1)
        #expect(layout.stems.count == 1)
        #expect(Set(layout.stems.first?.noteHeadIDs ?? []) == renderedHeadIDs)
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

    @Test("same-type simultaneous hits share a single stem")
    func sameTypeSimultaneousHitsShareSingleStem() throws {
        // Two crash cymbal hits at the same time should share one stem.
        // Same drum type → same voice → same stem direction → one stem.
        let notes = [
            Note(interval: .quarter, noteType: .crash, measureNumber: 1, measureOffset: 0),
            Note(interval: .quarter, noteType: .crash, measureNumber: 1, measureOffset: 0)
        ]
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
        )

        #expect(layout.stems.count == 1, "Same-type simultaneous hits should share one stem")
        let stem = try #require(layout.stems.first)
        #expect(stem.noteHeadIDs.count == 2, "Shared stem should reference both note head IDs")
        #expect(stem.direction == .up)
    }

    @Test("same-voice chord notes share unified stem direction regardless of position")
    func sameVoiceChordNotesShareUnifiedStemDirection() throws {
        // Override crash to line4 (staffStep -6) and highTom to line2
        // (staffStep -2).  Both are upper-voice drums with up-stems.
        // Stem direction is voice-first, not position-dependent, so both
        // resolve to up-stem and share a single stem regardless of their
        // distance from the middle staff line.
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
        // Voice-first stem direction resolves both to up-stem.
        #expect(layout.stems.count == 1, "Same-voice chord should share one stem")
        let stem = try #require(layout.stems.first)
        #expect(stem.direction == .up, "Upper-voice notes should have up-stem")
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
        let stemMemberships = layout.stems.map { Set($0.noteHeadIDs) }
        #expect(stemMemberships.count == 2)
        #expect(stemMemberships[0].isDisjoint(with: stemMemberships[1]))
    }

    @Test("down stem beams align to down stem x coordinates")
    func downStemBeamsAlignToDownStemXCoordinates() throws {
        let style = NotationLayoutStyle.gameplayDefault
        let notes = [
            Note(interval: .eighth, noteType: .bass, measureNumber: 1, measureOffset: 0),
            Note(interval: .eighth, noteType: .bass, measureNumber: 1, measureOffset: 0.125)
        ]
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour, style: style)
        )
        let sortedHeads = layout.noteHeads.sorted { $0.timePosition < $1.timePosition }
        let firstHead = try #require(sortedHeads.first)
        let lastHead = try #require(sortedHeads.last)
        let beam = try #require(layout.beams.first)
        let firstAnchorOffset = firstHead.glyph.stemAnchorOffset(
            direction: firstHead.stemDirection,
            in: style.noteHeadSize
        )
        let lastAnchorOffset = lastHead.glyph.stemAnchorOffset(
            direction: lastHead.stemDirection,
            in: style.noteHeadSize
        )

        #expect(layout.beams.count == 1)
        #expect(beam.direction == .down)
        #expect(beam.start.x == firstHead.position.x + firstAnchorOffset.x)
        #expect(beam.end.x == lastHead.position.x + lastAnchorOffset.x)
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
            let anchorOffset = noteHead.glyph.stemAnchorOffset(
                direction: noteHead.stemDirection,
                in: style.noteHeadSize
            )
            let stemX = noteHead.position.x + anchorOffset.x
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
                noteType: .bass,
                measureNumber: 1,
                measureOffset: Double(index) / 8.0
            )
        }
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour, style: style)
        )
        let beam = try #require(layout.beams.first { $0.level == 0 })
        #expect(beam.direction == .down)

        for noteHeadID in beam.noteHeadIDs {
            let noteHead = try #require(layout.noteHeads.first { $0.id == noteHeadID })
            let stem = try #require(layout.stems.first { $0.noteHeadIDs.contains(noteHeadID) })
            #expect(noteHead.stemDirection == .down)
            #expect(stem.direction == .down)
            let anchorOffset = noteHead.glyph.stemAnchorOffset(
                direction: noteHead.stemDirection,
                in: style.noteHeadSize
            )
            let stemX = noteHead.position.x + anchorOffset.x
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
            let anchorOffset = noteHead.glyph.stemAnchorOffset(
                direction: noteHead.stemDirection,
                in: style.noteHeadSize
            )
            let stemX = noteHead.position.x + anchorOffset.x
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
                noteType: .bass,
                measureNumber: 1,
                measureOffset: Double(index) / 16.0
            )
        }
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour, style: style)
        )

        // Bass drum notes have catalog-authored down-stems; verify two beam levels exist.
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
            #expect(noteHead.stemDirection == .down)
            #expect(stem.direction == .down)
            let anchorOffset = noteHead.glyph.stemAnchorOffset(
                direction: noteHead.stemDirection,
                in: style.noteHeadSize
            )
            let stemX = noteHead.position.x + anchorOffset.x
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

    @Test("isolated thirty-second note produces three flags")
    func isolatedThirtySecondNoteProducesThreeFlags() throws {
        let note = Note(interval: .thirtysecond, noteType: .snare, measureNumber: 1, measureOffset: 0)
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: [note], timeSignature: .fourFour)
        )

        #expect(layout.beams.isEmpty, "Isolated 32nd note must not form a beam")
        #expect(layout.flags.count == 3, "Isolated 32nd should have 3 flags")
        let indices = Set(layout.flags.map(\.flagIndex))
        #expect(indices == [0, 1, 2])
        let stem = try #require(layout.stems.first)
        #expect(stem.direction == .up)
    }

    @Test("isolated sixty-fourth note produces four flags")
    func isolatedSixtyFourthNoteProducesFourFlags() throws {
        let note = Note(interval: .sixtyfourth, noteType: .snare, measureNumber: 1, measureOffset: 0)
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: [note], timeSignature: .fourFour)
        )

        #expect(layout.beams.isEmpty, "Isolated 64th note must not form a beam")
        #expect(layout.flags.count == 4, "Isolated 64th should have 4 flags")
        let indices = Set(layout.flags.map(\.flagIndex))
        #expect(indices == [0, 1, 2, 3])
        let stem = try #require(layout.stems.first)
        #expect(stem.direction == .up)
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

    @Test("down stem bass flag has down direction")
    func downStemBassFlagHasDownDirection() throws {
        let note = Note(interval: .eighth, noteType: .bass, measureNumber: 1, measureOffset: 0)
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
        let style = NotationLayoutStyle.gameplayDefault.with(rowWidth: 1_400)
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(
                notes: notes,
                timeSignature: .fourFour,
                minimumMeasureCount: 3,
                style: style
            )
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
        let style = NotationLayoutStyle.gameplayDefault.with(rowWidth: 1_400)
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(
                notes: notes,
                timeSignature: .fourFour,
                minimumMeasureCount: 3,
                style: style
            )
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

    @Test("sixteenth in mixed sixteenth-eighth beam run produces a hook")
    func sixteenthInMixedBeamRunProducesHook() throws {
        // sixteenth (flagCount=2) + eighth (flagCount=1) in the same beam run.
        // Level 0 covers both notes; the lone level-1 owner gets a forward hook.
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

        // The single eligible sixteenth owns a forward hook at level 1.
        let levelOneBeams = layout.beams.filter { $0.level == 1 }
        #expect(levelOneBeams.count == 1)
        #expect(levelOneBeams.first?.kind == .forwardHook)

        // Both notes are fully covered by beam topology.
        let sixteenthHead = try #require(layout.noteHeads.first { $0.interval == .sixteenth })
        let eighthHead = try #require(layout.noteHeads.first { $0.interval == .eighth })
        let sixteenthFlags = layout.flags.filter { $0.noteHeadID == sixteenthHead.id }
        let eighthFlags = layout.flags.filter { $0.noteHeadID == eighthHead.id }

        #expect(sixteenthFlags.isEmpty)
        #expect(eighthFlags.isEmpty)
    }

    @Test("thirty-second in mixed beam run produces hooks for higher levels")
    func thirtySecondInMixedBeamRunProducesHigherLevelHooks() throws {
        // thirty-second (flagCount=3) + eighth (flagCount=1).
        // Level 0 covers both; the lone owner gets hooks at levels 1 and 2.
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

        let higherLevelBeams = layout.beams.filter { $0.level > 0 }
        #expect(higherLevelBeams.count == 2)
        #expect(higherLevelBeams.allSatisfy { $0.kind == .forwardHook })
        #expect(higherLevelBeams.allSatisfy { $0.noteHeadIDs == [thirtySecondHead.id] })
        #expect(thirtySecondFlags.isEmpty)
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

extension NotationLayoutEngineTests {
    @Test("unsupported meter renders isolated flags without beams")
    func unsupportedMeterUsesConservativeFlags() {
        let notes = [
            Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: 0),
            Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: 0.125)
        ]
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .sixEight)
        )
        #expect(layout.beams.isEmpty)
        #expect(layout.flags.count == 2)
    }

    @Test("shuffled source notes preserve rendered beam IDs and order")
    func shuffledInputIsDeterministic() {
        let notes = (0..<8).map {
            Note(
                interval: .sixteenth,
                noteType: .snare,
                measureNumber: 1,
                measureOffset: Double($0) / 16.0
            )
        }
        let forward = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
        )
        let reversed = NotationLayoutEngine().layout(
            input: NotationLayoutInput(
                notes: Array(notes.reversed()),
                timeSignature: .fourFour
            )
        )
        #expect(forward.beams.map(\.id) == reversed.beams.map(\.id))
    }

    @Test("2/4 with imported 16-step grid uses meter sixteenth baseline, not 4/4's 16 columns")
    func twoFourImportedSixteenStepGridUsesMeterBaseline() throws {
        // A 2/4 chart encoded on a 16-step-per-measure imported grid resolves
        // to ticksPerMeasure = LCM(meter baseline 8, imported 16) = 16. The
        // display baseline must derive from the meter (8 sixteenths), not the
        // hard-coded 4/4 value (16), so a sparse chart spaces at 2-tick
        // sixteenths and renders 8 columns instead of 16.
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
                normalizedTicksPerMeasure: 16
            ),
            Note(
                interval: .quarter,
                noteType: .bass,
                measureNumber: 1,
                measureOffset: 0.5,
                originKind: .dtx,
                normalizedMeasureIndex: 0,
                normalizedAbsoluteTick: 8,
                normalizedTickWithinMeasure: 8,
                normalizedTicksPerMeasure: 16
            )
        ]
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .twoFour)
        )

        #expect(layout.tabGrid.ticksPerMeasure == 16)
        // meterBaselineTicksPerMeasure(.twoFour) = 2 * 16 / 4 = 8.
        let baselineGap = max(16 / NotationLayoutEngine.meterBaselineTicksPerMeasure(timeSignature: .twoFour), 1)
        #expect(baselineGap == 2)
        // spacingTickGap is capped at the meter baseline (2), so the measure
        // spans 8 sixteenth columns, not 16.
        let expectedColumns = layout.tabGrid.ticksPerMeasure / baselineGap
        #expect(expectedColumns == 8)
        // Every 2/4 beat (2 beats) maps to a distinct tick column at the
        // sixteenth baseline.
        let beatTicks = (0...2).map {
            layout.tabGrid.tickIndex(forBeatWithinMeasure: Double($0), beatsPerMeasure: 2)
        }
        #expect(beatTicks == [0, 8, 16])
    }
}
