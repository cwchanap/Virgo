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

        // TIMING SYNC: Save elapsed time using metronome's timing reference
        if let metronomeTime = metronome.getCurrentPlaybackTime() {
            pausedElapsedTime += metronomeTime
        } else if let startTime = playbackStartTime {
            // Fallback to Date-based calculation if metronome timing unavailable
            pausedElapsedTime += Date().timeIntervalSince(startTime)
        }
        playbackStartTime = nil

        bgmPlayer?.pause()
        Logger.audioPlayback("Paused playback for track: \(track?.title ?? "Unknown")")
    }

    func startPlayback() {
        isPlaying = true
        guard let track = track else { return }

        // Set playback start time BEFORE starting metronome for synchronized timing reference
        playbackStartTime = Date()
        playbackTimer?.invalidate()
        
        // CRITICAL FIX: Calculate synchronized start time for both metronome and BGM
        // This eliminates the timing gap that made metronome appear "faster"
        let synchronizedStartDelay: TimeInterval = 0.1 // 100ms buffer for precise sync
        
        // Start InputManager listening with current start time
        if let startTime = playbackStartTime {
            inputManager.startListening(songStartTime: startTime)
        }

        // Start BGM playback with precise timing to sync with metronome
        if let bgmPlayer = bgmPlayer {
            // Check if BGM was previously paused and resume from current position
            if bgmPlayer.currentTime > 0 && !bgmPlayer.isPlaying {
                // For resume, start metronome and BGM simultaneously
                let trackBPM = track.bpm
                metronome.start(bpm: trackBPM, timeSignature: track.timeSignature)
                bgmPlayer.play()
                Logger.audioPlayback("Resumed BGM and metronome playback simultaneously for track: \(track.title)")
            } else {
                // Reset BGM to beginning and synchronize start times
                bgmPlayer.currentTime = 0
                
                // CRITICAL FIX: Use consistent timing references for BGM and metronome
                // BGM uses deviceCurrentTime, metronome uses CFAbsoluteTime - they're different!
                let bgmDeviceTime = bgmPlayer.deviceCurrentTime
                let bgmScheduledTime = bgmDeviceTime + synchronizedStartDelay + bgmOffsetSeconds
                
                // Schedule BGM to start at BGM's time reference
                bgmPlayer.play(atTime: bgmScheduledTime)
                
                // Start metronome immediately since we can't sync different time references
                // The 100ms delay in BGM scheduling compensates for metronome startup time
                let trackBPM = track.bpm
                
                metronome.start(bpm: trackBPM, timeSignature: track.timeSignature)
                
                let message = "Scheduled synchronized start - BGM at device time: \(bgmScheduledTime) " +
                            "(BGM offset: \(bgmOffsetSeconds)s, sync buffer: \(synchronizedStartDelay)s)"
                Logger.audioPlayback(message)
            }
        } else {
            // No BGM - start metronome immediately
            let trackBPM = track.bpm
            metronome.start(bpm: trackBPM, timeSignature: track.timeSignature)
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

        // CRITICAL FIX: Use metronome callbacks for visual updates instead of separate timer
        // This eliminates timing desync between audio and visual systems
        
        // The visual updates will now be driven by metronome beat callbacks via the existing subscription
        // This ensures perfect audio-visual synchronization using a single timing source
    }

    // TIMING SYNC: This function is deprecated - visual updates are now handled by metronome callbacks
    // Keeping for backwards compatibility during transition
    func updatePlaybackPosition(timer: Timer) {
        guard isPlaying else {
            timer.invalidate()
            return
        }

        // Visual updates are now driven by metronome callbacks in GameplayView.updateVisualElementsFromMetronome()
    }

    // MARK: - Playback Position Helper Methods

    func calculateElapsedTime() -> Double? {
        // TIMING SYNC: Always use metronome's timing reference for perfect sync
        // This ensures visual elements use the exact same time base as audio
        if let metronomeTime = metronome.getCurrentPlaybackTime() {
            let totalTime = pausedElapsedTime + metronomeTime
            return totalTime
        } else if isPlaying, let startTime = playbackStartTime {
            // Fallback only during transition period when metronome timing unavailable
            let currentSessionTime = Date().timeIntervalSince(startTime)
            let totalTime = pausedElapsedTime + currentSessionTime
            return totalTime
        } else {
            return nil
        }
    }

    struct PlaybackPositionData {
        let newBeatIndex: Int
        let newMeasureIndex: Int
        let newBeatPosition: Double
        let newTotalBeats: Int
        let newProgress: Double
    }

    func calculatePlaybackPosition(elapsedTime: Double, track: DrumTrack) -> PlaybackPositionData {
        let secondsPerBeat = 60.0 / track.bpm
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
            handlePlaybackCompletion(track: track)
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
    }

    func handlePlaybackCompletion(track: DrumTrack) {
        // TIMING SYNC: No separate timer to invalidate - completion triggered by metronome callbacks
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
