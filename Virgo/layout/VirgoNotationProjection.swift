import CoreGraphics
import DrumNotation

/// The app-to-package projection: the single app-site style mappers and the
/// snapshot→`ResolvedNotationInput` projection. Split from
/// `VirgoNotationAdapter`, which remains the primitive-mapper owner. HPA-166
/// Task 7 makes `NotationEngraver` the sole production geometry route — the
/// package now derives stem/beam/flag topology internally, so the app
/// pre-format flag classification was deleted with the legacy renderer.
enum VirgoNotationProjection {
    /// The single app-site style mapper for measured formatting (HPA-164 Task
    /// 4): resolved row width with the app's 900pt floor as the wrap budget,
    /// plus the exact default values pinned in Task 1. The sheet-width floor
    /// stays the fixed `maxRowWidth` — on wide windows the budget widens but
    /// a sparse sheet's staff lines must not stretch to it. No other app
    /// site may construct `NotationFormattingStyle`.
    static func formattingStyle(
        rowWidth: CGFloat,
        style: NotationLayoutStyle
    ) -> NotationFormattingStyle {
        NotationFormattingStyle(
            availableRowWidth: max(GameplayLayout.maxRowWidth, rowWidth),
            minimumSheetWidth: GameplayLayout.maxRowWidth,
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

    /// The single app-site mapper from `NotationLayoutStyle` to the package
    /// `NotationEngravingStyle` (HPA-166 Task 7): `formatting` routes through
    /// ``formattingStyle(rowWidth:style:)`` and every engraving scalar is
    /// spelled out explicitly so this seam fails loudly if either side's
    /// values ever drift. No other app site may construct
    /// `NotationEngravingStyle`.
    static func engravingStyle(for style: NotationLayoutStyle) -> NotationEngravingStyle {
        NotationEngravingStyle(
            formatting: formattingStyle(rowWidth: style.rowWidth, style: style),
            rowHeight: GameplayLayout.rowHeight,
            rowVerticalSpacing: GameplayLayout.rowVerticalSpacing,
            stemLength: style.stemLength,
            minimumStemExtensionPastChord: style.minimumStemExtensionPastChord,
            beamThickness: style.beamThickness,
            beamLevelSpacing: style.beamLevelSpacing,
            beamHookLength: style.beamHookLength,
            flagVerticalSpacing: GameplayLayout.flagVerticalSpacing,
            ledgerLineOverhang: style.ledgerLineOverhang,
            upperVoiceRestOffset: style.upperVoiceRestOffset,
            lowerVoiceRestOffset: style.lowerVoiceRestOffset,
            stopMarkSize: style.stopMarkSize,
            stopMarkStrokeWidth: style.stopMarkStrokeWidth,
            stopMarkVerticalOffset: style.stopMarkVerticalOffset,
            articulationVerticalOffset: style.articulationVerticalOffset,
            tupletLineWidth: style.tupletLineWidth,
            tupletLabelSize: style.tupletLabelSize,
            tupletVerticalOffset: style.tupletVerticalOffset,
            tupletHookLength: style.tupletHookLength,
            barLineWidth: GameplayLayout.barLineWidth,
            doubleBarThinWidth: GameplayLayout.doubleBarLineWidths.thin,
            doubleBarThickWidth: GameplayLayout.doubleBarLineWidths.thick,
            doubleBarSpacing: GameplayLayout.doubleBarLineSpacing,
            clefWidth: GameplayLayout.clefWidth,
            meterWidth: GameplayLayout.timeSignatureWidth
        )
    }

    /// The rendered staff step for a `GameplayLayout.NotePosition` — Y-down
    /// half-spaces below line 1. Package consumers negate at the seam (the
    /// package orders steps pitch-ascending).
    static func staffStep(for position: GameplayLayout.NotePosition) -> Int {
        Int((position.yOffset / (GameplayLayout.staffLineSpacing / 2)).rounded())
    }

    /// Projects the snapshot into package formatter input (HPA-164 Task 4).
    /// Trailing-measure expansion must already have happened; the package
    /// receives the complete requested measure list and synthesizes no app
    /// timing policy. Hidden rests are filtered here (the package has no
    /// hidden-rest state), and notes/rests/controls that would fall outside
    /// their measure are dropped by the projection guards below — this is
    /// the only filter between the snapshot and the package boundary.
    static func resolvedNotation(
        snapshot: RhythmLayoutSnapshot,
        expandedMeasures: [RhythmMeasure],
        notePositionOverrides: [DrumType: GameplayLayout.NotePosition]
    ) throws -> ResolvedNotationInput {
        let measuresByIndex = Dictionary(
            expandedMeasures.map { ($0.measureIndex, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let notes = mappedNotes(snapshot: snapshot, measuresByIndex: measuresByIndex)
        // One sort feeds both boundary consumers: the printed subset crosses
        // as `ResolvedRest`s (its ordinal order is the adapter-local rest ID
        // namespace), while the full candidate set — every visibility — feeds
        // tuplet feel-pair detection.
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
                staffStep: -Self.staffStep(for: position),
                noteheadStyle: VirgoNotationAdapter.noteheadStyle(for: entry.note.noteType),
                duration: VirgoNotationAdapter.duration(for: entry.note.rhythm.baseInterval),
                dotCount: entry.note.rhythm.dotCount,
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

    /// Snapshot notes that pass the projection's catalog-resolution and
    /// measure-containment guards before becoming resolved notes, paired
    /// with their catalog definitions.
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
                note.position.absoluteTick == measure.startTick + note.position.localTick,
                // Same duration/span guards rests get: a malformed note drops
                // here rather than failing the whole chart inside the package's
                // ResolvedNotation validation. Subtraction keeps the span check
                // non-trapping for extreme `durationTicks` — the bounds checks
                // above pin `localTick` to [0, durationTicks), so the
                // difference cannot overflow.
                note.durationTicks > 0,
                note.durationTicks <= measure.durationTicks - note.position.localTick
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
    /// sort order below.
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

    /// Every rest that passes the projection's rest guards in an
    /// engraving-permitting measure, in its candidate sort order (tick
    /// ascending, upper voice first, longer first) — all visibilities.
    /// Rests in engraving-unsupported measures are filtered here: Virgo
    /// suppresses their engraving at composition, so they must not reserve
    /// measured ink in the package. Callers filter `.printed` themselves;
    /// the full candidate set feeds the tuplet projection's feel-pair
    /// detection below.
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
                // Same non-trapping subtraction form as the note guard.
                rest.durationTicks <= measure.durationTicks - rest.position.localTick
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

    /// Controls cross only with resolved visual intent: the projection
    /// resolves the target itself (target lane + staff-position override),
    /// so a control whose target cannot resolve never reaches the package —
    /// it is dropped here rather than painted at a fabricated step.
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
                targetStaffStep: -Self.staffStep(for: targetPosition)
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

/// Duration mapping for timeline rests, shared with the adapter projection.
/// A measure-filling rest renders as a full-measure rest.
func legacyRestDuration(
    rhythm: NotationRhythm,
    fillsMeasure: Bool
) -> NotationRestDuration {
    if fillsMeasure { return .fullMeasure }
    switch rhythm.baseInterval {
    case .full: return .fullMeasure
    case .half: return .half
    case .quarter: return .quarter
    case .eighth: return .eighth
    case .sixteenth: return .sixteenth
    case .thirtysecond: return .thirtySecond
    case .sixtyfourth: return .sixtyFourth
    }
}

/// The tuplet arm of the projection, split out so the main enum stays under
/// the SwiftLint type-body limit: only already-resolved groups in
/// engraving-permitting measures cross, and declared swing/shuffle
/// feel-pairs stay suppressed at this boundary rather than carrying
/// `RhythmicFeel` into the package.
private enum VirgoNotationTupletProjection {
    /// Resolved tuplet groups keyed by deterministic adapter-local IDs.
    /// `notes` are the mapped note-head candidates; `rests` are the sorted
    /// rest candidates of every visibility (`restCandidates`' full set);
    /// `printedRests` is the subset that crosses the boundary —
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

    /// The projection's declared feel-pair detection over snapshot-level values:
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
