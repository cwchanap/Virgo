// HPA-166 Task 2 — package ownership of the stem-group flag planning that
// rides the ported beam topology (`BeamTopology.swift`). This is the mirror
// of `Virgo/layout/VirgoNotationProjection+Flags.swift` plus the
// engine's stem-group/representative logic in
// `NotationLayoutEngine+Beams.swift`: same grouping key, same pinned
// comparators, same three-arm visible-flag classification — one plan per
// stem group, measured once at the shared stem axis.
//
// Everything here is internal: the engraving result and tests consume the
// topology; no public API is added.

extension NotationDuration {
    /// True when the duration takes a stem (everything but whole).
    var needsStem: Bool { self != .whole }

    /// Required beam/flag levels — the interval's flag count.
    var flagCount: Int {
        switch self {
        case .whole, .half, .quarter:
            return 0
        case .eighth:
            return 1
        case .sixteenth:
            return 2
        case .thirtySecond:
            return 3
        case .sixtyFourth:
            return 4
        }
    }

    /// The canonical flag glyph family, or nil for unflagged durations.
    var flagDuration: NotationFlagDuration? {
        switch self {
        case .eighth:
            return .eighth
        case .sixteenth:
            return .sixteenth
        case .thirtySecond:
            return .thirtySecond
        case .sixtyFourth:
            return .sixtyFourth
        case .whole, .half, .quarter:
            return nil
        }
    }
}

// MARK: - Stem groups

/// One beam-topology stem group key: measure + local tick + voice + stem
/// direction. Beam groups are measure-local, so no row participates.
struct StemGroupKey: Hashable {
    let measureIndex: Int
    let localTick: Int
    let voice: NotationVoiceRole
    let stemDirection: NotationStemDirection
}

/// One onset/voice/direction chord collapsed into a single stem group: its
/// member note IDs plus the explicit representative IDs every consumer
/// (topology, stem geometry, formatter flag footprint, flag painting)
/// shares.
struct StemGroup: Hashable {
    let key: StemGroupKey
    /// Every member note ID in stable sorted order.
    let memberNoteIDs: [Int]
    /// The stem-side member the shared stem axis is painted from — the head
    /// whose undisplaced anchor anchors the stem and any visible flag.
    /// Nil when no member needs a stem or none is engravable.
    let stemRepresentativeID: Int?
    /// The member owning beam-level/flag-count decisions and the canonical
    /// flag family — intentionally distinct from the stem representative.
    let flagRepresentativeID: Int?
}

// MARK: - Visible flag plan

/// One stem group's visible flag plan: which flag ink the formatter reserves
/// at the shared stem axis and, later, which glyphs the flag painter draws.
enum VisibleFlagPlan: Hashable, Sendable {
    case none
    case canonical(NotationFlagDuration)
    case components(Set<Int>)

    /// The three-arm mapping: no uncovered level → `.none`; every expected
    /// level uncovered → `.canonical` at the flag representative's family; a
    /// proper subset → `.components` carrying exactly the uncovered levels.
    init(uncovered: Set<Int>, expected: Set<Int>, canonical: NotationFlagDuration) {
        if uncovered.isEmpty {
            self = .none
        } else if uncovered == expected {
            self = .canonical(canonical)
        } else {
            self = .components(uncovered)
        }
    }

    /// The flag footprint the formatter reserves at the shared stem axis:
    /// the canonical glyph for a fully uncovered family, one eighth
    /// component glyph for any partial set, nothing otherwise.
    var reservedFlagDuration: NotationFlagDuration? {
        switch self {
        case .none:
            return nil
        case .canonical(let duration):
            return duration
        case .components(let levels):
            return levels.isEmpty ? nil : .eighth
        }
    }
}

// MARK: - Stem topology result

/// The package mirror of the app's pre-format flag prepass: ordered stem
/// groups, their beam timeline events, the replayed topology, and one
/// `VisibleFlagPlan` per group.
struct StemTopology: Equatable {
    let stemGroups: [StemGroup]
    let events: [BeamTimelineEvent]
    let topology: BeamTopologyResult
    /// One visible flag plan per stem group, parallel to `stemGroups`.
    let flagPlans: [VisibleFlagPlan]

    /// The flag ink reservation per stem group, keyed by the stem-side
    /// representative's note ID — the single measured anchor the formatter
    /// reserves flag ink at, never one per chord member.
    var flagReservations: [Int: NotationFlagDuration] {
        var reservations: [Int: NotationFlagDuration] = [:]
        for (group, plan) in zip(stemGroups, flagPlans) {
            guard let representativeID = group.stemRepresentativeID,
                  let duration = plan.reservedFlagDuration else { continue }
            reservations[representativeID] = duration
        }
        return reservations
    }
}

/// Builds stem groups from resolved notes, replays the beam topology over
/// their events, and derives one `VisibleFlagPlan` per group.
struct StemTopologyBuilder {
    /// Builds the complete stem topology for already-validated input.
    func build(_ input: ResolvedNotationInput) -> StemTopology {
        let notesByID = Dictionary(
            input.notes.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let measuresByIndex = Dictionary(
            input.measures.map { ($0.index, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let pairs = buildStemGroups(notes: input.notes, notesByID: notesByID, measuresByIndex: measuresByIndex)
            .sorted { stemGroupComesBefore($0.event, $1.event) }
        let stemGroups = pairs.map(\.group)
        let events = pairs.map(\.event)
        let topology = NotationBeamTopologyBuilder().build(
            events: events,
            measures: input.measures
        )
        let flagPlans = stemGroups.enumerated().map { index, group in
            flagPlan(
                for: group,
                eventIndex: index,
                events: events,
                topology: topology,
                notesByID: notesByID
            )
        }
        return StemTopology(
            stemGroups: stemGroups,
            events: events,
            topology: topology,
            flagPlans: flagPlans
        )
    }

    /// One beam-topology stem group plus the timeline event the topology
    /// builder consumes — the mirror of the app prepass's pair.
    private typealias GroupAndEvent = (group: StemGroup, event: BeamTimelineEvent)

    /// Groups resolved notes by (measure, local tick, voice, stem direction)
    /// and picks both representatives with the pinned comparators.
    private func buildStemGroups(
        notes: [ResolvedNote],
        notesByID: [Int: ResolvedNote],
        measuresByIndex: [Int: ResolvedMeasure]
    ) -> [GroupAndEvent] {
        var grouped: [StemGroupKey: [ResolvedNote]] = [:]
        for note in notes {
            grouped[StemGroupKey(
                measureIndex: note.position.measureIndex,
                localTick: note.position.localTick,
                voice: note.voice,
                stemDirection: note.stemDirection
            ), default: []].append(note)
        }
        return grouped.map { key, members in
            let group = StemGroup(
                key: key,
                memberNoteIDs: members.map(\.id).sorted(),
                stemRepresentativeID: stemRepresentative(in: members)?.id,
                flagRepresentativeID: flagRepresentative(in: members)?.id
            )
            return (
                group: group,
                event: stemGroupEvent(for: group, notesByID: notesByID, measuresByIndex: measuresByIndex)
            )
        }
    }

    /// Same event semantics as the engine's timeline `buildTimelineEvents`:
    /// the flag representative governs beam levels and adjacency duration,
    /// while every member ID rides on the event.
    private func stemGroupEvent(
        for group: StemGroup,
        notesByID: [Int: ResolvedNote],
        measuresByIndex: [Int: ResolvedMeasure]
    ) -> BeamTimelineEvent {
        let representative = group.flagRepresentativeID.flatMap { notesByID[$0] }
        let role: BeamTimelineEventRole
        if let representative,
           representative.duration.flagCount > 0,
           representative.isRhythmEngravable,
           representative.durationTicks > 0 {
            role = .beamable(
                requiredBeamLevels: representative.duration.flagCount,
                durationTicks: representative.durationTicks
            )
        } else {
            role = .boundary
        }
        return BeamTimelineEvent(
            measureIndex: group.key.measureIndex,
            localTick: group.key.localTick,
            absoluteTick: (measuresByIndex[group.key.measureIndex]?.startTick ?? 0)
                + group.key.localTick,
            voice: group.key.voice,
            stemDirection: group.key.stemDirection,
            noteIDs: group.memberNoteIDs,
            role: role
        )
    }

    /// The stem-group ordering the app prepass uses — deterministic
    /// (measure, absolute tick, voice, direction, member IDs) so topology
    /// coverage indices line up regardless of input order.
    private func stemGroupComesBefore(
        _ lhs: BeamTimelineEvent,
        _ rhs: BeamTimelineEvent
    ) -> Bool {
        if lhs.measureIndex != rhs.measureIndex {
            return lhs.measureIndex < rhs.measureIndex
        }
        if lhs.absoluteTick != rhs.absoluteTick {
            return lhs.absoluteTick < rhs.absoluteTick
        }
        // App parity: `NotationVoice` is String-raw there, so "lower" sorts
        // before "upper" — replicate it with the Int-raw package role.
        if lhs.voice != rhs.voice {
            return lhs.voice == .lower
        }
        if lhs.stemDirection.rawValue != rhs.stemDirection.rawValue {
            return lhs.stemDirection.rawValue < rhs.stemDirection.rawValue
        }
        return lhs.noteIDs.lexicographicallyPrecedes(rhs.noteIDs)
    }

    /// The engine's `stemRepresentative` pick over resolved notes: members
    /// that need a stem and are engravable, ordered by staff position
    /// (pitch-ascending `staffStep` — the app's rendered-Y order reversed),
    /// then `tiebreakOrder`, then ID; up-stems take the lowest (stem-side)
    /// member, down-stems the highest.
    private func stemRepresentative(in members: [ResolvedNote]) -> ResolvedNote? {
        let candidates = members.filter { $0.duration.needsStem && $0.isRhythmEngravable }
        guard let direction = candidates.first?.stemDirection else { return nil }
        let ordered = candidates.sorted { lhs, rhs in
            if lhs.staffStep != rhs.staffStep { return lhs.staffStep > rhs.staffStep }
            if lhs.tiebreakOrder != rhs.tiebreakOrder {
                return lhs.tiebreakOrder < rhs.tiebreakOrder
            }
            return lhs.id < rhs.id
        }
        return direction == .up ? ordered.last : ordered.first
    }

    /// The engine's `flagRepresentative` comparator over resolved notes:
    /// most required flag levels, then `tiebreakOrder`, then ID.
    private func flagRepresentative(in members: [ResolvedNote]) -> ResolvedNote? {
        members.min { lhs, rhs in
            if lhs.duration.flagCount != rhs.duration.flagCount {
                return lhs.duration.flagCount > rhs.duration.flagCount
            }
            if lhs.tiebreakOrder != rhs.tiebreakOrder {
                return lhs.tiebreakOrder < rhs.tiebreakOrder
            }
            return lhs.id < rhs.id
        }
    }

    /// Maps each beamable stem group's uncovered beam levels to its flag
    /// plan — the same classification the app prepass applies, keyed to the
    /// group whose stem-side representative owns the measured anchor.
    private func flagPlan(
        for group: StemGroup,
        eventIndex: Int,
        events: [BeamTimelineEvent],
        topology: BeamTopologyResult,
        notesByID: [Int: ResolvedNote]
    ) -> VisibleFlagPlan {
        guard case let .beamable(requiredLevels, _) = events[eventIndex].role,
              let representativeID = group.flagRepresentativeID,
              let canonical = notesByID[representativeID]?.duration.flagDuration
        else { return .none }
        let covered = topology.coveredLevelsByEventIndex[eventIndex] ?? []
        let expected = Set(0..<requiredLevels)
        return VisibleFlagPlan(
            uncovered: expected.subtracting(covered),
            expected: expected,
            canonical: canonical
        )
    }
}
