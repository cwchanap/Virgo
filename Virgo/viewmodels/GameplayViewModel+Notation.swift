//
//  GameplayViewModel+Notation.swift
//  Virgo
//
//  Engraved notation installation, off-main timeline preparation, and the
//  measure coordinate caches derived from the installed engraving.
//  Split from GameplayViewModel+Computations.swift for SwiftLint file limits.
//

import Foundation
import DrumNotation

extension GameplayViewModel {
    /// Reports the sheet music view's currently available row width. If this changes
    /// the notation engraving is rebuilt so measures repack at the new width. Values at
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
    /// width changes every frame; rebuilding the full notation engraving each time is
    /// expensive. This mirrors the speed-change debounce pattern: coalesce rapid
    /// width changes and rebuild notation once the user stops resizing.
    private func scheduleRowWidthUpdate(_ width: CGFloat) {
        rowWidthTimer?.invalidate()

        if !isGameplayPrepared {
            cachedLayoutRowWidth = width
            return
        }

        // Apply immediately in tests for deterministic behavior
        if TestEnvironment.isRunningTests {
            cachedLayoutRowWidth = width
            refreshNotationEngraving()
            return
        }

        rowWidthTimer = Timer.scheduledTimer(
            withTimeInterval: rowWidthDebounceInterval,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.cachedLayoutRowWidth = width
                self.refreshNotationEngraving()
            }
        }
    }

    /// The synchronous notation refresh (HPA-166 Task 7): runs the same
    /// `GameplayNotationPreparer.prepare` route as the detached initial
    /// worker, then installs through the single
    /// `installPreparedNotation(_:generation:)` funnel.
    func refreshNotationEngraving() {
        guard track != nil else {
            clearNotationInstallation()
            cachedMeasureRowMap = [:]
            cachedNotationMeasuresByIndex = [:]
            cachedLegacyContentHeight = 0
            return
        }

        if let request = makeTimelineNotationPreparationRequest() {
            installPreparedNotation(GameplayNotationPreparer.prepare(request))
        } else {
            // No timeline snapshot: the engraved route requires one, so the
            // notation clears and playback falls back to the existing
            // non-notation beat UI. `cachedNotes` is never engraved.
            clearNotationInstallation()
        }
        refreshNotationMeasureCaches()
        logDroppedNotesIfAny()
    }

    /// Builds the immutable timeline-only request while all chart/runtime state
    /// remains on the main actor. The detached worker receives no model values.
    func makeTimelineNotationPreparationRequest() -> GameplayNotationPreparationRequest? {
        guard let snapshot = cachedRhythmRuntime.layoutSnapshot else { return nil }
        return GameplayNotationPreparationRequest(
            snapshot: snapshot,
            minimumMeasureCount: cachedLayoutMeasureCount,
            style: .gameplayDefault.with(
                rowWidth: max(GameplayLayout.maxRowWidth, cachedLayoutRowWidth)
            ),
            notePositionOverrides: notationNotePositionOverrides()
        )
    }

    /// Runs only the pure timeline request off-main and returns to this main
    /// actor for one generation-checked coherent install. The cancellation
    /// handler captures the worker directly so caller-task cancellation (e.g.
    /// the view disappearing) propagates to the detached worker. Cancellation
    /// is best-effort resource cleanup only: the dominant work is
    /// `NotationEngraver.engrave`, which has no cooperative cancellation
    /// points, so an abandoned worker may still run to completion. Correctness
    /// rests on the generation checks below — a stale result is discarded
    /// regardless of whether the worker finished or was cancelled.
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

    /// Applies one prepared timeline result through the notation installation
    /// funnel. A stale result changes no cache or readiness state.
    @discardableResult
    func applyPreparedNotation(
        _ prepared: GameplayNotationPreparedState,
        generation: UInt64
    ) -> Bool {
        guard generation == notationLayoutGeneration else { return false }
        guard installPreparedNotation(prepared, generation: generation) else { return false }
        refreshNotationMeasureCaches()
        logDroppedNotesIfAny()
        isGameplayPrepared = true
        return true
    }

    /// Rebuilds the measure→row and measure-by-index lookups from the
    /// installed engraving; clears them when no notation is installed.
    private func refreshNotationMeasureCaches() {
        if cachedNotationHasRenderableContent, let engraving = cachedEngravedNotation {
            cachedMeasureRowMap = Dictionary(
                uniqueKeysWithValues: engraving.measures.map { ($0.index, $0.rowIndex) }
            )
            cachedNotationMeasuresByIndex = Dictionary(
                uniqueKeysWithValues: engraving.measures.map { ($0.index, $0) }
            )
            cacheNotationMeasurePositionMap()
        } else {
            cachedMeasureRowMap = [:]
            cachedNotationMeasuresByIndex = [:]
        }
    }

    /// Use default positions in tests so notation remains deterministic across
    /// contributor machines; production reads the persisted override map here.
    private func notationNotePositionOverrides() -> [DrumType: GameplayLayout.NotePosition] {
        if TestEnvironment.isRunningTests {
            return Dictionary(uniqueKeysWithValues: DrumType.allCases.map { ($0, $0.notePosition) })
        }
        return DrumNotationSettingsManager.loadPositions()
    }

    /// Rebuilds `measurePositionMap` from the installed engraving's measures.
    private func cacheNotationMeasurePositionMap() {
        guard let engraving = cachedEngravedNotation else { return }
        measurePositionMap = Dictionary(
            uniqueKeysWithValues: engraving.measures.map { measure in
                (
                    measure.index,
                    GameplayLayout.MeasurePosition(
                        row: measure.rowIndex,
                        xOffset: measure.xOffset,
                        measureIndex: measure.index
                    )
                )
            }
        )
    }

    /// Logs a diagnostic when the engraving drops notes (i.e. the engraved
    /// note-head count is lower than the timeline's event count).
    /// With no timeline snapshot the notation is intentionally uninstalled
    /// (HPA-164), so no drop diagnostics apply.
    private func logDroppedNotesIfAny() {
        guard cachedRhythmRuntime.availability == .valid else { return }
        logDroppedTimelineNotesIfAny()
    }

    private func logDroppedTimelineNotesIfAny() {
        let renderedEventIDs = Set(cachedEngravedNotation?.noteHeads.map(\.noteID) ?? [])
        let droppedEventIDs = cachedRhythmRuntime.noteByEventID.keys
            .filter { !renderedEventIDs.contains($0.rawValue) }
            .sorted { $0.rawValue < $1.rawValue }
        guard !droppedEventIDs.isEmpty else { return }

        let droppedReasons = droppedEventIDs.prefix(5).map { eventID in
            guard let note = cachedRhythmRuntime.noteByEventID[eventID] else {
                return "eventID=\(eventID.rawValue)"
            }
            return droppedNoteMetadata(note, eventID: eventID)
        }
        Logger.warning(
            "Engraver dropped \(droppedEventIDs.count) timeline note(s): "
                + droppedReasons.joined(separator: "; ")
                + (droppedEventIDs.count > 5 ? " … and \(droppedEventIDs.count - 5) more" : "")
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
}
