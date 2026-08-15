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

/// One immutable, chart-scoped runtime selection shared by layout, input,
/// playback, metronome, BGM, and diagnostics. It is replaced atomically after
/// relationship loading; consumers never repeat metadata-origin selection.
@MainActor
struct GameplayRhythmRuntime {
    let availability: RhythmTimelineAvailability
    let timeline: RhythmTimeline?
    let layoutSnapshot: RhythmLayoutSnapshot?
    let noteTargets: [RhythmNoteTarget]
    let metronomeSchedule: RhythmMetronomeSchedule?
    let noteByEventID: [RhythmEventID: Note]
    let controlByEventID: [RhythmEventID: NotationControlEvent]
    let positionByNoteObjectID: [ObjectIdentifier: RhythmEventPosition]
    let diagnostics: [PersistedRhythmDiagnostic]

    static let legacy = GameplayRhythmRuntime(
        availability: .legacy,
        timeline: nil,
        layoutSnapshot: nil,
        noteTargets: [],
        metronomeSchedule: nil,
        noteByEventID: [:],
        controlByEventID: [:],
        positionByNoteObjectID: [:],
        diagnostics: []
    )
}

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
    /// Atomically cached runtime selected once while chart relationships are on the MainActor.
    var cachedRhythmRuntime = GameplayRhythmRuntime.legacy
    var cachedRhythmTimeline: RhythmTimeline? { cachedRhythmRuntime.timeline }
    var cachedRhythmNoteTargets: [RhythmNoteTarget] { cachedRhythmRuntime.noteTargets }
    var cachedNoteByRhythmEventID: [RhythmEventID: Note] { cachedRhythmRuntime.noteByEventID }
    var hasFatalRhythmTiming: Bool { cachedRhythmRuntime.availability == .fatal }
    var rhythmFatalMessage: String {
        guard let diagnostic = cachedRhythmRuntime.diagnostics.first else {
            return String(localized: "Unsupported chart timing")
        }
        let presentation = RhythmDiagnosticPresentation(code: diagnostic.code)
        if let measureIndex = diagnostic.sourceMeasureIndex {
            return String(localized: "\(presentation.title): measure \(measureIndex + 1) \(presentation.description)")
        }
        return String(localized: "\(presentation.title): \(presentation.description)")
    }
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
    /// Pre-computed notation layout that drives rendering when notes are present.
    /// The private storage keeps every replacement behind `installNotationLayout(_:)`.
    private var notationLayoutStorage = NotationLayout.empty
    private(set) var notationLayoutGeneration: UInt64 = 0
    var cachedNotationLayout: NotationLayout { notationLayoutStorage }
    /// Note-head presence is already an O(1) layout query. Printed-rest and
    /// control renderability is resolved once at layout installation so playback
    /// updates do not scan those arrays.
    var cachedNotationHasPlayableContent: Bool { !notationLayoutStorage.noteHeads.isEmpty }
    private(set) var cachedNotationHasRenderableContent = false
    /// Fast lookup from measure index to row for the notation layout path.
    var cachedMeasureRowMap: [Int: Int] = [:] // internal for cross-file extension access
    /// Fast lookup from measure index to rendered measure for the notation layout path.
    /// Replaces per-frame linear `first(where:)` scans in the playhead with O(1) access.
    var cachedNotationMeasuresByIndex: [Int: RenderedMeasure] = [:] // internal for cross-file extension access
    /// Duration-based measure count shared with legacy and notation layouts.
    var cachedLayoutMeasureCount = 1 // internal for cross-file extension access
    /// O(1) legacy-sheet height used by the observable sheet container. The
    /// measure-row scan that produces this value runs only when the layout is
    /// installed, never while playback updates the playhead.
    var cachedLegacyContentHeight: CGFloat = 0 // internal for cross-file extension access
    /// Available row width, fed from the sheet music view's GeometryProxy. Falls back
    /// to the legacy 900pt cap so layouts built before any geometry is observed behave
    /// the way they always have. Use `updateRowWidth(_:)` to set this from the view.
    var cachedLayoutRowWidth: CGFloat = GameplayLayout.maxRowWidth

    /// Retained handle to the in-flight detached preparation worker so
    /// `beginNotationPreparation()` and caller-task cancellation can stop the
    /// off-main work. Same contract: cancellation saves work, generation checks
    /// remain the correctness rule.
    var notationPreparationWorkerTask: Task<GameplayNotationPreparedState, Never>?

    // MARK: - Visual State
    /// Current purple bar position (x, y)
    var purpleBarPosition: (x: Double, y: Double)?
    /// Row index of the staff currently containing the playhead. Drives auto-scroll
    /// of the sheet music ScrollView so the active row stays visible during playback.
    var currentRow: Int = 0

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
    /// Cursor into sortedNotesByTimePosition (legacy miss scan); advanced forward-only each scan tick.
    /// Avoids O(totalNotes) scan on every metronome callback (now O(new notes)).
    var legacyMissedNoteScanCursor: Int = 0 // internal for cross-file extension access
    /// Cursor into cachedRhythmNoteTargets (timeline miss scan); advanced forward-only each scan tick.
    /// Kept separate from legacyMissedNoteScanCursor because the two collections are not aligned.
    var rhythmMissedNoteScanCursor: Int = 0 // internal for cross-file extension access
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

    /// Installs a notation layout through the single generation used to identify
    /// the current static notation projection. Worker results pass their already
    /// allocated generation so applying one does not create a second identity.
    @discardableResult
    func installNotationLayout(
        _ layout: NotationLayout,
        generation: UInt64? = nil
    ) -> Bool {
        if let generation {
            guard generation == notationLayoutGeneration else { return false }
        } else {
            notationLayoutGeneration &+= 1
        }
        notationLayoutStorage = layout
        cachedNotationHasRenderableContent = layout.hasRenderableContent
        return true
    }

    /// Invalidates any in-flight timeline preparation and allocates the next
    /// identity on the same counter used by the static notation child.
    @discardableResult
    func beginNotationPreparation() -> UInt64 {
        notationPreparationWorkerTask?.cancel()
        notationPreparationWorkerTask = nil
        notationLayoutGeneration &+= 1
        return notationLayoutGeneration
    }

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
            Logger.warning(
                "loadChartData: chart.notes returned empty array - chart may have no notes or relationship failed to load"
            )
        }

        track = DrumTrack(chart: chart)
        cachedRhythmRuntime = makeRhythmRuntime(resolvedRhythm: resolvedRhythm)
        isDataLoaded = true
    }

    // MARK: - Setup

    /// Sets up gameplay after data is loaded
    /// - Parameter loadPersistedSpeed: Whether to load the saved speed for this chart.
    ///   Pass `false` to use a preconfigured speed instead of the saved value.
    ///   Defaults to `true` to load saved speed (SC-06: Remember last-used speed).
    func setupGameplay(loadPersistedSpeed: Bool = true) async {
        isGameplayPrepared = false
        let setupGeneration = beginNotationPreparation()
        guard let track = track else {
            Logger.error("setupGameplay() called but track is nil - data not loaded yet")
            return
        }
        guard !hasFatalRhythmTiming else {
            resetForFatalRhythmTiming(generation: setupGeneration)
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
        let preparesTimelineOffMain = cachedRhythmRuntime.availability == .valid
        computeCachedLayoutData(prepareNotation: !preparesTimelineOffMain)
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

        guard preparesTimelineOffMain,
              let request = makeTimelineNotationPreparationRequest() else {
            if preparesTimelineOffMain {
                computeCachedLayoutData()
            }
            isGameplayPrepared = true
            return
        }
        await prepareTimelineNotation(request, generation: setupGeneration)
    }

    /// Tears down runtime state for a chart whose persisted timing is fatally
    /// inconsistent. The setup request already allocated `generation`; the reset
    /// reuses it so the reset remains a single notation installation.
    private func resetForFatalRhythmTiming(generation: UInt64) {
        _ = installNotationLayout(.empty, generation: generation)
        cachedMeasureRowMap = [:]
        cachedNotationMeasuresByIndex = [:]
        cachedLegacyContentHeight = 0
        cachedTrackDuration = 0
        bgmOffsetSeconds = 0
        metronome.stop()
        bgmPlayer?.stop()
        bgmPlayer = nil
        inputManager.stopListening()
        Logger.error(rhythmFatalMessage)
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
