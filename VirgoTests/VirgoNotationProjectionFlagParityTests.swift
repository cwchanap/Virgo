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
        /// The catalog-mapped notes the app prepass consumes.
        let mapped: [MappedNote]
        /// The resolved package input for the same snapshot.
        let input: ResolvedNotationInput
        /// The composed layout — real heads/stems for the flag painter.
        let layout: NotationLayout
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
            paintedFlagLevels: painted,
            mapped: mapped,
            input: input,
            layout: prepared.layout
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

    @Test("partially covered levels: package components match the app's plan through both pipelines")
    func partiallyCoveredParity() throws {
        // The three-arm mapping's partial arm is unreachable from real
        // input — the beam topology's hook segments always cover their
        // owner — so the parity gate injects the defensive coverage state
        // the spec requires through each pipeline's SHARED planning
        // decomposition. Nothing here bypasses production logic: both
        // sides retain a real stem group with real representatives, and
        // only the coverage input is synthetic.
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

        // Real stem groups in both pipelines, found by their tick.
        let appGroups = VirgoNotationProjection.buildStemGroups(notes: result.mapped)
        let packageIndex = try #require(
            result.packageTopology.stemGroups.firstIndex { $0.key.localTick == 240 }
        )
        let appIndex = try #require(appGroups.firstIndex {
            $0.event.timeColumn.tickWithinMeasure == 240
        })
        #expect(appGroups.count == 1)
        #expect(result.packageTopology.stemGroups.count == 1)

        // Inject the same synthetic coverage — level 0 covered, level 1
        // left uncovered — through both real planning paths: the app's
        // `classifyUncoveredFlagLevels` and the package's shared
        // `StemTopologyBuilder` planning seam.
        let coverage = SyntheticCoverage(
            appGroups: appGroups, appIndex: appIndex,
            packageIndex: packageIndex, covered: [0]
        )
        let plans = partiallyCoveredPlans(result: result, coverage: coverage)

        // Ownership + component levels: identical stem groups and
        // representatives, one `.components` plan carrying exactly the
        // uncovered level.
        let stemGroup = plans.package.stemGroups[packageIndex]
        #expect(plans.package.stemGroups == result.packageTopology.stemGroups)
        #expect(plans.package.flagPlans[packageIndex] == .components([1]))
        #expect(stemGroup.stemRepresentativeID == 1)
        #expect(stemGroup.flagRepresentativeID == 1)
        // Reservation parity: same owner, same eighth footprint.
        #expect(plans.appClassifications == [1: .eighth])
        #expect(plans.package.flagReservations == plans.appClassifications)

        try assertPaintedFlagParity(
            result: result, coverage: coverage, stemGroup: stemGroup,
            plan: plans.package.flagPlans[packageIndex]
        )
    }

    /// One synthetic coverage injection: the real stem groups in both
    /// pipelines plus the beam levels each side should treat as covered.
    private struct SyntheticCoverage {
        let appGroups: [VirgoNotationProjection.StemGroup]
        let appIndex: Int
        let packageIndex: Int
        let covered: Set<Int>
    }

    /// Runs both real planning paths over the same synthetic `covered`
    /// levels and returns each side's flag output.
    private func partiallyCoveredPlans(
        result: ParityResult,
        coverage: SyntheticCoverage
    ) -> (appClassifications: [Int: NotationFlagDuration], package: StemTopology) {
        let appClassifications = VirgoNotationProjection.classifyUncoveredFlagLevels(
            stemGroups: coverage.appGroups,
            topology: Virgo.BeamTopologyResult(
                primaryGroups: [],
                coveredLevelsByEventIndex: [coverage.appIndex: coverage.covered]
            ),
            permitsEngraving: [0: true],
            notePositionOverrides: [:]
        )
        let package = StemTopologyBuilder().build(
            result.input,
            topology: DrumNotation.BeamTopologyResult(
                primaryGroups: [],
                coveredLevelsByEventIndex: [coverage.packageIndex: coverage.covered]
            )
        )
        return (appClassifications, package)
    }

    /// Painted-plan interpretation: the app's real flag painter draws one
    /// flag per uncovered level on the flag representative — the package
    /// plan's component set must equal that painted level set.
    private func assertPaintedFlagParity(
        result: ParityResult,
        coverage: SyntheticCoverage,
        stemGroup: DrumNotation.StemGroup,
        plan: VisibleFlagPlan
    ) throws {
        let paintedFlags = NotationLayoutEngine().buildFlags(
            noteHeads: result.layout.noteHeads,
            beamBuild: BeamBuildResult(
                events: coverage.appGroups.map(\.event),
                topology: Virgo.BeamTopologyResult(
                    primaryGroups: [],
                    coveredLevelsByEventIndex: [coverage.appIndex: coverage.covered]
                ),
                beams: []
            ),
            stems: result.layout.stems,
            style: style
        )
        let flagRepHead = try #require(result.layout.noteHeads.first {
            $0.eventID?.rawValue == stemGroup.flagRepresentativeID
        })
        #expect(paintedFlags.count == 1)
        #expect(Set(paintedFlags.map(\.flagIndex)) == [1])
        #expect(paintedFlags.first?.noteHeadID == flagRepHead.id)
        guard case let .components(componentLevels) = plan else {
            Issue.record("expected .components plan under partial coverage")
            return
        }
        #expect(componentLevels == Set(paintedFlags.map(\.flagIndex)))
    }
}
