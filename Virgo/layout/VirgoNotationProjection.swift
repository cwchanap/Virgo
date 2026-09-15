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
        let flags = visibleFlagClassifications(
            notes: notes,
            expandedMeasures: expandedMeasures,
            notePositionOverrides: notePositionOverrides
        )
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
                // The engine's stem membership: buildStems paints a shared
                // stem only for supported notes whose interval needs one.
                stemMember: entry.note.rhythm.baseInterval.needsStem
                    && entry.note.rhythm.support == .supported,
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

    /// Shared by `resolvedNotes` and the flag-classification extension's
    /// stem-representative ordering: the rendered note position for an entry.
    static func staffPosition(
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

}
