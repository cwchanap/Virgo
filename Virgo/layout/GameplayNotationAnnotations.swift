import CoreGraphics
import DrumNotation

/// App-owned overlay marks painted on top of the package engraving: the
/// localized feel label and per-measure rhythm warnings. Positions are final
/// sheet coordinates read from `EngravedNotation` rows/measures — the
/// package's single normalization already applies, so no extra translation
/// is needed at paint time (HPA-166 Task 7).
struct GameplayNotationAnnotations: Equatable, Sendable {
    let feelMarks: [GameplayFeelMark]
    let rhythmWarnings: [GameplayRhythmWarning]

    static let empty = GameplayNotationAnnotations(feelMarks: [], rhythmWarnings: [])
}

struct GameplayFeelMark: Identifiable, Hashable, Sendable {
    let id: String
    let feel: RhythmicFeel
    let position: CGPoint
    let rowIndex: Int
    let size: CGSize

    init(feel: RhythmicFeel, position: CGPoint, rowIndex: Int, size: CGSize) {
        id = "feel-\(feel.rawValue)"
        self.feel = feel
        self.position = position
        self.rowIndex = rowIndex
        self.size = size
    }

    var accessibilityLabel: String {
        String(localized: "\(feel.rawValue.capitalized) feel")
    }
}

enum RhythmWarningScope: Hashable, Sendable {
    case measure(Int)
    case chartFatal
}

/// The support state a `GameplayRhythmWarning` was materialized from. The same
/// diagnostic code (e.g. `.indeterminateTerminalDuration`) can surface from a
/// measure that keeps engraving (`.warning`) or one that fell back
/// (`.unsupported`); the title and accessibility label must distinguish them so
/// an engravable measure is not announced as unsupported.
enum RhythmWarningKind: Hashable, Sendable {
    /// Engraving retained; the diagnostic is surfaced as a non-blocking warning.
    case warning
    /// Measure fell back to unsupported rendering.
    case unsupported
    /// Chart-level fatal diagnostic.
    case chartFatal
}

struct GameplayRhythmWarning: Identifiable, Hashable, Sendable {
    let id: String
    let scope: RhythmWarningScope
    let kind: RhythmWarningKind
    let codes: [RhythmDiagnosticCode]
    let position: CGPoint
    let rowIndex: Int?
    let size: CGSize
    let displayMeasureNumber: Int?

    static func measure(
        measureIndex: Int,
        kind: RhythmWarningKind,
        codes: [RhythmDiagnosticCode],
        position: CGPoint,
        rowIndex: Int? = nil,
        size: CGSize
    ) -> Self {
        let stableCodes = codes.stableDiagnosticOrder
        return Self(
            id: "warning-measure-\(measureIndex)-\(kind)-\(stableCodes.map(\.rawValue).joined(separator: "-"))",
            scope: .measure(measureIndex),
            kind: kind,
            codes: stableCodes,
            position: position,
            rowIndex: rowIndex,
            size: size,
            displayMeasureNumber: measureIndex + 1
        )
    }

    static func chartFatal(
        diagnostics: [PersistedRhythmDiagnostic],
        position: CGPoint,
        size: CGSize
    ) -> Self {
        let codes = diagnostics.map(\.code).stableDiagnosticOrder
        return Self(
            id: "warning-chart-fatal-\(codes.map(\.rawValue).joined(separator: "-"))",
            scope: .chartFatal,
            kind: .chartFatal,
            codes: codes,
            position: position,
            rowIndex: nil,
            size: size,
            displayMeasureNumber: diagnostics.compactMap(\.sourceMeasureIndex).min().map { $0 + 1 }
        )
    }

    var title: String {
        switch kind {
        case .warning:
            return String(localized: "Rhythm warning")
        case .unsupported, .chartFatal:
            guard let code = codes.first else { return String(localized: "Unsupported rhythm") }
            return RhythmDiagnosticPresentation(code: code).title
        }
    }

    var accessibilityLabel: String {
        let title = self.title
        let detail = codes.first.map { RhythmDiagnosticPresentation(code: $0).description }
            ?? String(localized: "This rhythm cannot be displayed safely.")
        if let displayMeasureNumber {
            return String(localized: "\(title), measure \(displayMeasureNumber): \(detail)")
        }
        return String(localized: "\(title): \(detail)")
    }
}

/// Localized title/description for one `RhythmDiagnosticCode` — shared by the
/// fatal-timing sheet (`GameplayViewModel.rhythmFatalMessage`), the warning
/// annotations above, and diagnostics logging.
struct RhythmDiagnosticPresentation: Hashable, Sendable {
    let code: RhythmDiagnosticCode

    var title: String {
        switch code.requiredSeverity {
        case .timingFatal: return String(localized: "Unsupported chart timing")
        case .engravingOnly: return String(localized: "Unsupported rhythm")
        }
    }

    var description: String {
        switch code {
        case .malformedTimeSignature: return String(localized: "The chart time signature is malformed.")
        case .unsupportedTimeSignature: return String(localized: "The chart time signature is not supported.")
        case .malformedFeel: return String(localized: "The chart feel declaration is malformed.")
        case .unsupportedFeel: return String(localized: "The chart feel is not supported.")
        case .malformedMeasureLength: return String(localized: "The measure length is malformed.")
        case .nonpositiveMeasureLength: return String(localized: "The measure length must be positive.")
        case .conflictingTimeSignature: return String(localized: "The chart declares conflicting time signatures.")
        case .conflictingFeel: return String(localized: "The chart declares conflicting feels.")
        case .conflictingMeasureLength: return String(localized: "The chart declares conflicting measure lengths.")
        case .unsupportedMetadataVersion: return String(localized: "The chart timing data uses an unsupported version.")
        case .arithmeticOverflow: return String(localized: "The chart timing values exceed the supported range.")
        case .resolutionLimitExceeded: return String(localized: "The chart needs a timing resolution above the limit.")
        case .measureLimitExceeded: return String(localized: "The chart contains too many measures.")
        case .rhythmMaterializationLimitExceeded:
            return String(localized: "The chart contains too many rhythm units.")
        case .inexactGridProjection: return String(localized: "A chart event cannot be placed on the exact timeline.")
        case .inconsistentPersistedTiming: return String(localized: "The saved chart timing is inconsistent.")
        case .unsupportedTupletRatio: return String(localized: "This tuplet ratio cannot be engraved.")
        case .unsupportedDotCount: return String(localized: "This dotted duration cannot be engraved.")
        case .incompleteTuplet: return String(localized: "This tuplet is incomplete or overlapping.")
        case .ambiguousBeatGrouping: return String(localized: "This measure has ambiguous beat grouping.")
        case .indeterminateTerminalDuration:
            return String(localized: "The final event duration cannot be determined.")
        case .manualTimelineUnavailable: return String(localized: "Exact timing is unavailable for this manual chart.")
        }
    }

    func logMessage(sourceMeasureIndex: Int?, sourceLineNumber: Int?) -> String {
        var fields = ["rhythmDiagnostic", "code=\(code.rawValue)"]
        if let sourceMeasureIndex { fields.append("measureIndex=\(sourceMeasureIndex)") }
        if let sourceLineNumber { fields.append("lineNumber=\(sourceLineNumber)") }
        return fields.joined(separator: " ")
    }
}

extension GameplayNotationAnnotations {
    /// Builds the feel/warning overlay against the installed engraving's final
    /// row/measure geometry — the same normalized sheet coordinates
    /// `DrumNotationView` paints.
    static func build(
        feel: RhythmicFeel,
        expandedMeasures: [RhythmMeasure],
        engraved: EngravedNotation,
        style: NotationLayoutStyle
    ) -> GameplayNotationAnnotations {
        GameplayNotationAnnotations(
            feelMarks: feelMarks(feel: feel, engraved: engraved, style: style),
            rhythmWarnings: rhythmWarnings(
                expandedMeasures: expandedMeasures,
                engraved: engraved,
                style: style
            )
        )
    }

    /// The top staff line's Y on the row — `staffLineYs` is pitch-ascending
    /// (bottom line first), so `last` is the staff top.
    private static func staffTopY(rowIndex: Int, engraved: EngravedNotation) -> CGFloat? {
        engraved.rows.first { $0.index == rowIndex }?.staffLineYs.last
    }

    /// The engraved measure's leading inset edge — the anchor for app marks
    /// placed just inside a measure's left edge.
    private static func leadingInsetX(in measure: EngravedMeasure, engraved: EngravedNotation) -> CGFloat {
        measure.xOffset + engraved.style.formatting.leadingMeasureInset
    }

    private static func feelMarks(
        feel: RhythmicFeel,
        engraved: EngravedNotation,
        style: NotationLayoutStyle
    ) -> [GameplayFeelMark] {
        guard feel != .straight,
              let first = engraved.measures.min(by: {
                  $0.rowIndex == $1.rowIndex ? $0.xOffset < $1.xOffset : $0.rowIndex < $1.rowIndex
              }),
              let staffTop = staffTopY(rowIndex: first.rowIndex, engraved: engraved) else { return [] }
        return [GameplayFeelMark(
            feel: feel,
            position: CGPoint(
                x: leadingInsetX(in: first, engraved: engraved) + style.feelMarkSize.width / 2,
                y: staffTop - style.feelMarkVerticalOffset
            ),
            rowIndex: first.rowIndex,
            size: style.feelMarkSize
        )]
    }

    private static func rhythmWarnings(
        expandedMeasures: [RhythmMeasure],
        engraved: EngravedNotation,
        style: NotationLayoutStyle
    ) -> [GameplayRhythmWarning] {
        let engravedByIndex = Dictionary(uniqueKeysWithValues: engraved.measures.map { ($0.index, $0) })
        return expandedMeasures.compactMap { measure in
            let kind: RhythmWarningKind
            let codes: [RhythmDiagnosticCode]
            switch measure.engravingSupport {
            case .supported:
                return nil
            case let .warning(value):
                kind = .warning
                codes = value
            case let .unsupported(value):
                kind = .unsupported
                codes = value
            }
            guard let engravedMeasure = engravedByIndex[measure.measureIndex],
                  let staffTop = staffTopY(rowIndex: engravedMeasure.rowIndex, engraved: engraved) else {
                return nil
            }
            return GameplayRhythmWarning.measure(
                measureIndex: measure.measureIndex,
                kind: kind,
                codes: codes,
                position: CGPoint(
                    x: leadingInsetX(in: engravedMeasure, engraved: engraved)
                        + min(engravedMeasure.width, style.warningSize.width) / 2,
                    y: staffTop - style.warningVerticalOffset
                ),
                rowIndex: engravedMeasure.rowIndex,
                size: style.warningSize
            )
        }
    }
}

private extension Array where Element == RhythmDiagnosticCode {
    var stableDiagnosticOrder: [RhythmDiagnosticCode] {
        Array(Set(self)).sorted { $0.rawValue < $1.rawValue }
    }
}
