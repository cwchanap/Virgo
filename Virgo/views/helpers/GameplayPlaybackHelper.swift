//
//  GameplayPlaybackHelper.swift
//  Virgo
//
//  Created by Claude Code on 9/8/2025.
//

import Foundation

extension GameplayView {
    // MARK: - Actions
    func togglePlayback() {
        isPlaying.toggle()
        if isPlaying {
            startPlayback()
        } else {
            pausePlayback()
        }
    }

    func pausePlayback() {
        playbackTimer?.invalidate()
        playbackTimer = nil

        // Stop metronome
        metronome.stop()
        
        // Stop InputManager listening
        inputManager.stopListening()

        // Save elapsed time when pausing
        if let startTime = playbackStartTime {
            pausedElapsedTime += Date().timeIntervalSince(startTime)
        }
        playbackStartTime = nil

        bgmPlayer?.pause()
        Logger.audioPlayback("Paused playback for track: \(track?.title ?? "Unknown")")
    }

    func startPlayback() {
        isPlaying = true
        guard let track = track else { return }

        // Start metronome immediately - no delay
        metronome.start(bpm: Double(track.bpm), timeSignature: track.timeSignature)
        
        // Set playback start time to current time for accurate timing reference
        playbackStartTime = Date()
        playbackTimer?.invalidate()
        
        // Start InputManager listening with current start time
        if let startTime = playbackStartTime {
            inputManager.startListening(songStartTime: startTime)
        }

        // Start BGM playback with precise timing to sync with metronome
        if let bgmPlayer = bgmPlayer {
            // Check if BGM was previously paused and resume from current position
            if bgmPlayer.currentTime > 0 && !bgmPlayer.isPlaying {
                // For resume, start immediately to match metronome
                bgmPlayer.play()
                Logger.audioPlayback("Resumed BGM playback for track: \(track.title)")
            } else {
                // Reset BGM to beginning
                bgmPlayer.currentTime = 0
                
                if bgmOffsetSeconds > 0 {
                    // Schedule BGM to start at current device time + BGM offset
                    // This ensures metronome starts at measure 0, BGM starts when music begins
                    let deviceTime = bgmPlayer.deviceCurrentTime
                    let bgmStartTime = deviceTime + bgmOffsetSeconds
                    bgmPlayer.play(atTime: bgmStartTime)
                    let message = "Scheduled BGM to start at \(bgmStartTime) (offset: \(bgmOffsetSeconds)s) for track: \(track.title)"
                    Logger.audioPlayback(message)
                } else {
                    // No offset - start BGM immediately to sync with metronome
                    bgmPlayer.play()
                    Logger.audioPlayback("Started BGM immediately to sync with metronome for track: \(track.title)")
                }
            }
        }

        Logger.audioPlayback("Started playback for track: \(track.title)")

        // Initialize playback position
        currentBeat = 0
        currentQuarterNotePosition = 0.0
        totalBeatsElapsed = 0
        lastBeatUpdate = -1
        currentBeatPosition = 0.0
        rawBeatPosition = 0.0
        currentMeasureIndex = 0
        lastMetronomeBeat = 0
        lastDiscreteBeat = -1
        lastDiscreteBeat = -1

        // CRITICAL: Force immediate UI update to show purple bar at position 0 from the start
        // This ensures the purple bar appears at beat 0 before the first timer update
        playbackProgress = 0.0

        // PERFORMANCE FIX: Reduce timer frequency from 10Hz to 2Hz to reduce UI updates
        // Each timer update triggers multiple @State changes causing expensive view re-renders
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
            self.updatePlaybackPosition(timer: timer)
        }
    }

    func updatePlaybackPosition(timer: Timer) {
        guard isPlaying else {
            timer.invalidate()
            return
        }

        guard let elapsedTime = calculateElapsedTime(),
              let track = track else { return }

        let playbackData = calculatePlaybackPosition(elapsedTime: elapsedTime, track: track)
        updateUIWithPlaybackData(playbackData, timer: timer, track: track)
    }

    // MARK: - Playback Position Helper Methods

    func calculateElapsedTime() -> Double? {
        guard let startTime = playbackStartTime else { return nil }
        let currentSessionTime = Date().timeIntervalSince(startTime)
        return pausedElapsedTime + currentSessionTime
    }

    struct PlaybackPositionData {
        let newBeatIndex: Int
        let newMeasureIndex: Int
        let newBeatPosition: Double
        let newTotalBeats: Int
        let newProgress: Double
    }

    func calculatePlaybackPosition(elapsedTime: Double, track: DrumTrack) -> PlaybackPositionData {
        let secondsPerBeat = 60.0 / Double(track.bpm)
        let beatsElapsed = elapsedTime / secondsPerBeat
        let beatsPerMeasure = Double(track.timeSignature.beatsPerMeasure)
        
        // Preserve fractional beat values for smooth animation
        let newMeasureIndex = Int(beatsElapsed / beatsPerMeasure)
        let beatWithinMeasure = beatsElapsed.truncatingRemainder(dividingBy: beatsPerMeasure)
        let newBeatPosition = beatWithinMeasure / beatsPerMeasure
        
        // Debug logging to trace the calculation
        if Int(elapsedTime * 10) % 5 == 0 { // Log every 0.5 seconds to avoid spam
            let logMessage = "Calculation: elapsed=\(elapsedTime), beatsElapsed=\(beatsElapsed), " +
                           "beatsPerMeasure=\(beatsPerMeasure), beatWithinMeasure=\(beatWithinMeasure), " +
                           "newBeatPosition=\(newBeatPosition)"
            Logger.debug(logMessage)
        }
        
        let totalBeats = Int(beatsElapsed)  // Keep for compatibility
        let newBeatIndex = findClosestBeatIndex(measureIndex: newMeasureIndex, beatPosition: newBeatPosition)
        let newProgress = min(elapsedTime / cachedTrackDuration, 1.0)

        return PlaybackPositionData(
            newBeatIndex: newBeatIndex,
            newMeasureIndex: newMeasureIndex,
            newBeatPosition: newBeatPosition,
            newTotalBeats: totalBeats,
            newProgress: newProgress
        )
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

    func updateUIWithPlaybackData(_ data: PlaybackPositionData, timer: Timer, track: DrumTrack) {
        let shouldUpdate = shouldUpdateUI(with: data)
        guard shouldUpdate else { return }

        applyUIUpdates(with: data)

        if data.newProgress >= 1.0 {
            handlePlaybackCompletion(timer: timer, track: track)
        }
    }

    func shouldUpdateUI(with data: PlaybackPositionData) -> Bool {
        // PERFORMANCE FIX: Only update if there's a significant change to reduce re-renders
        let significantBeatChange = abs(data.newBeatPosition - currentBeatPosition) > 0.1
        let measureChanged = data.newMeasureIndex != currentMeasureIndex
        let significantProgressChange = abs(playbackProgress - data.newProgress) > 0.05
        
        return measureChanged || significantBeatChange || significantProgressChange
    }

    func applyUIUpdates(with data: PlaybackPositionData) {
        // PERFORMANCE FIX: Batch state updates to minimize SwiftUI re-renders
        let beatsPerMeasure = track?.timeSignature.beatsPerMeasure ?? 4
        let discreteBeatPosition = floor(data.newBeatPosition * Double(beatsPerMeasure)) / Double(beatsPerMeasure)
        
        // Batch all state updates into a single update to reduce SwiftUI re-evaluation
        currentBeat = data.newBeatIndex
        currentMeasureIndex = data.newMeasureIndex
        currentBeatPosition = discreteBeatPosition  // Discretized for UI consistency
        rawBeatPosition = data.newBeatPosition      // Raw continuous for purple bar sync
        totalBeatsElapsed = data.newTotalBeats
        currentQuarterNotePosition = Double(data.newMeasureIndex) + discreteBeatPosition
        playbackProgress = data.newProgress
        
        // PERFORMANCE FIX: Update active beat once instead of calculating for every beat
        updateActiveBeat()
        // PERFORMANCE FIX: Update purple bar position once instead of calculating on every render
        updatePurpleBarPosition()
        
        let logMessage = "Purple bar discrete sync: measure=\(data.newMeasureIndex), " +
                       "timer_beat=\(data.newBeatPosition), " +
                       "discrete_beat=\(discreteBeatPosition)"
        Logger.debug(logMessage)
        
        // DEBUG: Compare timer calculations with metronome timing
        if let elapsedTime = calculateElapsedTime(), let track = track {
            let secondsPerBeat = 60.0 / Double(track.bpm)
            let expectedBeats = elapsedTime / secondsPerBeat
            let metronomeCurrentBeat = metronome.currentBeat
            let timerLogMessage = "TIMING COMPARISON: elapsed=\(String(format: "%.3f", elapsedTime))s, " +
                                "expected_beats=\(String(format: "%.3f", expectedBeats)), " +
                                "metronome_beat=\(metronomeCurrentBeat)"
            Logger.debug(timerLogMessage)
        }
    }

    func handlePlaybackCompletion(timer: Timer, track: DrumTrack) {
        timer.invalidate()
        isPlaying = false
        metronome.stop()
        playbackProgress = 0.0
        currentBeat = 0
        currentQuarterNotePosition = 0.0
        totalBeatsElapsed = 0
        lastBeatUpdate = -1
        currentBeatPosition = 0.0
        rawBeatPosition = 0.0
        currentMeasureIndex = 0
        lastMetronomeBeat = 0
        lastDiscreteBeat = -1
        playbackStartTime = nil
        pausedElapsedTime = 0.0
        bgmPlayer?.stop()
        Logger.audioPlayback("Playback finished for track: \(track.title)")
    }

    func restartPlayback() {
        playbackProgress = 0.0
        currentBeat = 0
        currentQuarterNotePosition = 0.0
        totalBeatsElapsed = 0
        lastBeatUpdate = -1
        currentBeatPosition = 0.0
        rawBeatPosition = 0.0
        currentMeasureIndex = 0
        lastMetronomeBeat = 0
        lastDiscreteBeat = -1
        playbackStartTime = nil
        pausedElapsedTime = 0.0  // Reset paused time on restart
        metronome.stop()
        bgmPlayer?.stop()
        bgmPlayer?.currentTime = 0  // Reset to beginning
        Logger.audioPlayback("Restarted playback for track: \(track?.title ?? "Unknown")")
        if isPlaying {
            startPlayback()
        }
    }

    func skipToEnd() {
        playbackProgress = 1.0
        isPlaying = false
        playbackTimer?.invalidate()
        playbackTimer = nil
        playbackStartTime = nil
        pausedElapsedTime = 0.0  // Reset paused time on skip to end
        bgmPlayer?.stop()
        Logger.audioPlayback("Skipped to end for track: \(track?.title ?? "Unknown")")
    }
}
