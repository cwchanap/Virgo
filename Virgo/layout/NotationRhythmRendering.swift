import CoreGraphics
import Foundation

enum RenderedRhythmDotSource: Hashable {
    case event(RhythmEventID)
    case rest(String)
}

struct RenderedRhythmDot: Identifiable, Hashable {
    let id: String
    let source: RenderedRhythmDotSource
    let position: CGPoint
    let rowIndex: Int

    init(source: RenderedRhythmDotSource, position: CGPoint, rowIndex: Int) {
        self.source = source
        self.position = position
        self.rowIndex = rowIndex
        switch source {
        case .event(let eventID): id = "dot-event-\(eventID.rawValue)"
        case .rest(let restID): id = "dot-rest-\(restID)"
        }
    }

    var accessibilityLabel: String { String(localized: "Rhythm dot") }
}

struct RenderedTuplet: Identifiable, Hashable {
    let id: RhythmTupletID
    let voice: NotationVoice
    let ratio: TupletRatio
    let memberEventIDs: [RhythmEventID]
    let bracketPoints: [CGPoint]
    let isBracketVisible: Bool
    let labelPosition: CGPoint
    let rowIndex: Int

    var accessibilityLabel: String {
        let voiceName = voice == .upper ? String(localized: "Upper") : String(localized: "Lower")
        return String(localized: "\(voiceName) voice tuplet, \(ratio.actual) in the time of \(ratio.normal)")
    }
}

struct RenderedFeelMark: Identifiable, Hashable {
    let id: String
    let feel: RhythmicFeel
    let position: CGPoint
    let rowIndex: Int
    let size: CGSize

    init(feel: RhythmicFeel, position: CGPoint, rowIndex: Int, style: NotationLayoutStyle) {
        id = "feel-\(feel.rawValue)"
        self.feel = feel
        self.position = position
        self.rowIndex = rowIndex
        size = style.feelMarkSize
    }

    var accessibilityLabel: String {
        String(localized: "\(feel.rawValue.capitalized) feel")
    }
}

enum RhythmWarningScope: Hashable {
    case measure(Int)
    case chartFatal
}

struct RenderedRhythmWarning: Identifiable, Hashable {
    let id: String
    let scope: RhythmWarningScope
    let codes: [RhythmDiagnosticCode]
    let position: CGPoint
    let rowIndex: Int?
    let size: CGSize
    let displayMeasureNumber: Int?

    static func measure(
        measureIndex: Int,
        codes: [RhythmDiagnosticCode],
        position: CGPoint,
        rowIndex: Int? = nil,
        style: NotationLayoutStyle
    ) -> Self {
        let stableCodes = codes.stableDiagnosticOrder
        return Self(
            id: "warning-measure-\(measureIndex)-\(stableCodes.map(\.rawValue).joined(separator: "-"))",
            scope: .measure(measureIndex),
            codes: stableCodes,
            position: position,
            rowIndex: rowIndex,
            size: style.warningSize,
            displayMeasureNumber: measureIndex + 1
        )
    }

    static func chartFatal(
        diagnostics: [PersistedRhythmDiagnostic],
        position: CGPoint,
        style: NotationLayoutStyle
    ) -> Self {
        let codes = diagnostics.map(\.code).stableDiagnosticOrder
        return Self(
            id: "warning-chart-fatal-\(codes.map(\.rawValue).joined(separator: "-"))",
            scope: .chartFatal,
            codes: codes,
            position: position,
            rowIndex: nil,
            size: style.warningSize,
            displayMeasureNumber: diagnostics.compactMap(\.sourceMeasureIndex).min().map { $0 + 1 }
        )
    }

    var title: String {
        guard let code = codes.first else { return String(localized: "Unsupported rhythm") }
        return RhythmDiagnosticPresentation(code: code).title
    }

    var accessibilityLabel: String {
        let presentation = codes.first.map(RhythmDiagnosticPresentation.init)
        let title = presentation?.title ?? String(localized: "Unsupported rhythm")
        let detail = presentation?.description ?? String(localized: "This rhythm cannot be displayed safely.")
        if let displayMeasureNumber {
            return String(localized: "\(title), measure \(displayMeasureNumber): \(detail)")
        }
        return String(localized: "\(title): \(detail)")
    }
}

struct RhythmDiagnosticPresentation: Hashable {
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

extension RenderedNoteHead {
    func paintedBounds(style: NotationLayoutStyle) -> CGRect {
        glyph.bounds(centeredAt: position, size: style.noteHeadSize)
    }
}

extension RenderedRest {
    func paintedBounds(style: NotationLayoutStyle) -> CGRect {
        guard isPrinted, duration != .indeterminate else { return .null }
        let size = duration == .fullMeasure || duration == .half
            ? CGSize(width: style.fullMeasureRestWidth, height: style.fullMeasureRestHeight)
            : CGSize(width: style.restSymbolWidth + 3, height: style.restSymbolHeight + 3)
        return CGRect(center: position, size: size)
    }
}

extension RenderedStopNote {
    func paintedBounds(style: NotationLayoutStyle) -> CGRect {
        CGRect(center: position, size: CGSize(
            width: style.stopMarkSize + style.stopMarkStrokeWidth,
            height: style.stopMarkSize + style.stopMarkStrokeWidth
        ))
    }
}

extension RenderedArticulation {
    func paintedBounds(style: NotationLayoutStyle) -> CGRect {
        let diameter = style.articulationDiameter + style.articulationStrokeWidth
        return CGRect(center: position, size: CGSize(width: diameter, height: diameter))
    }
}

extension RenderedStem {
    func paintedBounds(style: NotationLayoutStyle) -> CGRect {
        lineBounds(start: start, end: end, lineWidth: style.stemWidth)
    }
}

extension RenderedBeam {
    func paintedBounds(style: NotationLayoutStyle) -> CGRect {
        lineBounds(start: start, end: end, lineWidth: thickness)
    }
}

extension RenderedFlag {
    func paintedBounds(style: NotationLayoutStyle) -> CGRect {
        switch stemDirection {
        case .up:
            return CGRect(x: origin.x, y: origin.y, width: GameplayLayout.flagWidth, height: GameplayLayout.flagHeight)
        case .down:
            return CGRect(
                x: origin.x - GameplayLayout.flagWidth,
                y: origin.y - GameplayLayout.flagHeight,
                width: GameplayLayout.flagWidth,
                height: GameplayLayout.flagHeight
            )
        }
    }
}

extension RenderedLedgerLine {
    func paintedBounds(style: NotationLayoutStyle) -> CGRect {
        lineBounds(start: start, end: end, lineWidth: GameplayLayout.barLineWidth)
    }
}

extension RenderedMeasureBar {
    func paintedBounds(style: NotationLayoutStyle) -> CGRect {
        let centerY = GameplayLayout.StaffLinePosition.line3.absoluteY(for: row)
        if isFinal {
            let width = GameplayLayout.doubleBarLineWidths.thin
                + GameplayLayout.doubleBarLineSpacing
                + GameplayLayout.doubleBarLineWidths.thick
            return CGRect(
                x: x - width,
                y: centerY - GameplayLayout.staffHeight / 2,
                width: width,
                height: GameplayLayout.staffHeight
            )
        }
        return CGRect(
            center: CGPoint(x: x, y: centerY),
            size: CGSize(width: GameplayLayout.barLineWidth, height: GameplayLayout.staffHeight)
        )
    }
}

extension RenderedRhythmDot {
    func paintedBounds(style: NotationLayoutStyle) -> CGRect {
        let diameter = style.rhythmDotRadius * 2
        return CGRect(center: position, size: CGSize(width: diameter, height: diameter))
    }
}

extension RenderedTuplet {
    func paintedBounds(style: NotationLayoutStyle) -> CGRect {
        var bounds = bracketPoints.isEmpty ? CGRect.null : bracketPointsBounds
        bounds = bounds.union(CGRect(center: labelPosition, size: style.tupletLabelSize))
        return bounds.insetBy(dx: -style.tupletLineWidth / 2, dy: -style.tupletLineWidth / 2)
    }

    private var bracketPointsBounds: CGRect {
        bracketPoints.dropFirst().reduce(CGRect(origin: bracketPoints[0], size: .zero)) {
            $0.union(CGRect(origin: $1, size: .zero))
        }
    }
}

extension RenderedFeelMark {
    func paintedBounds(style: NotationLayoutStyle) -> CGRect { CGRect(center: position, size: size) }
}

extension RenderedRhythmWarning {
    func paintedBounds(style: NotationLayoutStyle) -> CGRect { CGRect(center: position, size: size) }
}

extension NotationLayout {
    func calculatePaintedBounds(style: NotationLayoutStyle) -> CGRect {
        let rectangles = noteHeads.map { $0.paintedBounds(style: style) }
            + rests.map { $0.paintedBounds(style: style) }
            + stopNotes.map { $0.paintedBounds(style: style) }
            + articulations.map { $0.paintedBounds(style: style) }
            + stems.map { $0.paintedBounds(style: style) }
            + beams.map { $0.paintedBounds(style: style) }
            + flags.map { $0.paintedBounds(style: style) }
            + ledgerLines.map { $0.paintedBounds(style: style) }
            + measureBars.map { $0.paintedBounds(style: style) }
            + rhythmDots.map { $0.paintedBounds(style: style) }
            + tuplets.map { $0.paintedBounds(style: style) }
            + feelMarks.map { $0.paintedBounds(style: style) }
            + rhythmWarnings.map { $0.paintedBounds(style: style) }
        return rectangles.filter { !$0.isNull }.reduce(.null) { $0.union($1) }
    }
}

private extension Array where Element == RhythmDiagnosticCode {
    var stableDiagnosticOrder: [RhythmDiagnosticCode] {
        Array(Set(self)).sorted { $0.rawValue < $1.rawValue }
    }
}

private extension CGRect {
    init(center: CGPoint, size: CGSize) {
        self.init(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}

private func lineBounds(start: CGPoint, end: CGPoint, lineWidth: CGFloat) -> CGRect {
    CGRect(
        x: min(start.x, end.x),
        y: min(start.y, end.y),
        width: abs(end.x - start.x),
        height: abs(end.y - start.y)
    ).insetBy(dx: -lineWidth / 2, dy: -lineWidth / 2)
}
