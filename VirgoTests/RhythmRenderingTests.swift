import CoreGraphics
import Testing
import DrumNotation
@testable import Virgo

@Suite("Rhythm Rendering Tests")
struct RhythmRenderingTests {
    /// The one preparation route (HPA-166 Task 7): every engraving in this
    /// suite comes from `GameplayNotationPreparer.prepare`, which ends in the
    /// package `NotationEngraver`. `.ready` carries the `EngravedNotation`
    /// plus the app-owned presentation (feel/warning annotations + VoiceOver
    /// labels); `.failed` fails the test.
    private func preparedEngraving(
        _ snapshot: RhythmLayoutSnapshot,
        minimumMeasureCount: Int = 1
    ) throws -> (engraved: EngravedNotation, presentation: GameplayNotationPresentation) {
        let prepared = GameplayNotationPreparer.prepare(GameplayNotationPreparationRequest(
            snapshot: snapshot,
            minimumMeasureCount: minimumMeasureCount,
            style: .gameplayDefault,
            notePositionOverrides: [:]
        ))
        guard case let .ready(engraved, presentation) = prepared else {
            Issue.record("Expected .ready, got \(prepared)")
            throw PreparationNotReady()
        }
        return (engraved, presentation)
    }

    private struct PreparationNotReady: Error {}

    @Test("dotted notes and rests retain exact timeline x positions")
    func dottedPrimitivesRetainTimelinePositions() throws {
        let measure = rhythmMeasure()
        let note = layoutNote(
            id: 11,
            tick: 120,
            noteType: .snare,
            rhythm: NotationRhythm(baseInterval: .eighth, dotCount: 1)
        )
        let rest = RhythmLayoutRest(
            position: position(tick: 360),
            durationTicks: 180,
            voice: .upper,
            rhythm: NotationRhythm(baseInterval: .eighth, dotCount: 1),
            visibility: .printed,
            tupletID: nil
        )

        let (engraved, _) = try preparedEngraving(
            try snapshot(measures: [measure], notes: [note], rests: [rest])
        )
        let head = try #require(engraved.noteHeads.first)
        let renderedRest = try #require(engraved.rests.first)
        let noteDot = try #require(
            engraved.rhythmDots.first { $0.source == .note(note.eventID.rawValue) }
        )
        let restDot = try #require(
            engraved.rhythmDots.first { $0.source == .rest(renderedRest.restID) }
        )

        // The live playhead lookup shares the logical column X with the
        // undisplaced head.
        let onset = try #require(engraved.formatted.position(measureIndex: 0, localTick: 120))
        #expect(head.position.x == onset.x)
        let restColumn = try #require(
            engraved.formatted.measures
                .first { $0.index == 0 }?
                .columns
                .first { $0.localTick == 360 }
        )
        #expect(renderedRest.position.x == restColumn.rests.first?.visualX)
        #expect(noteDot.position.x > head.paintedBounds.maxX)
        #expect(restDot.position.x > renderedRest.paintedBounds.maxX)
        #expect(engraved.paintedBounds.contains(noteDot.paintedBounds))
        #expect(engraved.paintedBounds.contains(restDot.paintedBounds))
    }

    @Test("triplets use beam geometry when beamed and brackets otherwise in both voices")
    func tupletGeometryUsesVoiceAndBeaming() throws {
        let beamedID = tupletID(voice: .upper, durationTicks: 240, stableID: 21)
        let beamedNotes = [0, 80, 160].enumerated().map { index, tick in
            layoutNote(
                id: 21 + index,
                tick: tick,
                noteType: .snare,
                rhythm: tripletRhythm(base: .eighth),
                tupletID: beamedID,
                durationTicks: 80
            )
        }
        let (beamed, _) = try preparedEngraving(
            try snapshot(measures: [rhythmMeasure()], notes: beamedNotes)
        )
        let beamedTuplet = try #require(beamed.tuplets.first)

        // Engraved tuplets carry package-local IDs; member notes cite their
        // event IDs verbatim.
        #expect(beamedTuplet.memberNoteIDs == beamedNotes.map { $0.eventID.rawValue })
        #expect(beamedTuplet.voice == .upper)
        #expect(!beamedTuplet.isBracketVisible)
        #expect(beamedTuplet.bracketPoints.isEmpty)
        #expect(beamedTuplet.labelPosition.y < beamed.beams.map(\.start.y).min() ?? .infinity)

        let bracketedID = tupletID(voice: .lower, durationTicks: 480, stableID: 31)
        let bracketedNotes = [0, 160, 320].enumerated().map { index, tick in
            layoutNote(
                id: 31 + index,
                tick: tick,
                noteType: .bass,
                rhythm: tripletRhythm(base: .quarter),
                tupletID: bracketedID,
                durationTicks: 160
            )
        }
        let (bracketed, _) = try preparedEngraving(try snapshot(
                measures: [rhythmMeasure(groupDurationTicks: 480)],
                notes: bracketedNotes
            ))
        let bracketedTuplet = try #require(bracketed.tuplets.first)

        #expect(bracketedTuplet.voice == .lower)
        #expect(bracketedTuplet.isBracketVisible)
        #expect(bracketedTuplet.bracketPoints.count == 6)
        #expect(bracketedTuplet.labelPosition.y > bracketed.noteHeads.map(\.position.y).max() ?? 0)
    }

    @Test("partially beamed tuplets keep brackets around note-note-rest in both stem directions")
    func partiallyBeamedTupletsKeepBrackets() throws {
        let upperID = tupletID(voice: .upper, durationTicks: 240, stableID: 25)
        let upperNotes = [0, 80].enumerated().map { index, tick in
            layoutNote(
                id: 25 + index,
                tick: tick,
                noteType: index == 0 ? .snare : .hiHat,
                rhythm: tripletRhythm(base: .eighth),
                tupletID: upperID,
                durationTicks: 80
            )
        }
        let upperRest = RhythmLayoutRest(
            position: position(tick: 160),
            durationTicks: 80,
            voice: .upper,
            rhythm: tripletRhythm(base: .eighth),
            visibility: .printed,
            tupletID: upperID
        )
        let (upper, _) = try preparedEngraving(try snapshot(
                measures: [rhythmMeasure()],
                notes: upperNotes,
                rests: [upperRest]
            ))
        let upperTuplet = try #require(upper.tuplets.first)

        #expect(!upper.beams.isEmpty)
        #expect(upperTuplet.isBracketVisible)
        #expect(upperTuplet.bracketPoints.count == 6)
        #expect(upperTuplet.memberRestIDs.count == 1)

        let lowerID = tupletID(voice: .lower, durationTicks: 240, stableID: 28)
        let lowerRest = RhythmLayoutRest(
            position: position(tick: 0),
            durationTicks: 80,
            voice: .lower,
            rhythm: tripletRhythm(base: .eighth),
            visibility: .printed,
            tupletID: lowerID
        )
        let lowerNotes = [80, 160].enumerated().map { index, tick in
            layoutNote(
                id: 28 + index,
                tick: tick,
                noteType: index == 0 ? .bass : .hiHatPedal,
                rhythm: tripletRhythm(base: .eighth),
                tupletID: lowerID,
                durationTicks: 80
            )
        }
        let (lower, _) = try preparedEngraving(try snapshot(
                measures: [rhythmMeasure()],
                notes: lowerNotes,
                rests: [lowerRest]
            ))
        let lowerTuplet = try #require(lower.tuplets.first)

        #expect(!lower.beams.isEmpty)
        #expect(lowerTuplet.isBracketVisible)
        #expect(lowerTuplet.bracketPoints.count == 6)
        #expect(lowerTuplet.memberRestIDs.count == 1)
    }

    @Test("swing and shuffle emit one accessible first-staff feel mark")
    func feelMarksAreChartScoped() throws {
        for feel in [RhythmicFeel.swing, .shuffle] {
            let (_, presentation) = try preparedEngraving(
                try snapshot(measures: [rhythmMeasure()], feel: feel)
            )
            let mark = try #require(presentation.annotations.feelMarks.first)

            #expect(presentation.annotations.feelMarks.count == 1)
            #expect(mark.feel == feel)
            #expect(mark.rowIndex == 0)
            #expect(mark.accessibilityLabel == "\(feel.rawValue.capitalized) feel")
        }
    }

    @Test("declared feel suppresses only a long-short pair, not a literal triplet")
    func feelSuppressesOnlyLongShortTupletMark() throws {
        let feelPairID = tupletID(voice: .upper, durationTicks: 240, stableID: 35)
        let feelPair = [
            layoutNote(
                id: 35,
                tick: 0,
                noteType: .snare,
                rhythm: tripletRhythm(base: .quarter),
                tupletID: feelPairID,
                durationTicks: 160
            ),
            layoutNote(
                id: 36,
                tick: 160,
                noteType: .snare,
                rhythm: tripletRhythm(base: .eighth),
                tupletID: feelPairID,
                durationTicks: 80
            )
        ]
        let (swungPair, swungPresentation) = try preparedEngraving(try snapshot(
                measures: [rhythmMeasure()],
                notes: feelPair,
                feel: .swing
            ))

        #expect(swungPair.tuplets.isEmpty)
        #expect(swungPresentation.annotations.feelMarks.count == 1)

        let (straightPair, _) = try preparedEngraving(try snapshot(
                measures: [rhythmMeasure()],
                notes: feelPair,
                feel: .straight
            ))
        #expect(straightPair.tuplets.count == 1)

        let literalID = tupletID(voice: .upper, durationTicks: 240, stableID: 37)
        let literal = [0, 80, 160].enumerated().map { index, tick in
            layoutNote(
                id: 37 + index,
                tick: tick,
                noteType: .snare,
                rhythm: tripletRhythm(base: .eighth),
                tupletID: literalID,
                durationTicks: 80
            )
        }
        let (swungLiteral, _) = try preparedEngraving(try snapshot(
                measures: [rhythmMeasure()],
                notes: literal,
                feel: .swing
            ))

        #expect(swungLiteral.tuplets.count == 1)

        let restID = tupletID(voice: .upper, durationTicks: 240, stableID: 40)
        let noteRestNote = [
            layoutNote(
                id: 40,
                tick: 0,
                noteType: .snare,
                rhythm: tripletRhythm(base: .eighth),
                tupletID: restID,
                durationTicks: 80
            ),
            layoutNote(
                id: 41,
                tick: 160,
                noteType: .snare,
                rhythm: tripletRhythm(base: .eighth),
                tupletID: restID,
                durationTicks: 80
            )
        ]
        let middleRest = RhythmLayoutRest(
            position: position(tick: 80),
            durationTicks: 80,
            voice: .upper,
            rhythm: tripletRhythm(base: .eighth),
            visibility: .printed,
            tupletID: restID
        )
        let (shuffledRestTuplet, _) = try preparedEngraving(try snapshot(
                measures: [rhythmMeasure()],
                notes: noteRestNote,
                rests: [middleRest],
                feel: .shuffle
            ))
        #expect(shuffledRestTuplet.tuplets.count == 1)
    }

    @Test("declared swing and shuffle suppress chordal long-short pairs by occupied onset")
    func declaredFeelSuppressesChordalLongShortPair() throws {
        let pairID = tupletID(voice: .upper, durationTicks: 240, stableID: 45)
        let chordalPair = [
            layoutNote(
                id: 45,
                tick: 0,
                noteType: .snare,
                rhythm: tripletRhythm(base: .quarter),
                tupletID: pairID,
                durationTicks: 160
            ),
            layoutNote(
                id: 46,
                tick: 0,
                noteType: .hiHat,
                rhythm: tripletRhythm(base: .quarter),
                tupletID: pairID,
                durationTicks: 160
            ),
            layoutNote(
                id: 47,
                tick: 160,
                noteType: .snare,
                rhythm: tripletRhythm(base: .eighth),
                tupletID: pairID,
                durationTicks: 80
            ),
            layoutNote(
                id: 48,
                tick: 160,
                noteType: .hiHat,
                rhythm: tripletRhythm(base: .eighth),
                tupletID: pairID,
                durationTicks: 80
            )
        ]

        for feel in [RhythmicFeel.swing, .shuffle] {
            let (engraved, presentation) = try preparedEngraving(try snapshot(
                measures: [rhythmMeasure()],
                notes: chordalPair,
                feel: feel
            ))

            #expect(engraved.tuplets.isEmpty)
            #expect(presentation.annotations.feelMarks.count == 1)
        }
    }

    @Test("unsupported measures keep exact event x while suppressing duration-bearing engraving")
    func unsupportedMeasureUsesConservativeEngraving() throws {
        let tuplet = tupletID(voice: .upper, durationTicks: 240, stableID: 41)
        let notes = [0, 80, 160].enumerated().map { index, tick in
            layoutNote(
                id: 41 + index,
                tick: tick,
                noteType: .snare,
                rhythm: NotationRhythm(
                    baseInterval: .eighth,
                    dotCount: 1,
                    tuplet: TupletRatio(actual: 3, normal: 2)
                ),
                tupletID: tuplet,
                durationTicks: 80
            )
        }
        let generatedRest = RhythmLayoutRest(
            position: position(tick: 240),
            durationTicks: 240,
            voice: .upper,
            rhythm: NotationRhythm(baseInterval: .quarter),
            visibility: .printed,
            tupletID: nil
        )
        let (supported, _) = try preparedEngraving(try snapshot(
                measures: [rhythmMeasure()],
                notes: notes,
                rests: [generatedRest]
            ))
        let (unsupported, unsupportedPresentation) = try preparedEngraving(try snapshot(
                measures: [rhythmMeasure(support: .unsupported([.ambiguousBeatGrouping]))],
                notes: notes,
                rests: [generatedRest]
            ))
        let warning = try #require(unsupportedPresentation.annotations.rhythmWarnings.first)

        #expect(unsupported.noteHeads.map(\.position.x) == supported.noteHeads.map(\.position.x))
        #expect(unsupported.beams.isEmpty)
        #expect(unsupported.flags.isEmpty)
        #expect(unsupported.rhythmDots.isEmpty)
        #expect(unsupported.tuplets.isEmpty)
        #expect(unsupported.rests.isEmpty)
        #expect(unsupportedPresentation.annotations.rhythmWarnings.count == 1)
        #expect(warning.scope == .measure(0))
        #expect(warning.kind == .unsupported)
        #expect(warning.accessibilityLabel.contains("measure 1"))
        #expect(warning.accessibilityLabel.contains("Unsupported rhythm"))
    }

    @Test("warning measures retain engraving and surface their runtime warning")
    func warningMeasureRetainsEngraving() throws {
        let notes = [
            layoutNote(
                id: 51,
                tick: 0,
                noteType: .snare,
                rhythm: NotationRhythm(baseInterval: .eighth)
            ),
            layoutNote(
                id: 52,
                tick: 120,
                noteType: .hiHat,
                rhythm: NotationRhythm(baseInterval: .eighth)
            )
        ]
        let lowerRest = RhythmLayoutRest(
            position: position(tick: 240),
            durationTicks: 240,
            voice: .lower,
            rhythm: NotationRhythm(baseInterval: .quarter),
            visibility: .printed,
            tupletID: nil
        )
        let (engraved, presentation) = try preparedEngraving(try snapshot(
                measures: [rhythmMeasure(support: .warning([.indeterminateTerminalDuration]))],
                notes: notes,
                rests: [lowerRest]
            ))
        let warning = try #require(presentation.annotations.rhythmWarnings.first)

        #expect(!engraved.beams.isEmpty)
        #expect(!engraved.stems.isEmpty)
        // Every engraved rest is printed by construction.
        #expect(engraved.rests.contains { $0.voice == .lower })
        #expect(presentation.annotations.rhythmWarnings.count == 1)
        #expect(warning.scope == .measure(0))
        #expect(warning.kind == .warning)
        #expect(warning.codes == [.indeterminateTerminalDuration])
        #expect(warning.title == "Rhythm warning")
        #expect(!warning.accessibilityLabel.contains("Unsupported"))
        #expect(warning.accessibilityLabel.contains("Rhythm warning"))
        #expect(warning.accessibilityLabel.contains("measure 1"))
    }

    @Test("diagnostic presentation covers stable codes and chart-fatal accessibility")
    func diagnosticPresentationIsStableAndLocalized() throws {
        for code in RhythmDiagnosticCode.allCases {
            let presentation = RhythmDiagnosticPresentation(code: code)
            #expect(!presentation.title.isEmpty)
            #expect(!presentation.description.isEmpty)
            #expect(presentation.logMessage(sourceMeasureIndex: 0, sourceLineNumber: 12)
                .contains("code=\(code.rawValue)"))
            #expect(presentation.logMessage(sourceMeasureIndex: 0, sourceLineNumber: 12)
                .contains("measureIndex=0"))
        }
        let diagnostic = try PersistedRhythmDiagnostic(
            code: .malformedTimeSignature,
            severity: .timingFatal,
            sourceMeasureIndex: 12,
            sourceLineNumber: 4
        )
        let warning = GameplayRhythmWarning.chartFatal(
            diagnostics: [diagnostic],
            position: CGPoint(x: 100, y: 40),
            size: NotationLayoutStyle.gameplayDefault.warningSize
        )

        #expect(warning.scope == .chartFatal)
        #expect(warning.codes == [.malformedTimeSignature])
        #expect(warning.accessibilityLabel.contains("measure 13"))
        #expect(!warning.accessibilityLabel.contains("measure 12"))
    }

    @Test("diagnostics log once at snapshot ingestion and repeated layout stays silent")
    func repeatedLayoutDoesNotRelogPersistedDiagnostics() throws {
        let diagnostic = try PersistedRhythmDiagnostic(
            code: .ambiguousBeatGrouping,
            severity: .engravingOnly,
            sourceMeasureIndex: 0,
            sourceLineNumber: 12
        )
        var messages: [String] = []
        let resolvedSnapshot = try RhythmLayoutSnapshot(
            ticksPerWholeNote: 960,
            measures: [rhythmMeasure(support: .unsupported([.ambiguousBeatGrouping]))],
            notes: [],
            controls: [],
            rests: [],
            feel: .straight,
            diagnostics: [diagnostic, diagnostic]
        )
        resolvedSnapshot.logDiagnostics { messages.append($0) }

        #expect(resolvedSnapshot.diagnostics == [diagnostic])
        #expect(messages == [
            "rhythmDiagnostic code=ambiguousBeatGrouping measureIndex=0 lineNumber=12"
        ])

        _ = try? preparedEngraving(resolvedSnapshot)
        _ = try? preparedEngraving(resolvedSnapshot)

        #expect(messages.count == 1)
    }
}

private extension RhythmRenderingTests {
    func rhythmMeasure(
        support: RhythmEngravingSupport = .supported,
        groupDurationTicks: Int = 240
    ) -> RhythmMeasure {
        RhythmMeasure(
            measureIndex: 0,
            startTick: 0,
            durationTicks: 960,
            timeSignature: .fourFour,
            beatGroups: stride(from: 0, to: 960, by: groupDurationTicks).enumerated().map {
                RhythmBeatGroup(
                    groupIndex: $0.offset,
                    startTick: $0.element,
                    durationTicks: min(groupDurationTicks, 960 - $0.element),
                    isResidual: false
                )
            },
            engravingSupport: support
        )
    }

    func snapshot(
        measures: [RhythmMeasure],
        notes: [RhythmLayoutNote] = [],
        rests: [RhythmLayoutRest] = [],
        feel: RhythmicFeel = .straight
    ) throws -> RhythmLayoutSnapshot {
        try RhythmLayoutSnapshot(
            ticksPerWholeNote: 960,
            measures: measures,
            notes: notes,
            controls: [],
            rests: rests,
            feel: feel
        )
    }

    func layoutNote(
        id: Int,
        tick: Int,
        noteType: NoteType,
        rhythm: NotationRhythm,
        tupletID: RhythmTupletID? = nil,
        durationTicks: Int = 120
    ) -> RhythmLayoutNote {
        return RhythmLayoutNote(
            eventID: RhythmEventID(rawValue: id),
            sourceLaneID: noteType == .bass ? "13" : "1A",
            sourceChipID: "chip-\(id)",
            noteType: noteType,
            position: position(tick: tick),
            durationTicks: durationTicks,
            rhythm: rhythm,
            tupletID: tupletID
        )
    }

    func position(tick: Int) -> RhythmEventPosition {
        RhythmEventPosition(measureIndex: 0, localTick: tick, absoluteTick: tick)
    }

    func tupletID(
        voice: NotationVoice,
        durationTicks: Int,
        stableID: Int
    ) -> RhythmTupletID {
        RhythmTupletID(
            measureIndex: 0,
            voice: voice,
            beatGroupIndex: 0,
            startTick: 0,
            durationTicks: durationTicks,
            stableMemberEventID: RhythmEventID(rawValue: stableID)
        )
    }

    func tripletRhythm(base: NoteInterval) -> NotationRhythm {
        NotationRhythm(
            baseInterval: base,
            tuplet: TupletRatio(actual: 3, normal: 2)
        )
    }
}
