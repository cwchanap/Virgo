//
//  RhythmTimeline.swift
//  Virgo
//

import Foundation

struct RhythmEventPosition: Hashable, Sendable {
    let measureIndex: Int
    let localTick: Int
    let absoluteTick: Int
}

struct RhythmBeatGroup: Hashable, Sendable {
    let groupIndex: Int
    let startTick: Int
    let durationTicks: Int
    let isResidual: Bool

    var endTick: Int {
        startTick + durationTicks
    }
}

struct RhythmMeasure: Hashable, Sendable {
    let measureIndex: Int
    let startTick: Int
    let durationTicks: Int
    let timeSignature: TimeSignature
    let beatGroups: [RhythmBeatGroup]
    let engravingSupport: RhythmEngravingSupport

    var endTick: Int {
        startTick + durationTicks
    }
}

struct RhythmTimeline: Hashable, Sendable {
    let ticksPerWholeNote: Int
    let measures: [RhythmMeasure]
    let eventPositions: [RhythmSourceEventID: RhythmEventPosition]
    let bgmStartPosition: RhythmEventPosition?

    var endTick: Int {
        measures.last?.endTick ?? 0
    }

    func position(for sourceEventID: RhythmSourceEventID) -> RhythmEventPosition? {
        eventPositions[sourceEventID]
    }

    func position(measureIndex: Int, localTick: Int) -> RhythmEventPosition? {
        guard measures.indices.contains(measureIndex) else { return nil }
        let measure = measures[measureIndex]
        guard (0...measure.durationTicks).contains(localTick) else { return nil }
        let absoluteTick = measure.startTick + localTick
        return position(forAbsoluteTick: absoluteTick)
    }

    func position(forAbsoluteTick absoluteTick: Int) -> RhythmEventPosition? {
        guard let measure = measure(containingAbsoluteTick: absoluteTick) else { return nil }
        return RhythmEventPosition(
            measureIndex: measure.measureIndex,
            localTick: absoluteTick - measure.startTick,
            absoluteTick: absoluteTick
        )
    }

    func measure(at index: Int) -> RhythmMeasure? {
        guard measures.indices.contains(index) else { return nil }
        return measures[index]
    }

    func measure(containingAbsoluteTick absoluteTick: Int) -> RhythmMeasure? {
        guard absoluteTick >= 0, absoluteTick <= endTick, !measures.isEmpty else { return nil }
        if absoluteTick == endTick {
            return measures.last
        }

        var lowerBound = 0
        var upperBound = measures.count
        while lowerBound < upperBound {
            let midpoint = lowerBound + (upperBound - lowerBound) / 2
            if measures[midpoint].startTick <= absoluteTick {
                lowerBound = midpoint + 1
            } else {
                upperBound = midpoint
            }
        }
        let candidateIndex = max(lowerBound - 1, 0)
        let candidate = measures[candidateIndex]
        return absoluteTick < candidate.endTick ? candidate : nil
    }

    func beatGroup(containing position: RhythmEventPosition) -> RhythmBeatGroup? {
        guard let measure = measure(at: position.measureIndex),
              position.absoluteTick == measure.startTick + position.localTick,
              (0...measure.durationTicks).contains(position.localTick) else {
            return nil
        }
        if position.localTick == measure.durationTicks {
            return measure.beatGroups.last
        }
        return measure.beatGroups.first {
            $0.startTick <= position.localTick && position.localTick < $0.endTick
        }
    }

    func beatGroup(containingAbsoluteTick absoluteTick: Int) -> RhythmBeatGroup? {
        guard let position = position(forAbsoluteTick: absoluteTick) else { return nil }
        return beatGroup(containing: position)
    }

    func seconds(forAbsoluteTick absoluteTick: Int, bpm: Double, speed: Double) -> Double? {
        guard absoluteTick >= 0, absoluteTick <= endTick,
              bpm.isFinite, bpm > 0,
              speed.isFinite, speed > 0 else {
            return nil
        }
        return Double(absoluteTick) / Double(ticksPerWholeNote) * (240.0 / bpm) / speed
    }

    func seconds(for position: RhythmEventPosition, bpm: Double, speed: Double) -> Double? {
        guard self.position(
            measureIndex: position.measureIndex,
            localTick: position.localTick
        ) == position else {
            return nil
        }
        return seconds(forAbsoluteTick: position.absoluteTick, bpm: bpm, speed: speed)
    }

    func eventTargetSeconds(
        for sourceEventID: RhythmSourceEventID,
        bpm: Double,
        speed: Double
    ) -> Double? {
        guard let position = position(for: sourceEventID) else { return nil }
        return seconds(for: position, bpm: bpm, speed: speed)
    }

    func continuousTick(forSeconds seconds: Double, bpm: Double, speed: Double) -> Double? {
        guard seconds.isFinite, seconds >= 0,
              bpm.isFinite, bpm > 0,
              speed.isFinite, speed > 0 else {
            return nil
        }
        let tick = seconds * Double(ticksPerWholeNote) * bpm * speed / 240.0
        guard tick.isFinite, tick >= 0, tick <= Double(endTick) else { return nil }
        return tick
    }

    func endSeconds(bpm: Double, speed: Double) -> Double? {
        seconds(forAbsoluteTick: endTick, bpm: bpm, speed: speed)
    }
}

struct CanonicalNormalizedTiming: Hashable, Sendable {
    let measureIndex: Int
    let absoluteTick: Int
    let tickWithinMeasure: Int
    let ticksPerMeasure: Int
}

struct CanonicalRhythmProjection: Hashable, Sendable {
    let ticksPerWholeNote: Int
    let positionsBySourceEventID: [RhythmSourceEventID: RhythmEventPosition]
    let durationTicksByMeasureIndex: [Int: Int]

    init(timeline: RhythmTimeline) {
        ticksPerWholeNote = timeline.ticksPerWholeNote
        positionsBySourceEventID = timeline.eventPositions
        durationTicksByMeasureIndex = Dictionary(
            uniqueKeysWithValues: timeline.measures.map { ($0.measureIndex, $0.durationTicks) }
        )
    }

    func position(for sourceEventID: RhythmSourceEventID) -> RhythmEventPosition? {
        positionsBySourceEventID[sourceEventID]
    }

    func normalizedTiming(for sourceEventID: RhythmSourceEventID) -> CanonicalNormalizedTiming? {
        guard let position = position(for: sourceEventID),
              let ticksPerMeasure = durationTicksByMeasureIndex[position.measureIndex] else {
            return nil
        }
        return CanonicalNormalizedTiming(
            measureIndex: position.measureIndex,
            absoluteTick: position.absoluteTick,
            tickWithinMeasure: position.localTick,
            ticksPerMeasure: ticksPerMeasure
        )
    }
}

extension RhythmTimelineBuilder {
    static func preflightBeatGroupMaterialization(
        timeSignature: TimeSignature,
        durationTicksByMeasure: [Int],
        ticksPerWholeNote: Int
    ) throws -> Int {
        guard ticksPerWholeNote > 0,
              durationTicksByMeasure.allSatisfy({ $0 > 0 }) else {
            throw RhythmTimelineBuildError.inexactProjection
        }

        let groupDuration = try standardBeatGroupDuration(
            for: timeSignature,
            ticksPerWholeNote: ticksPerWholeNote
        )

        var totalCount = 0
        for durationTicks in durationTicksByMeasure {
            let measureCount = try beatGroupCount(
                durationTicks: durationTicks,
                groupDuration: groupDuration
            )
            let result = totalCount.addingReportingOverflow(measureCount)
            guard !result.overflow else { throw RhythmTimelineBuildError.arithmeticOverflow }
            guard result.partialValue <= RhythmLimits.maximumMaterializedRhythmUnitCount else {
                throw RhythmTimelineBuildError.materializationLimitExceeded
            }
            totalCount = result.partialValue
        }
        return totalCount
    }

    private static func standardBeatGroupDuration(
        for timeSignature: TimeSignature,
        ticksPerWholeNote: Int
    ) throws -> Int? {
        switch timeSignature {
        case .sixEight, .nineEight, .twelveEight:
            guard ticksPerWholeNote.isMultiple(of: 8) else {
                throw RhythmTimelineBuildError.inexactProjection
            }
            return ticksPerWholeNote / 8 * 3
        case .twoFour, .threeFour, .fourFour, .fiveFour:
            guard ticksPerWholeNote.isMultiple(of: 4) else {
                throw RhythmTimelineBuildError.inexactProjection
            }
            return ticksPerWholeNote / 4
        case .sevenEight:
            return nil
        }
    }

    private static func beatGroupCount(
        durationTicks: Int,
        groupDuration: Int?
    ) throws -> Int {
        guard let groupDuration else { return 1 }
        let completeCount = durationTicks / groupDuration
        let residualCount = durationTicks.isMultiple(of: groupDuration) ? 0 : 1
        let result = completeCount.addingReportingOverflow(residualCount)
        guard !result.overflow else { throw RhythmTimelineBuildError.arithmeticOverflow }
        return result.partialValue
    }
}
