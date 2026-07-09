//
//  GameplayViewModel+VisualUpdates.swift
//  Virgo
//

import Foundation

extension GameplayViewModel {
    // MARK: - Visual Updates

    /// Starts a ~30 Hz timer that continuously updates playback progress, row
    /// scrolling, and beat-boundary playhead movement between metronome callbacks.
    /// The purple playhead itself is quantized to beat boundaries to avoid
    /// forcing sheet re-layout on every timer tick.
    /// Skipped in test environments to avoid interfering with the test runner's
    /// main run loop (matches the pattern used by audio components).
    func startVisualTickTimer() { // internal for cross-file extension access
        guard !TestEnvironment.isRunningTests else { return }
        playbackTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateContinuousVisualsTick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        playbackTimer = timer
    }

    func updateVisualElementsFromMetronome() {
        guard let track = track, isPlaying else { return }

        // Guard: Ensure track duration is initialized to prevent division by zero
        guard cachedTrackDuration > 0 else {
            Logger.debug("⚠️ Skipping visual update: cachedTrackDuration not initialized yet")
            return
        }

        guard let elapsedTime = calculateElapsedTime() else { return }

        updateContinuousVisuals(elapsedTime: elapsedTime, track: track)
    }

    /// Called by the continuous visual tick timer (~30 Hz) so progress and row
    /// scrolling stay responsive between metronome callbacks.
    private func updateContinuousVisualsTick() {
        guard let track = track, isPlaying else { return }
        guard cachedTrackDuration > 0 else { return }
        guard let elapsedTime = calculateElapsedTime() else { return }
        updateContinuousVisuals(elapsedTime: elapsedTime, track: track)
    }

    /// Test seam that drives the continuous-visual update path with a synthetic
    /// elapsed time, bypassing the live metronome clock. Used by unit tests to
    /// verify state that is normally only reached via the 30 Hz tick timer.
    func updateContinuousVisualsForTesting(elapsedTime: Double) {
        guard let track = track else { return }
        updateContinuousVisuals(elapsedTime: elapsedTime, track: track)
    }

    /// Shared logic for both the metronome callback and the continuous tick timer.
    private func updateContinuousVisuals(elapsedTime: Double, track: DrumTrack) {
        // Use effective BPM for visual sync (speed-adjusted)
        let secondsPerBeat = 60.0 / effectiveBPM()
        let totalBeatsElapsedFloat = elapsedTime / secondsPerBeat
        let discreteTotalBeats = Int(totalBeatsElapsedFloat)

        // Continuous playhead position drives missed-note scanning and row scrolling.
        let beatsPerMeasure = track.timeSignature.beatsPerMeasure
        let continuousMeasureFraction = max(0, totalBeatsElapsedFloat / Double(beatsPerMeasure))
        let continuousMeasureIdx = Int(continuousMeasureFraction)
        let continuousOffset = continuousMeasureFraction - Double(continuousMeasureIdx)
        let playheadTimePosition = Double(continuousMeasureIdx) + continuousOffset

        // Purple-bar math is checked on every tick, but the visible position is
        // quantized to beat boundaries and only assigned when it changes.
        updatePurpleBarPosition(elapsedTime: elapsedTime)

        // Track which row the playhead is on so the view can auto-scroll. Only
        // assign on change to avoid spurious observer churn at 30 Hz.
        let newRow = rowForMeasure(continuousMeasureIdx)
        if newRow != currentRow {
            currentRow = newRow
        }

        updatePlaybackProgress(elapsedTime: elapsedTime)

        if discreteTotalBeats != lastDiscreteBeat {
            lastDiscreteBeat = discreteTotalBeats

            let measureIndex = discreteTotalBeats / beatsPerMeasure
            let beatWithinMeasure = discreteTotalBeats % beatsPerMeasure
            let beatPosition = Double(beatWithinMeasure) / Double(beatsPerMeasure)

            currentMeasureIndex = measureIndex
            currentBeatPosition = beatPosition
            currentBeat = findClosestBeatIndex(measureIndex: measureIndex, beatPosition: beatPosition)
            totalBeatsElapsed = discreteTotalBeats

            scanForMissedNotes(upToTimePosition: playheadTimePosition)

            // Schedule delayed completion to preserve late-tolerance window for final notes.
            // Without this, notes near the end get instantly marked as missed before a
            // late-but-valid hit (within ±100ms) can be scored.
            if playbackProgress >= 1.0 && !completionScheduled {
                completionScheduled = true
                let gracePeriodSeconds = TimingAccuracy.good.toleranceMs / 1000.0
                completionTask = completionScheduler(gracePeriodSeconds) { [weak self] in
                    // Grace period elapsed — mark any still-unscored notes missed,
                    // then finalize the session.
                    self?.scanForMissedNotes(upToTimePosition: .infinity)
                    self?.handlePlaybackCompletion()
                }
            }
        }
    }

    func updatePurpleBarPosition(elapsedTime: Double? = nil) {
        let newPosition = calculatePurpleBarPosition(elapsedTime: elapsedTime)
        guard !isSamePurpleBarPosition(purpleBarPosition, newPosition) else { return }
        purpleBarPosition = newPosition
    }

    private func isSamePurpleBarPosition(
        _ lhs: (x: Double, y: Double)?,
        _ rhs: (x: Double, y: Double)?
    ) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none):
            return true
        case let (.some(lhs), .some(rhs)):
            return abs(lhs.x - rhs.x) < 0.0001 && abs(lhs.y - rhs.y) < 0.0001
        default:
            return false
        }
    }

    /// Resolves the staff row that contains the given measure index, branching on
    /// whether the notation layout or the legacy beat layout is active. Out-of-range
    /// indices clamp to the last valid measure so the cursor stays on the final row
    /// after the song ends instead of snapping back to row 0.
    func rowForMeasure(_ measureIndex: Int) -> Int {
        let isNotationLayoutActive = !cachedNotationLayout.noteHeads.isEmpty
        if isNotationLayoutActive {
            guard !cachedNotationLayout.measures.isEmpty else { return 0 }
            let clamped = min(max(measureIndex, 0), cachedNotationLayout.measures.count - 1)
            return cachedMeasureRowMap[clamped] ?? 0
        }
        if let pos = measurePositionMap[measureIndex] {
            return pos.row
        }
        // Out-of-range (typically after song end): use the last known row.
        let maxIndex = measurePositionMap.keys.max() ?? 0
        return measurePositionMap[maxIndex]?.row ?? 0
    }

    func calculatePurpleBarPosition(elapsedTime providedElapsedTime: Double? = nil) -> (x: Double, y: Double)? {
        guard let track = track, isPlaying else { return nil }
        let elapsedTime: Double
        if let providedElapsedTime {
            elapsedTime = providedElapsedTime
        } else {
            guard let calculatedElapsedTime = calculateElapsedTime() else { return nil }
            elapsedTime = calculatedElapsedTime
        }

        let secondsPerBeat = 60.0 / effectiveBPM()
        let beatsPerMeasure = track.timeSignature.beatsPerMeasure
        let totalBeatsElapsed = quantizedPurpleBarBeatBoundaryBeats(elapsedTime / secondsPerBeat)
        let continuousMeasureFraction = max(0, totalBeatsElapsed / Double(beatsPerMeasure))
        let measureIndex = Int(continuousMeasureFraction)
        let beatWithinMeasure = totalBeatsElapsed - Double(measureIndex * beatsPerMeasure)

        let isNotationLayoutActive = !cachedNotationLayout.noteHeads.isEmpty
        // Clamp measureIndex to valid range for notation layout lookup.
        // Also clamp beatWithinMeasure so the purple bar stays at the end
        // of the final measure instead of jumping back to beat 0.
        var clampedMeasureIndex = measureIndex
        var clampedBeatWithinMeasure = beatWithinMeasure
        if isNotationLayoutActive && measureIndex >= cachedNotationLayout.measures.count {
            clampedMeasureIndex = cachedNotationLayout.measures.count - 1
            clampedBeatWithinMeasure = Double(beatsPerMeasure)
        }
        if let notationPosition = calculateNotationPurpleBarPosition(
            measureIndex: clampedMeasureIndex,
            beatWithinMeasure: clampedBeatWithinMeasure
        ) {
            return notationPosition
        }
        if isNotationLayoutActive {
            return nil
        }

        let clampedIndex = measurePositionMap[measureIndex] != nil
            ? measureIndex
            : (measurePositionMap.keys.max() ?? 0)
        guard let measurePos = measurePositionMap[clampedIndex] else { return nil }
        let indicatorX = GameplayLayout.preciseNoteXPosition(
            measurePosition: measurePos,
            beatPosition: beatWithinMeasure,
            timeSignature: track.timeSignature
        )
        let staffCenterY = GameplayLayout.StaffLinePosition.line3.absoluteY(for: measurePos.row)

        return (x: Double(indicatorX), y: Double(staffCenterY))
    }

    private func quantizedPurpleBarBeatBoundaryBeats(_ totalBeats: Double) -> Double {
        guard totalBeats.isFinite else { return 0 }
        let clampedBeats = max(0, totalBeats)
        return floor(clampedBeats + 0.000_000_001)
    }

    private func updatePlaybackProgress(elapsedTime: Double) {
        let nextProgress = min(elapsedTime / cachedTrackDuration, 1.0)
        let shouldPublish: Bool
        if let lastElapsed = lastPlaybackProgressPublishElapsedTime {
            shouldPublish = elapsedTime < lastElapsed
                || elapsedTime - lastElapsed >= playbackProgressPublishInterval
                || nextProgress >= 1.0
        } else {
            shouldPublish = true
        }

        guard shouldPublish else { return }
        lastPlaybackProgressPublishElapsedTime = elapsedTime
        playbackProgress = nextProgress
    }

    func calculateNotationPurpleBarPosition(
        measureIndex: Int,
        beatWithinMeasure: Double
    ) -> (x: Double, y: Double)? {
        guard let track = track, !cachedNotationLayout.noteHeads.isEmpty else { return nil }
        guard let measure = cachedNotationMeasuresByIndex[measureIndex] else {
            return nil
        }

        let tickIndex = cachedNotationLayout.tabGrid.tickIndex(
            forBeatWithinMeasure: beatWithinMeasure,
            beatsPerMeasure: track.timeSignature.beatsPerMeasure
        )
        let indicatorX = cachedNotationLayout.tabGrid.xPosition(in: measure, tickIndex: tickIndex)
        let staffCenterY = GameplayLayout.StaffLinePosition.line3.absoluteY(for: measure.row)

        return (x: Double(indicatorX), y: Double(staffCenterY))
    }

    func calculateElapsedTime() -> Double? {
        if let bgmElapsedTime = currentBGMPlaybackElapsedTime() {
            return bgmElapsedTime
        }
        if let metronomeTime = metronome.getCurrentPlaybackTime() {
            return pausedElapsedTime + metronomeTime
        } else if isPlaying, let startTime = playbackStartTime {
            // playbackStartTime is backdated by pausedElapsedTime (e.g. scheduledStart - pausedElapsedTime),
            // so the raw interval already includes the pause offset. Do NOT add pausedElapsedTime again.
            // Clamp to zero: before a scheduled start, the interval can be slightly negative.
            return max(0, Date().timeIntervalSince(startTime))
        }
        return nil
    }

    func currentBGMPlaybackElapsedTime() -> Double? { // internal for cross-file extension access
        guard isPlaying, let bgmPlayer = bgmPlayer, bgmPlayer.currentTime > 0 else {
            return nil
        }
        return bgmTimelineElapsedTime(for: bgmPlayer.currentTime)
    }

    func findClosestBeatIndex(measureIndex: Int, beatPosition: Double) -> Int {
        guard !cachedDrumBeats.isEmpty else { return 0 }

        var left = 0
        var right = cachedDrumBeats.count - 1
        var result = 0

        while left <= right {
            let mid = (left + right) / 2
            let currentTimePosition = Double(measureIndex) + beatPosition
            if cachedDrumBeats[mid].timePosition <= currentTimePosition {
                result = mid
                left = mid + 1
            } else {
                right = mid - 1
            }
        }
        return result
    }

    func handlePlaybackCompletion() {
        isPlaying = false
        metronome.stop()
        inputManager.stopListening()
        playbackTimer?.invalidate()
        playbackTimer = nil
        // Capture final score and snapshot scoreEngine before reset clears them
        let finalScore = scoreEngine.score
        let finalSnapshot = LiveScoreSnapshot(scoreEngine: scoreEngine)
        let recordResult = scorePersistence.recordAttempt(
            finalSnapshot,
            for: chart,
            atFullSpeed: sessionAtFullSpeed,
            speedMultiplier: lastAppliedSpeedMultiplier
        )
        sessionScoreEngine = scoreEngine
        resetPlaybackState()
        playbackStartTime = nil
        pausedElapsedTime = 0.0
        bgmPlayer?.stop()
        // Set session result after reset
        sessionScoreSnapshot = finalSnapshot
        sessionRecordResult = recordResult
        isShowingSessionResults = true
        Logger.audioPlayback(
            "Playback finished. Score: \(finalScore)\(recordResult == .newBest ? " (new high score!)" : "")"
        )
    }
}
