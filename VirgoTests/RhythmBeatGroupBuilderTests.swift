import Testing
@testable import Virgo

@Suite("Rhythm Beat Group Builder Tests")
struct RhythmBeatGroupBuilderTests {
    @Test("simple meters use quarter-note groups with a residual tail")
    func simpleMeterGroups() {
        let groups = RhythmBeatGroupBuilder.groups(
            timeSignature: .fourFour,
            durationTicks: 1_100,
            ticksPerWholeNote: 960
        )

        #expect(groups.map(\.startTick) == [0, 240, 480, 720, 960])
        #expect(groups.map(\.durationTicks) == [240, 240, 240, 240, 140])
        #expect(groups.map(\.isResidual) == [false, false, false, false, true])
    }

    @Test("compound meters use dotted-quarter groups")
    func compoundMeterGroups() {
        let groups = RhythmBeatGroupBuilder.groups(
            timeSignature: .sixEight,
            durationTicks: 720,
            ticksPerWholeNote: 960
        )

        #expect(groups.map(\.startTick) == [0, 360])
        #expect(groups.map(\.durationTicks) == [360, 360])
        #expect(groups.allSatisfy { !$0.isResidual })
    }

    @Test("seven-eight remains one conservative ambiguous group")
    func sevenEightGroup() {
        let groups = RhythmBeatGroupBuilder.groups(
            timeSignature: .sevenEight,
            durationTicks: 840,
            ticksPerWholeNote: 960
        )

        #expect(groups.count == 1)
        #expect(groups.first?.startTick == 0)
        #expect(groups.first?.durationTicks == 840)
        #expect(groups.first?.isResidual == false)
    }
}
