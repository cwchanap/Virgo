import CoreGraphics

// HPA-166 Task 3 — the immutable engraving result. Every `Engraved*` value
// is pure final sheet-local geometry/semantics: X comes from the measured
// formatter, Y is package-owned and already carries the single normalization
// translation. Semantic primitives keep their source integer IDs/kinds so
// app tests and view accessibility can associate them without app types.
// No localized strings, no colors, no view state.
//
// Task 4 emits the topology-driven primitives (stems, beams, flags,
// articulations, controls, tuplets, measure bars); their arrays exist here
// already so the result contract does not change when they fill in.

/// The percussion-clef furniture at a row's leading edge. `position` is the
/// glyph's final center; `paintedBounds` is the clef's reserved furniture
/// slot (`clefWidth` × staff height, centered on `position`) — the
/// engraver's bound while the painter owns the glyph metrics.
public struct EngravedClef: Hashable, Sendable {
    /// Clef glyph center in final sheet coordinates.
    public let position: CGPoint
    /// The reserved furniture slot in final sheet coordinates.
    public let paintedBounds: CGRect

    public init(position: CGPoint, paintedBounds: CGRect) {
        self.position = position
        self.paintedBounds = paintedBounds
    }
}

/// The meter signature beside a row's clef: the resolved meter of the row's
/// first formatted measure at its furniture-center position, plus the
/// signature's reserved slot (`meterWidth` × staff height).
public struct EngravedMeterSignature: Hashable, Sendable {
    public let meter: NotationMeter
    /// Signature center in final sheet coordinates.
    public let position: CGPoint
    /// The reserved furniture slot in final sheet coordinates.
    public let paintedBounds: CGRect

    public init(meter: NotationMeter, position: CGPoint, paintedBounds: CGRect) {
        self.meter = meter
        self.position = position
        self.paintedBounds = paintedBounds
    }
}

/// One staff row of the sheet. `staffCenterY` is the Y of the middle staff
/// line (staff step 4) after the single Y normalization — the row-relative
/// pitch anchor every consumer shares. `staffLineYs` carries the painted
/// staff geometry row anchors and the playhead read from; `clef` and
/// `meterSignature` are the row-leading furniture descriptors; and
/// `paintedBounds` unions all the row's furniture ink — the five stroked
/// staff lines spanning the row's formatted extent plus both furniture
/// slots — so the furniture participates in the single normalization and
/// the sheet's painted bounds like every other primitive.
public struct EngravedRow: Hashable, Sendable {
    public let index: Int
    public let staffCenterY: CGFloat
    /// Staff-line Ys in pitch-ascending order (bottom line first).
    public let staffLineYs: [CGFloat]
    public let clef: EngravedClef
    public let meterSignature: EngravedMeterSignature
    /// Union of the row's furniture ink in final sheet coordinates.
    public let paintedBounds: CGRect

    public init(
        index: Int,
        staffCenterY: CGFloat,
        staffLineYs: [CGFloat],
        clef: EngravedClef,
        meterSignature: EngravedMeterSignature,
        paintedBounds: CGRect
    ) {
        self.index = index
        self.staffCenterY = staffCenterY
        self.staffLineYs = staffLineYs
        self.clef = clef
        self.meterSignature = meterSignature
        self.paintedBounds = paintedBounds
    }
}

/// One engraved measure: the formatted measure's row assignment and sheet
/// bounds plus the resolved measure's timing/meter semantics.
public struct EngravedMeasure: Hashable, Sendable {
    public let index: Int
    public let rowIndex: Int
    public let xOffset: CGFloat
    public let width: CGFloat
    public let startTick: Int
    public let durationTicks: Int
    public let meter: NotationMeter

    public init(
        index: Int,
        rowIndex: Int,
        xOffset: CGFloat,
        width: CGFloat,
        startTick: Int,
        durationTicks: Int,
        meter: NotationMeter
    ) {
        self.index = index
        self.rowIndex = rowIndex
        self.xOffset = xOffset
        self.width = width
        self.startTick = startTick
        self.durationTicks = durationTicks
        self.meter = meter
    }
}

/// One printed note head: the formatter's displaced head-center X, the
/// package staff-step Y, and the Bravura painted bounds around that center.
public struct EngravedNoteHead: Hashable, Sendable {
    public let noteID: Int
    public let measureIndex: Int
    public let rowIndex: Int
    /// Pitch-ascending staff step (same convention as `ResolvedNote`).
    public let staffStep: Int
    public let voice: NotationVoiceRole
    public let stemDirection: NotationStemDirection
    public let noteheadStyle: PercussionNoteheadStyle
    public let duration: NotationDuration
    /// Head glyph center in final sheet coordinates.
    public let position: CGPoint
    /// The Bravura head glyph's painted bounds around `position`.
    public let paintedBounds: CGRect

    public init(
        noteID: Int,
        measureIndex: Int,
        rowIndex: Int,
        staffStep: Int,
        voice: NotationVoiceRole,
        stemDirection: NotationStemDirection,
        noteheadStyle: PercussionNoteheadStyle,
        duration: NotationDuration,
        position: CGPoint,
        paintedBounds: CGRect
    ) {
        self.noteID = noteID
        self.measureIndex = measureIndex
        self.rowIndex = rowIndex
        self.staffStep = staffStep
        self.voice = voice
        self.stemDirection = stemDirection
        self.noteheadStyle = noteheadStyle
        self.duration = duration
        self.position = position
        self.paintedBounds = paintedBounds
    }
}

/// One printed rest: the formatter's visual X (centered in the measure for
/// full-measure rests) and the voice-owned staff-center Y.
public struct EngravedRest: Hashable, Sendable {
    public let restID: Int
    public let measureIndex: Int
    public let rowIndex: Int
    public let voice: NotationVoiceRole
    public let duration: NotationDuration
    public let isFullMeasure: Bool
    /// Rest glyph center in final sheet coordinates.
    public let position: CGPoint
    /// The Bravura rest glyph's painted bounds around `position`.
    public let paintedBounds: CGRect

    public init(
        restID: Int,
        measureIndex: Int,
        rowIndex: Int,
        voice: NotationVoiceRole,
        duration: NotationDuration,
        isFullMeasure: Bool,
        position: CGPoint,
        paintedBounds: CGRect
    ) {
        self.restID = restID
        self.measureIndex = measureIndex
        self.rowIndex = rowIndex
        self.voice = voice
        self.duration = duration
        self.isFullMeasure = isFullMeasure
        self.position = position
        self.paintedBounds = paintedBounds
    }
}

/// One shared stem painted from a stem group's representative anchor to its
/// beam/flag end. `noteIDs` lists every chord member the stem serves.
public struct EngravedStem: Hashable, Sendable {
    public let noteIDs: [Int]
    public let direction: NotationStemDirection
    public let start: CGPoint
    public let end: CGPoint

    public init(noteIDs: [Int], direction: NotationStemDirection, start: CGPoint, end: CGPoint) {
        self.noteIDs = noteIDs
        self.direction = direction
        self.start = start
        self.end = end
    }
}

/// The kind of one beam segment, mirroring the beam topology's segment kinds.
public enum EngravedBeamKind: String, Hashable, Sendable {
    case full
    case forwardHook
    case backwardHook
}

/// One beam segment: a full span across adjacent stem axes or a hook beside
/// a single stem. `level` is the beam-stack level (0 = primary beam).
public struct EngravedBeam: Hashable, Sendable {
    public let noteIDs: [Int]
    public let direction: NotationStemDirection
    public let level: Int
    public let kind: EngravedBeamKind
    public let start: CGPoint
    public let end: CGPoint
    public let thickness: CGFloat

    public init(
        noteIDs: [Int],
        direction: NotationStemDirection,
        level: Int,
        kind: EngravedBeamKind,
        start: CGPoint,
        end: CGPoint,
        thickness: CGFloat
    ) {
        self.noteIDs = noteIDs
        self.direction = direction
        self.level = level
        self.kind = kind
        self.start = start
        self.end = end
        self.thickness = thickness
    }
}

/// One visible flag glyph: `origin` is the SMuFL attachment point — the
/// stem's left edge at the flag level's vertical slot — and `duration` is
/// the flag family to paint (the canonical family, or one `.eighth`
/// component for partially uncovered plans).
public struct EngravedFlag: Hashable, Sendable {
    /// The stem group's flag representative note ID this flag hangs from.
    public let noteID: Int
    public let stemDirection: NotationStemDirection
    public let duration: NotationFlagDuration
    /// Uncovered beam level this flag paints (0 = at the stem tip).
    public let flagIndex: Int
    public let origin: CGPoint

    public init(
        noteID: Int,
        stemDirection: NotationStemDirection,
        duration: NotationFlagDuration,
        flagIndex: Int,
        origin: CGPoint
    ) {
        self.noteID = noteID
        self.stemDirection = stemDirection
        self.duration = duration
        self.flagIndex = flagIndex
        self.origin = origin
    }
}

/// One ledger line through a note head's staff step outside the staff.
public struct EngravedLedgerLine: Hashable, Sendable {
    /// The note head this ledger serves (one primitive per head per step).
    public let noteID: Int
    public let rowIndex: Int
    public let start: CGPoint
    public let end: CGPoint
    /// The stroked line's bounds (bar-line width around the segment).
    public let paintedBounds: CGRect

    public init(noteID: Int, rowIndex: Int, start: CGPoint, end: CGPoint, paintedBounds: CGRect) {
        self.noteID = noteID
        self.rowIndex = rowIndex
        self.start = start
        self.end = end
        self.paintedBounds = paintedBounds
    }
}

/// One printed rhythm dot trailing a note head's or rest's painted ink.
/// `source` keeps the source's integer ID inside its own namespace.
public struct EngravedRhythmDot: Hashable, Sendable {
    /// Which semantic primitive owns the dot — the namespaces stay separate.
    public enum Source: Hashable, Sendable {
        case note(Int)
        case rest(Int)
    }

    public let source: Source
    /// Dot center in final sheet coordinates.
    public let position: CGPoint
    public let rowIndex: Int
    /// The dot disc's bounds (formatter dot diameter around `position`).
    public let paintedBounds: CGRect

    public init(source: Source, position: CGPoint, rowIndex: Int, paintedBounds: CGRect) {
        self.source = source
        self.position = position
        self.rowIndex = rowIndex
        self.paintedBounds = paintedBounds
    }
}

/// One articulation mark attached to a note head (e.g. open hi-hat).
public struct EngravedArticulation: Hashable, Sendable {
    public let noteID: Int
    public let kind: PercussionArticulation
    /// Mark glyph center in final sheet coordinates.
    public let position: CGPoint

    public init(noteID: Int, kind: PercussionArticulation, position: CGPoint) {
        self.noteID = noteID
        self.kind = kind
        self.position = position
    }
}

/// One control mark (stop/choke/damp) painted at its resolved target.
public struct EngravedControl: Hashable, Sendable {
    public let controlID: Int
    public let kind: NotationControlKind
    public let measureIndex: Int
    public let rowIndex: Int
    /// Mark center in final sheet coordinates.
    public let position: CGPoint

    public init(
        controlID: Int,
        kind: NotationControlKind,
        measureIndex: Int,
        rowIndex: Int,
        position: CGPoint
    ) {
        self.controlID = controlID
        self.kind = kind
        self.measureIndex = measureIndex
        self.rowIndex = rowIndex
        self.position = position
    }
}

/// One resolved tuplet group: label-only when every member is continuously
/// beamed with no rests, bracket + label otherwise.
public struct EngravedTuplet: Hashable, Sendable {
    public let tupletID: Int
    public let voice: NotationVoiceRole
    public let ratio: ResolvedTupletRatio
    public let memberNoteIDs: [Int]
    public let memberRestIDs: [Int]
    public let isBracketVisible: Bool
    /// Ordered bracket polyline points; empty when `isBracketVisible` is false.
    public let bracketPoints: [CGPoint]
    /// Label center in final sheet coordinates.
    public let labelPosition: CGPoint
    public let rowIndex: Int

    public init(
        tupletID: Int,
        voice: NotationVoiceRole,
        ratio: ResolvedTupletRatio,
        memberNoteIDs: [Int],
        memberRestIDs: [Int],
        isBracketVisible: Bool,
        bracketPoints: [CGPoint],
        labelPosition: CGPoint,
        rowIndex: Int
    ) {
        self.tupletID = tupletID
        self.voice = voice
        self.ratio = ratio
        self.memberNoteIDs = memberNoteIDs
        self.memberRestIDs = memberRestIDs
        self.isBracketVisible = isBracketVisible
        self.bracketPoints = bracketPoints
        self.labelPosition = labelPosition
        self.rowIndex = rowIndex
    }
}

/// One measure bar line at a formatted measure boundary; `isFinal` marks
/// the closing double bar of the last measure.
public struct EngravedMeasureBar: Hashable, Sendable {
    /// The measure whose boundary this bar closes (leading bars share the
    /// index of the measure they open).
    public let measureIndex: Int
    public let rowIndex: Int
    public let x: CGFloat
    public let isFinal: Bool

    public init(measureIndex: Int, rowIndex: Int, x: CGFloat, isFinal: Bool) {
        self.measureIndex = measureIndex
        self.rowIndex = rowIndex
        self.x = x
        self.isFinal = isFinal
    }
}

/// Immutable engraving output: the embedded formatter result, the producing
/// engraving style, explicit rows and measures, every reusable primitive
/// array, and the final painted bounds/content size — all in normalized
/// sheet coordinates.
public struct EngravedNotation: Hashable, Sendable {
    /// The measured formatter output this engraving was composed from;
    /// remains the sole X and musical-position authority.
    public let formatted: FormattedNotation
    /// The style this engraving was composed with. Geometry owns positions
    /// and painted bounds; paint-time stroke/sizing metrics that are not
    /// per-primitive geometry (stem/bar/staff-line widths, control and
    /// tuplet mark sizing, staff-space glyph scale) read back from here,
    /// so `DrumNotationView` never re-derives or duplicates them.
    public let style: NotationEngravingStyle
    public let rows: [EngravedRow]
    public let measures: [EngravedMeasure]
    public let noteHeads: [EngravedNoteHead]
    public let rests: [EngravedRest]
    public let stems: [EngravedStem]
    public let beams: [EngravedBeam]
    public let flags: [EngravedFlag]
    public let ledgerLines: [EngravedLedgerLine]
    public let rhythmDots: [EngravedRhythmDot]
    public let articulations: [EngravedArticulation]
    public let controls: [EngravedControl]
    public let tuplets: [EngravedTuplet]
    public let measureBars: [EngravedMeasureBar]
    /// Union of every primitive's ink, post-normalization (`.null` when the
    /// input engraved nothing).
    public let paintedBounds: CGRect
    /// Sheet width: the widest laid-out row's right edge — the largest
    /// formatted measure `xOffset + width` — or the painted ink's right
    /// edge, whichever is wider (a flag/displacement may out-ink the
    /// column span).
    public let contentWidth: CGFloat
    /// Sheet height: covers the painted ink and the lowest row's full
    /// anchor extent — its band top plus one row pitch, the block the
    /// mounted sheet's `row_*` scroll anchors occupy.
    public let contentHeight: CGFloat

    public init(
        formatted: FormattedNotation,
        style: NotationEngravingStyle,
        rows: [EngravedRow],
        measures: [EngravedMeasure],
        noteHeads: [EngravedNoteHead],
        rests: [EngravedRest],
        stems: [EngravedStem],
        beams: [EngravedBeam],
        flags: [EngravedFlag],
        ledgerLines: [EngravedLedgerLine],
        rhythmDots: [EngravedRhythmDot],
        articulations: [EngravedArticulation],
        controls: [EngravedControl],
        tuplets: [EngravedTuplet],
        measureBars: [EngravedMeasureBar],
        paintedBounds: CGRect,
        contentWidth: CGFloat,
        contentHeight: CGFloat
    ) {
        self.formatted = formatted
        self.style = style
        self.rows = rows
        self.measures = measures
        self.noteHeads = noteHeads
        self.rests = rests
        self.stems = stems
        self.beams = beams
        self.flags = flags
        self.ledgerLines = ledgerLines
        self.rhythmDots = rhythmDots
        self.articulations = articulations
        self.controls = controls
        self.tuplets = tuplets
        self.measureBars = measureBars
        self.paintedBounds = paintedBounds
        self.contentWidth = contentWidth
        self.contentHeight = contentHeight
    }

    /// The live playhead's row and sheet-local X for a continuous tick —
    /// forwarded to the embedded formatter rather than re-interpolated here.
    public func position(measureIndex: Int, localTick: Double) -> FormattedNotation.Position? {
        formatted.position(measureIndex: measureIndex, localTick: localTick)
    }

    /// The final sheet position of one note head by its source note ID.
    public func noteHeadPosition(noteID: Int) -> CGPoint? {
        noteHeads.first { $0.noteID == noteID }?.position
    }
}
