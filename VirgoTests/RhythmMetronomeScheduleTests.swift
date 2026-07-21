//
//  RhythmMetronomeScheduleTests.swift
//  VirgoTests
//

import Testing
@testable import Virgo

@Suite("Rhythm metronome schedule")
struct RhythmMetronomeScheduleTests {
    @Test("simple meters pulse on quarters and accent every group start")
    func simpleMeterPulsePolicy() throws {
        let timeline = makeTimeline(
            ticksPerWholeNote: 8,
            measures: [makeMeasure(index: 0, startTick: 0, durationTicks: 8, meter: .fourFour)]
        )

        let schedule = try RhythmMetronomeSchedule(timeline: timeline, bpm: 120)

        #expect(schedule.pulses.map(\.position.localTick) == [0, 2, 4, 6])
        #expect(schedule.pulses.map(\.offsetSecondsAtOneX) == [0, 0.5, 1, 1.5])
        #expect(schedule.pulses.map(\.beatInMeasure) == [1, 2, 3, 4])
        #expect(schedule.pulses.map(\.accentLevel) == [.downbeat, .group, .group, .group])
    }

    @Test("compound meters pulse on eighths and accent dotted-quarter groups")
    func compoundMeterPulsePolicy() throws {
        for (meter, duration, groupStarts) in [
            (TimeSignature.sixEight, 6, [0, 3]),
            (.nineEight, 9, [0, 3, 6]),
            (.twelveEight, 12, [0, 3, 6, 9])
        ] {
            let timeline = makeTimeline(
                ticksPerWholeNote: 8,
                measures: [makeMeasure(index: 0, startTick: 0, durationTicks: duration, meter: meter)]
            )

            let schedule = try RhythmMetronomeSchedule(timeline: timeline, bpm: 120)

            #expect(schedule.pulses.map(\.position.localTick) == Array(0..<duration))
            #expect(schedule.pulses.filter(\.isAccented).map(\.position.localTick) == groupStarts)
            #expect(schedule.pulses.first?.accentLevel == .downbeat)
            #expect(schedule.pulses.dropFirst().filter { $0.accentLevel == .group }
                .map(\.position.localTick) == Array(groupStarts.dropFirst()))
        }
    }

    @Test("ambiguous seven-eight has seven isochronous pulses and only a downbeat accent")
    func ambiguousSevenEightPulsePolicy() throws {
        let timeline = makeTimeline(
            ticksPerWholeNote: 8,
            measures: [makeMeasure(index: 0, startTick: 0, durationTicks: 7, meter: .sevenEight)]
        )

        let schedule = try RhythmMetronomeSchedule(timeline: timeline, bpm: 120)

        #expect(schedule.pulses.map(\.position.localTick) == Array(0..<7))
        #expect(schedule.pulses.map(\.offsetSecondsAtOneX) == (0..<7).map { Double($0) * 0.25 })
        #expect(schedule.pulses.map(\.accentLevel) == [
            .downbeat, .regular, .regular, .regular, .regular, .regular, .regular
        ])
    }

    @Test("builder keeps standard shortened and extended seven-eight pulse ticks integral")
    func builderSevenEightPulseQuantum() throws {
        let shortened = try MeasureLengthOverride(
            measureIndex: 0,
            ratioToWholeNote: RhythmRatio(numerator: 1, denominator: 3)
        )
        let extended = try MeasureLengthOverride(
            measureIndex: 0,
            ratioToWholeNote: RhythmRatio(numerator: 4, denominator: 3)
        )

        for (override, expectedPulseCount) in [
            (nil, 7),
            (shortened, 3),
            (extended, 11)
        ] as [(MeasureLengthOverride?, Int)] {
            let timeline = try RhythmTimelineBuilder().build(
                metadata: try ChartRhythmMetadata(
                    timeSignature: .sevenEight,
                    feel: .straight,
                    measureLengthOverrides: override.map { [$0] } ?? [],
                    bgmStartAnchor: nil,
                    timingStatus: .valid,
                    diagnostics: []
                ),
                events: [],
                minimumMeasureCount: 1
            )

            #expect(timeline.ticksPerWholeNote.isMultiple(of: 8))
            let schedule = try RhythmMetronomeSchedule(timeline: timeline, bpm: 120)
            #expect(schedule.pulses.count == expectedPulseCount)
            #expect(schedule.pulses.allSatisfy { pulse in
                pulse.position.localTick.isMultiple(of: timeline.ticksPerWholeNote / 8)
            })
        }
    }

    @Test("short and extended bars include an accented residual group without crossing their end")
    func residualGroupPulsePolicy() throws {
        let short = makeMeasure(index: 0, startTick: 0, durationTicks: 5, meter: .fourFour)
        let extended = makeMeasure(index: 1, startTick: 5, durationTicks: 11, meter: .fourFour)
        let timeline = makeTimeline(ticksPerWholeNote: 8, measures: [short, extended])

        let schedule = try RhythmMetronomeSchedule(timeline: timeline, bpm: 120)
        let firstMeasure = schedule.pulses.filter { $0.position.measureIndex == 0 }
        let secondMeasure = schedule.pulses.filter { $0.position.measureIndex == 1 }

        #expect(firstMeasure.map(\.position.localTick) == [0, 2, 4])
        #expect(firstMeasure.last?.accentLevel == .group)
        #expect(secondMeasure.map(\.position.localTick) == [0, 2, 4, 6, 8, 10])
        #expect(secondMeasure.last?.accentLevel == .group)
        #expect(schedule.pulses.allSatisfy { pulse in
            let measure = timeline.measures[pulse.position.measureIndex]
            return pulse.position.localTick < measure.durationTicks
        })
    }

    @Test("pulse preflight accepts 49152 and rejects 49153 before materialization")
    func pulseMaterializationBound() throws {
        let accepted = makeTimeline(
            ticksPerWholeNote: 4,
            measures: [makeMeasure(
                index: 0,
                startTick: 0,
                durationTicks: RhythmLimits.maximumMaterializedRhythmUnitCount,
                meter: .fourFour
            )]
        )
        let rejected = makeTimeline(
            ticksPerWholeNote: 4,
            measures: [makeMeasure(
                index: 0,
                startTick: 0,
                durationTicks: RhythmLimits.maximumMaterializedRhythmUnitCount + 1,
                meter: .fourFour
            )]
        )

        #expect(try RhythmMetronomeSchedule.preflightPulseCount(for: accepted) == 49_152)
        #expect(try RhythmMetronomeSchedule(timeline: accepted, bpm: 120).pulses.count == 49_152)
        #expect(throws: RhythmTimelineBuildError.materializationLimitExceeded) {
            _ = try RhythmMetronomeSchedule.preflightPulseCount(for: rejected)
        }
        do {
            _ = try RhythmMetronomeSchedule(timeline: rejected, bpm: 120)
            Issue.record("Expected the schedule to reject 49,153 pulses")
        } catch let error as RhythmTimelineBuildError {
            #expect(error == .materializationLimitExceeded)
            #expect(error.diagnosticCode == .rhythmMaterializationLimitExceeded)
        }
    }

    @Test("cancellation between lookup and consume cannot advance a replacement")
    func cancellationInvalidatesLookedUpPulse() throws {
        let schedule = try makeVariableBarSchedule()
        let cursor = RhythmScheduleCursor(schedule: schedule, seatedAtOrAfterOffsetSeconds: 0)
        let lookedUp = try #require(cursor.nextCandidate())

        cursor.cancel()

        #expect(cursor.consume(lookedUp) == nil)
        #expect(cursor.nextCandidate() == nil)
    }

    @Test("reseating invalidates old lookup on either side of a shortened barline")
    func reseatAroundShortenedBarline() throws {
        let schedule = try makeVariableBarSchedule()
        let cursor = RhythmScheduleCursor(schedule: schedule, seatedAtOrAfterOffsetSeconds: 0)
        let oldLookup = try #require(cursor.nextCandidate())

        cursor.reseat(atOrAfterOffsetSeconds: 1.499)
        #expect(cursor.consume(oldLookup) == nil)
        let barline = try #require(cursor.nextCandidate())
        #expect(barline.pulse.offsetSecondsAtOneX == 1.5)
        #expect(barline.pulse.position == .init(measureIndex: 1, localTick: 0, absoluteTick: 6))
        #expect(cursor.consume(barline) == barline.pulse)

        cursor.reseat(atOrAfterOffsetSeconds: 1.501)
        let afterBarline = try #require(cursor.nextCandidate())
        #expect(afterBarline.pulse.offsetSecondsAtOneX == 2.0)
        #expect(afterBarline.pulse.position == .init(measureIndex: 1, localTick: 2, absoluteTick: 8))
    }
}

private extension RhythmMetronomeScheduleTests {
    func makeTimeline(ticksPerWholeNote: Int, measures: [RhythmMeasure]) -> RhythmTimeline {
        RhythmTimeline(
            ticksPerWholeNote: ticksPerWholeNote,
            measures: measures,
            eventPositions: [:],
            bgmStartPosition: nil
        )
    }

    func makeMeasure(
        index: Int,
        startTick: Int,
        durationTicks: Int,
        meter: TimeSignature
    ) -> RhythmMeasure {
        let unit = meter == .sixEight || meter == .nineEight || meter == .twelveEight ? 3 : 2
        var groups: [RhythmBeatGroup] = []
        var start = 0
        while start < durationTicks {
            groups.append(.init(
                groupIndex: groups.count,
                startTick: start,
                durationTicks: min(unit, durationTicks - start),
                isResidual: durationTicks - start < unit
            ))
            start += unit
        }
        if meter == .sevenEight {
            groups = [.init(groupIndex: 0, startTick: 0, durationTicks: durationTicks, isResidual: false)]
        }
        return RhythmMeasure(
            measureIndex: index,
            startTick: startTick,
            durationTicks: durationTicks,
            timeSignature: meter,
            beatGroups: groups,
            engravingSupport: .supported
        )
    }

    func makeVariableBarSchedule() throws -> RhythmMetronomeSchedule {
        let short = makeMeasure(index: 0, startTick: 0, durationTicks: 6, meter: .fourFour)
        let ordinary = makeMeasure(index: 1, startTick: 6, durationTicks: 8, meter: .fourFour)
        return try RhythmMetronomeSchedule(
            timeline: makeTimeline(ticksPerWholeNote: 8, measures: [short, ordinary]),
            bpm: 120
        )
    }
}
