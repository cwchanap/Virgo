import Testing
@testable import DrumNotation
@testable import Virgo

/// HPA-166 Task 2 Step 6 — the temporary production parity gate. Each
/// controlled snapshot is projected through BOTH flag pipelines:
///
/// 1. the live app prepass (`VirgoNotationProjection+Flags` →
///    `visibleFlagClassifications`, still the formatter's flag source until
///    the Task-7 cutover), and
/// 2. the ported package stem-group/topology plan
///    (`StemTopologyBuilder` → `VisibleFlagPlan`).
///
/// The gate compares visible-plan ownership (the stem-side representative's
/// event ID), canonical/component levels, and the flag levels the app
/// actually paints. The app prepass must not be deleted while this suite
/// exists — it is the deletion gate's evidence.
@Suite("Virgo projection/package flag-plan parity")
struct VirgoNotationProjectionFlagParityTests {
    private let style = NotationLayoutStyle.gameplayDefault

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

    private func makeNote(
        eventID: Int,
        noteType: NoteType,
        measureIndex: Int,
        localTick: Int,
        interval: NoteInterval,
        durationTicks: Int? = nil
    ) -> RhythmLayoutNote {
        RhythmLayoutNote(
            eventID: RhythmEventID(rawValue: eventID),
            sourceLaneID: nil,
            sourceChipID: nil,
            noteType: noteType,
            position: RhythmEventPosition(
                measureIndex: measureIndex,
                localTick: localTick,
                absoluteTick: measureIndex * 960 + localTick
            ),
            durationTicks: durationTicks ?? 960 / Self.tickDivisor(of: interval),
            rhythm: NotationRhythm(baseInterval: interval),
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

    /// A note paired with its catalog definition — the tuple shape the app
    /// prepass consumes, as a named type so SwiftLint stays quiet.
    private typealias MappedNote = (
        note: RhythmLayoutNote,
        definition: DrumNotationDefinition
    )

    /// Both flag pipelines' observable output for one snapshot.
    private struct ParityResult {
        /// App prepass: stem-representative event ID → visible flag duration.
        let appClassifications: [Int: NotationFlagDuration]
        /// Package topology: parallel stem groups + plans + reservations.
        let packageTopology: StemTopology
        /// Painted flag levels per flag-representative event ID.
        let paintedFlagLevels: [Int: Set<Int>]
    }

    /// Projects `notes` through the live app prepass, the package stem-group
    /// topology, and the full preparation route (for painted flag levels).
    private func projectBoth(
        notes: [RhythmLayoutNote],
        measures: [RhythmMeasure],
        overrides: [DrumType: GameplayLayout.NotePosition] = [:]
    ) throws -> ParityResult {
        let mapped = notes.compactMap { note -> MappedNote? in
            guard let definition = DrumNotationCatalog.resolve(
                noteType: note.noteType, sourceLaneID: note.sourceLaneID
            )?.definition else { return nil }
            return MappedNote(note: note, definition: definition)
        }
        let appClassifications = VirgoNotationProjection.visibleFlagClassifications(
            notes: mapped,
            expandedMeasures: measures,
            notePositionOverrides: overrides
        )
        let snapshot = try RhythmLayoutSnapshot(
            ticksPerWholeNote: 960,
            measures: measures,
            notes: notes,
            controls: [],
            rests: [],
            feel: .straight
        )
        let input = try VirgoNotationProjection.resolvedNotation(
            snapshot: snapshot,
            expandedMeasures: measures,
            notePositionOverrides: overrides
        )
        let packageTopology = StemTopologyBuilder().build(input)
        let prepared = GameplayNotationPreparer.prepare(GameplayNotationPreparationRequest(
            snapshot: snapshot,
            minimumMeasureCount: measures.count,
            style: style,
            notePositionOverrides: overrides
        ))
        var painted: [Int: Set<Int>] = [:]
        for flag in prepared.layout.flags {
            guard let eventID = prepared.layout.noteHeads
                .first(where: { $0.id == flag.noteHeadID })?
                .eventID else { continue }
            painted[Int(eventID.rawValue), default: []].insert(flag.flagIndex)
        }
        return ParityResult(
            appClassifications: appClassifications,
            packageTopology: packageTopology,
            paintedFlagLevels: painted
        )
    }

    /// The required flag levels `flagIndex` paints for `note`'s interval.
    private func expectedLevels(of note: RhythmLayoutNote) -> Set<Int> {
        Set(0..<note.rhythm.baseInterval.flagCount)
    }

    @Test("isolated sixteenth: canonical plan, app classification and painted levels agree")
    func isolatedSixteenthParity() throws {
        let measure = makeMeasure(index: 0)
        let note = makeNote(
            eventID: 1, noteType: .snare, measureIndex: 0, localTick: 240, interval: .sixteenth
        )
        let result = try projectBoth(notes: [note], measures: [measure])

        // Ownership: one stem group, one plan, one reservation — the app's
        // single classification lands on the same stem representative.
        #expect(result.packageTopology.stemGroups.count == 1)
        #expect(result.packageTopology.flagPlans == [.canonical(.sixteenth)])
        #expect(result.packageTopology.flagReservations == result.appClassifications)
        #expect(result.appClassifications == [1: .sixteenth])
        // Painted levels: the flag representative shows every expected level.
        #expect(result.paintedFlagLevels == [1: expectedLevels(of: note)])
    }

    @Test("fully beamed sixteenths: no plans, no classifications, no painted flags")
    func fullyBeamedParity() throws {
        let measure = makeMeasure(index: 0)
        let notes = (0..<4).map {
            makeNote(
                eventID: $0 + 1,
                noteType: .snare,
                measureIndex: 0,
                localTick: $0 * 60,
                interval: .sixteenth
            )
        }
        let result = try projectBoth(notes: notes, measures: [measure])

        #expect(result.packageTopology.stemGroups.count == 4)
        #expect(result.packageTopology.topology.primaryGroups.count == 1)
        #expect(result.packageTopology.flagPlans == [.none, .none, .none, .none])
        #expect(result.appClassifications.isEmpty)
        #expect(result.packageTopology.flagReservations.isEmpty)
        #expect(result.paintedFlagLevels.isEmpty)
    }

    @Test("same-tick snare + closed-hi-hat chord: one owner, one canonical plan")
    func chordParity() throws {
        let measure = makeMeasure(index: 0)
        let notes = [
            makeNote(
                eventID: 1, noteType: .snare, measureIndex: 0, localTick: 240, interval: .sixteenth
            ),
            makeNote(
                eventID: 2, noteType: .hiHat, measureIndex: 0, localTick: 240, interval: .sixteenth
            )
        ]
        let result = try projectBoth(notes: notes, measures: [measure])
        let stemGroup = try #require(result.packageTopology.stemGroups.first)

        // One stem group owns one flag plan; the stem-side representative —
        // the snare below the hi-hat for an up stem — is the shared owner
        // both pipelines pick.
        #expect(result.packageTopology.stemGroups.count == 1)
        #expect(stemGroup.memberNoteIDs == [1, 2])
        #expect(stemGroup.stemRepresentativeID == 1)
        #expect(result.packageTopology.flagPlans == [.canonical(.sixteenth)])
        #expect(result.appClassifications == [1: .sixteenth])
        #expect(result.packageTopology.flagReservations == result.appClassifications)
        // Both representatives resolve to the snare (equal flag levels break
        // by catalog order; the lower head is the up-stem side), so the one
        // painted flag family lands on it with both levels.
        #expect(result.paintedFlagLevels == [1: [0, 1]])
    }

    @Test("upper/lower voice split: each stem group owns its own plan")
    func voiceSeparationParity() throws {
        let measure = makeMeasure(index: 0)
        let notes = [
            makeNote(
                eventID: 1, noteType: .snare, measureIndex: 0, localTick: 240, interval: .sixteenth
            ),
            makeNote(
                eventID: 2, noteType: .bass, measureIndex: 0, localTick: 240, interval: .sixteenth
            )
        ]
        let result = try projectBoth(notes: notes, measures: [measure])

        // Same tick, different voices: two stem groups, two owners, two
        // canonical plans — both pipelines reserve one flag each.
        #expect(result.packageTopology.stemGroups.count == 2)
        #expect(result.packageTopology.flagPlans == [
            .canonical(.sixteenth), .canonical(.sixteenth)
        ])
        #expect(result.appClassifications == [1: .sixteenth, 2: .sixteenth])
        #expect(result.packageTopology.flagReservations == result.appClassifications)
        #expect(result.paintedFlagLevels == [1: [0, 1], 2: [0, 1]])
    }

    /// One synthetic coverage case for the three-arm flag-plan mapping.
    private struct FlagPlanCase {
        let uncovered: Set<Int>
        let expected: Set<Int>
        let canonical: NotationFlagDuration
    }

    @Test("partially covered levels: package components match the app's eighth footprint")
    func partiallyCoveredParity() {
        // The three-arm mapping's partial arm is unreachable end-to-end —
        // the beam topology's hook segments always cover their owner — so
        // parity for it is pinned at the mapping level the brief requires:
        // same uncovered/expected inputs must yield the same reservation.
        let cases = [
            FlagPlanCase(uncovered: [1], expected: [0, 1], canonical: .sixteenth),
            FlagPlanCase(uncovered: [0, 2], expected: [0, 1, 2], canonical: .thirtySecond),
            FlagPlanCase(uncovered: [2, 3], expected: [0, 1, 2, 3], canonical: .sixtyFourth),
            FlagPlanCase(uncovered: [], expected: [0], canonical: .eighth),
            FlagPlanCase(uncovered: [0], expected: [0], canonical: .eighth),
            FlagPlanCase(uncovered: [0, 1, 2], expected: [0, 1, 2], canonical: .thirtySecond)
        ]
        for flagCase in cases {
            let appResult = VirgoNotationProjection.visibleFlagClassification(
                uncovered: flagCase.uncovered,
                expected: flagCase.expected,
                canonical: flagCase.canonical
            )
            let packagePlan = VisibleFlagPlan(
                uncovered: flagCase.uncovered,
                expected: flagCase.expected,
                canonical: flagCase.canonical
            )
            // The reserved footprint must be identical: canonical keeps its
            // own glyph, partial components reserve the eighth footprint.
            #expect(packagePlan.reservedFlagDuration == appResult)
            if flagCase.uncovered.isEmpty {
                #expect(packagePlan == .none)
            } else if flagCase.uncovered == flagCase.expected {
                #expect(packagePlan == .canonical(flagCase.canonical))
            } else {
                #expect(packagePlan == .components(flagCase.uncovered))
                #expect(appResult == .eighth)
            }
        }
    }
}
