//
//  DTXRhythmParserTests.swift
//  VirgoTests
//

import Foundation
import Testing
@testable import Virgo

@Suite("DTX rhythm parser")
struct DTXRhythmParserTests {
    @Test("rhythm directives and values are case-insensitive")
    func parsesCaseInsensitiveDirectives() throws {
        let chart = try parse("""
        #virgo_time_signature: 6/8
        #ViRgO_FeEl: sWiNg
        """)

        #expect(chart.rhythmMetadata.timeSignature == .sixEight)
        #expect(chart.rhythmMetadata.feel == .swing)
        #expect(chart.rhythmMetadata.timingStatus == .valid)
        #expect(chart.rhythmDiagnostics.isEmpty)

        let nominalDuration = try RhythmRatio(
            numerator: chart.rhythmMetadata.timeSignature?.beatsPerMeasure ?? 0,
            denominator: chart.rhythmMetadata.timeSignature?.noteValue ?? 0
        )
        let threeQuarters = try RhythmRatio(numerator: 3, denominator: 4)
        #expect(nominalDuration == threeQuarters)
    }

    @Test("channel 02 is an exact measure ratio, not a chip array")
    func parsesMeasureLengthExactly() throws {
        let chart = try parse("""
        #VIRGO_TIME_SIGNATURE: 6/8
        #00002: 0.75
        #00011: 01000100
        """)

        let expectedOverride = try MeasureLengthOverride(
            measureIndex: 0,
            ratioToWholeNote: .init(numerator: 3, denominator: 4)
        )
        #expect(chart.rhythmMetadata.measureLengthOverrides == [expectedOverride])
        #expect(chart.rhythmMetadata.timingStatus == .valid)
        #expect(chart.notes.count == 2)
        #expect(chart.notes.allSatisfy { $0.laneID != "02" })
    }

    @Test("channel 02 overrides nominal meter duration without changing the meter")
    func measureLengthOverridesNominalMeter() throws {
        let chart = try parse("""
        #VIRGO_TIME_SIGNATURE: 6/8
        #01202: 1.5
        """)

        #expect(chart.rhythmMetadata.timeSignature == .sixEight)
        let expectedOverride = try MeasureLengthOverride(
            measureIndex: 12,
            ratioToWholeNote: .init(numerator: 3, denominator: 2)
        )
        #expect(chart.rhythmMetadata.measureLengthOverrides == [expectedOverride])
    }

    @Test("absent rhythm directives use valid 4/4 straight defaults")
    func usesDefaultsOnlyWhenDirectivesAreAbsent() throws {
        let chart = try parse("")

        #expect(chart.rhythmMetadata.timeSignature == .fourFour)
        #expect(chart.rhythmMetadata.feel == .straight)
        #expect(chart.rhythmMetadata.timingStatus == .valid)
        #expect(chart.rhythmMetadata.measureLengthOverrides.isEmpty)
    }

    @Test("identical rhythm declarations are accepted")
    func acceptsIdenticalDuplicates() throws {
        let chart = try parse("""
        #VIRGO_TIME_SIGNATURE: 6/8
        #virgo_time_signature: 6/8
        #VIRGO_FEEL: SHUFFLE
        #virgo_feel: shuffle
        #00302: 0.750
        #00302: 0.75
        """)

        #expect(chart.rhythmMetadata.timingStatus == .valid)
        #expect(chart.rhythmDiagnostics.isEmpty)
        #expect(chart.rhythmMetadata.measureLengthOverrides.count == 1)
    }

    @Test("conflicting rhythm declarations emit ordered stable diagnostics")
    func diagnosesConflictingDuplicates() throws {
        let chart = try parse("""
        #VIRGO_TIME_SIGNATURE: 6/8
        #VIRGO_TIME_SIGNATURE: 4/4
        #VIRGO_FEEL: STRAIGHT
        #VIRGO_FEEL: SWING
        #00302: 0.75
        #00302: 1.0
        """)

        #expect(chart.rhythmMetadata.timingStatus == .fatal)
        #expect(chart.rhythmDiagnostics.map(\.code) == [
            .conflictingTimeSignature,
            .conflictingFeel,
            .conflictingMeasureLength
        ])
        #expect(chart.rhythmDiagnostics.map(\.sourceLineNumber) == [6, 8, 10])
        #expect(chart.rhythmMetadata.timeSignature == .sixEight)
        #expect(chart.rhythmMetadata.feel == .straight)
        let expectedOverride = try MeasureLengthOverride(
            measureIndex: 3,
            ratioToWholeNote: .init(numerator: 3, denominator: 4)
        )
        #expect(chart.rhythmMetadata.measureLengthOverrides == [expectedOverride])
    }

    @Test("malformed and unsupported meters have distinct diagnostics")
    func distinguishesMalformedAndUnsupportedMeters() throws {
        let malformed = try parse("#VIRGO_TIME_SIGNATURE: six/eight")
        let unsupported = try parse("#VIRGO_TIME_SIGNATURE: 13/16")

        #expect(malformed.rhythmDiagnostics.map(\.code) == [.malformedTimeSignature])
        #expect(malformed.rhythmMetadata.timeSignature == nil)
        #expect(unsupported.rhythmDiagnostics.map(\.code) == [.unsupportedTimeSignature])
        #expect(unsupported.rhythmMetadata.timeSignature == nil)
    }

    @Test("malformed and unsupported feels have distinct diagnostics")
    func distinguishesMalformedAndUnsupportedFeels() throws {
        let empty = try parse("#VIRGO_FEEL:")
        let malformed = try parse("#VIRGO_FEEL: swing-ish")
        let unsupported = try parse("#VIRGO_FEEL: triplet")

        #expect(empty.rhythmDiagnostics.map(\.code) == [.malformedFeel])
        #expect(malformed.rhythmDiagnostics.map(\.code) == [.malformedFeel])
        #expect(unsupported.rhythmDiagnostics.map(\.code) == [.unsupportedFeel])
        #expect(unsupported.rhythmMetadata.feel == nil)
    }

    @Test("malformed, nonpositive, and conflicting measure lengths remain distinct")
    func diagnosesInvalidMeasureLengths() throws {
        let chart = try parse("""
        #00002: 1e0
        #00102: 0
        #00202: -0.5
        #00302: 1.0
        #00302: 1.5
        """)

        #expect(chart.rhythmDiagnostics.map(\.code) == [
            .malformedMeasureLength,
            .nonpositiveMeasureLength,
            .nonpositiveMeasureLength,
            .conflictingMeasureLength
        ])
        #expect(chart.rhythmMetadata.timingStatus == .fatal)
        #expect(chart.notes.isEmpty)
    }

    @Test("decimal scale construction reports arithmetic overflow")
    func diagnosesDecimalArithmeticOverflow() throws {
        let chart = try parse("#00002: 0.0000000000000000000000000000000000000001")

        #expect(chart.rhythmDiagnostics.map(\.code) == [.arithmeticOverflow])
        #expect(chart.rhythmMetadata.timingStatus == .fatal)
    }

    private func parse(_ rhythmLines: String) throws -> DTXChartData {
        try DTXFileParser.parseChartMetadata(from: """
        #TITLE: Rhythm Test
        #ARTIST: Tester
        #BPM: 120
        #DLEVEL: 50
        \(rhythmLines)
        """)
    }
}
