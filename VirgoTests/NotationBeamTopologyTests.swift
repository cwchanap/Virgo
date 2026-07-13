import Testing
@testable import Virgo

@Suite("Notation Beam Topology Tests")
struct NotationBeamTopologyTests {
    private let builder = NotationBeamTopologyBuilder()

    private func event(
        tick: Int,
        levels: Int,
        durationTicks: Int?,
        measure: Int = 0,
        absoluteTick: Int? = nil,
        row: Int = 0,
        voice: NotationVoice = .upper,
        direction: StemDirection = .up,
        noteHeadIDs: [UInt64]
    ) -> BeamTimelineEvent {
        BeamTimelineEvent(
            timeColumn: NotationTimeColumn(
                measureIndex: measure,
                tickWithinMeasure: tick,
                absoluteLayoutTick: absoluteTick ?? tick
            ),
            row: row,
            voice: voice,
            stemDirection: direction,
            noteHeadIDs: noteHeadIDs,
            role: .beamable(
                requiredBeamLevels: levels,
                durationTicks: durationTicks
            )
        )
    }

    private func event(
        tick: Int,
        levels: Int,
        durationTicks: Int?,
        measure: Int = 0,
        absoluteTick: Int? = nil,
        row: Int = 0,
        voice: NotationVoice = .upper,
        direction: StemDirection = .up,
        noteHeadID: UInt64
    ) -> BeamTimelineEvent {
        event(
            tick: tick,
            levels: levels,
            durationTicks: durationTicks,
            measure: measure,
            absoluteTick: absoluteTick,
            row: row,
            voice: voice,
            direction: direction,
            noteHeadIDs: [noteHeadID]
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

    private func build(_ events: [BeamTimelineEvent]) -> BeamTopologyResult {
        builder.build(
            events: events,
            ticksPerMeasure: 960,
            timeSignature: .fourFour
        )
    }

    @Test("Four beat groups use exact quarter-note boundaries")
    func fourBeatGroupsUseExactBoundaries() {
        let events = (0..<8).map { index in
            event(
                tick: index * 120,
                levels: 1,
                durationTicks: 120,
                noteHeadID: UInt64(index + 1)
            )
        }

        let result = build(events)

        #expect(result.primaryGroups.count == 4)
        #expect(result.primaryGroups.map(\.id.beatGroupIndex) == [0, 1, 2, 3])
        #expect(result.primaryGroups.map(\.id.firstAbsoluteTick) == [0, 240, 480, 720])
        #expect(result.primaryGroups.map(\.id.lastAbsoluteTick) == [120, 360, 600, 840])
        #expect(result.primaryGroups.map(\.eventIndices) == [[0, 1], [2, 3], [4, 5], [6, 7]])
        #expect(result.primaryGroups.flatMap(\.segments).allSatisfy {
            $0.level == 0 && $0.kind == .full && $0.hookNeighborIndex == nil
        })
        for index in events.indices {
            #expect(result.coveredLevelsByEventIndex[index] == [0])
        }
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

        let result = build(events)
        let group = try #require(result.primaryGroups.first)

        #expect(result.primaryGroups.count == 1)
        #expect(group.id == BeamPrimaryGroupID(
            measureIndex: 0,
            row: 0,
            voice: .upper,
            stemDirection: .up,
            beatGroupIndex: 0,
            firstAbsoluteTick: 0,
            lastAbsoluteTick: 180
        ))
        #expect(group.eventIndices == [0, 1, 2, 3])
        #expect(group.segments.map(\.level) == [0, 1])
        #expect(group.segments.allSatisfy {
            $0.kind == .full && $0.hookNeighborIndex == nil
        })
        for index in events.indices {
            #expect(result.coveredLevelsByEventIndex[index] == [0, 1])
        }
    }

    @Test("Sixteenth followed by eighth creates a forward secondary hook")
    func mixedDurationsCreateForwardHook() throws {
        let result = build([
            event(tick: 0, levels: 2, durationTicks: 60, noteHeadID: 1),
            event(tick: 60, levels: 1, durationTicks: 120, noteHeadID: 2)
        ])
        let group = try #require(result.primaryGroups.first)

        #expect(group.segments == [
            BeamTopologySegment(
                level: 0,
                kind: .full,
                eventIndices: [0, 1],
                hookNeighborIndex: nil
            ),
            BeamTopologySegment(
                level: 1,
                kind: .forwardHook,
                eventIndices: [0],
                hookNeighborIndex: 1
            )
        ])
        #expect(result.coveredLevelsByEventIndex == [0: [0, 1], 1: [0]])
    }

    @Test("Eighth followed by sixteenth creates a backward secondary hook")
    func mixedDurationsCreateBackwardHook() throws {
        let result = build([
            event(tick: 0, levels: 1, durationTicks: 120, noteHeadID: 1),
            event(tick: 120, levels: 2, durationTicks: 60, noteHeadID: 2)
        ])
        let group = try #require(result.primaryGroups.first)

        #expect(group.segments.map(\.kind) == [.full, .backwardHook])
        #expect(group.segments[1].eventIndices == [1])
        #expect(group.segments[1].hookNeighborIndex == 0)
        #expect(result.coveredLevelsByEventIndex == [0: [0], 1: [0, 1]])
    }
}

extension NotationBeamTopologyTests {
    @Test(
        "Unequal-distance interior hooks select the nearer primary neighbor",
        arguments: [
            (
                ticks: [0, 30, 90],
                durations: [30, 60, 60],
                expectedKind: BeamSegmentKind.backwardHook,
                expectedNeighbor: 0
            ),
            (
                ticks: [0, 60, 90],
                durations: [60, 30, 60],
                expectedKind: BeamSegmentKind.forwardHook,
                expectedNeighbor: 2
            )
        ]
    )
    func unequalDistanceHooksSelectNearerNeighbor(
        ticks: [Int],
        durations: [Int],
        expectedKind: BeamSegmentKind,
        expectedNeighbor: Int
    ) throws {
        let events = ticks.indices.map { index in
            event(
                tick: ticks[index],
                levels: index == 1 ? 2 : 1,
                durationTicks: durations[index],
                noteHeadID: UInt64(index + 1)
            )
        }
        let result = build(events)
        let group = try #require(result.primaryGroups.first)
        let hook = try #require(group.segments.first { $0.level == 1 })

        #expect(group.eventIndices == [0, 1, 2])
        #expect(hook.kind == expectedKind)
        #expect(hook.eventIndices == [1])
        #expect(hook.hookNeighborIndex == expectedNeighbor)
        #expect(result.coveredLevelsByEventIndex == [0: [0], 1: [0, 1], 2: [0]])
    }

    @Test(
        "Multi-event deep durations create full beams at every required level",
        arguments: [
            (levels: 3, duration: 30, expectedLevels: [0, 1, 2]),
            (levels: 4, duration: 15, expectedLevels: [0, 1, 2, 3])
        ]
    )
    func multiEventDeepDurationsCreateFullLevels(
        levels: Int,
        duration: Int,
        expectedLevels: [Int]
    ) throws {
        let result = build([
            event(tick: 0, levels: levels, durationTicks: duration, noteHeadID: 1),
            event(tick: duration, levels: levels, durationTicks: duration, noteHeadID: 2)
        ])
        let group = try #require(result.primaryGroups.first)

        #expect(group.id.firstAbsoluteTick == 0)
        #expect(group.id.lastAbsoluteTick == duration)
        #expect(group.segments.map(\.level) == expectedLevels)
        #expect(group.segments.allSatisfy {
            $0.kind == .full
                && $0.eventIndices == [0, 1]
                && $0.hookNeighborIndex == nil
        })
        #expect(result.coveredLevelsByEventIndex[0] == Set(expectedLevels))
        #expect(result.coveredLevelsByEventIndex[1] == Set(expectedLevels))
    }

    @Test("A rhythmic gap splits runs inside one beat group")
    func rhythmicGapSplitsRuns() {
        let result = build([
            event(tick: 0, levels: 2, durationTicks: 30, noteHeadID: 1),
            event(tick: 30, levels: 2, durationTicks: 30, noteHeadID: 2),
            event(tick: 120, levels: 1, durationTicks: 60, noteHeadID: 3),
            event(tick: 180, levels: 1, durationTicks: 60, noteHeadID: 4)
        ])

        #expect(result.primaryGroups.map(\.id.beatGroupIndex) == [0, 0])
        #expect(result.primaryGroups.map(\.id.firstAbsoluteTick) == [0, 120])
        #expect(result.primaryGroups.map(\.id.lastAbsoluteTick) == [30, 180])
        #expect(result.primaryGroups.map(\.eventIndices) == [[0, 1], [2, 3]])
        #expect(result.primaryGroups[0].segments.map(\.level) == [0, 1])
        #expect(result.primaryGroups[1].segments.map(\.level) == [0])
        #expect(result.coveredLevelsByEventIndex == [
            0: [0, 1], 1: [0, 1], 2: [0], 3: [0]
        ])
    }

    @Test("Stemless boundary splits an otherwise contiguous run")
    func boundarySplitsRun() {
        let result = build([
            event(tick: 0, levels: 2, durationTicks: 60, noteHeadID: 1),
            boundary(tick: 30, noteHeadID: 2),
            event(tick: 60, levels: 2, durationTicks: 60, noteHeadID: 3)
        ])

        #expect(result == BeamTopologyResult.empty)
    }
}

extension NotationBeamTopologyTests {
    @Test(
        "Measure, row, voice, and direction each separate primary groups",
        arguments: [
            (measure: 1, row: 0, voice: NotationVoice.upper, direction: StemDirection.up),
            (measure: 0, row: 1, voice: NotationVoice.upper, direction: StemDirection.up),
            (measure: 0, row: 0, voice: NotationVoice.lower, direction: StemDirection.up),
            (measure: 0, row: 0, voice: NotationVoice.upper, direction: StemDirection.down)
        ]
    )
    func semanticGroupKeysSeparateRuns(
        measure: Int,
        row: Int,
        voice: NotationVoice,
        direction: StemDirection
    ) {
        let result = build([
            event(tick: 0, levels: 1, durationTicks: 120, noteHeadID: 1),
            event(
                tick: 120,
                levels: 1,
                durationTicks: 120,
                measure: measure,
                absoluteTick: 120,
                row: row,
                voice: voice,
                direction: direction,
                noteHeadID: 2
            )
        ])

        #expect(result.primaryGroups.isEmpty)
        #expect(result.coveredLevelsByEventIndex.isEmpty)
    }

    @Test("One same-time chord event preserves IDs and maximum required levels")
    func sameTimeChordUsesPureEventContract() throws {
        let chord = event(
            tick: 0,
            levels: 4,
            durationTicks: 15,
            noteHeadIDs: [7, 9]
        )
        let events = [
            chord,
            event(tick: 15, levels: 1, durationTicks: 120, noteHeadID: 11)
        ]
        let result = build(events)
        let group = try #require(result.primaryGroups.first)

        #expect(chord.noteHeadIDs == [7, 9])
        #expect(chord.role == .beamable(requiredBeamLevels: 4, durationTicks: 15))
        #expect(group.eventIndices == [0, 1])
        #expect(group.segments.map(\.kind) == [
            .full, .forwardHook, .forwardHook, .forwardHook
        ])
        #expect(group.segments.map(\.eventIndices) == [[0, 1], [0], [0], [0]])
        #expect(group.segments.map(\.hookNeighborIndex) == [nil, 1, 1, 1])
        #expect(result.coveredLevelsByEventIndex == [0: [0, 1, 2, 3], 1: [0]])
    }

    @Test("Invalid and non-quarter-divisible grids return empty topology")
    func invalidGridsReturnEmptyTopology() {
        let events = [
            event(tick: 0, levels: 1, durationTicks: 120, noteHeadID: 1),
            event(tick: 120, levels: 1, durationTicks: 120, noteHeadID: 2)
        ]

        for ticksPerMeasure in [0, -960, 962] {
            let result = builder.build(
                events: events,
                ticksPerMeasure: ticksPerMeasure,
                timeSignature: .fourFour
            )
            #expect(result == .empty)
        }
    }

    @Test("Compound meter (6/8) returns no topology coverage")
    func compoundMeterFallsBack() {
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

    @Test("3/4 simple meter scopes beams to three quarter-note beat groups")
    func threeFourScopesToThreeBeatGroups() {
        // 3/4 with 12-tick baseline: beatTicks = 12 / 3 = 4.
        let events = (0..<6).map { index in
            event(
                tick: index * 2,
                levels: 1,
                durationTicks: 2,
                noteHeadID: UInt64(index + 1)
            )
        }

        let result = builder.build(
            events: events,
            ticksPerMeasure: 12,
            timeSignature: .threeFour
        )

        #expect(result.primaryGroups.count == 3)
        #expect(result.primaryGroups.map(\.id.beatGroupIndex) == [0, 1, 2])
        #expect(result.primaryGroups.map(\.eventIndices) == [[0, 1], [2, 3], [4, 5]])
    }

    @Test("5/4 simple meter scopes beams to five quarter-note beat groups")
    func fiveFourScopesToFiveBeatGroups() {
        // 5/4 with 20-tick baseline: beatTicks = 20 / 5 = 4.
        let events = (0..<10).map { index in
            event(
                tick: index * 2,
                levels: 1,
                durationTicks: 2,
                noteHeadID: UInt64(index + 1)
            )
        }

        let result = builder.build(
            events: events,
            ticksPerMeasure: 20,
            timeSignature: .fiveFour
        )

        #expect(result.primaryGroups.count == 5)
        #expect(result.primaryGroups.map(\.id.beatGroupIndex) == [0, 1, 2, 3, 4])
        #expect(result.primaryGroups.map(\.eventIndices) == [
            [0, 1], [2, 3], [4, 5], [6, 7], [8, 9]
        ])
    }

    @Test("2/4 simple meter scopes beams to two quarter-note beat groups")
    func twoFourScopesToTwoBeatGroups() {
        // 2/4 with 8-tick baseline: beatTicks = 8 / 2 = 4.
        let events = (0..<4).map { index in
            event(
                tick: index * 2,
                levels: 1,
                durationTicks: 2,
                noteHeadID: UInt64(index + 1)
            )
        }

        let result = builder.build(
            events: events,
            ticksPerMeasure: 8,
            timeSignature: .twoFour
        )

        #expect(result.primaryGroups.count == 2)
        #expect(result.primaryGroups.map(\.id.beatGroupIndex) == [0, 1])
        #expect(result.primaryGroups.map(\.eventIndices) == [[0, 1], [2, 3]])
    }

    @Test("Invalid beamable duration breaks continuity and has no coverage")
    func invalidDurationIsIsolated() {
        let result = build([
            event(tick: 0, levels: 2, durationTicks: nil, noteHeadID: 1),
            event(tick: 60, levels: 2, durationTicks: 60, noteHeadID: 2)
        ])

        #expect(result == .empty)
    }
}

extension NotationBeamTopologyTests {
    @Test("Primary groups and coverage contain exactly the same segment memberships")
    func primaryGroupsAndCoverageAreConsistent() {
        let events = [
            event(tick: 0, levels: 4, durationTicks: 15, noteHeadID: 1),
            event(tick: 15, levels: 1, durationTicks: 120, noteHeadID: 2),
            event(tick: 240, levels: 2, durationTicks: 60, noteHeadID: 3),
            event(tick: 300, levels: 2, durationTicks: 60, noteHeadID: 4),
            event(tick: 480, levels: 1, durationTicks: 120, noteHeadID: 5)
        ]
        let result = build(events)
        var expectedCoverage: [Int: Set<Int>] = [:]

        for group in result.primaryGroups {
            #expect(group.eventIndices.count >= 2)
            #expect(group.segments.first?.level == 0)
            #expect(group.segments.first?.eventIndices == group.eventIndices)
            for segment in group.segments {
                let owners = segment.kind == .full
                    ? segment.eventIndices
                    : Array(segment.eventIndices.prefix(1))
                for owner in owners {
                    expectedCoverage[owner, default: []].insert(segment.level)
                }
            }
        }

        #expect(result.primaryGroups.map(\.eventIndices) == [[0, 1], [2, 3]])
        #expect(result.coveredLevelsByEventIndex == expectedCoverage)
        #expect(result.coveredLevelsByEventIndex[4] == nil)
    }

    @Test("Shuffled source input produces deterministic structural topology")
    func shuffledInputProducesDeterministicStructuralTopology() {
        let source = [
            event(tick: 240, levels: 2, durationTicks: 60, noteHeadID: 30),
            event(tick: 60, levels: 1, durationTicks: 120, noteHeadID: 20),
            event(tick: 300, levels: 2, durationTicks: 60, noteHeadID: 40),
            event(tick: 0, levels: 2, durationTicks: 60, noteHeadID: 10)
        ]
        let shuffled = [source[2], source[0], source[3], source[1]]

        let orderedResult = build(source)
        let shuffledResult = build(shuffled)

        // build() sorts internally by group key and event comparator, so the
        // structural shape must match regardless of input ordering. Event
        // indices differ (they reference input positions), so compare
        // order-independent properties: beat group indices, segment kinds,
        // and coverage remapped by noteHeadID.
        #expect(
            shuffledResult.primaryGroups.map(\.id.beatGroupIndex)
                == orderedResult.primaryGroups.map(\.id.beatGroupIndex)
        )
        #expect(
            shuffledResult.primaryGroups.flatMap(\.segments).map(\.kind)
                == orderedResult.primaryGroups.flatMap(\.segments).map(\.kind)
        )

        func coverageByNoteHeadID(
            _ result: BeamTopologyResult,
            events: [BeamTimelineEvent]
        ) -> [UInt64: Set<Int>] {
            var map: [UInt64: Set<Int>] = [:]
            for (index, levels) in result.coveredLevelsByEventIndex {
                guard index < events.count else { continue }
                for id in events[index].noteHeadIDs {
                    map[id, default: []].formUnion(levels)
                }
            }
            return map
        }

        #expect(
            coverageByNoteHeadID(shuffledResult, events: shuffled)
                == coverageByNoteHeadID(orderedResult, events: source)
        )
        #expect(orderedResult.primaryGroups.map(\.id.beatGroupIndex) == [0, 1])
        #expect(orderedResult.primaryGroups.flatMap(\.segments).map(\.kind) == [
            .full, .forwardHook, .full, .full
        ])
        #expect(orderedResult.primaryGroups.flatMap(\.segments).map(\.hookNeighborIndex) == [
            nil, 1, nil, nil
        ])
        #expect(orderedResult.coveredLevelsByEventIndex == [
            0: [0, 1], 1: [0], 2: [0, 1], 3: [0, 1]
        ])
    }

    @Test(
        "Equal-distance interior hooks point toward the beat center",
        arguments: [
            (ownerTick: 60, expected: BeamSegmentKind.forwardHook, neighbor: 2),
            (ownerTick: 180, expected: BeamSegmentKind.backwardHook, neighbor: 0)
        ]
    )
    func equalDistanceHooksUseBeatMidpoint(
        ownerTick: Int,
        expected: BeamSegmentKind,
        neighbor: Int
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
        let result = build(events)
        let hook = try #require(
            result.primaryGroups.first?.segments.first { $0.level == 1 }
        )

        #expect(hook.kind == expected)
        #expect(hook.eventIndices == [1])
        #expect(hook.hookNeighborIndex == neighbor)
        #expect(result.coveredLevelsByEventIndex == [0: [0], 1: [0, 1], 2: [0]])
    }
}
