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
    /// The flag-ink source is the transitional HPA-164 per-note field until
    /// the Task-7 cutover hands the direct route the package flag plans.
    public static func format(
        _ input: ResolvedNotationInput,
        style: NotationFormattingStyle
    ) throws -> FormattedNotation {
        format(input, style: style, flagReservations: projectedFlagReservations(input))
    }

    private static func format(
        _ input: ResolvedNotationInput,
        style: NotationFormattingStyle,
        flagReservations: [Int: NotationFlagDuration]
    ) -> FormattedNotation {
        // Phase 1: per-measure column layout with local X and natural width.
        let laidOut = input.measures
            .sorted { $0.index < $1.index }
            .map { layoutMeasure($0, input: input, style: style, flagReservations: flagReservations) }

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
                    contentCenterX: contentCenterX
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
        /// Every rest at this tick, in stable ID order.
        let rests: [ResolvedRest]
        let leftExtent: CGFloat
        let rightExtent: CGFloat
    }

    private struct LaidOutMeasure {
        let measure: ResolvedMeasure
        var columns: [LaidOutColumn]
        let width: CGFloat
    }

    private static func layoutMeasure(
        _ measure: ResolvedMeasure,
        input: ResolvedNotationInput,
        style: NotationFormattingStyle,
        flagReservations: [Int: NotationFlagDuration]
    ) -> LaidOutMeasure {
        var notesByTick: [Int: [ResolvedNote]] = [:]
        for note in input.notes where note.position.measureIndex == measure.index {
            notesByTick[note.position.localTick, default: []].append(note)
        }
        var restsByTick: [Int: [ResolvedRest]] = [:]
        for rest in input.rests where rest.position.measureIndex == measure.index {
            restsByTick[rest.position.localTick, default: []].append(rest)
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
                style: style,
                flagReservations: flagReservations
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
        // A full-measure rest paints centered in the content span
        // [leadingMeasureInset, end-anchor X], so its ink is a keep-clear
        // band around that center — not onset-column ink (buildColumn left
        // it out). Open a pocket for the band with the least growth.
        if let reach = centeredRestInkReach(columns: columns, style: style) {
            applyCenteredRestPocket(&columns, inkReach: reach, style: style)
        }
        // Natural width: the end anchor's position plus the trailing inset.
        let width = (columns.last?.x ?? style.leadingMeasureInset) + style.trailingMeasureInset
        return LaidOutMeasure(
            measure: measure,
            columns: columns,
            width: width
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

    /// Left/right ink reach (from the rest's center) for the measure's
    /// full-measure rests — the union of every such rest's glyph and dot
    /// bounds. Nil when the measure has none.
    private static func centeredRestInkReach(
        columns: [LaidOutColumn],
        style: NotationFormattingStyle
    ) -> (left: CGFloat, right: CGFloat)? {
        var left: CGFloat = 0
        var right: CGFloat = 0
        var found = false
        for rest in columns.flatMap(\.rests) where rest.isFullMeasure {
            let bounds = PercussionGlyphMetrics.rest(
                duration: rest.duration,
                staffSpace: style.staffSpace
            ).paintedBounds
            left = max(left, -bounds.minX)
            right = max(
                right,
                dotInkRight(after: bounds.maxX, dotCount: rest.dotCount, style: style) ?? bounds.maxX
            )
            found = true
        }
        return found ? (left: left, right: right) : nil
    }

    /// Opens a keep-clear pocket for the centered full-measure rest's band —
    /// the content center ± ink reach ± the inter-column clearance — by
    /// splitting the laid-out columns: columns at or left of the split keep
    /// their X and their ink must end left of the band; columns right of the
    /// split (always including the end anchor) shift right by the same delta
    /// the end anchor moves, and their ink must start right of the band.
    /// With `L′ = leftReach + clearance`, `R′ = rightReach + clearance`, and
    /// `E` the natural end-anchor X, split `k` needs
    ///   left  ink i ≤ k: δ ≥ 2·inkMaxᵢ + 2·L′ − L − E    (band right of ink)
    ///   right ink i > k: δ ≥ L + E + 2·R′ − 2·inkMinᵢ    (ink right of band)
    /// and δ(k) is the max of those bounds, floored at 0. The split with the
    /// smallest δ wins; ties take the largest split so the fewest columns
    /// move. Closed form — column inks are disjoint and ordered — no
    /// iteration, no floating-point fixpoint.
    private static func applyCenteredRestPocket(
        _ columns: inout [LaidOutColumn],
        inkReach: (left: CGFloat, right: CGFloat),
        style: NotationFormattingStyle
    ) {
        guard let lastIndex = columns.indices.last, lastIndex > 0 else { return }
        let leading = style.leadingMeasureInset
        let leftMargin = inkReach.left + style.minimumInterColumnClearance
        let rightMargin = inkReach.right + style.minimumInterColumnClearance
        let endX = columns[lastIndex].x
        // Prefix max of ink right edges; suffix min of ink left edges.
        // Zero-extent columns contribute no bound.
        var prefixMax = [CGFloat](repeating: -.infinity, count: columns.count)
        var suffixMin = [CGFloat](repeating: .infinity, count: columns.count + 1)
        for (index, column) in columns.enumerated()
        where column.leftExtent > 0 || column.rightExtent > 0 {
            prefixMax[index] = column.x + column.rightExtent
            suffixMin[index] = column.x - column.leftExtent
        }
        for index in columns.indices.dropFirst() {
            prefixMax[index] = max(prefixMax[index], prefixMax[index - 1])
        }
        for index in columns.indices.reversed().dropFirst() {
            suffixMin[index] = min(suffixMin[index], suffixMin[index + 1])
        }
        var bestDelta: CGFloat = .infinity
        var bestSplit = 0
        for split in 0..<lastIndex {
            let leftBound = 2 * prefixMax[split] + 2 * leftMargin - leading - endX
            let rightBound = leading + endX + 2 * rightMargin - 2 * suffixMin[split + 1]
            let delta = max(0, leftBound, rightBound)
            if delta <= bestDelta {  // `<=` keeps the largest split among ties
                bestDelta = delta
                bestSplit = split
            }
        }
        guard bestDelta > 0, bestDelta.isFinite else { return }
        for index in (bestSplit + 1)...lastIndex {
            columns[index].x += bestDelta
        }
    }

    private static func finalizeColumn(
        _ column: LaidOutColumn,
        rowX: CGFloat,
        contentCenterX: CGFloat
    ) -> FormattedColumn {
        FormattedColumn(
            localTick: column.tick,
            logicalColumnX: rowX + column.x,
            noteHeads: column.noteIDs.map { noteID in
                FormattedNoteHead(noteID: noteID, headCenterX: rowX + column.x + (column.shifts[noteID] ?? 0))
            },
            rests: column.rests.map { rest in
                // Every rest keeps its own placement: a full-measure rest's
                // timing anchor stays on the column while its visual centers
                // in the measure content span (finalized now that the width
                // is known); interval rests paint at the column itself.
                FormattedRest(restID: rest.id, visualX: rest.isFullMeasure ? contentCenterX : rowX + column.x)
            },
            leftExtent: column.leftExtent,
            rightExtent: column.rightExtent
        )
    }

    private static func buildColumn(
        tick: Int,
        notes: [ResolvedNote],
        rests: [ResolvedRest],
        style: NotationFormattingStyle,
        flagReservations: [Int: NotationFlagDuration]
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
            // stemUpSE/stemDownNW anchor at the undisplaced column X — and
            // attach where the flag paints from: the stem axis minus half
            // the stem width (Virgo's painted stem origin convention), never
            // on the displaced head. The reservation is keyed by the stem
            // group's representative, so chord members never double the ink.
            if let flagDuration = flagReservations[note.id] {
                let flag = PercussionGlyphMetrics.flag(
                    duration: flagDuration,
                    direction: note.stemDirection,
                    staffSpace: style.staffSpace
                )
                let attachmentX = headMetrics.stemAnchorOffset.x
                    - style.stemWidth / 2
                    - flag.attachmentOffset.x
                ink.union(attachmentX + flag.paintedBounds.minX)
                ink.union(attachmentX + flag.paintedBounds.maxX)
            }
        }
        // Every interval rest at the tick keeps its own placement and
        // contributes its glyph and dot bounds to the column's collision
        // ink — same-tick rests never collapse into a single representative.
        // A full-measure rest paints centered in the finished measure, not
        // on this column; its ink is the keep-clear band enforced by
        // `applyCenteredRestPocket` rather than onset-column ink.
        for rest in rests where !rest.isFullMeasure {
            let bounds = PercussionGlyphMetrics.rest(
                duration: rest.duration,
                staffSpace: style.staffSpace
            ).paintedBounds
            ink.union(bounds.minX)
            ink.union(bounds.maxX)
            if let dotRight = dotInkRight(after: bounds.maxX, dotCount: rest.dotCount, style: style) {
                ink.union(dotRight)
            }
        }
        return LaidOutColumn(
            tick: tick,
            noteIDs: notes.map(\.id),
            shifts: shifts,
            rests: rests,
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
    /// directions at one tick never shift each other. The run's alternation
    /// parity is anchored on the first stem member: the caller paints the
    /// shared stem (and any visible flag) from that head's undisplaced
    /// anchor, so it must hold the base slot — non-members (stemless or
    /// unsupported heads) never do.
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
            var runStart = group.startIndex
            while runStart < group.endIndex {
                var runEnd = runStart
                while runEnd + 1 < group.endIndex,
                      abs(group[runEnd + 1].staffStep - group[runEnd].staffStep) == 1 {
                    runEnd += 1
                }
                let run = group[runStart...runEnd]
                let anchor = run.firstIndex(where: \.stemMember) ?? run.startIndex
                let baseParity = run.distance(from: run.startIndex, to: anchor) % 2
                for (position, note) in run.enumerated() where position % 2 != baseParity {
                    let width = PercussionGlyphMetrics.notehead(
                        style: note.noteheadStyle,
                        duration: note.duration,
                        stemDirection: note.stemDirection,
                        staffSpace: style.staffSpace
                    ).paintedBounds.width
                    let magnitude = width - style.stemWidth / 2
                    shifts[note.id] = direction == .up ? magnitude : -magnitude
                }
                runStart = runEnd + 1
            }
        }
        return shifts
    }
}

extension NotationFormatter {
    // MARK: Flag-ink sources and the plan-driven entry point

    /// Plan-driven formatting (HPA-166 Task 2): the same spacing engine, but
    /// flag ink comes from the package stem-group plans — one reservation
    /// per group measured once at the shared stem axis. `NotationEngraver`
    /// and the package parity tests drive this path; it stays internal so
    /// no second public formatting engine exists.
    static func format(
        _ input: ResolvedNotationInput,
        style: NotationFormattingStyle,
        stemTopology: StemTopology
    ) -> FormattedNotation {
        format(input, style: style, flagReservations: stemTopology.flagReservations)
    }

    /// The transitional flag source: the projection's per-note field.
    private static func projectedFlagReservations(
        _ input: ResolvedNotationInput
    ) -> [Int: NotationFlagDuration] {
        var reservations: [Int: NotationFlagDuration] = [:]
        for note in input.notes {
            if let flag = note.visibleFlagDuration {
                reservations[note.id] = flag
            }
        }
        return reservations
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
