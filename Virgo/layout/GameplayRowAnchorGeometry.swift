import CoreGraphics
import DrumNotation

/// Per-row scroll-anchor geometry derived once from an installed engraving
/// (HPA-583). `GameplayNotationInstall` computes these at install, so the
/// playback-observed sheet reads scalar/array anchor geometry instead of
/// rescanning every engraved primitive on each view invalidation.
enum GameplayRowAnchorGeometry {
    /// One `scrollTo("row_i", anchor: .top)` target per engraved row, in
    /// sheet coordinates: the row's nominal band top pulled up to that
    /// row's own topmost ink. A single shared `firstRowTop` cannot express
    /// this — a later row's above-band ink resolves to a negative shared
    /// offset, and a `max(0, …)` clamp discards it, landing that row's
    /// anchor on its band top and clipping the overhang.
    ///
    /// Every primitive contributes its exact package-painted `minY` — no
    /// app-side glyph-size guesses. Each row keeps its own top even when
    /// tops decrease: a later row's ink can reach above an earlier row's
    /// anchor, and clamping to the previous top would put that row's
    /// anchor below its own ink. The anchor column therefore uses
    /// independently positioned targets, not stacked extents — a `VStack`
    /// cannot encode a decreasing top with a non-negative extent. Rows
    /// always carry furniture bounds, so every engraved row resolves a
    /// top.
    static func anchorTops(for engraving: EngravedNotation) -> [CGFloat] {
        var inkTopByRow: [Int: CGFloat] = [:]
        for (row, minY) in inkTopCandidates(engraving) {
            inkTopByRow[row] = min(inkTopByRow[row] ?? .infinity, minY)
        }
        return engraving.rows.map { row in
            let bandTop = max(0, row.staffCenterY - engraving.style.rowHeight / 2)
            return max(0, min(bandTop, inkTopByRow[row.index] ?? bandTop))
        }
    }

    /// Per-row topmost Y over every primitive family: rows and the
    /// `rowIndex`-keyed families directly; stems, beams, flags, and
    /// articulations join through the note heads' row assignment.
    private static func inkTopCandidates(
        _ engraving: EngravedNotation
    ) -> [(row: Int, minY: CGFloat)] {
        var tops: [(Int, CGFloat)] = []
        tops += engraving.rows.map { ($0.index, $0.paintedBounds.minY) }
        tops += engraving.noteHeads.map { ($0.rowIndex, $0.paintedBounds.minY) }
        tops += engraving.rests.map { ($0.rowIndex, $0.paintedBounds.minY) }
        tops += engraving.ledgerLines.map { ($0.rowIndex, $0.paintedBounds.minY) }
        tops += engraving.rhythmDots.map { ($0.rowIndex, $0.paintedBounds.minY) }
        tops += engraving.controls.map { ($0.rowIndex, $0.paintedBounds.minY) }
        tops += engraving.tuplets.map { ($0.rowIndex, $0.paintedBounds.minY) }
        let noteRow = Dictionary(
            engraving.noteHeads.map { ($0.noteID, $0.rowIndex) },
            uniquingKeysWith: { existing, _ in existing }
        )
        tops += engraving.stems.compactMap { stem in
            stem.noteIDs.lazy.compactMap { noteRow[$0] }.first
                .map { ($0, stem.paintedBounds.minY) }
        }
        tops += engraving.beams.compactMap { beam in
            beam.noteIDs.lazy.compactMap { noteRow[$0] }.first
                .map { ($0, beam.paintedBounds.minY) }
        }
        tops += engraving.flags.compactMap { flag in
            noteRow[flag.noteID].map { ($0, flag.paintedBounds.minY) }
        }
        tops += engraving.articulations.compactMap { articulation in
            noteRow[articulation.noteID].map { ($0, articulation.paintedBounds.minY) }
        }
        return tops
    }
}
