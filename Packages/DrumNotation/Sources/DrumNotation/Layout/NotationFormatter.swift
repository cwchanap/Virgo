import CoreGraphics

/// Deterministic measured formatter (HPA-164). Builds one logical column per
/// exact local tick per measure — including explicit start (`0`) and end
/// (`durationTicks`) anchors — applies the pinned VexFlow staff-second
/// displacement, and measures each column's collision ink. Spacing, measure
/// widths, row packing and tick-lookup interpolation land in a later task;
/// until then every column keeps `logicalColumnX` = 0 relative to its measure
/// and measures carry placeholder row/offset/width values.
public enum NotationFormatter {
    /// Formats already-validated resolved input at `style`. The throwing
    /// signature is the pinned API the app and later tasks call through.
    public static func format(
        _ input: ResolvedNotationInput,
        style: NotationFormattingStyle
    ) throws -> FormattedNotation {
        let measures = input.measures
            .sorted { $0.index < $1.index }
            .map { measure in
                formatMeasure(
                    measure,
                    notes: input.notes,
                    rests: input.rests,
                    controls: input.controls,
                    style: style
                )
            }
        return FormattedNotation(measures: measures)
    }

    // MARK: Logical columns

    private static func formatMeasure(
        _ measure: ResolvedMeasure,
        notes: [ResolvedNote],
        rests: [ResolvedRest],
        controls: [ResolvedControl],
        style: NotationFormattingStyle
    ) -> FormattedMeasure {
        var notesByTick: [Int: [ResolvedNote]] = [:]
        for note in notes where note.position.measureIndex == measure.index {
            notesByTick[note.position.localTick, default: []].append(note)
        }
        var restsByTick: [Int: [ResolvedRest]] = [:]
        for rest in rests where rest.position.measureIndex == measure.index {
            restsByTick[rest.position.localTick, default: []].append(rest)
        }
        var ticks = Set([0, measure.durationTicks])
        ticks.formUnion(notesByTick.keys)
        ticks.formUnion(restsByTick.keys)
        for control in controls where control.position.measureIndex == measure.index {
            ticks.insert(control.position.localTick)
        }
        let columns = ticks.sorted().map { tick in
            buildColumn(
                tick: tick,
                notes: (notesByTick[tick] ?? []).sorted { $0.id < $1.id },
                rests: (restsByTick[tick] ?? []).sorted { $0.id < $1.id },
                style: style
            )
        }
        // Spacing/rows are a later task; X placement stays logical for now.
        return FormattedMeasure(index: measure.index, rowIndex: 0, xOffset: 0, width: 0, columns: columns)
    }

    private static func buildColumn(
        tick: Int,
        notes: [ResolvedNote],
        rests: [ResolvedRest],
        style: NotationFormattingStyle
    ) -> FormattedColumn {
        let shifts = staffSecondShifts(for: notes, style: style)
        let heads = notes
            .map { FormattedNoteHead(noteID: $0.id, headCenterX: shifts[$0.id] ?? 0) }
            .sorted { $0.noteID < $1.noteID }

        var ink = InkExtents()
        for note in notes {
            let centerX = shifts[note.id] ?? 0
            let head = PercussionGlyphMetrics.notehead(
                style: note.noteheadStyle,
                duration: note.duration,
                stemDirection: note.stemDirection,
                staffSpace: style.staffSpace
            ).paintedBounds
            ink.union(centerX + head.minX)
            ink.union(centerX + head.maxX)
            if let dotRight = dotInkRight(after: centerX + head.maxX, dotCount: note.dotCount, style: style) {
                ink.union(dotRight)
            }
            // Flags hang on the shared stem axis (the undisplaced column X),
            // never on the displaced head.
            if let flagDuration = note.visibleFlagDuration {
                let flag = PercussionGlyphMetrics.flag(
                    duration: flagDuration,
                    direction: note.stemDirection,
                    staffSpace: style.staffSpace
                )
                let attachmentX = -flag.attachmentOffset.x
                ink.union(attachmentX + flag.paintedBounds.minX)
                ink.union(attachmentX + flag.paintedBounds.maxX)
            }
        }
        var restVisual: FormattedRest?
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
            // Full-measure re-centering happens once measure width is known.
            restVisual = FormattedRest(restID: rest.id, visualX: 0)
        }
        return FormattedColumn(
            localTick: tick,
            logicalColumnX: 0,
            noteHeads: heads,
            rest: restVisual,
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
