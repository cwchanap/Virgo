//
//  RhythmMetadataTests.swift
//  VirgoTests
//

import Foundation
import Testing
@testable import Virgo

@Suite("Rhythm metadata")
struct RhythmMetadataTests {
    @Test("ratios reduce, use checked arithmetic, and reject invalid components")
    func ratioValidation() throws {
        let cases = [
            (numerator: 6, denominator: 8, expected: try RhythmRatio(numerator: 3, denominator: 4)),
            (numerator: 12, denominator: 3, expected: try RhythmRatio(numerator: 4, denominator: 1))
        ]

        for testCase in cases {
            #expect(
                try RhythmRatio(numerator: testCase.numerator, denominator: testCase.denominator) == testCase.expected
            )
        }

        let threeQuarters = try RhythmRatio(numerator: 3, denominator: 4)
        let twoThirds = try RhythmRatio(numerator: 2, denominator: 3)
        let threeEighths = try RhythmRatio(numerator: 3, denominator: 8)
        #expect(try threeQuarters.multiplied(by: twoThirds) == RhythmRatio(numerator: 1, denominator: 2))
        #expect(try threeQuarters.divided(by: threeEighths) == RhythmRatio(numerator: 2, denominator: 1))
        #expect(try RhythmRatio.leastCommonMultiple(12, 18) == 36)
        #expect(throws: RhythmMetadataValidationError.self) {
            _ = try RhythmRatio(numerator: 1, denominator: 0)
        }
        #expect(throws: RhythmMetadataValidationError.self) {
            _ = try RhythmRatio(numerator: Int.max, denominator: 1).multiplied(by: .init(numerator: 2, denominator: 1))
        }
    }

    @Test("decoded values use the same validation as construction")
    func decodingRejectsInvalidPayloads() throws {
        let corruptRatio = Data(#"{"numerator":1,"denominator":0}"#.utf8)
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(RhythmRatio.self, from: corruptRatio)
        }

        let unreducedRatio = Data(#"{"numerator":6,"denominator":8}"#.utf8)
        let decoded = try JSONDecoder().decode(RhythmRatio.self, from: unreducedRatio)
        let expected = try RhythmRatio(numerator: 3, denominator: 4)
        #expect(decoded == expected)
    }

    @Test("metadata canonicalizes overrides and validates bounded source anchors")
    func metadataCollectionsAndAnchors() throws {
        let first = try MeasureLengthOverride(measureIndex: 0, ratioToWholeNote: .init(numerator: 3, denominator: 4))
        let second = try MeasureLengthOverride(measureIndex: 2, ratioToWholeNote: .init(numerator: 5, denominator: 4))
        let metadata = try makeValidMetadata(measureLengthOverrides: [second, first])

        #expect(metadata.measureLengthOverrides == [first, second])
        #expect(throws: RhythmMetadataValidationError.self) {
            _ = try makeValidMetadata(measureLengthOverrides: [first, first])
        }
        let validAnchor = try RhythmSourceAnchor(measureIndex: 4_095, gridPosition: 3, gridSize: 4)
        #expect(validAnchor.gridPosition == 3)
        #expect(throws: RhythmMetadataValidationError.self) {
            _ = try RhythmSourceAnchor(measureIndex: 4_096, gridPosition: 0, gridSize: 1)
        }
        #expect(throws: RhythmMetadataValidationError.self) {
            _ = try RhythmSourceAnchor(measureIndex: 0, gridPosition: 4, gridSize: 4)
        }
    }

    @Test("diagnostics accept only their declared severity")
    func diagnosticSeverityAgreement() throws {
        let fatal = try PersistedRhythmDiagnostic(code: .malformedFeel, severity: .timingFatal)
        let materializationLimit = try PersistedRhythmDiagnostic(
            code: .rhythmMaterializationLimitExceeded,
            severity: .timingFatal
        )
        let engraving = try PersistedRhythmDiagnostic(code: .unsupportedDotCount, severity: .engravingOnly)
        #expect(fatal.severity == .timingFatal)
        #expect(materializationLimit.code.rawValue == "rhythmMaterializationLimitExceeded")
        #expect(materializationLimit.severity == .timingFatal)
        #expect(RhythmLimits.maximumMaterializedRhythmUnitCount == 49_152)
        #expect(engraving.severity == .engravingOnly)
        #expect(throws: RhythmMetadataValidationError.self) {
            _ = try PersistedRhythmDiagnostic(code: .malformedFeel, severity: .engravingOnly)
        }
        #expect(throws: RhythmMetadataValidationError.self) {
            _ = try PersistedRhythmDiagnostic(code: .unsupportedDotCount, severity: .timingFatal)
        }
        #expect(throws: RhythmMetadataValidationError.self) {
            _ = try PersistedRhythmDiagnostic(
                code: .rhythmMaterializationLimitExceeded,
                severity: .engravingOnly
            )
        }
    }

    @Test("only version one is supported and valid metadata requires meter and feel")
    func metadataStatusInvariants() throws {
        #expect(try makeValidMetadata().version == 1)
        #expect(throws: RhythmMetadataValidationError.self) {
            _ = try ChartRhythmMetadata(
                version: 2,
                timeSignature: .fourFour,
                feel: .straight,
                measureLengthOverrides: [],
                bgmStartAnchor: nil,
                timingStatus: .valid,
                diagnostics: []
            )
        }
        #expect(throws: RhythmMetadataValidationError.self) {
            _ = try ChartRhythmMetadata(
                version: 1,
                timeSignature: nil,
                feel: .straight,
                measureLengthOverrides: [],
                bgmStartAnchor: nil,
                timingStatus: .valid,
                diagnostics: []
            )
        }

        let fatal = try ChartRhythmMetadata(
            version: 1,
            timeSignature: nil,
            feel: .straight,
            measureLengthOverrides: [],
            bgmStartAnchor: nil,
            timingStatus: .fatal,
            diagnostics: [try PersistedRhythmDiagnostic(code: .malformedTimeSignature, severity: .timingFatal)]
        )
        #expect(fatal.timeSignature == nil)
    }

    @Test("codec is deterministic and preserves valid and fatal metadata")
    func codecRoundTrips() throws {
        let valid = try makeValidMetadata()
        let fatal = try ChartRhythmMetadata(
            version: 1,
            timeSignature: nil,
            feel: .straight,
            measureLengthOverrides: [],
            bgmStartAnchor: nil,
            timingStatus: .fatal,
            diagnostics: [try PersistedRhythmDiagnostic(code: .malformedTimeSignature, severity: .timingFatal)]
        )

        let first = try ChartRhythmMetadataCodec.encode(valid)
        let second = try ChartRhythmMetadataCodec.encode(valid)
        #expect(first == second)
        #expect(ChartRhythmMetadataCodec.decode(first) == .valid(valid))
        #expect(ChartRhythmMetadataCodec.decode(try ChartRhythmMetadataCodec.encode(fatal)) == .valid(fatal))
        #expect(ChartRhythmMetadataCodec.decode(Data("not JSON".utf8)) == .invalid(.inconsistentPersistedTiming))

        let unsupported = unsupportedVersionData()
        #expect(ChartRhythmMetadataCodec.decode(unsupported) == .invalid(.unsupportedMetadataVersion))
    }

    private func makeValidMetadata(
        measureLengthOverrides: [MeasureLengthOverride] = []
    ) throws -> ChartRhythmMetadata {
        let anchor = try RhythmSourceAnchor(measureIndex: 0, gridPosition: 0, gridSize: 16)
        return try ChartRhythmMetadata(
            version: 1,
            timeSignature: .sixEight,
            feel: .straight,
            measureLengthOverrides: measureLengthOverrides,
            bgmStartAnchor: anchor,
            timingStatus: .valid,
            diagnostics: []
        )
    }

    private func unsupportedVersionData() -> Data {
        Data(
            """
            {"version":2,"timeSignature":"4/4","feel":"straight","measureLengthOverrides":[],
            "timingStatus":"valid","diagnostics":[]}
            """.utf8
        )
    }
}
