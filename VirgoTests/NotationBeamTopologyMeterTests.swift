import Testing
@testable import Virgo

extension NotationBeamTopologyTests {
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
}
