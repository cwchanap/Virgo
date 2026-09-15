import CoreGraphics
import DrumNotation
import Testing
@testable import Virgo

/// HPA-164 Task 4: the pre-format projection into `DrumNotation`, the single
/// style mapper, the pre-format visible-flag classification, and the one
/// preparation route shared by detached and synchronous invocation. The
/// route-equivalence suite itself lives in
/// `VirgoNotationPreparationRouteTests`.
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
        let bass = try #require(byID[2])
        #expect(bass.noteheadStyle == .normal)
        #expect(bass.stemDirection == .down)
        #expect(bass.duration == .quarter)
        #expect(bass.dotCount == 0)
    }

    @Test("Package model carries no voice/tuplet/beat-group/engraving-support copy")
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

        let forbidden = ["voice", "tuplet", "beatgroup", "engravingsupport", "engraving"]
        let findings = reflectedFieldNames(in: input).filter { field in
            forbidden.contains { field.lowercased().contains($0) }
        }
        #expect(
            findings.isEmpty,
            Comment(rawValue: "package projection carries app-semantics fields: \(findings)")
        )
    }

    // MARK: - Step 2: trailing-measure expansion before package conversion

    @Test("Minimum measure count expansion happens before package conversion")
    func minimumMeasureCountExpandsBeforePackageConversion() throws {
        let measure = makeMeasure(index: 0)
        let snapshot = try makeSnapshot(measures: [measure])

        let input = try VirgoNotationProjection.resolvedNotation(
            snapshot: snapshot,
            expandedMeasures: NotationLayoutEngine().expandedRhythmMeasures(
                snapshot,
                minimumMeasureCount: 3
            ),
            notePositionOverrides: [:]
        )

        #expect(input.measures.map(\.index) == [0, 1, 2])
        #expect(input.measures.map(\.startTick) == [0, 960, 1920])
        #expect(input.measures.map(\.durationTicks) == [960, 960, 960])
    }

    // MARK: - Step 3/4: visible flag classification

    @Test("Flag classification maps uncovered levels to nil/canonical/.eighth")
    func flagClassificationMapperCoversAllThreeArms() {
        let expected: Set<Int> = [0, 1, 2]
        #expect(VirgoNotationProjection.visibleFlagClassification(
            uncovered: [],
            expected: expected,
            canonical: .thirtySecond
        ) == nil)
        #expect(VirgoNotationProjection.visibleFlagClassification(
            uncovered: [0, 1, 2],
            expected: expected,
            canonical: .thirtySecond
        ) == .thirtySecond)
        #expect(VirgoNotationProjection.visibleFlagClassification(
            uncovered: [0, 2],
            expected: expected,
            canonical: .thirtySecond
        ) == .eighth)
    }

    @Test(
        "Pre-format classification agrees with the post-format painted flag family",
        arguments: [
            // Fully beamed: two adjacent eighths inside beat 0.
            BeamFixture(abstractTicks: [0, 120], intervals: [.eighth, .eighth]),
            // Isolated: one sixteenth alone in beat 1.
            BeamFixture(abstractTicks: [240], intervals: [.sixteenth]),
            // Fully beamed mixed run: eighth + adjacent sixteenth in beat 2.
            BeamFixture(abstractTicks: [480, 600], intervals: [.eighth, .sixteenth]),
            // Isolated thirty-second in beat 3.
            BeamFixture(abstractTicks: [720], intervals: [.thirtysecond]),
            // Unflagged notes never carry a visible flag.
            BeamFixture(abstractTicks: [0], intervals: [.quarter])
        ]
    )
    func preFormatClassificationAgreesWithPostFormatFlagPainting(fixture: BeamFixture) throws {
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
        let expandedMeasures = [measure]
        let style = NotationLayoutStyle.gameplayDefault

        // Pre-format: the adapter projection.
        let input = try VirgoNotationProjection.resolvedNotation(
            snapshot: snapshot,
            expandedMeasures: expandedMeasures,
            notePositionOverrides: [:]
        )
        let classificationByID = Dictionary(
            uniqueKeysWithValues: input.notes.compactMap { note in
                note.visibleFlagDuration.map { (note.id, $0) }
            }
        )

        // Post-format: the same pipeline the engine paints from — the one
        // measured preparation route (HPA-164).
        let prepared = GameplayNotationPreparer.prepare(GameplayNotationPreparationRequest(
            snapshot: snapshot,
            minimumMeasureCount: 1,
            style: style,
            notePositionOverrides: [:]
        ))
        let layout = prepared.layout
        let beamBuild = NotationLayoutEngine().buildBeams(
            noteHeads: layout.noteHeads,
            measures: expandedMeasures,
            style: style
        )
        let stems = NotationLayoutEngine().buildStems(noteHeads: layout.noteHeads, beams: beamBuild.beams, style: style)
        let flags = NotationLayoutEngine().buildFlags(
            noteHeads: layout.noteHeads,
            beamBuild: beamBuild,
            stems: stems,
            style: style
        )
        let commands = VirgoNotationAdapter.flagPaintCommands(
            flags: flags,
            heads: layout.noteHeads,
            style: style
        )

        // Painted family per representative head: canonical duration when the
        // uncovered levels are exactly the expected set, .eighth otherwise.
        var paintedFamilyByID: [Int: NotationFlagDuration] = [:]
        for (headID, headFlags) in Dictionary(grouping: flags, by: \.noteHeadID) {
            guard let head = layout.noteHeads.first(where: { $0.id == headID }),
                let eventID = head.eventID.map({ Int($0.rawValue) })
            else { continue }
            let levels = Set(headFlags.map(\.flagIndex))
            let expectedLevels = Set(0..<head.interval.flagCount)
            if levels == expectedLevels {
                let canonical = try #require(
                    commands.first { $0.id == headFlags.first { $0.flagIndex == 0 }?.id }
                )
                paintedFamilyByID[eventID] = canonical.duration
            } else {
                paintedFamilyByID[eventID] = .eighth
            }
        }

        // Unflagged intervals must carry a nil classification on the
        // projected note itself — absence from classificationByID alone is
        // vacuous when a note never reached the projection (the measure-
        // bounds guard drops ticks at or past the measure duration) — and
        // the post-format path must paint no flags for their heads.
        for note in notes where note.rhythm.baseInterval.flagCount == 0 {
            let projected = try #require(input.notes.first { $0.id == note.eventID.rawValue })
            #expect(projected.visibleFlagDuration == nil)
            let headIDs = Set(layout.noteHeads.filter { $0.eventID == note.eventID }.map(\.id))
            #expect(!headIDs.isEmpty && flags.allSatisfy { !headIDs.contains($0.noteHeadID) })
        }

        // Every note's pre-format classification must equal the family its
        // stem group paints post-format.
        for (eventID, classification) in classificationByID {
            #expect(
                paintedFamilyByID[eventID] == classification,
                Comment(rawValue: "eventID \(eventID): pre-format \(String(describing: classification)) "
                    + "vs painted \(String(describing: paintedFamilyByID[eventID]))")
            )
        }
        // And every painted family must be claimed by a matching classification.
        for (eventID, family) in paintedFamilyByID {
            #expect(classificationByID[eventID] == family)
        }
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

        #expect(input.notes.first?.visibleFlagDuration == nil)
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

    // MARK: - Fixtures

    struct BeamFixture: Sendable {
        let abstractTicks: [Int]
        let intervals: [NoteInterval]
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
        controls: [RhythmLayoutControl] = []
    ) throws -> RhythmLayoutSnapshot {
        try RhythmLayoutSnapshot(
            ticksPerWholeNote: ticksPerWholeNote,
            measures: measures,
            notes: notes,
            controls: controls,
            rests: rests,
            feel: .straight
        )
    }

    private func makeNote(
        eventID: Int,
        noteType: NoteType,
        measureIndex: Int,
        localTick: Int,
        absoluteTick: Int? = nil,
        interval: NoteInterval,
        dotCount: Int = 0
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
            durationTicks: durationTicks(of: interval),
            rhythm: NotationRhythm(baseInterval: interval, dotCount: dotCount),
            tupletID: nil
        )
    }

    private func makeRest(
        measureIndex: Int,
        localTick: Int,
        voice: NotationVoice,
        interval: NoteInterval,
        visibility: NotationRestVisibility
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
            rhythm: NotationRhythm(baseInterval: interval),
            visibility: visibility,
            tupletID: nil
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

    private func makeControl(eventID: Int, measureIndex: Int, localTick: Int) -> RhythmLayoutControl {
        let source = ChartControlEvent(kind: .stop, measureNumber: measureIndex + 1, measureOffset: 0)
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
