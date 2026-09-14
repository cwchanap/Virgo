// swiftlint:disable file_length
import Testing
import SwiftUI
@testable import Virgo

/// Retained renderer/bounds behavior for the composed measured layout
/// (HPA-164 Task 6). Pure horizontal spacing contracts moved to the
/// DrumNotation package (`NotationFormatterSpacingTests`); the fixed-grid
/// fallback/tickWidth compatibility coverage was deleted with the grid.
@Suite("Notation Layout Engine Tests")
// swiftlint:disable:next type_body_length
struct NotationLayoutEngineTests {
    private let support = NotationSnapshotTestSupport()

    @Test("row-width copy preserves all HPA-143 metrics")
    func rowWidthCopyPreservesRestAndControlMetrics() {
        let style = NotationLayoutStyle.gameplayDefault
        let resized = style.with(rowWidth: 2_000)

        #expect(resized.restSymbolWidth == style.restSymbolWidth)
        #expect(resized.restSymbolHeight == style.restSymbolHeight)
        #expect(resized.fullMeasureRestWidth == style.fullMeasureRestWidth)
        #expect(resized.fullMeasureRestHeight == style.fullMeasureRestHeight)
        #expect(resized.upperVoiceRestOffset == style.upperVoiceRestOffset)
        #expect(resized.lowerVoiceRestOffset == style.lowerVoiceRestOffset)
        #expect(resized.stopMarkSize == style.stopMarkSize)
        #expect(resized.stopMarkStrokeWidth == style.stopMarkStrokeWidth)
        #expect(resized.stopMarkVerticalOffset == style.stopMarkVerticalOffset)
        #expect(resized.articulationDiameter == style.articulationDiameter)
        #expect(resized.articulationStrokeWidth == style.articulationStrokeWidth)
        #expect(resized.articulationVerticalOffset == style.articulationVerticalOffset)
    }

    @Test("content predicates distinguish playable and renderable primitives")
    func contentPredicatesDistinguishPlayableAndRenderablePrimitives() throws {
        let hiddenRest = makeRenderedRest(visibility: .hiddenSpacing)
        let printedRest = makeRenderedRest(visibility: .printed)
        let stop = makeRenderedStopNote()
        let articulation = makeRenderedArticulation()
        let renderedHead = try #require(
            support.prepare(notes: [
                Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0)
            ]).layout.noteHeads.first
        )

        var hiddenOnly = NotationLayout.empty
        hiddenOnly.rests = [hiddenRest]
        var noteheadOnly = NotationLayout.empty
        noteheadOnly.noteHeads = [renderedHead]
        var printedRestOnly = NotationLayout.empty
        printedRestOnly.rests = [printedRest]
        var stopOnly = NotationLayout.empty
        stopOnly.stopNotes = [stop]
        var articulationOnly = NotationLayout.empty
        articulationOnly.articulations = [articulation]

        #expect(!NotationLayout.empty.hasPlayableContent)
        #expect(!NotationLayout.empty.hasRenderableContent)
        #expect(!hiddenOnly.hasPlayableContent)
        #expect(!hiddenOnly.hasRenderableContent)
        #expect(noteheadOnly.hasPlayableContent)
        #expect(noteheadOnly.hasRenderableContent)
        #expect(!printedRestOnly.hasPlayableContent)
        #expect(printedRestOnly.hasRenderableContent)
        #expect(!stopOnly.hasPlayableContent)
        #expect(stopOnly.hasRenderableContent)
        #expect(!articulationOnly.hasPlayableContent)
        #expect(!articulationOnly.hasRenderableContent)
    }

    @Test("render contracts expose semantic accessibility labels")
    func renderContractsExposeSemanticAccessibilityLabels() throws {
        let upperQuarterRest = makeRenderedRest(
            voice: .upper,
            duration: .quarter,
            visibility: .printed
        )
        let lowerFullMeasureRest = makeRenderedRest(
            voice: .lower,
            duration: .fullMeasure,
            visibility: .printed
        )
        let layout = support.prepare(notes: [
            Note(interval: .quarter, noteType: .hiHat, measureNumber: 1, measureOffset: 0),
            Note(interval: .quarter, noteType: .openHiHat, measureNumber: 1, measureOffset: 0.25),
            Note(interval: .quarter, noteType: .hiHatPedal, measureNumber: 1, measureOffset: 0.5)
        ]).layout
        let closedHiHat = try #require(layout.noteHeads.first { $0.variant == .closedHiHat })
        let openHiHat = try #require(layout.noteHeads.first { $0.variant == .openHiHat })
        let pedalHiHat = try #require(layout.noteHeads.first { $0.variant == .pedalHiHat })

        #expect(upperQuarterRest.accessibilityLabel == "Upper voice quarter rest")
        #expect(lowerFullMeasureRest.accessibilityLabel == "Lower voice full-measure rest")
        #expect(makeRenderedStopNote().accessibilityLabel == "Choke Crash")
        #expect(closedHiHat.accessibilityLabel == "Closed hi-hat")
        #expect(openHiHat.accessibilityLabel == "Open hi-hat")
        #expect(pedalHiHat.accessibilityLabel == "Pedal hi-hat")
    }

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

    @Test("layout exposes note head positions by note head ID")
    func notationLayoutExposesNoteHeadPositionsByNoteHeadID() {
        let labels = Set(Mirror(reflecting: NotationLayout.empty).children.compactMap(\.label))

        #expect(labels.contains("noteHeadPositionsByID"))
        #expect(!labels.contains("beatLookup"))
    }

    @Test("renderable measures reuse the shared rhythm limit")
    func renderableMeasuresReuseRhythmLimit() {
        #expect(NotationLayoutEngine.maximumRenderableMeasureCount == RhythmLimits.maximumMeasureCount)
    }

    @Test("drum types map to gameplay voices")
    func drumTypesMapToGameplayVoices() {
        #expect(NotationVoice.voice(for: .kick) == .lower)
        #expect(NotationVoice.voice(for: .hiHatPedal) == .lower)
        #expect(NotationVoice.voice(for: .snare) == .upper)
        #expect(NotationVoice.voice(for: .crash) == .upper)
    }

    @Test("minimum measure count preserves trailing empty measures")
    func minimumMeasureCountPreservesTrailingEmptyMeasures() {
        let layout = support.prepare(
            notes: [Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0)],
            minimumMeasureCount: 4
        ).layout

        #expect(layout.measures.map(\.measureIndex) == [0, 1, 2, 3])
        #expect(layout.measureBars.contains { $0.id == "bar_3_end" && $0.isFinal })
    }

    @Test("same-time kick snare and hi-hat share the exact column")
    func sameTimeKickSnareAndHiHatShareExactColumn() throws {
        let layout = support.prepare(notes: [
            Note(interval: .quarter, noteType: .bass, measureNumber: 1, measureOffset: 0.25),
            Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0.25),
            Note(interval: .quarter, noteType: .hiHat, measureNumber: 1, measureOffset: 0.25)
        ]).layout
        let heads = layout.noteHeads
        let firstHead = try #require(heads.first)

        #expect(heads.count == 3)
        #expect(heads.allSatisfy { $0.timeColumn == firstHead.timeColumn })
        #expect(Set(heads.map(\.position.x)).count == 1)
    }

    @Test("simultaneous quarter pairs produce four time columns")
    func simultaneousQuarterPairsProduceFourTimeColumns() {
        let notes = (0..<4).flatMap { index in
            [
                Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: Double(index) / 4),
                Note(interval: .quarter, noteType: .bass, measureNumber: 1, measureOffset: Double(index) / 4)
            ]
        }
        let layout = support.prepare(notes: notes).layout

        #expect(layout.noteHeads.count == 8)
        #expect(Set(layout.noteHeads.map(\.timeColumn)).count == 4)
        #expect(Set(layout.noteHeads.map(\.position.x)).count == 4)
    }

    @Test("above staff crash emits ledger line")
    func aboveStaffCrashEmitsLedgerLine() {
        let layout = support.prepare(notes: [
            Note(interval: .quarter, noteType: .crash, measureNumber: 1, measureOffset: 0)
        ]).layout

        #expect(layout.ledgerLines.count >= 1)
        #expect(layout.ledgerLines.allSatisfy { $0.end.x > $0.start.x })
    }

    @Test("below staff kick emits ledger lines")
    func belowStaffKickEmitsLedgerLines() {
        let layout = support.prepare(notes: [
            Note(interval: .quarter, noteType: .bass, measureNumber: 1, measureOffset: 0)
        ]).layout

        #expect(layout.ledgerLines.count >= 1)
        #expect(layout.ledgerLines.allSatisfy { $0.end.x > $0.start.x })
    }

    @Test("rendered head preserves stable rendered and notation identity")
    func renderedHeadPreservesStableRenderedAndNotationIdentity() throws {
        let layout = support.prepare(notes: [
            Note(
                interval: .quarter,
                noteType: .openHiHat,
                measureNumber: 1,
                measureOffset: 0,
                originKind: .dtx,
                sourceLaneID: "18",
                sourceNoteID: "A1"
            )
        ]).layout
        let head = try #require(layout.noteHeads.first)

        #expect(head.sourceLaneID == "18")
        #expect(head.sourceChipID == "A1")
        #expect(head.noteType == .openHiHat)
        #expect(head.drumType == .hiHat)
        #expect(VirgoNotationAdapter.noteheadStyle(for: head.noteType) == .x)
        #expect(head.variant == .openHiHat)
        #expect(head.voice == .upper)
        #expect(head.stemDirection == .up)
    }

    @Test("unknown lane fallback preserves raw rendered identity")
    func unknownLaneFallbackPreservesRawRenderedIdentity() throws {
        let layout = support.prepare(notes: [
            Note(
                interval: .quarter,
                noteType: .ride,
                measureNumber: 1,
                measureOffset: 0,
                originKind: .dtx,
                sourceLaneID: "AA",
                sourceNoteID: "7F"
            )
        ]).layout
        let head = try #require(layout.noteHeads.first)

        #expect(head.sourceLaneID == "AA")
        #expect(head.sourceChipID == "7F")
        #expect(head.noteType == .ride)
        #expect(head.drumType == .ride)
        #expect(head.variant == .ride)
    }

    @Test("identical heads retain distinct identities and lookup entries")
    func identicalHeadsRetainDistinctIdentitiesAndLookupEntries() {
        let layout = support.prepare(notes: [
            Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0),
            Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0)
        ]).layout
        let heads = layout.noteHeads
        let renderedIDs = Set(heads.map(\.id))
        let tickKey = 0

        #expect(heads.count == 2)
        #expect(renderedIDs.count == 2)
        #expect(layout.noteHeadPositionsByID.count == 2)
        #expect(layout.noteHeadIDsByLayoutTick[tickKey] == renderedIDs)
    }

    @Test("ledger width follows authored glyph bounds")
    func ledgerWidthFollowsAuthoredGlyphBounds() throws {
        let style = NotationLayoutStyle.gameplayDefault
        let layout = support.prepare(
            notes: [Note(interval: .quarter, noteType: .crash, measureNumber: 1, measureOffset: 0)],
            style: style
        ).layout
        let head = try #require(layout.noteHeads.first)
        let ledger = try #require(layout.ledgerLines.first)
        let headBounds = VirgoNotationAdapter.noteheadMetrics(for: head, style: style).paintedBounds
            .offsetBy(dx: head.position.x, dy: head.position.y)

        #expect(ledger.start.x == headBounds.minX - style.ledgerLineOverhang)
        #expect(ledger.end.x == headBounds.maxX + style.ledgerLineOverhang)
    }

    @Test("same voice simultaneous notes do not split")
    func sameVoiceSimultaneousNotesDoNotSplit() throws {
        let layout = support.prepare(notes: [
            Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0.5),
            Note(interval: .quarter, noteType: .crash, measureNumber: 1, measureOffset: 0.5)
        ]).layout
        let snare = try #require(layout.noteHeads.first { $0.drumType == .snare })
        let crash = try #require(layout.noteHeads.first { $0.drumType == .crash })

        #expect(snare.voice == .upper)
        #expect(crash.voice == .upper)
        #expect(abs(snare.position.x - crash.position.x) < 0.001)
    }

    @Test("crash stem uses catalog up direction")
    func crashStemUsesCatalogUpDirection() throws {
        let style = NotationLayoutStyle.gameplayDefault
        let layout = support.prepare(
            notes: [Note(interval: .quarter, noteType: .crash, measureNumber: 1, measureOffset: 0)],
            style: style
        ).layout
        let crash = try #require(layout.noteHeads.first { $0.drumType == .crash })
        let stem = try #require(layout.stems.first)
        let anchorOffset = VirgoNotationAdapter.noteheadMetrics(for: crash, style: style).stemAnchorOffset
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
        let layout = support.prepare(
            notes: [Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0)],
            style: style
        ).layout
        let snare = try #require(layout.noteHeads.first { $0.drumType == .snare })
        let stem = try #require(layout.stems.first)
        let anchorOffset = VirgoNotationAdapter.noteheadMetrics(for: snare, style: style).stemAnchorOffset
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
            Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: Double(index) / 4.0)
        }
        let layout = support.prepare(notes: notes).layout

        #expect(layout.stems.count == 4)
        #expect(layout.beams.isEmpty)
    }

    @Test("full and half notes do not create stems")
    func fullAndHalfNotesDoNotCreateStems() {
        let layout = support.prepare(notes: [
            Note(interval: .full, noteType: .snare, measureNumber: 1, measureOffset: 0),
            Note(interval: .half, noteType: .snare, measureNumber: 1, measureOffset: 0.5)
        ]).layout

        #expect(layout.stems.isEmpty)
        #expect(layout.beams.isEmpty)
    }

    @Test("consecutive sixteenths create two beam levels")
    func consecutiveSixteenthsCreateTwoBeamLevels() throws {
        let style = NotationLayoutStyle.gameplayDefault
        let notes = (0..<4).map { index in
            Note(interval: .sixteenth, noteType: .snare, measureNumber: 1, measureOffset: Double(index) / 16.0)
        }
        let layout = support.prepare(notes: notes, style: style).layout
        let sortedHeads = layout.noteHeads.sorted { $0.timePosition < $1.timePosition }
        let firstHead = try #require(sortedHeads.first)
        let lastHead = try #require(sortedHeads.last)
        let firstAnchorOffset = VirgoNotationAdapter.noteheadMetrics(for: firstHead, style: style).stemAnchorOffset
        let lastAnchorOffset = VirgoNotationAdapter.noteheadMetrics(for: lastHead, style: style).stemAnchorOffset
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
            Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: Double(index) / 8.0)
        }
        let layout = support.prepare(notes: notes, style: style).layout
        let beam = try #require(layout.beams.first)
        let sortedHeads = layout.noteHeads.sorted { $0.timePosition < $1.timePosition }
        let firstHead = try #require(sortedHeads.first)
        let lastHead = try #require(sortedHeads.last)
        let firstAnchorOffset = VirgoNotationAdapter.noteheadMetrics(for: firstHead, style: style).stemAnchorOffset
        let lastAnchorOffset = VirgoNotationAdapter.noteheadMetrics(for: lastHead, style: style).stemAnchorOffset

        #expect(layout.beams.count == 1)
        #expect(beam.level == 0)
        #expect(beam.noteHeadIDs.count == 2)
        #expect(beam.start.x == firstHead.position.x + firstAnchorOffset.x)
        #expect(beam.end.x == lastHead.position.x + lastAnchorOffset.x)
    }

    @Test("beams do not cross measure boundaries")
    func beamsDoNotCrossMeasureBoundaries() {
        let layout = support.prepare(notes: [
            Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: 0.875),
            Note(interval: .eighth, noteType: .snare, measureNumber: 2, measureOffset: 0)
        ]).layout

        #expect(layout.stems.count == 2)
        #expect(layout.beams.isEmpty)
    }

    @Test("isolated eighth does not create beam")
    func isolatedEighthDoesNotCreateBeam() {
        let layout = support.prepare(notes: [
            Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: 0)
        ]).layout

        #expect(layout.stems.count == 1)
        #expect(layout.beams.isEmpty)
    }

    @Test("cross voice notes do not beam together")
    func crossVoiceNotesDoNotBeamTogether() {
        let layout = support.prepare(notes: [
            Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: 0),
            Note(interval: .eighth, noteType: .bass, measureNumber: 1, measureOffset: 0.125)
        ]).layout

        #expect(layout.stems.count == 2)
        #expect(layout.beams.isEmpty)
    }

    @Test("non-beamable note between eighths breaks beam run")
    func nonBeamableNoteBetweenEighthsBreaksBeamRun() {
        let layout = support.prepare(notes: [
            Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: 0),
            Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0.125),
            Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: 0.25)
        ]).layout

        #expect(layout.stems.count == 3)
        #expect(layout.beams.isEmpty)
    }

    @Test("higher beam level uses hooks around intervening lower duration note")
    func higherBeamLevelUsesHooksAroundInterveningLowerDurationNote() {
        let layout = support.prepare(notes: [
            Note(interval: .sixteenth, noteType: .snare, measureNumber: 1, measureOffset: 0),
            Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: 0.0625),
            Note(interval: .sixteenth, noteType: .snare, measureNumber: 1, measureOffset: 0.1875)
        ]).layout
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
        let layout = support.prepare(notes: [
            Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: 0),
            Note(interval: .eighth, noteType: .highTom, measureNumber: 1, measureOffset: 0)
        ]).layout

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
        let layout = support.prepare(notes: [
            Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0),
            Note(interval: .quarter, noteType: .highTom, measureNumber: 1, measureOffset: 0)
        ]).layout

        #expect(layout.stems.count == 1, "Chord notes at the same position should share one stem")
        let stem = try #require(layout.stems.first)
        #expect(stem.noteHeadIDs.count == 2, "Shared stem should reference both note head IDs")
        #expect(stem.direction == .up)
    }

    @Test("same-type simultaneous hits share a single stem")
    func sameTypeSimultaneousHitsShareSingleStem() throws {
        // Two crash cymbal hits at the same time should share one stem.
        // Same drum type → same voice → same stem direction → one stem.
        let layout = support.prepare(notes: [
            Note(interval: .quarter, noteType: .crash, measureNumber: 1, measureOffset: 0),
            Note(interval: .quarter, noteType: .crash, measureNumber: 1, measureOffset: 0)
        ]).layout

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
        let layout = support.prepare(
            notes: [
                Note(interval: .quarter, noteType: .crash, measureNumber: 1, measureOffset: 0),
                Note(interval: .quarter, noteType: .highTom, measureNumber: 1, measureOffset: 0)
            ],
            notePositionOverrides: [.crash: .line4, .tom1: .line2]
        ).layout

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
        let layout = support.prepare(notes: [
            Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0),
            Note(interval: .quarter, noteType: .bass, measureNumber: 1, measureOffset: 0)
        ]).layout

        #expect(layout.stems.count == 2, "Different-voice notes should get separate stems")
        let stemMemberships = layout.stems.map { Set($0.noteHeadIDs) }
        #expect(stemMemberships.count == 2)
        #expect(stemMemberships[0].isDisjoint(with: stemMemberships[1]))
    }

    @Test("down stem beams align to down stem x coordinates")
    func downStemBeamsAlignToDownStemXCoordinates() throws {
        let style = NotationLayoutStyle.gameplayDefault
        let layout = support.prepare(
            notes: [
                Note(interval: .eighth, noteType: .bass, measureNumber: 1, measureOffset: 0),
                Note(interval: .eighth, noteType: .bass, measureNumber: 1, measureOffset: 0.125)
            ],
            style: style
        ).layout
        let sortedHeads = layout.noteHeads.sorted { $0.timePosition < $1.timePosition }
        let firstHead = try #require(sortedHeads.first)
        let lastHead = try #require(sortedHeads.last)
        let beam = try #require(layout.beams.first)
        let firstAnchorOffset = VirgoNotationAdapter.noteheadMetrics(for: firstHead, style: style).stemAnchorOffset
        let lastAnchorOffset = VirgoNotationAdapter.noteheadMetrics(for: lastHead, style: style).stemAnchorOffset

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
            Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: Double(index) / 8.0)
        }
        let layout = support.prepare(notes: notes, style: style).layout
        let beam = try #require(layout.beams.first { $0.level == 0 })

        // Every note head in the beam must have a stem whose end Y matches the beam Y at that stem x.
        for noteHeadID in beam.noteHeadIDs {
            let noteHead = try #require(layout.noteHeads.first { $0.id == noteHeadID })
            let stem = try #require(layout.stems.first { $0.noteHeadIDs.contains(noteHeadID) })
            let anchorOffset = VirgoNotationAdapter.noteheadMetrics(for: noteHead, style: style).stemAnchorOffset
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
            Note(interval: .eighth, noteType: .bass, measureNumber: 1, measureOffset: Double(index) / 8.0)
        }
        let layout = support.prepare(notes: notes, style: style).layout
        let beam = try #require(layout.beams.first { $0.level == 0 })
        #expect(beam.direction == .down)

        for noteHeadID in beam.noteHeadIDs {
            let noteHead = try #require(layout.noteHeads.first { $0.id == noteHeadID })
            let stem = try #require(layout.stems.first { $0.noteHeadIDs.contains(noteHeadID) })
            #expect(noteHead.stemDirection == .down)
            #expect(stem.direction == .down)
            let anchorOffset = VirgoNotationAdapter.noteheadMetrics(for: noteHead, style: style).stemAnchorOffset
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
            Note(interval: .sixteenth, noteType: .snare, measureNumber: 1, measureOffset: Double(index) / 16.0)
        }
        let layout = support.prepare(notes: notes, style: style).layout

        // Find the outermost beam (highest level = furthest from note heads for up-stems)
        let outermostBeam = try #require(layout.beams.max { $0.level < $1.level })

        // Every stem must reach the outermost beam at its stem x position
        for noteHeadID in outermostBeam.noteHeadIDs {
            let noteHead = try #require(layout.noteHeads.first { $0.id == noteHeadID })
            let stem = try #require(layout.stems.first { $0.noteHeadIDs.contains(noteHeadID) })
            let anchorOffset = VirgoNotationAdapter.noteheadMetrics(for: noteHead, style: style).stemAnchorOffset
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
            Note(interval: .sixteenth, noteType: .bass, measureNumber: 1, measureOffset: Double(index) / 16.0)
        }
        let layout = support.prepare(notes: notes, style: style).layout

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
            let anchorOffset = VirgoNotationAdapter.noteheadMetrics(for: noteHead, style: style).stemAnchorOffset
            let stemX = noteHead.position.x + anchorOffset.x
            let t = (stemX - outermostBeam.start.x) / (outermostBeam.end.x - outermostBeam.start.x)
            let expectedY = outermostBeam.start.y + t * (outermostBeam.end.y - outermostBeam.start.y)
            #expect(abs(stem.end.y - expectedY) < 0.5)
        }
    }

    // MARK: - Flag Rendering Tests

    @Test("isolated eighth note produces one flag")
    func isolatedEighthNoteProducesOneFlag() throws {
        let layout = support.prepare(notes: [
            Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: 0)
        ]).layout

        #expect(layout.flags.count == 1)
        let flag = try #require(layout.flags.first)
        #expect(flag.flagIndex == 0)
        #expect(flag.stemDirection == .up)
        #expect(flag.noteHeadID == layout.noteHeads.first?.id)
    }

    @Test("isolated sixteenth note produces two flags")
    func isolatedSixteenthNoteProducesTwoFlags() throws {
        let layout = support.prepare(notes: [
            Note(interval: .sixteenth, noteType: .snare, measureNumber: 1, measureOffset: 0)
        ]).layout

        #expect(layout.flags.count == 2)
        let indices = Set(layout.flags.map(\.flagIndex))
        #expect(indices == [0, 1])
    }

    @Test("isolated thirty-second note produces three flags")
    func isolatedThirtySecondNoteProducesThreeFlags() throws {
        let layout = support.prepare(notes: [
            Note(interval: .thirtysecond, noteType: .snare, measureNumber: 1, measureOffset: 0)
        ]).layout

        #expect(layout.beams.isEmpty, "Isolated 32nd note must not form a beam")
        #expect(layout.flags.count == 3, "Isolated 32nd should have 3 flags")
        let indices = Set(layout.flags.map(\.flagIndex))
        #expect(indices == [0, 1, 2])
        let stem = try #require(layout.stems.first)
        #expect(stem.direction == .up)
    }

    @Test("isolated sixty-fourth note produces four flags")
    func isolatedSixtyFourthNoteProducesFourFlags() throws {
        let layout = support.prepare(notes: [
            Note(interval: .sixtyfourth, noteType: .snare, measureNumber: 1, measureOffset: 0)
        ]).layout

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
            Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: Double(index) / 8.0)
        }
        let layout = support.prepare(notes: notes).layout

        #expect(layout.beams.count == 1)
        #expect(layout.flags.isEmpty)
    }

    @Test("quarter notes produce no flags")
    func quarterNotesProduceNoFlags() {
        let layout = support.prepare(notes: [
            Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0)
        ]).layout

        #expect(layout.flags.isEmpty)
    }

    @Test("mixed beamed and isolated notes produce flags only for isolated")
    func mixedBeamedAndIsolatedNotesProduceFlagsOnlyForIsolated() throws {
        let layout = support.prepare(notes: [
            Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: 0),
            Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: 0.125),
            Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: 0.5)
        ]).layout

        // First two eighths are beamed, last one is isolated
        #expect(layout.beams.count == 1)
        #expect(layout.flags.count == 1)
        let isolatedHead = try #require(layout.noteHeads.first { $0.timePosition == 480 })
        let flag = try #require(layout.flags.first)
        #expect(flag.noteHeadID == isolatedHead.id)
    }

    @Test("down stem bass flag has down direction")
    func downStemBassFlagHasDownDirection() throws {
        let layout = support.prepare(notes: [
            Note(interval: .eighth, noteType: .bass, measureNumber: 1, measureOffset: 0)
        ]).layout

        let flag = try #require(layout.flags.first)
        #expect(flag.stemDirection == .down)
    }

    // MARK: - Barline Deduplication Tests

    @Test("adjacent measures on same row share single barline")
    func adjacentMeasuresOnSameRowShareSingleBarline() throws {
        let notes = (0..<8).map { index in
            Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: Double(index % 4) / 4.0)
        }
        let style = NotationLayoutStyle.gameplayDefault.with(rowWidth: 1_400)
        let layout = support.prepare(
            notes: notes,
            minimumMeasureCount: 3,
            style: style
        ).layout

        let sameRowMeasures = layout.measures.filter { $0.row == 0 }
        guard sameRowMeasures.count >= 2 else {
            Issue.record("Expected at least 2 measures on row 0")
            return
        }

        // Internal boundaries should have exactly one barline, not two
        let row0Bars = layout.measureBars.filter { $0.row == 0 }
        let barXPositions = Set(row0Bars.map(\.x))

        // For N measures on a row, we expect: 1 start bar + N end bars = N+1 bars
        // NOT 2*N bars (start + end for each)
        let expectedBarCount = sameRowMeasures.count + 1
        #expect(row0Bars.count == expectedBarCount)
        #expect(barXPositions.count == row0Bars.count)
    }

    @Test("final measure barline is marked isFinal")
    func finalMeasureBarlineIsMarkedFinal() {
        let layout = support.prepare(
            notes: [Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0)],
            minimumMeasureCount: 2
        ).layout

        let finalBars = layout.measureBars.filter(\.isFinal)
        #expect(finalBars.count == 1)
        #expect(finalBars.first?.isFinal == true)
    }

    @Test("internal barline sits at the package measure boundary")
    func internalBarlineSitsAtPackageMeasureBoundary() throws {
        let notes = (0..<8).map { index in
            Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: Double(index % 4) / 4.0)
        }
        let style = NotationLayoutStyle.gameplayDefault.with(rowWidth: 1_400)
        let layout = support.prepare(
            notes: notes,
            minimumMeasureCount: 3,
            style: style
        ).layout

        let sameRowMeasures = layout.measures.filter { $0.row == 0 }
        let sameRowBars = layout.measureBars.filter { $0.row == 0 }
        guard sameRowMeasures.count >= 2 else {
            Issue.record("Expected at least 2 measures on row 0")
            return
        }

        // Every measure's end barline sits on its own package measure
        // boundary (xOffset + width) — including internal same-row measures.
        // The row continues after the measureSpacing gap, so anchoring the
        // bar on the next measure's xOffset would draw it one gap too far
        // right, outside the measure it closes.
        for current in sameRowMeasures {
            let endBar = try #require(
                sameRowBars.first { $0.id == "bar_\(current.measureIndex)_end" }
            )
            #expect(abs(endBar.x - (current.xOffset + current.width)) < 0.001)
        }
    }

    @Test("measure wrapping to new row gets separate start barline")
    func measureWrappingToNewRowGetsSeparateStartBarline() {
        // Create enough notes/measures to force a row wrap
        let notes = (0..<4).map { index in
            Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: Double(index) / 4.0)
        }
        let layout = support.prepare(notes: notes, minimumMeasureCount: 20).layout

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
        let layout = support.prepare(notes: [
            Note(interval: .sixteenth, noteType: .snare, measureNumber: 1, measureOffset: 0),
            Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: 0.0625)
        ]).layout

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
        let layout = support.prepare(notes: [
            Note(interval: .thirtysecond, noteType: .snare, measureNumber: 1, measureOffset: 0),
            Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: 0.03125)
        ]).layout

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
            Note(interval: .sixteenth, noteType: .snare, measureNumber: 1, measureOffset: Double(index) / 16.0)
        }
        let layout = support.prepare(notes: notes).layout

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
        let layout = support.prepare(notes: notes).layout
        let lastNoteHead = try #require(layout.noteHeads.max(by: { $0.position.x < $1.position.x }))
        #expect(layout.contentWidth > lastNoteHead.position.x)
        // Width expands to accommodate dense notes - at minimum equals max row width.
        #expect(layout.contentWidth >= GameplayLayout.maxRowWidth)
    }

    // MARK: - Top Content Inset

    @Test("topContentInset is zero without articulations or stop notes")
    func topContentInsetIsZeroWithoutOverlays() {
        let layout = support.prepare(notes: [
            Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0)
        ]).layout
        #expect(layout.topContentInset(style: .gameplayDefault) == 0)
    }

    @Test("topContentInset contains the highest open-hi-hat overlay inside the sheet origin")
    func topContentInsetContainsHighestOpenHiHatOverlay() throws {
        let style = NotationLayoutStyle.gameplayDefault
        let layout = support.prepare(
            notes: [Note(interval: .quarter, noteType: .openHiHat, measureNumber: 1, measureOffset: 0)],
            style: style,
            notePositionOverrides: [.hiHat: .aboveLine9]
        ).layout
        let articulation = try #require(layout.articulations.first)
        let paintedTopEdge = articulation.position.y
            - style.articulationDiameter / 2
            - style.articulationStrokeWidth / 2
        let inset = layout.topContentInset(style: style)

        // The overlay exceeds the sheet origin on its own (paintedTopEdge < 0).
        #expect(paintedTopEdge < 0)
        // topContentInset is positive to compensate.
        #expect(inset > 0)
        // After applying the inset, the painted top edge stays within the sheet origin.
        #expect(paintedTopEdge + inset >= 0)
    }

    @Test("notes in different rows get separate stems even at same x position")
    func notesInDifferentRowsGetSeparateStems() throws {
        let layout = support.prepare(
            notes: [
                Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0),
                Note(interval: .quarter, noteType: .snare, measureNumber: 4, measureOffset: 0)
            ],
            minimumMeasureCount: 5
        ).layout
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

    @Test("shuffled source notes preserve rendered beam IDs and order")
    func shuffledInputIsDeterministic() {
        let notes = (0..<8).map {
            Note(interval: .sixteenth, noteType: .snare, measureNumber: 1, measureOffset: Double($0) / 16.0)
        }
        let forward = support.prepare(notes: notes).layout
        let reversed = support.prepare(notes: Array(notes.reversed())).layout
        #expect(forward.beams.map(\.id) == reversed.beams.map(\.id))
    }

    @Test("3/4 adjacent eighth-note pair forms a beam, not isolated flags")
    func threeFourAdjacentEighthsFormBeam() {
        // 3/4 has 6 eighths per measure; offsets 0 and 1/6 are adjacent
        // eighths spanning 120 ticks on the canonical whole-note grid
        // (one beat = 240 ticks, an eighth = 120). The subdivision duration
        // must scale from the whole note, not the measure, or the run is
        // rejected and the notes render as isolated flags.
        let layout = NotationSnapshotTestSupport(timeSignature: .threeFour).prepare(notes: [
            Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: 0),
            Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: 1.0 / 6.0)
        ]).layout

        #expect(!layout.beams.isEmpty, "3/4 adjacent eighths should form a beam")
        #expect(layout.flags.isEmpty, "3/4 adjacent eighths should not render isolated flags")
    }

    private func makeRenderedRest(
        voice: NotationVoice = .upper,
        duration: NotationRestDuration = .quarter,
        visibility: NotationRestVisibility
    ) -> RenderedRest {
        RenderedRest(
            id: "rest-0-upper-quarter",
            timeColumn: NotationTimeColumn(
                measureIndex: 0,
                tickWithinMeasure: 0,
                absoluteLayoutTick: 0
            ),
            measureIndex: 0,
            row: 0,
            voice: voice,
            durationTicks: 240,
            duration: duration,
            visibility: visibility,
            position: .zero
        )
    }

    private func makeRenderedStopNote() -> RenderedStopNote {
        RenderedStopNote(
            id: "control-0-choke-1A",
            kind: .choke,
            sourceLaneID: "2A",
            sourceNoteID: "01",
            targetLaneID: "1A",
            targetDisplayName: "Crash",
            timeColumn: NotationTimeColumn(
                measureIndex: 0,
                tickWithinMeasure: 0,
                absoluteLayoutTick: 0
            ),
            row: 0,
            position: .zero
        )
    }

    private func makeRenderedArticulation() -> RenderedArticulation {
        RenderedArticulation(
            id: "articulation-1-open-hi-hat",
            kind: .openHiHat,
            sourceNoteHeadID: 1,
            row: 0,
            position: .zero
        )
    }
}
