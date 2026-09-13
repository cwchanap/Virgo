import CoreGraphics

/// One formatted notehead: the note's package-visual head-center X. Displaced
/// staff seconds store their shifted center here; the logical timing column X
/// is `FormattedColumn.logicalColumnX` and is never replaced.
public struct FormattedNoteHead: Hashable, Sendable {
    public let noteID: Int
    public let headCenterX: CGFloat

    public init(noteID: Int, headCenterX: CGFloat) {
        self.noteID = noteID
        self.headCenterX = headCenterX
    }
}

/// A printed rest's package-owned visual X (its timing anchor stays the
/// column's `logicalColumnX`; full-measure rests may be centered within the
/// measure once its final width is known).
public struct FormattedRest: Hashable, Sendable {
    public let restID: Int
    public let visualX: CGFloat

    public init(restID: Int, visualX: CGFloat) {
        self.restID = restID
        self.visualX = visualX
    }
}

/// One logical onset column at one exact local tick, ordered by tick within
/// its measure — the formatter guarantees at most one column per tick and
/// stable tick ordering. Every X is final sheet-local (row-leading inset
/// included); the caller applies no post-format X transform.
public struct FormattedColumn: Hashable, Sendable {
    public let localTick: Int
    /// Logical onset X — the timing anchor every note/rest at this tick
    /// shares. Never displaced; staff-second displacement only moves
    /// `FormattedNoteHead.headCenterX`.
    public let logicalColumnX: CGFloat
    public let noteHeads: [FormattedNoteHead]
    public let rest: FormattedRest?
    /// Collision ink reach left of `logicalColumnX` (≥ 0): the union of
    /// displaced notehead bounds, dot footprints, printed-rest bounds and
    /// visible flag bounds attached at the undisplaced column axis.
    public let leftExtent: CGFloat
    /// Collision ink reach right of `logicalColumnX` (≥ 0), same union.
    public let rightExtent: CGFloat

    public init(
        localTick: Int,
        logicalColumnX: CGFloat,
        noteHeads: [FormattedNoteHead],
        rest: FormattedRest?,
        leftExtent: CGFloat = 0,
        rightExtent: CGFloat = 0
    ) {
        self.localTick = localTick
        self.logicalColumnX = logicalColumnX
        self.noteHeads = noteHeads
        self.rest = rest
        self.leftExtent = leftExtent
        self.rightExtent = rightExtent
    }
}

/// One formatted measure: its row assignment, sheet-local origin/width and
/// ordered onset columns.
public struct FormattedMeasure: Hashable, Sendable {
    public let index: Int
    public let rowIndex: Int
    public let xOffset: CGFloat
    public let width: CGFloat
    public let columns: [FormattedColumn]

    public init(
        index: Int,
        rowIndex: Int,
        xOffset: CGFloat,
        width: CGFloat,
        columns: [FormattedColumn]
    ) {
        self.index = index
        self.rowIndex = rowIndex
        self.xOffset = xOffset
        self.width = width
        self.columns = columns
    }
}

/// Immutable formatter output: ordered formatted measures/columns plus the
/// single notation tick → row/X lookup for the live playhead.
public struct FormattedNotation: Hashable, Sendable {
    /// One lookup result: the packed row and the sheet-local X.
    public struct Position: Hashable, Sendable {
        public let rowIndex: Int
        public let x: CGFloat

        public init(rowIndex: Int, x: CGFloat) {
            self.rowIndex = rowIndex
            self.x = x
        }
    }

    /// Ordered by measure index.
    public let measures: [FormattedMeasure]

    public init(measures: [FormattedMeasure]) {
        self.measures = measures
    }

    /// Exact-anchor resolution: the logical onset X of the column at exactly
    /// `localTick` in `measureIndex`, with that measure's row. Nil when the
    /// measure or the exact anchor does not exist. (Between-anchor
    /// interpolation is the formatter's tick-lookup contract, not input
    /// re-quantization, and stays measure-local.)
    public func position(measureIndex: Int, localTick: Int) -> Position? {
        guard let measure = measures.first(where: { $0.index == measureIndex }),
            let column = measure.columns.first(where: { $0.localTick == localTick })
        else { return nil }
        return Position(rowIndex: measure.rowIndex, x: column.logicalColumnX)
    }
}
