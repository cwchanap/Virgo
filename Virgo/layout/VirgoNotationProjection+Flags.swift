import CoreGraphics
import DrumNotation

/// The pre-format visible flag classification (HPA-164 Task 4): stem-group
/// construction, beam-topology replay and uncovered-level mapping. Split
/// from `VirgoNotationProjection` to keep the main file under the SwiftLint
/// type-body limit — the mirror of `NotationLayoutEngine+Beams.swift`.
extension VirgoNotationProjection {
    /// Pre-format visible flag classification per note event ID. Rebuilds the
    /// X-independent `BeamTimelineEvent` topology from the same
    /// timing/voice/beat-group inputs the post-format flag builder consumes,
    /// with provisional row identity (beam groups are measure-local), then
    /// maps each stem group's uncovered beam levels through
    /// ``visibleFlagClassification(uncovered:expected:canonical:)``.
    static func visibleFlagClassifications(
        notes: [(note: RhythmLayoutNote, definition: DrumNotationDefinition)],
        expandedMeasures: [RhythmMeasure],
        notePositionOverrides: [DrumType: GameplayLayout.NotePosition] = [:]
    ) -> [Int: NotationFlagDuration] {
        let permitsEngraving = Dictionary(
            uniqueKeysWithValues: expandedMeasures.map { ($0.measureIndex, $0.engravingSupport.permitsEngraving) }
        )
        let stemGroups = buildStemGroups(notes: notes)
        let topology = NotationBeamTopologyBuilder().build(
            events: stemGroups.map(\.event),
            measures: expandedMeasures
        )
        return classifyUncoveredFlagLevels(
            stemGroups: stemGroups,
            topology: topology,
            permitsEngraving: permitsEngraving,
            notePositionOverrides: notePositionOverrides
        )
    }

    // MARK: - Stem groups

    /// One beam-topology stem group: its member entries plus the timeline
    /// event the topology builder consumes. Internal (not private) so the
    /// HPA-166 parity gate can drive the same classification decomposition
    /// with a synthetic coverage map — production calls this exact path.
    struct StemGroup {
        let entries: [(note: RhythmLayoutNote, definition: DrumNotationDefinition)]
        let event: BeamTimelineEvent
    }

    /// Beam groups are measure-local, so the provisional row identity is the
    /// (measure, tick, voice, stem direction) key.
    private struct StemGroupKey: Hashable {
        let measureIndex: Int
        let localTick: Int
        let voice: NotationVoice
        let stemDirection: StemDirection
    }

    /// Same event semantics as the engine's timeline
    /// `buildTimelineEvents(noteHeads:)`, sorted with the same comparator
    /// so topology coverage indices line up. Internal for the parity gate.
    static func buildStemGroups(
        notes: [(note: RhythmLayoutNote, definition: DrumNotationDefinition)]
    ) -> [StemGroup] {
        var grouped: [StemGroupKey: [(note: RhythmLayoutNote, definition: DrumNotationDefinition)]] = [:]
        for entry in notes {
            grouped[StemGroupKey(
                measureIndex: entry.note.position.measureIndex,
                localTick: entry.note.position.localTick,
                voice: entry.definition.voice,
                stemDirection: entry.definition.defaultStemDirection
            ), default: []].append(entry)
        }
        return grouped.values.compactMap { group -> StemGroup? in
            guard let representative = flagRepresentative(in: group) else { return nil }
            return StemGroup(entries: group, event: stemGroupEvent(representative: representative, group: group))
        }
        .sorted(by: areStemGroupsOrdered)
    }

    private static func stemGroupEvent(
        representative: (note: RhythmLayoutNote, definition: DrumNotationDefinition),
        group: [(note: RhythmLayoutNote, definition: DrumNotationDefinition)]
    ) -> BeamTimelineEvent {
        let flagCount = representative.note.rhythm.baseInterval.flagCount
        let role: BeamTimelineEventRole
        if flagCount > 0,
            representative.note.rhythm.support == .supported,
            representative.note.durationTicks > 0 {
            role = .beamable(
                requiredBeamLevels: flagCount,
                durationTicks: representative.note.durationTicks
            )
        } else {
            role = .boundary
        }
        return BeamTimelineEvent(
            timeColumn: NotationTimeColumn(
                measureIndex: representative.note.position.measureIndex,
                tickWithinMeasure: representative.note.position.localTick,
                absoluteLayoutTick: representative.note.position.absoluteTick
            ),
            row: 0,
            voice: representative.definition.voice,
            stemDirection: representative.definition.defaultStemDirection,
            noteHeadIDs: group.map { UInt64($0.note.eventID.rawValue) }.sorted(),
            role: role
        )
    }

    private static func areStemGroupsOrdered(_ lhs: StemGroup, _ rhs: StemGroup) -> Bool {
        if lhs.event.timeColumn.measureIndex != rhs.event.timeColumn.measureIndex {
            return lhs.event.timeColumn.measureIndex < rhs.event.timeColumn.measureIndex
        }
        if lhs.event.timeColumn.absoluteLayoutTick != rhs.event.timeColumn.absoluteLayoutTick {
            return lhs.event.timeColumn.absoluteLayoutTick < rhs.event.timeColumn.absoluteLayoutTick
        }
        if lhs.event.voice.rawValue != rhs.event.voice.rawValue {
            return lhs.event.voice.rawValue < rhs.event.voice.rawValue
        }
        if lhs.event.stemDirection.rawValue != rhs.event.stemDirection.rawValue {
            return lhs.event.stemDirection.rawValue < rhs.event.stemDirection.rawValue
        }
        return lhs.event.noteHeadIDs.lexicographicallyPrecedes(rhs.event.noteHeadIDs)
    }

    /// Maps each beamable stem group's uncovered beam levels to its flag
    /// classification, keyed by the stem representative's event ID.
    /// Internal for the parity gate, which injects synthetic coverage to
    /// pin the defensive partial-coverage arm through this exact function.
    static func classifyUncoveredFlagLevels(
        stemGroups: [StemGroup],
        topology: BeamTopologyResult,
        permitsEngraving: [Int: Bool],
        notePositionOverrides: [DrumType: GameplayLayout.NotePosition]
    ) -> [Int: NotationFlagDuration] {
        var classifications: [Int: NotationFlagDuration] = [:]
        for (index, stemGroup) in stemGroups.enumerated() {
            guard case let .beamable(requiredLevels, _) = stemGroup.event.role else { continue }
            // Notes in engraving-unsupported measures never paint flags.
            guard permitsEngraving[stemGroup.event.timeColumn.measureIndex] == true else { continue }
            let covered = topology.coveredLevelsByEventIndex[index] ?? []
            let expected = Set(0..<requiredLevels)
            // The painted flag family comes from the flag representative
            // (buildFlags tags the flag with it and its interval supplies the
            // expected levels); its X comes from the shared stem axis.
            guard let flagRepresentative = flagRepresentative(in: stemGroup.entries),
                let canonical = VirgoNotationAdapter.flagDuration(for: flagRepresentative.note.rhythm.baseInterval),
                let stemRepresentative = stemRepresentative(
                    in: stemGroup.entries,
                    overrides: notePositionOverrides
                )
            else { continue }
            let classification = visibleFlagClassification(
                uncovered: expected.subtracting(covered),
                expected: expected,
                canonical: canonical
            )
            guard let classification else { continue }
            // ONE measured anchor per stem group: the classification rides on
            // the stem representative — the head whose anchor buildStems
            // paints the shared stem from, which flagStemOrigin anchors the
            // painted flag to — so the formatter reserves the flag's ink at
            // the axis Virgo actually paints it from, never one per chord
            // member.
            classifications[stemRepresentative.note.eventID.rawValue] = classification
        }
        return classifications
    }

    /// The engine's `stemRepresentative` pick over snapshot notes: supported
    /// heads whose interval needs a stem, ordered by rendered staff position
    /// (override-aware yOffset — all entries share the provisional row, so
    /// yOffset order is the engine's position.y order), then catalog order,
    /// then event ID; up-stems take the lowest (stem-side) head, down-stems
    /// the highest.
    private static func stemRepresentative(
        in group: [(note: RhythmLayoutNote, definition: DrumNotationDefinition)],
        overrides: [DrumType: GameplayLayout.NotePosition]
    ) -> (note: RhythmLayoutNote, definition: DrumNotationDefinition)? {
        let members = group.filter {
            $0.note.rhythm.baseInterval.needsStem && $0.note.rhythm.support == .supported
        }
        guard let direction = members.first?.definition.defaultStemDirection else { return nil }
        let ordered = members.sorted { lhs, rhs in
            let lhsY = staffPosition(for: lhs, overrides: overrides).yOffset
            let rhsY = staffPosition(for: rhs, overrides: overrides).yOffset
            if lhsY != rhsY { return lhsY < rhsY }
            if lhs.definition.catalogOrder != rhs.definition.catalogOrder {
                return lhs.definition.catalogOrder < rhs.definition.catalogOrder
            }
            return lhs.note.eventID.rawValue < rhs.note.eventID.rawValue
        }
        return direction == .up ? ordered.last : ordered.first
    }

    /// The engine's ``flagRepresentative`` comparator over snapshot notes:
    /// most flags, then catalog order, then event ID.
    private static func flagRepresentative(
        in group: [(note: RhythmLayoutNote, definition: DrumNotationDefinition)]
    ) -> (note: RhythmLayoutNote, definition: DrumNotationDefinition)? {
        group.min {
            let lhsFlags = $0.note.rhythm.baseInterval.flagCount
            let rhsFlags = $1.note.rhythm.baseInterval.flagCount
            if lhsFlags != rhsFlags { return lhsFlags > rhsFlags }
            if $0.definition.catalogOrder != $1.definition.catalogOrder {
                return $0.definition.catalogOrder < $1.definition.catalogOrder
            }
            return $0.note.eventID.rawValue < $1.note.eventID.rawValue
        }
    }
}
