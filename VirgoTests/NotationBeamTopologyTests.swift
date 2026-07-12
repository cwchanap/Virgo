import Testing
@testable import Virgo

@Suite("Notation Beam Topology Tests")
struct NotationBeamTopologyTests {
    private let builder = NotationBeamTopologyBuilder()

    private func event(
        tick: Int,
        levels: Int,
        durationTicks: Int?,
        row: Int = 0,
        voice: NotationVoice = .upper,
        direction: StemDirection = .up,
        noteHeadID: UInt64
    ) -> BeamTimelineEvent {
        BeamTimelineEvent(
            timeColumn: NotationTimeColumn(
                measureIndex: 0,
                tickWithinMeasure: tick,
                absoluteLayoutTick: tick
            ),
            row: row,
            voice: voice,
            stemDirection: direction,
            noteHeadIDs: [noteHeadID],
            role: .beamable(
                requiredBeamLevels: levels,
                durationTicks: durationTicks
            )
        )
    }

    private func boundary(
        tick: Int,
        noteHeadID: UInt64,
        direction: StemDirection = .up
    ) -> BeamTimelineEvent {
        BeamTimelineEvent(
            timeColumn: NotationTimeColumn(
                measureIndex: 0,
                tickWithinMeasure: tick,
                absoluteLayoutTick: tick
            ),
            row: 0,
            voice: .upper,
            stemDirection: direction,
            noteHeadIDs: [noteHeadID],
            role: .boundary
        )
    }

    @Test("Four contiguous sixteenths create one two-level primary group")
    func fourSixteenthsCreateTwoLevels() throws {
        let events = (0..<4).map {
            event(
                tick: $0 * 60,
                levels: 2,
                durationTicks: 60,
                noteHeadID: UInt64($0)
            )
        }

        let result = builder.build(
            events: events,
            ticksPerMeasure: 960,
            timeSignature: .fourFour
        )

        let group = try #require(result.primaryGroups.first)
        #expect(result.primaryGroups.count == 1)
        #expect(group.eventIndices == [0, 1, 2, 3])
        #expect(group.segments.map(\.level) == [0, 1])
        #expect(group.segments.allSatisfy { $0.kind == .full })
        for index in 0..<4 {
            #expect(result.coveredLevelsByEventIndex[index] == [0, 1])
        }
    }

    @Test("Sixteenth followed by eighth creates a forward secondary hook")
    func mixedDurationsCreateForwardHook() throws {
        let events = [
            event(tick: 0, levels: 2, durationTicks: 60, noteHeadID: 1),
            event(tick: 60, levels: 1, durationTicks: 120, noteHeadID: 2)
        ]

        let result = builder.build(
            events: events,
            ticksPerMeasure: 960,
            timeSignature: .fourFour
        )
        let group = try #require(result.primaryGroups.first)
        let hook = try #require(group.segments.first { $0.level == 1 })

        #expect(hook.kind == .forwardHook)
        #expect(hook.eventIndices == [0])
        #expect(hook.hookNeighborIndex == 1)
        #expect(result.coveredLevelsByEventIndex[0] == [0, 1])
        #expect(result.coveredLevelsByEventIndex[1] == [0])
    }

    @Test("Stemless boundary splits an otherwise contiguous run")
    func boundarySplitsRun() {
        let events = [
            event(tick: 0, levels: 2, durationTicks: 60, noteHeadID: 1),
            boundary(tick: 30, noteHeadID: 2),
            event(tick: 60, levels: 2, durationTicks: 60, noteHeadID: 3)
        ]

        let result = builder.build(
            events: events,
            ticksPerMeasure: 960,
            timeSignature: .fourFour
        )

        #expect(result == BeamTopologyResult.empty)
    }

    @Test("Direction is a primary grouping boundary")
    func directionSeparatesGroups() {
        let events = [
            event(tick: 0, levels: 1, durationTicks: 120, noteHeadID: 1),
            event(
                tick: 120,
                levels: 1,
                durationTicks: 120,
                direction: .down,
                noteHeadID: 2
            )
        ]

        let result = builder.build(
            events: events,
            ticksPerMeasure: 960,
            timeSignature: .fourFour
        )

        #expect(result == BeamTopologyResult.empty)
    }

    @Test("Unsupported meter returns no topology coverage")
    func unsupportedMeterFallsBack() {
        let events = [
            event(tick: 0, levels: 1, durationTicks: 120, noteHeadID: 1),
            event(tick: 120, levels: 1, durationTicks: 120, noteHeadID: 2)
        ]

        let result = builder.build(
            events: events,
            ticksPerMeasure: 960,
            timeSignature: .sixEight
        )

        #expect(result == BeamTopologyResult.empty)
    }

    @Test("isolated invalid beamable event has no coverage")
    func invalidDurationIsIsolated() {
        let events = [
            event(tick: 0, levels: 2, durationTicks: nil, noteHeadID: 1),
            event(tick: 60, levels: 2, durationTicks: 60, noteHeadID: 2)
        ]
        let result = builder.build(
            events: events,
            ticksPerMeasure: 960,
            timeSignature: .fourFour
        )
        #expect(result == .empty)
    }

    @Test("thirty-second and sixty-fourth levels are completely covered")
    func deepBeamLevelsAreCovered() throws {
        let events = [
            event(tick: 0, levels: 4, durationTicks: 15, noteHeadID: 1),
            event(tick: 15, levels: 1, durationTicks: 120, noteHeadID: 2)
        ]
        let result = builder.build(
            events: events,
            ticksPerMeasure: 960,
            timeSignature: .fourFour
        )
        let segments = try #require(result.primaryGroups.first?.segments)
        #expect(segments.map(\.level) == [0, 1, 2, 3])
        #expect(segments.dropFirst().allSatisfy { $0.kind == .forwardHook })
        #expect(result.coveredLevelsByEventIndex[0] == [0, 1, 2, 3])
    }

    @Test(
        "equal-distance interior hooks point toward the beat center",
        arguments: [
            (ownerTick: 60, expected: BeamSegmentKind.forwardHook),
            (ownerTick: 180, expected: BeamSegmentKind.backwardHook)
        ]
    )
    func equalDistanceHooksUseBeatMidpoint(
        ownerTick: Int,
        expected: BeamSegmentKind
    ) throws {
        let events = [
            event(
                tick: ownerTick - 30,
                levels: 1,
                durationTicks: 30,
                noteHeadID: 1
            ),
            event(
                tick: ownerTick,
                levels: 2,
                durationTicks: 30,
                noteHeadID: 2
            ),
            event(
                tick: ownerTick + 30,
                levels: 1,
                durationTicks: 30,
                noteHeadID: 3
            )
        ]
        let result = builder.build(
            events: events,
            ticksPerMeasure: 960,
            timeSignature: .fourFour
        )
        let hook = try #require(
            result.primaryGroups.first?.segments.first { $0.level == 1 }
        )
        #expect(hook.kind == expected)
    }
}
