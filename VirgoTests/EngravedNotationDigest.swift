import CoreGraphics
import Foundation
import DrumNotation
@testable import Virgo

/// Serializes a rendered fixture to deterministic text for golden comparison.
///
/// The timeline/analyzer section is unchanged in meaning from the old
/// `NotationLayoutDigest`: it pins the resolved rhythm the real import path
/// produced. The geometry section now serializes the package
/// `EngravedNotation` — the same `ResolvedNotationInput` +
/// `NotationEngraver` path Task 7 will mount in production — rather than the
/// app-composed `NotationLayout`.
///
/// Engraving-line conventions (HPA-166 Task 6):
/// - primitive X stays absolute sheet-local;
/// - every primitive Y prints relative to its owning row's `staffCenterY`,
///   so the package's single global Y normalization is a digest no-op while
///   staff-relative geometry stays pinned;
/// - style values are the package `NotationEngravingStyle` semantics, not
///   the deleted app box widths/heights;
/// - hidden rests never appear: the projection filters them before
///   engraving, so none exist to serialize;
/// - app-only marks (`feel`, `warn`) are gone — the analyzer verdicts they
///   echoed remain pinned in the `tl-meas` `engraving=` fields.
///
/// Does NOT lock anything downstream of engraving — view modifiers, colour,
/// z-order, font rasterization. That boundary is deliberate.
@MainActor
enum EngravedNotationDigest {
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
        lines.append(contentsOf: engravingSection(result))
        return lines.joined(separator: "\n") + "\n"
    }

    /// The resolved-timeline section — identical in meaning to the old
    /// digest: it pins what the real DTX import/analyzer produced before
    /// any geometry ran.
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
            case let .warning(codes):
                engraving = "warning[" + codes.map(\.rawValue).sorted().joined(separator: ",") + "]"
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

    private static func engravingSection(_ result: FixtureRenderResult) -> [String] {
        let engraved = result.engraved
        let joins = Joins(result)
        var lines: [String] = []

        lines.append(contentsOf: styleLines(engraved))
        lines.append(contentsOf: rowLines(engraved))
        lines.append(contentsOf: measureLines(engraved))

        lines.append(contentsOf: headLines(engraved, joins: joins))
        lines.append(contentsOf: stemLines(engraved, joins: joins))
        lines.append(contentsOf: beamLines(engraved, joins: joins))
        lines.append(contentsOf: flagLines(engraved, joins: joins))
        lines.append(contentsOf: restLines(engraved, joins: joins))
        lines.append(contentsOf: controlLines(engraved, joins: joins))
        lines.append(contentsOf: articulationLines(engraved, joins: joins))
        lines.append(contentsOf: dotLines(engraved, joins: joins))
        lines.append(contentsOf: tupletLines(engraved, joins: joins))
        lines.append(contentsOf: ledgerLines(engraved, joins: joins))
        lines.append(contentsOf: barLines(engraved))
        return lines
    }

    private static func styleLines(_ engraved: EngravedNotation) -> [String] {
        let style = engraved.style
        let formatting = style.formatting
        return [
            "style staffSpace=\(f(formatting.staffSpace)) "
                + "rowWidth=\(f(formatting.availableRowWidth)) "
                + "rowInset=\(f(formatting.rowLeadingInset)) "
                + "stemWidth=\(f(formatting.stemWidth)) "
                + "colGap=\(f(formatting.minimumInterColumnClearance)) "
                + "quarterGap=\(f(formatting.minimumQuarterNoteSpacing)) "
                + "measGap=\(f(formatting.measureSpacing)) "
                + "leadInset=\(f(formatting.leadingMeasureInset)) "
                + "trailInset=\(f(formatting.trailingMeasureInset)) "
                + "dotRadius=\(f(formatting.rhythmDotRadius)) "
                + "dotSpacing=\(f(formatting.rhythmDotSpacing)) "
                + "overrides=default",
            "style2 rowHeight=\(f(style.rowHeight)) rowGap=\(f(style.rowVerticalSpacing)) "
                + "stemLen=\(f(style.stemLength)) stemExt=\(f(style.minimumStemExtensionPastChord)) "
                + "beamThick=\(f(style.beamThickness)) beamLevel=\(f(style.beamLevelSpacing)) "
                + "beamHook=\(f(style.beamHookLength)) flagGap=\(f(style.flagVerticalSpacing)) "
                + "ledgerExt=\(f(style.ledgerLineOverhang)) "
                + "restUp=\(f(style.upperVoiceRestOffset)) restDown=\(f(style.lowerVoiceRestOffset)) "
                + "stopSize=\(f(style.stopMarkSize)) stopStroke=\(f(style.stopMarkStrokeWidth)) "
                + "stopOff=\(f(style.stopMarkVerticalOffset)) "
                + "articOff=\(f(style.articulationVerticalOffset)) "
                + "tupletLine=\(f(style.tupletLineWidth)) "
                + "tupletLabel=\(f(style.tupletLabelSize.width))x\(f(style.tupletLabelSize.height)) "
                + "tupletOff=\(f(style.tupletVerticalOffset)) tupletHook=\(f(style.tupletHookLength)) "
                + "bar=\(f(style.barLineWidth)) "
                + "dblBar=\(f(style.doubleBarThinWidth))/\(f(style.doubleBarSpacing))"
                + "/\(f(style.doubleBarThickWidth)) "
                + "clef=\(f(style.clefWidth)) meter=\(f(style.meterWidth))",
            "dims  contentWidth=\(f(engraved.contentWidth)) "
                + "contentHeight=\(f(engraved.contentHeight)) "
                + "paintedBounds=\(rect(engraved.paintedBounds))"
        ]
    }

    private static func rowLines(_ engraved: EngravedNotation) -> [String] {
        // `pitch` is row-center minus the lowest row's center: deterministic
        // (row pitch is style-derived) and immune to the single global shift.
        let baseCenterY = engraved.rows.map(\.staffCenterY).min() ?? 0
        return engraved.rows.sorted { $0.index < $1.index }.map { row in
            let measures = engraved.measures
                .filter { $0.rowIndex == row.index }
                .sorted { $0.index < $1.index }
                .map { "m\($0.index)" }
                .joined(separator: ",")
            let lineYs = row.staffLineYs
                .map { f($0 - row.staffCenterY) }
                .joined(separator: ",")
            let meter = row.meterSignature.meter
            return "row   \(row.index) measures=[\(measures)] "
                + "pitch=\(f(row.staffCenterY - baseCenterY)) "
                + "lines=[\(lineYs)] "
                + "clef=\(pt(relativeTo: row.staffCenterY, row.clef.position)) "
                + "meter=\(meter.beats)/\(meter.noteValue) "
                + "\(pt(relativeTo: row.staffCenterY, row.meterSignature.position))"
        }
    }

    private static func measureLines(_ engraved: EngravedNotation) -> [String] {
        engraved.measures
            .sorted { ($0.rowIndex, $0.index) < ($1.rowIndex, $1.index) }
            .map { measure in
                "meas  m\(measure.index) row=\(measure.rowIndex) "
                    + "xOffset=\(f(measure.xOffset)) width=\(f(measure.width)) "
                    + "startTick=\(measure.startTick) durationTicks=\(measure.durationTicks) "
                    + "meter=\(measure.meter.beats)/\(measure.meter.noteValue)"
            }
    }

    private static func rect(_ rect: CGRect) -> String {
        rect.isNull
            ? "null"
            : "(\(f(rect.minX)),\(f(rect.minY)),\(f(rect.width)),\(f(rect.height)))"
    }

    /// Point text with Y relative to a row's staff center — the digest's
    /// one coordinate convention for every primitive.
    private static func pt(relativeTo centerY: CGFloat, _ point: CGPoint) -> String {
        "(\(f(point.x)),\(f(point.y - centerY)))"
    }

    /// Field-by-field text for `NotationVoiceRole` (an Int-raw enum — its
    /// interpolated `rawValue` would print `0`/`1`, not a voice name).
    private static func voiceText(_ voice: NotationVoiceRole) -> String {
        switch voice {
        case .upper: return "upper"
        case .lower: return "lower"
        }
    }
}

@MainActor
extension EngravedNotationDigest {
    /// Lookup tables shared by the engraving-line builders: the resolved
    /// package input (for event ticks and control steps the engraved
    /// primitives do not carry), the analyzer snapshot (for lane, variant
    /// and rhythm verdicts the package never sees), and each row's
    /// `staffCenterY` for the row-relative Y convention.
    @MainActor
    struct Joins {
        let centerYByRow: [Int: CGFloat]
        let noteByID: [Int: ResolvedNote]
        let restByID: [Int: ResolvedRest]
        let controlByID: [Int: ResolvedControl]
        let snapshotNoteByID: [Int: RhythmLayoutNote]
        let snapshotControlByID: [Int: RhythmLayoutControl]
        let rowByNoteID: [Int: Int]

        init(_ result: FixtureRenderResult) {
            let engraved = result.engraved
            centerYByRow = Dictionary(
                engraved.rows.map { ($0.index, $0.staffCenterY) },
                uniquingKeysWith: { first, _ in first }
            )
            noteByID = Dictionary(
                result.resolvedInput.notes.map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            restByID = Dictionary(
                result.resolvedInput.rests.map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            controlByID = Dictionary(
                result.resolvedInput.controls.map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            snapshotNoteByID = Dictionary(
                result.snapshot.notes.map { ($0.eventID.rawValue, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            snapshotControlByID = Dictionary(
                result.snapshot.controls.map { ($0.eventID.rawValue, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            rowByNoteID = Dictionary(
                engraved.noteHeads.map { ($0.noteID, $0.rowIndex) },
                uniquingKeysWith: { first, _ in first }
            )
        }

        /// Point text with Y relative to `row`'s staff center. A missing
        /// row falls back to the raw Y rather than trapping — a compose bug
        /// should surface as a golden diff, not a crashed test host.
        func pt(_ point: CGPoint, row: Int) -> String {
            EngravedNotationDigest.pt(
                relativeTo: centerYByRow[row] ?? 0,
                point
            )
        }

        /// The owning row of a note-bearing primitive (stems, beams, flags,
        /// articulations) — every member shares one row by the beam
        /// partition, so the first member's row is the primitive's row.
        func row(forNoteID id: Int) -> Int { rowByNoteID[id] ?? 0 }
    }

    // MARK: - Note heads

    fileprivate static func headLines(
        _ engraved: EngravedNotation,
        joins: Joins
    ) -> [String] {
        let heads = engraved.noteHeads.sorted { lhs, rhs in
            let lp = joins.noteByID[lhs.noteID]?.position
            let rp = joins.noteByID[rhs.noteID]?.position
            return (lp?.measureIndex ?? -1, lp?.localTick ?? -1,
                    Double(lhs.position.y), lhs.noteID)
                < (rp?.measureIndex ?? -1, rp?.localTick ?? -1,
                   Double(rhs.position.y), rhs.noteID)
        }
        return heads.map { head in
            let note = joins.snapshotNoteByID[head.noteID]
            let resolved = note.flatMap {
                DrumNotationCatalog.resolve(noteType: $0.noteType, sourceLaneID: $0.sourceLaneID)
            }
            return "head  m\(head.measureIndex) "
                + "t\(String(format: "%04d", locale: posix, note?.position.localTick ?? -1)) "
                + "abs\(String(format: "%04d", locale: posix, note?.position.absoluteTick ?? -1)) "
                + "id=\(head.noteID) "
                + "pos=\(joins.pt(head.position, row: head.rowIndex)) "
                + "\(resolved?.definition.gameplayInstrument.description ?? "-") "
                + "notehead=\(head.noteheadStyle.rawValue) "
                + "variant=\(resolved?.variant.rawValue ?? "-") "
                + "voice=\(voiceText(head.voice)) stem=\(head.stemDirection.rawValue) "
                + "row=\(head.rowIndex) lane=\(note?.sourceLaneID ?? "-") "
                + "interval=\(note?.rhythm.baseInterval.rawValue ?? "-") "
                + "rhythm=\(note.map { rhythmText($0.rhythm) } ?? "-") "
                + "durTicks=\(note.map { String($0.durationTicks) } ?? "-") "
                + "step=\(head.staffStep) dur=\(head.duration.rawValue)"
        }
    }

    // MARK: - Stems, beams, flags

    fileprivate static func stemLines(
        _ engraved: EngravedNotation,
        joins: Joins
    ) -> [String] {
        engraved.stems.sorted(by: byStart(\.start, ids: \.noteIDs)).map { stem in
            let row = joins.row(forNoteID: stem.noteIDs.first ?? -1)
            return "stem  ids=\(stem.noteIDs.sorted()) dir=\(stem.direction.rawValue) "
                + "start=\(joins.pt(stem.start, row: row)) end=\(joins.pt(stem.end, row: row))"
        }
    }

    fileprivate static func beamLines(
        _ engraved: EngravedNotation,
        joins: Joins
    ) -> [String] {
        engraved.beams.sorted(by: byStart(\.start, ids: \.noteIDs)).map { beam in
            let row = joins.row(forNoteID: beam.noteIDs.first ?? -1)
            return "beam  ids=\(beam.noteIDs.sorted()) dir=\(beam.direction.rawValue) "
                + "level=\(beam.level) kind=\(beam.kind.rawValue) "
                + "start=\(joins.pt(beam.start, row: row)) end=\(joins.pt(beam.end, row: row)) "
                + "thickness=\(f(beam.thickness))"
        }
    }

    fileprivate static func flagLines(
        _ engraved: EngravedNotation,
        joins: Joins
    ) -> [String] {
        engraved.flags.sorted {
            ($0.origin.x, $0.origin.y, $0.noteID, $0.flagIndex)
                < ($1.origin.x, $1.origin.y, $1.noteID, $1.flagIndex)
        }.map { flag in
            "flag  head=\(flag.noteID) dir=\(flag.stemDirection.rawValue) "
                + "index=\(flag.flagIndex) dur=\(flag.duration.rawValue) "
                + "origin=\(joins.pt(flag.origin, row: joins.row(forNoteID: flag.noteID)))"
        }
    }

    // MARK: - Rests and controls

    fileprivate static func restLines(
        _ engraved: EngravedNotation,
        joins: Joins
    ) -> [String] {
        engraved.rests.sorted { lhs, rhs in
            let lp = joins.restByID[lhs.restID]?.position
            let rp = joins.restByID[rhs.restID]?.position
            return (lhs.measureIndex, lp?.localTick ?? -1,
                    Double(lhs.position.y), lhs.restID)
                < (rhs.measureIndex, rp?.localTick ?? -1,
                   Double(rhs.position.y), rhs.restID)
        }.map { rest in
            let resolved = joins.restByID[rest.restID]
            return "rest  m\(rest.measureIndex) "
                + "t\(String(format: "%04d", locale: posix, resolved?.position.localTick ?? -1)) "
                + "id=\(rest.restID) voice=\(voiceText(rest.voice)) "
                + "dur=\(rest.duration.rawValue) full=\(rest.isFullMeasure) "
                + "dots=\(resolved?.dotCount ?? -1) "
                + "ticks=\(resolved?.durationTicks ?? -1) "
                + "pos=\(joins.pt(rest.position, row: rest.rowIndex))"
        }
    }

    fileprivate static func controlLines(
        _ engraved: EngravedNotation,
        joins: Joins
    ) -> [String] {
        engraved.controls.sorted { lhs, rhs in
            let lp = joins.controlByID[lhs.controlID]?.position
            let rp = joins.controlByID[rhs.controlID]?.position
            return (lhs.measureIndex, lp?.localTick ?? -1, lhs.controlID)
                < (rhs.measureIndex, rp?.localTick ?? -1, rhs.controlID)
        }.map { control in
            let resolved = joins.controlByID[control.controlID]
            let snapshot = joins.snapshotControlByID[control.controlID]
            return "ctrl  m\(control.measureIndex) "
                + "t\(String(format: "%04d", locale: posix, resolved?.position.localTick ?? -1)) "
                + "id=\(control.controlID) kind=\(control.kind.rawValue) "
                + "target=\(snapshot?.event.targetLaneID ?? "-") "
                + "pos=\(joins.pt(control.position, row: control.rowIndex)) "
                + "lane=\(snapshot?.event.sourceLaneID ?? "-") "
                + "step=\(resolved?.targetStaffStep ?? 0)"
        }
    }

    // MARK: - Dots, articulations, tuplets, ledgers, bars

    fileprivate static func articulationLines(
        _ engraved: EngravedNotation,
        joins: Joins
    ) -> [String] {
        engraved.articulations.sorted {
            ($0.position.x, $0.position.y, $0.noteID) < ($1.position.x, $1.position.y, $1.noteID)
        }.map { artic in
            "artic kind=\(artic.kind.rawValue) head=\(artic.noteID) "
                + "row=\(joins.row(forNoteID: artic.noteID)) "
                + "pos=\(joins.pt(artic.position, row: joins.row(forNoteID: artic.noteID)))"
        }
    }

    fileprivate static func dotLines(
        _ engraved: EngravedNotation,
        joins: Joins
    ) -> [String] {
        engraved.rhythmDots.sorted {
            ($0.position.x, $0.position.y, dotSourceText($0.source))
                < ($1.position.x, $1.position.y, dotSourceText($1.source))
        }.map { dot in
            "dot   source=\(dotSourceText(dot.source)) "
                + "pos=\(joins.pt(dot.position, row: dot.rowIndex)) row=\(dot.rowIndex)"
        }
    }

    fileprivate static func tupletLines(
        _ engraved: EngravedNotation,
        joins: Joins
    ) -> [String] {
        engraved.tuplets.sorted { $0.tupletID < $1.tupletID }.map { tuplet in
            let bracket = tuplet.bracketPoints
                .map { joins.pt($0, row: tuplet.rowIndex) }
                .joined(separator: " ")
            return "tuplet id=\(tuplet.tupletID) voice=\(voiceText(tuplet.voice)) "
                + "ratio=\(tuplet.ratio.actual):\(tuplet.ratio.normal) "
                + "notes=\(tuplet.memberNoteIDs.sorted()) rests=\(tuplet.memberRestIDs.sorted()) "
                + "bracketVisible=\(tuplet.isBracketVisible) "
                + "label=\(joins.pt(tuplet.labelPosition, row: tuplet.rowIndex)) "
                + "row=\(tuplet.rowIndex) bracket=[\(bracket)]"
        }
    }

    fileprivate static func ledgerLines(
        _ engraved: EngravedNotation,
        joins: Joins
    ) -> [String] {
        engraved.ledgerLines.sorted {
            ($0.start.x, $0.start.y, $0.noteID) < ($1.start.x, $1.start.y, $1.noteID)
        }.map { ledger in
            "ledger row=\(ledger.rowIndex) "
                + "start=\(joins.pt(ledger.start, row: ledger.rowIndex)) "
                + "end=\(joins.pt(ledger.end, row: ledger.rowIndex))"
        }
    }

    fileprivate static func barLines(_ engraved: EngravedNotation) -> [String] {
        engraved.measureBars.sorted {
            ($0.rowIndex, $0.x, $0.measureIndex, $0.isFinal ? 1 : 0)
                < ($1.rowIndex, $1.x, $1.measureIndex, $1.isFinal ? 1 : 0)
        }.map { bar in
            "bar   row=\(bar.rowIndex) x=\(f(bar.x)) isFinal=\(bar.isFinal) "
                + "meas=\(bar.measureIndex)"
        }
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

    /// Field-by-field text for `EngravedRhythmDot.Source`, rather than reflecting the enum
    /// via string interpolation. Reflection output is stable within a toolchain but is not
    /// a documented API contract across Swift versions. The note/rest namespaces stay
    /// separate, matching the package's collision-safe ID design.
    private static func dotSourceText(_ source: EngravedRhythmDot.Source) -> String {
        switch source {
        case let .note(noteID):
            return "note:\(noteID)"
        case let .rest(restID):
            return "rest:\(restID)"
        }
    }

    /// Total order for primitives that carry a point and a member-ID list
    /// but no time column (stems, beams).
    private static func byStart<T>(
        _ point: KeyPath<T, CGPoint>,
        ids: KeyPath<T, [Int]>
    ) -> (T, T) -> Bool {
        { lhs, rhs in
            let left = lhs[keyPath: point], right = rhs[keyPath: point]
            if left.x != right.x { return left.x < right.x }
            if left.y != right.y { return left.y < right.y }
            return lhs[keyPath: ids].lexicographicallyPrecedes(rhs[keyPath: ids])
        }
    }
}
