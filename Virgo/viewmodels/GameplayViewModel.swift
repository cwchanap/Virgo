//
//  GameplayViewModel.swift
//  Virgo
//
//  Consolidates GameplayView state management to reduce @State explosion
//  and improve maintainability.
//

// swiftlint:disable file_length type_body_length

import SwiftUI
import Observation
import AVFoundation
import Combine

/// ViewModel for GameplayView that consolidates state management
/// and provides a clean separation between UI and business logic.
@Observable
@MainActor
final class GameplayViewModel {
    // MARK: - Dependencies
    let chart: Chart
    let metronome: MetronomeEngine

    // MARK: - Cached SwiftData Relationships
    /// Cached song to avoid main thread blocking from relationship access
    var cachedSong: Song?
    /// Cached notes array to avoid relationship access during rendering
    var cachedNotes: [Note] = []
    /// Flag indicating whether async data loading is complete
    var isDataLoaded = false

    // MARK: - Track State
    /// Cached DrumTrack instance to avoid repeated object creation
    var track: DrumTrack?

    // MARK: - Playback State
    /// Whether playback is currently active
    var isPlaying = false
    /// Current playback progress (0.0 to 1.0)
    var playbackProgress: Double = 0.0
    /// Current beat index in the track
    var currentBeat: Int = 0
    /// Current quarter note position for visual sync
    var currentQuarterNotePosition: Double = 0.0
    /// Total beats elapsed since playback started
    var totalBeatsElapsed: Int = 0

    // MARK: - Timing State
    /// Current beat position within measure (discretized for UI)
    var currentBeatPosition: Double = 0.0
    /// Raw continuous beat position for purple bar sync
    var rawBeatPosition: Double = 0.0
    /// Current measure index (0-based)
    var currentMeasureIndex: Int = 0
    /// Last metronome beat value to detect changes
    var lastMetronomeBeat: Int = 0
    /// Last discrete beat to prevent unnecessary updates
    var lastDiscreteBeat: Int = -1
    /// Last beat update index
    var lastBeatUpdate: Int = -1
    /// Timer for playback updates (deprecated - now using metronome callbacks)
    var playbackTimer: Timer?
    /// Playback start time for timing calculations
    var playbackStartTime: Date?
    /// Accumulated elapsed time when paused
    var pausedElapsedTime: Double = 0.0

    // MARK: - Cached Layout Data
    /// Pre-computed drum beats from notes
    private(set) var cachedDrumBeats: [DrumBeat] = []
    /// Pre-computed measure positions for layout
    private(set) var cachedMeasurePositions: [GameplayLayout.MeasurePosition] = []
    /// Pre-computed beam groups for notation
    private(set) var cachedBeamGroups: [BeamGroup] = []
    /// Fast lookup map from beat ID to beam group
    private(set) var beatToBeamGroupMap: [UInt64: BeamGroup] = [:]
    /// Cached track duration in seconds
    private(set) var cachedTrackDuration: Double = 0.0
    /// Cached beat indices for iteration
    private(set) var cachedBeatIndices: [Int] = []
    /// Fast lookup map from measure index to position
    private(set) var measurePositionMap: [Int: GameplayLayout.MeasurePosition] = [:]
    /// Pre-cached beat positions for performance
    private(set) var cachedBeatPositions: [UInt64: (x: Double, y: Double)] = [:]

    // MARK: - Visual State
    /// Currently active beat ID for highlighting
    var activeBeatId: UInt64?
    /// Current purple bar position (x, y)
    var purpleBarPosition: (x: Double, y: Double)?
    /// Cached static staff lines view (uses AnyView for type erasure)
    var staticStaffLinesView: AnyView?

    // MARK: - BGM State
    /// Audio player for background music
    var bgmPlayer: AVAudioPlayer?
    /// Error message if BGM loading failed
    var bgmLoadingError: String?
    /// BGM start offset in seconds (for sync with first note)
    var bgmOffsetSeconds: Double = 0.0

    // MARK: - Input State
    /// Input manager for MIDI/keyboard handling
    var inputManager = InputManager()
    /// Input handler delegate
    var inputHandler = GameplayInputHandler()

    // MARK: - Subscriptions
    /// Metronome beat subscription for visual sync
    var metronomeSubscription: AnyCancellable?

    // MARK: - Initialization

    init(chart: Chart, metronome: MetronomeEngine) {
        self.chart = chart
        self.metronome = metronome
    }

    // MARK: - Unique ID Generation
    /// Monotonic counter for generating unique DrumBeat IDs
    /// Thread-safe: @MainActor ensures all access is on main thread
    private var nextBeatId: UInt64 = 0

    /// Generate a unique ID for a DrumBeat
    private func generateBeatId() -> UInt64 {
        defer { nextBeatId += 1 }
        return nextBeatId
    }

    // MARK: - Data Loading

    /// Loads SwiftData relationships asynchronously to avoid blocking main thread
    func loadChartData() async {
        cachedSong = chart.song
        cachedNotes = chart.notes.map { $0 }

        track = DrumTrack(chart: chart)
        isDataLoaded = true
    }

    // MARK: - Setup

    /// Sets up gameplay after data is loaded
    func setupGameplay() {
        guard let track = track else {
            Logger.audioPlayback("setupGameplay() called but track is nil - data not loaded yet")
            return
        }

        computeDrumBeats()
        computeCachedLayoutData()
        bgmOffsetSeconds = calculateBGMOffset()
        metronome.configure(bpm: track.bpm, timeSignature: track.timeSignature)
        setupBGMPlayer()
        cachedTrackDuration = calculateTrackDuration()
        inputManager.configure(bpm: track.bpm, timeSignature: track.timeSignature, notes: cachedNotes)
        setupInterruptionHandling()
    }

    /// Sets up audio interruption handling to pause playback on phone calls, Siri, etc.
    private func setupInterruptionHandling() {
        metronome.onInterruption = { [weak self] isInterrupted in
            guard let self = self else { return }
            if isInterrupted {
                Logger.audioPlayback("Audio interruption began - pausing gameplay")
                self.pausePlayback()
            } else {
                // Interruption ended - user can manually resume if desired
                // We don't auto-resume to avoid unexpected playback
                Logger.audioPlayback("Audio interruption ended - user can resume manually")
            }
        }
    }

    /// Sets up metronome subscription for visual sync
    func setupMetronomeSubscription() {
        metronomeSubscription = metronome.$currentBeat
            .sink { [weak self] currentBeat in
                guard let self = self else { return }
                if self.isPlaying && currentBeat != self.lastMetronomeBeat {
                    self.lastMetronomeBeat = currentBeat
                    self.updateVisualElementsFromMetronome()
                }
            }
    }

    // MARK: - Playback Control

    func togglePlayback() {
        Logger.audioPlayback("🎮 togglePlayback called - current isPlaying: \(isPlaying)")

        // Guard: Cannot start playback if data not loaded or track not ready
        if !isPlaying {
            guard isDataLoaded else {
                Logger.audioPlayback("🎮 ERROR: Cannot start playback - data not loaded")
                return
            }
            guard track != nil else {
                Logger.audioPlayback("🎮 ERROR: Cannot start playback - no track available")
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

        // Guard: Ensure track is ready before starting playback
        guard let track = track else {
            Logger.audioPlayback("🎮 ERROR: No track available for playback")
            return
        }

        guard isDataLoaded else {
            Logger.audioPlayback("🎮 ERROR: Data not loaded, cannot start playback")
            return
        }

        playbackTimer?.invalidate()

        // Check if we're resuming from a pause or starting fresh
        // Use pausedElapsedTime as primary indicator for resume (works for both BGM and metronome-only sessions)
        let isResuming = pausedElapsedTime > 0.0

        if isResuming {
            // When resuming, calculate and restore state based on elapsed time
            // For BGM sessions, use BGM position as source of truth
            // For metronome-only sessions, use pausedElapsedTime
            let actualElapsedTime: Double
            if let bgmPlayer = bgmPlayer, bgmPlayer.currentTime > 0 {
                Logger.audioPlayback("🎮 Resuming BGM playback from \(bgmPlayer.currentTime)s")
                // Convert audio time to timeline position (accounting for BGM offset)
                actualElapsedTime = bgmPlayer.currentTime + bgmOffsetSeconds
            } else {
                Logger.audioPlayback("🎮 Resuming metronome-only playback from \(pausedElapsedTime)s")
                actualElapsedTime = pausedElapsedTime
            }

            let secondsPerBeat = 60.0 / track.bpm
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
        } else {
            Logger.audioPlayback("🎮 Starting fresh playback")

            // Starting from beginning - reset all state
            resetPlaybackState()
            pausedElapsedTime = 0.0
        }

        // Calculate song start time accounting for paused elapsed time
        // This ensures InputManager timing calculations stay aligned after resume
        // InputManager computes elapsed time as: now - songStartTime
        // By subtracting pausedElapsedTime, we effectively set songStartTime to when playback originally started
        let adjustedSongStartTime = Date().addingTimeInterval(-pausedElapsedTime)
        playbackStartTime = adjustedSongStartTime

        if let startTime = playbackStartTime {
            inputManager.startListening(songStartTime: startTime)
        }

        startBGMPlayback(track: track)

        // Set playback state AFTER all operations succeed
        // This ensures UI state accurately reflects whether playback actually started
        isPlaying = true
    }

    func pausePlayback() {
        guard isPlaying else { return }
        isPlaying = false
        playbackTimer?.invalidate()
        playbackTimer = nil

        if let metronomeTime = metronome.getCurrentPlaybackTime() {
            pausedElapsedTime += metronomeTime
        } else if let startTime = playbackStartTime {
            pausedElapsedTime += Date().timeIntervalSince(startTime)
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
        playbackProgress = 1.0
        isPlaying = false
        playbackTimer?.invalidate()
        playbackTimer = nil
        playbackStartTime = nil
        pausedElapsedTime = 0.0
        bgmPlayer?.stop()
        metronome.stop()
        inputManager.stopListening()
        purpleBarPosition = nil
        Logger.audioPlayback("Skipped to end for track: \(track?.title ?? "Unknown")")
    }

    // MARK: - Cleanup

    func cleanup() {
        playbackTimer?.invalidate()
        playbackTimer = nil
        metronome.stop()
        metronome.onInterruption = nil
        bgmPlayer?.stop()
        bgmPlayer = nil
        inputManager.stopListening()
        metronomeSubscription?.cancel()
        metronomeSubscription = nil
    }

    // MARK: - Private Helpers

    private func resetPlaybackState() {
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
        purpleBarPosition = nil
    }

    private func startBGMPlayback(track: DrumTrack) {
        if let bgmPlayer = bgmPlayer {
            // Check if we're resuming from a pause
            let isResuming = pausedElapsedTime > 0.0

            // Resume BGM playback: player has current position and is not playing
            if bgmPlayer.currentTime > 0 && !bgmPlayer.isPlaying {
                Logger.audioPlayback("🎮 Resuming BGM at \(bgmPlayer.currentTime)s")
                // Use startAtTime with totalBeatsElapsed to preserve beat phase on resume
                let setupTime: TimeInterval = 0.05
                let commonStartTime = CFAbsoluteTimeGetCurrent() + setupTime
                metronome.startAtTime(
                    bpm: track.bpm,
                    timeSignature: track.timeSignature,
                    startTime: commonStartTime,
                    totalBeatsElapsed: totalBeatsElapsed
                )
                let bgmDeviceTime = convertToAudioPlayerDeviceTime(commonStartTime, bgmPlayer: bgmPlayer)
                bgmPlayer.play(atTime: bgmDeviceTime)
            } else if isResuming {
                // Resuming during initial silent offset period (BGM hasn't started yet)
                // Calculate remaining offset time and schedule accordingly
                Logger.audioPlayback("🎮 Resuming during BGM offset period")
                bgmPlayer.currentTime = 0
                let setupTime: TimeInterval = 0.05
                let commonStartTime = CFAbsoluteTimeGetCurrent() + setupTime

                // Use totalBeatsElapsed to preserve beat phase on resume
                metronome.startAtTime(
                    bpm: track.bpm,
                    timeSignature: track.timeSignature,
                    startTime: commonStartTime,
                    totalBeatsElapsed: totalBeatsElapsed
                )

                // Calculate remaining offset time (total offset minus elapsed time)
                let remainingOffset = max(0, bgmOffsetSeconds - pausedElapsedTime)
                let bgmDeviceTime = convertToAudioPlayerDeviceTime(commonStartTime, bgmPlayer: bgmPlayer)
                let bgmScheduledTime = bgmDeviceTime + remainingOffset
                bgmPlayer.play(atTime: bgmScheduledTime)
            } else {
                // Starting fresh BGM playback
                Logger.audioPlayback("🎮 Starting fresh BGM playback")
                bgmPlayer.currentTime = 0
                let setupTime: TimeInterval = 0.05
                let commonStartTime = CFAbsoluteTimeGetCurrent() + setupTime
                metronome.startAtTime(
                    bpm: track.bpm,
                    timeSignature: track.timeSignature,
                    startTime: commonStartTime
                )

                let bgmDeviceTime = convertToAudioPlayerDeviceTime(
                    commonStartTime,
                    bgmPlayer: bgmPlayer
                )
                let bgmScheduledTime = bgmDeviceTime + bgmOffsetSeconds
                bgmPlayer.play(atTime: bgmScheduledTime)
            }
        } else {
            // Metronome-only playback - preserve beat phase on resume
            if pausedElapsedTime > 0.0 {
                Logger.audioPlayback("🎮 Resuming metronome-only playback with beat offset")
                let setupTime: TimeInterval = 0.05
                let commonStartTime = CFAbsoluteTimeGetCurrent() + setupTime
                metronome.startAtTime(
                    bpm: track.bpm,
                    timeSignature: track.timeSignature,
                    startTime: commonStartTime,
                    totalBeatsElapsed: totalBeatsElapsed
                )
            } else {
                Logger.audioPlayback("🎮 Starting metronome-only playback")
                metronome.start(bpm: track.bpm, timeSignature: track.timeSignature)
            }
        }
    }

    private func convertToAudioPlayerDeviceTime(_ cfTime: CFAbsoluteTime, bgmPlayer: AVAudioPlayer) -> TimeInterval {
        let currentCFTime = CFAbsoluteTimeGetCurrent()
        let currentAudioTime = bgmPlayer.deviceCurrentTime
        let timeOffset = cfTime - currentCFTime
        return currentAudioTime + timeOffset
    }

    // MARK: - Visual Updates

    func updateVisualElementsFromMetronome() {
        guard let track = track, isPlaying else { return }

        // Guard: Ensure track duration is initialized to prevent division by zero
        guard cachedTrackDuration > 0 else {
            Logger.debug("⚠️ Skipping visual update: cachedTrackDuration not initialized yet")
            return
        }

        guard let metronomeTime = metronome.getCurrentPlaybackTime() else { return }
        let elapsedTime = pausedElapsedTime + metronomeTime

        let secondsPerBeat = 60.0 / track.bpm
        let totalBeatsElapsedFloat = elapsedTime / secondsPerBeat
        let discreteTotalBeats = Int(totalBeatsElapsedFloat)

        if discreteTotalBeats != lastDiscreteBeat {
            lastDiscreteBeat = discreteTotalBeats

            let beatsPerMeasure = track.timeSignature.beatsPerMeasure
            let measureIndex = discreteTotalBeats / beatsPerMeasure
            let beatWithinMeasure = discreteTotalBeats % beatsPerMeasure
            let beatPosition = Double(beatWithinMeasure) / Double(beatsPerMeasure)

            currentMeasureIndex = measureIndex
            currentBeatPosition = beatPosition
            currentBeat = findClosestBeatIndex(measureIndex: measureIndex, beatPosition: beatPosition)
            totalBeatsElapsed = discreteTotalBeats
            playbackProgress = min(elapsedTime / cachedTrackDuration, 1.0)

            updatePurpleBarPosition()
            updateActiveBeat()

            if playbackProgress >= 1.0 {
                handlePlaybackCompletion()
            }
        }
    }

    func updateActiveBeat() {
        guard let track = track, isPlaying else {
            activeBeatId = nil
            return
        }

        guard let elapsedTime = calculateElapsedTime() else {
            activeBeatId = nil
            return
        }

        let secondsPerBeat = 60.0 / track.bpm
        let totalBeatsElapsed = elapsedTime / secondsPerBeat
        let beatsPerMeasure = track.timeSignature.beatsPerMeasure

        let discreteTotalBeats = Int(totalBeatsElapsed)
        let measureIndex = discreteTotalBeats / beatsPerMeasure
        let beatWithinMeasure = Double(discreteTotalBeats % beatsPerMeasure)

        let currentTimePosition = Double(measureIndex) + (beatWithinMeasure / Double(beatsPerMeasure))
        let timeTolerance = 0.05

        for beat in cachedDrumBeats where abs(beat.timePosition - currentTimePosition) < timeTolerance {
            activeBeatId = beat.id
            return
        }
        activeBeatId = nil
    }

    func updatePurpleBarPosition() {
        purpleBarPosition = calculatePurpleBarPosition()
    }

    func calculatePurpleBarPosition() -> (x: Double, y: Double)? {
        guard let track = track, isPlaying else { return nil }
        guard let beatProgress = metronome.getCurrentBeatProgress() else { return nil }

        let beatsPerMeasure = track.timeSignature.beatsPerMeasure
        let discreteTotalBeats = Int(beatProgress.totalBeats)
        let measureIndex = discreteTotalBeats / beatsPerMeasure
        let beatWithinMeasure = Double(discreteTotalBeats % beatsPerMeasure)

        guard let measurePos = measurePositionMap[measureIndex] ?? measurePositionMap[0] else {
            return nil
        }

        let indicatorX = GameplayLayout.preciseNoteXPosition(
            measurePosition: measurePos,
            beatPosition: beatWithinMeasure,
            timeSignature: track.timeSignature
        )
        let staffCenterY = GameplayLayout.StaffLinePosition.line3.absoluteY(for: measurePos.row)

        return (x: Double(indicatorX), y: Double(staffCenterY))
    }

    func calculateElapsedTime() -> Double? {
        if let metronomeTime = metronome.getCurrentPlaybackTime() {
            return pausedElapsedTime + metronomeTime
        } else if isPlaying, let startTime = playbackStartTime {
            return pausedElapsedTime + Date().timeIntervalSince(startTime)
        }
        return nil
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
        resetPlaybackState()
        playbackStartTime = nil
        pausedElapsedTime = 0.0
        bgmPlayer?.stop()
        Logger.audioPlayback("Playback finished for track: \(track?.title ?? "Unknown")")
    }

    // MARK: - Computation Methods

    func computeDrumBeats() {
        if cachedNotes.isEmpty {
            cachedDrumBeats = []
            nextBeatId = 0  // Reset counter for consistency
            return
        }

        let groupedNotes = Dictionary(grouping: cachedNotes) { note in
            NotePositionKey(measureNumber: note.measureNumber, measureOffset: note.measureOffset)
        }

        cachedDrumBeats = groupedNotes.map { (positionKey, notes) in
            let timePosition = MeasureUtils.timePosition(
                measureNumber: positionKey.measureNumber,
                measureOffset: positionKey.measureOffset
            )
            let drumTypes = notes.compactMap { DrumType.from(noteType: $0.noteType) }
            let interval = notes.first?.interval ?? .quarter
            return DrumBeat(
                id: generateBeatId(),
                drums: drumTypes,
                timePosition: timePosition,
                interval: interval
            )
        }
        .sorted { $0.timePosition < $1.timePosition }

        cachedBeatIndices = Array(0..<cachedDrumBeats.count)
    }

    func computeCachedLayoutData() {
        guard let track = track else { return }

        let secondsPerBeat = 60.0 / track.bpm
        let secondsPerMeasure = secondsPerBeat * Double(track.timeSignature.beatsPerMeasure)

        let trackDurationInSeconds = calculateTrackDurationInSeconds(secondsPerMeasure: secondsPerMeasure)
        let totalMeasuresForDuration = Int(ceil(trackDurationInSeconds / secondsPerMeasure))
        let measuresCount = max(1, totalMeasuresForDuration)

        cachedMeasurePositions = GameplayLayout.calculateMeasurePositions(
            totalMeasures: measuresCount,
            timeSignature: track.timeSignature
        )

        cachedBeamGroups = BeamGroupingHelper.calculateBeamGroups(from: cachedDrumBeats)

        beatToBeamGroupMap = [:]
        for beamGroup in cachedBeamGroups {
            for beat in beamGroup.beats {
                beatToBeamGroupMap[beat.id] = beamGroup
            }
        }

        measurePositionMap = [:]
        for position in cachedMeasurePositions {
            measurePositionMap[position.measureIndex] = position
        }

        staticStaffLinesView = AnyView(StaffLinesBackgroundView(measurePositions: cachedMeasurePositions))

        if measurePositionMap[0] == nil {
            Logger.warning("Measure 0 missing from measurePositionMap! Creating fallback measure 0.")
            let measure0 = GameplayLayout.MeasurePosition(
                row: 0,
                xOffset: GameplayLayout.leftMargin,
                measureIndex: 0
            )
            measurePositionMap[0] = measure0
        }

        cacheBeatPositions()
    }

    func cacheBeatPositions() {
        guard let track = track else { return }

        cachedBeatPositions = [:]

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

        Logger.debug("Cached \(cachedBeatPositions.count) beat positions for performance optimization")
    }

    private func calculateTrackDurationInSeconds(secondsPerMeasure: Double) -> Double {
        if let song = cachedSong, !song.duration.isEmpty && song.duration != "0:00" {
            let components = song.duration.split(separator: ":")
            if components.count == 2,
               let minutes = Double(components[0]),
               let seconds = Double(components[1]) {
                return minutes * 60 + seconds
            }
        }

        let maxIndex = (cachedDrumBeats.map {
            MeasureUtils.measureIndex(from: $0.timePosition)
        }.max() ?? 0)
        let noteMeasures = max(1, maxIndex + 1)
        return Double(noteMeasures) * secondsPerMeasure
    }

    func calculateTrackDuration() -> Double {
        guard let track = track else { return 0.0 }

        let secondsPerBeat = 60.0 / track.bpm
        let secondsPerMeasure = secondsPerBeat * Double(track.timeSignature.beatsPerMeasure)

        return calculateTrackDurationInSeconds(secondsPerMeasure: secondsPerMeasure)
    }

    func calculateBGMOffset() -> Double {
        guard let track = track else { return 0.0 }

        let earliestNote = cachedNotes.min {
            $0.measureNumber < $1.measureNumber ||
            ($0.measureNumber == $1.measureNumber && $0.measureOffset < $1.measureOffset)
        }

        if let earliestNote = earliestNote,
           earliestNote.measureNumber > 1 || earliestNote.measureOffset > 0.0 {
            let secondsPerBeat = 60.0 / track.bpm
            let secondsPerMeasure = secondsPerBeat * Double(track.timeSignature.beatsPerMeasure)
            let noteTimeSeconds = Double(earliestNote.measureNumber - 1) * secondsPerMeasure +
                (earliestNote.measureOffset * secondsPerMeasure)
            return noteTimeSeconds
        }

        return 0.0
    }

    // MARK: - BGM Setup

    func setupBGMPlayer() {
        guard let song = cachedSong,
              let bgmFilePath = song.bgmFilePath,
              !bgmFilePath.isEmpty else {
            Logger.audioPlayback("No BGM file available for track: \(track?.title ?? "Unknown")")
            return
        }

        let bgmURL = URL(fileURLWithPath: bgmFilePath)

        do {
            bgmPlayer = try AVAudioPlayer(contentsOf: bgmURL)
            bgmPlayer?.prepareToPlay()
            bgmPlayer?.volume = 0.7
            Logger.audioPlayback("BGM player setup successful for track: \(track?.title ?? "Unknown")")
        } catch {
            bgmLoadingError = "Failed to load BGM: \(error.localizedDescription)"
            Logger.audioPlayback("Failed to setup BGM player: \(error.localizedDescription)")
        }
    }
}
