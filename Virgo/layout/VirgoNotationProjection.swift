import CoreGraphics
import DrumNotation

/// Fail-closed projection: malformed snapshot events abort
/// `resolvedNotation` so `GameplayNotationPreparer.prepare` reports
/// `.failed` instead of silently installing a sheet that dropped them.
/// Composition-policy filters — hidden rests, rests in
/// engraving-unsupported measures, and controls whose target lane does
/// not resolve — are not errors and stay filtered.
enum VirgoNotationProjectionError: Error, CustomStringConvertible {
    case malformedNote(eventID: RhythmEventID, detail: String)
    case malformedRest(measureIndex: Int, localTick: Int, detail: String)
    case malformedControl(eventID: RhythmEventID, detail: String)
    case malformedMeasure(measureIndex: Int, detail: String)

    var description: String {
        switch self {
        case let .malformedNote(eventID, detail):
            return "malformed note (event \(eventID.rawValue)): \(detail)"
        case let .malformedRest(measureIndex, localTick, detail):
            return "malformed rest (measure \(measureIndex), tick \(localTick)): \(detail)"
        case let .malformedControl(eventID, detail):
            return "malformed control (event \(eventID.rawValue)): \(detail)"
        case let .malformedMeasure(measureIndex, detail):
            return "malformed measure (index \(measureIndex)): \(detail)"
        }
    }
}

/// One snapshot note paired with its single catalog resolution, reused by
/// every later stage: staff position, engraving, tuplet grouping.
struct MappedNotationNote {
    let note: RhythmLayoutNote
    let definition: DrumNotationDefinition
    let variant: DrumNotationVariant?
}

/// The app-to-package projection: the single app-site style mappers and
/// the snapshot→`ResolvedNotationInput` projection. `VirgoNotationAdapter`
/// remains the primitive-mapper owner. `NotationEngraver` is the sole
/// production geometry route — the package derives stem/beam/flag topology
/// internally; the pre-format flag classification left with the legacy
/// renderer.
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
    /// hidden-rest state), and malformed notes/rests/controls fail closed
    /// by throwing — the only silent filters left between the snapshot and
    /// the package boundary are hidden rests, rests in
    /// engraving-unsupported measures, and controls whose target lane does
    /// not resolve in the catalog.
    static func resolvedNotation(
        snapshot: RhythmLayoutSnapshot,
        expandedMeasures: [RhythmMeasure],
        notePositionOverrides: [DrumType: GameplayLayout.NotePosition]
    ) throws -> ResolvedNotationInput {
        let measuresByIndex = Dictionary(
            expandedMeasures.map { ($0.measureIndex, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let notes = try mappedNotes(snapshot: snapshot, measuresByIndex: measuresByIndex)
        // One sort feeds both boundary consumers: the printed subset crosses
        // as `ResolvedRest`s (its ordinal order is the adapter-local rest ID
        // namespace), while the full candidate set — every visibility — feeds
        // tuplet feel-pair detection.
        let candidates = try restCandidates(snapshot: snapshot, measuresByIndex: measuresByIndex)
        let printed = candidates.filter { $0.visibility == .printed }
        return try ResolvedNotationInput(
            ticksPerWholeNote: snapshot.ticksPerWholeNote,
            measures: expandedMeasures.map { measure in
                ResolvedMeasure(
                    index: measure.measureIndex,
                    startTick: measure.startTick,
                    durationTicks: measure.durationTicks,
                    meter: printedMeter(
                        for: measure,
                        ticksPerWholeNote: snapshot.ticksPerWholeNote
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
            controls: try resolvedControls(
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

    /// Overflow-safe `absoluteTick == startTick + localTick`: a pathological
    /// tick sum drops the event instead of trapping — `prepare`'s do/catch
    /// cannot catch an arithmetic trap, and this runs on the detached worker.
    private static func absoluteTickMatches(
        _ absoluteTick: Int,
        measureStartTick: Int,
        localTick: Int
    ) -> Bool {
        let sum = measureStartTick.addingReportingOverflow(localTick)
        return !sum.overflow && absoluteTick == sum.partialValue
    }

    /// The meter a measure PRINTS. `RhythmMeasure.timeSignature` is
    /// chart-wide, so a measure-length ratio can leave a bar shorter than
    /// its nominal signature — a 0.75 bar in 4/4 is three quarter beats.
    /// Derive beats from the actual span at the declared note value; a span
    /// that is not a whole number of those beats keeps the declared meter.
    static func printedMeter(
        for measure: RhythmMeasure,
        ticksPerWholeNote: Int
    ) -> NotationMeter {
        let declared = measure.timeSignature
        guard ticksPerWholeNote > 0, declared.noteValue > 0 else {
            return NotationMeter(beats: declared.beatsPerMeasure, noteValue: declared.noteValue)
        }
        let numerator = measure.durationTicks.multipliedReportingOverflow(
            by: declared.noteValue
        )
        guard !numerator.overflow,
              numerator.partialValue > 0,
              numerator.partialValue.isMultiple(of: ticksPerWholeNote) else {
            return NotationMeter(beats: declared.beatsPerMeasure, noteValue: declared.noteValue)
        }
        let beats = numerator.partialValue / ticksPerWholeNote
        return NotationMeter(beats: beats, noteValue: declared.noteValue)
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
        notes: [MappedNotationNote],
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
                // The resolved open-hi-hat intent: lane-variant resolution
                // already picked `.openHiHat` in `mappedNotes`; the package
                // carries the matching articulation or none.
                articulation: entry.variant == .openHiHat ? .open : nil
            )
        }
    }

    /// Snapshot notes that pass the projection's catalog-resolution and
    /// measure-containment guards before becoming resolved notes, paired
    /// with their catalog definitions and lane variants (one resolve per
    /// note — later stages reuse the tuple instead of re-resolving). A note
    /// that fails any guard is malformed snapshot data and throws — one bad
    /// note must fail the chart visibly, not vanish from the engraved sheet.
    private static func mappedNotes(
        snapshot: RhythmLayoutSnapshot,
        measuresByIndex: [Int: RhythmMeasure]
    ) throws -> [MappedNotationNote] {
        try snapshot.notes.map { note in
            guard let resolved = DrumNotationCatalog.resolve(
                noteType: note.noteType,
                sourceLaneID: note.sourceLaneID
            ) else {
                throw VirgoNotationProjectionError.malformedNote(
                    eventID: note.eventID,
                    detail: "no catalog definition for noteType \(note.noteType), "
                        + "lane \(note.sourceLaneID ?? "nil")"
                )
            }
            let definition = resolved.definition
            guard let measure = measuresByIndex[note.position.measureIndex],
                note.position.localTick >= 0,
                note.position.localTick < measure.durationTicks else {
                throw VirgoNotationProjectionError.malformedNote(
                    eventID: note.eventID,
                    detail: "position (measure \(note.position.measureIndex), "
                        + "tick \(note.position.localTick)) is outside the expanded measures"
                )
            }
            guard absoluteTickMatches(
                note.position.absoluteTick,
                measureStartTick: measure.startTick,
                localTick: note.position.localTick
            ) else {
                throw VirgoNotationProjectionError.malformedNote(
                    eventID: note.eventID,
                    detail: "absoluteTick \(note.position.absoluteTick) does not match "
                        + "measure start \(measure.startTick) + localTick"
                )
            }
            // Same duration/span guards rests get. Subtraction keeps the span
            // check non-trapping for extreme `durationTicks` — the bounds
            // checks above pin `localTick` to [0, durationTicks), so the
            // difference cannot overflow.
            guard note.durationTicks > 0,
                note.durationTicks <= measure.durationTicks - note.position.localTick else {
                throw VirgoNotationProjectionError.malformedNote(
                    eventID: note.eventID,
                    detail: "span \(note.durationTicks) does not stay inside "
                        + "measure \(measure.measureIndex)"
                )
            }
            return MappedNotationNote(note: note, definition: definition, variant: resolved.variant)
        }
    }

    /// The rendered note position for an entry — the single place lane
    /// overrides resolve for the projection.
    static func staffPosition(
        for entry: MappedNotationNote,
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
            return ResolvedRest(
                id: index,
                position: NotationTickPosition(
                    measureIndex: rest.position.measureIndex,
                    localTick: rest.position.localTick
                ),
                // One step to the package duration: a measure-filling rest
                // prints as a whole rest; otherwise the rhythm's base
                // interval maps directly (a whole-interval rest inside a
                // longer measure also prints whole).
                duration: fillsMeasure
                    ? .whole
                    : VirgoNotationAdapter.duration(for: rest.rhythm.baseInterval),
                dotCount: rest.rhythm.dotCount,
                isFullMeasure: fillsMeasure,
                voice: notationVoiceRole(rest.voice),
                durationTicks: rest.durationTicks
            )
        }
    }

    /// Every rest that survives the projection's rest guards in an
    /// engraving-permitting measure, in its candidate sort order (tick
    /// ascending, upper voice first, longer first) — all visibilities.
    /// Rests in engraving-unsupported measures are filtered here: Virgo
    /// suppresses their engraving at composition, so they must not reserve
    /// measured ink in the package. That filter is composition policy, not
    /// malformed data — every other guard failure throws. Callers filter
    /// `.printed` themselves; the full candidate set feeds the tuplet
    /// projection's feel-pair detection below.
    private static func restCandidates(
        snapshot: RhythmLayoutSnapshot,
        measuresByIndex: [Int: RhythmMeasure]
    ) throws -> [RhythmLayoutRest] {
        try snapshot.rests.compactMap { rest -> RhythmLayoutRest? in
            guard let measure = measuresByIndex[rest.position.measureIndex],
                rest.position.localTick >= 0,
                rest.position.localTick < measure.durationTicks else {
                throw VirgoNotationProjectionError.malformedRest(
                    measureIndex: rest.position.measureIndex,
                    localTick: rest.position.localTick,
                    detail: "position is outside the expanded measures"
                )
            }
            guard measure.engravingSupport.permitsEngraving else { return nil }
            guard absoluteTickMatches(
                rest.position.absoluteTick,
                measureStartTick: measure.startTick,
                localTick: rest.position.localTick
            ) else {
                throw VirgoNotationProjectionError.malformedRest(
                    measureIndex: rest.position.measureIndex,
                    localTick: rest.position.localTick,
                    detail: "absoluteTick \(rest.position.absoluteTick) does not match "
                        + "measure start \(measure.startTick) + localTick"
                )
            }
            // Same non-trapping subtraction form as the note guard: the
            // bounds checks above pin `localTick` to [0, durationTicks).
            guard rest.durationTicks > 0,
                rest.durationTicks <= measure.durationTicks - rest.position.localTick else {
                throw VirgoNotationProjectionError.malformedRest(
                    measureIndex: rest.position.measureIndex,
                    localTick: rest.position.localTick,
                    detail: "span \(rest.durationTicks) does not stay inside the measure"
                )
            }
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
    /// and a malformed position or timing throws — it is never painted at a
    /// fabricated step. An unresolvable target lane is composition policy,
    /// not malformed timing: the DTX control design preserves unknown
    /// target IDs in chart data, so the mark drops and the chart stays
    /// playable rather than failing closed.
    private static func resolvedControls(
        snapshot: RhythmLayoutSnapshot,
        measuresByIndex: [Int: RhythmMeasure],
        notePositionOverrides: [DrumType: GameplayLayout.NotePosition]
    ) throws -> [ResolvedControl] {
        try snapshot.controls.compactMap { control -> ResolvedControl? in
            guard let measure = measuresByIndex[control.position.measureIndex],
                control.position.localTick >= 0,
                control.position.localTick < measure.durationTicks else {
                throw VirgoNotationProjectionError.malformedControl(
                    eventID: control.eventID,
                    detail: "position (measure \(control.position.measureIndex), "
                        + "tick \(control.position.localTick)) is outside the expanded measures"
                )
            }
            guard absoluteTickMatches(
                control.position.absoluteTick,
                measureStartTick: measure.startTick,
                localTick: control.position.localTick
            ) else {
                throw VirgoNotationProjectionError.malformedControl(
                    eventID: control.eventID,
                    detail: "absoluteTick \(control.position.absoluteTick) does not match "
                        + "measure start \(measure.startTick) + localTick"
                )
            }
            guard let targetLaneID = control.event.targetLaneID,
                let target = DrumNotationCatalog.resolveTarget(laneID: targetLaneID) else {
                return nil
            }
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

/// The tuplet arm of the projection (split so the main enum stays under
/// the SwiftLint type-body limit): only already-resolved groups in
/// engraving-permitting measures cross, and declared feel-pairs stay
/// suppressed rather than carrying `RhythmicFeel` into the package.
private enum VirgoNotationTupletProjection {
    /// Resolved tuplet groups keyed by deterministic adapter-local IDs;
    /// `printedRests` ordinals are the rest ID namespace members cite.
    /// Members are pre-grouped by tuplet ID in one pass per collection
    /// (not tuplets × notes re-filtering).
    static func resolvedTuplets(
        notes: [MappedNotationNote],
        rests: [RhythmLayoutRest],
        printedRests: [RhythmLayoutRest],
        measuresByIndex: [Int: RhythmMeasure],
        feel: RhythmicFeel
    ) -> [ResolvedTupletGroup] {
        var notesByTupletID: [RhythmTupletID: [MappedNotationNote]] = [:]
        for entry in notes {
            guard let id = entry.note.tupletID else { continue }
            notesByTupletID[id, default: []].append(entry)
        }
        var restsByTupletID: [RhythmTupletID: [RhythmLayoutRest]] = [:]
        for rest in rests {
            guard let id = rest.tupletID else { continue }
            restsByTupletID[id, default: []].append(rest)
        }
        var printedRestOrdinalsByTupletID: [RhythmTupletID: [Int]] = [:]
        for (ordinal, rest) in printedRests.enumerated() {
            guard let id = rest.tupletID else { continue }
            printedRestOrdinalsByTupletID[id, default: []].append(ordinal)
        }
        let ordered = Set(notesByTupletID.keys)
            .union(restsByTupletID.keys)
            .filter { id in
                measuresByIndex[id.measureIndex]?.engravingSupport.permitsEngraving == true
                    && !isDeclaredFeelPair(
                        id: id,
                        feel: feel,
                        memberNotes: notesByTupletID[id] ?? [],
                        hasRestMembers: restsByTupletID[id] != nil,
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
                memberNotes: notesByTupletID[id] ?? [],
                memberRests: restsByTupletID[id] ?? [],
                memberRestOrdinals: printedRestOrdinalsByTupletID[id] ?? []
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
        memberNotes: [MappedNotationNote],
        memberRests: [RhythmLayoutRest],
        memberRestOrdinals: [Int]
    ) -> ResolvedTupletGroup? {
        guard let ratio = memberNotes.compactMap({ $0.note.rhythm.tuplet }).first
            ?? memberRests.compactMap({ $0.rhythm.tuplet }).first else { return nil }
        let memberNoteIDs = memberNotes.map { $0.note.eventID.rawValue }.sorted()
        let memberRestIDs = memberRestOrdinals.sorted()
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

    /// The projection's declared feel-pair detection: a swing/shuffle
    /// chart where the group covers one whole beat group, has no rest
    /// members, and its notes occupy exactly the long/short triplet slots.
    private static func isDeclaredFeelPair(
        id: RhythmTupletID,
        feel: RhythmicFeel,
        memberNotes: [MappedNotationNote],
        hasRestMembers: Bool,
        measuresByIndex: [Int: RhythmMeasure]
    ) -> Bool {
        guard feel == .swing || feel == .shuffle,
            !hasRestMembers,
            id.durationTicks > 0,
            id.durationTicks.isMultiple(of: 3),
            let beatGroup = measuresByIndex[id.measureIndex]?.beatGroups
                .first(where: { $0.groupIndex == id.beatGroupIndex }),
            beatGroup.startTick == id.startTick,
            beatGroup.durationTicks == id.durationTicks else { return false }
        let members = memberNotes.map(\.note)
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
