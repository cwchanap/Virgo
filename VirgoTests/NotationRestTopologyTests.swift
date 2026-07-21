import Testing
@testable import Virgo

@Suite("Notation Rest Topology Tests")
struct NotationRestTopologyTests {
    private let builder = NotationRestTopologyBuilder()

    private func note(
        tick: Int,
        voice: NotationVoice,
        durationTicks: Int?,
        measure: Int = 0
    ) -> RestTimelineNote {
        RestTimelineNote(
            timeColumn: NotationTimeColumn(
                measureIndex: measure,
                tickWithinMeasure: tick,
                absoluteLayoutTick: measure * 960 + tick
            ),
            voice: voice,
            durationTicks: durationTicks
        )
    }

    private func build(
        _ notes: [RestTimelineNote],
        measures: Int = 1,
        signature: TimeSignature = .fourFour
    ) -> [RestTopologyEvent] {
        builder.build(
            notes: notes,
            totalMeasureCount: measures,
            ticksPerMeasure: 960,
            timeSignature: signature
        )
    }

    private func event(
        voice: NotationVoice,
        start: Int,
        ticks: Int,
        duration: NotationRestDuration,
        visibility: NotationRestVisibility = .printed,
        measure: Int = 0
    ) -> RestTopologyEvent {
        RestTopologyEvent(
            measureIndex: measure,
            voice: voice,
            startTick: start,
            durationTicks: ticks,
            duration: duration,
            visibility: visibility
        )
    }

    @Test("silent measure prints one upper full-measure rest and hides the lower duplicate")
    func bothVoicesSilent() {
        #expect(build([]) == [
            event(voice: .upper, start: 0, ticks: 960, duration: .fullMeasure),
            event(
                voice: .lower,
                start: 0,
                ticks: 960,
                duration: .fullMeasure,
                visibility: .hiddenDuplicate
            )
        ])
    }

    @Test("upper-only onset prints a lower full-measure rest")
    func upperOnlyPrintsLowerCompanion() {
        let result = build([note(tick: 0, voice: .upper, durationTicks: 240)])

        #expect(result.contains {
            $0.voice == .lower && $0.duration == .fullMeasure && $0.isPrinted
        })
        #expect(!result.contains {
            $0.voice == .upper && $0.duration == .fullMeasure
        })
    }

    @Test("lower-only onset prints an upper full-measure rest")
    func lowerOnlyPrintsUpperCompanion() {
        let result = build([note(tick: 0, voice: .lower, durationTicks: 240)])

        #expect(result.contains {
            $0.voice == .upper && $0.duration == .fullMeasure && $0.isPrinted
        })
        #expect(!result.contains {
            $0.voice == .lower && $0.duration == .fullMeasure
        })
    }

    @Test(
        "aligned gaps decompose to every closed internal rest duration",
        arguments: [
            (ticks: 480, duration: NotationRestDuration.half),
            (ticks: 240, duration: NotationRestDuration.quarter),
            (ticks: 120, duration: NotationRestDuration.eighth),
            (ticks: 60, duration: NotationRestDuration.sixteenth),
            (ticks: 30, duration: NotationRestDuration.thirtySecond),
            (ticks: 15, duration: NotationRestDuration.sixtyFourth)
        ]
    )
    func alignedGapUsesExactDuration(ticks: Int, duration: NotationRestDuration) {
        let result = build([
            note(tick: ticks, voice: .upper, durationTicks: 960 - ticks)
        ])

        #expect(result.filter { $0.voice == .upper } == [
            event(voice: .upper, start: 0, ticks: ticks, duration: duration)
        ])
    }

    @Test("rest vocabulary is seven printed cases plus an indeterminate sentinel, with no ordinary full rest")
    func restDurationsAreClosed() {
        #expect(Set(NotationRestDuration.allCases) == [
            .fullMeasure,
            .half,
            .quarter,
            .eighth,
            .sixteenth,
            .thirtySecond,
            .sixtyFourth,
            .indeterminate
        ])
        // The seven printed cases form the closed rest vocabulary.
        let printedCases: Set<NotationRestDuration> = [
            .fullMeasure, .half, .quarter, .eighth, .sixteenth, .thirtySecond, .sixtyFourth
        ]
        #expect(printedCases.isDisjoint(with: [.indeterminate]))
        #expect(NotationRestDuration.allCases.allSatisfy { $0.rawValue != "full" })
    }

    @Test(
        "quarter duration is exact in supported simple meters",
        arguments: [
            (TimeSignature.twoFour, 480),
            (TimeSignature.threeFour, 320),
            (TimeSignature.fourFour, 240),
            (TimeSignature.fiveFour, 192)
        ]
    )
    func quarterDurationIsExact(signature: TimeSignature, expectedTicks: Int) {
        #expect(
            builder.noteDurationTicks(
                for: NoteInterval.quarter,
                ticksPerMeasure: 960,
                timeSignature: signature
            ) == expectedTicks
        )
    }

    @Test(
        "all playable and internal durations convert exactly in supported simple meters",
        arguments: [
            (TimeSignature.twoFour, [1920, 960, 480, 240, 120, 60, 30]),
            (TimeSignature.threeFour, [1280, 640, 320, 160, 80, 40, 20]),
            (TimeSignature.fourFour, [960, 480, 240, 120, 60, 30, 15]),
            (TimeSignature.fiveFour, [768, 384, 192, 96, 48, 24, 12])
        ]
    )
    func exactDurationConversion(signature: TimeSignature, expected: [Int]) {
        let noteDurations = NoteInterval.allCases.map {
            builder.noteDurationTicks(for: $0, ticksPerMeasure: 960, timeSignature: signature)
        }
        let restDurations = NotationRestDuration.allCases
            .filter { $0 != .fullMeasure && $0 != .indeterminate }
            .map { builder.restDurationTicks(for: $0, ticksPerMeasure: 960, timeSignature: signature) }

        #expect(noteDurations == expected.map(Optional.some))
        #expect(restDurations == expected.dropFirst().map(Optional.some))
        #expect(
            builder.restDurationTicks(
                for: .fullMeasure,
                ticksPerMeasure: 960,
                timeSignature: signature
            ) == nil
        )
    }

    @Test("duration conversion rejects compound meters and inexact or invalid grids")
    func durationConversionRejectsUnsupportedInputs() {
        #expect(
            builder.noteDurationTicks(
                for: .quarter,
                ticksPerMeasure: 960,
                timeSignature: .sixEight
            ) == nil
        )
        #expect(
            builder.noteDurationTicks(
                for: .sixtyfourth,
                ticksPerMeasure: 10,
                timeSignature: .fourFour
            ) == nil
        )
        #expect(
            builder.restDurationTicks(
                for: .quarter,
                ticksPerMeasure: 0,
                timeSignature: .fourFour
            ) == nil
        )
    }
}

extension NotationRestTopologyTests {
    @Test("longest exact same-time chord member controls occupancy")
    func longestChordMemberControlsOccupancy() {
        let result = build([
            note(tick: 0, voice: .upper, durationTicks: 120),
            note(tick: 0, voice: .upper, durationTicks: 480),
            note(tick: 720, voice: .upper, durationTicks: 240)
        ])

        #expect(result.filter { $0.voice == .upper } == [
            event(voice: .upper, start: 480, ticks: 240, duration: .quarter)
        ])
    }

    @Test("a later same-voice onset clips prior occupancy near the barline")
    func laterOnsetClipsPriorOccupancy() {
        let result = build([
            note(tick: 0, voice: .upper, durationTicks: 960),
            note(tick: 900, voice: .upper, durationTicks: 60)
        ])

        #expect(result.filter { $0.voice == .upper }.isEmpty)
    }

    @Test("overlapping exact spans merge before gap discovery")
    func overlappingSpansMerge() {
        let result = build([
            note(tick: 0, voice: .upper, durationTicks: 480),
            note(tick: 240, voice: .upper, durationTicks: 480),
            note(tick: 720, voice: .upper, durationTicks: 240)
        ])

        #expect(result.filter { $0.voice == .upper }.isEmpty)
    }

    @Test("upper and lower onsets never clip each other's occupancy")
    func voicesDoNotClipEachOther() {
        let result = build([
            note(tick: 0, voice: .upper, durationTicks: 480),
            note(tick: 240, voice: .lower, durationTicks: 240)
        ])

        #expect(result.filter { $0.voice == .upper } == [
            event(voice: .upper, start: 480, ticks: 480, duration: .half)
        ])
    }

    @Test("a too-small gap becomes one hidden spacing event")
    func tooSmallGapBecomesHiddenSpacing() {
        let result = build([
            note(tick: 10, voice: .upper, durationTicks: 950)
        ])

        #expect(result.filter { $0.voice == .upper } == [
            event(
                voice: .upper,
                start: 0,
                ticks: 10,
                duration: .indeterminate,
                visibility: .hiddenSpacing
            )
        ])
    }

    @Test("an unaligned gap remainder becomes one hidden spacing event")
    func unalignedRemainderBecomesHiddenSpacing() {
        let result = build([
            note(tick: 100, voice: .upper, durationTicks: 860)
        ])

        #expect(result.filter { $0.voice == .upper } == [
            event(voice: .upper, start: 0, ticks: 60, duration: .sixteenth),
            event(voice: .upper, start: 60, ticks: 30, duration: .thirtySecond),
            event(
                voice: .upper,
                start: 90,
                ticks: 10,
                duration: .indeterminate,
                visibility: .hiddenSpacing
            )
        ])
    }

    @Test("nil duration reserves through the next same-voice onset as hidden spacing")
    func uncertainDurationReservesHiddenSpacing() {
        let result = build([
            note(tick: 240, voice: .upper, durationTicks: nil),
            note(tick: 480, voice: .upper, durationTicks: 480)
        ])

        #expect(result.filter { $0.voice == .upper } == [
            event(voice: .upper, start: 0, ticks: 240, duration: .quarter),
            event(
                voice: .upper,
                start: 240,
                ticks: 240,
                duration: .quarter,
                visibility: .hiddenSpacing
            )
        ])
    }

    @Test("a final nil duration reserves through measure end as hidden spacing")
    func finalUncertainDurationReservesThroughMeasureEnd() {
        let result = build([
            note(tick: 240, voice: .upper, durationTicks: nil)
        ])

        #expect(result.filter { $0.voice == .upper } == [
            event(voice: .upper, start: 0, ticks: 240, duration: .quarter),
            event(
                voice: .upper,
                start: 240,
                ticks: 720,
                duration: .indeterminate,
                visibility: .hiddenSpacing
            )
        ])
    }

    @Test("one uncertain member makes its entire same-time chord uncertain")
    func uncertainChordMemberControlsOccupancy() {
        let result = build([
            note(tick: 0, voice: .upper, durationTicks: 120),
            note(tick: 0, voice: .upper, durationTicks: nil),
            note(tick: 480, voice: .upper, durationTicks: 480)
        ])

        #expect(result.filter { $0.voice == .upper } == [
            event(
                voice: .upper,
                start: 0,
                ticks: 480,
                duration: .half,
                visibility: .hiddenSpacing
            )
        ])
    }

    @Test("compound meter keeps silent policy and hides active-voice complements")
    func compoundMeterHidesInternalComplements() {
        let result = build([
            note(tick: 120, voice: .upper, durationTicks: 120)
        ], signature: .sixEight)

        #expect(result == [
            event(
                voice: .upper,
                start: 0,
                ticks: 120,
                duration: .indeterminate,
                visibility: .hiddenSpacing
            ),
            event(
                voice: .upper,
                start: 240,
                ticks: 720,
                duration: .indeterminate,
                visibility: .hiddenSpacing
            ),
            event(voice: .lower, start: 0, ticks: 960, duration: .fullMeasure)
        ])
    }

    @Test("compound meter with uncertain duration extends note span to measure end")
    func compoundMeterUncertainDurationExtendsToMeasureEnd() {
        let result = build([
            note(tick: 120, voice: .upper, durationTicks: nil)
        ], signature: .sixEight)

        #expect(result == [
            event(
                voice: .upper,
                start: 0,
                ticks: 120,
                duration: .indeterminate,
                visibility: .hiddenSpacing
            ),
            event(
                voice: .upper,
                start: 120,
                ticks: 840,
                duration: .indeterminate,
                visibility: .hiddenSpacing
            ),
            event(voice: .lower, start: 0, ticks: 960, duration: .fullMeasure)
        ])
    }
}

extension NotationRestTopologyTests {
    private func resolvedMeasure(
        duration: Int = 960,
        groups: [RhythmBeatGroup]
    ) -> RhythmMeasure {
        RhythmMeasure(
            measureIndex: 0,
            startTick: 0,
            durationTicks: duration,
            timeSignature: .fourFour,
            beatGroups: groups,
            engravingSupport: .supported
        )
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

    @Test("empty multi-measure chart applies the silent policy in every measure")
    func emptyMultiMeasureChartUsesSilentPolicy() {
        #expect(build([], measures: 2) == [
            event(voice: .upper, start: 0, ticks: 960, duration: .fullMeasure, measure: 0),
            event(
                voice: .lower,
                start: 0,
                ticks: 960,
                duration: .fullMeasure,
                visibility: .hiddenDuplicate,
                measure: 0
            ),
            event(voice: .upper, start: 0, ticks: 960, duration: .fullMeasure, measure: 1),
            event(
                voice: .lower,
                start: 0,
                ticks: 960,
                duration: .fullMeasure,
                visibility: .hiddenDuplicate,
                measure: 1
            )
        ])
    }

    @Test("shuffled input produces the same sorted events")
    func shuffledInputIsDeterministic() {
        let source = [
            note(tick: 480, voice: .upper, durationTicks: 240),
            note(tick: 0, voice: .lower, durationTicks: 240),
            note(tick: 120, voice: .upper, durationTicks: 120),
            note(tick: 720, voice: .lower, durationTicks: 240)
        ]

        #expect(build(source) == build([source[2], source[0], source[3], source[1]]))
    }

    @Test("each voice partitions exact occupancy and complements without overlap or holes")
    func exactCoverageIsPartitioned() {
        let result = build([
            note(tick: 120, voice: .upper, durationTicks: 120),
            note(tick: 480, voice: .upper, durationTicks: 240),
            note(tick: 0, voice: .lower, durationTicks: 240),
            note(tick: 360, voice: .lower, durationTicks: 120),
            note(tick: 720, voice: .lower, durationTicks: 240)
        ])
        let occupied: [NotationVoice: [Range<Int>]] = [
            .upper: [120..<240, 480..<720],
            .lower: [0..<240, 360..<480, 720..<960]
        ]

        for voice in [NotationVoice.upper, .lower] {
            var counts = Array(repeating: 0, count: 960)
            for range in occupied[voice, default: []] {
                for tick in range { counts[tick] += 1 }
            }
            for rest in result where rest.voice == voice {
                for tick in rest.startTick..<(rest.startTick + rest.durationTicks) {
                    counts[tick] += 1
                }
            }
            #expect(counts.allSatisfy { $0 == 1 })
        }
    }

    @Test("nonpositive measure or grid inputs return no topology")
    func invalidBuildInputsReturnEmpty() {
        #expect(
            builder.build(
                notes: [],
                totalMeasureCount: 0,
                ticksPerMeasure: 960,
                timeSignature: .fourFour
            ).isEmpty
        )
        #expect(
            builder.build(
                notes: [],
                totalMeasureCount: 1,
                ticksPerMeasure: 0,
                timeSignature: .fourFour
            ).isEmpty
        )
    }
}
