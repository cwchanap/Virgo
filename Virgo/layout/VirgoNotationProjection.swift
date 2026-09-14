import CoreGraphics
import DrumNotation

/// The HPA-164 pre-format projection (Task 4): the single app-site style
/// mapper, the snapshot→package input projection, and the pre-format visible
/// flag classification. Split from `VirgoNotationAdapter`, which remains the
/// primitive/flag-paint owner.
enum VirgoNotationProjection {
    /// The single app-site style mapper for measured formatting (HPA-164 Task
    /// 4): resolved row width with the app's 900pt floor plus the exact
    /// default values pinned in Task 1. No other app site may construct
    /// `NotationFormattingStyle`.
    static func formattingStyle(
        rowWidth: CGFloat,
        style: NotationLayoutStyle
    ) -> NotationFormattingStyle {
        NotationFormattingStyle(
            availableRowWidth: max(GameplayLayout.maxRowWidth, rowWidth),
            rowLeadingInset: GameplayLayout.leftMargin,
            staffSpace: style.staffLineSpacing,
            stemWidth: GameplayLayout.stemWidth,
            minimumInterColumnClearance: 8,
            minimumQuarterNoteSpacing: GameplayLayout.uniformSpacing,
            measureSpacing: GameplayLayout.measureSpacing,
            leadingMeasureInset: GameplayLayout.barLineWidth + GameplayLayout.uniformSpacing,
            trailingMeasureInset: 0,
            rhythmDotRadius: style.rhythmDotRadius,
            rhythmDotSpacing: style.rhythmDotSpacing
        )
    }

    /// Projects the snapshot into package formatter input (HPA-164 Task 4).
    /// Trailing-measure expansion must already have happened; the package
    /// receives the complete requested measure list and synthesizes no app
    /// timing policy. Hidden rests are filtered here (the package has no
    /// hidden-rest state), and notes/rests/controls that would fall outside
    /// their measure are dropped exactly like the current engine guards.
    static func resolvedNotation(
        snapshot: RhythmLayoutSnapshot,
        expandedMeasures: [RhythmMeasure],
        notePositionOverrides: [DrumType: GameplayLayout.NotePosition]
    ) throws -> ResolvedNotationInput {
        let measuresByIndex = Dictionary(
            uniqueKeysWithValues: expandedMeasures.map { ($0.measureIndex, $0) }
        )
        let notes = mappedNotes(snapshot: snapshot, measuresByIndex: measuresByIndex)
        let flags = visibleFlagClassifications(notes: notes, expandedMeasures: expandedMeasures)
        return try ResolvedNotationInput(
            ticksPerWholeNote: snapshot.ticksPerWholeNote,
            measures: expandedMeasures.map {
                ResolvedMeasure(
                    index: $0.measureIndex,
                    startTick: $0.startTick,
                    durationTicks: $0.durationTicks
                )
            },
            notes: resolvedNotes(notes: notes, flags: flags, notePositionOverrides: notePositionOverrides),
            rests: resolvedRests(
                printed: printedRests(snapshot: snapshot, measuresByIndex: measuresByIndex),
                measuresByIndex: measuresByIndex
            ),
            controls: resolvedControls(snapshot: snapshot, measuresByIndex: measuresByIndex)
        )
    }

    /// The three-arm visible-flag mapping pinned by the brief: no uncovered
    /// level → nil, all expected levels uncovered → the canonical duration
    /// flag, partially uncovered → an `.eighth` component footprint.
    static func visibleFlagClassification(
        uncovered: Set<Int>,
        expected: Set<Int>,
        canonical: NotationFlagDuration
    ) -> NotationFlagDuration? {
        guard !uncovered.isEmpty else { return nil }
        return uncovered == expected ? canonical : .eighth
    }

    /// Pre-format visible flag classification per note event ID. Rebuilds the
    /// X-independent `BeamTimelineEvent` topology from the same
    /// timing/voice/beat-group inputs the post-format flag builder consumes,
    /// with provisional row identity (beam groups are measure-local), then
    /// maps each stem group's uncovered beam levels through
    /// ``visibleFlagClassification(uncovered:expected:canonical:)``.
    static func visibleFlagClassifications(
        notes: [(note: RhythmLayoutNote, definition: DrumNotationDefinition)],
        expandedMeasures: [RhythmMeasure]
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
            permitsEngraving: permitsEngraving
        )
    }

    // MARK: - Notes

    private static func resolvedNotes(
        notes: [(note: RhythmLayoutNote, definition: DrumNotationDefinition)],
        flags: [Int: NotationFlagDuration],
        notePositionOverrides: [DrumType: GameplayLayout.NotePosition]
    ) -> [ResolvedNote] {
        notes.map { entry -> ResolvedNote in
            let position = staffPosition(for: entry, overrides: notePositionOverrides)
            return ResolvedNote(
                id: entry.note.eventID.rawValue,
                position: NotationTickPosition(
                    measureIndex: entry.note.position.measureIndex,
                    localTick: entry.note.position.localTick
                ),
                stemDirection: VirgoNotationAdapter.stemDirection(entry.definition.defaultStemDirection),
                // The package orders staff steps pitch-ascending (its pinned
                // VexFlow displacement walks away from the stem side through
                // ascending steps); Virgo's layout staffStep is Y-down, so
                // negate at this seam. Keeps the stem-side head undisplaced.
                staffStep: -NotationLayoutEngine.staffStep(for: position),
                noteheadStyle: VirgoNotationAdapter.noteheadStyle(for: entry.note.noteType),
                duration: VirgoNotationAdapter.duration(for: entry.note.rhythm.baseInterval),
                dotCount: entry.note.rhythm.dotCount,
                visibleFlagDuration: flags[entry.note.eventID.rawValue]
            )
        }
    }

    /// Snapshot notes that pass the same guards the engine applies before
    /// building timeline note heads, paired with their catalog definitions.
    private static func mappedNotes(
        snapshot: RhythmLayoutSnapshot,
        measuresByIndex: [Int: RhythmMeasure]
    ) -> [(note: RhythmLayoutNote, definition: DrumNotationDefinition)] {
        snapshot.notes.compactMap { note in
            guard let definition = DrumNotationCatalog.resolve(
                noteType: note.noteType,
                sourceLaneID: note.sourceLaneID
            )?.definition,
                UInt64(exactly: note.eventID.rawValue) != nil,
                let measure = measuresByIndex[note.position.measureIndex],
                note.position.localTick >= 0,
                note.position.localTick < measure.durationTicks,
                note.position.absoluteTick == measure.startTick + note.position.localTick
            else { return nil }
            return (note, definition)
        }
    }

    private static func staffPosition(
        for entry: (note: RhythmLayoutNote, definition: DrumNotationDefinition),
        overrides: [DrumType: GameplayLayout.NotePosition]
    ) -> GameplayLayout.NotePosition {
        overrides[entry.definition.gameplayInstrument] ?? entry.definition.defaultPosition
    }

    // MARK: - Rests

    /// Deterministic adapter-local rest namespace: rests carry no event ID,
    /// so each printed rest's `ResolvedRest.id` is its ordinal in the printed
    /// sort order below. `NotationLayoutEngine.buildRests` reconstructs the
    /// same ordinal from its identically sorted candidates to join every
    /// printed rest to its `FormattedRest` placement.
    private static func resolvedRests(
        printed: [RhythmLayoutRest],
        measuresByIndex: [Int: RhythmMeasure]
    ) -> [ResolvedRest] {
        printed.enumerated().map { index, rest -> ResolvedRest in
            let measure = measuresByIndex[rest.position.measureIndex]
            let fillsMeasure = rest.position.localTick == 0
                && rest.durationTicks == measure?.durationTicks
            let legacy = legacyRestDuration(rhythm: rest.rhythm, fillsMeasure: fillsMeasure)
            return ResolvedRest(
                id: index,
                position: NotationTickPosition(
                    measureIndex: rest.position.measureIndex,
                    localTick: rest.position.localTick
                ),
                duration: VirgoNotationAdapter.restDuration(legacy) ?? .quarter,
                dotCount: rest.rhythm.dotCount,
                isFullMeasure: legacy == .fullMeasure
            )
        }
    }

    /// Printed rests that pass the engine's rest guards, in its candidate
    /// sort order (tick ascending, upper voice first, longer first). Rests
    /// in engraving-unsupported measures are filtered here too: Virgo
    /// suppresses their engraving at composition, so they must not reserve
    /// measured ink in the package.
    private static func printedRests(
        snapshot: RhythmLayoutSnapshot,
        measuresByIndex: [Int: RhythmMeasure]
    ) -> [RhythmLayoutRest] {
        snapshot.rests.compactMap { rest -> RhythmLayoutRest? in
            guard rest.visibility == .printed,
                let measure = measuresByIndex[rest.position.measureIndex],
                measure.engravingSupport.permitsEngraving,
                rest.position.localTick >= 0,
                rest.position.localTick < measure.durationTicks,
                rest.position.absoluteTick == measure.startTick + rest.position.localTick,
                rest.durationTicks > 0,
                rest.position.localTick + rest.durationTicks <= measure.durationTicks
            else { return nil }
            return rest
        }
        .sorted {
            if $0.position.absoluteTick != $1.position.absoluteTick {
                return $0.position.absoluteTick < $1.position.absoluteTick
            }
            if $0.voice != $1.voice { return $0.voice == .upper }
            return $0.durationTicks > $1.durationTicks
        }
    }

    // MARK: - Controls

    private static func resolvedControls(
        snapshot: RhythmLayoutSnapshot,
        measuresByIndex: [Int: RhythmMeasure]
    ) -> [ResolvedControl] {
        snapshot.controls.compactMap { control -> ResolvedControl? in
            guard let measure = measuresByIndex[control.position.measureIndex],
                control.position.localTick >= 0,
                control.position.localTick < measure.durationTicks,
                control.position.absoluteTick == measure.startTick + control.position.localTick
            else { return nil }
            return ResolvedControl(
                id: control.eventID.rawValue,
                position: NotationTickPosition(
                    measureIndex: control.position.measureIndex,
                    localTick: control.position.localTick
                )
            )
        }
    }

    // MARK: - Stem groups

    /// One beam-topology stem group: its member entries plus the timeline
    /// event the topology builder consumes.
    private struct StemGroup {
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
    /// so topology coverage indices line up.
    private static func buildStemGroups(
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
    private static func classifyUncoveredFlagLevels(
        stemGroups: [StemGroup],
        topology: BeamTopologyResult,
        permitsEngraving: [Int: Bool]
    ) -> [Int: NotationFlagDuration] {
        var classifications: [Int: NotationFlagDuration] = [:]
        for (index, stemGroup) in stemGroups.enumerated() {
            guard case let .beamable(requiredLevels, _) = stemGroup.event.role else { continue }
            // Notes in engraving-unsupported measures never paint flags.
            guard permitsEngraving[stemGroup.event.timeColumn.measureIndex] == true else { continue }
            let covered = topology.coveredLevelsByEventIndex[index] ?? []
            let expected = Set(0..<requiredLevels)
            guard let representative = flagRepresentative(in: stemGroup.entries),
                let canonical = VirgoNotationAdapter.flagDuration(for: representative.note.rhythm.baseInterval)
            else { continue }
            let classification = visibleFlagClassification(
                uncovered: expected.subtracting(covered),
                expected: expected,
                canonical: canonical
            )
            guard let classification else { continue }
            // ONE measured anchor per stem group: the classification rides on
            // the stem representative — the same head buildFlags paints the
            // flag on — so the formatter reserves a single flag footprint at
            // the shared stem axis, never one per chord member.
            classifications[representative.note.eventID.rawValue] = classification
        }
        return classifications
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
