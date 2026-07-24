//
//  RhythmMetronomeSchedule.swift
//  Virgo
//

import Foundation

enum RhythmMetronomeAccentLevel: Int, Hashable, Sendable {
    case regular
    case group
    case downbeat
}

struct RhythmMetronomePulse: Hashable, Sendable {
    let position: RhythmEventPosition
    let offsetSecondsAtOneX: Double
    let beatInMeasure: Int
    let accentLevel: RhythmMetronomeAccentLevel

    var isAccented: Bool {
        accentLevel != .regular
    }
}

struct RhythmMetronomeSchedule: Hashable, Sendable {
    let pulses: [RhythmMetronomePulse]

    init(timeline: RhythmTimeline, bpm: Double) throws {
        let pulseCount = try Self.preflight(timeline: timeline, bpm: bpm)
        var pulses: [RhythmMetronomePulse] = []
        pulses.reserveCapacity(pulseCount)

        for measure in timeline.measures {
            let pulseUnitTicks = try Self.pulseUnitTicks(
                for: measure.timeSignature,
                ticksPerWholeNote: timeline.ticksPerWholeNote
            )
            let accentedGroupStarts = Set(measure.beatGroups.lazy.map(\.startTick))
            var localTick = 0
            var beatInMeasure = 1
            while localTick < measure.durationTicks {
                let absoluteTick = measure.startTick.addingReportingOverflow(localTick)
                guard !absoluteTick.overflow,
                      let offset = timeline.seconds(
                        forAbsoluteTick: absoluteTick.partialValue,
                        bpm: bpm,
                        speed: 1
                      ) else {
                    throw RhythmTimelineBuildError.arithmeticOverflow
                }
                pulses.append(RhythmMetronomePulse(
                    position: RhythmEventPosition(
                        measureIndex: measure.measureIndex,
                        localTick: localTick,
                        absoluteTick: absoluteTick.partialValue
                    ),
                    offsetSecondsAtOneX: offset,
                    beatInMeasure: beatInMeasure,
                    accentLevel: Self.accentLevel(
                        localTick: localTick,
                        meter: measure.timeSignature,
                        accentedGroupStarts: accentedGroupStarts
                    )
                ))

                let nextTick = localTick.addingReportingOverflow(pulseUnitTicks)
                guard !nextTick.overflow else {
                    throw RhythmTimelineBuildError.arithmeticOverflow
                }
                localTick = nextTick.partialValue
                beatInMeasure += 1
            }
        }

        self.pulses = pulses
    }

    /// Validates every schedule prerequisite and returns its exact pulse count
    /// without allocating the pulse array. Library readiness and runtime schedule
    /// construction share this boundary so a chart cannot be selectable but
    /// impossible to start.
    static func preflight(timeline: RhythmTimeline, bpm: Double) throws -> Int {
        guard bpm.isFinite, bpm > 0 else {
            throw RhythmTimelineBuildError.invalidMetadata
        }
        return try preflightPulseCount(for: timeline)
    }

    static func preflightPulseCount(for timeline: RhythmTimeline) throws -> Int {
        guard timeline.ticksPerWholeNote > 0 else {
            throw RhythmTimelineBuildError.inexactProjection
        }

        var totalCount = 0
        for measure in timeline.measures {
            guard measure.durationTicks > 0 else {
                throw RhythmTimelineBuildError.inexactProjection
            }
            let unitTicks = try pulseUnitTicks(
                for: measure.timeSignature,
                ticksPerWholeNote: timeline.ticksPerWholeNote
            )
            let completePulses = measure.durationTicks / unitTicks
            let residualPulse = measure.durationTicks % unitTicks == 0 ? 0 : 1
            let measureCount = completePulses.addingReportingOverflow(residualPulse)
            guard !measureCount.overflow else {
                throw RhythmTimelineBuildError.arithmeticOverflow
            }
            let newTotal = totalCount.addingReportingOverflow(measureCount.partialValue)
            guard !newTotal.overflow else {
                throw RhythmTimelineBuildError.arithmeticOverflow
            }
            guard newTotal.partialValue <= RhythmLimits.maximumMaterializedRhythmUnitCount else {
                throw RhythmTimelineBuildError.materializationLimitExceeded
            }
            totalCount = newTotal.partialValue
        }
        return totalCount
    }

    // Pulse unit selection. Simple meters (x/4) pulse on each quarter; the
    // divisor is the whole-note denominator so one pulse spans one beat.
    //
    // Compound meters (x/8) intentionally pulse on each eighth note rather than
    // the conventional dotted-quarter beat. This is a deliberate choice for a
    // practice metronome: eighth subdivision keeps every pulse audible while
    // practicing, and `accentLevel` marks the dotted-quarter group starts
    // (via `accentedGroupStarts`) so the downbeat/group accents still convey
    // the compound grouping. Switching to dotted-quarter pulses would halve
    // the click density and is a behavior change, not a fix.
    private static func pulseUnitTicks(
        for meter: TimeSignature,
        ticksPerWholeNote: Int
    ) throws -> Int {
        let divisor: Int
        switch meter {
        case .sixEight, .sevenEight, .nineEight, .twelveEight:
            divisor = 8
        case .twoFour, .threeFour, .fourFour, .fiveFour:
            divisor = 4
        }
        guard ticksPerWholeNote.isMultiple(of: divisor) else {
            throw RhythmTimelineBuildError.inexactProjection
        }
        return ticksPerWholeNote / divisor
    }

    private static func accentLevel(
        localTick: Int,
        meter: TimeSignature,
        accentedGroupStarts: Set<Int>
    ) -> RhythmMetronomeAccentLevel {
        if localTick == 0 {
            return .downbeat
        }
        if meter != .sevenEight, accentedGroupStarts.contains(localTick) {
            return .group
        }
        return .regular
    }
}

final class RhythmScheduleCursor: @unchecked Sendable {
    struct Candidate: Hashable, Sendable {
        let pulse: RhythmMetronomePulse
        fileprivate let pulseIndex: Int
        fileprivate let generation: UInt64
    }

    private let lock = NSLock()
    private let schedule: RhythmMetronomeSchedule
    private var nextPulseIndex: Int
    private var generation: UInt64 = 0
    private var isActive = true

    init(schedule: RhythmMetronomeSchedule, seatedAtOrAfterOffsetSeconds offsetSeconds: Double) {
        self.schedule = schedule
        self.nextPulseIndex = Self.firstPulseIndex(
            in: schedule.pulses,
            atOrAfterOffsetSeconds: offsetSeconds
        )
    }

    func nextCandidate() -> Candidate? {
        lock.lock()
        defer { lock.unlock() }
        guard isActive, schedule.pulses.indices.contains(nextPulseIndex) else { return nil }
        return Candidate(
            pulse: schedule.pulses[nextPulseIndex],
            pulseIndex: nextPulseIndex,
            generation: generation
        )
    }

    func consume(_ candidate: Candidate) -> RhythmMetronomePulse? {
        lock.lock()
        defer { lock.unlock() }
        guard isActive,
              candidate.generation == generation,
              candidate.pulseIndex == nextPulseIndex,
              schedule.pulses.indices.contains(nextPulseIndex),
              schedule.pulses[nextPulseIndex] == candidate.pulse else {
            return nil
        }
        nextPulseIndex += 1
        return candidate.pulse
    }

    func reseat(atOrAfterOffsetSeconds offsetSeconds: Double) {
        lock.lock()
        generation &+= 1
        nextPulseIndex = Self.firstPulseIndex(
            in: schedule.pulses,
            atOrAfterOffsetSeconds: offsetSeconds
        )
        isActive = true
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        generation &+= 1
        isActive = false
        lock.unlock()
    }

    private static func firstPulseIndex(
        in pulses: [RhythmMetronomePulse],
        atOrAfterOffsetSeconds offsetSeconds: Double
    ) -> Int {
        guard offsetSeconds.isFinite else {
            return offsetSeconds == -.infinity ? 0 : pulses.endIndex
        }
        let target = max(0, offsetSeconds)
        var lowerBound = pulses.startIndex
        var upperBound = pulses.endIndex
        while lowerBound < upperBound {
            let midpoint = lowerBound + (upperBound - lowerBound) / 2
            if pulses[midpoint].offsetSecondsAtOneX < target {
                lowerBound = midpoint + 1
            } else {
                upperBound = midpoint
            }
        }
        return lowerBound
    }
}
