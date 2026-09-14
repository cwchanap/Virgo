import CoreGraphics

/// One formatted notehead: the note's sheet-local head-center X — its
/// column's `logicalColumnX` plus the VexFlow staff-second displacement (zero
/// for undisplaced heads). The logical timing column X itself is
/// `FormattedColumn.logicalColumnX` and is never replaced.
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
    /// Every printed rest at this tick, in stable rest-ID order — each keeps
    /// its own visual X (full-measure rests center in the measure's content
    /// span; interval rests sit on `logicalColumnX`).
    public let rests: [FormattedRest]
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
        rests: [FormattedRest],
        leftExtent: CGFloat = 0,
        rightExtent: CGFloat = 0
    ) {
        self.localTick = localTick
        self.logicalColumnX = logicalColumnX
        self.noteHeads = noteHeads
        self.rests = rests
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

    /// Resolves the live playhead's row and sheet-local X for a continuous
    /// tick inside `measureIndex`. Exact anchors return their
    /// `logicalColumnX`; values between two anchors interpolate linearly
    /// between the adjacent columns of that measure only — never across a
    /// measure or row boundary. The start/end anchor columns make empty,
    /// control-only and trailing measures resolvable across their full span.
    /// Tiny floating-point drift at the measure edges (±1e-6 ticks) clamps to
    /// the boundary anchor; anything further outside the measure, an unknown
    /// measure index, or non-finite input returns nil.
    public func position(measureIndex: Int, localTick: Double) -> Position? {
        guard localTick.isFinite,
            let measure = measures.first(where: { $0.index == measureIndex })
        else { return nil }
        let duration = Double(measure.columns.last?.localTick ?? 0)
        let edgeTolerance = 1e-6
        guard localTick >= -edgeTolerance, localTick <= duration + edgeTolerance else { return nil }
        let t = min(max(localTick, 0), duration)
        var previous: FormattedColumn?
        for column in measure.columns {
            let tick = Double(column.localTick)
            if tick == t {
                return Position(rowIndex: measure.rowIndex, x: column.logicalColumnX)
            }
            if tick > t {
                guard let previous else { return nil }
                let span = tick - Double(previous.localTick)
                let fraction = span > 0 ? (t - Double(previous.localTick)) / span : 0
                return Position(
                    rowIndex: measure.rowIndex,
                    x: previous.logicalColumnX
                        + (column.logicalColumnX - previous.logicalColumnX) * CGFloat(fraction)
                )
            }
            previous = column
        }
        // Beyond the last column (output built without an end anchor) has no
        // position.
        return nil
    }
}
