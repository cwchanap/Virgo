//
//  GameplayViewModel+Playback.swift
//  Virgo
//

import Foundation

extension GameplayViewModel {
    // MARK: - Playback Control

    func togglePlayback() {
        Logger.audioPlayback("🎮 togglePlayback called - current isPlaying: \(isPlaying)")

        // Guard: Cannot start playback if data not loaded or track not ready
        if !isPlaying {
            guard isDataLoaded else {
                Logger.error("Cannot start playback - data not loaded")
                return
            }
            guard track != nil else {
                Logger.error("Cannot start playback - no track available")
                return
            }
        }

        if isPlaying {
            pausePlayback()
        } else {
            startPlayback()
        }
    }

    func startPlayback() {
        Logger.audioPlayback("🎮 startPlayback() called")

        let isResuming = pausedElapsedTime > 0.0

        inputManager.refreshGameplayConfigurationFromSettingsIfNeeded()

        if shouldGateGameplayOnSelectedMIDISource && !inputManager.hasSelectedMIDISourcePreference {
            midiDeviceAlertMessage = "Select your MIDI device before starting."
            isShowingMIDIDeviceAlert = true
            return
        }

        if shouldGateGameplayOnSelectedMIDISource && !inputManager.isSelectedMIDISourceAvailable {
            midiDeviceAlertMessage = "Reconnect or select your MIDI device before starting."
            isShowingMIDIDeviceAlert = true
            return
        }

        // Guard: Ensure track is ready before starting playback
        guard let track = track else {
            Logger.error("No track available for playback")
            return
        }

        guard isDataLoaded else {
            Logger.error("Data not loaded, cannot start playback")
            return
        }
        guard isGameplayPrepared else {
            Logger.error("Gameplay not prepared, cannot start playback")
            return
        }

        playbackTimer?.invalidate()
        isShowingMIDIDeviceAlert = false
        midiDeviceAlertMessage = ""

        // Check if we're resuming from a pause or starting fresh
        // Use pausedElapsedTime as primary indicator for resume (works for both BGM and metronome-only sessions)
        if isResuming {
            // When resuming, calculate and restore state based on elapsed time
            // For BGM sessions, use BGM position as source of truth
            // For metronome-only sessions, use pausedElapsedTime
            let actualElapsedTime: Double
            if let bgmPlayer = bgmPlayer, bgmPlayer.currentTime > 0 {
                Logger.audioPlayback("🎮 Resuming BGM playback from \(bgmPlayer.currentTime)s")
                // Convert audio time to timeline position (accounting for speed + BGM offset)
                actualElapsedTime = bgmTimelineElapsedTime(for: bgmPlayer.currentTime)
            } else {
                Logger.audioPlayback("🎮 Resuming metronome-only playback from \(pausedElapsedTime)s")
                actualElapsedTime = pausedElapsedTime
            }

            // Use effective BPM for beat calculation during speed-adjusted playback
            let secondsPerBeat = 60.0 / effectiveBPM()
            let elapsedBeats = actualElapsedTime / secondsPerBeat
            let discreteBeats = Int(elapsedBeats)

            // Restore state to match current position
            totalBeatsElapsed = discreteBeats
            let beatWithinMeasure = Double(discreteBeats % track.timeSignature.beatsPerMeasure)
            currentBeatPosition = beatWithinMeasure / Double(track.timeSignature.beatsPerMeasure)
            currentMeasureIndex = discreteBeats / track.timeSignature.beatsPerMeasure

            // Guard against zero duration to prevent division by zero
            if cachedTrackDuration > 0 {
                playbackProgress = actualElapsedTime / cachedTrackDuration
            } else {
                Logger.warning("⚠️ Cannot calculate playback progress: cachedTrackDuration is zero")
                playbackProgress = 0.0
            }

            // Update derived state
            currentBeat = findClosestBeatIndex(measureIndex: currentMeasureIndex, beatPosition: currentBeatPosition)
            lastMetronomeBeat = totalBeatsElapsed
            lastDiscreteBeat = discreteBeats
            lastBeatUpdate = discreteBeats

            // Preserve elapsed offset as base time for this playback session
            pausedElapsedTime = actualElapsedTime

            // A speed change applied while paused is not cleared by applySpeedChangeInternal
            // (which only acts while playing). Re-evaluate on resume so a run slowed at any
            // point cannot set an all-time best. One-way latch: only ever clears.
            if !Self.isFullSpeed(practiceSettings.speedMultiplier) {
                sessionAtFullSpeed = false
            }
        } else {
            Logger.audioPlayback("🎮 Starting fresh playback")

            // Starting from beginning - reset all state
            resetPlaybackState()
            pausedElapsedTime = 0.0
            // A fresh run is best-eligible only if it begins at full speed.
            sessionAtFullSpeed = Self.isFullSpeed(practiceSettings.speedMultiplier)
        }

        startBGMPlayback(track: track)

        // Set playback state AFTER all operations succeed
        // This ensures UI state accurately reflects whether playback actually started
        isPlaying = true

        // Start continuous visual tick (~30 Hz) so sub-beat notes (eighths,
        // sixteenths) advance and playback progress + row scrolling stay
        // responsive between quarter-note metronome callbacks.
        lastPlaybackProgressPublishElapsedTime = nil
        startVisualTickTimer()

        // Synchronize input timeline with the actual scheduled playback start time.
        // The metronome/BGM are scheduled 0.05s in the future (setupTime). The input
        // manager must use the same zero-point so hits are judged relative to what the
        // player hears, not relative to when startPlayback() was called.
        if let scheduledStartTime = lastScheduledPlaybackStartTime {
            // Convert CFAbsoluteTime to Date (both use the 2001-01-01 epoch).
            let adjustedSongStartTime = Date(
                timeIntervalSinceReferenceDate: scheduledStartTime - pausedElapsedTime
            )
            playbackStartTime = adjustedSongStartTime
            // Use the host time captured at the scheduling instant and the fixed setup
            // delay (0.05s) so the input zero-point aligns exactly with audio start,
            // with no drift from main-thread work between scheduling and this call.
            inputManager.startListening(
                songStartTime: adjustedSongStartTime,
                elapsedOffset: pausedElapsedTime,
                scheduledStartDelay: 0.05,
                capturedHostTime: lastScheduledPlaybackHostTime
            )
        } else {
            // Fallback: no scheduled start time available (shouldn't happen)
            let adjustedSongStartTime = Date()
            playbackStartTime = adjustedSongStartTime
            inputManager.startListening(
                songStartTime: adjustedSongStartTime,
                elapsedOffset: pausedElapsedTime
            )
        }
    }

    func handleSelectedMIDISourceDisconnect() {
        guard shouldGateGameplayOnSelectedMIDISource else { return }

        if isPlaying {
            pausePlayback()
            midiDeviceAlertMessage =
                "Your selected MIDI device disconnected. Reconnect it, then resume when ready."
        } else {
            midiDeviceAlertMessage = "Reconnect or reselect your MIDI device before starting."
        }

        isShowingMIDIDeviceAlert = true
    }

    func pausePlayback() {
        guard isPlaying else { return }
        let bgmElapsedTime = currentBGMPlaybackElapsedTime()

        isPlaying = false
        playbackTimer?.invalidate()
        playbackTimer = nil

        // Cancel scheduled completion if user pauses during grace period
        completionTask?.cancel()
        completionTask = nil
        completionScheduled = false

        if let bgmElapsedTime {
            pausedElapsedTime = bgmElapsedTime
        } else if let metronomeTime = metronome.getCurrentPlaybackTime() {
            pausedElapsedTime += metronomeTime
        } else if let startTime = playbackStartTime {
            // playbackStartTime is backdated by pausedElapsedTime, so the raw
            // interval already represents total elapsed song time. Use assignment
            // (not +=) to avoid double-counting the pause offset.
            //
            // When audio was scheduled in the future (e.g. the 50 ms priming
            // window) and the user pauses before it actually starts,
            // Date() - startTime is negative.  Clamp to the existing offset so
            // the next resume either re-uses the pre-start value (0 for fresh
            // starts) or the previously-accumulated pause offset.
            let elapsed = Date().timeIntervalSince(startTime)
            pausedElapsedTime = max(pausedElapsedTime, elapsed)
        }

        metronome.stop()
        inputManager.stopListening()
        playbackStartTime = nil
        bgmPlayer?.pause()
        purpleBarPosition = nil
        Logger.audioPlayback("Paused playback for track: \(track?.title ?? "Unknown")")
    }

    func restartPlayback() {
        resetPlaybackState()
        pausedElapsedTime = 0.0
        metronome.stop()
        bgmPlayer?.stop()
        bgmPlayer?.currentTime = 0
        Logger.audioPlayback("Restarted playback for track: \(track?.title ?? "Unknown")")
        if isPlaying {
            startPlayback()
        }
    }

    func skipToEnd() {
        // Only process a skip when actively playing; calling this on an idle or paused
        // session would run scanForMissedNotes + handlePlaybackCompletion with a
        // zero/partial score and open the results sheet unintentionally.
        guard isPlaying else { return }
        playbackTimer?.invalidate()
        playbackTimer = nil
        Logger.audioPlayback("Skipped to end for track: \(track?.title ?? "Unknown")")
        // Process all remaining unscored notes as misses before saving the score,
        // so the saved record reflects a complete run rather than a partial one.
        scanForMissedNotes(upToTimePosition: .infinity)
        // Capture the full position snapshot BEFORE handlePlaybackCompletion()
        // calls resetPlaybackState(), which zeros every field. Restoring all of
        // them keeps the frozen-at-end UI consistent (progress bar, purple bar,
        // beat/measure position all agree) whether or not the results sheet is
        // visible.
        let endBeat = currentBeat
        let endQNPosition = currentQuarterNotePosition
        let endTotalBeats = totalBeatsElapsed
        let endBeatPosition = currentBeatPosition
        let endRawBeatPosition = rawBeatPosition
        let endMeasureIndex = currentMeasureIndex
        let endPurpleBarPosition = purpleBarPosition
        let endRow = currentRow
        handlePlaybackCompletion()
        // Restore the end-of-song position so all playback fields are mutually
        // consistent (playbackProgress = 1.0 and position state at the last beat).
        playbackProgress = 1.0
        currentBeat = endBeat
        currentQuarterNotePosition = endQNPosition
        totalBeatsElapsed = endTotalBeats
        currentBeatPosition = endBeatPosition
        rawBeatPosition = endRawBeatPosition
        currentMeasureIndex = endMeasureIndex
        purpleBarPosition = endPurpleBarPosition
        currentRow = endRow
    }

    // MARK: - Cleanup

    func cleanup() {
        // Cancel any pending debounced speed changes before saving/cleanup
        // to prevent timer firing after cleanup and corrupting state
        speedChangeTimer?.invalidate()
        speedChangeTimer = nil
        latestPendingSpeed = nil

        // Cancel pending row-width resize to prevent layout rebuild after cleanup
        rowWidthTimer?.invalidate()
        rowWidthTimer = nil

        // Save speed setting for this chart (SC-06: Remember last-used speed per chart)
        // Guard: Only save if the chart's persisted speed was actually loaded.
        // Prevents race condition where quickly dismissing the view could save the
        // default speed (1.0) under the current chart's ID before its own speed was loaded.
        if hasLoadedPersistedSpeed {
            practiceSettings.saveSpeed(practiceSettings.speedMultiplier, for: chart.persistentModelID)
        }

        playbackTimer?.invalidate()
        playbackTimer = nil
        // Cancel any pending grace-period completion so it cannot persist score
        // state after the view has been dismissed.
        completionTask?.cancel()
        completionTask = nil
        completionScheduled = false
        metronome.stop()
        metronome.onInterruption = nil
        bgmPlayer?.stop()
        bgmPlayer = nil
        inputManager.stopListening()
        metronomeSubscription?.cancel()
        metronomeSubscription = nil
        isGameplayPrepared = false
    }
}
