import CoreGraphics

/// One exact tick inside one resolved measure. Absolute tick is never input
/// state; consumers derive it as `measure.startTick + localTick`.
public struct NotationTickPosition: Hashable, Sendable {
    public let measureIndex: Int
    public let localTick: Int

    public init(measureIndex: Int, localTick: Int) {
        self.measureIndex = measureIndex
        self.localTick = localTick
    }
}

/// One resolved measure: exact index and integer tick span.
public struct ResolvedMeasure: Hashable, Sendable {
    public let index: Int
    public let startTick: Int
    public let durationTicks: Int

    public init(index: Int, startTick: Int, durationTicks: Int) {
        self.index = index
        self.startTick = startTick
        self.durationTicks = durationTicks
    }
}

/// One resolved note onset. IDs map directly from the caller's integer event
/// IDs; no stringification or parallel ID table.
public struct ResolvedNote: Hashable, Sendable {
    public let id: Int
    public let position: NotationTickPosition
    public let stemDirection: NotationStemDirection
    /// Pitch-ascending staff step (each unit is one staff half-position;
    /// higher values sit higher on the staff). Callers whose steps are
    /// Y-down negate at this seam.
    public let staffStep: Int
    /// True when this onset joins its tick's shared stem group — the caller
    /// paints a shared stem (and any visible flag) from the stem-side stem
    /// member's undisplaced head anchor. Staff-second displacement never
    /// leaves that member displaced; non-members (e.g. stemless half/whole
    /// heads sharing the column) may take either parity.
    public let stemMember: Bool
    public let noteheadStyle: PercussionNoteheadStyle
    public let duration: NotationDuration
    public let dotCount: Int
    /// Nil when unflagged or fully covered by beams. When non-nil, this is the
    /// canonical visible flag glyph whose horizontal footprint must be reserved.
    public let visibleFlagDuration: NotationFlagDuration?

    public init(
        id: Int,
        position: NotationTickPosition,
        stemDirection: NotationStemDirection,
        staffStep: Int,
        stemMember: Bool,
        noteheadStyle: PercussionNoteheadStyle,
        duration: NotationDuration,
        dotCount: Int,
        visibleFlagDuration: NotationFlagDuration?
    ) {
        self.id = id
        self.position = position
        self.stemDirection = stemDirection
        self.staffStep = staffStep
        self.stemMember = stemMember
        self.noteheadStyle = noteheadStyle
        self.duration = duration
        self.dotCount = dotCount
        self.visibleFlagDuration = visibleFlagDuration
    }
}

/// One printed rest. Hidden rests are filtered by the caller before input, so
/// every rest here is printed and anchors spacing.
public struct ResolvedRest: Hashable, Sendable {
    public let id: Int
    public let position: NotationTickPosition
    public let duration: NotationDuration
    public let dotCount: Int
    public let isFullMeasure: Bool

    public init(
        id: Int,
        position: NotationTickPosition,
        duration: NotationDuration,
        dotCount: Int,
        isFullMeasure: Bool
    ) {
        self.id = id
        self.position = position
        self.duration = duration
        self.dotCount = dotCount
        self.isFullMeasure = isFullMeasure
    }
}

/// One control onset (timing anchor only; contributes zero collision width).
public struct ResolvedControl: Hashable, Sendable {
    public let id: Int
    public let position: NotationTickPosition

    public init(id: Int, position: NotationTickPosition) {
        self.id = id
        self.position = position
    }
}

/// The complete resolved formatter input: exact integer measures and events,
/// already filtered/suppressed by the caller. Construction validates the
/// resolution; an invalid document is unrepresentable.
public struct ResolvedNotationInput: Hashable, Sendable {
    public let ticksPerWholeNote: Int
    public let measures: [ResolvedMeasure]
    public let notes: [ResolvedNote]
    public let rests: [ResolvedRest]
    public let controls: [ResolvedControl]

    /// - Throws: `ValidationError` for a non-positive `ticksPerWholeNote`,
    ///   duplicate/invalid/overlapping measures, or an event whose
    ///   `localTick` falls outside its owning measure.
    public init(
        ticksPerWholeNote: Int,
        measures: [ResolvedMeasure],
        notes: [ResolvedNote] = [],
        rests: [ResolvedRest] = [],
        controls: [ResolvedControl] = []
    ) throws {
        try Self.validate(
            ticksPerWholeNote: ticksPerWholeNote,
            measures: measures,
            notes: notes,
            rests: rests,
            controls: controls
        )
        self.ticksPerWholeNote = ticksPerWholeNote
        self.measures = measures
        self.notes = notes
        self.rests = rests
        self.controls = controls
    }

    public enum ValidationError: Error, Hashable, Sendable {
        case invalidTicksPerWholeNote(Int)
        case duplicateMeasureIndex(Int)
        case invalidMeasure(index: Int, startTick: Int, durationTicks: Int)
        case overlappingMeasures(first: ResolvedMeasure, second: ResolvedMeasure)
        case eventOutsideMeasure(eventID: Int, measureIndex: Int, localTick: Int)
    }

    private static func validate(
        ticksPerWholeNote: Int,
        measures: [ResolvedMeasure],
        notes: [ResolvedNote],
        rests: [ResolvedRest],
        controls: [ResolvedControl]
    ) throws {
        guard ticksPerWholeNote > 0 else {
            throw ValidationError.invalidTicksPerWholeNote(ticksPerWholeNote)
        }
        var seenIndices = Set<Int>()
        for measure in measures {
            guard measure.index >= 0, measure.startTick >= 0, measure.durationTicks > 0 else {
                throw ValidationError.invalidMeasure(
                    index: measure.index,
                    startTick: measure.startTick,
                    durationTicks: measure.durationTicks
                )
            }
            // `startTick + durationTicks` must be representable; every
            // downstream consumer (overlap check, end-anchor synthesis)
            // relies on it. Reject instead of overflowing.
            let endTick = measure.startTick.addingReportingOverflow(measure.durationTicks)
            guard !endTick.overflow else {
                throw ValidationError.invalidMeasure(
                    index: measure.index,
                    startTick: measure.startTick,
                    durationTicks: measure.durationTicks
                )
            }
            guard seenIndices.insert(measure.index).inserted else {
                throw ValidationError.duplicateMeasureIndex(measure.index)
            }
        }
        // Sorted by (startTick, index): Swift's `sorted` is not guaranteed
        // stable, so the index tiebreak keeps the error payload's
        // `first`/`second` order defined when start ticks tie.
        let byStartTick = measures.sorted {
            $0.startTick != $1.startTick ? $0.startTick < $1.startTick : $0.index < $1.index
        }
        for (previous, next) in zip(byStartTick, byStartTick.dropFirst())
        where next.startTick < previous.startTick + previous.durationTicks {
            throw ValidationError.overlappingMeasures(first: previous, second: next)
        }
        // Every measure's end tick was already overflow-checked above, so
        // this comparison cannot overflow.
        let measuresByIndex = Dictionary(uniqueKeysWithValues: measures.map { ($0.index, $0) })
        func requireInsideMeasure(_ position: NotationTickPosition, eventID: Int) throws {
            guard let measure = measuresByIndex[position.measureIndex],
                position.localTick >= 0,
                position.localTick < measure.durationTicks
            else {
                throw ValidationError.eventOutsideMeasure(
                    eventID: eventID,
                    measureIndex: position.measureIndex,
                    localTick: position.localTick
                )
            }
        }
        for note in notes { try requireInsideMeasure(note.position, eventID: note.id) }
        for rest in rests { try requireInsideMeasure(rest.position, eventID: rest.id) }
        for control in controls { try requireInsideMeasure(control.position, eventID: control.id) }
    }
}

/// Plain scalar formatter style; every value is points. The defaults are the
/// mapping Virgo uses (`availableRowWidth` = the app's 900pt row-width floor).
public struct NotationFormattingStyle: Hashable, Sendable {
    public let availableRowWidth: CGFloat
    public let rowLeadingInset: CGFloat
    public let staffSpace: CGFloat
    public let stemWidth: CGFloat
    /// Edge-to-edge clearance between adjacent column ink, **not** a
    /// center-to-center pitch. With the Bravura X-black head (23.2pt wide at
    /// staff-space 20) the default 8pt clearance yields the 31.2pt adjacent
    /// pitch Virgo's sixteenth runs actually render.
    public let minimumInterColumnClearance: CGFloat
    public let minimumQuarterNoteSpacing: CGFloat
    public let measureSpacing: CGFloat
    public let leadingMeasureInset: CGFloat
    public let trailingMeasureInset: CGFloat
    public let rhythmDotRadius: CGFloat
    public let rhythmDotSpacing: CGFloat

    public init(
        availableRowWidth: CGFloat = 900,
        rowLeadingInset: CGFloat = 100,
        staffSpace: CGFloat = 20,
        stemWidth: CGFloat = 2,
        minimumInterColumnClearance: CGFloat = 8,
        minimumQuarterNoteSpacing: CGFloat = 50,
        measureSpacing: CGFloat = 12,
        leadingMeasureInset: CGFloat = 52,
        trailingMeasureInset: CGFloat = 0,
        rhythmDotRadius: CGFloat = 2.5,
        rhythmDotSpacing: CGFloat = 4
    ) {
        self.availableRowWidth = availableRowWidth
        self.rowLeadingInset = rowLeadingInset
        self.staffSpace = staffSpace
        self.stemWidth = stemWidth
        self.minimumInterColumnClearance = minimumInterColumnClearance
        self.minimumQuarterNoteSpacing = minimumQuarterNoteSpacing
        self.measureSpacing = measureSpacing
        self.leadingMeasureInset = leadingMeasureInset
        self.trailingMeasureInset = trailingMeasureInset
        self.rhythmDotRadius = rhythmDotRadius
        self.rhythmDotSpacing = rhythmDotSpacing
    }

    /// The default mapping used by Virgo.
    public static let virgoDefault = NotationFormattingStyle()
}
