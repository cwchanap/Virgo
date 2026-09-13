import CoreGraphics
import DrumNotation

/// One resolved flag paint operation, shared by production rendering and the
/// raster probe. Pure data: paint consumers never search sibling flags.
struct FlagPaintCommand: Identifiable, Equatable {
    let id: String
    let center: CGPoint
    let duration: NotationFlagDuration
    let direction: NotationStemDirection
    let staffSpace: CGFloat
    let paintedBounds: CGRect
}

/// The single pure app-to-package mapping seam between Virgo's DTX/notation
/// domain and the `DrumNotation` package. Takes values in, returns values out:
/// no view construction, no rendering, no mutation of layout outputs.
enum VirgoNotationAdapter {
    static func noteheadStyle(for noteType: NoteType) -> PercussionNoteheadStyle {
        switch noteType {
        case .bass, .snare, .highTom, .midTom, .lowTom:
            return .normal
        case .hiHat, .hiHatPedal, .openHiHat, .crash, .ride, .china, .splash:
            return .x
        case .cowbell:
            return .diamond
        }
    }

    static func duration(for interval: NoteInterval) -> NotationDuration {
        switch interval {
        case .full:
            return .whole
        case .half:
            return .half
        case .quarter:
            return .quarter
        case .eighth:
            return .eighth
        case .sixteenth:
            return .sixteenth
        case .thirtysecond:
            return .thirtySecond
        case .sixtyfourth:
            return .sixtyFourth
        }
    }

    /// The flag duration for `interval`, or nil for intervals that never carry
    /// a flag (full/half/quarter).
    static func flagDuration(for interval: NoteInterval) -> NotationFlagDuration? {
        switch interval {
        case .eighth:
            return .eighth
        case .sixteenth:
            return .sixteenth
        case .thirtysecond:
            return .thirtySecond
        case .sixtyfourth:
            return .sixtyFourth
        case .full, .half, .quarter:
            return nil
        }
    }

    static func articulation(for kind: RenderedArticulationKind) -> PercussionArticulation {
        switch kind {
        case .openHiHat:
            return .open
        }
    }

    static func stemDirection(_ direction: StemDirection) -> NotationStemDirection {
        switch direction {
        case .up:
            return .up
        case .down:
            return .down
        }
    }

    static func restDuration(_ duration: NotationRestDuration) -> NotationDuration? {
        switch duration {
        case .fullMeasure:
            return .whole
        case .half:
            return .half
        case .quarter:
            return .quarter
        case .eighth:
            return .eighth
        case .sixteenth:
            return .sixteenth
        case .thirtySecond:
            return .thirtySecond
        case .sixtyFourth:
            return .sixtyFourth
        case .indeterminate:
            return nil
        }
    }

    static func staffSpace(for style: NotationLayoutStyle) -> CGFloat {
        style.staffLineSpacing
    }

    // MARK: - Pre-format projection (HPA-164 Task 4)

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

        let resolvedNotes = notes.map { entry -> ResolvedNote in
            let position = staffPosition(for: entry, overrides: notePositionOverrides)
            return ResolvedNote(
                id: entry.note.eventID.rawValue,
                position: NotationTickPosition(
                    measureIndex: entry.note.position.measureIndex,
                    localTick: entry.note.position.localTick
                ),
                stemDirection: stemDirection(entry.definition.defaultStemDirection),
                // The package orders staff steps pitch-ascending (its pinned
                // VexFlow displacement walks away from the stem side through
                // ascending steps); Virgo's layout staffStep is Y-down, so
                // negate at this seam. Keeps the stem-side head undisplaced.
                staffStep: -NotationLayoutEngine.staffStep(for: position),
                noteheadStyle: noteheadStyle(for: entry.note.noteType),
                duration: duration(for: entry.note.rhythm.baseInterval),
                dotCount: entry.note.rhythm.dotCount,
                visibleFlagDuration: flags[entry.note.eventID.rawValue] ?? nil
            )
        }

        // Deterministic adapter-local rest namespace: rests carry no event ID,
        // so printed rests are sorted in the engine's candidate order and
        // given descending negative IDs — the formatter's lowest-ID-wins rule
        // then prefers the earliest/upper/longest rest of a shared column,
        // matching current rest rendering.
        let printedRests = printedRests(snapshot: snapshot, measuresByIndex: measuresByIndex)
        let resolvedRests = printedRests.enumerated().map { index, rest -> ResolvedRest in
            let measure = measuresByIndex[rest.position.measureIndex]
            let fillsMeasure = rest.position.localTick == 0
                && rest.durationTicks == measure?.durationTicks
            let legacy = legacyRestDuration(rhythm: rest.rhythm, fillsMeasure: fillsMeasure)
            return ResolvedRest(
                id: index - printedRests.count,
                position: NotationTickPosition(
                    measureIndex: rest.position.measureIndex,
                    localTick: rest.position.localTick
                ),
                duration: restDuration(legacy) ?? .quarter,
                dotCount: rest.rhythm.dotCount,
                isFullMeasure: legacy == .fullMeasure
            )
        }

        let resolvedControls = snapshot.controls.compactMap { control -> ResolvedControl? in
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

        return try ResolvedNotationInput(
            ticksPerWholeNote: snapshot.ticksPerWholeNote,
            measures: expandedMeasures.map {
                ResolvedMeasure(
                    index: $0.measureIndex,
                    startTick: $0.startTick,
                    durationTicks: $0.durationTicks
                )
            },
            notes: resolvedNotes,
            rests: resolvedRests,
            controls: resolvedControls
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

        struct GroupKey: Hashable {
            let measureIndex: Int
            let localTick: Int
            let voice: NotationVoice
            let stemDirection: StemDirection
        }
        var grouped: [GroupKey: [(note: RhythmLayoutNote, definition: DrumNotationDefinition)]] = [:]
        for entry in notes {
            grouped[GroupKey(
                measureIndex: entry.note.position.measureIndex,
                localTick: entry.note.position.localTick,
                voice: entry.definition.voice,
                stemDirection: entry.definition.defaultStemDirection
            ), default: []].append(entry)
        }

        // Same event semantics as the engine's timeline
        // `buildTimelineEvents(noteHeads:)`, sorted with the same comparator
        // so topology coverage indices line up.
        let stemGroups: [(entries: [(note: RhythmLayoutNote, definition: DrumNotationDefinition)], event: BeamTimelineEvent)]
            = grouped.values.compactMap { group in
                guard let representative = flagRepresentative(in: group) else { return nil }
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
                return (
                    group,
                    BeamTimelineEvent(
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
                )
            }
            .sorted { lhs, rhs in
                let lhsEvent = lhs.event
                let rhsEvent = rhs.event
                if lhsEvent.timeColumn.measureIndex != rhsEvent.timeColumn.measureIndex {
                    return lhsEvent.timeColumn.measureIndex < rhsEvent.timeColumn.measureIndex
                }
                if lhsEvent.timeColumn.absoluteLayoutTick != rhsEvent.timeColumn.absoluteLayoutTick {
                    return lhsEvent.timeColumn.absoluteLayoutTick < rhsEvent.timeColumn.absoluteLayoutTick
                }
                if lhsEvent.voice.rawValue != rhsEvent.voice.rawValue {
                    return lhsEvent.voice.rawValue < rhsEvent.voice.rawValue
                }
                if lhsEvent.stemDirection.rawValue != rhsEvent.stemDirection.rawValue {
                    return lhsEvent.stemDirection.rawValue < rhsEvent.stemDirection.rawValue
                }
                return lhsEvent.noteHeadIDs.lexicographicallyPrecedes(rhsEvent.noteHeadIDs)
            }

        let topology = NotationBeamTopologyBuilder().build(
            events: stemGroups.map(\.event),
            measures: expandedMeasures
        )

        var classifications: [Int: NotationFlagDuration] = [:]
        for (index, stemGroup) in stemGroups.enumerated() {
            guard case let .beamable(requiredLevels, _) = stemGroup.event.role else { continue }
            // Notes in engraving-unsupported measures never paint flags.
            guard permitsEngraving[stemGroup.event.timeColumn.measureIndex] ?? false else { continue }
            let covered = topology.coveredLevelsByEventIndex[index] ?? []
            let expected = Set(0..<requiredLevels)
            guard let representative = flagRepresentative(in: stemGroup.entries),
                let canonical = flagDuration(for: representative.note.rhythm.baseInterval)
            else { continue }
            let classification = visibleFlagClassification(
                uncovered: expected.subtracting(covered),
                expected: expected,
                canonical: canonical
            )
            guard let classification else { continue }
            for entry in stemGroup.entries {
                classifications[entry.note.eventID.rawValue] = classification
            }
        }
        return classifications
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

    /// Printed rests that pass the engine's rest guards, in its candidate
    /// sort order (tick ascending, upper voice first, longer first).
    private static func printedRests(
        snapshot: RhythmLayoutSnapshot,
        measuresByIndex: [Int: RhythmMeasure]
    ) -> [RhythmLayoutRest] {
        snapshot.rests.compactMap { rest -> RhythmLayoutRest? in
            guard rest.visibility == .printed,
                let measure = measuresByIndex[rest.position.measureIndex],
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

    private static func staffPosition(
        for entry: (note: RhythmLayoutNote, definition: DrumNotationDefinition),
        overrides: [DrumType: GameplayLayout.NotePosition]
    ) -> GameplayLayout.NotePosition {
        overrides[entry.definition.gameplayInstrument] ?? entry.definition.defaultPosition
    }

    /// The single package-metrics lookup for one rendered head: painted bounds
    /// and stem anchor offset in head-local coordinates (Y-down, centered on
    /// ``RenderedNoteHead.position``). Callers translate by `head.position`.
    static func noteheadMetrics(
        for head: RenderedNoteHead,
        style: NotationLayoutStyle
    ) -> NoteheadMetrics {
        PercussionGlyphMetrics.notehead(
            style: noteheadStyle(for: head.noteType),
            duration: duration(for: head.interval),
            stemDirection: stemDirection(head.stemDirection),
            staffSpace: staffSpace(for: style)
        )
    }

    /// Resolves `RenderedFlag`s into package-backed paint commands.
    ///
    /// Policy per head: expected uncovered levels are `0..<head.interval.flagCount`.
    /// When the actual uncovered levels exactly equal that set, emit one command
    /// from level 0 at the head's canonical duration and suppress sibling levels;
    /// otherwise emit one `.eighth` command per existing flag, preserving each
    /// origin. Output order always follows the input `flags` order.
    static func flagPaintCommands(
        flags: [RenderedFlag],
        heads: [RenderedNoteHead],
        style: NotationLayoutStyle
    ) -> [FlagPaintCommand] {
        let headsByID = Dictionary(heads.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var suppressedFlagIDs = Set<String>()
        var canonicalByFlagID: [String: FlagPaintCommand] = [:]

        for (headID, headFlags) in Dictionary(grouping: flags, by: \.noteHeadID) {
            guard let head = headsByID[headID],
                let levelZero = headFlags.first(where: { $0.flagIndex == 0 }),
                let canonicalDuration = flagDuration(for: head.interval),
                Set(headFlags.map(\.flagIndex)) == Set(0..<head.interval.flagCount)
            else { continue }

            for flag in headFlags where flag.flagIndex != 0 {
                suppressedFlagIDs.insert(flag.id)
            }
            canonicalByFlagID[levelZero.id] = makeCommand(
                id: levelZero.id,
                origin: levelZero.origin,
                duration: canonicalDuration,
                direction: stemDirection(levelZero.stemDirection),
                style: style
            )
        }

        return flags.compactMap { flag in
            if let canonical = canonicalByFlagID[flag.id] {
                return canonical
            }
            guard !suppressedFlagIDs.contains(flag.id) else { return nil }
            return makeCommand(
                id: flag.id,
                origin: flag.origin,
                duration: .eighth,
                direction: stemDirection(flag.stemDirection),
                style: style
            )
        }
    }

    /// The maximum distance any flagged member's canonical Bravura flag
    /// reaches back from the stem attachment point toward the noteheads,
    /// measured along the stem. Zero when no member carries a flag
    /// (full/half/quarter). Pure package metrics; no layout policy.
    static func maximumFlagInwardExtent(
        heads: [RenderedNoteHead],
        style: NotationLayoutStyle
    ) -> CGFloat {
        var extent: CGFloat = 0
        for head in heads {
            guard let flagDuration = flagDuration(for: head.interval) else { continue }
            let direction = stemDirection(head.stemDirection)
            let metrics = PercussionGlyphMetrics.flag(
                duration: flagDuration,
                direction: direction,
                staffSpace: staffSpace(for: style)
            )
            let relativeBounds = metrics.paintedBounds.offsetBy(
                dx: -metrics.attachmentOffset.x,
                dy: -metrics.attachmentOffset.y
            )
            let inwardExtent: CGFloat
            switch direction {
            case .up:
                inwardExtent = max(0, relativeBounds.maxY)
            case .down:
                inwardExtent = max(0, -relativeBounds.minY)
            }
            extent = max(extent, inwardExtent)
        }
        return extent
    }

    /// Effective minimum stem length for one unbeamed stem group: the maximum
    /// canonical-flag clearance required by any flagged member, or the default
    /// `style.stemLength` when no member carries a flag (full/half/quarter).
    /// Task 6's `unbeamedStemEndY` passes the heads sharing that stem; the
    /// result replaces the bare `style.stemLength` in its extent arithmetic.
    /// Pure data only: never changes beam grouping or `buildFlags` output.
    static func minimumUnbeamedStemLength(
        heads: [RenderedNoteHead],
        style: NotationLayoutStyle
    ) -> CGFloat {
        max(
            style.stemLength,
            maximumFlagInwardExtent(heads: heads, style: style)
                + style.minimumStemExtensionPastChord
        )
    }

    private static func makeCommand(
        id: String,
        origin: CGPoint,
        duration: NotationFlagDuration,
        direction: NotationStemDirection,
        style: NotationLayoutStyle
    ) -> FlagPaintCommand {
        let staffSpace = staffSpace(for: style)
        let metrics = PercussionGlyphMetrics.flag(
            duration: duration,
            direction: direction,
            staffSpace: staffSpace
        )
        let center = CGPoint(
            x: origin.x - metrics.attachmentOffset.x,
            y: origin.y - metrics.attachmentOffset.y
        )
        return FlagPaintCommand(
            id: id,
            center: center,
            duration: duration,
            direction: direction,
            staffSpace: staffSpace,
            paintedBounds: metrics.paintedBounds.offsetBy(dx: center.x, dy: center.y)
        )
    }
}
