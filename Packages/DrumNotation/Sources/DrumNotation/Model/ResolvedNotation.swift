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

/// The notation voice a resolved event belongs to: upper-voice events stem
/// up, lower-voice events stem down. Carries no app instrument state.
public enum NotationVoiceRole: Int, Hashable, Sendable {
    case upper
    case lower
}

/// One measure's resolved meter: beats per measure over the note value that
/// carries the beat (4/4 → `beats: 4, noteValue: 4`).
public struct NotationMeter: Hashable, Sendable {
    public let beats: Int
    public let noteValue: Int

    public init(beats: Int, noteValue: Int) {
        self.beats = beats
        self.noteValue = noteValue
    }
}

/// One ordered beat group inside a measure: a tick span the beam topology
/// scopes to. The group's ordinal is its array position inside
/// `ResolvedMeasure.beatGroups` — groups are validated to tile the measure
/// contiguously from tick 0 — so no redundant index rides along.
public struct ResolvedBeatGroup: Hashable, Sendable {
    public let startTick: Int
    public let durationTicks: Int

    public init(startTick: Int, durationTicks: Int) {
        self.startTick = startTick
        self.durationTicks = durationTicks
    }
}

/// One resolved measure: exact index and integer tick span, plus the meter
/// and ordered beat groups the engraving topology consumes.
public struct ResolvedMeasure: Hashable, Sendable {
    public let index: Int
    public let startTick: Int
    public let durationTicks: Int
    public let meter: NotationMeter
    public let beatGroups: [ResolvedBeatGroup]

    public init(
        index: Int,
        startTick: Int,
        durationTicks: Int,
        meter: NotationMeter,
        beatGroups: [ResolvedBeatGroup]
    ) {
        self.index = index
        self.startTick = startTick
        self.durationTicks = durationTicks
        self.meter = meter
        self.beatGroups = beatGroups
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
    /// The notation voice this onset belongs to.
    public let voice: NotationVoiceRole
    /// Exact timeline duration in ticks, used for adjacency; never
    /// reconstructed from `duration`.
    public let durationTicks: Int
    /// Deterministic engraving tiebreak the caller resolves once from its
    /// instrument ordering; the package never sees the source catalog.
    public let tiebreakOrder: Int
    /// False suppresses duration-bearing engraving (stems/beams/flags/dots)
    /// while the head still paints — the way a caller preserves note identity
    /// in a measure that does not permit engraving.
    public let isRhythmEngravable: Bool
    /// Resolved articulation intent (e.g. open hi-hat); nil when none.
    public let articulation: PercussionArticulation?

    public init(
        id: Int,
        position: NotationTickPosition,
        stemDirection: NotationStemDirection,
        staffStep: Int,
        stemMember: Bool,
        noteheadStyle: PercussionNoteheadStyle,
        duration: NotationDuration,
        dotCount: Int,
        visibleFlagDuration: NotationFlagDuration?,
        voice: NotationVoiceRole,
        durationTicks: Int,
        tiebreakOrder: Int,
        isRhythmEngravable: Bool,
        articulation: PercussionArticulation? = nil
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
        self.voice = voice
        self.durationTicks = durationTicks
        self.tiebreakOrder = tiebreakOrder
        self.isRhythmEngravable = isRhythmEngravable
        self.articulation = articulation
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
    /// The notation voice this rest belongs to (owns its staff offset).
    public let voice: NotationVoiceRole
    /// Exact timeline duration in ticks.
    public let durationTicks: Int

    public init(
        id: Int,
        position: NotationTickPosition,
        duration: NotationDuration,
        dotCount: Int,
        isFullMeasure: Bool,
        voice: NotationVoiceRole,
        durationTicks: Int
    ) {
        self.id = id
        self.position = position
        self.duration = duration
        self.dotCount = dotCount
        self.isFullMeasure = isFullMeasure
        self.voice = voice
        self.durationTicks = durationTicks
    }
}

/// The control mark a resolved control event paints.
public enum NotationControlKind: String, Hashable, Sendable {
    case stop
    case choke
    case damp
}

/// One control onset carrying resolved visual intent: it anchors a timing
/// column (zero collision width) and paints its mark at `targetStaffStep`.
public struct ResolvedControl: Hashable, Sendable {
    public let id: Int
    public let position: NotationTickPosition
    public let kind: NotationControlKind
    /// Pitch-ascending staff step of the resolved target — the same
    /// convention as `ResolvedNote.staffStep` — after the caller applies its
    /// staff-position override.
    public let targetStaffStep: Int

    public init(
        id: Int,
        position: NotationTickPosition,
        kind: NotationControlKind,
        targetStaffStep: Int
    ) {
        self.id = id
        self.position = position
        self.kind = kind
        self.targetStaffStep = targetStaffStep
    }
}

/// A resolved tuplet ratio already inferred upstream (e.g. a 3:2 triplet).
public struct ResolvedTupletRatio: Hashable, Sendable {
    public let actual: Int
    public let normal: Int

    public init(actual: Int, normal: Int) {
        self.actual = actual
        self.normal = normal
    }
}

/// One resolved tuplet group. Members are IDs into the note and rest
/// collections — separate namespaces, each validated to reference existing
/// members in the same measure and voice.
public struct ResolvedTupletGroup: Hashable, Sendable {
    /// Deterministic adapter-local ID; the tuplet namespace is separate from
    /// the note/rest/control namespaces.
    public let id: Int
    public let measureIndex: Int
    public let voice: NotationVoiceRole
    public let ratio: ResolvedTupletRatio
    public let memberNoteIDs: [Int]
    public let memberRestIDs: [Int]

    public init(
        id: Int,
        measureIndex: Int,
        voice: NotationVoiceRole,
        ratio: ResolvedTupletRatio,
        memberNoteIDs: [Int],
        memberRestIDs: [Int]
    ) {
        self.id = id
        self.measureIndex = measureIndex
        self.voice = voice
        self.ratio = ratio
        self.memberNoteIDs = memberNoteIDs
        self.memberRestIDs = memberRestIDs
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
    public let tuplets: [ResolvedTupletGroup]

    /// - Throws: `ValidationError` for a non-positive `ticksPerWholeNote`,
    ///   duplicate/invalid/overlapping measures, beat groups that fail to
    ///   cover their measure, duplicate event IDs, non-positive event
    ///   durations, an event whose `localTick` falls outside its owning
    ///   measure, a note/rest whose `localTick + durationTicks` span crosses
    ///   its owning measure's end, or a tuplet that references unknown
    ///   members.
    public init(
        ticksPerWholeNote: Int,
        measures: [ResolvedMeasure],
        notes: [ResolvedNote] = [],
        rests: [ResolvedRest] = [],
        controls: [ResolvedControl] = [],
        tuplets: [ResolvedTupletGroup] = []
    ) throws {
        try Self.validate(
            ticksPerWholeNote: ticksPerWholeNote,
            measures: measures,
            events: EventCollections(notes: notes, rests: rests, controls: controls, tuplets: tuplets)
        )
        self.ticksPerWholeNote = ticksPerWholeNote
        self.measures = measures
        self.notes = notes
        self.rests = rests
        self.controls = controls
        self.tuplets = tuplets
    }

    public enum ValidationError: Error, Hashable, Sendable {
        case invalidTicksPerWholeNote(Int)
        case duplicateMeasureIndex(Int)
        case invalidMeasure(index: Int, startTick: Int, durationTicks: Int)
        case overlappingMeasures(first: ResolvedMeasure, second: ResolvedMeasure)
        case eventOutsideMeasure(eventID: Int, measureIndex: Int, localTick: Int)
        case invalidBeatGroupDuration(measureIndex: Int, startTick: Int, durationTicks: Int)
        case nonContiguousBeatGroups(measureIndex: Int, expectedStartTick: Int, actualStartTick: Int)
        case beatGroupsDoNotCoverMeasure(measureIndex: Int, durationTicks: Int, coveredTicks: Int)
        case duplicateEventID(Int)
        case invalidEventDurationTicks(eventID: Int, durationTicks: Int)
        case eventSpanOutsideMeasure(eventID: Int, measureIndex: Int, localTick: Int, durationTicks: Int)
        case invalidTupletRatio(tupletID: Int, actual: Int, normal: Int)
        case unknownTupletMeasure(tupletID: Int, measureIndex: Int)
        case unknownTupletMember(tupletID: Int, memberID: Int)
    }

    /// Groups the four event collections so `validate` stays readable and
    /// under the parameter-count limit.
    private struct EventCollections {
        let notes: [ResolvedNote]
        let rests: [ResolvedRest]
        let controls: [ResolvedControl]
        let tuplets: [ResolvedTupletGroup]
    }

    private static func validate(
        ticksPerWholeNote: Int,
        measures: [ResolvedMeasure],
        events: EventCollections
    ) throws {
        guard ticksPerWholeNote > 0 else {
            throw ValidationError.invalidTicksPerWholeNote(ticksPerWholeNote)
        }
        try validateMeasures(measures)
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
        for note in events.notes { try requireInsideMeasure(note.position, eventID: note.id) }
        for rest in events.rests { try requireInsideMeasure(rest.position, eventID: rest.id) }
        for control in events.controls { try requireInsideMeasure(control.position, eventID: control.id) }
        try requireUniqueIDs(events.notes.map(\.id))
        try requireUniqueIDs(events.rests.map(\.id))
        try requireUniqueIDs(events.controls.map(\.id))
        try requireUniqueIDs(events.tuplets.map(\.id))
        try validateEventDurations(
            notes: events.notes,
            rests: events.rests,
            measuresByIndex: measuresByIndex
        )
        try validateTuplets(
            tuplets: events.tuplets,
            notes: events.notes,
            rests: events.rests,
            measuresByIndex: measuresByIndex
        )
    }

    /// Per-measure bounds, beat-group coverage, index uniqueness, and
    /// overlap — checked before any event lookup relies on the indexes.
    private static func validateMeasures(_ measures: [ResolvedMeasure]) throws {
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
            try validateBeatGroups(measure)
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
    }

    /// Beat groups must be positive-duration, contiguous from tick 0, and
    /// exactly cover the measure — the group's validated ordinal is its
    /// array position, which the beam topology consumes directly.
    private static func validateBeatGroups(_ measure: ResolvedMeasure) throws {
        var expectedStart = 0
        for group in measure.beatGroups {
            guard group.durationTicks > 0 else {
                throw ValidationError.invalidBeatGroupDuration(
                    measureIndex: measure.index,
                    startTick: group.startTick,
                    durationTicks: group.durationTicks
                )
            }
            guard group.startTick == expectedStart else {
                throw ValidationError.nonContiguousBeatGroups(
                    measureIndex: measure.index,
                    expectedStartTick: expectedStart,
                    actualStartTick: group.startTick
                )
            }
            let advanced = expectedStart.addingReportingOverflow(group.durationTicks)
            guard !advanced.overflow else {
                throw ValidationError.beatGroupsDoNotCoverMeasure(
                    measureIndex: measure.index,
                    durationTicks: measure.durationTicks,
                    coveredTicks: Int.max
                )
            }
            expectedStart = advanced.partialValue
        }
        guard expectedStart == measure.durationTicks else {
            throw ValidationError.beatGroupsDoNotCoverMeasure(
                measureIndex: measure.index,
                durationTicks: measure.durationTicks,
                coveredTicks: expectedStart
            )
        }
    }

    /// Event IDs are unique within each collection; namespaces are separate,
    /// so an ID may repeat across collections but never inside one.
    private static func requireUniqueIDs(_ ids: [Int]) throws {
        var seen = Set<Int>()
        for id in ids where !seen.insert(id).inserted {
            throw ValidationError.duplicateEventID(id)
        }
    }

    /// Event durations stay positive and their span stays inside the owning
    /// measure: `localTick + durationTicks <= measure.durationTicks`, with the
    /// exact measure end allowed. The addition is reporting-overflow safe —
    /// an unrepresentable end is rejected, never trapped.
    private static func validateEventDurations(
        notes: [ResolvedNote],
        rests: [ResolvedRest],
        measuresByIndex: [Int: ResolvedMeasure]
    ) throws {
        for note in notes {
            try requireContainedSpan(
                eventID: note.id,
                position: note.position,
                durationTicks: note.durationTicks,
                measuresByIndex: measuresByIndex
            )
        }
        for rest in rests {
            try requireContainedSpan(
                eventID: rest.id,
                position: rest.position,
                durationTicks: rest.durationTicks,
                measuresByIndex: measuresByIndex
            )
        }
    }

    /// One event's duration span must be contained in its owning measure.
    /// The onset was already validated inside the measure above, so the
    /// measure lookup cannot fail here.
    private static func requireContainedSpan(
        eventID: Int,
        position: NotationTickPosition,
        durationTicks: Int,
        measuresByIndex: [Int: ResolvedMeasure]
    ) throws {
        guard durationTicks > 0 else {
            throw ValidationError.invalidEventDurationTicks(
                eventID: eventID,
                durationTicks: durationTicks
            )
        }
        guard let measure = measuresByIndex[position.measureIndex] else { return }
        let endTick = position.localTick.addingReportingOverflow(durationTicks)
        guard !endTick.overflow, endTick.partialValue <= measure.durationTicks else {
            throw ValidationError.eventSpanOutsideMeasure(
                eventID: eventID,
                measureIndex: position.measureIndex,
                localTick: position.localTick,
                durationTicks: durationTicks
            )
        }
    }

    /// Tuplets must have a positive ratio, live in a known measure, and
    /// reference existing notes/rests in that measure with the same voice.
    private static func validateTuplets(
        tuplets: [ResolvedTupletGroup],
        notes: [ResolvedNote],
        rests: [ResolvedRest],
        measuresByIndex: [Int: ResolvedMeasure]
    ) throws {
        let notesByID = Dictionary(notes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let restsByID = Dictionary(rests.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for tuplet in tuplets {
            guard tuplet.ratio.actual > 0, tuplet.ratio.normal > 0 else {
                throw ValidationError.invalidTupletRatio(
                    tupletID: tuplet.id,
                    actual: tuplet.ratio.actual,
                    normal: tuplet.ratio.normal
                )
            }
            guard measuresByIndex[tuplet.measureIndex] != nil else {
                throw ValidationError.unknownTupletMeasure(
                    tupletID: tuplet.id,
                    measureIndex: tuplet.measureIndex
                )
            }
            for memberID in tuplet.memberNoteIDs {
                guard let note = notesByID[memberID],
                      note.position.measureIndex == tuplet.measureIndex,
                      note.voice == tuplet.voice else {
                    throw ValidationError.unknownTupletMember(tupletID: tuplet.id, memberID: memberID)
                }
            }
            for memberID in tuplet.memberRestIDs {
                guard let rest = restsByID[memberID],
                      rest.position.measureIndex == tuplet.measureIndex,
                      rest.voice == tuplet.voice else {
                    throw ValidationError.unknownTupletMember(tupletID: tuplet.id, memberID: memberID)
                }
            }
        }
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
