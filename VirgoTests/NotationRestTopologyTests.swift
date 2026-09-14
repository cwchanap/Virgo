import Testing
@testable import Virgo

/// Coverage for the live timeline-native rest path
/// (`NotationRhythmAnalyzer` + `NotationRestTopologyBuilder.buildExact`);
/// these tests pin its printed/hidden rest decisions and warnings.
@Suite("Notation Rest Topology Tests")
struct NotationRestTopologyTests {
    private let builder = NotationRestTopologyBuilder()

    private func resolvedMeasure(
        duration: Int = 960,
        support: RhythmEngravingSupport = .supported,
        groups: [RhythmBeatGroup]
    ) -> RhythmMeasure {
        RhythmMeasure(
            measureIndex: 0,
            startTick: 0,
            durationTicks: duration,
            timeSignature: .fourFour,
            beatGroups: groups,
            engravingSupport: support
        )
    }

    @Test("warning measures solve exact ordinary gaps without escalating")
    func warningMeasureUsesExactRestGap() throws {
        let measure = resolvedMeasure(
            duration: 240,
            support: .warning([.indeterminateTerminalDuration]),
            groups: [RhythmBeatGroup(groupIndex: 0, startTick: 0, durationTicks: 240, isResidual: false)]
        )
        let result = builder.buildExact(
            notes: [RestTimelineNote(
                position: RhythmEventPosition(measureIndex: 0, localTick: 120, absoluteTick: 120),
                voice: .upper,
                durationTicks: 120,
                rhythm: NotationRhythm(baseInterval: .eighth),
                tupletID: nil
            )],
            measures: [measure],
            reservedTupletRests: [],
            ticksPerWholeNote: 960
        )
        let rest = try #require(result.events.first { $0.voice == .upper && $0.startTick == 0 })

        #expect(rest.durationTicks == 120)
        #expect(rest.duration == .eighth)
        #expect(rest.visibility == .printed)
        #expect(!result.warnings.contains { $0.codes.contains(.ambiguousBeatGrouping) })
    }

    @Test("terminal uncertainty keeps its adjacent complement as hidden spacing")
    func terminalUncertaintyDoesNotInventSixtyFourthRest() throws {
        let measure = resolvedMeasure(
            duration: 64,
            support: .warning([.indeterminateTerminalDuration]),
            groups: [RhythmBeatGroup(groupIndex: 0, startTick: 0, durationTicks: 64, isResidual: false)]
        )
        let result = builder.buildExact(
            notes: [
                RestTimelineNote(
                    position: RhythmEventPosition(measureIndex: 0, localTick: 0, absoluteTick: 0),
                    voice: .upper,
                    durationTicks: 32,
                    rhythm: NotationRhythm(baseInterval: .half),
                    tupletID: nil
                ),
                RestTimelineNote(
                    position: RhythmEventPosition(measureIndex: 0, localTick: 33, absoluteTick: 33),
                    voice: .upper,
                    durationTicks: nil,
                    rhythm: NotationRhythm(
                        baseInterval: .quarter,
                        support: .indeterminate(.indeterminateTerminalDuration)
                    ),
                    tupletID: nil
                )
            ],
            measures: [measure],
            reservedTupletRests: [],
            ticksPerWholeNote: 64
        )
        let complement = try #require(result.events.first {
            $0.voice == .upper && $0.startTick == 32
        })

        #expect(complement.durationTicks == 1)
        #expect(complement.duration == .indeterminate)
        #expect(complement.visibility == .hiddenSpacing)
        #expect(complement.rhythm?.support == .indeterminate(.indeterminateTerminalDuration))
        #expect(!result.events.contains {
            $0.voice == .upper && $0.duration == .sixtyFourth && $0.visibility == .printed
        })
        #expect(!result.warnings.contains { $0.codes.contains(.ambiguousBeatGrouping) })
    }

    @Test("exact rest DP prefers one dotted token inside a resolved group")
    func exactRestDPPrefersDottedToken() throws {
        let measure = resolvedMeasure(
            duration: 360,
            groups: [RhythmBeatGroup(groupIndex: 0, startTick: 0, durationTicks: 360, isResidual: false)]
        )
        let result = builder.buildExact(
            notes: [RestTimelineNote(
                position: RhythmEventPosition(measureIndex: 0, localTick: 180, absoluteTick: 180),
                voice: .upper,
                durationTicks: 180,
                rhythm: NotationRhythm(baseInterval: .eighth, dotCount: 1),
                tupletID: nil
            )],
            measures: [measure],
            reservedTupletRests: [],
            ticksPerWholeNote: 960
        )
        let rest = try #require(result.events.first {
            $0.voice == .upper && $0.startTick == 0
        })

        #expect(rest.durationTicks == 180)
        #expect(rest.rhythm == NotationRhythm(baseInterval: .eighth, dotCount: 1))
        #expect(result.warnings.isEmpty)
    }

    @Test("rest DP never chooses one dotted token across a resolved group boundary")
    func exactRestDPRespectsGroups() {
        let measure = resolvedMeasure(duration: 480, groups: [
            RhythmBeatGroup(groupIndex: 0, startTick: 0, durationTicks: 240, isResidual: false),
            RhythmBeatGroup(groupIndex: 1, startTick: 240, durationTicks: 240, isResidual: false)
        ])
        let result = builder.buildExact(
            notes: [RestTimelineNote(
                position: RhythmEventPosition(measureIndex: 0, localTick: 360, absoluteTick: 360),
                voice: .upper,
                durationTicks: 120,
                rhythm: NotationRhythm(baseInterval: .eighth),
                tupletID: nil
            )],
            measures: [measure],
            reservedTupletRests: [],
            ticksPerWholeNote: 960
        )
        let upper = result.events.filter { $0.voice == .upper }

        #expect(upper.map(\.startTick) == [0, 240])
        #expect(upper.map(\.durationTicks) == [240, 120])
        #expect(upper.map(\.rhythm?.dotCount) == [0, 0])
    }

    @Test("tuplet rests are reserved before binary complement solving")
    func tupletRestReservationPrecedesDP() throws {
        let group = RhythmBeatGroup(groupIndex: 0, startTick: 0, durationTicks: 240, isResidual: false)
        let measure = resolvedMeasure(duration: 240, groups: [group])
        let id = RhythmTupletID(
            measureIndex: 0,
            voice: .upper,
            beatGroupIndex: 0,
            startTick: 0,
            durationTicks: 240
        )
        let tupletRhythm = NotationRhythm(
            baseInterval: .eighth,
            tuplet: TupletRatio(actual: 3, normal: 2)
        )
        let notes = [0, 160].map { tick in
            RestTimelineNote(
                position: RhythmEventPosition(measureIndex: 0, localTick: tick, absoluteTick: tick),
                voice: .upper,
                durationTicks: 80,
                rhythm: tupletRhythm,
                tupletID: id
            )
        }
        let reserved = AnalyzedRhythmRest(
            measureIndex: 0,
            voice: .upper,
            startTick: 80,
            durationTicks: 80,
            rhythm: tupletRhythm,
            tupletID: id,
            visibility: .printed
        )
        let result = builder.buildExact(
            notes: notes,
            measures: [measure],
            reservedTupletRests: [reserved],
            ticksPerWholeNote: 960
        )
        let rest = try #require(result.events.first { $0.voice == .upper && $0.startTick == 80 })

        #expect(rest.durationTicks == 80)
        #expect(rest.tupletID == id)
        #expect(rest.rhythm?.tuplet == TupletRatio(actual: 3, normal: 2))
    }

    @Test("unsupported exact gap emits hidden spacing and one measure warning")
    func unsupportedExactGapWarnsOnce() {
        let measure = resolvedMeasure(
            duration: 240,
            groups: [RhythmBeatGroup(groupIndex: 0, startTick: 0, durationTicks: 240, isResidual: false)]
        )
        let result = builder.buildExact(
            notes: [RestTimelineNote(
                position: RhythmEventPosition(measureIndex: 0, localTick: 10, absoluteTick: 10),
                voice: .upper,
                durationTicks: 230,
                rhythm: NotationRhythm(baseInterval: .quarter),
                tupletID: nil
            )],
            measures: [measure],
            reservedTupletRests: [],
            ticksPerWholeNote: 960
        )

        #expect(result.events.filter { $0.voice == .upper }.count == 1)
        #expect(result.events.first { $0.voice == .upper }?.visibility == .hiddenSpacing)
        #expect(result.warnings == [RhythmMeasureWarning(
            measureIndex: 0,
            codes: [.ambiguousBeatGrouping]
        )])
    }
}
