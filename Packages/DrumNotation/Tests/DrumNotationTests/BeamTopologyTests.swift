import Testing
@testable import DrumNotation

/// HPA-166 Task 2: pins the mechanical port of Virgo's proven beam-topology
/// algorithm into DrumNotation. Event-level fixtures mirror the app suite
/// (`VirgoTests/NotationBeamTopologyTests.swift`) one-to-one, minus the
/// pre-format row the package intentionally drops — measures never split
/// across rows, so row identity cannot participate in the grouping key.
@Suite("Beam topology port")
struct BeamTopologyTests {
    /// Shared by the grouping/multi-measure extension in
    /// `BeamTopologyGroupingTests.swift` — helpers are internal so the
    /// split suite file can reach them.
    let builder = NotationBeamTopologyBuilder()

    /// Quarter = 240 ticks at the fixtures' 960 ticks per whole note.
    func event(
        tick: Int,
        levels: Int,
        durationTicks: Int?,
        measure: Int = 0,
        absoluteTick: Int? = nil,
        voice: NotationVoiceRole = .upper,
        direction: NotationStemDirection = .up,
        noteIDs: [Int]
    ) -> BeamTimelineEvent {
        BeamTimelineEvent(
            measureIndex: measure,
            localTick: tick,
            absoluteTick: absoluteTick ?? tick,
            voice: voice,
            stemDirection: direction,
            noteIDs: noteIDs,
            role: .beamable(requiredBeamLevels: levels, durationTicks: durationTicks)
        )
    }

    func event(
        tick: Int,
        levels: Int,
        durationTicks: Int?,
        measure: Int = 0,
        absoluteTick: Int? = nil,
        voice: NotationVoiceRole = .upper,
        direction: NotationStemDirection = .up,
        noteID: Int
    ) -> BeamTimelineEvent {
        event(
            tick: tick,
            levels: levels,
            durationTicks: durationTicks,
            measure: measure,
            absoluteTick: absoluteTick,
            voice: voice,
            direction: direction,
            noteIDs: [noteID]
        )
    }

    func boundary(
        tick: Int,
        noteID: Int,
        direction: NotationStemDirection = .up
    ) -> BeamTimelineEvent {
        BeamTimelineEvent(
            measureIndex: 0,
            localTick: tick,
            absoluteTick: tick,
            voice: .upper,
            stemDirection: direction,
            noteIDs: [noteID],
            role: .boundary
        )
    }

    /// 4/4 at 960 ticks per whole note: four quarter-note beat groups.
    func measure(index: Int = 0, startTick: Int = 0) -> ResolvedMeasure {
        resolvedMeasure(
            index: index,
            startTick: startTick,
            durationTicks: 960,
            meter: NotationMeter(beats: 4, noteValue: 4),
            groups: [(0, 240), (240, 240), (480, 240), (720, 240)]
        )
    }

    func resolvedMeasure(
        index: Int,
        startTick: Int,
        durationTicks: Int,
        meter: NotationMeter,
        groups: [(Int, Int)]
    ) -> ResolvedMeasure {
        ResolvedMeasure(
            index: index,
            startTick: startTick,
            durationTicks: durationTicks,
            meter: meter,
            beatGroups: groups.map { ResolvedBeatGroup(startTick: $0.0, durationTicks: $0.1) }
        )
    }

    func build(_ events: [BeamTimelineEvent]) -> BeamTopologyResult {
        builder.build(events: events, measures: [measure()])
    }

    // MARK: Primary runs and beam levels

    @Test("Four beat groups use exact quarter-note boundaries")
    func fourBeatGroupsUseExactBoundaries() {
        let events = (0..<8).map { index in
            event(tick: index * 120, levels: 1, durationTicks: 120, noteID: index + 1)
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

    @Test("Single eighth alone in a beat produces no beam group (flag, not zero-length beam)")
    func singleEighthAloneProducesNoBeam() {
        let result = build([
            event(tick: 0, levels: 1, durationTicks: 120, noteID: 1)
        ])

        #expect(result.primaryGroups.isEmpty, "A lone beamable note must not form a beam group")
        #expect(result.coveredLevelsByEventIndex.isEmpty, "No coverage so the note receives flags")
    }

    @Test("Four contiguous sixteenths create one two-level primary group")
    func fourSixteenthsCreateTwoLevels() throws {
        let events = (0..<4).map {
            event(tick: $0 * 60, levels: 2, durationTicks: 60, noteID: $0)
        }

        let result = build(events)
        let group = try #require(result.primaryGroups.first)

        #expect(result.primaryGroups.count == 1)
        #expect(group.id == BeamPrimaryGroupID(
            measureIndex: 0,
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

    // MARK: Required parity fixtures — mixed durations and hooks

    @Test("Sixteenth followed by eighth creates a forward secondary hook")
    func mixedDurationsCreateForwardHook() throws {
        let result = build([
            event(tick: 0, levels: 2, durationTicks: 60, noteID: 1),
            event(tick: 60, levels: 1, durationTicks: 120, noteID: 2)
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
            event(tick: 0, levels: 1, durationTicks: 120, noteID: 1),
            event(tick: 120, levels: 2, durationTicks: 60, noteID: 2)
        ])
        let group = try #require(result.primaryGroups.first)

        #expect(group.segments.map(\.kind) == [.full, .backwardHook])
        #expect(group.segments[1].eventIndices == [1])
        #expect(group.segments[1].hookNeighborIndex == 0)
        #expect(result.coveredLevelsByEventIndex == [0: [0], 1: [0, 1]])
    }

    @Test("Mixed thirty-second/sixteenth durations beam shared levels, hook only the deeper one")
    func mixedSixteenthThirtySecondHooks() throws {
        let forward = build([
            event(tick: 0, levels: 3, durationTicks: 30, noteID: 1),
            event(tick: 30, levels: 2, durationTicks: 60, noteID: 2)
        ])
        let forwardGroup = try #require(forward.primaryGroups.first)
        // Levels 0–1 are shared by both durations → full beams; level 2
        // belongs to the thirty-second alone → forward hook.
        #expect(forwardGroup.segments.map(\.level) == [0, 1, 2])
        #expect(forwardGroup.segments.map(\.kind) == [.full, .full, .forwardHook])
        #expect(forwardGroup.segments.map(\.hookNeighborIndex) == [nil, nil, 1])
        #expect(forward.coveredLevelsByEventIndex == [0: [0, 1, 2], 1: [0, 1]])

        let backward = build([
            event(tick: 0, levels: 2, durationTicks: 60, noteID: 1),
            event(tick: 60, levels: 3, durationTicks: 30, noteID: 2)
        ])
        let backwardGroup = try #require(backward.primaryGroups.first)
        #expect(backwardGroup.segments.map(\.level) == [0, 1, 2])
        #expect(backwardGroup.segments.map(\.kind) == [.full, .full, .backwardHook])
        #expect(backwardGroup.segments.map(\.hookNeighborIndex) == [nil, nil, 0])
        #expect(backward.coveredLevelsByEventIndex == [0: [0, 1], 1: [0, 1, 2]])
    }

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
                noteID: index + 1
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
            event(tick: ownerTick - 30, levels: 1, durationTicks: 30, noteID: 1),
            event(tick: ownerTick, levels: 2, durationTicks: 30, noteID: 2),
            event(tick: ownerTick + 30, levels: 1, durationTicks: 30, noteID: 3)
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
            event(tick: 0, levels: levels, durationTicks: duration, noteID: 1),
            event(tick: duration, levels: levels, durationTicks: duration, noteID: 2)
        ])
        let group = try #require(result.primaryGroups.first)

        #expect(group.id.firstAbsoluteTick == 0)
        #expect(group.id.lastAbsoluteTick == duration)
        #expect(group.segments.map(\.level) == expectedLevels)
        #expect(group.segments.allSatisfy {
            $0.kind == .full && $0.eventIndices == [0, 1] && $0.hookNeighborIndex == nil
        })
        #expect(result.coveredLevelsByEventIndex[0] == Set(expectedLevels))
        #expect(result.coveredLevelsByEventIndex[1] == Set(expectedLevels))
    }
}

extension BeamTopologyTests {
    // MARK: Required parity fixtures — grouping boundaries

    @Test("Upper and lower voices at the same ticks form separate primary groups")
    func voiceSeparatesPrimaryGroups() {
        let result = build([
            event(tick: 0, levels: 1, durationTicks: 120, noteID: 1),
            event(tick: 120, levels: 1, durationTicks: 120, noteID: 2),
            event(tick: 0, levels: 1, durationTicks: 120, voice: .lower, noteID: 3),
            event(tick: 120, levels: 1, durationTicks: 120, voice: .lower, noteID: 4)
        ])

        #expect(result.primaryGroups.count == 2)
        #expect(Set(result.primaryGroups.map(\.id.voice)) == [.upper, .lower])
        #expect(
            Set(result.primaryGroups.map(\.eventIndices))
                == Set([[0, 1], [2, 3]])
        )
        #expect(result.coveredLevelsByEventIndex == [
            0: [0], 1: [0], 2: [0], 3: [0]
        ])
    }

    @Test("Opposite stem directions at the same ticks form separate primary groups")
    func stemDirectionSeparatesPrimaryGroups() {
        let result = build([
            event(tick: 0, levels: 1, durationTicks: 120, noteID: 1),
            event(tick: 120, levels: 1, durationTicks: 120, noteID: 2),
            event(tick: 0, levels: 1, durationTicks: 120, direction: .down, noteID: 3),
            event(tick: 120, levels: 1, durationTicks: 120, direction: .down, noteID: 4)
        ])

        #expect(result.primaryGroups.count == 2)
        #expect(Set(result.primaryGroups.map(\.id.stemDirection)) == [.up, .down])
        #expect(
            Set(result.primaryGroups.map(\.eventIndices))
                == Set([[0, 1], [2, 3]])
        )
        #expect(result.coveredLevelsByEventIndex == [
            0: [0], 1: [0], 2: [0], 3: [0]
        ])
    }

    @Test("6/8 beams stay inside the resolved dotted-quarter beat-group boundary")
    func sixEightBeatGroupBoundary() {
        let events = [
            event(tick: 0, levels: 1, durationTicks: 180, noteID: 1),
            event(tick: 180, levels: 1, durationTicks: 180, noteID: 2),
            event(tick: 360, levels: 1, durationTicks: 180, noteID: 3),
            event(tick: 540, levels: 1, durationTicks: 180, noteID: 4)
        ]
        let sixEight = resolvedMeasure(
            index: 0,
            startTick: 0,
            durationTicks: 720,
            meter: NotationMeter(beats: 6, noteValue: 8),
            groups: [(0, 360), (360, 360)]
        )

        let result = builder.build(events: events, measures: [sixEight])

        // Each dotted-quarter group beams its own pair; the events at 180 and
        // 360 never join across the boundary even though durations touch.
        #expect(result.primaryGroups.map(\.id.beatGroupIndex) == [0, 1])
        #expect(result.primaryGroups.map(\.eventIndices) == [[0, 1], [2, 3]])
        #expect(result.coveredLevelsByEventIndex == [
            0: [0], 1: [0], 2: [0], 3: [0]
        ])
    }

    @Test("Supported tuplet members beam contiguously by exact-duration adjacency")
    func tupletExactDurationAdjacency() {
        // A triplet inside one 240-tick beat group: three 80-tick members.
        let events = [0, 80, 160].enumerated().map {
            event(tick: $0.element, levels: 1, durationTicks: 80, noteID: $0.offset + 1)
        }
        let beatMeasure = resolvedMeasure(
            index: 0,
            startTick: 0,
            durationTicks: 240,
            meter: NotationMeter(beats: 4, noteValue: 4),
            groups: [(0, 240)]
        )

        let result = builder.build(events: events, measures: [beatMeasure])

        #expect(result.primaryGroups.map(\.eventIndices) == [[0, 1, 2]])
        #expect(result.coveredLevelsByEventIndex == [0: [0], 1: [0], 2: [0]])
    }

    @Test("A rhythmic gap splits runs inside one beat group")
    func rhythmicGapSplitsRuns() {
        let result = build([
            event(tick: 0, levels: 2, durationTicks: 30, noteID: 1),
            event(tick: 30, levels: 2, durationTicks: 30, noteID: 2),
            event(tick: 120, levels: 1, durationTicks: 60, noteID: 3),
            event(tick: 180, levels: 1, durationTicks: 60, noteID: 4)
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
            event(tick: 0, levels: 2, durationTicks: 60, noteID: 1),
            boundary(tick: 30, noteID: 2),
            event(tick: 60, levels: 2, durationTicks: 60, noteID: 3)
        ])

        #expect(result == .empty)
    }

    @Test("Invalid beamable duration breaks continuity and has no coverage")
    func invalidDurationIsIsolated() {
        let result = build([
            event(tick: 0, levels: 2, durationTicks: nil, noteID: 1),
            event(tick: 60, levels: 2, durationTicks: 60, noteID: 2)
        ])

        #expect(result == .empty)
    }
}
