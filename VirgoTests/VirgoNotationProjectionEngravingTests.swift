import DrumNotation
import Testing
@testable import Virgo

/// HPA-166 Task 1: resolved control intent at the package boundary — the
/// control kind and the resolved target staff step (including staff-position
/// overrides) cross, while controls whose target cannot resolve stay out.
/// Tuplet mapping tests live in the sibling suite below; both are split
/// from `VirgoNotationProjectionTests` for SwiftLint's length limits.
@Suite("Virgo Notation Projection Engraving")
struct VirgoNotationProjectionEngravingTests {
    @Test("Control kind and resolved target staff step cross; unresolvable controls drop")
    func controlKindAndResolvedTargetSurvive() throws {
        let measure = EngravingProjectionFixtures.makeMeasure(index: 0)
        let snapshot = try EngravingProjectionFixtures.makeSnapshot(
            measures: [measure],
            controls: [
                EngravingProjectionFixtures.makeControl(
                    eventID: 1, measureIndex: 0, localTick: 0, kind: .stop, targetLaneID: "12"
                ),
                EngravingProjectionFixtures.makeControl(
                    eventID: 2, measureIndex: 0, localTick: 240, kind: .choke, targetLaneID: "12"
                ),
                EngravingProjectionFixtures.makeControl(
                    eventID: 3, measureIndex: 0, localTick: 480, kind: .damp, targetLaneID: "11"
                ),
                // Unknown target lane: the engine drops these rather than
                // painting a mark at a fabricated step, so they never cross.
                EngravingProjectionFixtures.makeControl(
                    eventID: 4, measureIndex: 0, localTick: 720, kind: .stop, targetLaneID: "ZZ"
                ),
                EngravingProjectionFixtures.makeControl(
                    eventID: 5, measureIndex: 0, localTick: 720, kind: .stop, targetLaneID: nil
                )
            ]
        )

        let input = try VirgoNotationProjection.resolvedNotation(
            snapshot: snapshot,
            expandedMeasures: [measure],
            notePositionOverrides: [:]
        )

        #expect(input.controls.map(\.id) == [1, 2, 3])
        let byID = Dictionary(uniqueKeysWithValues: input.controls.map { ($0.id, $0) })
        // Snare target sits on `.line3` (app step −4 → package +4); the
        // hi-hat target sits on `.line5` (app step −8 → +8).
        #expect(byID[1]?.kind == .stop)
        #expect(byID[1]?.targetStaffStep == 4)
        #expect(byID[2]?.kind == .choke)
        #expect(byID[2]?.targetStaffStep == 4)
        #expect(byID[3]?.kind == .damp)
        #expect(byID[3]?.targetStaffStep == 8)
    }

    @Test("Staff-position overrides apply to control targets")
    func controlTargetHonorsStaffOverrides() throws {
        let measure = EngravingProjectionFixtures.makeMeasure(index: 0)
        let snapshot = try EngravingProjectionFixtures.makeSnapshot(
            measures: [measure],
            controls: [
                EngravingProjectionFixtures.makeControl(
                    eventID: 1, measureIndex: 0, localTick: 0, targetLaneID: "12"
                )
            ]
        )

        let input = try VirgoNotationProjection.resolvedNotation(
            snapshot: snapshot,
            expandedMeasures: [measure],
            notePositionOverrides: [.snare: .line1]
        )

        // `.line1` is app step 0 — the override moves the resolved target.
        #expect(input.controls.first?.targetStaffStep == 0)
    }
}

/// HPA-166 Task 1: resolved tuplet groups at the package boundary —
/// deterministic adapter-local IDs, member references into the resolved
/// note/rest namespaces, and the same suppression rules the engine applies
/// (unsupported measures, declared swing/shuffle long-short pairs).
@Suite("Virgo Notation Projection Tuplets")
struct VirgoNotationProjectionTupletTests {
    @Test("A resolved triplet crosses with a deterministic ID and member references")
    func tripletProjectsWithDeterministicIDAndMembers() throws {
        let measure = EngravingProjectionFixtures.makeMeasure(index: 0)
        // Eighth-note triplet across beat group 0 (ticks 0..<240): three
        // members at 0/80/160 with 80-tick spans.
        let tripletID = RhythmTupletID(
            measureIndex: 0,
            voice: .upper,
            beatGroupIndex: 0,
            startTick: 0,
            durationTicks: 240,
            stableMemberEventID: RhythmEventID(rawValue: 1)
        )
        let snapshot = try EngravingProjectionFixtures.makeSnapshot(
            measures: [measure],
            notes: [0, 1, 2].map { index in
                EngravingProjectionFixtures.makeNote(
                    eventID: index + 1,
                    noteType: .hiHat,
                    measureIndex: 0,
                    localTick: index * 80,
                    interval: .eighth,
                    durationTicks: 80,
                    tupletID: tripletID
                )
            }
        )

        let input = try VirgoNotationProjection.resolvedNotation(
            snapshot: snapshot,
            expandedMeasures: [measure],
            notePositionOverrides: [:]
        )

        let triplet = try #require(input.tuplets.first)
        #expect(input.tuplets.count == 1)
        #expect(triplet.id == 0)
        #expect(triplet.measureIndex == 0)
        #expect(triplet.voice == .upper)
        #expect(triplet.ratio == ResolvedTupletRatio(actual: 3, normal: 2))
        #expect(triplet.memberNoteIDs == [1, 2, 3])
        #expect(triplet.memberRestIDs == [])

        // IDs are deterministic: projecting the same snapshot twice yields
        // identical tuplets.
        let again = try VirgoNotationProjection.resolvedNotation(
            snapshot: snapshot,
            expandedMeasures: [measure],
            notePositionOverrides: [:]
        )
        #expect(again.tuplets == input.tuplets)
    }

    @Test("A printed rest member crosses as its resolved rest ordinal")
    func tupletRestMemberUsesPrintedOrdinal() throws {
        let measure = EngravingProjectionFixtures.makeMeasure(index: 0)
        let mixedID = RhythmTupletID(
            measureIndex: 0,
            voice: .upper,
            beatGroupIndex: 1,
            startTick: 240,
            durationTicks: 240,
            stableMemberEventID: RhythmEventID(rawValue: 4)
        )
        let snapshot = try EngravingProjectionFixtures.makeSnapshot(
            measures: [measure],
            notes: [
                EngravingProjectionFixtures.makeNote(
                    eventID: 4,
                    noteType: .hiHat,
                    measureIndex: 0,
                    localTick: 240,
                    interval: .eighth,
                    durationTicks: 80,
                    tupletID: mixedID
                )
            ],
            rests: [
                EngravingProjectionFixtures.makeRest(
                    measureIndex: 0,
                    localTick: 320,
                    voice: .upper,
                    interval: .eighth,
                    visibility: .printed,
                    tupletID: mixedID
                )
            ]
        )

        let input = try VirgoNotationProjection.resolvedNotation(
            snapshot: snapshot,
            expandedMeasures: [measure],
            notePositionOverrides: [:]
        )

        let group = try #require(input.tuplets.first)
        #expect(input.tuplets.count == 1)
        #expect(group.memberNoteIDs == [4])
        // The printed rest is the only printed rest, so its resolved ID is 0.
        #expect(group.memberRestIDs == [0])
    }

    @Test("Tuplets in engraving-unsupported measures never cross")
    func unsupportedMeasureTupletsAreFiltered() throws {
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
        let tripletID = RhythmTupletID(
            measureIndex: 0,
            voice: .upper,
            beatGroupIndex: 0,
            startTick: 0,
            durationTicks: 240,
            stableMemberEventID: RhythmEventID(rawValue: 1)
        )
        let snapshot = try EngravingProjectionFixtures.makeSnapshot(
            measures: [measure],
            notes: [0, 1, 2].map { index in
                EngravingProjectionFixtures.makeNote(
                    eventID: index + 1,
                    noteType: .hiHat,
                    measureIndex: 0,
                    localTick: index * 80,
                    interval: .eighth,
                    durationTicks: 80,
                    tupletID: tripletID
                )
            }
        )

        let input = try VirgoNotationProjection.resolvedNotation(
            snapshot: snapshot,
            expandedMeasures: [measure],
            notePositionOverrides: [:]
        )

        #expect(input.tuplets.isEmpty)
        // The member notes themselves still cross, flagged non-engravable.
        #expect(input.notes.count == 3)
        #expect(input.notes.allSatisfy { !$0.isRhythmEngravable })
    }

    @Test("Declared swing/shuffle long-short pairs stay suppressed at the boundary")
    func swingPairsStaySuppressed() throws {
        let measure = EngravingProjectionFixtures.makeMeasure(index: 0)
        // The engine's declared-pair shape: a 3:2 group covering one whole
        // beat group with notes on the long and short slots only.
        let pairID = RhythmTupletID(
            measureIndex: 0,
            voice: .upper,
            beatGroupIndex: 0,
            startTick: 0,
            durationTicks: 240,
            stableMemberEventID: RhythmEventID(rawValue: 1)
        )
        let notes = [
            EngravingProjectionFixtures.makeNote(
                eventID: 1,
                noteType: .hiHat,
                measureIndex: 0,
                localTick: 0,
                interval: .quarter,
                durationTicks: 160,
                tupletID: pairID
            ),
            EngravingProjectionFixtures.makeNote(
                eventID: 2,
                noteType: .hiHat,
                measureIndex: 0,
                localTick: 160,
                interval: .eighth,
                durationTicks: 80,
                tupletID: pairID
            )
        ]

        let straight = try VirgoNotationProjection.resolvedNotation(
            snapshot: try EngravingProjectionFixtures.makeSnapshot(measures: [measure], notes: notes),
            expandedMeasures: [measure],
            notePositionOverrides: [:]
        )
        #expect(straight.tuplets.count == 1)

        let swung = try VirgoNotationProjection.resolvedNotation(
            snapshot: try EngravingProjectionFixtures.makeSnapshot(
                measures: [measure], notes: notes, feel: .swing
            ),
            expandedMeasures: [measure],
            notePositionOverrides: [:]
        )
        #expect(swung.tuplets.isEmpty)
    }
}

/// Shared 960-ticks-per-whole-note fixtures for the two engraving
/// projection suites above — the same shapes `VirgoNotationProjectionTests`
/// builds, plus tuplet and control-intent parameters.
private enum EngravingProjectionFixtures {
    static let ticksPerWholeNote = 960

    /// Four-beat 4/4 measure at 960 ticks/whole-note: quarter = 240 ticks.
    static func makeMeasure(index: Int, startTick: Int = 0) -> RhythmMeasure {
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

    static func makeSnapshot(
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

    static func makeNote(
        eventID: Int,
        noteType: NoteType,
        measureIndex: Int,
        localTick: Int,
        interval: NoteInterval,
        durationTicks: Int? = nil,
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
                absoluteTick: measureIndex * 960 + localTick
            ),
            durationTicks: durationTicks ?? ticksPerWholeNote / tickDivisor(of: interval),
            rhythm: NotationRhythm(
                baseInterval: interval,
                tuplet: tupletID == nil ? nil : TupletRatio(actual: 3, normal: 2)
            ),
            tupletID: tupletID
        )
    }

    static func makeRest(
        measureIndex: Int,
        localTick: Int,
        voice: NotationVoice,
        interval: NoteInterval,
        visibility: NotationRestVisibility,
        tupletID: RhythmTupletID? = nil
    ) -> RhythmLayoutRest {
        RhythmLayoutRest(
            position: RhythmEventPosition(
                measureIndex: measureIndex,
                localTick: localTick,
                absoluteTick: measureIndex * 960 + localTick
            ),
            durationTicks: ticksPerWholeNote / tickDivisor(of: interval),
            voice: voice,
            rhythm: NotationRhythm(
                baseInterval: interval,
                tuplet: tupletID == nil ? nil : TupletRatio(actual: 3, normal: 2)
            ),
            visibility: visibility,
            tupletID: tupletID
        )
    }

    static func makeControl(
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
}
