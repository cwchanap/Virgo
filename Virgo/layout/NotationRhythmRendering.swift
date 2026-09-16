import CoreGraphics
import DrumNotation
import Foundation

enum RenderedRhythmDotSource: Hashable, Sendable {
    case event(RhythmEventID)
    case rest(String)
}

struct RenderedRhythmDot: Identifiable, Hashable, Sendable {
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

struct RenderedTuplet: Identifiable, Hashable, Sendable {
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

struct RenderedFeelMark: Identifiable, Hashable, Sendable {
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

struct RenderedRhythmWarning: Identifiable, Hashable, Sendable {
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
        style: NotationLayoutStyle
    ) -> Self {
        let stableCodes = codes.stableDiagnosticOrder
        return Self(
            id: "warning-measure-\(measureIndex)-\(kind)-\(stableCodes.map(\.rawValue).joined(separator: "-"))",
            scope: .measure(measureIndex),
            kind: kind,
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
            kind: .chartFatal,
            codes: codes,
            position: position,
            rowIndex: nil,
            size: style.warningSize,
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

extension RenderedNoteHead {
    func paintedBounds(style: NotationLayoutStyle) -> CGRect {
        VirgoNotationAdapter.noteheadMetrics(for: self, style: style).paintedBounds
            .offsetBy(dx: position.x, dy: position.y)
    }
}

extension RenderedRest {
    func paintedBounds(style: NotationLayoutStyle) -> CGRect {
        guard isPrinted, let duration = VirgoNotationAdapter.restDuration(self.duration) else {
            return .null
        }
        return PercussionGlyphMetrics.rest(duration: duration, staffSpace: style.staffLineSpacing)
            .paintedBounds
            .offsetBy(dx: position.x, dy: position.y)
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
        PercussionGlyphMetrics.articulation(
            VirgoNotationAdapter.articulation(for: kind),
            staffSpace: style.staffLineSpacing
        )
            .paintedBounds
            .offsetBy(dx: position.x, dy: position.y)
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

extension RenderedLedgerLine {
    func paintedBounds(style: NotationLayoutStyle) -> CGRect {
        lineBounds(start: start, end: end, lineWidth: GameplayLayout.barLineWidth)
    }
}

extension NotationLayout {
    func calculatePaintedBounds(style: NotationLayoutStyle) -> CGRect {
        let flagCommands = VirgoNotationAdapter.flagPaintCommands(
            flags: flags,
            heads: noteHeads,
            style: style
        )
        var rectangles: [CGRect] = []
        rectangles.append(contentsOf: noteHeads.map { $0.paintedBounds(style: style) })
        rectangles.append(contentsOf: rests.map { $0.paintedBounds(style: style) })
        rectangles.append(contentsOf: stopNotes.map { $0.paintedBounds(style: style) })
        rectangles.append(contentsOf: articulations.map { $0.paintedBounds(style: style) })
        rectangles.append(contentsOf: stems.map { $0.paintedBounds(style: style) })
        rectangles.append(contentsOf: beams.map { $0.paintedBounds(style: style) })
        rectangles.append(contentsOf: flagCommands.map(\.paintedBounds))
        rectangles.append(contentsOf: ledgerLines.map { $0.paintedBounds(style: style) })
        rectangles.append(contentsOf: measureBars.map { $0.paintedBounds(style: style) })
        rectangles.append(contentsOf: rhythmDots.map { $0.paintedBounds(style: style) })
        rectangles.append(contentsOf: tuplets.map { $0.paintedBounds(style: style) })
        rectangles.append(contentsOf: feelMarks.map { $0.paintedBounds(style: style) })
        rectangles.append(contentsOf: rhythmWarnings.map { $0.paintedBounds(style: style) })
        let nonNull = rectangles.filter { !$0.isNull }
        return nonNull.reduce(CGRect.null) { $0.union($1) }
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
