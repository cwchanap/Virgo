import CoreGraphics

/// HPA-166 Task 3 — the single package engraving facade. `engrave` is the
/// only production route from validated `ResolvedNotationInput` to the
/// immutable `EngravedNotation`: it owns vertical/primitive geometry on top
/// of the measured formatter and never duplicates horizontal formatting.
///
/// Pinned order (per the design): stem groups/topology first, one visible
/// flag plan per group, the plan-driven formatter path, then raw vertical
/// and primitive geometry, one painted-bounds pass, and exactly one package
/// Y normalization. Task 4 fills the topology-driven arrays (stems, beams,
/// flags, articulations, controls, tuplets, measure bars) inside this same
/// compose path; the result contract already carries them.
public enum NotationEngraver {
    public static func engrave(
        _ input: ResolvedNotationInput,
        style: NotationEngravingStyle
    ) throws -> EngravedNotation {
        let stemTopology = StemTopologyBuilder().build(input)
        let formatted = NotationFormatter.format(
            input,
            style: style.formatting,
            stemTopology: stemTopology
        )
        return SheetComposer(input: input, style: style, formatted: formatted).compose()
    }
}

/// Composes final sheet geometry from one formatted result: rows and
/// measures from the formatted assignments, note heads/rests at formatted
/// X and package staff-step Y, ledger lines and rhythm dots from the actual
/// Bravura painted bounds, then the single Y normalization.
private struct SheetComposer {
    /// Staff-step convention: 0 is the bottom line, 4 the middle line, 8 the
    /// top line (ledger steps continue by twos outside the staff).
    private static let bottomLineStaffStep = 0
    private static let middleLineStaffStep = 4
    private static let topLineStaffStep = 8

    let input: ResolvedNotationInput
    let style: NotationEngravingStyle
    let formatted: FormattedNotation

    private var formatting: NotationFormattingStyle { style.formatting }
    /// Row pitch — the deterministic staff-center spacing between rows.
    private var rowPitch: CGFloat { style.rowHeight + style.rowVerticalSpacing }
    private var halfStaffSpace: CGFloat { formatting.staffSpace / 2 }

    /// One row's raw staff center: the staff is centered in each `rowHeight`
    /// band, so row 0's center is `rowHeight / 2` and successive centers are
    /// one row pitch apart — deterministic from the style alone.
    private func staffCenterY(rowIndex: Int) -> CGFloat {
        style.rowHeight / 2 + CGFloat(rowIndex) * rowPitch
    }

    /// Raw sheet Y of a pitch-ascending staff step on a row.
    private func staffStepY(_ staffStep: Int, rowIndex: Int) -> CGFloat {
        staffCenterY(rowIndex: rowIndex)
            - CGFloat(staffStep - Self.middleLineStaffStep) * halfStaffSpace
    }

    /// Ledger steps outside the staff, walking away from the nearer line by
    /// twos — mirrors the engine's `ledgerSteps(for:)` in package
    /// pitch-ascending convention.
    private func ledgerSteps(for staffStep: Int) -> [Int] {
        if staffStep > Self.topLineStaffStep {
            return stride(from: Self.topLineStaffStep + 2, through: staffStep, by: 2).map { $0 }
        }
        if staffStep < Self.bottomLineStaffStep {
            return stride(from: Self.bottomLineStaffStep - 2, through: staffStep, by: -2).map { $0 }
        }
        return []
    }

    /// One pending note head in raw (unshifted) sheet coordinates.
    private struct PendingNoteHead {
        let note: ResolvedNote
        let rowIndex: Int
        let position: CGPoint
        let bounds: CGRect
    }

    /// One pending rest in raw (unshifted) sheet coordinates.
    private struct PendingRest {
        let rest: ResolvedRest
        let rowIndex: Int
        let position: CGPoint
        let bounds: CGRect
    }

    /// The shared trailing-dot anchor: which source owns the dots, which row
    /// they land on, the Y they center on, and the ink they trail.
    private struct DotAnchor {
        let source: EngravedRhythmDot.Source
        let rowIndex: Int
        let centerY: CGFloat
        let inkMaxX: CGFloat
        let dotCount: Int
    }

    /// Raw-geometry accumulator: pending primitives plus the running ink
    /// union, all still in unshifted sheet coordinates.
    private struct RawGeometry {
        var noteHeads: [PendingNoteHead] = []
        var rests: [PendingRest] = []
        var ledgerLines: [EngravedLedgerLine] = []
        var rhythmDots: [EngravedRhythmDot] = []
        var paintedUnion: CGRect?

        mutating func include(_ bounds: CGRect) {
            paintedUnion = paintedUnion?.union(bounds) ?? bounds
        }
    }

    func compose() -> EngravedNotation {
        var raw = RawGeometry()
        collect(&raw)
        // The one Y normalization: raw ink above Y 0 shifts rows and every
        // primitive down by the same amount; nothing else ever translates.
        let shift = max(0, -(raw.paintedUnion?.minY ?? 0))
        let paintedBounds = raw.paintedUnion?.offsetBy(dx: 0, dy: shift)
        let rows = Set(formatted.measures.map(\.rowIndex)).sorted().map {
            EngravedRow(index: $0, staffCenterY: staffCenterY(rowIndex: $0) + shift)
        }
        let measuresByIndex = Dictionary(
            input.measures.map { ($0.index, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let measures = formatted.measures.compactMap { formattedMeasure -> EngravedMeasure? in
            guard let measure = measuresByIndex[formattedMeasure.index] else { return nil }
            return EngravedMeasure(
                index: measure.index,
                rowIndex: formattedMeasure.rowIndex,
                xOffset: formattedMeasure.xOffset,
                width: formattedMeasure.width,
                startTick: measure.startTick,
                durationTicks: measure.durationTicks,
                meter: measure.meter
            )
        }
        return EngravedNotation(
            formatted: formatted,
            rows: rows,
            measures: measures,
            noteHeads: raw.noteHeads.map { materialize($0, shift: shift) },
            rests: raw.rests.map { materialize($0, shift: shift) },
            stems: [],
            beams: [],
            flags: [],
            ledgerLines: raw.ledgerLines.map { $0.translated(byY: shift) },
            rhythmDots: raw.rhythmDots.map { $0.translated(byY: shift) },
            articulations: [],
            controls: [],
            tuplets: [],
            measureBars: [],
            paintedBounds: paintedBounds ?? .null,
            contentWidth: contentWidth(painted: paintedBounds),
            contentHeight: contentHeight(painted: paintedBounds, rows: rows)
        )
    }

    /// Sheet width: the widest laid-out row's right edge or the painted ink's,
    /// whichever is wider (a flag/displacement may out-ink the column span).
    private func contentWidth(painted: CGRect?) -> CGFloat {
        let contentRight = formatted.measures.map { $0.xOffset + $0.width }.max() ?? 0
        return max(contentRight, painted?.maxX ?? 0)
    }

    /// Sheet height: the painted bottom or the lowest row's staff bottom —
    /// the sheet always covers its staff lines even when ink sits high.
    private func contentHeight(painted: CGRect?, rows: [EngravedRow]) -> CGFloat {
        let staffBottom = rows.last.map {
            $0.staffCenterY + CGFloat(Self.topLineStaffStep - Self.middleLineStaffStep) * halfStaffSpace
        } ?? 0
        return max(painted?.maxY ?? 0, staffBottom)
    }

    /// Pass 1: walks the formatted columns once, resolving every note head
    /// and rest to its raw position/painted bounds plus derived ledgers and
    /// dots. All Y is raw — the union drives the single shift afterwards.
    private func collect(_ raw: inout RawGeometry) {
        let notesByID = Dictionary(input.notes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let restsByID = Dictionary(input.rests.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for measure in formatted.measures {
            for column in measure.columns {
                for head in column.noteHeads {
                    guard let note = notesByID[head.noteID] else { continue }
                    collect(note: note, headCenterX: head.headCenterX, measure: measure, raw: &raw)
                }
                for formattedRest in column.rests {
                    guard let rest = restsByID[formattedRest.restID] else { continue }
                    collect(rest: rest, visualX: formattedRest.visualX, measure: measure, raw: &raw)
                }
            }
        }
    }

    private func collect(
        note: ResolvedNote,
        headCenterX: CGFloat,
        measure: FormattedMeasure,
        raw: inout RawGeometry
    ) {
        let position = CGPoint(
            x: headCenterX,
            y: staffStepY(note.staffStep, rowIndex: measure.rowIndex)
        )
        let bounds = PercussionGlyphMetrics.notehead(
            style: note.noteheadStyle,
            duration: note.duration,
            stemDirection: note.stemDirection,
            staffSpace: formatting.staffSpace
        ).paintedBounds.offsetBy(dx: position.x, dy: position.y)
        raw.include(bounds)
        raw.noteHeads.append(PendingNoteHead(
            note: note, rowIndex: measure.rowIndex, position: position, bounds: bounds
        ))
        collectLedgerLines(note: note, rowIndex: measure.rowIndex, headBounds: bounds, raw: &raw)
        // Unsupported-duration heads keep their ink but no rhythm semantics.
        guard note.isRhythmEngravable else { return }
        collectDots(anchor: DotAnchor(
            source: .note(note.id),
            rowIndex: measure.rowIndex,
            centerY: position.y,
            inkMaxX: bounds.maxX,
            dotCount: note.dotCount
        ), raw: &raw)
    }

    private func collect(
        rest: ResolvedRest,
        visualX: CGFloat,
        measure: FormattedMeasure,
        raw: inout RawGeometry
    ) {
        let voiceOffset = rest.voice == .upper ? style.upperVoiceRestOffset : style.lowerVoiceRestOffset
        let position = CGPoint(
            x: visualX,
            y: staffCenterY(rowIndex: measure.rowIndex) + voiceOffset
        )
        let bounds = PercussionGlyphMetrics.rest(
            duration: rest.duration,
            staffSpace: formatting.staffSpace
        ).paintedBounds.offsetBy(dx: position.x, dy: position.y)
        raw.include(bounds)
        raw.rests.append(PendingRest(
            rest: rest, rowIndex: measure.rowIndex, position: position, bounds: bounds
        ))
        collectDots(anchor: DotAnchor(
            source: .rest(rest.id),
            rowIndex: measure.rowIndex,
            centerY: position.y,
            inkMaxX: bounds.maxX,
            dotCount: rest.dotCount
        ), raw: &raw)
    }

    /// One ledger line per staff step outside the staff, overhanging the
    /// head's painted bounds; the stroke is `barLineWidth` (the app's
    /// ledger/staff-furniture width).
    private func collectLedgerLines(
        note: ResolvedNote,
        rowIndex: Int,
        headBounds: CGRect,
        raw: inout RawGeometry
    ) {
        for step in ledgerSteps(for: note.staffStep) {
            let y = staffStepY(step, rowIndex: rowIndex)
            let startX = headBounds.minX - style.ledgerLineOverhang
            let endX = headBounds.maxX + style.ledgerLineOverhang
            let bounds = CGRect(
                x: startX,
                y: y - style.barLineWidth / 2,
                width: endX - startX,
                height: style.barLineWidth
            )
            raw.include(bounds)
            raw.ledgerLines.append(EngravedLedgerLine(
                noteID: note.id,
                rowIndex: rowIndex,
                start: CGPoint(x: startX, y: y),
                end: CGPoint(x: endX, y: y),
                paintedBounds: bounds
            ))
        }
    }

    /// Rhythm dots trail the painted ink: first center at
    /// `maxX + spacing + radius`, each next dot one diameter+spacing further.
    /// The formatter reserves the same footprint, so painted ink never
    /// exceeds the reserved collision span.
    private func collectDots(anchor: DotAnchor, raw: inout RawGeometry) {
        let radius = formatting.rhythmDotRadius
        let pitch = radius * 2 + formatting.rhythmDotSpacing
        for index in 0..<anchor.dotCount {
            let center = CGPoint(
                x: anchor.inkMaxX + formatting.rhythmDotSpacing + radius + CGFloat(index) * pitch,
                y: anchor.centerY
            )
            let bounds = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            raw.include(bounds)
            raw.rhythmDots.append(EngravedRhythmDot(
                source: anchor.source,
                position: center,
                rowIndex: anchor.rowIndex,
                paintedBounds: bounds
            ))
        }
    }

    /// Materializes one raw note head at its final (shifted) position.
    private func materialize(_ raw: PendingNoteHead, shift: CGFloat) -> EngravedNoteHead {
        EngravedNoteHead(
            noteID: raw.note.id,
            measureIndex: raw.note.position.measureIndex,
            rowIndex: raw.rowIndex,
            staffStep: raw.note.staffStep,
            voice: raw.note.voice,
            stemDirection: raw.note.stemDirection,
            noteheadStyle: raw.note.noteheadStyle,
            duration: raw.note.duration,
            position: CGPoint(x: raw.position.x, y: raw.position.y + shift),
            paintedBounds: raw.bounds.offsetBy(dx: 0, dy: shift)
        )
    }

    /// Materializes one raw rest at its final (shifted) position.
    private func materialize(_ raw: PendingRest, shift: CGFloat) -> EngravedRest {
        EngravedRest(
            restID: raw.rest.id,
            measureIndex: raw.rest.position.measureIndex,
            rowIndex: raw.rowIndex,
            voice: raw.rest.voice,
            duration: raw.rest.duration,
            isFullMeasure: raw.rest.isFullMeasure,
            position: CGPoint(x: raw.position.x, y: raw.position.y + shift),
            paintedBounds: raw.bounds.offsetBy(dx: 0, dy: shift)
        )
    }
}

/// The one package Y translation applied after the painted-bounds pass —
/// file-private so the only route to a moved primitive is the composer.
extension EngravedLedgerLine {
    fileprivate func translated(byY delta: CGFloat) -> EngravedLedgerLine {
        EngravedLedgerLine(
            noteID: noteID,
            rowIndex: rowIndex,
            start: CGPoint(x: start.x, y: start.y + delta),
            end: CGPoint(x: end.x, y: end.y + delta),
            paintedBounds: paintedBounds.offsetBy(dx: 0, dy: delta)
        )
    }
}

extension EngravedRhythmDot {
    fileprivate func translated(byY delta: CGFloat) -> EngravedRhythmDot {
        EngravedRhythmDot(
            source: source,
            position: CGPoint(x: position.x, y: position.y + delta),
            rowIndex: rowIndex,
            paintedBounds: paintedBounds.offsetBy(dx: 0, dy: delta)
        )
    }
}
