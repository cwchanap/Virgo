import CoreGraphics
import Foundation
@testable import Virgo

/// Serializes a rendered fixture to deterministic text for golden comparison.
///
/// Locks layout geometry, the grid, the resolved style, and the layout's own
/// dimensions. Does NOT lock anything downstream of layout — view modifiers,
/// colour, z-order, font rasterization. That boundary is deliberate.
@MainActor
enum NotationLayoutDigest {
    private static let posix = Locale(identifier: "en_US_POSIX")

    private static func f(_ value: CGFloat) -> String {
        String(format: "%.2f", locale: posix, Double(value))
    }

    private static func pt(_ point: CGPoint) -> String {
        "(\(f(point.x)),\(f(point.y)))"
    }

    static func make(_ result: FixtureRenderResult) -> String {
        var lines: [String] = []
        lines.append(contentsOf: timelineSection(result))
        lines.append("")
        lines.append(contentsOf: layoutSection(result))
        return lines.joined(separator: "\n") + "\n"
    }

    private static func timelineSection(_ result: FixtureRenderResult) -> [String] {
        let snapshot = result.snapshot
        var lines = ["tl-grid ticksPerWholeNote=\(snapshot.ticksPerWholeNote) feel=\(snapshot.feel)"]
        for measure in snapshot.measures.sorted(by: { $0.measureIndex < $1.measureIndex }) {
            let groups = measure.beatGroups
                .sorted { $0.groupIndex < $1.groupIndex }
                .map(\.startTick)
                .map(String.init)
                .joined(separator: ",")
            let engraving: String
            switch measure.engravingSupport {
            case .supported:
                engraving = "supported"
            case let .unsupported(codes):
                engraving = "unsupported[" + codes.map(\.rawValue).sorted().joined(separator: ",") + "]"
            }
            lines.append(
                "tl-meas m\(measure.measureIndex) startTick=\(measure.startTick) "
                + "durationTicks=\(measure.durationTicks) sig=\(measure.timeSignature.rawValue) "
                + "groups=[\(groups)] engraving=\(engraving)"
            )
        }
        return lines
    }

    private static func layoutSection(_ result: FixtureRenderResult) -> [String] {
        let layout = result.layout
        let grid = layout.tabGrid
        let style = result.style
        var lines: [String] = []

        lines.append(
            "grid  ticksPerWholeNote=\(grid.ticksPerWholeNote) "
            + "tickWidth=\(f(grid.tickWidth)) leftPadding=\(f(grid.leftPadding))"
        )
        lines.append(
            "style rowWidth=\(f(style.rowWidth)) overrides=default "
            + "minNoteColumnGap=\(f(style.minimumNoteColumnGap)) "
            + "minQuarterBeatGap=\(f(style.minimumQuarterBeatGap)) "
            + "staffLineSpacing=\(f(style.staffLineSpacing)) "
            + "noteHeadWidth=\(f(style.noteHeadWidth)) "
            + "noteHeadHeight=\(f(style.noteHeadHeight)) "
            + "stemLength=\(f(style.stemLength))"
        )
        lines.append(
            "dims  noteHeadSize=\(f(layout.noteHeadSize.width))x\(f(layout.noteHeadSize.height)) "
            + "totalHeight=\(f(layout.totalHeight)) "
            + "paintedBounds=\(rect(layout.paintedBounds))"
        )

        for row in Set(layout.measures.map(\.row)).sorted() {
            let measures = layout.measures
                .filter { $0.row == row }
                .sorted { $0.measureIndex < $1.measureIndex }
                .map { "m\($0.measureIndex)" }
                .joined(separator: ",")
            lines.append("row   \(row) measures=[\(measures)] contentWidth=\(f(layout.contentWidth))")
        }

        for measure in layout.measures.sorted(by: measureOrder) {
            lines.append(
                "meas  m\(measure.measureIndex) row=\(measure.row) "
                + "xOffset=\(f(measure.xOffset)) width=\(f(measure.width)) "
                + "startTick=\(measure.startTick) durationTicks=\(measure.durationTicks) "
                + "contentStartX=\(f(measure.contentStartX))"
            )
        }

        lines.append(contentsOf: primitiveLines(layout))
        return lines
    }

    private static func rect(_ rect: CGRect) -> String {
        rect.isNull
            ? "null"
            : "(\(f(rect.minX)),\(f(rect.minY)),\(f(rect.width)),\(f(rect.height)))"
    }

    private static func measureOrder(_ lhs: RenderedMeasure, _ rhs: RenderedMeasure) -> Bool {
        if lhs.row != rhs.row { return lhs.row < rhs.row }
        return lhs.measureIndex < rhs.measureIndex
    }
}

@MainActor
extension NotationLayoutDigest {
    // swiftlint:disable:next function_body_length cyclomatic_complexity
    fileprivate static func primitiveLines(_ layout: NotationLayout) -> [String] {
        var lines: [String] = []

        let heads = layout.noteHeads.sorted {
            ($0.timeColumn.measureIndex, $0.timeColumn.tickWithinMeasure, Double($0.position.y), $0.id)
                < ($1.timeColumn.measureIndex, $1.timeColumn.tickWithinMeasure, Double($1.position.y), $1.id)
        }
        for head in heads {
            lines.append(
                "head  m\(head.timeColumn.measureIndex) "
                + "t\(String(format: "%04d", locale: posix, head.timeColumn.tickWithinMeasure)) "
                + "abs\(String(format: "%04d", locale: posix, head.timeColumn.absoluteLayoutTick)) "
                + "pos=\(pt(head.position)) \(head.drumType.description) "
                + "glyph=\(head.glyph) variant=\(head.variant) voice=\(head.voice.rawValue) "
                + "stem=\(head.stemDirection.rawValue) row=\(head.row) "
                + "lane=\(head.sourceLaneID ?? "-") "
                + "interval=\(head.interval.rawValue) rhythm=\(rhythmText(head.rhythm)) "
                + "durTicks=\(head.rhythmDurationTicks.map(String.init) ?? "-")"
            )
        }

        for stem in layout.stems.sorted(by: byStart(\.start, \.id)) {
            lines.append(
                "stem  ids=\(stem.noteHeadIDs.sorted()) dir=\(stem.direction.rawValue) "
                + "start=\(pt(stem.start)) end=\(pt(stem.end))"
            )
        }

        for beam in layout.beams.sorted(by: byStart(\.start, \.id)) {
            lines.append(
                "beam  ids=\(beam.noteHeadIDs.sorted()) dir=\(beam.direction.rawValue) "
                + "level=\(beam.level) kind=\(beam.kind.rawValue) "
                + "start=\(pt(beam.start)) end=\(pt(beam.end)) thickness=\(f(beam.thickness))"
            )
        }

        for flag in layout.flags.sorted(by: byStart(\.origin, \.id)) {
            lines.append(
                "flag  head=\(flag.noteHeadID) dir=\(flag.stemDirection.rawValue) "
                + "index=\(flag.flagIndex) origin=\(pt(flag.origin))"
            )
        }

        let rests = layout.rests.sorted {
            ($0.measureIndex, $0.timeColumn.tickWithinMeasure, Double($0.position.y), $0.id)
                < ($1.measureIndex, $1.timeColumn.tickWithinMeasure, Double($1.position.y), $1.id)
        }
        for rest in rests {
            lines.append(
                "rest  m\(rest.measureIndex) "
                + "t\(String(format: "%04d", locale: posix, rest.timeColumn.tickWithinMeasure)) "
                + "voice=\(rest.voice.rawValue) dur=\(rest.duration) ticks=\(rest.durationTicks) "
                + "vis=\(rest.visibility) pos=\(pt(rest.position)) "
                + "tuplet=\(rest.tupletID.map { "\($0)" } ?? "-")"
            )
        }

        let stops = layout.stopNotes.sorted {
            ($0.timeColumn.measureIndex, $0.timeColumn.tickWithinMeasure, $0.id)
                < ($1.timeColumn.measureIndex, $1.timeColumn.tickWithinMeasure, $1.id)
        }
        for stop in stops {
            lines.append(
                "stop  m\(stop.timeColumn.measureIndex) "
                + "t\(String(format: "%04d", locale: posix, stop.timeColumn.tickWithinMeasure)) "
                + "kind=\(stop.kind.rawValue) target=\(stop.targetLaneID) "
                + "pos=\(pt(stop.position)) lane=\(stop.sourceLaneID ?? "-")"
            )
        }

        for artic in layout.articulations.sorted(by: byStart(\.position, \.id)) {
            lines.append(
                "artic kind=\(artic.kind) head=\(artic.sourceNoteHeadID) "
                + "row=\(artic.row) pos=\(pt(artic.position))"
            )
        }

        for dot in layout.rhythmDots.sorted(by: byStart(\.position, \.id)) {
            lines.append("dot   source=\(dotSourceText(dot.source)) pos=\(pt(dot.position)) row=\(dot.rowIndex)")
        }

        for tuplet in layout.tuplets.sorted(by: tupletIDOrder) {
            let bracket = tuplet.bracketPoints.map(pt).joined(separator: " ")
            lines.append(
                "tuplet id=\(tupletIDText(tuplet.id)) voice=\(tuplet.voice.rawValue) ratio=\(tuplet.ratio) "
                + "members=\(tuplet.memberEventIDs.map(\.rawValue).sorted()) "
                + "bracketVisible=\(tuplet.isBracketVisible) label=\(pt(tuplet.labelPosition)) "
                + "row=\(tuplet.rowIndex) bracket=[\(bracket)]"
            )
        }

        for ledger in layout.ledgerLines.sorted(by: byStart(\.start, \.id)) {
            lines.append("ledger row=\(ledger.row) start=\(pt(ledger.start)) end=\(pt(ledger.end))")
        }

        for bar in layout.measureBars.sorted(by: { ($0.row, Double($0.x), $0.id) < ($1.row, Double($1.x), $1.id) }) {
            lines.append("bar   row=\(bar.row) x=\(f(bar.x)) isFinal=\(bar.isFinal)")
        }

        for mark in layout.feelMarks.sorted(by: byStart(\.position, \.id)) {
            lines.append("feel  \(mark.feel) pos=\(pt(mark.position)) row=\(mark.rowIndex)")
        }

        for warning in layout.rhythmWarnings.sorted(by: byStart(\.position, \.id)) {
            let codes = warning.codes.map(\.rawValue).sorted().joined(separator: ",")
            lines.append(
                "warn  scope=\(warningScopeText(warning.scope)) codes=[\(codes)] "
                + "row=\(warning.rowIndex.map(String.init) ?? "-") "
                + "measure=\(warning.displayMeasureNumber.map(String.init) ?? "-") "
                + "pos=\(pt(warning.position)) size=\(f(warning.size.width))x\(f(warning.size.height))"
            )
        }

        return lines
    }

    /// Field-by-field text for the inferred duration a head carries, for the same reason as
    /// `dotSourceText(_:)` below.
    ///
    /// This is the analyzer's *verdict* about a note — base value, augmentation dots, tuplet
    /// ratio, and whether it could be engraved at all — and it is otherwise only indirectly
    /// observable in a digest, through the stems, beams and flags it produces. In a measure
    /// that resolves `.unsupported` there are no such primitives at all, so without this
    /// field a duration-inference regression inside an unsupported measure moves no golden
    /// line whatsoever.
    private static func rhythmText(_ rhythm: NotationRhythm) -> String {
        var text = rhythm.baseInterval.rawValue
        if rhythm.dotCount > 0 { text += "+\(rhythm.dotCount)dot" }
        if let tuplet = rhythm.tuplet { text += "/\(tuplet.actual):\(tuplet.normal)" }
        switch rhythm.support {
        case .supported:
            return text
        case let .indeterminate(code):
            return text + "[indeterminate:\(code.rawValue)]"
        case let .unsupported(code):
            return text + "[unsupported:\(code.rawValue)]"
        }
    }

    /// Field-by-field text for `RenderedRhythmDotSource`, rather than reflecting the enum
    /// via string interpolation. Reflection output is stable within a toolchain but is not
    /// a documented API contract across Swift versions.
    private static func dotSourceText(_ source: RenderedRhythmDotSource) -> String {
        switch source {
        case let .event(eventID):
            return "event:\(eventID.rawValue)"
        case let .rest(restID):
            return "rest:\(restID)"
        }
    }

    /// Field-by-field text for `RhythmWarningScope`, for the same reason as
    /// `dotSourceText(_:)`.
    private static func warningScopeText(_ scope: RhythmWarningScope) -> String {
        switch scope {
        case let .measure(index):
            return "measure:\(index)"
        case .chartFatal:
            return "chartFatal"
        }
    }

    /// Field-by-field text for `RhythmTupletID`. Also backs `tupletIDOrder(_:_:)` below —
    /// this ID doubles as the tuplet sort key, so an unstable reflected description would
    /// have silently reordered `tuplet` lines, not just reformatted them.
    private static func tupletIDText(_ id: RhythmTupletID) -> String {
        "m\(id.measureIndex)/v\(id.voice.rawValue)/g\(id.beatGroupIndex)/"
            + "t\(id.startTick)+\(id.durationTicks)/e\(id.stableMemberEventID.rawValue)"
    }

    /// Explicit field-by-field total order for `RenderedTuplet`, matching
    /// `tupletIDText(_:)`'s field order.
    private static func tupletIDOrder(_ lhs: RenderedTuplet, _ rhs: RenderedTuplet) -> Bool {
        let left = lhs.id, right = rhs.id
        if left.measureIndex != right.measureIndex { return left.measureIndex < right.measureIndex }
        if left.voice.rawValue != right.voice.rawValue { return left.voice.rawValue < right.voice.rawValue }
        if left.beatGroupIndex != right.beatGroupIndex { return left.beatGroupIndex < right.beatGroupIndex }
        if left.startTick != right.startTick { return left.startTick < right.startTick }
        if left.durationTicks != right.durationTicks { return left.durationTicks < right.durationTicks }
        return left.stableMemberEventID.rawValue < right.stableMemberEventID.rawValue
    }

    /// Total order for primitives that carry a point but no time column.
    private static func byStart<T, ID: Comparable>(
        _ point: KeyPath<T, CGPoint>,
        _ id: KeyPath<T, ID>
    ) -> (T, T) -> Bool {
        { lhs, rhs in
            let left = lhs[keyPath: point], right = rhs[keyPath: point]
            if left.x != right.x { return left.x < right.x }
            if left.y != right.y { return left.y < right.y }
            return lhs[keyPath: id] < rhs[keyPath: id]
        }
    }
}
