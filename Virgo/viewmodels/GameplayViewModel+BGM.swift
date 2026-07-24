//
//  GameplayViewModel+BGM.swift
//  Virgo
//

import Foundation
import AVFoundation

extension GameplayViewModel {
    // MARK: - Private Helpers

    func resetPlaybackState() { // internal for cross-file extension access
        currentBeat = 0
        currentQuarterNotePosition = 0.0
        totalBeatsElapsed = 0
        lastBeatUpdate = -1
        currentBeatPosition = 0.0
        rawBeatPosition = 0.0
        currentMeasureIndex = 0
        lastMetronomeBeat = 0
        lastDiscreteBeat = -1
        playbackProgress = 0.0
        lastPlaybackProgressPublishElapsedTime = nil
        purpleBarPosition = nil
        currentRow = 0
        lastScheduledPlaybackStartTime = nil
        lastScheduledPlaybackHostTime = nil
        resetScoring()
    }

    func refreshTimingCaches() { // internal for cross-file extension access
        guard isDataLoaded, track != nil else { return }
        bgmOffsetSeconds = calculateBGMOffset()
        cachedTrackDuration = calculateTrackDuration()
    }

    /// Returns the clamped speed if BGM is present and speed is below minimum, nil otherwise.
    /// Returns value instead of calling setSpeed directly, preventing .onChange re-entry.
    func enforceBGMMinimumSpeedIfNeeded() -> Double? { // internal for cross-file extension access
        guard let bgmPlayer, !shouldYieldBGMClockToTimeline(bgmPlayer) else { return nil }
        let minimumSpeed = 0.5
        if practiceSettings.speedMultiplier < minimumSpeed {
            Logger.warning("BGM enabled - clamping speed to 50% to keep audio in sync")
            return minimumSpeed
        }
        return nil
    }

    func startBGMPlayback(track: DrumTrack) { // internal for cross-file extension access
        guard !hasFatalRhythmTiming else {
            Logger.error("Cannot start BGM or metronome for timing-fatal chart")
            return
        }
        let currentEffectiveBPM = effectiveBPM()
        let currentSpeedMultiplier = practiceSettings.speedMultiplier

        if let bgmPlayer = bgmPlayer {
            bgmPlayer.enableRate = true
            bgmPlayer.rate = clampedBGMRate(for: currentSpeedMultiplier)

            let isResuming = pausedElapsedTime > 0.0

            if shouldYieldBGMClockToTimeline(bgmPlayer) {
                lastScheduledPlaybackStartTime = startMetronomeOnlyPlayback(
                    track: track,
                    effectiveBPM: currentEffectiveBPM
                )
            } else if bgmPlayer.currentTime > 0 && !bgmPlayer.isPlaying {
                lastScheduledPlaybackStartTime = resumeBGMFromPosition(
                    track: track,
                    bgmPlayer: bgmPlayer,
                    effectiveBPM: currentEffectiveBPM
                )
            } else if isResuming {
                lastScheduledPlaybackStartTime = resumeBGMDuringOffset(
                    track: track,
                    bgmPlayer: bgmPlayer,
                    effectiveBPM: currentEffectiveBPM
                )
            } else {
                lastScheduledPlaybackStartTime = startFreshBGMPlayback(
                    track: track,
                    bgmPlayer: bgmPlayer,
                    effectiveBPM: currentEffectiveBPM
                )
            }
        } else {
            lastScheduledPlaybackStartTime = startMetronomeOnlyPlayback(
                track: track,
                effectiveBPM: currentEffectiveBPM
            )
        }
    }

    @discardableResult
    private func resumeBGMFromPosition(
        track: DrumTrack,
        bgmPlayer: AVAudioPlayer,
        effectiveBPM: Double
    ) -> CFAbsoluteTime {
        Logger.audioPlayback("🎮 Resuming BGM at \(bgmPlayer.currentTime)s")
        let setupTime: TimeInterval = 0.05
        let capturedHostTime = mach_absolute_time()
        lastScheduledPlaybackHostTime = capturedHostTime
        let commonStartTime = CFAbsoluteTimeGetCurrent() + setupTime
        startMetronomeAtSharedTime(
            commonStartTime,
            timeSignature: track.timeSignature,
            effectiveBPM: effectiveBPM
        )
        let bgmDeviceTime = convertToAudioPlayerDeviceTime(commonStartTime, bgmPlayer: bgmPlayer)
        if !bgmPlayer.play(atTime: bgmDeviceTime) {
            Logger.error("BGM play(atTime:) failed during resume from position")
        }
        return commonStartTime
    }

    @discardableResult
    private func resumeBGMDuringOffset(
        track: DrumTrack,
        bgmPlayer: AVAudioPlayer,
        effectiveBPM: Double
    ) -> CFAbsoluteTime {
        Logger.audioPlayback("🎮 Resuming during BGM offset period")
        bgmPlayer.currentTime = 0
        let setupTime: TimeInterval = 0.05
        let capturedHostTime = mach_absolute_time()
        lastScheduledPlaybackHostTime = capturedHostTime
        let commonStartTime = CFAbsoluteTimeGetCurrent() + setupTime

        startMetronomeAtSharedTime(
            commonStartTime,
            timeSignature: track.timeSignature,
            effectiveBPM: effectiveBPM
        )

        let remainingOffset = remainingBGMOffset()
        let bgmDeviceTime = convertToAudioPlayerDeviceTime(commonStartTime, bgmPlayer: bgmPlayer)
        let bgmScheduledTime = bgmDeviceTime + remainingOffset
        if !bgmPlayer.play(atTime: bgmScheduledTime) {
            Logger.error("BGM play(atTime:) failed during resume in offset period")
        }
        return commonStartTime
    }

    @discardableResult
    private func startFreshBGMPlayback(
        track: DrumTrack,
        bgmPlayer: AVAudioPlayer,
        effectiveBPM: Double
    ) -> CFAbsoluteTime {
        Logger.audioPlayback("🎮 Starting fresh BGM playback")
        bgmPlayer.currentTime = 0
        let setupTime: TimeInterval = 0.05
        let capturedHostTime = mach_absolute_time()
        lastScheduledPlaybackHostTime = capturedHostTime
        let commonStartTime = CFAbsoluteTimeGetCurrent() + setupTime
        startMetronomeAtSharedTime(
            commonStartTime,
            timeSignature: track.timeSignature,
            effectiveBPM: effectiveBPM
        )

        let bgmDeviceTime = convertToAudioPlayerDeviceTime(commonStartTime, bgmPlayer: bgmPlayer)
        let bgmScheduledTime = bgmDeviceTime + bgmOffsetSeconds
        if !bgmPlayer.play(atTime: bgmScheduledTime) {
            Logger.error("BGM play(atTime:) failed during fresh playback start")
        }
        return commonStartTime
    }

    @discardableResult
    private func startMetronomeOnlyPlayback(
        track: DrumTrack,
        effectiveBPM: Double
    ) -> CFAbsoluteTime {
        let isResuming = pausedElapsedTime > 0.0
        Logger.audioPlayback(
            isResuming
                ? "🎮 Resuming metronome-only playback with beat offset"
                : "🎮 Starting metronome-only playback"
        )

        // Use the same delayed start as BGM-backed playback so input listening
        // is installed before the first scheduled metronome pulse.
        let setupTime: TimeInterval = 0.05
        let capturedHostTime = mach_absolute_time()
        lastScheduledPlaybackHostTime = capturedHostTime
        let startTime = CFAbsoluteTimeGetCurrent() + setupTime
        startMetronomeAtSharedTime(
            startTime,
            timeSignature: track.timeSignature,
            effectiveBPM: effectiveBPM
        )
        return startTime
    }

    func startMetronomeAtSharedTime(
        _ startTime: CFAbsoluteTime,
        timeSignature: TimeSignature,
        effectiveBPM: Double
    ) {
        if let schedule = cachedRhythmRuntime.metronomeSchedule {
            metronome.startAtTime(
                schedule: schedule,
                speed: practiceSettings.speedMultiplier,
                startTime: startTime,
                elapsedTime: pausedElapsedTime
            )
        } else {
            metronome.startAtTime(
                bpm: effectiveBPM,
                timeSignature: timeSignature,
                startTime: startTime,
                totalBeatsElapsed: elapsedBeatsForScheduling(effectiveBPM: effectiveBPM)
            )
        }
    }

    // internal for cross-file extension access
    func convertToAudioPlayerDeviceTime(_ cfTime: CFAbsoluteTime, bgmPlayer: AVAudioPlayer) -> TimeInterval {
        let currentCFTime = CFAbsoluteTimeGetCurrent()
        let currentAudioTime = bgmPlayer.deviceCurrentTime
        let timeOffset = cfTime - currentCFTime
        return currentAudioTime + timeOffset
    }

    /// Remaining BGM offset delay based on the current paused elapsed time.
    /// Internal for unit testing.
    func remainingBGMOffset() -> Double {
        max(0, bgmOffsetSeconds - pausedElapsedTime)
    }

    // MARK: - BGM Setup

    func setupBGMPlayer() {
        guard !hasFatalRhythmTiming else { return }
        guard let song = cachedSong,
              let bgmFilePath = song.bgmFilePath,
              !bgmFilePath.isEmpty else {
            Logger.audioPlayback("No BGM file available for track: \(track?.title ?? "Unknown")")
            return
        }

        let bgmURL = URL(fileURLWithPath: bgmFilePath)

        do {
            bgmPlayer = try AVAudioPlayer(contentsOf: bgmURL)
            // enableRate must be set before prepareToPlay() for AVAudioPlayer to allocate rate-adjustment buffers
            bgmPlayer?.enableRate = true
            bgmPlayer?.prepareToPlay()
            bgmPlayer?.volume = 0.7
            Logger.audioPlayback("BGM player setup successful for track: \(track?.title ?? "Unknown")")
        } catch {
            bgmLoadingError = "Failed to load BGM: \(error.localizedDescription)"
            Logger.error("Failed to setup BGM player: \(error.localizedDescription)")
        }
    }
}
