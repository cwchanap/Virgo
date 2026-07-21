//
//  DTXRhythmParser.swift
//  Virgo
//

import Foundation

struct DTXRhythmDiagnostic: Hashable {
    let code: RhythmDiagnosticCode
    let severity: RhythmDiagnosticSeverity
    let sourceLineNumber: Int?
    let sourceLine: String
}

private struct DTXRhythmDiagnosticEntry {
    let diagnostic: DTXRhythmDiagnostic
    let sourceMeasureIndex: Int?
}

private enum DTXDecimalRatioResult {
    case value(RhythmRatio)
    case malformed
    case nonpositive
    case overflow
}

enum DTXRhythmParser {
    struct State {
        private(set) var timeSignature: TimeSignature?
        private(set) var feel: RhythmicFeel?
        private var measureLengthOverrides: [Int: RhythmRatio] = [:]
        private var conflictedMeasureIndices: Set<Int> = []
        private var diagnosticEntries: [DTXRhythmDiagnosticEntry] = []
        private var sawTimeSignatureDirective = false
        private var sawFeelDirective = false
        private var hasTimeSignatureConflict = false
        private var hasFeelConflict = false

        var diagnostics: [DTXRhythmDiagnostic] {
            diagnosticEntries.map(\.diagnostic)
        }

        mutating func consume(
            _ line: String,
            sourceLineNumber: Int,
            sourceLine: String
        ) -> Bool {
            let uppercasedLine = line.uppercased()
            if uppercasedLine.hasPrefix("#VIRGO_TIME_SIGNATURE:") {
                sawTimeSignatureDirective = true
                parseTimeSignature(
                    value(afterColonIn: line),
                    sourceLineNumber: sourceLineNumber,
                    sourceLine: sourceLine
                )
                return true
            }
            if uppercasedLine.hasPrefix("#VIRGO_FEEL:") {
                sawFeelDirective = true
                parseFeel(
                    value(afterColonIn: line),
                    sourceLineNumber: sourceLineNumber,
                    sourceLine: sourceLine
                )
                return true
            }
            guard let measureIndex = Self.measureLengthIndex(in: line) else {
                return false
            }
            parseMeasureLength(
                value(afterColonIn: line),
                measureIndex: measureIndex,
                sourceLineNumber: sourceLineNumber,
                sourceLine: sourceLine
            )
            return true
        }

        func makeMetadata(bgmStartAnchor: RhythmSourceAnchor?) throws -> ChartRhythmMetadata {
            let persistedDiagnostics = try diagnosticEntries.map { entry in
                try PersistedRhythmDiagnostic(
                    code: entry.diagnostic.code,
                    severity: entry.diagnostic.severity,
                    sourceMeasureIndex: entry.sourceMeasureIndex,
                    sourceLineNumber: entry.diagnostic.sourceLineNumber
                )
            }
            let overrides = try measureLengthOverrides.map { measureIndex, ratio in
                try MeasureLengthOverride(measureIndex: measureIndex, ratioToWholeNote: ratio)
            }
            let hasFatalDiagnostic = diagnosticEntries.contains {
                $0.diagnostic.severity == .timingFatal
            }

            return try ChartRhythmMetadata(
                timeSignature: hasTimeSignatureConflict
                    ? nil
                    : (timeSignature ?? (sawTimeSignatureDirective ? nil : .fourFour)),
                feel: hasFeelConflict ? nil : (feel ?? (sawFeelDirective ? nil : .straight)),
                measureLengthOverrides: overrides,
                bgmStartAnchor: bgmStartAnchor,
                timingStatus: hasFatalDiagnostic ? .fatal : .valid,
                diagnostics: persistedDiagnostics
            )
        }

        private mutating func parseTimeSignature(
            _ value: String,
            sourceLineNumber: Int,
            sourceLine: String
        ) {
            guard let normalizedValue = Self.normalizedTimeSignature(value) else {
                appendDiagnostic(
                    .malformedTimeSignature,
                    sourceLineNumber: sourceLineNumber,
                    sourceLine: sourceLine
                )
                return
            }
            guard let parsed = TimeSignature(rawValue: normalizedValue) else {
                appendDiagnostic(
                    .unsupportedTimeSignature,
                    sourceLineNumber: sourceLineNumber,
                    sourceLine: sourceLine
                )
                return
            }
            guard !hasTimeSignatureConflict else { return }
            if let timeSignature, timeSignature != parsed {
                self.timeSignature = nil
                hasTimeSignatureConflict = true
                appendDiagnostic(
                    .conflictingTimeSignature,
                    sourceLineNumber: sourceLineNumber,
                    sourceLine: sourceLine
                )
            } else {
                timeSignature = parsed
            }
        }

        private mutating func parseFeel(
            _ value: String,
            sourceLineNumber: Int,
            sourceLine: String
        ) {
            guard !value.isEmpty, value.allSatisfy(Self.isASCIILetter) else {
                appendDiagnostic(
                    .malformedFeel,
                    sourceLineNumber: sourceLineNumber,
                    sourceLine: sourceLine
                )
                return
            }
            guard let parsed = RhythmicFeel(rawValue: value.lowercased()) else {
                appendDiagnostic(
                    .unsupportedFeel,
                    sourceLineNumber: sourceLineNumber,
                    sourceLine: sourceLine
                )
                return
            }
            guard !hasFeelConflict else { return }
            if let feel, feel != parsed {
                self.feel = nil
                hasFeelConflict = true
                appendDiagnostic(
                    .conflictingFeel,
                    sourceLineNumber: sourceLineNumber,
                    sourceLine: sourceLine
                )
            } else {
                feel = parsed
            }
        }

        private mutating func parseMeasureLength(
            _ value: String,
            measureIndex: Int,
            sourceLineNumber: Int,
            sourceLine: String
        ) {
            switch Self.exactDecimalRatio(value) {
            case .value(let ratio):
                guard !conflictedMeasureIndices.contains(measureIndex) else { return }
                if let existing = measureLengthOverrides[measureIndex], existing != ratio {
                    measureLengthOverrides.removeValue(forKey: measureIndex)
                    conflictedMeasureIndices.insert(measureIndex)
                    appendDiagnostic(
                        .conflictingMeasureLength,
                        sourceLineNumber: sourceLineNumber,
                        sourceLine: sourceLine,
                        sourceMeasureIndex: measureIndex
                    )
                } else {
                    measureLengthOverrides[measureIndex] = ratio
                }
            case .malformed:
                appendDiagnostic(
                    .malformedMeasureLength,
                    sourceLineNumber: sourceLineNumber,
                    sourceLine: sourceLine,
                    sourceMeasureIndex: measureIndex
                )
            case .nonpositive:
                appendDiagnostic(
                    .nonpositiveMeasureLength,
                    sourceLineNumber: sourceLineNumber,
                    sourceLine: sourceLine,
                    sourceMeasureIndex: measureIndex
                )
            case .overflow:
                appendDiagnostic(
                    .arithmeticOverflow,
                    sourceLineNumber: sourceLineNumber,
                    sourceLine: sourceLine,
                    sourceMeasureIndex: measureIndex
                )
            }
        }

        private mutating func appendDiagnostic(
            _ code: RhythmDiagnosticCode,
            sourceLineNumber: Int,
            sourceLine: String,
            sourceMeasureIndex: Int? = nil
        ) {
            diagnosticEntries.append(
                DTXRhythmDiagnosticEntry(
                    diagnostic: DTXRhythmDiagnostic(
                        code: code,
                        severity: code.requiredSeverity,
                        sourceLineNumber: sourceLineNumber,
                        sourceLine: sourceLine
                    ),
                    sourceMeasureIndex: sourceMeasureIndex
                )
            )
        }

        private func value(afterColonIn line: String) -> String {
            guard let colon = line.firstIndex(of: ":") else { return "" }
            return line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }

        private static func normalizedTimeSignature(_ value: String) -> String? {
            let components = value.split(separator: "/", omittingEmptySubsequences: false)
            guard components.count == 2,
                  components.allSatisfy({ !$0.isEmpty && $0.allSatisfy(isASCIIDigit) }),
                  let numerator = Int(components[0]), numerator > 0,
                  let denominator = Int(components[1]), denominator > 0 else {
                return nil
            }
            return "\(numerator)/\(denominator)"
        }

        private static func measureLengthIndex(in line: String) -> Int? {
            guard let colon = line.firstIndex(of: ":") else { return nil }
            let header = line[..<colon]
            guard header.count == 6,
                  header.first == "#",
                  header.suffix(2) == "02" else {
                return nil
            }
            let measureDigits = header.dropFirst().prefix(3)
            guard measureDigits.allSatisfy(isASCIIDigit) else { return nil }
            return Int(measureDigits)
        }

        private static func isASCIIDigit(_ character: Character) -> Bool {
            character >= "0" && character <= "9"
        }

        private static func isASCIILetter(_ character: Character) -> Bool {
            (character >= "A" && character <= "Z")
                || (character >= "a" && character <= "z")
        }

        private static func exactDecimalRatio(_ value: String) -> DTXDecimalRatioResult {
            var characters = Array(value)
            guard !characters.isEmpty else { return .malformed }

            var isNegative = false
            if characters.first == "+" || characters.first == "-" {
                isNegative = characters.first == "-"
                characters.removeFirst()
            }

            let components = String(characters).split(separator: ".", omittingEmptySubsequences: false)
            guard !characters.isEmpty,
                  components.count <= 2,
                  components.contains(where: { !$0.isEmpty }),
                  components.allSatisfy({ $0.allSatisfy(isASCIIDigit) }) else {
                return .malformed
            }

            let wholeDigits = components[0]
            let fractionalDigits = components.count == 2 ? components[1] : Substring()
            guard let scale = checkedPowerOfTen(fractionalDigits.count),
                  let whole = checkedUnsignedInteger(wholeDigits),
                  let fraction = checkedUnsignedInteger(fractionalDigits),
                  let scaledWhole = checkedMultiply(whole, scale),
                  let numerator = checkedAdd(scaledWhole, fraction) else {
                return .overflow
            }
            guard !isNegative, numerator > 0 else { return .nonpositive }

            do {
                return .value(try RhythmRatio(numerator: numerator, denominator: scale))
            } catch RhythmMetadataValidationError.arithmeticOverflow {
                return .overflow
            } catch {
                return .malformed
            }
        }

        private static func checkedPowerOfTen(_ exponent: Int) -> Int? {
            var result = 1
            for _ in 0..<exponent {
                guard let next = checkedMultiply(result, 10) else { return nil }
                result = next
            }
            return result
        }

        private static func checkedUnsignedInteger(_ digits: Substring) -> Int? {
            var result = 0
            for character in digits {
                guard let digit = character.wholeNumberValue,
                      let shifted = checkedMultiply(result, 10),
                      let next = checkedAdd(shifted, digit) else {
                    return nil
                }
                result = next
            }
            return result
        }

        private static func checkedMultiply(_ left: Int, _ right: Int) -> Int? {
            let result = left.multipliedReportingOverflow(by: right)
            return result.overflow ? nil : result.partialValue
        }

        private static func checkedAdd(_ left: Int, _ right: Int) -> Int? {
            let result = left.addingReportingOverflow(right)
            return result.overflow ? nil : result.partialValue
        }
    }
}
