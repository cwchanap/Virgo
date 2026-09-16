import CoreGraphics
import DrumNotation

/// The HPA-164 pre-format projection (Task 4): the single app-site style
/// mapper, the snapshot→package input projection, and the pre-format visible
/// flag classification. Split from `VirgoNotationAdapter`, which remains the
/// primitive/flag-paint owner. HPA-166 Task 1 extends the projected input
/// with the final engraving semantics (voice, meter, beat groups, control
/// intent, resolved tuplets) while production still consumes the formatter.
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
        // One sort feeds both boundary consumers: the printed subset crosses
        // as `ResolvedRest`s (its ordinal order is the adapter-local rest ID
        // namespace), while the full candidate set — every visibility — feeds
        // tuplet feel-pair detection exactly like `buildTuplets` does over
        // `buildRests` output.
        let candidates = restCandidates(snapshot: snapshot, measuresByIndex: measuresByIndex)
        let printed = candidates.filter { $0.visibility == .printed }
        return try ResolvedNotationInput(
            ticksPerWholeNote: snapshot.ticksPerWholeNote,
            measures: expandedMeasures.map { measure in
                ResolvedMeasure(
                    index: measure.measureIndex,
                    startTick: measure.startTick,
                    durationTicks: measure.durationTicks,
                    meter: NotationMeter(
                        beats: measure.timeSignature.beatsPerMeasure,
                        noteValue: measure.timeSignature.noteValue
                    ),
                    beatGroups: measure.beatGroups.map {
                        ResolvedBeatGroup(startTick: $0.startTick, durationTicks: $0.durationTicks)
                    }
                )
            },
            notes: resolvedNotes(
                notes: notes,
                flags: flags,
                notePositionOverrides: notePositionOverrides,
                measuresByIndex: measuresByIndex
            ),
            rests: resolvedRests(printed: printed, measuresByIndex: measuresByIndex),
            controls: resolvedControls(
                snapshot: snapshot,
                measuresByIndex: measuresByIndex,
                notePositionOverrides: notePositionOverrides
            ),
            tuplets: VirgoNotationTupletProjection.resolvedTuplets(
                notes: notes,
                rests: candidates,
                printedRests: printed,
                measuresByIndex: measuresByIndex,
                feel: snapshot.feel
            )
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

    /// `NotationVoice` → package `NotationVoiceRole` (file-private so the
    /// tuplet arm in this file can share it).
    fileprivate static func notationVoiceRole(_ voice: NotationVoice) -> NotationVoiceRole {
        switch voice {
        case .upper: return .upper
        case .lower: return .lower
        }
    }

    // MARK: - Notes

    private static func resolvedNotes(
        notes: [(note: RhythmLayoutNote, definition: DrumNotationDefinition)],
        flags: [Int: NotationFlagDuration],
        notePositionOverrides: [DrumType: GameplayLayout.NotePosition],
        measuresByIndex: [Int: RhythmMeasure]
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
                visibleFlagDuration: flags[entry.note.eventID.rawValue],
                voice: notationVoiceRole(entry.definition.voice),
                durationTicks: entry.note.durationTicks,
                tiebreakOrder: entry.definition.catalogOrder,
                // Heads still cross in engraving-unsupported measures when
                // Virgo preserves note identity; the flag suppresses their
                // duration-bearing engraving (stems/beams/flags/dots) there.
                isRhythmEngravable: entry.note.rhythm.support == .supported
                    && measuresByIndex[entry.note.position.measureIndex]?
                        .engravingSupport.permitsEngraving == true,
                articulation: articulation(for: entry.note)
            )
        }
    }

    /// The resolved open-hi-hat intent: lane-variant resolution already picks
    /// `.openHiHat`; the package carries the matching articulation or none.
    private static func articulation(for note: RhythmLayoutNote) -> PercussionArticulation? {
        DrumNotationCatalog.resolve(
            noteType: note.noteType,
            sourceLaneID: note.sourceLaneID
        )?.variant == .openHiHat ? .open : nil
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
                isFullMeasure: legacy == .fullMeasure,
                voice: notationVoiceRole(rest.voice),
                durationTicks: rest.durationTicks
            )
        }
    }

    /// Every rest that passes the engine's rest guards in an
    /// engraving-permitting measure, in its candidate sort order (tick
    /// ascending, upper voice first, longer first) — all visibilities.
    /// Rests in engraving-unsupported measures are filtered here: Virgo
    /// suppresses their engraving at composition, so they must not reserve
    /// measured ink in the package. Callers filter `.printed` themselves;
    /// the full candidate set mirrors `buildRests`'s population for tuplet
    /// feel-pair detection.
    private static func restCandidates(
        snapshot: RhythmLayoutSnapshot,
        measuresByIndex: [Int: RhythmMeasure]
    ) -> [RhythmLayoutRest] {
        snapshot.rests.compactMap { rest -> RhythmLayoutRest? in
            guard let measure = measuresByIndex[rest.position.measureIndex],
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

    /// Controls cross only with resolved visual intent: the same target
    /// resolution `buildStopNotes` applies (target lane + staff-position
    /// override), so a control whose target cannot resolve never reaches the
    /// package — mirroring the engine dropping it rather than painting a
    /// mark at a fabricated step.
    private static func resolvedControls(
        snapshot: RhythmLayoutSnapshot,
        measuresByIndex: [Int: RhythmMeasure],
        notePositionOverrides: [DrumType: GameplayLayout.NotePosition]
    ) -> [ResolvedControl] {
        snapshot.controls.compactMap { control -> ResolvedControl? in
            guard let measure = measuresByIndex[control.position.measureIndex],
                control.position.localTick >= 0,
                control.position.localTick < measure.durationTicks,
                control.position.absoluteTick == measure.startTick + control.position.localTick,
                let targetLaneID = control.event.targetLaneID,
                let target = DrumNotationCatalog.resolveTarget(laneID: targetLaneID)
            else { return nil }
            let targetPosition = notePositionOverrides[target.definition.gameplayInstrument]
                ?? target.definition.defaultPosition
            return ResolvedControl(
                id: control.eventID.rawValue,
                position: NotationTickPosition(
                    measureIndex: control.position.measureIndex,
                    localTick: control.position.localTick
                ),
                kind: controlKind(control.event.kind),
                // Same pitch-ascending seam as note staffStep: the app's
                // target step is Y-down, so negate here.
                targetStaffStep: -NotationLayoutEngine.staffStep(for: targetPosition)
            )
        }
    }

    private static func controlKind(_ kind: NotationControlEventKind) -> NotationControlKind {
        switch kind {
        case .stop: return .stop
        case .choke: return .choke
        case .damp: return .damp
        }
    }
}

/// The tuplet arm of the projection, split out so the main enum stays under
/// the SwiftLint type-body limit — the mirror of `buildTuplets`: only
/// already-resolved groups in engraving-permitting measures cross, and
/// declared swing/shuffle feel-pairs stay suppressed at this boundary
/// rather than carrying `RhythmicFeel` into the package.
private enum VirgoNotationTupletProjection {
    /// Resolved tuplet groups keyed by deterministic adapter-local IDs.
    /// `notes` are the mapped note-head candidates; `rests` are the sorted
    /// rest candidates of every visibility (the engine's `buildTuplets`
    /// population); `printedRests` is the subset that crosses the boundary —
    /// its ordinal order is the `ResolvedRest` ID namespace members cite.
    static func resolvedTuplets(
        notes: [(note: RhythmLayoutNote, definition: DrumNotationDefinition)],
        rests: [RhythmLayoutRest],
        printedRests: [RhythmLayoutRest],
        measuresByIndex: [Int: RhythmMeasure],
        feel: RhythmicFeel
    ) -> [ResolvedTupletGroup] {
        var ids = Set(notes.compactMap { $0.note.tupletID })
        ids.formUnion(rests.compactMap(\.tupletID))
        let ordered = ids
            .filter { id in
                measuresByIndex[id.measureIndex]?.engravingSupport.permitsEngraving == true
                    && !isDeclaredFeelPair(
                        id: id,
                        feel: feel,
                        notes: notes,
                        rests: rests,
                        measuresByIndex: measuresByIndex
                    )
            }
            .sorted {
                if $0.measureIndex != $1.measureIndex { return $0.measureIndex < $1.measureIndex }
                if $0.startTick != $1.startTick { return $0.startTick < $1.startTick }
                return $0.stableMemberEventID.rawValue < $1.stableMemberEventID.rawValue
            }
        var groups: [ResolvedTupletGroup] = []
        for id in ordered {
            guard let group = resolvedTuplet(
                packageID: groups.count,
                tupletID: id,
                notes: notes,
                rests: rests,
                printedRests: printedRests
            ) else { continue }
            groups.append(group)
        }
        return groups
    }

    /// One resolved group, or nil when no member or ratio survives — members
    /// cite resolved IDs: note event IDs verbatim and printed-rest ordinals.
    private static func resolvedTuplet(
        packageID: Int,
        tupletID: RhythmTupletID,
        notes: [(note: RhythmLayoutNote, definition: DrumNotationDefinition)],
        rests: [RhythmLayoutRest],
        printedRests: [RhythmLayoutRest]
    ) -> ResolvedTupletGroup? {
        let memberNotes = notes.filter { $0.note.tupletID == tupletID }
        let memberRests = rests.filter { $0.tupletID == tupletID }
        guard let ratio = memberNotes.compactMap({ $0.note.rhythm.tuplet }).first
            ?? memberRests.compactMap({ $0.rhythm.tuplet }).first else { return nil }
        let memberNoteIDs = memberNotes.map { $0.note.eventID.rawValue }.sorted()
        let memberRestIDs = printedRests.enumerated()
            .filter { $0.element.tupletID == tupletID }
            .map(\.offset)
            .sorted()
        guard !memberNoteIDs.isEmpty || !memberRestIDs.isEmpty else { return nil }
        return ResolvedTupletGroup(
            id: packageID,
            measureIndex: tupletID.measureIndex,
            voice: VirgoNotationProjection.notationVoiceRole(tupletID.voice),
            ratio: ResolvedTupletRatio(actual: ratio.actual, normal: ratio.normal),
            memberNoteIDs: memberNoteIDs,
            memberRestIDs: memberRestIDs
        )
    }

    /// The engine's declared feel-pair detection over snapshot-level values:
    /// a swing/shuffle chart where the group covers one whole beat group,
    /// has no rest members, and its notes occupy exactly the long/short
    /// triplet slots.
    private static func isDeclaredFeelPair(
        id: RhythmTupletID,
        feel: RhythmicFeel,
        notes: [(note: RhythmLayoutNote, definition: DrumNotationDefinition)],
        rests: [RhythmLayoutRest],
        measuresByIndex: [Int: RhythmMeasure]
    ) -> Bool {
        guard feel == .swing || feel == .shuffle,
            rests.allSatisfy({ $0.tupletID != id }),
            id.durationTicks > 0,
            id.durationTicks.isMultiple(of: 3),
            let beatGroup = measuresByIndex[id.measureIndex]?.beatGroups
                .first(where: { $0.groupIndex == id.beatGroupIndex }),
            beatGroup.startTick == id.startTick,
            beatGroup.durationTicks == id.durationTicks else { return false }
        let members = notes.filter { $0.note.tupletID == id }.map(\.note)
        let slot = id.durationTicks / 3
        let membersByOnset = Dictionary(grouping: members, by: { $0.position.localTick })
        let occupiedOnsets = membersByOnset.keys.sorted()
        guard occupiedOnsets == [id.startTick, id.startTick + slot * 2],
            members.allSatisfy({ $0.rhythm.tuplet == TupletRatio(actual: 3, normal: 2) }),
            membersByOnset[id.startTick, default: []].allSatisfy({ $0.durationTicks == slot * 2 }),
            membersByOnset[id.startTick + slot * 2, default: []].allSatisfy({ $0.durationTicks == slot })
        else { return false }
        return true
    }
}
