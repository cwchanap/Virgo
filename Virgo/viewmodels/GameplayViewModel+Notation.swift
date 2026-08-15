//
//  GameplayViewModel+Notation.swift
//  Virgo
//
//  Notation layout installation, off-main timeline preparation, and the
//  beat/measure coordinate caches derived from the installed layout.
//  Split from GameplayViewModel+Computations.swift for SwiftLint file limits.
//

import Foundation

extension GameplayViewModel {
    /// Reports the sheet music view's currently available row width. If this changes
    /// the notation layout is rebuilt so measures repack at the new width. Values at
    /// or below the legacy `maxRowWidth` (900) are treated as the floor so behavior
    /// on narrow windows matches the historical layout.
    func updateRowWidth(_ width: CGFloat) {
        guard width.isFinite, width > 0 else { return }
        let resolved = max(GameplayLayout.maxRowWidth, width)
        guard abs(resolved - cachedLayoutRowWidth) > 0.5 else {
            // Width returned to the cached value — cancel any pending stale
            // timer so a previously-scheduled wider/narrower update doesn't
            // fire after the window is already back at the current width.
            rowWidthTimer?.invalidate()
            rowWidthTimer = nil
            return
        }
        scheduleRowWidthUpdate(resolved)
    }

    /// Trailing-edge debounce for row-width changes. During macOS live resize the
    /// width changes every frame; rebuilding the full notation layout each time is
    /// expensive. This mirrors the speed-change debounce pattern: coalesce rapid
    /// width changes and rebuild layout once the user stops resizing.
    private func scheduleRowWidthUpdate(_ width: CGFloat) {
        rowWidthTimer?.invalidate()

        if !isGameplayPrepared {
            cachedLayoutRowWidth = width
            return
        }

        // Apply immediately in tests for deterministic behavior
        if TestEnvironment.isRunningTests {
            cachedLayoutRowWidth = width
            cacheNotationLayout()
            cacheBeatPositions()
            return
        }

        rowWidthTimer = Timer.scheduledTimer(
            withTimeInterval: rowWidthDebounceInterval,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.cachedLayoutRowWidth = width
                self.cacheNotationLayout()
                self.cacheBeatPositions()
            }
        }
    }

    func cacheNotationLayout() {
        guard let track = track else {
            installNotationLayout(.empty)
            cachedNotationNoteHeadPositions = [:]
            cachedMeasureRowMap = [:]
            cachedNotationMeasuresByIndex = [:]
            cachedLegacyContentHeight = 0
            return
        }

        let notePositionOverrides = notationNotePositionOverrides()
        let resolvedRowWidth = max(GameplayLayout.maxRowWidth, cachedLayoutRowWidth)
        let style = NotationLayoutStyle.gameplayDefault.with(rowWidth: resolvedRowWidth)
        let input: NotationLayoutInput
        if let snapshot = cachedRhythmRuntime.layoutSnapshot {
            input = NotationLayoutInput(
                timing: .timeline(snapshot),
                minimumMeasureCount: cachedLayoutMeasureCount,
                style: style,
                notePositionOverrides: notePositionOverrides
            )
        } else {
            input = NotationLayoutInput(
                notes: cachedNotes,
                controlEvents: cachedControlEvents,
                timeSignature: track.timeSignature,
                minimumMeasureCount: cachedLayoutMeasureCount,
                style: style,
                notePositionOverrides: notePositionOverrides
            )
        }
        installNotationLayout(NotationLayoutEngine().layout(input: input))
        if cachedNotationHasRenderableContent {
            cachedMeasureRowMap = Dictionary(
                uniqueKeysWithValues: cachedNotationLayout.measures.map { ($0.measureIndex, $0.row) }
            )
            cachedNotationMeasuresByIndex = Dictionary(
                uniqueKeysWithValues: cachedNotationLayout.measures.map { ($0.measureIndex, $0) }
            )
            cacheNotationMeasurePositionMap()
        } else {
            cachedMeasureRowMap = [:]
            cachedNotationMeasuresByIndex = [:]
        }

        logDroppedNotesIfAny()

        cachedNotationNoteHeadPositions = Dictionary(
            uniqueKeysWithValues: cachedNotationLayout.noteHeadPositionsByID.map { noteHeadID, position in
                (noteHeadID, (x: Double(position.x), y: Double(position.y)))
            }
        )
    }

    /// Builds the immutable timeline-only request while all chart/runtime state
    /// remains on the main actor. The detached worker receives no model values.
    func makeTimelineNotationPreparationRequest() -> GameplayNotationPreparationRequest? {
        guard let snapshot = cachedRhythmRuntime.layoutSnapshot else { return nil }
        let beatPositionsByID: [UInt64: RhythmEventPosition] = Dictionary(
            uniqueKeysWithValues: cachedDrumBeats.compactMap { beat in
                guard let position = beat.rhythmPosition else { return nil }
                return (beat.id, position)
            }
        )
        return GameplayNotationPreparationRequest(
            snapshot: snapshot,
            minimumMeasureCount: cachedLayoutMeasureCount,
            style: .gameplayDefault.with(
                rowWidth: max(GameplayLayout.maxRowWidth, cachedLayoutRowWidth)
            ),
            notePositionOverrides: notationNotePositionOverrides(),
            beatPositionsByID: beatPositionsByID
        )
    }

    /// Runs only the pure timeline request off-main and returns to this main
    /// actor for one generation-checked coherent install. The cancellation
    /// handler captures the worker directly so caller-task cancellation (e.g.
    /// the view disappearing) propagates to the detached worker — abandoned
    /// preparations stop cooperatively instead of burning CPU to completion.
    /// The worker handle is only cleared when this worker is still current
    /// (generation matches), so a newer preparation's worker is never clobbered
    /// by a stale completion.
    func prepareTimelineNotation(
        _ request: GameplayNotationPreparationRequest,
        generation: UInt64
    ) async {
        let worker = Task.detached(priority: .userInitiated) {
            GameplayNotationPreparer.prepare(request)
        }
        notationPreparationWorkerTask = worker
        await withTaskCancellationHandler {
            let prepared = await worker.value
            // Only clear the handle if this worker is still current — a newer
            // preparation may have supplanted it while we were suspended.
            if notationLayoutGeneration == generation {
                notationPreparationWorkerTask = nil
            }
            guard !Task.isCancelled, !worker.isCancelled else { return }
            _ = applyPreparedNotation(prepared, generation: generation)
        } onCancel: {
            // Capture the worker directly so cancellation always targets this
            // worker, never a newer one that may have replaced it on the main
            // actor while the handler fires.
            worker.cancel()
        }
    }

    /// Applies one prepared timeline result through the existing notation
    /// installation funnel. A stale result changes no cache or readiness state.
    @discardableResult
    func applyPreparedNotation(
        _ prepared: GameplayNotationPreparedState,
        generation: UInt64
    ) -> Bool {
        guard generation == notationLayoutGeneration else { return false }
        guard installNotationLayout(prepared.layout, generation: generation) else { return false }

        if cachedNotationHasRenderableContent {
            cachedMeasureRowMap = Dictionary(
                uniqueKeysWithValues: cachedNotationLayout.measures.map { ($0.measureIndex, $0.row) }
            )
            cachedNotationMeasuresByIndex = Dictionary(
                uniqueKeysWithValues: cachedNotationLayout.measures.map { ($0.measureIndex, $0) }
            )
            cacheNotationMeasurePositionMap()
        } else {
            cachedMeasureRowMap = [:]
            cachedNotationMeasuresByIndex = [:]
        }

        logDroppedNotesIfAny()
        cachedNotationNoteHeadPositions = Dictionary(
            uniqueKeysWithValues: cachedNotationLayout.noteHeadPositionsByID.map { noteHeadID, position in
                (noteHeadID, (x: Double(position.x), y: Double(position.y)))
            }
        )
        cachedBeatPositions = Dictionary(
            uniqueKeysWithValues: prepared.beatPositionsByID.map { beatID, position in
                (beatID, (x: Double(position.x), y: Double(position.y)))
            }
        )
        isGameplayPrepared = true
        return true
    }

    /// Use default positions in tests so notation remains deterministic across
    /// contributor machines; production reads the persisted override map here.
    private func notationNotePositionOverrides() -> [DrumType: GameplayLayout.NotePosition] {
        if TestEnvironment.isRunningTests {
            return Dictionary(uniqueKeysWithValues: DrumType.allCases.map { ($0, $0.notePosition) })
        }
        return DrumNotationSettingsManager.loadPositions()
    }

    /// Rebuilds `measurePositionMap` from the current notation layout's measures.
    /// Extracted from `cacheNotationLayout()` to keep it under the function-body-length limit.
    private func cacheNotationMeasurePositionMap() {
        measurePositionMap = Dictionary(
            uniqueKeysWithValues: cachedNotationLayout.measures.map { measure in
                (
                    measure.measureIndex,
                    GameplayLayout.MeasurePosition(
                        row: measure.row,
                        xOffset: measure.xOffset,
                        measureIndex: measure.measureIndex
                    )
                )
            }
        )
    }

    /// Logs a diagnostic when the notation layout engine drops notes (i.e. the
    /// rendered note-head count is lower than the cached note count). Extracted
    /// from `cacheNotationLayout()` to keep it under the function-body-length limit.
    private func logDroppedNotesIfAny() {
        if cachedRhythmRuntime.availability == .valid {
            logDroppedTimelineNotesIfAny()
        } else {
            logDroppedLegacyNotesIfAny()
        }
    }

    private func logDroppedTimelineNotesIfAny() {
        let renderedEventIDs = Set(cachedNotationLayout.noteHeads.compactMap(\.eventID))
        let droppedEventIDs = cachedRhythmRuntime.noteByEventID.keys
            .filter { !renderedEventIDs.contains($0) }
            .sorted { $0.rawValue < $1.rawValue }
        guard !droppedEventIDs.isEmpty else { return }

        let droppedReasons = droppedEventIDs.prefix(5).map { eventID in
            guard let note = cachedRhythmRuntime.noteByEventID[eventID] else {
                return "eventID=\(eventID.rawValue)"
            }
            return droppedNoteMetadata(note, eventID: eventID)
        }
        Logger.warning(
            "Layout engine dropped \(droppedEventIDs.count) timeline note(s): "
                + droppedReasons.joined(separator: "; ")
                + (droppedEventIDs.count > 5 ? " … and \(droppedEventIDs.count - 5) more" : "")
        )
    }

    private func logDroppedLegacyNotesIfAny() {
        let droppedCount = cachedNotes.count - cachedNotationLayout.noteHeads.count
        guard droppedCount > 0 else { return }
        let representativeNotes = cachedNotes.prefix(min(5, droppedCount))
        let droppedReasons = representativeNotes.map { droppedNoteMetadata($0) }
        Logger.warning(
            "Layout engine dropped \(droppedCount) legacy note(s); exact model identity unavailable: "
                + droppedReasons.joined(separator: "; ")
                + (droppedCount > 5 ? " … and \(droppedCount - 5) more" : "")
        )
    }

    private func droppedNoteMetadata(_ note: Note, eventID: RhythmEventID? = nil) -> String {
        let eventPrefix = eventID.map { "eventID=\($0.rawValue), " } ?? ""
        let drumType = DrumType.from(noteType: note.noteType)
        let measureIdx = MeasureUtils.measureIndex(from: MeasureUtils.timePosition(
            measureNumber: note.measureNumber, measureOffset: note.measureOffset
        ))
        return eventPrefix + "noteType=\(note.noteType)(\(drumType?.description ?? "unknown")), " +
            "measure=\(note.measureNumber)(idx=\(measureIdx))"
    }

    func cacheBeatPositions() {
        guard let track = track else { return }

        cachedBeatPositions = [:]

        if cachedNotationHasPlayableContent {
            cacheNotationBeatPositions(track: track)
        } else if !cachedNotationHasRenderableContent {
            cacheLegacyBeatPositions(track: track)
        }

        Logger.debug("Cached \(cachedBeatPositions.count) beat positions for performance optimization")
    }

    private func cacheNotationBeatPositions(track: DrumTrack) {
        if cachedRhythmRuntime.availability == .valid {
            cacheTimelineNotationBeatPositions()
            return
        }
        for beat in cachedDrumBeats {
            let measureIndex = MeasureUtils.measureIndex(from: beat.timePosition)
            guard let measure = cachedNotationMeasuresByIndex[measureIndex] else { continue }
            let beatOffsetInMeasure = beat.timePosition - Double(measureIndex)
            let beatWithinMeasure = beatOffsetInMeasure * Double(track.timeSignature.beatsPerMeasure)
            let tick = cachedNotationLayout.tabGrid.tickIndex(
                forBeatWithinMeasure: beatWithinMeasure,
                beatsPerMeasure: track.timeSignature.beatsPerMeasure
            )
            let beatX = cachedNotationLayout.tabGrid.xPosition(in: measure, tickIndex: tick)
            let staffCenterY = GameplayLayout.StaffLinePosition.line3.absoluteY(for: measure.row)
            cachedBeatPositions[beat.id] = (x: Double(beatX), y: Double(staffCenterY))
        }
    }

    private func cacheTimelineNotationBeatPositions() {
        for beat in cachedDrumBeats {
            guard let position = beat.rhythmPosition,
                  let measure = cachedNotationMeasuresByIndex[position.measureIndex] else {
                continue
            }
            let beatX = cachedNotationLayout.tabGrid.xPosition(in: measure, localTick: position.localTick)
            let staffCenterY = GameplayLayout.StaffLinePosition.line3.absoluteY(for: measure.row)
            cachedBeatPositions[beat.id] = (x: Double(beatX), y: Double(staffCenterY))
        }
    }

    private func cacheLegacyBeatPositions(track: DrumTrack) {
        for beat in cachedDrumBeats {
            let measureIndex = MeasureUtils.measureIndex(from: beat.timePosition)

            if let measurePos = measurePositionMap[measureIndex] {
                let beatOffsetInMeasure = beat.timePosition - Double(measureIndex)
                let beatPosition = beatOffsetInMeasure * Double(track.timeSignature.beatsPerMeasure)
                let beatX = GameplayLayout.preciseNoteXPosition(
                    measurePosition: measurePos,
                    beatPosition: beatPosition,
                    timeSignature: track.timeSignature
                )
                let staffCenterY = GameplayLayout.StaffLinePosition.line3.absoluteY(for: measurePos.row)
                cachedBeatPositions[beat.id] = (x: Double(beatX), y: Double(staffCenterY))
            }
        }
    }
}
