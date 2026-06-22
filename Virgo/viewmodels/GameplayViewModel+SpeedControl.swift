//
//  GameplayViewModel+SpeedControl.swift
//  Virgo
//

import Foundation

extension GameplayViewModel {
    // MARK: - Speed Control

    /// True when a speed multiplier is effectively 1.0x.
    static func isFullSpeed(_ multiplier: Double) -> Bool {
        abs(multiplier - 1.0) < 0.0001
    }

    /// Calculates the effective BPM based on current speed multiplier.
    /// This should be used for all timing calculations instead of track.bpm directly.
    func effectiveBPM() -> Double {
        guard let track = track else {
            Logger.error("effectiveBPM() called with nil track - using fallback 120 BPM")
            return practiceSettings.effectiveBPM(baseBPM: 120.0)
        }
        return practiceSettings.effectiveBPM(baseBPM: track.bpm)
    }

    /// Updates the playback speed. Can be called during active playback.
    /// - Parameter newSpeed: Speed multiplier (0.25 to 1.5)
    func updateSpeed(_ newSpeed: Double) {
        practiceSettings.setSpeed(newSpeed)
        applySpeedChange()
    }

    /// Applies updates when practice settings change without recreating the view model.
    /// - Parameter practiceSettings: The shared practice settings service.
    /// Verifies the caller's reference matches this ViewModel's instance before applying.
    /// Note: Currently unused - intended for future .onChange modifier integration.
    func updateSettings(_ practiceSettings: PracticeSettingsService) {
        guard practiceSettings === self.practiceSettings else { return }
        applySpeedChange()
    }

    private func applySpeedChange() {
        // Trailing-edge debounce: store the latest speed and schedule application
        let targetSpeed = practiceSettings.speedMultiplier
        latestPendingSpeed = targetSpeed

        // Cancel any existing pending timer
        speedChangeTimer?.invalidate()

        // Make speed updates deterministic in unit tests to avoid run-loop timing flakiness.
        if TestEnvironment.isRunningTests {
            let previousApplied = lastAppliedSpeedMultiplier
            lastSpeedChangeTimestamp = Date()
            latestPendingSpeed = nil
            applySpeedChangeInternal(previousSpeed: previousApplied)
            return
        }

        // Schedule a new timer to apply the speed change after the debounce interval
        speedChangeTimer = Timer.scheduledTimer(withTimeInterval: speedChangeDebounceInterval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else {
                    Logger.warning("Speed change timer fired after ViewModel deallocation - user's speed change was discarded")
                    return
                }

                // Only apply if we still have a pending speed
                guard self.latestPendingSpeed != nil else { return }

                // Use lastAppliedSpeedMultiplier (the actual last-applied speed) instead of a
                // captured previousSpeed parameter, which could be stale from a debounced-away
                // intermediate slider value
                let previousApplied = self.lastAppliedSpeedMultiplier

                // Update timestamp when actually applying
                self.lastSpeedChangeTimestamp = Date()
                self.latestPendingSpeed = nil

                // Apply the speed change
                self.applySpeedChangeInternal(previousSpeed: previousApplied)
            }
        }
    }

    /// Internal method that actually applies the speed change after debouncing
    private func applySpeedChangeInternal(previousSpeed: Double) {
        // Skip speed application during initialization before data is loaded
        guard isDataLoaded else {
            Logger.debug("Speed change skipped - data not yet loaded")
            return
        }

        // Enforce BGM minimum speed if needed, applying once to avoid redundant .onChange re-entry
        if let clampedSpeed = enforceBGMMinimumSpeedIfNeeded() {
            practiceSettings.setSpeed(clampedSpeed)
        }
        refreshTimingCaches()
        let currentSpeed = practiceSettings.speedMultiplier
        guard abs(previousSpeed - currentSpeed) > 0.0001 else { return }
        lastAppliedSpeedMultiplier = currentSpeed
        if isPlaying && !Self.isFullSpeed(currentSpeed) {
            sessionAtFullSpeed = false
        }
        let effectiveBPMValue = effectiveBPM()

        if isDataLoaded, let track = track {
            // Keep input timing aligned even before playback starts.
            inputManager.configure(
                bpm: effectiveBPMValue,
                timeSignature: track.timeSignature,
                notes: cachedNotes
            )
        }

        // If playing, update metronome and BGM rate immediately
        if isPlaying {
            applySpeedChangeWhilePlaying(
                previousSpeed: previousSpeed,
                currentSpeed: currentSpeed,
                effectiveBPMValue: effectiveBPMValue
            )
        } else if pausedElapsedTime > 0, previousSpeed > 0, currentSpeed > 0 {
            let speedRatio = previousSpeed / currentSpeed
            pausedElapsedTime *= speedRatio
            if cachedTrackDuration > 0 {
                playbackProgress = pausedElapsedTime / cachedTrackDuration
            } else {
                Logger.warning("Cannot update playback progress: cachedTrackDuration is zero")
                playbackProgress = 0.0
            }
        }

        if !isPlaying, metronome.isEnabled {
            metronome.updateBPM(effectiveBPMValue)
        }
    }

    /// Returns a clamped BGM playback rate for AVAudioPlayer while logging clamp warnings.
    /// Exposed as non-private to enable unit testing.
    func clampedBGMRate(for speedMultiplier: Double) -> Float {
        let clampedRate = Float(max(0.5, min(2.0, speedMultiplier)))

        // Warn if BGM rate is clamped (causes desync with metronome)
        if speedMultiplier < 0.5 {
            Logger.warning(
                "BGM rate clamped from \(Int(speedMultiplier * 100))% to 50% - " +
                    "AVAudioPlayer limitation may cause audio desync"
            )
        } else if speedMultiplier > 2.0 {
            Logger.warning(
                "BGM rate clamped from \(Int(speedMultiplier * 100))% to 200% - " +
                    "AVAudioPlayer limitation may cause audio desync"
            )
        }

        return clampedRate
    }

    /// Converts audio-file time into the speed-adjusted timeline used for beat/progress math.
    /// Internal for unit testing.
    func bgmTimelineElapsedTime(for bgmCurrentTime: TimeInterval) -> Double {
        let speedMultiplier = practiceSettings.speedMultiplier
        guard speedMultiplier > 0 else {
            assertionFailure("bgmTimelineElapsedTime called with zero speedMultiplier")
            Logger.error("bgmTimelineElapsedTime called with zero speedMultiplier - returning bgmOffsetSeconds as fallback")
            return bgmOffsetSeconds
        }

        return (bgmCurrentTime / speedMultiplier) + bgmOffsetSeconds
    }

    func elapsedBeatsForScheduling(effectiveBPM: Double) -> Double { // internal for cross-file extension access
        guard effectiveBPM.isFinite, effectiveBPM > 0 else {
            Logger.error("elapsedBeatsForScheduling called with invalid effectiveBPM - using integer beat state")
            return Double(totalBeatsElapsed)
        }
        return max(0, pausedElapsedTime * effectiveBPM / 60.0)
    }

    /// Reschedules BGM playback to align with a metronome restart on speed changes.
    /// Internal for unit testing.
    @discardableResult
    func rescheduleBGMForSpeedChange(commonStartTime: CFAbsoluteTime) -> Bool {
        guard let bgmPlayer = bgmPlayer else {
            return false
        }

        bgmPlayer.pause()
        let bgmDeviceTime = convertToAudioPlayerDeviceTime(commonStartTime, bgmPlayer: bgmPlayer)
        let remainingOffset = remainingBGMOffset()
        let scheduledTime: TimeInterval
        if remainingOffset > 0, bgmPlayer.currentTime == 0 {
            scheduledTime = bgmDeviceTime + remainingOffset
        } else {
            scheduledTime = bgmDeviceTime
        }
        let success = bgmPlayer.play(atTime: scheduledTime)
        if !success {
            Logger.error("BGM play(atTime:) failed during speed change reschedule (scheduled: \(scheduledTime))")
        }
        return success
    }

    private func applySpeedChangeWhilePlaying(
        previousSpeed: Double,
        currentSpeed: Double,
        effectiveBPMValue: Double
    ) {
        if let bgmPlayer = bgmPlayer {
            bgmPlayer.enableRate = true
            bgmPlayer.rate = clampedBGMRate(for: currentSpeed)
        }

        if let metronomeTime = metronome.getCurrentPlaybackTime(), previousSpeed > 0, currentSpeed > 0 {
            pausedElapsedTime += metronomeTime
            let speedRatio = previousSpeed / currentSpeed
            pausedElapsedTime *= speedRatio
            let elapsedBeats = elapsedBeatsForScheduling(effectiveBPM: effectiveBPMValue)
            restartMetronomeForSpeedChange(effectiveBPM: effectiveBPMValue, elapsedBeats: elapsedBeats)
        } else {
            if previousSpeed > 0, currentSpeed > 0 {
                let speedRatio = previousSpeed / currentSpeed
                pausedElapsedTime *= speedRatio
            }
            let elapsedBeats = elapsedBeatsForScheduling(effectiveBPM: effectiveBPMValue)
            restartMetronomeForSpeedChange(effectiveBPM: effectiveBPMValue, elapsedBeats: elapsedBeats)
            Logger.warning("BGM rescheduled after speed change without metronome time - may cause brief desync")
        }

        if previousSpeed > 0, currentSpeed > 0 {
            if let scheduledStart = lastScheduledPlaybackStartTime {
                let adjustedSongStartTime = Date(
                    timeIntervalSinceReferenceDate: scheduledStart - pausedElapsedTime
                )
                self.playbackStartTime = adjustedSongStartTime
                inputManager.startListening(
                    songStartTime: adjustedSongStartTime,
                    elapsedOffset: pausedElapsedTime,
                    scheduledStartDelay: 0.05,
                    capturedHostTime: lastScheduledPlaybackHostTime
                )
            } else if let playbackStartTime = playbackStartTime {
                let elapsedSinceStart = Date().timeIntervalSince(playbackStartTime)
                let speedRatio = previousSpeed / currentSpeed
                let adjustedElapsed = elapsedSinceStart * speedRatio
                let adjustedSongStartTime = Date()
                self.playbackStartTime = adjustedSongStartTime
                inputManager.startListening(
                    songStartTime: adjustedSongStartTime,
                    elapsedOffset: adjustedElapsed
                )
            }
        }

        let speedPercent = Int(currentSpeed * 100)
        Logger.audioPlayback("Live speed change to \(speedPercent)% (\(Int(effectiveBPMValue)) BPM)")
    }

    /// Stops and restarts the metronome at a scheduled future time for a live speed
    /// change, capturing host time and updating beat bookkeeping. Shared by both the
    /// metronome-time-available and fallback branches of `applySpeedChangeWhilePlaying`.
    /// Returns the scheduled CFAbsoluteTime start so callers can reschedule BGM against it.
    @discardableResult
    private func restartMetronomeForSpeedChange(
        effectiveBPM: Double,
        elapsedBeats: Double
    ) -> CFAbsoluteTime {
        let beatOffset = Int(elapsedBeats)
        totalBeatsElapsed = beatOffset
        metronome.stop()
        let capturedHostTime = mach_absolute_time()
        lastScheduledPlaybackHostTime = capturedHostTime
        let scheduledStartTime = CFAbsoluteTimeGetCurrent() + 0.05
        lastScheduledPlaybackStartTime = scheduledStartTime
        metronome.startAtTime(
            bpm: effectiveBPM,
            timeSignature: track?.timeSignature ?? .fourFour,
            startTime: scheduledStartTime,
            totalBeatsElapsed: elapsedBeats
        )
        rescheduleBGMForSpeedChange(commonStartTime: scheduledStartTime)
        return scheduledStartTime
    }
}
