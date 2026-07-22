//
//  RhythmMetadata.swift
//  Virgo
//

import Foundation

enum RhythmLimits {
    static let maximumMeasureCount = 4_096
    static let maximumMaterializedRhythmUnitCount = 49_152
    static let maximumExactDoubleInteger = 9_007_199_254_740_991
}

enum RhythmMetadataValidationError: Error, Equatable {
    case nonpositiveRatio
    case invalidTicksPerWholeNote
    case arithmeticOverflow
    case invalidMeasureIndex
    case invalidGridSize
    case invalidGridPosition
    case invalidDiagnosticLocation
    case mismatchedDiagnosticSeverity
    case duplicateMeasureLengthOverride
    case unsupportedMetadataVersion
    case missingTimeSignature
    case missingFeel
}

/// Immutable note payload crossing from resolved/analyzed rhythm into layout.
/// The SwiftData model itself deliberately stays outside this boundary.
struct RhythmLayoutNote: Hashable {
    let eventID: RhythmEventID
    let sourceObjectID: ObjectIdentifier
    let sourceLaneID: String?
    let sourceChipID: String?
    let noteType: NoteType
    let position: RhythmEventPosition
    let durationTicks: Int
    let rhythm: NotationRhythm
    let tupletID: RhythmTupletID?
}

/// Immutable control payload crossing from resolved rhythm into layout.
struct RhythmLayoutControl: Hashable {
    let eventID: RhythmEventID
    let event: NotationControlEvent
    let position: RhythmEventPosition
}

/// Immutable rest payload crossing from semantic rhythm analysis into layout.
struct RhythmLayoutRest: Hashable {
    let position: RhythmEventPosition
    let durationTicks: Int
    let voice: NotationVoice
    let rhythm: NotationRhythm
    let visibility: NotationRestVisibility
    let tupletID: RhythmTupletID?
}

/// Self-contained timing boundary consumed by timeline-native layout.
struct RhythmLayoutSnapshot: Hashable {
    let ticksPerWholeNote: Int
    let measures: [RhythmMeasure]
    let notes: [RhythmLayoutNote]
    let controls: [RhythmLayoutControl]
    let rests: [RhythmLayoutRest]
    let feel: RhythmicFeel
    let diagnostics: [PersistedRhythmDiagnostic]

    init(
        ticksPerWholeNote: Int,
        measures: [RhythmMeasure],
        notes: [RhythmLayoutNote],
        controls: [RhythmLayoutControl],
        rests: [RhythmLayoutRest],
        feel: RhythmicFeel,
        diagnostics: [PersistedRhythmDiagnostic] = []
    ) throws {
        guard ticksPerWholeNote > 0 else {
            throw RhythmMetadataValidationError.invalidTicksPerWholeNote
        }
        self.ticksPerWholeNote = ticksPerWholeNote
        self.measures = measures
        self.notes = notes
        self.controls = controls
        self.rests = rests
        self.feel = feel
        self.diagnostics = Self.stableDiagnostics(diagnostics)
    }

    func logDiagnostics(_ log: (String) -> Void = { Logger.warning($0) }) {
        for diagnostic in diagnostics {
            log(RhythmDiagnosticPresentation(code: diagnostic.code).logMessage(
                sourceMeasureIndex: diagnostic.sourceMeasureIndex,
                sourceLineNumber: diagnostic.sourceLineNumber
            ))
        }
    }

    private static func stableDiagnostics(
        _ diagnostics: [PersistedRhythmDiagnostic]
    ) -> [PersistedRhythmDiagnostic] {
        Array(Set(diagnostics)).sorted { left, right in
            let leftMeasure = left.sourceMeasureIndex ?? -1
            let rightMeasure = right.sourceMeasureIndex ?? -1
            if leftMeasure != rightMeasure { return leftMeasure < rightMeasure }
            let leftLine = left.sourceLineNumber ?? -1
            let rightLine = right.sourceLineNumber ?? -1
            if leftLine != rightLine { return leftLine < rightLine }
            return left.code.rawValue < right.code.rawValue
        }
    }
}

struct RhythmRatio: Codable, Hashable, Sendable {
    let numerator: Int
    let denominator: Int

    init(numerator: Int, denominator: Int) throws {
        guard numerator > 0, denominator > 0 else {
            throw RhythmMetadataValidationError.nonpositiveRatio
        }
        let divisor = try Self.greatestCommonDivisor(numerator, denominator)
        self.numerator = try Self.checkedDivision(numerator, by: divisor)
        self.denominator = try Self.checkedDivision(denominator, by: divisor)
    }

    func multiplied(by other: Self) throws -> Self {
        let numerator = try Self.checkedMultiplication(numerator, by: other.numerator)
        let denominator = try Self.checkedMultiplication(denominator, by: other.denominator)
        return try Self(numerator: numerator, denominator: denominator)
    }

    func divided(by other: Self) throws -> Self {
        let numerator = try Self.checkedMultiplication(numerator, by: other.denominator)
        let denominator = try Self.checkedMultiplication(denominator, by: other.numerator)
        return try Self(numerator: numerator, denominator: denominator)
    }

    static func leastCommonMultiple(_ left: Int, _ right: Int) throws -> Int {
        guard left > 0, right > 0 else {
            throw RhythmMetadataValidationError.nonpositiveRatio
        }
        let divisor = try greatestCommonDivisor(left, right)
        let reducedLeft = try checkedDivision(left, by: divisor)
        return try checkedMultiplication(reducedLeft, by: right)
    }

    init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let numerator = try container.decode(Int.self, forKey: .numerator)
            let denominator = try container.decode(Int.self, forKey: .denominator)
            try self.init(numerator: numerator, denominator: denominator)
        } catch let error as DecodingError {
            throw error
        } catch {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Invalid rhythm ratio", underlyingError: error)
            )
        }
    }

    private static func greatestCommonDivisor(_ left: Int, _ right: Int) throws -> Int {
        var dividend = left
        var divisor = right
        while divisor != 0 {
            let quotient = try checkedDivision(dividend, by: divisor)
            let product = try checkedMultiplication(quotient, by: divisor)
            let remainder = try checkedSubtraction(dividend, product)
            dividend = divisor
            divisor = remainder
        }
        return dividend
    }

    fileprivate static func checkedAddition(_ left: Int, _ right: Int) throws -> Int {
        let result = left.addingReportingOverflow(right)
        guard !result.overflow else { throw RhythmMetadataValidationError.arithmeticOverflow }
        return result.partialValue
    }

    private static func checkedSubtraction(_ left: Int, _ right: Int) throws -> Int {
        let result = left.subtractingReportingOverflow(right)
        guard !result.overflow else { throw RhythmMetadataValidationError.arithmeticOverflow }
        return result.partialValue
    }

    private static func checkedMultiplication(_ left: Int, by right: Int) throws -> Int {
        let result = left.multipliedReportingOverflow(by: right)
        guard !result.overflow else { throw RhythmMetadataValidationError.arithmeticOverflow }
        return result.partialValue
    }

    private static func checkedDivision(_ left: Int, by right: Int) throws -> Int {
        let result = left.dividedReportingOverflow(by: right)
        guard !result.overflow else { throw RhythmMetadataValidationError.arithmeticOverflow }
        return result.partialValue
    }
}

enum RhythmicFeel: String, Codable, CaseIterable, Hashable, Sendable {
    case straight
    case swing
    case shuffle
}

struct MeasureLengthOverride: Codable, Hashable, Sendable {
    let measureIndex: Int
    let ratioToWholeNote: RhythmRatio

    init(measureIndex: Int, ratioToWholeNote: RhythmRatio) throws {
        guard (0..<RhythmLimits.maximumMeasureCount).contains(measureIndex) else {
            throw RhythmMetadataValidationError.invalidMeasureIndex
        }
        self.measureIndex = measureIndex
        self.ratioToWholeNote = ratioToWholeNote
    }

    init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(
                measureIndex: container.decode(Int.self, forKey: .measureIndex),
                ratioToWholeNote: container.decode(RhythmRatio.self, forKey: .ratioToWholeNote)
            )
        } catch let error as DecodingError {
            throw error
        } catch {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Invalid measure-length override",
                    underlyingError: error
                )
            )
        }
    }
}

struct RhythmSourceAnchor: Codable, Hashable, Sendable {
    let measureIndex: Int
    let gridPosition: Int
    let gridSize: Int

    init(measureIndex: Int, gridPosition: Int, gridSize: Int) throws {
        guard (0..<RhythmLimits.maximumMeasureCount).contains(measureIndex) else {
            throw RhythmMetadataValidationError.invalidMeasureIndex
        }
        guard gridSize > 0 else { throw RhythmMetadataValidationError.invalidGridSize }
        let exclusiveGridPosition = try RhythmRatio.checkedAddition(gridPosition, 1)
        guard gridPosition >= 0, exclusiveGridPosition <= gridSize else {
            throw RhythmMetadataValidationError.invalidGridPosition
        }
        self.measureIndex = measureIndex
        self.gridPosition = gridPosition
        self.gridSize = gridSize
    }

    init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(
                measureIndex: container.decode(Int.self, forKey: .measureIndex),
                gridPosition: container.decode(Int.self, forKey: .gridPosition),
                gridSize: container.decode(Int.self, forKey: .gridSize)
            )
        } catch let error as DecodingError {
            throw error
        } catch {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Invalid rhythm source anchor",
                    underlyingError: error
                )
            )
        }
    }
}

enum RhythmTimingStatus: String, Codable, Hashable, Sendable {
    case valid
    case fatal
}

enum RhythmTimelineAvailability: Hashable, Sendable {
    case valid
    case legacy
    case fatal
}

enum RhythmDiagnosticSeverity: String, Codable, Hashable, Sendable {
    case timingFatal
    case engravingOnly
}

enum RhythmDiagnosticCode: String, Codable, CaseIterable, Hashable, Sendable {
    case malformedTimeSignature
    case unsupportedTimeSignature
    case malformedFeel
    case unsupportedFeel
    case malformedMeasureLength
    case nonpositiveMeasureLength
    case conflictingTimeSignature
    case conflictingFeel
    case conflictingMeasureLength
    case unsupportedMetadataVersion
    case arithmeticOverflow
    case resolutionLimitExceeded
    case measureLimitExceeded
    case rhythmMaterializationLimitExceeded
    case inexactGridProjection
    case inconsistentPersistedTiming
    case unsupportedTupletRatio
    case unsupportedDotCount
    case incompleteTuplet
    case ambiguousBeatGrouping
    case indeterminateTerminalDuration
    case manualTimelineUnavailable

    var requiredSeverity: RhythmDiagnosticSeverity {
        switch self {
        case .unsupportedTupletRatio,
                .unsupportedDotCount,
                .incompleteTuplet,
                .ambiguousBeatGrouping,
                .indeterminateTerminalDuration,
                .manualTimelineUnavailable:
            return .engravingOnly
        default:
            return .timingFatal
        }
    }
}

struct PersistedRhythmDiagnostic: Codable, Hashable, Sendable {
    let code: RhythmDiagnosticCode
    let severity: RhythmDiagnosticSeverity
    let sourceMeasureIndex: Int?
    let sourceLineNumber: Int?

    init(
        code: RhythmDiagnosticCode,
        severity: RhythmDiagnosticSeverity,
        sourceMeasureIndex: Int? = nil,
        sourceLineNumber: Int? = nil
    ) throws {
        guard code.requiredSeverity == severity else {
            throw RhythmMetadataValidationError.mismatchedDiagnosticSeverity
        }
        if let sourceMeasureIndex,
           !(0..<RhythmLimits.maximumMeasureCount).contains(sourceMeasureIndex) {
            throw RhythmMetadataValidationError.invalidDiagnosticLocation
        }
        if let sourceLineNumber, sourceLineNumber <= 0 {
            throw RhythmMetadataValidationError.invalidDiagnosticLocation
        }
        self.code = code
        self.severity = severity
        self.sourceMeasureIndex = sourceMeasureIndex
        self.sourceLineNumber = sourceLineNumber
    }

    init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(
                code: container.decode(RhythmDiagnosticCode.self, forKey: .code),
                severity: container.decode(RhythmDiagnosticSeverity.self, forKey: .severity),
                sourceMeasureIndex: container.decodeIfPresent(Int.self, forKey: .sourceMeasureIndex),
                sourceLineNumber: container.decodeIfPresent(Int.self, forKey: .sourceLineNumber)
            )
        } catch let error as DecodingError {
            throw error
        } catch {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Invalid rhythm diagnostic",
                    underlyingError: error
                )
            )
        }
    }
}

enum RhythmSemanticSupport: Hashable, Sendable {
    case supported
    case indeterminate(RhythmDiagnosticCode)
    case unsupported(RhythmDiagnosticCode)
}

enum RhythmEngravingSupport: Hashable, Sendable {
    case supported
    case unsupported([RhythmDiagnosticCode])
}

struct ChartRhythmMetadata: Codable, Hashable, Sendable {
    static let supportedVersion = 1

    let version: Int
    let timeSignature: TimeSignature?
    let feel: RhythmicFeel?
    let measureLengthOverrides: [MeasureLengthOverride]
    let bgmStartAnchor: RhythmSourceAnchor?
    let timingStatus: RhythmTimingStatus
    let diagnostics: [PersistedRhythmDiagnostic]

    init(
        version: Int = Self.supportedVersion,
        timeSignature: TimeSignature?,
        feel: RhythmicFeel?,
        measureLengthOverrides: [MeasureLengthOverride],
        bgmStartAnchor: RhythmSourceAnchor?,
        timingStatus: RhythmTimingStatus,
        diagnostics: [PersistedRhythmDiagnostic]
    ) throws {
        guard version == Self.supportedVersion else {
            throw RhythmMetadataValidationError.unsupportedMetadataVersion
        }
        if timingStatus == .valid {
            guard timeSignature != nil else { throw RhythmMetadataValidationError.missingTimeSignature }
            guard feel != nil else { throw RhythmMetadataValidationError.missingFeel }
        }

        let sortedOverrides = measureLengthOverrides.sorted {
            $0.measureIndex < $1.measureIndex
        }
        let overrideIndexesAreUnique = zip(sortedOverrides, sortedOverrides.dropFirst()).allSatisfy {
            $0.measureIndex != $1.measureIndex
        }
        guard overrideIndexesAreUnique else {
            throw RhythmMetadataValidationError.duplicateMeasureLengthOverride
        }

        self.version = version
        self.timeSignature = timeSignature
        self.feel = feel
        self.measureLengthOverrides = sortedOverrides
        self.bgmStartAnchor = bgmStartAnchor
        self.timingStatus = timingStatus
        self.diagnostics = diagnostics
    }

    init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(
                version: container.decode(Int.self, forKey: .version),
                timeSignature: container.decodeIfPresent(TimeSignature.self, forKey: .timeSignature),
                feel: container.decodeIfPresent(RhythmicFeel.self, forKey: .feel),
                measureLengthOverrides: container.decode([MeasureLengthOverride].self, forKey: .measureLengthOverrides),
                bgmStartAnchor: container.decodeIfPresent(RhythmSourceAnchor.self, forKey: .bgmStartAnchor),
                timingStatus: container.decode(RhythmTimingStatus.self, forKey: .timingStatus),
                diagnostics: container.decode([PersistedRhythmDiagnostic].self, forKey: .diagnostics)
            )
        } catch let error as DecodingError {
            throw error
        } catch {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Invalid chart rhythm metadata",
                    underlyingError: error
                )
            )
        }
    }
}

enum ChartRhythmMetadataLoadState: Hashable, Sendable {
    case missing
    case valid(ChartRhythmMetadata)
    case invalid(RhythmDiagnosticCode)
}

enum ChartRhythmMetadataCodec {
    static func encode(_ metadata: ChartRhythmMetadata) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(metadata)
    }

    static func decode(_ data: Data) -> ChartRhythmMetadataLoadState {
        do {
            return .valid(try JSONDecoder().decode(ChartRhythmMetadata.self, from: data))
        } catch {
            return .invalid(diagnosticCode(for: data, error: error))
        }
    }

    private static func diagnosticCode(for data: Data, error: Error) -> RhythmDiagnosticCode {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let values = object as? [String: Any],
              let version = values["version"] as? Int,
              version != ChartRhythmMetadata.supportedVersion else {
            return .inconsistentPersistedTiming
        }
        return .unsupportedMetadataVersion
    }
}
