//
//  RhythmTimelineBuilder.swift
//  Virgo
//

import Foundation
enum RhythmSourceEventKind: String, Hashable, Sendable {
    case note
    case control
}

struct RhythmSourceEventID: Hashable, Sendable {
    let kind: RhythmSourceEventKind
    let stableOrdinal: Int
}

struct RhythmPersistedTimingFields: Hashable, Sendable {
    let measureIndex: Int?
    let absoluteTick: Int?
    let tickWithinMeasure: Int?
    let ticksPerMeasure: Int?

    init(
        measureIndex: Int? = nil,
        absoluteTick: Int? = nil,
        tickWithinMeasure: Int? = nil,
        ticksPerMeasure: Int? = nil
    ) {
        self.measureIndex = measureIndex
        self.absoluteTick = absoluteTick
        self.tickWithinMeasure = tickWithinMeasure
        self.ticksPerMeasure = ticksPerMeasure
    }

    var presentValueCount: Int {
        [measureIndex, absoluteTick, tickWithinMeasure, ticksPerMeasure].compactMap { $0 }.count
    }
}

enum RhythmSourceCoordinate: Hashable, Sendable {
    case dtx(measureIndex: Int, gridPosition: Int, gridSize: Int)
    case manual(measureNumber: Int, measureOffset: Double)
}

struct RhythmSourceEvent: Hashable, Sendable {
    let id: RhythmSourceEventID
    let coordinate: RhythmSourceCoordinate
    let sourceLaneID: String?
    let sourceNoteID: String?
    let drumLaneID: String?
    let persistedTiming: RhythmPersistedTimingFields

    init(
        id: RhythmSourceEventID,
        coordinate: RhythmSourceCoordinate,
        sourceLaneID: String? = nil,
        sourceNoteID: String? = nil,
        drumLaneID: String? = nil,
        persistedTiming: RhythmPersistedTimingFields = .init()
    ) {
        self.id = id
        self.coordinate = coordinate
        self.sourceLaneID = sourceLaneID
        self.sourceNoteID = sourceNoteID
        self.drumLaneID = drumLaneID
        self.persistedTiming = persistedTiming
    }
}

enum RhythmTimelineBuildError: Error, Equatable {
    case invalidMetadata
    case invalidSourceCoordinate
    case invalidManualOffset
    case manualOffsetUnrepresentable
    case measureLimitExceeded
    case arithmeticOverflow
    case resolutionLimitExceeded
    case materializationLimitExceeded
    case inexactProjection
    case cumulativeTickLimitExceeded
    case inconsistentPersistedTiming
    case duplicateSourceEventID

    var diagnosticCode: RhythmDiagnosticCode {
        switch self {
        case .measureLimitExceeded:
            return .measureLimitExceeded
        case .arithmeticOverflow, .cumulativeTickLimitExceeded:
            return .arithmeticOverflow
        case .resolutionLimitExceeded:
            return .resolutionLimitExceeded
        case .materializationLimitExceeded:
            return .rhythmMaterializationLimitExceeded
        case .invalidSourceCoordinate, .invalidManualOffset,
                .manualOffsetUnrepresentable, .inexactProjection:
            return .inexactGridProjection
        case .invalidMetadata, .inconsistentPersistedTiming, .duplicateSourceEventID:
            return .inconsistentPersistedTiming
        }
    }
}

struct RhythmTimelineBuilder: Sendable {
    static let maximumTicksPerWholeNote = 4_096
    static let manualOffsetTolerance = 1e-9

    func build(
        metadata: ChartRhythmMetadata,
        events: [RhythmSourceEvent],
        minimumMeasureCount: Int = 1
    ) throws -> RhythmTimeline {
        guard metadata.timingStatus == .valid,
              let timeSignature = metadata.timeSignature else {
            throw RhythmTimelineBuildError.invalidMetadata
        }
        guard (1...RhythmLimits.maximumMeasureCount).contains(minimumMeasureCount) else {
            throw RhythmTimelineBuildError.measureLimitExceeded
        }
        guard Set(events.map(\.id)).count == events.count else {
            throw RhythmTimelineBuildError.duplicateSourceEventID
        }

        let preparedEvents = try events.map(prepare)
        let measureCount = try resolvedMeasureCount(
            metadata: metadata,
            events: preparedEvents,
            minimumMeasureCount: minimumMeasureCount
        )
        let ratios = try measureRatios(
            metadata: metadata,
            timeSignature: timeSignature,
            measureCount: measureCount
        )
        let resolution = try resolvedTicksPerWholeNote(
            timeSignature: timeSignature,
            measureRatios: ratios,
            events: preparedEvents,
            bgmStartAnchor: metadata.bgmStartAnchor
        )
        let measures = try materializeMeasures(
            timeSignature: timeSignature,
            ratios: ratios,
            ticksPerWholeNote: resolution,
            metadataDiagnostics: metadata.diagnostics
        )
        let eventPositions = try projectEvents(
            preparedEvents,
            into: measures,
            ticksPerWholeNote: resolution
        )
        let bgmStartPosition = try metadata.bgmStartAnchor.map {
            try project(anchor: $0, into: measures)
        }

        return RhythmTimeline(
            ticksPerWholeNote: resolution,
            measures: measures,
            eventPositions: eventPositions,
            bgmStartPosition: bgmStartPosition
        )
    }
}

private extension RhythmTimelineBuilder {
    struct Fraction: Hashable, Sendable {
        let numerator: Int
        let denominator: Int
    }

    enum PreparedCoordinate: Hashable, Sendable {
        case dtx(gridPosition: Int, gridSize: Int)
        case manual(Fraction)
    }

    struct PreparedEvent: Hashable, Sendable {
        let event: RhythmSourceEvent
        let measureIndex: Int
        let coordinate: PreparedCoordinate
    }

    func prepare(_ event: RhythmSourceEvent) throws -> PreparedEvent {
        switch event.coordinate {
        case let .dtx(measureIndex, gridPosition, gridSize):
            guard measureIndex >= 0 else { throw RhythmTimelineBuildError.invalidSourceCoordinate }
            guard measureIndex < RhythmLimits.maximumMeasureCount else {
                throw RhythmTimelineBuildError.measureLimitExceeded
            }
            guard gridSize > 0, gridPosition >= 0, gridPosition < gridSize else {
                throw RhythmTimelineBuildError.invalidSourceCoordinate
            }
            return PreparedEvent(
                event: event,
                measureIndex: measureIndex,
                coordinate: .dtx(gridPosition: gridPosition, gridSize: gridSize)
            )
        case let .manual(measureNumber, measureOffset):
            guard measureNumber >= 1,
                  measureOffset.isFinite,
                  (0...1).contains(measureOffset) else {
                throw RhythmTimelineBuildError.invalidManualOffset
            }
            let rollsForward = measureOffset == 1
            let measureIndex = rollsForward ? measureNumber : measureNumber - 1
            guard measureIndex < RhythmLimits.maximumMeasureCount else {
                throw RhythmTimelineBuildError.measureLimitExceeded
            }
            let fraction = rollsForward
                ? Fraction(numerator: 0, denominator: 1)
                : try rationalize(measureOffset)
            return PreparedEvent(event: event, measureIndex: measureIndex, coordinate: .manual(fraction))
        }
    }

    func rationalize(_ value: Double) throws -> Fraction {
        if value == 0 { return Fraction(numerator: 0, denominator: 1) }
        for denominator in 1...Self.maximumTicksPerWholeNote {
            let scaledValue = value * Double(denominator)
            let candidates = Set([Int(floor(scaledValue)), Int(ceil(scaledValue))]).sorted()
            for numerator in candidates where (0...denominator).contains(numerator) {
                let divisor = greatestCommonDivisor(numerator, denominator)
                let reduced = Fraction(
                    numerator: numerator / divisor,
                    denominator: denominator / divisor
                )
                let difference = abs(
                    Double(reduced.numerator) / Double(reduced.denominator) - value
                )
                if difference <= Self.manualOffsetTolerance {
                    return reduced
                }
            }
        }
        throw RhythmTimelineBuildError.manualOffsetUnrepresentable
    }

    func resolvedMeasureCount(
        metadata: ChartRhythmMetadata,
        events: [PreparedEvent],
        minimumMeasureCount: Int
    ) throws -> Int {
        var maximumMeasureIndex = minimumMeasureCount - 1
        for override in metadata.measureLengthOverrides {
            guard override.measureIndex < RhythmLimits.maximumMeasureCount else {
                throw RhythmTimelineBuildError.measureLimitExceeded
            }
            maximumMeasureIndex = max(maximumMeasureIndex, override.measureIndex)
        }
        for event in events {
            maximumMeasureIndex = max(maximumMeasureIndex, event.measureIndex)
        }
        if let anchor = metadata.bgmStartAnchor {
            guard anchor.measureIndex < RhythmLimits.maximumMeasureCount else {
                throw RhythmTimelineBuildError.measureLimitExceeded
            }
            maximumMeasureIndex = max(maximumMeasureIndex, anchor.measureIndex)
        }
        let measureCount = try checkedAdd(maximumMeasureIndex, 1)
        guard measureCount <= RhythmLimits.maximumMeasureCount else {
            throw RhythmTimelineBuildError.measureLimitExceeded
        }
        return measureCount
    }

    func measureRatios(
        metadata: ChartRhythmMetadata,
        timeSignature: TimeSignature,
        measureCount: Int
    ) throws -> [RhythmRatio] {
        let nominal: RhythmRatio
        do {
            nominal = try RhythmRatio(
                numerator: timeSignature.beatsPerMeasure,
                denominator: timeSignature.noteValue
            )
        } catch {
            throw RhythmTimelineBuildError.arithmeticOverflow
        }
        let overrides = Dictionary(
            uniqueKeysWithValues: metadata.measureLengthOverrides.map {
                ($0.measureIndex, $0.ratioToWholeNote)
            }
        )
        return (0..<measureCount).map { overrides[$0] ?? nominal }
    }

    func resolvedTicksPerWholeNote(
        timeSignature: TimeSignature,
        measureRatios: [RhythmRatio],
        events: [PreparedEvent],
        bgmStartAnchor: RhythmSourceAnchor?
    ) throws -> Int {
        var resolution = 1
        for ratio in measureRatios {
            resolution = try includeGridFactor(gridSize: 1, ratio: ratio, resolution: resolution)
        }
        resolution = try includeMeterProjectionFactor(timeSignature: timeSignature, resolution: resolution)
        for event in events {
            let ratio = measureRatios[event.measureIndex]
            switch event.coordinate {
            case let .dtx(_, gridSize):
                resolution = try includeGridFactor(
                    gridSize: gridSize,
                    ratio: ratio,
                    resolution: resolution
                )
            case let .manual(fraction):
                resolution = try includeManualFactor(
                    fraction: fraction,
                    ratio: ratio,
                    resolution: resolution
                )
            }
        }
        if let anchor = bgmStartAnchor {
            resolution = try includeGridFactor(
                gridSize: anchor.gridSize,
                ratio: measureRatios[anchor.measureIndex],
                resolution: resolution
            )
        }
        return resolution
    }

    func includeGridFactor(gridSize: Int, ratio: RhythmRatio, resolution: Int) throws -> Int {
        let denominatorTimesGrid = try checkedMultiply(ratio.denominator, gridSize)
        let divisor = greatestCommonDivisor(ratio.numerator, denominatorTimesGrid)
        let factor = denominatorTimesGrid / divisor
        return try include(factor: factor, in: resolution)
    }

    func includeManualFactor(
        fraction: Fraction,
        ratio: RhythmRatio,
        resolution: Int
    ) throws -> Int {
        let denominatorProduct = try checkedMultiply(ratio.denominator, fraction.denominator)
        let numeratorProduct = try checkedMultiply(ratio.numerator, fraction.numerator)
        let divisor = greatestCommonDivisor(numeratorProduct, denominatorProduct)
        return try include(factor: denominatorProduct / divisor, in: resolution)
    }

    func includeMeterProjectionFactor(timeSignature: TimeSignature, resolution: Int) throws -> Int {
        switch timeSignature {
        case .sixEight, .sevenEight, .nineEight, .twelveEight:
            return try include(factor: 8, in: resolution)
        case .twoFour, .threeFour, .fourFour, .fiveFour:
            return try include(factor: 4, in: resolution)
        }
    }

    func include(factor: Int, in resolution: Int) throws -> Int {
        let updated = try checkedLeastCommonMultiple(resolution, factor)
        guard updated <= Self.maximumTicksPerWholeNote else {
            throw RhythmTimelineBuildError.resolutionLimitExceeded
        }
        return updated
    }
}

private extension RhythmTimelineBuilder {
    func materializeMeasures(
        timeSignature: TimeSignature,
        ratios: [RhythmRatio],
        ticksPerWholeNote: Int,
        metadataDiagnostics: [PersistedRhythmDiagnostic]
    ) throws -> [RhythmMeasure] {
        let durations = try preflightMeasureDurations(
            ratios: ratios,
            ticksPerWholeNote: ticksPerWholeNote
        )
        _ = try Self.preflightBeatGroupMaterialization(
            timeSignature: timeSignature,
            durationTicksByMeasure: durations,
            ticksPerWholeNote: ticksPerWholeNote
        )

        var measures: [RhythmMeasure] = []
        measures.reserveCapacity(ratios.count)
        var startTick = 0

        for (measureIndex, durationTicks) in durations.enumerated() {
            let support = engravingSupport(
                timeSignature: timeSignature,
                measureIndex: measureIndex,
                metadataDiagnostics: metadataDiagnostics
            )
            measures.append(RhythmMeasure(
                measureIndex: measureIndex,
                startTick: startTick,
                durationTicks: durationTicks,
                timeSignature: timeSignature,
                beatGroups: RhythmBeatGroupBuilder.groups(
                    timeSignature: timeSignature,
                    durationTicks: durationTicks,
                    ticksPerWholeNote: ticksPerWholeNote
                ),
                engravingSupport: support
            ))
            startTick = try checkedAdd(startTick, durationTicks)
        }
        return measures
    }

    func preflightMeasureDurations(
        ratios: [RhythmRatio],
        ticksPerWholeNote: Int
    ) throws -> [Int] {
        var durations: [Int] = []
        durations.reserveCapacity(ratios.count)
        var cumulativeTick = 0

        for ratio in ratios {
            guard ticksPerWholeNote.isMultiple(of: ratio.denominator) else {
                throw RhythmTimelineBuildError.inexactProjection
            }
            let baseTicks = ticksPerWholeNote / ratio.denominator
            let durationTicks = try checkedMultiply(baseTicks, ratio.numerator)
            guard durationTicks > 0 else { throw RhythmTimelineBuildError.inexactProjection }
            cumulativeTick = try checkedAdd(cumulativeTick, durationTicks)
            guard cumulativeTick <= RhythmLimits.maximumExactDoubleInteger else {
                throw RhythmTimelineBuildError.cumulativeTickLimitExceeded
            }
            durations.append(durationTicks)
        }
        return durations
    }

    func engravingSupport(
        timeSignature: TimeSignature,
        measureIndex: Int,
        metadataDiagnostics: [PersistedRhythmDiagnostic]
    ) -> RhythmEngravingSupport {
        var codes = metadataDiagnostics.compactMap { diagnostic -> RhythmDiagnosticCode? in
            guard diagnostic.severity == .engravingOnly,
                  diagnostic.sourceMeasureIndex == nil || diagnostic.sourceMeasureIndex == measureIndex else {
                return nil
            }
            return diagnostic.code
        }
        if timeSignature == .sevenEight {
            codes.append(.ambiguousBeatGrouping)
        }
        let uniqueCodes = Array(Set(codes)).sorted { $0.rawValue < $1.rawValue }
        return uniqueCodes.isEmpty ? .supported : .unsupported(uniqueCodes)
    }

    func projectEvents(
        _ events: [PreparedEvent],
        into measures: [RhythmMeasure],
        ticksPerWholeNote: Int
    ) throws -> [RhythmSourceEventID: RhythmEventPosition] {
        var positions: [RhythmSourceEventID: RhythmEventPosition] = [:]
        positions.reserveCapacity(events.count)
        for event in events {
            let measure = measures[event.measureIndex]
            let localTick = try projectedLocalTick(event.coordinate, measure: measure)
            guard localTick >= 0, localTick < measure.durationTicks else {
                throw RhythmTimelineBuildError.inexactProjection
            }
            let absoluteTick = try checkedAdd(measure.startTick, localTick)
            let position = RhythmEventPosition(
                measureIndex: event.measureIndex,
                localTick: localTick,
                absoluteTick: absoluteTick
            )
            try validatePersistedTiming(event.event.persistedTiming, position: position, measure: measure)
            positions[event.event.id] = position
        }
        return positions
    }

    func projectedLocalTick(
        _ coordinate: PreparedCoordinate,
        measure: RhythmMeasure
    ) throws -> Int {
        switch coordinate {
        case let .dtx(gridPosition, gridSize):
            guard measure.durationTicks.isMultiple(of: gridSize) else {
                throw RhythmTimelineBuildError.inexactProjection
            }
            return try checkedMultiply(measure.durationTicks / gridSize, gridPosition)
        case let .manual(fraction):
            guard measure.durationTicks.isMultiple(of: fraction.denominator) else {
                throw RhythmTimelineBuildError.inexactProjection
            }
            return try checkedMultiply(
                measure.durationTicks / fraction.denominator,
                fraction.numerator
            )
        }
    }

    func validatePersistedTiming(
        _ fields: RhythmPersistedTimingFields,
        position: RhythmEventPosition,
        measure: RhythmMeasure
    ) throws {
        guard fields.presentValueCount > 0 else { return }
        guard fields.presentValueCount == 4,
              fields.measureIndex == position.measureIndex,
              fields.absoluteTick == position.absoluteTick,
              fields.tickWithinMeasure == position.localTick,
              fields.ticksPerMeasure == measure.durationTicks else {
            throw RhythmTimelineBuildError.inconsistentPersistedTiming
        }
    }

    func project(anchor: RhythmSourceAnchor, into measures: [RhythmMeasure]) throws -> RhythmEventPosition {
        let measure = measures[anchor.measureIndex]
        guard measure.durationTicks.isMultiple(of: anchor.gridSize) else {
            throw RhythmTimelineBuildError.inexactProjection
        }
        let localTick = try checkedMultiply(
            measure.durationTicks / anchor.gridSize,
            anchor.gridPosition
        )
        return RhythmEventPosition(
            measureIndex: anchor.measureIndex,
            localTick: localTick,
            absoluteTick: try checkedAdd(measure.startTick, localTick)
        )
    }
}

private extension RhythmTimelineBuilder {
    func checkedAdd(_ left: Int, _ right: Int) throws -> Int {
        let result = left.addingReportingOverflow(right)
        guard !result.overflow else { throw RhythmTimelineBuildError.arithmeticOverflow }
        return result.partialValue
    }

    func checkedMultiply(_ left: Int, _ right: Int) throws -> Int {
        let result = left.multipliedReportingOverflow(by: right)
        guard !result.overflow else { throw RhythmTimelineBuildError.arithmeticOverflow }
        return result.partialValue
    }

    func checkedLeastCommonMultiple(_ left: Int, _ right: Int) throws -> Int {
        guard left > 0, right > 0 else { throw RhythmTimelineBuildError.arithmeticOverflow }
        let divisor = greatestCommonDivisor(left, right)
        // `left / divisor` is plain (unchecked) division by intent: `divisor`
        // is `gcd(left, right)`, which divides `left` exactly, so the quotient
        // is an integer no larger than `left` and cannot overflow (the only
        // `Int` division overflow is `Int.min / -1`, impossible with `left > 0`).
        return try checkedMultiply(left / divisor, right)
    }

    func greatestCommonDivisor(_ left: Int, _ right: Int) -> Int {
        var dividend = left
        var divisor = right
        while divisor != 0 {
            // Plain modulo is safe: the `while divisor != 0` guard ensures the
            // divisor is non-zero on every iteration, and `Int` remainder never
            // overflows (the only division trap is `Int.min % -1`, impossible
            // here because inputs are non-negative per the callers).
            let remainder = dividend % divisor
            dividend = divisor
            divisor = remainder
        }
        return max(dividend, 1)
    }
}
