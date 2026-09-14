import CoreGraphics

/// Deterministic measured formatter (HPA-164). Builds one logical column per
/// exact local tick per measure — including explicit start (`0`) and end
/// (`durationTicks`) anchors — applies the pinned VexFlow staff-second
/// displacement, spaces columns one gap at a time (no global density scan or
/// iterative relaxation), sizes each measure from its own content, packs
/// whole measures onto rows greedily, and owns the tick → row/X lookup for
/// the live playhead. Every output X is final sheet-local (row-leading inset
/// included); the caller applies no post-format X transform.
public enum NotationFormatter {
    /// Formats already-validated resolved input at `style`. The throwing
    /// signature is the pinned API the app and later tasks call through.
    public static func format(
        _ input: ResolvedNotationInput,
        style: NotationFormattingStyle
    ) throws -> FormattedNotation {
        // Phase 1: per-measure column layout with local X and natural width.
        let laidOut = input.measures
            .sorted { $0.index < $1.index }
            .map { layoutMeasure($0, input: input, style: style) }

        // Phase 2: greedy whole-measure row packing, then sheet-local finalize.
        var measures: [FormattedMeasure] = []
        measures.reserveCapacity(laidOut.count)
        var rowIndex = 0
        var rowX = style.rowLeadingInset
        for layout in laidOut {
            if rowX > style.rowLeadingInset, rowX + layout.width > style.availableRowWidth {
                rowIndex += 1
                rowX = style.rowLeadingInset
            }
            let contentCenterX = rowX
                + (style.leadingMeasureInset + layout.width - style.trailingMeasureInset) / 2
            let columns = layout.columns.map { column in
                finalizeColumn(
                    column,
                    rowX: rowX,
                    contentCenterX: contentCenterX,
                    isFullMeasureRest: layout.fullMeasureRestTicks.contains(column.tick)
                )
            }
            measures.append(FormattedMeasure(
                index: layout.measure.index,
                rowIndex: rowIndex,
                xOffset: rowX,
                width: layout.width,
                columns: columns
            ))
            rowX += layout.width + style.measureSpacing
        }
        return FormattedNotation(measures: measures)
    }

    // MARK: Per-measure spacing

    /// Intermediate column layout in measure-local coordinates (origin = the
    /// measure's row origin).
    private struct LaidOutColumn {
        let tick: Int
        var x: CGFloat = 0
        /// Note IDs in stable ID order (every note at this tick).
        let noteIDs: [Int]
        /// Staff-second displacement per note ID (absent = undisplaced).
        let shifts: [Int: CGFloat]
        let restID: Int?
        let leftExtent: CGFloat
        let rightExtent: CGFloat
    }

    private struct LaidOutMeasure {
        let measure: ResolvedMeasure
        var columns: [LaidOutColumn]
        let width: CGFloat
        let fullMeasureRestTicks: Set<Int>
    }

    private static func layoutMeasure(
        _ measure: ResolvedMeasure,
        input: ResolvedNotationInput,
        style: NotationFormattingStyle
    ) -> LaidOutMeasure {
        var notesByTick: [Int: [ResolvedNote]] = [:]
        for note in input.notes where note.position.measureIndex == measure.index {
            notesByTick[note.position.localTick, default: []].append(note)
        }
        var restsByTick: [Int: [ResolvedRest]] = [:]
        var fullMeasureRestTicks = Set<Int>()
        for rest in input.rests where rest.position.measureIndex == measure.index {
            restsByTick[rest.position.localTick, default: []].append(rest)
            if rest.isFullMeasure { fullMeasureRestTicks.insert(rest.position.localTick) }
        }
        var ticks = Set([0, measure.durationTicks])
        ticks.formUnion(notesByTick.keys)
        ticks.formUnion(restsByTick.keys)
        for control in input.controls where control.position.measureIndex == measure.index {
            ticks.insert(control.position.localTick)
        }

        var columns = ticks.sorted().map { tick -> LaidOutColumn in
            buildColumn(
                tick: tick,
                notes: (notesByTick[tick] ?? []).sorted { $0.id < $1.id },
                rests: (restsByTick[tick] ?? []).sorted { $0.id < $1.id },
                style: style
            )
        }
        // One-pass gap rule: tick 0 sits at the leading inset, each next column
        // advances by max(rhythmic, collision). No chart-wide scale — a dense
        // measure never rescales a sparse neighbor.
        var x = style.leadingMeasureInset
        for index in columns.indices {
            if index > 0 {
                x += requiredGap(
                    from: columns[index - 1],
                    to: columns[index],
                    style: style,
                    ticksPerWholeNote: input.ticksPerWholeNote
                )
            }
            columns[index].x = x
        }
        // Natural width: the end anchor's position plus the trailing inset.
        let width = (columns.last?.x ?? style.leadingMeasureInset) + style.trailingMeasureInset
        return LaidOutMeasure(
            measure: measure,
            columns: columns,
            width: width,
            fullMeasureRestTicks: fullMeasureRestTicks
        )
    }

    /// `rhythmicGap = minimumQuarterNoteSpacing * deltaTicks * 4 /
    /// ticksPerWholeNote` against `collisionGap = previous.rightExtent +
    /// minimumInterColumnClearance + next.leftExtent`, taking the larger. The
    /// delta converts to CGFloat before scaling, so a near-`Int.max` tick
    /// delta cannot overflow (exact for realistic grid values; the final
    /// conversion keeps the value finite).
    private static func requiredGap(
        from previous: LaidOutColumn,
        to next: LaidOutColumn,
        style: NotationFormattingStyle,
        ticksPerWholeNote: Int
    ) -> CGFloat {
        let rhythmicGap = CGFloat(next.tick - previous.tick)
            * 4 * style.minimumQuarterNoteSpacing / CGFloat(ticksPerWholeNote)
        let collisionGap = previous.rightExtent + style.minimumInterColumnClearance + next.leftExtent
        return max(rhythmicGap, collisionGap)
    }

    private static func finalizeColumn(
        _ column: LaidOutColumn,
        rowX: CGFloat,
        contentCenterX: CGFloat,
        isFullMeasureRest: Bool
    ) -> FormattedColumn {
        FormattedColumn(
            localTick: column.tick,
            logicalColumnX: rowX + column.x,
            noteHeads: column.noteIDs.map { noteID in
                FormattedNoteHead(noteID: noteID, headCenterX: rowX + column.x + (column.shifts[noteID] ?? 0))
            },
            rest: column.restID.map { restID in
                // The full-measure rest's timing anchor stays on the column;
                // its visual centers in the measure content span, finalized
                // now that the width is known.
                FormattedRest(restID: restID, visualX: isFullMeasureRest ? contentCenterX : rowX + column.x)
            },
            leftExtent: column.leftExtent,
            rightExtent: column.rightExtent
        )
    }

    private static func buildColumn(
        tick: Int,
        notes: [ResolvedNote],
        rests: [ResolvedRest],
        style: NotationFormattingStyle
    ) -> LaidOutColumn {
        let shifts = staffSecondShifts(for: notes, style: style)

        var ink = InkExtents()
        for note in notes {
            let centerX = shifts[note.id] ?? 0
            let headMetrics = PercussionGlyphMetrics.notehead(
                style: note.noteheadStyle, duration: note.duration,
                stemDirection: note.stemDirection, staffSpace: style.staffSpace
            )
            let head = headMetrics.paintedBounds
            ink.union(centerX + head.minX)
            ink.union(centerX + head.maxX)
            if let dotRight = dotInkRight(after: centerX + head.maxX, dotCount: note.dotCount, style: style) {
                ink.union(dotRight)
            }
            // Flags hang on the shared stem axis — the head glyph's
            // stemUpSE/stemDownNW anchor at the undisplaced column X — never on
            // the displaced head. A column with flagged notes in both
            // directions unions each flag at its own direction's axis.
            if let flagDuration = note.visibleFlagDuration {
                let flag = PercussionGlyphMetrics.flag(
                    duration: flagDuration,
                    direction: note.stemDirection,
                    staffSpace: style.staffSpace
                )
                let attachmentX = headMetrics.stemAnchorOffset.x - flag.attachmentOffset.x
                ink.union(attachmentX + flag.paintedBounds.minX)
                ink.union(attachmentX + flag.paintedBounds.maxX)
            }
        }
        var restID: Int?
        // Multiple same-tick rests: lowest ID wins (deterministic; validation
        // does not reject duplicates).
        if let rest = rests.first {
            let bounds = PercussionGlyphMetrics.rest(
                duration: rest.duration,
                staffSpace: style.staffSpace
            ).paintedBounds
            ink.union(bounds.minX)
            ink.union(bounds.maxX)
            if let dotRight = dotInkRight(after: bounds.maxX, dotCount: rest.dotCount, style: style) {
                ink.union(dotRight)
            }
            restID = rest.id
        }
        return LaidOutColumn(
            tick: tick,
            noteIDs: notes.map(\.id),
            shifts: shifts,
            restID: restID,
            leftExtent: max(0, -ink.minX),
            rightExtent: max(0, ink.maxX)
        )
    }

    /// Right ink edge of the trailing rhythm dot, mirroring the existing dot
    /// placement (dot center = ink maxX + spacing + radius; extra dots follow
    /// at one dot diameter + spacing pitch).
    private static func dotInkRight(
        after inkMaxX: CGFloat,
        dotCount: Int,
        style: NotationFormattingStyle
    ) -> CGFloat? {
        guard dotCount > 0 else { return nil }
        let lastDotCenter = inkMaxX + style.rhythmDotSpacing + style.rhythmDotRadius
            + CGFloat(dotCount - 1) * (style.rhythmDotRadius * 2 + style.rhythmDotSpacing)
        return lastDotCenter + style.rhythmDotRadius
    }

    // MARK: VexFlow staff-second displacement

    /// Closed VexFlow staff-second rule. Within one onset and stem direction,
    /// walking away from the stem side (up: ascending, down: descending),
    /// adjacent staff steps alternate base → shifted → base …; a shifted head
    /// moves by one head width minus half the stem width so it still overlaps
    /// the shared stem. Non-adjacent heads never shift, and mixed stem
    /// directions at one tick never shift each other.
    private static func staffSecondShifts(
        for notes: [ResolvedNote],
        style: NotationFormattingStyle
    ) -> [Int: CGFloat] {
        var shifts: [Int: CGFloat] = [:]
        for direction in [NotationStemDirection.up, .down] {
            let group = notes
                .filter { $0.stemDirection == direction }
                .sorted { lhs, rhs in
                    if lhs.staffStep != rhs.staffStep {
                        return direction == .up ? lhs.staffStep < rhs.staffStep : lhs.staffStep > rhs.staffStep
                    }
                    return lhs.id < rhs.id
                }
            var previousStep: Int?
            var previousShifted = false
            for note in group {
                let adjacent = previousStep.map { abs(note.staffStep - $0) == 1 } ?? false
                let shifted = adjacent && !previousShifted
                if shifted {
                    let width = PercussionGlyphMetrics.notehead(
                        style: note.noteheadStyle,
                        duration: note.duration,
                        stemDirection: note.stemDirection,
                        staffSpace: style.staffSpace
                    ).paintedBounds.width
                    let magnitude = width - style.stemWidth / 2
                    shifts[note.id] = direction == .up ? magnitude : -magnitude
                }
                previousStep = note.staffStep
                previousShifted = shifted
            }
        }
        return shifts
    }
}

/// Running horizontal ink extent relative to a column's base X.
private struct InkExtents {
    var minX: CGFloat = 0
    var maxX: CGFloat = 0

    mutating func union(_ x: CGFloat) {
        minX = min(minX, x)
        maxX = max(maxX, x)
    }
}
