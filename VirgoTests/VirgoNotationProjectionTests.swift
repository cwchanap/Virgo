import CoreGraphics
import DrumNotation
import Testing
@testable import Virgo

/// HPA-164 Task 4: the pre-format projection into `DrumNotation`, the single
/// style mapper, and the one preparation route shared by detached and
/// synchronous invocation. The route-equivalence suite itself lives in
/// `VirgoNotationPreparationRouteTests`. HPA-166 Task 7 deleted the app-side
/// pre-format flag classification — the package derives flag topology
/// internally — so flag agreement is now asserted on the engraved output.
@Suite("Virgo Notation Projection")
struct VirgoNotationProjectionTests {
    private let ticksPerWholeNote = 960

    // MARK: - Step 1: trimmed input projection

    @Test("RhythmEventID rawValues map directly to package note/control IDs")
    func eventIDsMapDirectlyToPackageIDs() throws {
        let snapshot = try makeSnapshot(
            measures: [makeMeasure(index: 0)],
            notes: [makeNote(eventID: 42, noteType: .snare, measureIndex: 0, localTick: 0, interval: .quarter)],
            controls: [makeControl(eventID: 7, measureIndex: 0, localTick: 240)]
        )

        let input = try VirgoNotationProjection.resolvedNotation(
            snapshot: snapshot,
            expandedMeasures: [makeMeasure(index: 0)],
            notePositionOverrides: [:]
        )

        #expect(input.notes.map(\.id) == [42])
        #expect(input.controls.map(\.id) == [7])
        // Stop lane targeting the snare (lane "12", `.line3`): the package
        // step is pitch-ascending, so app step −4 crosses as +4.
        let control = try #require(input.controls.first)
        #expect(control.kind == .stop)
        #expect(control.targetStaffStep == 4)
    }

    @Test("Measure/local tick survives; absolute tick is derivable, not copied")
    func measureAndLocalTickSurviveAndAbsoluteTickIsDerivable() throws {
        let measure = makeMeasure(index: 1, startTick: 960)
        let snapshot = try makeSnapshot(
            measures: [makeMeasure(index: 0), measure],
            notes: [makeNote(
                eventID: 5,
                noteType: .snare,
                measureIndex: 1,
                localTick: 240,
                absoluteTick: 1200,
                interval: .quarter
            )]
        )

        let input = try VirgoNotationProjection.resolvedNotation(
            snapshot: snapshot,
            expandedMeasures: [makeMeasure(index: 0), measure],
            notePositionOverrides: [:]
        )

        let note = try #require(input.notes.first)
        #expect(note.position.measureIndex == 1)
        #expect(note.position.localTick == 240)
        // The package derives absolute tick from the owning measure.
        let owningMeasure = try #require(input.measures.first { $0.index == 1 })
        #expect(owningMeasure.startTick + note.position.localTick == 1200)
        // Nothing in the projected tree copies an absolute tick.
        #expect(reflectedFieldNames(in: input).filter { $0.lowercased().contains("absolute") }.isEmpty)
    }

    @Test("Staff position overrides survive as staffStep")
    func staffOverrideSurvivesAsStaffStep() throws {
        let snapshot = try makeSnapshot(
            measures: [makeMeasure(index: 0)],
            notes: [
                makeNote(eventID: 1, noteType: .snare, measureIndex: 0, localTick: 0, interval: .quarter),
                makeNote(eventID: 2, noteType: .bass, measureIndex: 0, localTick: 240, interval: .quarter)
            ]
        )

        let input = try VirgoNotationProjection.resolvedNotation(
            snapshot: snapshot,
            expandedMeasures: [makeMeasure(index: 0)],
            notePositionOverrides: [.snare: .line1, .kick: .belowLine2]
        )

        let staffStepsByID = Dictionary(uniqueKeysWithValues: input.notes.map { ($0.id, $0.staffStep) })
        // Package convention is pitch-ascending: the adapter negates Virgo's
        // Y-down step, so line1 = 0 and belowLine2 (yOffset +40) = −4.
        #expect(staffStepsByID[1] == 0)
        #expect(staffStepsByID[2] == -4)
    }

    @Test("Notehead style, stem direction, duration and dots survive")
    func headStyleStemDurationAndDotsSurvive() throws {
        let snapshot = try makeSnapshot(
            measures: [makeMeasure(index: 0)],
            notes: [
                makeNote(
                    eventID: 1,
                    noteType: .openHiHat,
                    measureIndex: 0,
                    localTick: 0,
                    interval: .sixteenth,
                    dotCount: 1
                ),
                makeNote(
                    eventID: 2,
                    noteType: .bass,
                    measureIndex: 0,
                    localTick: 240,
                    interval: .quarter,
                    dotCount: 0
                )
            ]
        )

        let input = try VirgoNotationProjection.resolvedNotation(
            snapshot: snapshot,
            expandedMeasures: [makeMeasure(index: 0)],
            notePositionOverrides: [:]
        )

        let byID = Dictionary(uniqueKeysWithValues: input.notes.map { ($0.id, $0) })
        let hiHat = try #require(byID[1])
        #expect(hiHat.noteheadStyle == .x)
        #expect(hiHat.stemDirection == .up)
        #expect(hiHat.duration == .sixteenth)
        #expect(hiHat.dotCount == 1)
        // HPA-166: voice comes from the resolved catalog definition, the
        // tiebreak is its catalog order, and the open-hi-hat variant resolves
        // to the package's articulation intent.
        #expect(hiHat.voice == .upper)
        #expect(hiHat.durationTicks == 60)
        #expect(hiHat.tiebreakOrder == 3)
        #expect(hiHat.isRhythmEngravable)
        #expect(hiHat.articulation == .open)
        let bass = try #require(byID[2])
        #expect(bass.noteheadStyle == .normal)
        #expect(bass.stemDirection == .down)
        #expect(bass.duration == .quarter)
        #expect(bass.dotCount == 0)
        #expect(bass.voice == .lower)
        #expect(bass.durationTicks == 240)
        #expect(bass.tiebreakOrder == 0)
        #expect(bass.articulation == nil)
    }

    @Test("Package projection carries resolved semantics only, no app-implementation fields")
    func packageModelCarriesNoAppSemanticsCopy() throws {
        let measure = makeMeasure(index: 0)
        let snapshot = try makeSnapshot(
            measures: [measure],
            notes: [makeNote(eventID: 1, noteType: .snare, measureIndex: 0, localTick: 0, interval: .quarter)],
            rests: [makeRest(
                measureIndex: 0,
                localTick: 240,
                voice: .upper,
                interval: .quarter,
                visibility: .printed
            )],
            controls: [makeControl(eventID: 3, measureIndex: 0, localTick: 480)]
        )
        let input = try VirgoNotationProjection.resolvedNotation(
            snapshot: snapshot,
            expandedMeasures: [measure],
            notePositionOverrides: [:]
        )

        // Resolved engraving semantics (voice, meter, beatGroups, tuplets,
        // targetStaffStep) legitimately cross since HPA-166 Task 1. What must
        // never cross is the app's implementation vocabulary: lane/chip IDs,
        // rest visibility, raw rhythm-support or engraving-support state,
        // feel names, absolute ticks, beat-group internals like residual
        // markers or group indexes, and per-member stable event IDs.
        let forbidden = [
            "lane", "chip", "visibility", "engravingsupport", "support",
            "feel", "absolute", "groupindex", "isresidual", "stemless",
            "variant", "instrument", "stablemember"
        ]
        let findings = reflectedFieldNames(in: input).filter { field in
            forbidden.contains { field.lowercased().contains($0) }
        }
        #expect(
            findings.isEmpty,
            Comment(rawValue: "package projection carries app-implementation fields: \(findings)")
        )
    }

    // MARK: - Step 2: trailing-measure expansion before package conversion

    @Test("Minimum measure count expansion happens before package conversion")
    func minimumMeasureCountExpandsBeforePackageConversion() throws {
        let measure = makeMeasure(index: 0)
        let snapshot = try makeSnapshot(measures: [measure])

        let input = try VirgoNotationProjection.resolvedNotation(
            snapshot: snapshot,
            expandedMeasures: GameplayNotationPreparer.expandedRhythmMeasures(
                snapshot,
                minimumMeasureCount: 3
            ),
            notePositionOverrides: [:]
        )

        #expect(input.measures.map(\.index) == [0, 1, 2])
        #expect(input.measures.map(\.startTick) == [0, 960, 1920])
        #expect(input.measures.map(\.durationTicks) == [960, 960, 960])
        // Meter and ordered beat groups cross on every measure — including
        // the synthesized trailing ones, which the same builder materializes.
        let fourByFour = NotationMeter(beats: 4, noteValue: 4)
        let expectedGroups = (0..<4).map { ResolvedBeatGroup(startTick: $0 * 240, durationTicks: 240) }
        #expect(input.measures.allSatisfy { $0.meter == fourByFour })
        #expect(input.measures.allSatisfy { $0.beatGroups == expectedGroups })
    }

    // MARK: - Step 3/4: engraved flag output

    @Test(
        "Engraved flag families match the beaming outcome per fixture",
        arguments: [
            // Fully beamed: two adjacent eighths inside beat 0 — no flags.
            FlagFixture(abstractTicks: [0, 120], intervals: [.eighth, .eighth], expected: [:]),
            // Isolated: one sixteenth alone in beat 1 — canonical flag.
            FlagFixture(abstractTicks: [240], intervals: [.sixteenth], expected: [1: .sixteenth]),
            // Mixed run: eighth + adjacent sixteenth in beat 2 — the
            // sixteenth's secondary level takes a hook beam, so nothing
            // paints a flag.
            FlagFixture(
                abstractTicks: [480, 600],
                intervals: [.eighth, .sixteenth],
                expected: [:]
            ),
            // Isolated thirty-second in beat 3 — canonical flag.
            FlagFixture(abstractTicks: [720], intervals: [.thirtysecond], expected: [1: .thirtySecond]),
            // Unflagged intervals never carry a visible flag.
            FlagFixture(abstractTicks: [0], intervals: [.quarter], expected: [:])
        ]
    )
    func engravedFlagFamiliesMatchBeaming(fixture: FlagFixture) throws {
        let measure = makeMeasure(index: 0)
        let notes = zip(fixture.abstractTicks, fixture.intervals).enumerated().map { index, pair in
            makeNote(
                eventID: index + 1,
                noteType: .snare,
                measureIndex: 0,
                localTick: pair.0,
                interval: pair.1
            )
        }
        let snapshot = try makeSnapshot(measures: [measure], notes: notes)

        // The one measured preparation route — the package derives flag
        // topology internally; each painted flag cites its stem group's
        // representative note ID (the event ID verbatim).
        let prepared = GameplayNotationPreparer.prepare(GameplayNotationPreparationRequest(
            snapshot: snapshot,
            minimumMeasureCount: 1,
            style: .gameplayDefault,
            notePositionOverrides: [:]
        ))
        let engraved = try DrumTabFixtureHarness.requireEngraved(prepared)
        let paintedFamilyByID = Dictionary(
            uniqueKeysWithValues: engraved.flags.map { ($0.noteID, $0.duration) }
        )

        #expect(paintedFamilyByID == fixture.expected)
    }

    @Test("Notes in engraving-unsupported measures never carry a visible flag")
    func unsupportedMeasureNotesNeverCarryFlags() throws {
        let measure = RhythmMeasure(
            measureIndex: 0,
            startTick: 0,
            durationTicks: 960,
            timeSignature: .fourFour,
            beatGroups: (0..<4).map {
                RhythmBeatGroup(groupIndex: $0, startTick: $0 * 240, durationTicks: 240, isResidual: false)
            },
            engravingSupport: .unsupported([.malformedMeasureLength])
        )
        let snapshot = try makeSnapshot(
            measures: [measure],
            notes: [makeNote(eventID: 1, noteType: .snare, measureIndex: 0, localTick: 0, interval: .sixteenth)]
        )

        let input = try VirgoNotationProjection.resolvedNotation(
            snapshot: snapshot,
            expandedMeasures: [measure],
            notePositionOverrides: [:]
        )

        // The note still crosses (Virgo preserves its identity) but the
        // package suppresses its duration-bearing engraving.
        #expect(input.notes.first?.isRhythmEngravable == false)
        let engraved = try NotationEngraver.engrave(
            input,
            style: VirgoNotationProjection.engravingStyle(for: .gameplayDefault)
        )
        #expect(engraved.noteHeads.map(\.noteID) == [1])
        #expect(engraved.stems.isEmpty && engraved.beams.isEmpty && engraved.flags.isEmpty)
        #expect(engraved.rhythmDots.isEmpty)
    }

    // MARK: - Step 5: the single style mapper

    @Test("formattingStyle maps resolved row width and the pinned Virgo values")
    func formattingStyleMapsPinnedValues() {
        let style = VirgoNotationProjection.formattingStyle(
            rowWidth: 1200,
            style: .gameplayDefault
        )

        #expect(style.availableRowWidth == 1200)
        #expect(style.rowLeadingInset == GameplayLayout.leftMargin)
        #expect(style.rowLeadingInset == 100)
        #expect(style.staffSpace == GameplayLayout.staffLineSpacing)
        #expect(style.staffSpace == 20)
        #expect(style.stemWidth == GameplayLayout.stemWidth)
        #expect(style.stemWidth == 2)
        #expect(style.minimumInterColumnClearance == 8)
        #expect(style.minimumQuarterNoteSpacing == GameplayLayout.uniformSpacing)
        #expect(style.minimumQuarterNoteSpacing == 50)
        #expect(style.measureSpacing == 12)
        #expect(style.leadingMeasureInset == GameplayLayout.barLineWidth + GameplayLayout.uniformSpacing)
        #expect(style.leadingMeasureInset == 52)
        #expect(style.trailingMeasureInset == 0)
        #expect(style.rhythmDotRadius == 2.5)
        #expect(style.rhythmDotSpacing == 4)
    }

    @Test("formattingStyle applies the 900pt row-width floor")
    func formattingStyleAppliesRowWidthFloor() {
        let style = VirgoNotationProjection.formattingStyle(
            rowWidth: 500,
            style: .gameplayDefault
        )
        #expect(style.availableRowWidth == GameplayLayout.maxRowWidth)
    }

    // MARK: - Step 6/7: one preparation route
    // The route-equivalence tests live in `VirgoNotationPreparationRouteTests`.
    // The HPA-166 control-intent and tuplet mapping tests live in
    // `VirgoNotationProjectionEngravingTests`.

    // MARK: - Fixtures

    struct FlagFixture: Sendable {
        let abstractTicks: [Int]
        let intervals: [NoteInterval]
        /// Painted flag duration per representative note ID (event ID raw value).
        let expected: [Int: NotationFlagDuration]
    }

    /// Four-beat 4/4 measure at 960 ticks/whole-note: quarter = 240 ticks.
    private func makeMeasure(index: Int, startTick: Int = 0) -> RhythmMeasure {
        RhythmMeasure(
            measureIndex: index,
            startTick: startTick,
            durationTicks: 960,
            timeSignature: .fourFour,
            beatGroups: (0..<4).map {
                RhythmBeatGroup(groupIndex: $0, startTick: $0 * 240, durationTicks: 240, isResidual: false)
            },
            engravingSupport: .supported
        )
    }

    private func makeSnapshot(
        measures: [RhythmMeasure],
        notes: [RhythmLayoutNote] = [],
        rests: [RhythmLayoutRest] = [],
        controls: [RhythmLayoutControl] = [],
        feel: RhythmicFeel = .straight
    ) throws -> RhythmLayoutSnapshot {
        try RhythmLayoutSnapshot(
            ticksPerWholeNote: ticksPerWholeNote,
            measures: measures,
            notes: notes,
            controls: controls,
            rests: rests,
            feel: feel
        )
    }

    private func makeNote(
        eventID: Int,
        noteType: NoteType,
        measureIndex: Int,
        localTick: Int,
        absoluteTick: Int? = nil,
        interval: NoteInterval,
        dotCount: Int = 0,
        durationTicks: Int? = nil,
        tuplet: TupletRatio? = nil,
        tupletID: RhythmTupletID? = nil
    ) -> RhythmLayoutNote {
        RhythmLayoutNote(
            eventID: RhythmEventID(rawValue: eventID),
            sourceLaneID: nil,
            sourceChipID: nil,
            noteType: noteType,
            position: RhythmEventPosition(
                measureIndex: measureIndex,
                localTick: localTick,
                absoluteTick: absoluteTick ?? measureIndex * 960 + localTick
            ),
            durationTicks: durationTicks ?? self.durationTicks(of: interval),
            rhythm: NotationRhythm(baseInterval: interval, dotCount: dotCount, tuplet: tuplet),
            tupletID: tupletID
        )
    }

    private func makeRest(
        measureIndex: Int,
        localTick: Int,
        voice: NotationVoice,
        interval: NoteInterval,
        visibility: NotationRestVisibility,
        tuplet: TupletRatio? = nil,
        tupletID: RhythmTupletID? = nil
    ) -> RhythmLayoutRest {
        let durationTicks = ticksPerWholeNote / Self.tickDivisor(of: interval)
        return RhythmLayoutRest(
            position: RhythmEventPosition(
                measureIndex: measureIndex,
                localTick: localTick,
                absoluteTick: measureIndex * 960 + localTick
            ),
            durationTicks: durationTicks,
            voice: voice,
            rhythm: NotationRhythm(baseInterval: interval, tuplet: tuplet),
            visibility: visibility,
            tupletID: tupletID
        )
    }

    private static func tickDivisor(of interval: NoteInterval) -> Int {
        switch interval {
        case .full: return 1
        case .half: return 2
        case .quarter: return 4
        case .eighth: return 8
        case .sixteenth: return 16
        case .thirtysecond: return 32
        case .sixtyfourth: return 64
        }
    }

    private func makeControl(
        eventID: Int,
        measureIndex: Int,
        localTick: Int,
        kind: NotationControlEventKind = .stop,
        targetLaneID: String? = "12"
    ) -> RhythmLayoutControl {
        let source = ChartControlEvent(
            kind: kind,
            measureNumber: measureIndex + 1,
            measureOffset: 0,
            targetLaneID: targetLaneID
        )
        return RhythmLayoutControl(
            eventID: RhythmEventID(rawValue: eventID),
            event: NotationControlEvent(source),
            position: RhythmEventPosition(
                measureIndex: measureIndex,
                localTick: localTick,
                absoluteTick: measureIndex * 960 + localTick
            )
        )
    }

    private func durationTicks(of interval: NoteInterval) -> Int {
        switch interval {
        case .full: return ticksPerWholeNote
        case .half: return ticksPerWholeNote / 2
        case .quarter: return ticksPerWholeNote / 4
        case .eighth: return ticksPerWholeNote / 8
        case .sixteenth: return ticksPerWholeNote / 16
        case .thirtysecond: return ticksPerWholeNote / 32
        case .sixtyfourth: return ticksPerWholeNote / 64
        }
    }

    private func reflectedFieldNames(in value: Any) -> [String] {
        var names: [String] = []
        collectFieldNames(in: value, names: &names)
        return names
    }

    /// The `.class`/`.enum` case-skip bounds the reflection scan to the
    /// package's all-value-type input; revisit if package types grow
    /// reference or enum payloads.
    private func collectFieldNames(in value: Any, names: inout [String]) {
        let mirror = Mirror(reflecting: value)
        guard mirror.displayStyle == .struct || mirror.displayStyle == .collection
            || mirror.displayStyle == .optional else { return }
        for child in mirror.children {
            if let label = child.label {
                names.append(label)
                collectFieldNames(in: child.value, names: &names)
            } else if mirror.displayStyle == .collection || mirror.displayStyle == .optional {
                collectFieldNames(in: child.value, names: &names)
            }
        }
    }
}
