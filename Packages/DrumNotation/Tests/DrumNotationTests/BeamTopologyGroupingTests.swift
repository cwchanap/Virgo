import Testing
@testable import DrumNotation

/// Multi-measure, chord-event, ordering and measure-validation cases of the
/// beam-topology port — split from `BeamTopologyTests.swift` for the file
/// length limit; the shared event/measure helpers live there.
extension BeamTopologyTests {
    // MARK: Multi-measure, chords, ordering and validation

    @Test("Independent groups in adjacent measures form separate primary groups")
    func adjacentMeasuresFormIndependentGroups() throws {
        let events = [
            event(tick: 0, levels: 1, durationTicks: 120, measure: 0, absoluteTick: 0, noteID: 1),
            event(tick: 120, levels: 1, durationTicks: 120, measure: 0, absoluteTick: 120, noteID: 2),
            event(tick: 0, levels: 1, durationTicks: 120, measure: 1, absoluteTick: 960, noteID: 3),
            event(tick: 120, levels: 1, durationTicks: 120, measure: 1, absoluteTick: 1080, noteID: 4)
        ]
        let result = builder.build(events: events, measures: [
            measure(index: 0, startTick: 0),
            measure(index: 1, startTick: 960)
        ])

        #expect(result.primaryGroups.count == 2)
        #expect(result.primaryGroups.map(\.id.measureIndex) == [0, 1])
        #expect(result.primaryGroups.map(\.eventIndices) == [[0, 1], [2, 3]])
        #expect(result.primaryGroups.map(\.id.firstAbsoluteTick) == [0, 960])
        #expect(result.primaryGroups.map(\.id.lastAbsoluteTick) == [120, 1080])
        for group in result.primaryGroups {
            #expect(group.segments.count == 1)
            #expect(group.segments.first?.level == 0)
            #expect(group.segments.first?.kind == .full)
        }
        #expect(result.coveredLevelsByEventIndex == [
            0: [0], 1: [0], 2: [0], 3: [0]
        ])
    }

    @Test("One same-time chord event preserves IDs and maximum required levels")
    func sameTimeChordUsesPureEventContract() throws {
        let chord = event(tick: 0, levels: 4, durationTicks: 15, noteIDs: [7, 9])
        let events = [
            chord,
            event(tick: 15, levels: 1, durationTicks: 120, noteID: 11)
        ]
        let result = build(events)
        let group = try #require(result.primaryGroups.first)

        #expect(chord.noteIDs == [7, 9])
        #expect(chord.role == .beamable(requiredBeamLevels: 4, durationTicks: 15))
        #expect(group.eventIndices == [0, 1])
        #expect(group.segments.map(\.kind) == [
            .full, .forwardHook, .forwardHook, .forwardHook
        ])
        #expect(group.segments.map(\.eventIndices) == [[0, 1], [0], [0], [0]])
        #expect(group.segments.map(\.hookNeighborIndex) == [nil, 1, 1, 1])
        #expect(result.coveredLevelsByEventIndex == [0: [0, 1, 2, 3], 1: [0]])
    }

    @Test("Co-located onsets in one stem group never fabricate a beam")
    func coLocatedOnsetsNeverBeam() {
        // Two events share measure/voice/direction/beat-group AND absolute
        // tick — the (absoluteTick, noteIDs) event sort is the only ordering
        // left between them, and strict duration adjacency still cannot
        // connect them into a run.
        let result = build([
            event(tick: 0, levels: 1, durationTicks: 120, noteID: 2),
            event(tick: 0, levels: 1, durationTicks: 120, noteID: 1)
        ])

        #expect(result == .empty)
    }

    @Test("Malformed measures return the empty topology")
    func malformedMeasuresReturnEmpty() {
        let events = [
            event(tick: 0, levels: 1, durationTicks: 120, noteID: 1),
            event(tick: 120, levels: 1, durationTicks: 120, noteID: 2)
        ]
        // Non-contiguous beat groups fail the builder's measure validation.
        let broken = resolvedMeasure(
            index: 0,
            startTick: 0,
            durationTicks: 960,
            meter: NotationMeter(beats: 4, noteValue: 4),
            groups: [(0, 240), (480, 480)]
        )
        // A group overshooting the measure end also fails.
        let overshot = resolvedMeasure(
            index: 0,
            startTick: 0,
            durationTicks: 960,
            meter: NotationMeter(beats: 4, noteValue: 4),
            groups: [(0, 240), (240, 800)]
        )
        // No measures at all fails too.
        #expect(builder.build(events: events, measures: [broken]) == .empty)
        #expect(builder.build(events: events, measures: [overshot]) == .empty)
        #expect(builder.build(events: events, measures: []) == .empty)
    }

    @Test("Primary groups and coverage contain exactly the same segment memberships")
    func primaryGroupsAndCoverageAreConsistent() {
        let events = [
            event(tick: 0, levels: 4, durationTicks: 15, noteID: 1),
            event(tick: 15, levels: 1, durationTicks: 120, noteID: 2),
            event(tick: 240, levels: 2, durationTicks: 60, noteID: 3),
            event(tick: 300, levels: 2, durationTicks: 60, noteID: 4),
            event(tick: 480, levels: 1, durationTicks: 120, noteID: 5)
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
            event(tick: 240, levels: 2, durationTicks: 60, noteID: 30),
            event(tick: 60, levels: 1, durationTicks: 120, noteID: 20),
            event(tick: 300, levels: 2, durationTicks: 60, noteID: 40),
            event(tick: 0, levels: 2, durationTicks: 60, noteID: 10)
        ]
        let shuffled = [source[2], source[0], source[3], source[1]]

        let orderedResult = build(source)
        let shuffledResult = build(shuffled)

        // Structural shape must match regardless of input ordering; event
        // indices differ, so compare order-independent properties: beat group
        // indices, segment kinds, and coverage remapped by noteID.
        #expect(
            shuffledResult.primaryGroups.map(\.id.beatGroupIndex)
                == orderedResult.primaryGroups.map(\.id.beatGroupIndex)
        )
        #expect(
            shuffledResult.primaryGroups.flatMap(\.segments).map(\.kind)
                == orderedResult.primaryGroups.flatMap(\.segments).map(\.kind)
        )

        func coverageByNoteID(
            _ result: BeamTopologyResult,
            events: [BeamTimelineEvent]
        ) -> [Int: Set<Int>] {
            var map: [Int: Set<Int>] = [:]
            for (index, levels) in result.coveredLevelsByEventIndex {
                guard index < events.count else { continue }
                for id in events[index].noteIDs {
                    map[id, default: []].formUnion(levels)
                }
            }
            return map
        }

        #expect(
            coverageByNoteID(shuffledResult, events: shuffled)
                == coverageByNoteID(orderedResult, events: source)
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
}
