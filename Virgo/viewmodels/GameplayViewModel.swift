//
//  GameplayViewModel.swift
//  Virgo
//
//  Consolidates GameplayView state management to reduce @State explosion
//  and improve maintainability.
//

import SwiftUI
import Observation
import AVFoundation
import Combine

/// Schedules the delayed playback-completion action. `action` is invoked on the
/// main actor after `delaySeconds`; the returned cancellable's `cancel()` must
/// prevent a not-yet-fired action from running. The default implementation uses a
/// background-queue `DispatchSourceTimer` (reliable under main-actor contention);
/// tests inject an immediate scheduler to avoid wall-clock timing under CI load,
/// mirroring the `MIDILearnTimeoutTimerFactory` pattern.
typealias GameplayCompletionScheduler = @MainActor (
    TimeInterval,
    @escaping @MainActor () -> Void
) -> AnyCancellable

/// ViewModel for GameplayView that consolidates state management
/// and provides a clean separation between UI and business logic.
@Observable
@MainActor
final class GameplayViewModel {
    // MARK: - Dependencies
    let chart: Chart
    let metronome: MetronomeEngine
    let practiceSettings: PracticeSettingsService
    var lastAppliedSpeedMultiplier: Double // internal for cross-file extension access

    // MARK: - Speed Change Debounce
    /// Timestamp of last speed change application (diagnostic only)
    var lastSpeedChangeTimestamp: Date? // internal for cross-file extension access
    /// Minimum interval between speed change applications
    let speedChangeDebounceInterval: TimeInterval = 0.1 // internal for cross-file extension access
    /// Pending speed change timer for trailing-edge debounce
    var speedChangeTimer: Timer? // internal for cross-file extension access
    /// Latest pending speed value waiting to be applied
    var latestPendingSpeed: Double? // internal for cross-file extension access

    // MARK: - Row Width Resize Debounce
    /// Minimum interval between row-width layout rebuilds
    let rowWidthDebounceInterval: TimeInterval = 0.1 // internal for cross-file extension access
    /// Pending resize timer for trailing-edge debounce
    var rowWidthTimer: Timer?

    // MARK: - Cached SwiftData Relationships
    /// Cached song to avoid main thread blocking from relationship access
    var cachedSong: Song?
    /// Cached notes array to avoid relationship access during rendering
    var cachedNotes: [Note] = []
    /// Immutable control snapshots; views/layout never traverse the SwiftData relationship.
    var cachedControlEvents: [NotationControlEvent] = []
    /// Immutable timeline selected once while chart relationships are on the MainActor.
    var cachedRhythmTimeline: RhythmTimeline?
    /// Model-free input snapshots, sorted by stable timeline identity.
    var cachedRhythmNoteTargets: [RhythmNoteTarget] = []
    /// MainActor-only bridge from immutable event identity back to SwiftData notes for UI use.
    var cachedNoteByRhythmEventID: [RhythmEventID: Note] = [:]
    /// Flag indicating whether async data loading is complete
    var isDataLoaded = false
    /// Flag indicating whether gameplay-derived layout/audio state has been prepared.
    var isGameplayPrepared = false
    /// Flag indicating whether the chart's persisted speed was loaded (prevents saving before load)
    var hasLoadedPersistedSpeed = false // internal for cross-file extension access

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
    let playbackProgressPublishInterval: TimeInterval = 0.1 // internal for cross-file extension access
    var lastPlaybackProgressPublishElapsedTime: Double? // internal for cross-file extension access
    /// Playback start time for timing calculations
    var playbackStartTime: Date?
    /// Accumulated elapsed time when paused
    var pausedElapsedTime: Double = 0.0
    /// The CFAbsoluteTime at which the metronome/BGM were last scheduled to start.
    /// Used to synchronize input timing with actual audio playback so hits are
    /// judged relative to what the player hears, not when startPlayback() was called.
    var lastScheduledPlaybackStartTime: CFAbsoluteTime? // internal for cross-file extension access
    /// Host clock (`mach_absolute_time()`) captured at the same instant as
    /// `lastScheduledPlaybackStartTime` so the input manager can project its
    /// zero-point forward without drift from intervening main-thread work.
    var lastScheduledPlaybackHostTime: UInt64? // internal for cross-file extension access

    // MARK: - Cached Layout Data
    /// Pre-computed drum beats from notes
    var cachedDrumBeats: [DrumBeat] = [] // internal for cross-file extension access
    /// Pre-computed measure positions for layout
    var cachedMeasurePositions: [GameplayLayout.MeasurePosition] = [] // internal for cross-file extension access
    /// Cached track duration in seconds
    var cachedTrackDuration: Double = 0.0 // internal for cross-file extension access
    /// Cached beat indices for iteration
    var cachedBeatIndices: [Int] = [] // internal for cross-file extension access
    /// Fast lookup map from measure index to position
    var measurePositionMap: [Int: GameplayLayout.MeasurePosition] = [:] // internal for cross-file extension access
    /// Pre-cached beat positions for performance
    var cachedBeatPositions: [UInt64: (x: Double, y: Double)] = [:] // internal for cross-file extension access
    /// Pre-computed notation layout that drives rendering when notes are present
    var cachedNotationLayout = NotationLayout.empty // internal for cross-file extension access
    /// Fast lookup from measure index to row for the notation layout path.
    var cachedMeasureRowMap: [Int: Int] = [:] // internal for cross-file extension access
    /// Fast lookup from measure index to rendered measure for the notation layout path.
    /// Replaces per-frame linear `first(where:)` scans in the playhead with O(1) access.
    var cachedNotationMeasuresByIndex: [Int: RenderedMeasure] = [:] // internal for cross-file extension access
    /// Fast lookup map from rendered note-head ID to rendered position
    var cachedNotationNoteHeadPositions: [UInt64: (x: Double, y: Double)] = [:] // internal for cross-file extension access
    /// Duration-based measure count shared with both legacy sheet layout and notation layout.
    var cachedLayoutMeasureCount = 1 // internal for cross-file extension access
    /// Available row width, fed from the sheet music view's GeometryProxy. Falls back
    /// to the legacy 900pt cap so layouts built before any geometry is observed behave
    /// the way they always have. Use `updateRowWidth(_:)` to set this from the view.
    var cachedLayoutRowWidth: CGFloat = GameplayLayout.maxRowWidth

    // MARK: - Visual State
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
    var shouldGateGameplayOnSelectedMIDISource: Bool { // internal for cross-file extension access
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
    var milestoneAnimationTask: Task<Void, Never>? // internal for cross-file extension access
    /// True briefly after a combo break to drive visual feedback
    var showComboBreakFeedback: Bool = false
    /// Retained handle for the delayed combo-break-feedback reset; same rationale as
    /// milestoneAnimationTask — cancels the old timer before starting a new one.
    var comboBreakFeedbackTask: Task<Void, Never>? // internal for cross-file extension access
    /// Notes already scored via explicit hit — skipped by missed-note scan
    var scoredNoteIDs: Set<ObjectIdentifier> = [] // internal for cross-file extension access
    /// Timeline events already scored or auto-missed. Stable across matcher speed changes.
    var scoredRhythmEventIDs: Set<RhythmEventID> = [] // internal for cross-file extension access
    /// Notes sorted by ascending time position; built once after data load.
    /// Enables the missed-note scan to walk forward without re-scanning the full list.
    var sortedNotesByTimePosition: [Note] = [] // internal for cross-file extension access
    /// Cursor into sortedNotesByTimePosition; advanced forward-only each scan tick.
    /// Avoids O(totalNotes) scan on every metronome callback (now O(new notes)).
    var missedNoteScanCursor: Int = 0 // internal for cross-file extension access
    /// High-water mark for missed-note scan (timePosition units)
    var lastScannedTimePosition: Double = 0.0 // internal for cross-file extension access
    /// High-water mark for timeline missed-note scans (effective song seconds).
    var lastScannedRhythmTargetSeconds: Double = -.infinity // internal for cross-file extension access

    // MARK: - Completion Scheduling
    /// Whether playback completion has been scheduled (prevents double-scheduling during grace period)
    var completionScheduled = false // internal for cross-file extension access
    /// Cancellable handle for the delayed-completion grace-period timer. Nilled
    /// by `pausePlayback`/`cleanup`/`resetScoring` so a stale grace-period action
    /// cannot fire after the user dismisses gameplay or starts a new run.
    var completionTask: AnyCancellable?
    /// Injected scheduler used to defer the playback-completion action by the
    /// late-tolerance grace window. Tests inject an immediate scheduler.
    let completionScheduler: GameplayCompletionScheduler // internal for cross-file extension access

    // MARK: - Score Persistence
    let scorePersistence: ScorePersistenceService

    /// True only while the current run has been at 1.0x speed for its entire
    /// duration. Gates all-time best eligibility.
    var sessionAtFullSpeed: Bool = true

    // MARK: - Haptic Generators (iOS only)
    #if os(iOS)
    // `internal` (not `private`) so the cross-file extensions in
    // GameplayViewModel+Computations.swift can reach these from their `#if os(iOS)`
    // branches. `private` only allows same-file access; this is the one iOS-only
    // storage the split moves out of the core file. (CI builds macOS only, so an
    // accidental `private` here breaks the iPad build silently — see HPA-90.)
    let hitHapticGenerator = UIImpactFeedbackGenerator(style: .light)
    let comboBreakHapticGenerator = UINotificationFeedbackGenerator()
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
        scorePersistence: ScorePersistenceService,
        completionScheduler: GameplayCompletionScheduler? = nil
    ) {
        self.chart = chart
        self.metronome = metronome
        self.practiceSettings = practiceSettings
        self.scorePersistence = scorePersistence
        self.completionScheduler = completionScheduler ?? Self.defaultCompletionScheduler()
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

    /// Production default: a background-queue `DispatchSourceTimer` whose handler
    /// hops to the main actor to finalize playback. Scheduling the timer off the
    /// main actor keeps the late-tolerance grace-period firing on time even when
    /// the main actor is contended (final-beat visual/input work), matching the
    /// `MIDILearnSession` timeout-timer approach.
    private static func defaultCompletionScheduler() -> GameplayCompletionScheduler {
        { delaySeconds, action in
            let queue = DispatchQueue(label: "com.virgo.gameplay.completion")
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + delaySeconds)
            timer.setEventHandler {
                Task { @MainActor in action() }
            }
            timer.resume()
            // The cancellable retains the timer until it fires or is cancelled.
            return AnyCancellable { timer.cancel() }
        }
    }

    // MARK: - Unique ID Generation
    /// Monotonic counter for generating unique DrumBeat IDs
    var nextBeatId: UInt64 = 0 // internal for cross-file extension access

    // MARK: - Data Loading

    /// Loads SwiftData relationships asynchronously to avoid blocking main thread
    func loadChartData() async {
        isGameplayPrepared = false
        cachedSong = chart.song
        cachedNotes = chart.notes.map { $0 }
        cachedControlEvents = chart.safeControlEvents.map(NotationControlEvent.init)
        let resolvedRhythm = RhythmTimelineResolver().resolve(chart: chart)
        cachedRhythmTimeline = resolvedRhythm.timeline
        cachedNoteByRhythmEventID = resolvedRhythm.noteByEventID
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
        cacheRhythmInputTargets(resolvedRhythm: resolvedRhythm)
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
        configureInputTiming(speed: practiceSettings.speedMultiplier)
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

}
