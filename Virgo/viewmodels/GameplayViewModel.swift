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
    let practiceSettings: PracticeSettingsService
    private var lastAppliedSpeedMultiplier: Double

    // MARK: - Speed Change Debounce
    /// Timestamp of last speed change application (diagnostic only)
    private var lastSpeedChangeTimestamp: Date?
    /// Minimum interval between speed change applications
    private let speedChangeDebounceInterval: TimeInterval = 0.1
    /// Pending speed change timer for trailing-edge debounce
    private var speedChangeTimer: Timer?
    /// Latest pending speed value waiting to be applied
    private var latestPendingSpeed: Double?

    // MARK: - Row Width Resize Debounce
    /// Minimum interval between row-width layout rebuilds
    private let rowWidthDebounceInterval: TimeInterval = 0.1
    /// Pending resize timer for trailing-edge debounce
    var rowWidthTimer: Timer?

    // MARK: - Cached SwiftData Relationships
    /// Cached song to avoid main thread blocking from relationship access
    var cachedSong: Song?
    /// Cached notes array to avoid relationship access during rendering
    var cachedNotes: [Note] = []
    /// Flag indicating whether async data loading is complete
    var isDataLoaded = false
    /// Flag indicating whether gameplay-derived layout/audio state has been prepared.
    var isGameplayPrepared = false
    /// Flag indicating whether the chart's persisted speed was loaded (prevents saving before load)
    private var hasLoadedPersistedSpeed = false

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
    /// Timer reference retained for cleanup during state transitions (periodic updates driven by metronome callbacks)
    var playbackTimer: Timer?
    private let playbackProgressPublishInterval: TimeInterval = 0.1
    private var lastPlaybackProgressPublishElapsedTime: Double?
    /// Playback start time for timing calculations
    var playbackStartTime: Date?
    /// Accumulated elapsed time when paused
    var pausedElapsedTime: Double = 0.0
    /// The CFAbsoluteTime at which the metronome/BGM were last scheduled to start.
    /// Used to synchronize input timing with actual audio playback so hits are
    /// judged relative to what the player hears, not when startPlayback() was called.
    private(set) var lastScheduledPlaybackStartTime: CFAbsoluteTime?
    /// Host clock (`mach_absolute_time()`) captured at the same instant as
    /// `lastScheduledPlaybackStartTime` so the input manager can project its
    /// zero-point forward without drift from intervening main-thread work.
    private var lastScheduledPlaybackHostTime: UInt64?

    // MARK: - Cached Layout Data
    /// Pre-computed drum beats from notes
    private(set) var cachedDrumBeats: [DrumBeat] = []
    /// Pre-computed measure positions for layout
    private(set) var cachedMeasurePositions: [GameplayLayout.MeasurePosition] = []
    /// Cached track duration in seconds
    private(set) var cachedTrackDuration: Double = 0.0
    /// Cached beat indices for iteration
    private(set) var cachedBeatIndices: [Int] = []
    /// Fast lookup map from measure index to position
    private(set) var measurePositionMap: [Int: GameplayLayout.MeasurePosition] = [:]
    /// Pre-cached beat positions for performance
    private(set) var cachedBeatPositions: [UInt64: (x: Double, y: Double)] = [:]
    /// Pre-computed notation layout that drives rendering when notes are present
    private(set) var cachedNotationLayout = NotationLayout.empty
    /// Fast lookup from measure index to row for the notation layout path.
    private(set) var cachedMeasureRowMap: [Int: Int] = [:]
    /// Fast lookup map from rendered note-head ID to rendered position
    private(set) var cachedNotationNoteHeadPositions: [UInt64: (x: Double, y: Double)] = [:]
    /// Maps legacy DrumBeat IDs to all rendered note heads at the same musical time.
    private(set) var cachedNotationNoteHeadIDsByBeatID: [UInt64: [UInt64]] = [:]
    /// Duration-based measure count shared with both legacy sheet layout and notation layout.
    private var cachedLayoutMeasureCount = 1
    /// Available row width, fed from the sheet music view's GeometryProxy. Falls back
    /// to the legacy 900pt cap so layouts built before any geometry is observed behave
    /// the way they always have. Use `updateRowWidth(_:)` to set this from the view.
    var cachedLayoutRowWidth: CGFloat = GameplayLayout.maxRowWidth
    /// Preserves the legacy grouping key that produced each DrumBeat ID.
    private var cachedDrumBeatIDByNotePositionKey: [NotePositionKey: UInt64] = [:]

    // MARK: - Visual State
    /// Currently active beat ID for highlighting
    var activeBeatId: UInt64? {
        didSet {
            guard oldValue != activeBeatId else { return }
            // Clear active note heads when beat changes (self-enforcing invariant)
            activeNotationNoteHeadIDs = []
        }
    }
    private(set) var activeNotationNoteHeadIDs: Set<UInt64> = []
    /// Current purple bar position (x, y)
    var purpleBarPosition: (x: Double, y: Double)?
    /// Row index of the staff currently containing the playhead. Drives auto-scroll
    /// of the sheet music ScrollView so the active row stays visible during playback.
    var currentRow: Int = 0
    /// Cached static staff lines view (uses AnyView for type erasure)
    var staticStaffLinesView: AnyView?
    /// Cached notation-path staff lines view (width matches notation content width)
    var notationStaffLinesView: AnyView?

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
    /// Whether to show the selected MIDI device alert
    var isShowingMIDIDeviceAlert = false
    /// User-facing message for MIDI source gating / disconnects
    var midiDeviceAlertMessage = ""
    private var shouldGateGameplayOnSelectedMIDISource: Bool {
        inputManager.requiresMIDISourceForGameplay
    }

    // MARK: - Scoring State
    /// All combo and scoring state
    var scoreEngine = ScoreEngine()
    var liveScoreSnapshot: LiveScoreSnapshot {
        LiveScoreSnapshot(scoreEngine: scoreEngine)
    }
    /// Snapshot of scoreEngine captured at session end before resetScoring clears it.
    /// Retained for test observability of raw timing deviations (not exposed in LiveScoreSnapshot).
    /// Production code reads sessionScoreSnapshot; remove once snapshot exposes deviation detail.
    var sessionScoreEngine = ScoreEngine()
    /// Snapshot captured at session end before resetScoring clears live state.
    var sessionScoreSnapshot = LiveScoreSnapshot.empty
    /// The save outcome from the most recent handlePlaybackCompletion, passed to
    /// SessionResultsView so the NEW HIGH SCORE badge only appears when the write
    /// actually succeeded, and a "not saved" banner can surface save failures.
    var sessionRecordResult: ScorePersistenceService.RecordResult = .recorded
    /// Whether the session results sheet is visible
    var isShowingSessionResults: Bool = false
    /// Non-nil for one render cycle to drive milestone animation (10/25/50/100)
    var showMilestoneAnimation: Bool = false
    /// Retained handle for the delayed milestone-animation reset; cancelled before
    /// retriggering so a rapid second milestone cannot be cut short by the first task.
    private var milestoneAnimationTask: Task<Void, Never>?
    /// True briefly after a combo break to drive visual feedback
    var showComboBreakFeedback: Bool = false
    /// Retained handle for the delayed combo-break-feedback reset; same rationale as
    /// milestoneAnimationTask — cancels the old timer before starting a new one.
    private var comboBreakFeedbackTask: Task<Void, Never>?
    /// Notes already scored via explicit hit — skipped by missed-note scan
    private var scoredNoteIDs: Set<ObjectIdentifier> = []
    /// Notes sorted by ascending time position; built once after data load.
    /// Enables the missed-note scan to walk forward without re-scanning the full list.
    private var sortedNotesByTimePosition: [Note] = []
    /// Cursor into sortedNotesByTimePosition; advanced forward-only each scan tick.
    /// Avoids O(totalNotes) scan on every metronome callback (now O(new notes)).
    private var missedNoteScanCursor: Int = 0
    /// High-water mark for missed-note scan (timePosition units)
    private var lastScannedTimePosition: Double = 0.0

    // MARK: - Completion Scheduling
    /// Whether playback completion has been scheduled (prevents double-scheduling during grace period)
    private var completionScheduled = false
    /// Task for delayed completion to allow late-tolerance window for final notes
    var completionTask: Task<Void, Never>?

    // MARK: - Score Persistence
    let scorePersistence: ScorePersistenceService

    /// True only while the current run has been at 1.0x speed for its entire
    /// duration. Gates all-time best eligibility.
    var sessionAtFullSpeed: Bool = true

    // MARK: - Haptic Generators (iOS only)
    #if os(iOS)
    private let hitHapticGenerator = UIImpactFeedbackGenerator(style: .light)
    private let comboBreakHapticGenerator = UINotificationFeedbackGenerator()
    #endif

    // MARK: - Subscriptions
    /// Metronome beat subscription for visual sync
    var metronomeSubscription: AnyCancellable?

    // MARK: - Initialization

    @MainActor
    init(
        chart: Chart,
        metronome: MetronomeEngine,
        practiceSettings: PracticeSettingsService,
        scorePersistence: ScorePersistenceService
    ) {
        self.chart = chart
        self.metronome = metronome
        self.practiceSettings = practiceSettings
        self.scorePersistence = scorePersistence
        self.lastAppliedSpeedMultiplier = practiceSettings.speedMultiplier
    }

    @MainActor
    convenience init(chart: Chart, metronome: MetronomeEngine, practiceSettings: PracticeSettingsService) {
        self.init(
            chart: chart, metronome: metronome, practiceSettings: practiceSettings,
            scorePersistence: ScorePersistenceService.makeInMemory()
        )
    }

    #if DEBUG
    @MainActor
    convenience init(chart: Chart, metronome: MetronomeEngine) {
        let ps = PracticeSettingsService()
        self.init(
            chart: chart, metronome: metronome, practiceSettings: ps,
            scorePersistence: ScorePersistenceService.makeInMemory()
        )
    }
    #endif

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

    private func elapsedBeatsForScheduling(effectiveBPM: Double) -> Double {
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
            let beatOffset = Int(elapsedBeats)
            totalBeatsElapsed = beatOffset
            metronome.stop()
            let capturedHostTime = mach_absolute_time()
            lastScheduledPlaybackHostTime = capturedHostTime
            let scheduledStartTime = CFAbsoluteTimeGetCurrent() + 0.05
            lastScheduledPlaybackStartTime = scheduledStartTime
            metronome.startAtTime(
                bpm: effectiveBPMValue,
                timeSignature: track?.timeSignature ?? .fourFour,
                startTime: scheduledStartTime,
                totalBeatsElapsed: elapsedBeats
            )
            rescheduleBGMForSpeedChange(commonStartTime: scheduledStartTime)
        } else {
            if previousSpeed > 0, currentSpeed > 0 {
                let speedRatio = previousSpeed / currentSpeed
                pausedElapsedTime *= speedRatio
            }
            let elapsedBeats = elapsedBeatsForScheduling(effectiveBPM: effectiveBPMValue)
            let beatOffset = Int(elapsedBeats)
            totalBeatsElapsed = beatOffset
            metronome.stop()
            let capturedHostTime = mach_absolute_time()
            lastScheduledPlaybackHostTime = capturedHostTime
            let scheduledStartTime = CFAbsoluteTimeGetCurrent() + 0.05
            lastScheduledPlaybackStartTime = scheduledStartTime
            metronome.startAtTime(
                bpm: effectiveBPMValue,
                timeSignature: track?.timeSignature ?? .fourFour,
                startTime: scheduledStartTime,
                totalBeatsElapsed: elapsedBeats
            )
            rescheduleBGMForSpeedChange(commonStartTime: scheduledStartTime)
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

    // MARK: - Unique ID Generation
    /// Monotonic counter for generating unique DrumBeat IDs
    private var nextBeatId: UInt64 = 0

    /// Generate a unique ID for a DrumBeat
    private func generateBeatId() -> UInt64 {
        defer { nextBeatId += 1 }
        return nextBeatId
    }

    // MARK: - Data Loading

    /// Loads SwiftData relationships asynchronously to avoid blocking main thread
    func loadChartData() async {
        isGameplayPrepared = false
        cachedSong = chart.song
        cachedNotes = chart.notes.map { $0 }
        // Pre-sort notes by time position once so scanForMissedNotes can advance
        // a forward-only cursor instead of re-walking the full list each tick.
        sortedNotesByTimePosition = cachedNotes.sorted {
            MeasureUtils.timePosition(measureNumber: $0.measureNumber, measureOffset: $0.measureOffset)
            < MeasureUtils.timePosition(measureNumber: $1.measureNumber, measureOffset: $1.measureOffset)
        }

        if cachedSong == nil {
            Logger.error("loadChartData: chart.song relationship returned nil")
        }
        if cachedNotes.isEmpty {
            Logger.warning("loadChartData: chart.notes returned empty array - chart may have no notes or relationship failed to load")
        }

        track = DrumTrack(chart: chart)
        isDataLoaded = true
    }

    // MARK: - Setup

    /// Sets up gameplay after data is loaded
    /// - Parameter loadPersistedSpeed: Whether to load the saved speed for this chart.
    ///   Pass `false` to use a preconfigured speed instead of the saved value.
    ///   Defaults to `true` to load saved speed (SC-06: Remember last-used speed).
    func setupGameplay(loadPersistedSpeed: Bool = true) {
        isGameplayPrepared = false
        guard let track = track else {
            Logger.error("setupGameplay() called but track is nil - data not loaded yet")
            return
        }

        let isUITesting = ProcessInfo.processInfo.arguments.contains(LaunchArguments.uiTesting)
        if !TestEnvironment.isRunningTests && !isUITesting {
            #if os(iOS)
            inputManager.requiresMIDISourceForGameplay = true
            #else
            inputManager.requiresMIDISourceForGameplay = false
            #endif
        }

        // Load saved speed for this chart unless caller explicitly requested preconfigured speed
        if loadPersistedSpeed {
            practiceSettings.loadAndApplySpeed(for: chart.persistentModelID)
            lastAppliedSpeedMultiplier = practiceSettings.speedMultiplier
            // Only set the flag when we actually load a persisted speed
            // This ensures cleanup() doesn't save before persisted speed is loaded
            hasLoadedPersistedSpeed = true
        }

        computeDrumBeats()
        computeCachedLayoutData()
        setupBGMPlayer()
        // Apply clamped speed if BGM minimum enforcement returns a value
        if let clampedSpeed = enforceBGMMinimumSpeedIfNeeded() {
            practiceSettings.setSpeed(clampedSpeed)
            // Update the baseline to reflect the effective speed actually in use
            // This ensures subsequent live speed changes calculate correct ratios
            lastAppliedSpeedMultiplier = clampedSpeed
        }
        refreshTimingCaches()
        // Use effective BPM (base × speed multiplier) for metronome
        metronome.configure(bpm: effectiveBPM(), timeSignature: track.timeSignature)
        // InputManager should use effective BPM so scoring matches playback speed
        inputManager.configure(bpm: effectiveBPM(), timeSignature: track.timeSignature, notes: cachedNotes)
        setupInterruptionHandling()
        isGameplayPrepared = true
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
        // progress and row scrolling responsive between quarter-note metronome callbacks.
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
        clearActiveBeat()
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
        lastPlaybackProgressPublishElapsedTime = nil
        purpleBarPosition = nil
        currentRow = 0
        clearActiveBeat()
        lastScheduledPlaybackStartTime = nil
        lastScheduledPlaybackHostTime = nil
        resetScoring()
    }

    private func refreshTimingCaches() {
        guard isDataLoaded, track != nil else { return }
        bgmOffsetSeconds = calculateBGMOffset()
        cachedTrackDuration = calculateTrackDuration()
    }

    /// Returns the clamped speed if BGM is present and speed is below minimum, nil otherwise.
    /// Returns value instead of calling setSpeed directly, preventing .onChange re-entry.
    private func enforceBGMMinimumSpeedIfNeeded() -> Double? {
        guard bgmPlayer != nil else { return nil }
        let minimumSpeed = 0.5
        if practiceSettings.speedMultiplier < minimumSpeed {
            Logger.warning("BGM enabled - clamping speed to 50% to keep audio in sync")
            return minimumSpeed
        }
        return nil
    }

    private func startBGMPlayback(track: DrumTrack) {
        let currentEffectiveBPM = effectiveBPM()
        let currentSpeedMultiplier = practiceSettings.speedMultiplier

        if let bgmPlayer = bgmPlayer {
            bgmPlayer.enableRate = true
            bgmPlayer.rate = clampedBGMRate(for: currentSpeedMultiplier)

            let isResuming = pausedElapsedTime > 0.0

            if bgmPlayer.currentTime > 0 && !bgmPlayer.isPlaying {
                lastScheduledPlaybackStartTime = resumeBGMFromPosition(track: track, bgmPlayer: bgmPlayer, effectiveBPM: currentEffectiveBPM)
            } else if isResuming {
                lastScheduledPlaybackStartTime = resumeBGMDuringOffset(track: track, bgmPlayer: bgmPlayer, effectiveBPM: currentEffectiveBPM)
            } else {
                lastScheduledPlaybackStartTime = startFreshBGMPlayback(track: track, bgmPlayer: bgmPlayer, effectiveBPM: currentEffectiveBPM)
            }
        } else {
            lastScheduledPlaybackStartTime = startMetronomeOnlyPlayback(track: track, effectiveBPM: currentEffectiveBPM)
        }
    }

    @discardableResult
    private func resumeBGMFromPosition(track: DrumTrack, bgmPlayer: AVAudioPlayer, effectiveBPM: Double) -> CFAbsoluteTime {
        Logger.audioPlayback("🎮 Resuming BGM at \(bgmPlayer.currentTime)s")
        let setupTime: TimeInterval = 0.05
        let capturedHostTime = mach_absolute_time()
        lastScheduledPlaybackHostTime = capturedHostTime
        let commonStartTime = CFAbsoluteTimeGetCurrent() + setupTime
        metronome.startAtTime(
            bpm: effectiveBPM,
            timeSignature: track.timeSignature,
            startTime: commonStartTime,
            totalBeatsElapsed: elapsedBeatsForScheduling(effectiveBPM: effectiveBPM)
        )
        let bgmDeviceTime = convertToAudioPlayerDeviceTime(commonStartTime, bgmPlayer: bgmPlayer)
        if !bgmPlayer.play(atTime: bgmDeviceTime) {
            Logger.error("BGM play(atTime:) failed during resume from position")
        }
        return commonStartTime
    }

    @discardableResult
    private func resumeBGMDuringOffset(track: DrumTrack, bgmPlayer: AVAudioPlayer, effectiveBPM: Double) -> CFAbsoluteTime {
        Logger.audioPlayback("🎮 Resuming during BGM offset period")
        bgmPlayer.currentTime = 0
        let setupTime: TimeInterval = 0.05
        let capturedHostTime = mach_absolute_time()
        lastScheduledPlaybackHostTime = capturedHostTime
        let commonStartTime = CFAbsoluteTimeGetCurrent() + setupTime

        metronome.startAtTime(
            bpm: effectiveBPM,
            timeSignature: track.timeSignature,
            startTime: commonStartTime,
            totalBeatsElapsed: elapsedBeatsForScheduling(effectiveBPM: effectiveBPM)
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
    private func startFreshBGMPlayback(track: DrumTrack, bgmPlayer: AVAudioPlayer, effectiveBPM: Double) -> CFAbsoluteTime {
        Logger.audioPlayback("🎮 Starting fresh BGM playback")
        bgmPlayer.currentTime = 0
        let setupTime: TimeInterval = 0.05
        let capturedHostTime = mach_absolute_time()
        lastScheduledPlaybackHostTime = capturedHostTime
        let commonStartTime = CFAbsoluteTimeGetCurrent() + setupTime
        metronome.startAtTime(
            bpm: effectiveBPM,
            timeSignature: track.timeSignature,
            startTime: commonStartTime
        )

        let bgmDeviceTime = convertToAudioPlayerDeviceTime(commonStartTime, bgmPlayer: bgmPlayer)
        let bgmScheduledTime = bgmDeviceTime + bgmOffsetSeconds
        if !bgmPlayer.play(atTime: bgmScheduledTime) {
            Logger.error("BGM play(atTime:) failed during fresh playback start")
        }
        return commonStartTime
    }

    @discardableResult
    private func startMetronomeOnlyPlayback(track: DrumTrack, effectiveBPM: Double) -> CFAbsoluteTime {
        if pausedElapsedTime > 0.0 {
            Logger.audioPlayback("🎮 Resuming metronome-only playback with beat offset")
            let setupTime: TimeInterval = 0.05
            let capturedHostTime = mach_absolute_time()
            lastScheduledPlaybackHostTime = capturedHostTime
            let commonStartTime = CFAbsoluteTimeGetCurrent() + setupTime
            metronome.startAtTime(
                bpm: effectiveBPM,
                timeSignature: track.timeSignature,
                startTime: commonStartTime,
                totalBeatsElapsed: elapsedBeatsForScheduling(effectiveBPM: effectiveBPM)
            )
            return commonStartTime
        } else {
            Logger.audioPlayback("🎮 Starting metronome-only playback")
            // Fresh metronome start uses scheduled timing (setupTime delay) to match BGM cases,
            // ensuring inputManager.startListening is called before audio actually begins.
            let setupTime: TimeInterval = 0.05
            let capturedHostTime = mach_absolute_time()
            lastScheduledPlaybackHostTime = capturedHostTime
            let startTime = CFAbsoluteTimeGetCurrent() + setupTime
            metronome.startAtTime(
                bpm: effectiveBPM,
                timeSignature: track.timeSignature,
                startTime: startTime
            )
            return startTime
        }
    }

    private func convertToAudioPlayerDeviceTime(_ cfTime: CFAbsoluteTime, bgmPlayer: AVAudioPlayer) -> TimeInterval {
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

    // MARK: - Visual Updates

    /// Starts a ~30 Hz timer that continuously updates playback progress, row
    /// scrolling, and beat-boundary playhead movement between metronome callbacks.
    /// The purple playhead itself is quantized to beat boundaries to avoid
    /// forcing sheet re-layout on every timer tick.
    /// Skipped in test environments to avoid interfering with the test runner's
    /// main run loop (matches the pattern used by audio components).
    private func startVisualTickTimer() {
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
                let gracePeriodNs = UInt64(TimingAccuracy.good.toleranceMs * 1_000_000)
                completionTask = Task { @MainActor [weak self] in
                    // Sleep the full late-tolerance window so that hits arriving
                    // between ~0–100ms after the last note can still be scored via
                    // recordHit before we auto-miss and finalize.
                    // Do NOT scan during the sleep: passing .infinity to
                    // scanForMissedNotes on every tick would mark all remaining
                    // notes missed immediately on the first iteration.
                    do {
                        try await Task.sleep(nanoseconds: gracePeriodNs)
                    } catch {
                        return // cancelled
                    }
                    guard !Task.isCancelled else { return }
                    // Grace period elapsed — mark any still-unscored notes missed,
                    // then finalize the session.
                    self?.scanForMissedNotes(upToTimePosition: .infinity)
                    self?.handlePlaybackCompletion()
                }
            }
        }
    }

    func updateActiveBeat(forTimePosition providedTimePosition: Double? = nil) {
        guard let track = track, isPlaying else {
            clearActiveBeat()
            return
        }

        let currentTimePosition: Double

        if let providedTimePosition {
            currentTimePosition = providedTimePosition
        } else {
            guard let elapsedTime = calculateElapsedTime() else {
                clearActiveBeat()
                return
            }
            // Use effective BPM for visual sync (speed-adjusted)
            let secondsPerBeat = 60.0 / effectiveBPM()
            let totalBeats = elapsedTime / secondsPerBeat
            let beatsPerMeasure = Double(track.timeSignature.beatsPerMeasure)
            let continuousMeasureFraction = max(0, totalBeats / beatsPerMeasure)
            let measureIdx = Int(continuousMeasureFraction)
            let measureOffset = continuousMeasureFraction - Double(measureIdx)
            currentTimePosition = Double(measureIdx) + measureOffset
        }

        // Two-step search: prefer beats at/before the playhead, then fall back to
        // a small look-ahead.  The metronome only fires at quarter-note intervals,
        // so sub-beat notes (eighths, sixteenths) are never exactly at the playhead.
        // Using look-ahead catches those, but we must not let a future note steal
        // the active-beat slot from a note the playhead is currently on.
        let lookAhead = 0.05
        let maxLookBehind = 1.0 / Double(track.timeSignature.beatsPerMeasure)

        // Step 1: find the last beat at or before the playhead.
        if let index = lastBeatIndex(atOrBefore: currentTimePosition, lookAhead: 0) {
            let beat = cachedDrumBeats[index]
            if currentTimePosition - beat.timePosition <= maxLookBehind {
                activeBeatId = beat.id
                updateActiveNotation(forBeatID: beat.id, fallbackTimePosition: currentTimePosition)
                return
            }
        }

        // Step 2: no beat at/before playhead — try a small look-ahead for
        // sub-beat notes that the playhead is about to reach.
        // Find the NEAREST upcoming note (first after the playhead), not the
        // farthest note in the look-ahead window.
        if let index = firstBeatIndex(atOrAfter: currentTimePosition, within: lookAhead) {
            let beat = cachedDrumBeats[index]
            if currentTimePosition - beat.timePosition <= maxLookBehind {
                activeBeatId = beat.id
                updateActiveNotation(forBeatID: beat.id, fallbackTimePosition: currentTimePosition)
                return
            }
        }

        clearActiveBeat()
    }

    /// Performs binary search over cachedDrumBeats to find the last beat at or before
    /// (timePosition + lookAhead).
    private func lastBeatIndex(atOrBefore timePosition: Double, lookAhead: Double = 0.0) -> Int? {
        guard !cachedDrumBeats.isEmpty else { return nil }

        var left = 0
        var right = cachedDrumBeats.count - 1
        var result = -1

        let target = timePosition + lookAhead

        while left <= right {
            let mid = (left + right) / 2
            if cachedDrumBeats[mid].timePosition <= target {
                result = mid
                left = mid + 1
            } else {
                right = mid - 1
            }
        }

        return result >= 0 ? result : nil
    }

    /// Performs binary search over cachedDrumBeats to find the first beat at or after
    /// `timePosition` that is also within `maxDistance` of it.
    /// Used by the look-ahead branch to select the nearest upcoming note.
    private func firstBeatIndex(atOrAfter timePosition: Double, within maxDistance: Double) -> Int? {
        guard !cachedDrumBeats.isEmpty else { return nil }

        // Lower-bound binary search: first index where timePosition >= threshold.
        var left = 0
        var right = cachedDrumBeats.count
        while left < right {
            let mid = (left + right) / 2
            if cachedDrumBeats[mid].timePosition < timePosition {
                left = mid + 1
            } else {
                right = mid
            }
        }

        guard left < cachedDrumBeats.count else { return nil }
        let candidate = cachedDrumBeats[left]
        guard candidate.timePosition - timePosition <= maxDistance else { return nil }
        return left
    }

    func updateActiveNotation(forTimePosition timePosition: Double) {
        let key = NotationLayout.timePositionKey(timePosition)
        activeNotationNoteHeadIDs = cachedNotationLayout.noteHeadIDsByTimePosition[key] ?? []
    }

    private func updateActiveNotation(forBeatID beatID: UInt64, fallbackTimePosition: Double) {
        let noteHeadIDs = Set(cachedNotationNoteHeadIDsByBeatID[beatID] ?? [])
        if noteHeadIDs.isEmpty {
            updateActiveNotation(forTimePosition: fallbackTimePosition)
        } else {
            activeNotationNoteHeadIDs = noteHeadIDs
        }
    }

    private func clearActiveBeat() {
        activeBeatId = nil
        activeNotationNoteHeadIDs = []
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
        guard let measure = cachedNotationLayout.measures.first(where: { $0.measureIndex == measureIndex }) else {
            return nil
        }

        let drawableWidth = measure.width - GameplayLayout.barLineWidth - GameplayLayout.uniformSpacing
        let beatGap = drawableWidth / CGFloat(track.timeSignature.beatsPerMeasure)
        let indicatorX = measure.xOffset
            + GameplayLayout.barLineWidth
            + GameplayLayout.uniformSpacing
            + CGFloat(beatWithinMeasure) * beatGap
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

    private func currentBGMPlaybackElapsedTime() -> Double? {
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

    // MARK: - Computation Methods

    func computeDrumBeats() {
        if cachedNotes.isEmpty {
            cachedDrumBeats = []
            cachedDrumBeatIDByNotePositionKey = [:]
            nextBeatId = 0  // Reset counter for consistency
            return
        }

        let groupedNotes = Dictionary(grouping: cachedNotes) { note in
            NotePositionKey(measureNumber: note.measureNumber, measureOffset: note.measureOffset).normalized()
        }

        cachedDrumBeatIDByNotePositionKey = [:]
        cachedDrumBeats = groupedNotes.map { (positionKey, notes) in
            let beatID = generateBeatId()
            let timePosition = MeasureUtils.timePosition(
                measureNumber: positionKey.measureNumber,
                measureOffset: positionKey.measureOffset
            )
            let drumTypes = notes.compactMap { DrumType.from(noteType: $0.noteType) }
            let interval = notes.first?.interval ?? .quarter
            cachedDrumBeatIDByNotePositionKey[positionKey] = beatID
            return DrumBeat(
                id: beatID,
                drums: drumTypes,
                timePosition: timePosition,
                interval: interval
            )
        }
        .sorted { $0.timePosition < $1.timePosition }

        cachedBeatIndices = Array(0..<cachedDrumBeats.count)
    }

    func computeCachedLayoutData() {
        guard let track = track else {
            cacheNotationLayout()
            return
        }

        let secondsPerBeat = 60.0 / track.bpm
        let secondsPerMeasure = secondsPerBeat * Double(track.timeSignature.beatsPerMeasure)

        let trackDurationInSeconds = calculateTrackDurationInSeconds(secondsPerMeasure: secondsPerMeasure)
        let totalMeasuresForDuration = Int(ceil(trackDurationInSeconds / secondsPerMeasure))
        let measuresCount = max(1, totalMeasuresForDuration)
        cachedLayoutMeasureCount = measuresCount

        cachedMeasurePositions = GameplayLayout.calculateMeasurePositions(
            totalMeasures: measuresCount,
            timeSignature: track.timeSignature
        )

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

        cacheNotationLayout()
        cacheBeatPositions()
    }

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

        // Apply immediately in tests for deterministic behavior
        if TestEnvironment.isRunningTests {
            cachedLayoutRowWidth = width
            cacheNotationLayout()
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
            }
        }
    }

    func cacheNotationLayout() {
        guard let track = track else {
            cachedNotationLayout = .empty
            cachedNotationNoteHeadPositions = [:]
            cachedNotationNoteHeadIDsByBeatID = [:]
            cachedMeasureRowMap = [:]
            notationStaffLinesView = nil
            activeNotationNoteHeadIDs = []
            return
        }

        // Use default positions in tests to avoid reading developer's local
        // UserDefaults overrides, which would make layout non-deterministic
        // across contributor machines.  Position overrides are independently
        // tested in DrumNotationSettingsManager unit tests.
        let notePositionOverrides: [DrumType: GameplayLayout.NotePosition]
        if TestEnvironment.isRunningTests {
            notePositionOverrides = Dictionary(
                uniqueKeysWithValues: DrumType.allCases.map { ($0, $0.notePosition) }
            )
        } else {
            notePositionOverrides = DrumNotationSettingsManager.loadPositions()
        }

        let resolvedRowWidth = max(GameplayLayout.maxRowWidth, cachedLayoutRowWidth)
        let style = NotationLayoutStyle.gameplayDefault.with(rowWidth: resolvedRowWidth)
        let input = NotationLayoutInput(
            notes: cachedNotes,
            timeSignature: track.timeSignature,
            minimumMeasureCount: cachedLayoutMeasureCount,
            style: style,
            notePositionOverrides: notePositionOverrides
        )
        cachedNotationLayout = NotationLayoutEngine().layout(input: input)
        cachedMeasureRowMap = Dictionary(
            uniqueKeysWithValues: cachedNotationLayout.measures.map { ($0.measureIndex, $0.row) }
        )

        if !cachedNotationLayout.noteHeads.isEmpty {
            let notationMeasurePositions = cachedNotationLayout.measures.map { measure in
                GameplayLayout.MeasurePosition(
                    row: measure.row,
                    xOffset: measure.xOffset,
                    measureIndex: measure.measureIndex
                )
            }
            let contentWidth = cachedNotationLayout.contentWidth
            notationStaffLinesView = AnyView(
                StaffLinesBackgroundView(measurePositions: notationMeasurePositions, width: contentWidth)
            )
        } else {
            notationStaffLinesView = nil
        }

        if cachedNotes.count != cachedNotationLayout.noteHeads.count, !cachedNotes.isEmpty {
            let renderedSourceIDs = Set(cachedNotationLayout.noteHeads.map { $0.sourceNoteID })
            let droppedNotes = cachedNotes.filter { !renderedSourceIDs.contains(ObjectIdentifier($0)) }
            let droppedReasons = droppedNotes.prefix(5).map { note in
                let drumType = DrumType.from(noteType: note.noteType)
                let measureIdx = MeasureUtils.measureIndex(from: MeasureUtils.timePosition(
                    measureNumber: note.measureNumber, measureOffset: note.measureOffset
                ))
                return "noteType=\(note.noteType)(\(drumType?.description ?? "unknown")), " +
                        "measure=\(note.measureNumber)(idx=\(measureIdx))"
            }
            Logger.warning(
                "Layout engine dropped \(droppedNotes.count) note(s): \(droppedReasons.joined(separator: "; "))"
                    + (droppedNotes.count > 5 ? " … and \(droppedNotes.count - 5) more" : "")
            )
        }

        cachedNotationNoteHeadPositions = Dictionary(
            uniqueKeysWithValues: cachedNotationLayout.noteHeadPositionsByID.map { noteHeadID, position in
                (noteHeadID, (x: Double(position.x), y: Double(position.y)))
            }
        )
        var notePositionKeyBySourceNoteID: [ObjectIdentifier: NotePositionKey] = [:]
        for note in cachedNotes {
            let key = ObjectIdentifier(note)
            let positionKey = NotePositionKey(measureNumber: note.measureNumber, measureOffset: note.measureOffset).normalized()
            if notePositionKeyBySourceNoteID[key] != nil {
                Logger.warning(
                    "Duplicate ObjectIdentifier for Note(measure:\(note.measureNumber), " +
                    "offset:\(note.measureOffset)) — SwiftData faulting returned identical instance"
                )
            }
            notePositionKeyBySourceNoteID[key] = positionKey
        }
        var noteHeadIDsByBeatID = Dictionary(uniqueKeysWithValues: cachedDrumBeats.map { ($0.id, [UInt64]()) })
        var desyncCount = 0
        for noteHead in cachedNotationLayout.noteHeads {
            guard let positionKey = notePositionKeyBySourceNoteID[noteHead.sourceNoteID],
                  let beatID = cachedDrumBeatIDByNotePositionKey[positionKey] else {
                desyncCount += 1
                continue
            }
            noteHeadIDsByBeatID[beatID, default: []].append(noteHead.id)
        }
        if desyncCount > 0 {
            Logger.warning(
                "NoteHead-to-beatID mapping failed for \(desyncCount)/\(cachedNotationLayout.noteHeads.count) noteHeads"
            )
        }
        cachedNotationNoteHeadIDsByBeatID = noteHeadIDsByBeatID
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
        guard let track = track else {
            Logger.error("calculateTrackDuration() called with nil track - returning 0.0")
            return 0.0
        }

        let secondsPerBeat = 60.0 / track.bpm
        let secondsPerMeasure = secondsPerBeat * Double(track.timeSignature.beatsPerMeasure)
        let baseDuration = calculateTrackDurationInSeconds(secondsPerMeasure: secondsPerMeasure)
        let speedMultiplier = practiceSettings.speedMultiplier
        guard speedMultiplier > 0 else {
            Logger.error("calculateTrackDuration called with zero speedMultiplier - returning base duration")
            return baseDuration
        }
        return baseDuration / speedMultiplier
    }

    func calculateBGMOffset() -> Double {
        guard let track = track else { return 0.0 }
        if let bgmStartOffsetSeconds = cachedSong?.bgmStartOffsetSeconds, bgmStartOffsetSeconds > 0 {
            let speedMultiplier = practiceSettings.speedMultiplier
            guard speedMultiplier > 0 else {
                Logger.error("calculateBGMOffset called with zero speedMultiplier - returning unscaled DTX BGM offset")
                return bgmStartOffsetSeconds
            }
            return bgmStartOffsetSeconds / speedMultiplier
        }

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
            let speedMultiplier = practiceSettings.speedMultiplier
            guard speedMultiplier > 0 else {
                Logger.error("calculateBGMOffset called with zero speedMultiplier - returning unscaled offset")
                return noteTimeSeconds
            }
            return noteTimeSeconds / speedMultiplier
        }

        return 0.0
    }

    // MARK: - Scoring Methods

    /// Process a note match result from InputManager. Called by GameplayInputHandler closure.
    func recordHit(result: NoteMatchResult) {
        guard isPlaying else { return }

        // Flush any notes that were missed before this hit so combo state is correct
        // when processHit runs (handles 8th/16th notes within the same beat).
        let hitTimePos = MeasureUtils.timePosition(
            measureNumber: result.measureNumber,
            measureOffset: result.measureOffset
        )
        scanForMissedNotes(upToTimePosition: hitTimePos)

        // Prevent duplicate scoring: if this note was already scored (e.g. double-tap
        // within InputManager's search window), discard the repeated result entirely.
        if let note = result.matchedNote {
            let noteID = ObjectIdentifier(note)
            guard scoredNoteIDs.insert(noteID).inserted else { return }
        }

        let prevCombo = scoreEngine.combo
        scoreEngine.processHit(accuracy: result.timingAccuracy, timingError: result.timingError)

        if result.timingAccuracy == .miss {
            if prevCombo > 0 { triggerComboBreakFeedback() }
        } else {
            triggerHitHaptic()
            if ScoreEngine.milestone(crossedFrom: prevCombo, to: scoreEngine.combo) != nil {
                triggerMilestoneAnimation()
            }
        }

        Logger.userAction("Score: \(scoreEngine.score) | Combo: \(scoreEngine.combo)x")
    }

    /// Scan cachedNotes for notes that scrolled past without any hit attempt.
    func scanForMissedNotes(upToTimePosition playheadPosition: Double) {
        guard isPlaying || playheadPosition.isInfinite else { return }

        // Offset the miss boundary by the good-tier late tolerance so that late hits
        // arriving within ±100 ms can still score before we auto-mark them missed.
        let bpm = effectiveBPM()
        let beatsPerMeasure = Double(track?.timeSignature.beatsPerMeasure ?? 4)
        let secondsPerMeasure = beatsPerMeasure * 60.0 / bpm
        let lateWindowInMeasures = TimingAccuracy.good.toleranceMs / 1000.0 / secondsPerMeasure
        let scanBoundary = playheadPosition - lateWindowInMeasures

        // Bail out when not enough time has elapsed to guarantee any note is past the window.
        guard scanBoundary > lastScannedTimePosition else { return }

        // Capture combo before the loop so we can fire break feedback exactly once
        // if any auto-missed note drops the combo from non-zero to zero.
        let prevCombo = scoreEngine.combo

        // Walk forward from the cursor; notes are sorted ascending by time position,
        // so we stop as soon as we reach a note at or beyond the scan boundary.
        // This is O(new notes this tick) rather than O(totalNotes).
        while missedNoteScanCursor < sortedNotesByTimePosition.count {
            let note = sortedNotesByTimePosition[missedNoteScanCursor]
            let noteTimePos = MeasureUtils.timePosition(
                measureNumber: note.measureNumber,
                measureOffset: note.measureOffset
            )
            // All remaining notes are at or after the miss boundary — done for this tick.
            if noteTimePos >= scanBoundary { break }
            // Mark as miss only if no explicit hit was recorded for this note.
            let noteID = ObjectIdentifier(note)
            if !scoredNoteIDs.contains(noteID) {
                scoredNoteIDs.insert(noteID)
                scoreEngine.processMissedNote()
            }
            missedNoteScanCursor += 1
        }
        lastScannedTimePosition = scanBoundary

        // Fire combo-break feedback if any auto-miss above broke the combo.
        // Mirrors the same guard in recordHit; triggerComboBreakFeedback also
        // double-checks combo == 0 internally, so no duplication risk.
        if prevCombo > 0 && scoreEngine.combo == 0 {
            triggerComboBreakFeedback()
        }
    }

    /// Resets all scoring state. Called by resetPlaybackState() on restart and completion.
    func resetScoring() {
        scoreEngine.reset()
        sessionScoreSnapshot = .empty
        sessionRecordResult = .recorded
        isShowingSessionResults = false
        showMilestoneAnimation = false
        showComboBreakFeedback = false
        scoredNoteIDs = []
        missedNoteScanCursor = 0
        lastScannedTimePosition = 0.0
        // Cancel any in-flight feedback reset tasks so they cannot clear flags on
        // the fresh session that is about to start.
        milestoneAnimationTask?.cancel()
        milestoneAnimationTask = nil
        comboBreakFeedbackTask?.cancel()
        comboBreakFeedbackTask = nil
        // Cancel scheduled completion and reset flag for next session
        completionTask?.cancel()
        completionTask = nil
        completionScheduled = false
    }

    /// Wire GameplayInputHandler closures to ViewModel scoring methods.
    func wireInputHandler() {
        inputHandler.onNoteResult = { [weak self] result in
            self?.recordHit(result: result)
        }
        inputHandler.onSelectedSourceDisconnect = { [weak self] in
            self?.handleSelectedMIDISourceDisconnect()
        }
    }

    private func triggerMilestoneAnimation() {
        milestoneAnimationTask?.cancel()
        showMilestoneAnimation = true
        milestoneAnimationTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            self?.showMilestoneAnimation = false
        }
    }

    private func triggerComboBreakFeedback() {
        guard scoreEngine.combo == 0 else { return }
        comboBreakFeedbackTask?.cancel()
        showComboBreakFeedback = true
        triggerComboBreakHaptic()
        comboBreakFeedbackTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            self?.showComboBreakFeedback = false
        }
    }

    private func triggerHitHaptic() {
        #if os(iOS)
        hitHapticGenerator.impactOccurred(intensity: 0.6)
        #endif
    }

    private func triggerComboBreakHaptic() {
        #if os(iOS)
        comboBreakHapticGenerator.notificationOccurred(.warning)
        #endif
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

// swiftlint:enable file_length type_body_length
