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
    /// Bounds-bearing primitives contribute their painted `minY`;
    /// endpoint/center-only primitives get a conservative style-derived
    /// margin — an anchor that reveals slightly more than the ink is
    /// correct, one that clips is not. Rows always carry furniture bounds,
    /// so every engraved row resolves a top.
    static func anchorTops(for engraving: EngravedNotation) -> [CGFloat] {
        var inkTopByRow: [Int: CGFloat] = [:]
        for (row, minY) in boundedInkTops(engraving) + joinedInkTops(engraving) {
            inkTopByRow[row] = min(inkTopByRow[row] ?? .infinity, minY)
        }
        return engraving.rows.map { row in
            let bandTop = max(0, row.staffCenterY - engraving.style.rowHeight / 2)
            return max(0, min(bandTop, inkTopByRow[row.index] ?? bandTop))
        }
    }

    /// Per-row topmost Y for primitives that carry their own `rowIndex` and
    /// a painted bounds or a style-bounded extent: furniture, heads, rests,
    /// ledgers, dots, controls, and tuplets.
    private static func boundedInkTops(
        _ engraving: EngravedNotation
    ) -> [(row: Int, minY: CGFloat)] {
        let style = engraving.style
        var tops: [(Int, CGFloat)] = []
        tops += engraving.rows.map { ($0.index, $0.paintedBounds.minY) }
        tops += engraving.noteHeads.map { ($0.rowIndex, $0.paintedBounds.minY) }
        tops += engraving.rests.map { ($0.rowIndex, $0.paintedBounds.minY) }
        tops += engraving.ledgerLines.map { ($0.rowIndex, $0.paintedBounds.minY) }
        tops += engraving.rhythmDots.map { ($0.rowIndex, $0.paintedBounds.minY) }
        tops += engraving.controls.map { ($0.rowIndex, $0.position.y - style.stopMarkSize) }
        tops += engraving.tuplets.map { tuplet in
            let inkTop = min(
                tuplet.bracketPoints.map(\.y).min() ?? .infinity,
                tuplet.labelPosition.y - style.tupletLabelSize.height / 2
            )
            return (tuplet.rowIndex, inkTop - style.tupletLineWidth)
        }
        return tops
    }

    /// Per-row topmost Y for primitives keyed by `noteID`/`noteIDs` rather
    /// than `rowIndex` — stems, beams, flags, articulations join through the
    /// note heads' row assignment.
    private static func joinedInkTops(
        _ engraving: EngravedNotation
    ) -> [(row: Int, minY: CGFloat)] {
        let style = engraving.style
        let noteRow = Dictionary(
            engraving.noteHeads.map { ($0.noteID, $0.rowIndex) },
            uniquingKeysWith: { existing, _ in existing }
        )
        var tops: [(Int, CGFloat)] = []
        tops += engraving.stems.compactMap { stem in
            stem.noteIDs.lazy.compactMap { noteRow[$0] }.first.map {
                ($0, min(stem.start.y, stem.end.y) - style.formatting.stemWidth)
            }
        }
        tops += engraving.beams.compactMap { beam in
            beam.noteIDs.lazy.compactMap { noteRow[$0] }.first.map {
                ($0, min(beam.start.y, beam.end.y) - beam.thickness)
            }
        }
        tops += engraving.flags.compactMap { flag in
            noteRow[flag.noteID].map { ($0, flag.origin.y - style.formatting.staffSpace) }
        }
        tops += engraving.articulations.compactMap { articulation in
            noteRow[articulation.noteID].map {
                ($0, articulation.position.y - style.formatting.staffSpace)
            }
        }
        return tops
    }
}
