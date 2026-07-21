//
//  InputManager.swift
//  Virgo
//
//  Created by Claude Code on 9/8/2025.
//  swiftlint:disable file_length
//

import Foundation
import Combine
import CoreMIDI
#if os(macOS)
import AppKit
#endif

// MARK: - Input Event Types

struct InputHit: Sendable {
    let drumType: DrumType
    let velocity: Double // 0.0 to 1.0
    let timestamp: Date
}

struct NoteMatchResult {
    let hitInput: InputHit
    let matchedNote: Note?
    let timingAccuracy: TimingAccuracy
    let measureNumber: Int?
    let measureOffset: Double?
    let timingError: Double? // in milliseconds, positive = late, negative = early; nil when no note matched
    let matchedEventID: RhythmEventID?
    let matchedTargetPosition: RhythmEventPosition?
    let matchedTargetSeconds: Double?
    let hitSongSeconds: Double?
    let hitPosition: RhythmEventPosition?

    init(
        hitInput: InputHit,
        matchedNote: Note? = nil,
        timingAccuracy: TimingAccuracy,
        measureNumber: Int? = nil,
        measureOffset: Double? = nil,
        timingError: Double?,
        matchedEventID: RhythmEventID? = nil,
        matchedTargetPosition: RhythmEventPosition? = nil,
        matchedTargetSeconds: Double? = nil,
        hitSongSeconds: Double? = nil,
        hitPosition: RhythmEventPosition? = nil
    ) {
        self.hitInput = hitInput
        self.matchedNote = matchedNote
        self.timingAccuracy = timingAccuracy
        self.measureNumber = measureNumber
        self.measureOffset = measureOffset
        self.timingError = timingError
        self.matchedEventID = matchedEventID
        self.matchedTargetPosition = matchedTargetPosition
        self.matchedTargetSeconds = matchedTargetSeconds
        self.hitSongSeconds = hitSongSeconds
        self.hitPosition = hitPosition
    }
}

enum TimingAccuracy: Sendable {
    case perfect    // ±25ms
    case great      // ±50ms
    case good       // ±100ms
    case miss       // >100ms or no note

    var toleranceMs: Double {
        switch self {
        case .perfect: return 25.0
        case .great: return 50.0
        case .good: return 100.0
        case .miss: return Double.infinity
        }
    }
    
    var scoreMultiplier: Double {
        switch self {
        case .perfect: return 1.0
        case .great: return 0.8
        case .good: return 0.5
        case .miss: return 0.0
        }
    }
}

// MARK: - Input Manager Protocol

protocol InputManagerDelegate: AnyObject {
    func inputManager(_ manager: InputManager, didReceiveHit hit: InputHit)
    func inputManager(_ manager: InputManager, didMatchNote result: NoteMatchResult)
    func inputManagerSelectedMIDISourceDisconnected(_ manager: InputManager)
}

extension InputManagerDelegate {
    func inputManagerSelectedMIDISourceDisconnected(_ manager: InputManager) {}
}

class InputManager: ObservableObject {
    weak var delegate: InputManagerDelegate?
    private let runtimeStateQueue = DispatchQueue(label: "Virgo.InputManager.runtime")
    private let midiConnectionQueue = DispatchQueue(label: "Virgo.InputManager.midi-connections")
    private let midiCallbackDrain = NSCondition()
    private var activeMIDICallbackCountsBySourceID: [String: Int] = [:]
    /// Source IDs currently being disconnected — only callbacks from these sources are rejected,
    /// allowing hits from unaffected MIDI devices to continue during partial refreshes.
    private var disconnectingSourceIDs: Set<String> = []
    
    // Song timing reference
    private var songStartTime: Date?
    private var songStartHostTime: UInt64?
    private var bpm: Double = 120.0
    private var timeSignature: TimeSignature = .fourFour
    private var notes: [Note] = []

    var configuredBPM: Double {
        withRuntimeState { bpm }
    }
    var hasSelectedMIDISourcePreference: Bool { settingsManager.getSelectedMIDISource() != nil }
    var requiresMIDISourceForGameplay = false
    var isSelectedMIDISourceAvailable: Bool {
        withRuntimeState { selectedMIDISourceAvailableSnapshot }
    }
    
    // Input mapping configuration
    private var keyboardMapping: [String: DrumType] = [:]
    private var midiMapping: [UInt8: DrumType] = [:]
    private var midiMappingSnapshot: [UInt8: DrumType] = [:]
    private var keyboardMappingHasRuntimeOverride = false
    private var midiMappingHasRuntimeOverride = false
    private var selectedSourceIDSnapshot: String?
    private var selectedMIDISourceAvailableSnapshot = false
    private var learnSessionIsCapturingSnapshot = false
    
    // Settings manager for persistent configuration
    private let settingsManager: InputSettingsManager
    private let deviceRegistry: MIDIDeviceRegistry
    private let eventRouter: MIDIEventRouter
    private let hostTimeConverter: MIDIHostTimeConverter
    private let diagnosticsStore: MIDIDiagnosticsStore
    private let learnSession: MIDILearnSession
    private let sourceIDResolver: MIDISourceIDResolving
    private let timingTransitionCriticalSection: (() -> Void)?
    private var learnSessionCaptureCancellable: AnyCancellable?
    
    // MIDI setup
    private var midiClient: MIDIClientRef = 0
    private var midiInputPort: MIDIPortRef = 0
    private var midiSourceContexts: [MIDIEndpointRef: Unmanaged<MIDISourceConnectionContext>] = [:]
    /// Tracks whether CoreMIDI setup was attempted but failed in production.
    /// Distinguishes "not initialized" (test environment) from "initialization failed"
    /// so the availability gate doesn't falsely report sources as available.
    /// Accessed only on `midiConnectionQueue`.
    private var midiSetupFailed = false
    
    // Keyboard event monitors for proper cleanup
    #if os(macOS)
    private var globalEventMonitor: Any?
    private var localEventMonitor: Any?
    #endif
    
    // Timing calculation cache
    private var secondsPerBeat: Double = 0.5
    private var secondsPerMeasure: Double = 2.0
    private var inputTimingMatcher: InputTimingMatcher?
    private var hostTimeElapsedOffset: Double = 0.0
    
    // Test environment detection
    private let isTestEnvironment: Bool

    private final class MIDISourceConnectionContext {
        let sourceID: String

        init(sourceID: String) {
            self.sourceID = sourceID
        }
    }

    private struct MIDINoteHandlingContext {
        let songStartTime: Date?
        let songStartHostTime: UInt64?
        let hostTimeElapsedOffset: Double
        let selectedSourceID: String?
        let selectedSourceAvailable: Bool
        let requiresMIDISourceForGameplay: Bool
        let midiMapping: [UInt8: DrumType]
        let inputTimingMatcher: InputTimingMatcher?
    }

    private struct KeyboardInputContext {
        let songStartTime: Date?
        let elapsedOffset: Double
        let keyboardMapping: [String: DrumType]
        let inputTimingMatcher: InputTimingMatcher?
    }
    
    /// Creates an `InputManager`.
    ///
    /// Always instantiate `InputManager` on the main thread. Several internal initialization
    /// steps (settings reload, learn-session binding, MIDI source discovery) are dispatched
    /// asynchronously to the main actor and will not be complete when `init` returns on a
    /// non-main thread. All current call sites create `InputManager` on `@MainActor`.
    init(
        settingsManager: InputSettingsManager? = nil,
        deviceRegistry: MIDIDeviceRegistry? = nil,
        eventRouter: MIDIEventRouter = MIDIEventRouter(),
        hostTimeConverter: MIDIHostTimeConverter = MIDIHostTimeConverter(),
        diagnosticsStore: MIDIDiagnosticsStore? = nil,
        learnSession: MIDILearnSession? = nil,
        sourceIDResolver: MIDISourceIDResolving = CoreMIDISourceIDResolver(),
        timingTransitionCriticalSection: (() -> Void)? = nil
    ) {
        let settingsManager = settingsManager ?? InputSettingsManager()

        self.settingsManager = settingsManager
        self.deviceRegistry = deviceRegistry ?? Self.makeDefaultDeviceRegistry(settingsManager: settingsManager)
        self.eventRouter = eventRouter
        self.hostTimeConverter = hostTimeConverter
        self.diagnosticsStore = diagnosticsStore ?? Self.makeDefaultDiagnosticsStore()
        self.learnSession = learnSession ?? Self.makeDefaultLearnSession(settingsManager: settingsManager)
        self.sourceIDResolver = sourceIDResolver
        self.timingTransitionCriticalSection = timingTransitionCriticalSection
        self.isTestEnvironment = TestEnvironment.isRunningTests
        bindLearnSessionCaptureState()
        reloadMappingsFromSettings()

        // Only set up MIDI if not in test environment
        if !isTestEnvironment {
            setupMIDI()
        }
    }

    deinit {
        // Always clean up keyboard monitors if they were installed (even in test
        // environments, where startListening() may have been called).
        #if os(macOS)
        stopKeyboardListening()
        #endif

        // Only tear down CoreMIDI resources in non-test environments.
        guard !isTestEnvironment else { return }
        teardownMIDI()
    }

    private static func makeDefaultDeviceRegistry(settingsManager: InputSettingsManager) -> MIDIDeviceRegistry {
        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                MIDIDeviceRegistry(settingsManager: settingsManager)
            }
        }

        preconditionFailure("InputManager must be created on the main thread when using default MIDI dependencies")
    }

    private static func makeDefaultDiagnosticsStore() -> MIDIDiagnosticsStore {
        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                MIDIDiagnosticsStore()
            }
        }

        preconditionFailure("InputManager must be created on the main thread when using default MIDI dependencies")
    }

    private static func makeDefaultLearnSession(settingsManager: InputSettingsManager) -> MIDILearnSession {
        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                MIDILearnSession(settingsManager: settingsManager)
            }
        }

        preconditionFailure("InputManager must be created on the main thread when using default MIDI dependencies")
    }

    private func withRuntimeState<T>(_ body: () -> T) -> T {
        runtimeStateQueue.sync(execute: body)
    }

    private func updateRuntimeState(_ body: () -> Void) {
        runtimeStateQueue.sync(execute: body)
    }

    private func bindLearnSessionCaptureState() {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                bindLearnSessionCaptureStateOnMainActor()
            }
        } else {
            Task { @MainActor [weak self] in
                self?.bindLearnSessionCaptureStateOnMainActor()
            }
        }
    }

    @MainActor
    private func bindLearnSessionCaptureStateOnMainActor() {
        learnSessionCaptureCancellable = learnSession.$isCapturing.sink { [weak self] isCapturing in
            guard let self else { return }
            self.updateRuntimeState {
                self.learnSessionIsCapturingSnapshot = isCapturing
            }
        }
    }

    private func currentMIDINoteHandlingContext() -> MIDINoteHandlingContext {
        withRuntimeState {
            MIDINoteHandlingContext(
                songStartTime: songStartTime,
                songStartHostTime: songStartHostTime,
                hostTimeElapsedOffset: hostTimeElapsedOffset,
                selectedSourceID: selectedSourceIDSnapshot,
                selectedSourceAvailable: selectedMIDISourceAvailableSnapshot,
                requiresMIDISourceForGameplay: requiresMIDISourceForGameplay,
                midiMapping: midiMappingSnapshot,
                inputTimingMatcher: inputTimingMatcher
            )
        }
    }

    private func currentKeyboardInputContext() -> KeyboardInputContext {
        withRuntimeState {
            KeyboardInputContext(
                songStartTime: songStartTime,
                elapsedOffset: hostTimeElapsedOffset,
                keyboardMapping: keyboardMapping,
                inputTimingMatcher: inputTimingMatcher
            )
        }
    }

    private func currentSelectedSourceID() -> String? {
        withRuntimeState { selectedSourceIDSnapshot }
    }

    private func updateSelectedMIDISourceAvailabilitySnapshot(_ available: Bool) {
        updateRuntimeState {
            selectedMIDISourceAvailableSnapshot = available
        }
    }
}

// MARK: - Configuration

extension InputManager {
    func configure(bpm: Double, timeSignature: TimeSignature, notes: [Note]) {
        configure(.legacy(bpm: bpm, timeSignature: timeSignature, notes: notes))
    }

    func configure(_ configuration: InputTimingConfiguration, elapsedOffset: Double = 0) {
        validateElapsedOffset(elapsedOffset)
        let prepared = prepareInputTimingConfiguration(configuration)

        updateRuntimeState {
            applyPreparedInputTiming(prepared)
            self.hostTimeElapsedOffset = elapsedOffset
        }
    }

    func configureAndStartListening(
        _ configuration: InputTimingConfiguration,
        songStartTime: Date,
        elapsedOffset: Double = 0,
        scheduledStartDelay: Double = 0,
        capturedHostTime: UInt64? = nil
    ) {
        validateElapsedOffset(elapsedOffset)
        let prepared = prepareInputTimingConfiguration(configuration)
        let hostOrigin = listeningHostOrigin(
            scheduledStartDelay: scheduledStartDelay,
            capturedHostTime: capturedHostTime
        )

        updateRuntimeState {
            applyPreparedInputTiming(prepared)
            self.songStartTime = songStartTime
            self.songStartHostTime = hostOrigin
            self.hostTimeElapsedOffset = elapsedOffset
            self.timingTransitionCriticalSection?()
        }
        finishStartingListeners()
    }
    
    /// - Parameter scheduledStartDelay: Seconds between *now* and the moment
    ///   the metronome/BGM are scheduled to start producing audio.  When audio
    ///   is scheduled in the future (e.g. 50 ms ahead for buffer priming), the
    ///   host-time zero-point must be projected forward so that a hit arriving
    ///   exactly at audio-start registers as zero elapsed time.
    func startListening(
        songStartTime: Date,
        elapsedOffset: Double = 0.0,
        scheduledStartDelay: Double = 0.0,
        capturedHostTime: UInt64? = nil
    ) {
        validateElapsedOffset(elapsedOffset)
        let hostOrigin = listeningHostOrigin(
            scheduledStartDelay: scheduledStartDelay,
            capturedHostTime: capturedHostTime
        )
        updateRuntimeState {
            self.songStartTime = songStartTime
            self.songStartHostTime = hostOrigin
            self.hostTimeElapsedOffset = elapsedOffset
        }
        finishStartingListeners()
    }

    private func finishStartingListeners() {
        refreshSelectedMIDISourceStateFromSettings()
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.startKeyboardListening()
            }
            return
        }
        startKeyboardListening()
        // MIDI is already listening from setup
    }

    private func listeningHostOrigin(
        scheduledStartDelay: Double,
        capturedHostTime: UInt64?
    ) -> UInt64 {
        let rawHostTime = capturedHostTime ?? mach_absolute_time()
        guard scheduledStartDelay > 0 else { return rawHostTime }
        return hostTimeConverter.hostTimeByAdding(seconds: scheduledStartDelay, to: rawHostTime)
    }

    private func validateElapsedOffset(_ elapsedOffset: Double) {
        precondition(
            elapsedOffset.isFinite && elapsedOffset >= 0,
            "Input elapsed offset must be finite and nonnegative"
        )
    }

    private func prepareInputTimingConfiguration(
        _ configuration: InputTimingConfiguration
    ) -> (configuration: InputTimingConfiguration, matcher: InputTimingMatcher, bpm: Double?) {
        let normalizedConfiguration: InputTimingConfiguration
        switch configuration {
        case let .legacy(bpm, timeSignature, notes):
            guard bpm > 0.1 && bpm <= 1000 else {
                preconditionFailure("BPM must be between 0.1 and 1000.0, got: \(bpm)")
            }
            guard timeSignature.beatsPerMeasure > 0 else {
                preconditionFailure(
                    "Time signature beats per measure must be positive, got: \(timeSignature.beatsPerMeasure)"
                )
            }
            let sortedNotes = notes.sorted {
                $0.measureNumber < $1.measureNumber
                    || ($0.measureNumber == $1.measureNumber && $0.measureOffset < $1.measureOffset)
            }
            normalizedConfiguration = .legacy(
                bpm: bpm,
                timeSignature: timeSignature,
                notes: sortedNotes
            )
        case .timeline:
            normalizedConfiguration = configuration
        }
        let matcher = InputTimingMatcher(configuration: normalizedConfiguration)
        return (normalizedConfiguration, matcher, matcher.effectiveBPM)
    }

    private func applyPreparedInputTiming(
        _ prepared: (configuration: InputTimingConfiguration, matcher: InputTimingMatcher, bpm: Double?)
    ) {
        switch prepared.configuration {
        case let .legacy(bpm, timeSignature, notes):
            self.bpm = bpm
            self.timeSignature = timeSignature
            self.notes = notes
            self.secondsPerBeat = 60 / bpm
            self.secondsPerMeasure = self.secondsPerBeat * Double(timeSignature.beatsPerMeasure)
        case let .timeline(_, timeline, _):
            self.notes = []
            if let timeSignature = timeline.measures.first?.timeSignature {
                self.timeSignature = timeSignature
            }
            if let matcherBPM = prepared.bpm {
                self.bpm = matcherBPM
                self.secondsPerBeat = 60 / matcherBPM
                self.secondsPerMeasure = self.secondsPerBeat * Double(self.timeSignature.beatsPerMeasure)
            }
        }
        inputTimingMatcher = prepared.matcher
    }
    
    func stopListening() {
        updateRuntimeState {
            self.songStartTime = nil
            self.songStartHostTime = nil
            self.hostTimeElapsedOffset = 0.0
        }
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.stopKeyboardListening()
            }
            return
        }
        stopKeyboardListening()
        // MIDI continues to listen but won't process hits without songStartTime
    }

    func refreshGameplayConfigurationFromSettingsIfNeeded() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.refreshGameplayConfigurationFromSettingsIfNeeded()
            }
            return
        }

        settingsManager.loadSettings()

        let snapshot = (
            keyboardMapping: settingsManager.getKeyboardMappings(),
            midiMapping: settingsManager.getMidiMappings(),
            selectedSourceID: settingsManager.getSelectedMIDISource()?.id
        )

        updateRuntimeState {
            if !keyboardMappingHasRuntimeOverride {
                keyboardMapping = snapshot.keyboardMapping
            }
            if !midiMappingHasRuntimeOverride {
                midiMapping = snapshot.midiMapping
                midiMappingSnapshot = snapshot.midiMapping
            }
            selectedSourceIDSnapshot = snapshot.selectedSourceID
        }
        refreshMIDISourceAvailabilitySnapshot()
    }

    /// Simulates a CoreMIDI setup failure for testing.
    /// Sets the internal `midiSetupFailed` flag so the availability gate
    /// correctly rejects sources even when the registry reports them as available.
    /// Only intended for unit tests — in production this state is reached
    /// when `MIDIClientCreateWithBlock` or `MIDIInputPortCreateWithBlock` fails.
    func simulateMIDISetupFailureForTesting() {
        midiConnectionQueue.sync {
            midiSetupFailed = true
        }
    }

    func refreshSelectedMIDISourceStateFromSettings() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.refreshSelectedMIDISourceStateFromSettings()
            }
            return
        }

        settingsManager.loadSettings()

        let selectedSourceID = settingsManager.getSelectedMIDISource()?.id

        updateRuntimeState {
            selectedSourceIDSnapshot = selectedSourceID
        }
        refreshMIDISourceAvailabilitySnapshot()
    }
    
    /// Reload mappings from settings (call this when settings are updated)
    func reloadMappingsFromSettings() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.reloadMappingsFromSettings()
            }
            return
        }

        settingsManager.loadSettings()

        let snapshot = (
            keyboardMapping: settingsManager.getKeyboardMappings(),
            midiMapping: settingsManager.getMidiMappings(),
            selectedSourceID: settingsManager.getSelectedMIDISource()?.id
        )
        let isCapturing = withRuntimeState { learnSessionIsCapturingSnapshot }

        updateRuntimeState {
            keyboardMapping = snapshot.keyboardMapping
            midiMapping = snapshot.midiMapping
            midiMappingSnapshot = snapshot.midiMapping
            keyboardMappingHasRuntimeOverride = false
            midiMappingHasRuntimeOverride = false
            selectedSourceIDSnapshot = snapshot.selectedSourceID
            learnSessionIsCapturingSnapshot = isCapturing
        }
        refreshMIDISourceAvailabilitySnapshot()
    }

    func startMIDIMonitoring() {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                deviceRegistry.onSelectedSourceUnavailable = { [weak self] sourceID in
                    self?.handleSelectedSourceDisconnect(sourceID: sourceID)
                }
                deviceRegistry.onSelectedSourceReconnected = { [weak self] sourceID in
                    self?.handleSelectedSourceReconnect(sourceID: sourceID)
                }
                deviceRegistry.startMonitoring()
                let registryAvailable = deviceRegistry.isSelectedSourceAvailable
                let effectiveAvailable = applyConnectionAvailabilityGate(
                    registryAvailable: registryAvailable
                )
                updateSelectedMIDISourceAvailabilitySnapshot(effectiveAvailable)
            }
        } else {
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.deviceRegistry.onSelectedSourceUnavailable = { [weak self] sourceID in
                    self?.handleSelectedSourceDisconnect(sourceID: sourceID)
                }
                self.deviceRegistry.onSelectedSourceReconnected = { [weak self] sourceID in
                    self?.handleSelectedSourceReconnect(sourceID: sourceID)
                }
                self.deviceRegistry.startMonitoring()
                let registryAvailable = self.deviceRegistry.isSelectedSourceAvailable
                let effectiveAvailable = self.applyConnectionAvailabilityGate(
                    registryAvailable: registryAvailable
                )
                self.updateSelectedMIDISourceAvailabilitySnapshot(effectiveAvailable)
            }
        }
    }

    private func refreshMIDISourceAvailabilitySnapshot() {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                deviceRegistry.refreshSources()
                let registryAvailable = deviceRegistry.isSelectedSourceAvailable
                let effectiveAvailable = applyConnectionAvailabilityGate(
                    registryAvailable: registryAvailable
                )
                updateSelectedMIDISourceAvailabilitySnapshot(effectiveAvailable)
            }
        } else {
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.deviceRegistry.refreshSources()
                let registryAvailable = self.deviceRegistry.isSelectedSourceAvailable
                let effectiveAvailable = self.applyConnectionAvailabilityGate(
                    registryAvailable: registryAvailable
                )
                self.updateSelectedMIDISourceAvailabilitySnapshot(effectiveAvailable)
            }
        }
    }

    /// Combines registry availability with InputManager's actual connection state.
    ///
    /// A source is only truly "available" for gameplay if:
    /// 1. The registry sees it in CoreMIDI discovery (registryAvailable), AND
    /// 2. InputManager has successfully connected its input port to receive events.
    ///
    /// When MIDI is not yet initialized (e.g. in test environments), the
    /// connection gate is skipped to avoid falsely marking sources as unavailable.
    private func applyConnectionAvailabilityGate(registryAvailable: Bool) -> Bool {
        guard registryAvailable else { return false }
        guard let connected = connectedSourceIDsIfInitialized else {
            // MIDI not initialized (test environment) — rely solely on registry availability.
            return registryAvailable
        }
        let selectedID = settingsManager.getSelectedMIDISource()?.id
        return selectedID.map { connected.contains($0) } ?? false
    }

    /// Returns the set of stable source IDs that InputManager has successfully
    /// connected its MIDI input port to.  Returns `nil` when the MIDI subsystem
    /// has not been initialized (e.g. in test environments), allowing callers to
    /// skip the connection gate.  Returns an empty set when initialization was
    /// attempted but failed, so the gate correctly rejects all sources.
    private var connectedSourceIDsIfInitialized: Set<String>? {
        midiConnectionQueue.sync {
            guard midiInputPort != 0 else {
                if midiSetupFailed {
                    // Setup was attempted but failed — return empty set so the gate
                    // properly rejects all sources (vs nil which bypasses the gate).
                    return []
                }
                return nil
            }
            return Set(midiSourceContexts.values.map { $0.takeUnretainedValue().sourceID })
        }
    }
}

// MARK: - Input Processing

extension InputManager {
    @discardableResult
    func handleMIDINoteEvent(_ event: MIDINoteEvent) -> NoteMatchResult? {
        consumeLearnSessionIfNeeded(event)
        let context = currentMIDINoteHandlingContext()

        // Source gate:
        //  - No selected source → accept from any device
        //  - Event from selected source → always accept
        //  - Selected source unavailable AND gated mode OFF → accept from any device (fallback)
        //  - Selected source unavailable AND gated mode ON → reject non-selected events.
        //    The delegate will pause playback; accepting hits from wrong devices
        //    during the async dispatch window would break the "selected device required" invariant.
        guard context.selectedSourceID == nil ||
              event.sourceID == context.selectedSourceID ||
              (!context.selectedSourceAvailable && !context.requiresMIDISourceForGameplay) else {
            publishMIDIDiagnostics(event: event, mappedDrumType: nil)
            return nil
        }

        guard let drumType = context.midiMapping[event.note] else {
            publishMIDIDiagnostics(event: event, mappedDrumType: nil)
            return nil
        }

        let elapsedTime = gameplayElapsedTime(for: event, context: context)
        guard let elapsedTime else {
            publishMIDIDiagnostics(event: event, mappedDrumType: drumType)
            return nil
        }
        guard elapsedTime >= 0 else {
            publishMIDIDiagnostics(event: event, mappedDrumType: drumType)
            return nil
        }

        let hitTimestamp = context.songStartTime?.addingTimeInterval(elapsedTime) ?? Date()
        let velocity = min(1.0, max(0.0, Double(event.velocity) / 127.0))
        let hit = InputHit(drumType: drumType, velocity: velocity, timestamp: hitTimestamp)
        let result = calculateNoteMatch(for: hit, elapsedTime: elapsedTime, matcher: context.inputTimingMatcher)

        publishMIDIDiagnostics(event: event, mappedDrumType: drumType)
        notifyDelegate(hit: hit, result: result)
        return result
    }

    func handleSelectedSourceDisconnect(sourceID: String) {
        let shouldNotify = withRuntimeState {
            guard sourceID == selectedSourceIDSnapshot else { return false }
            selectedMIDISourceAvailableSnapshot = false
            return true
        }
        guard shouldNotify else { return }

        if Thread.isMainThread {
            delegate?.inputManagerSelectedMIDISourceDisconnected(self)
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.inputManagerSelectedMIDISourceDisconnected(self)
            }
        }
    }

    func handleSelectedSourceReconnect(sourceID: String) {
        let shouldRefresh = withRuntimeState {
            guard sourceID == selectedSourceIDSnapshot,
                  !selectedMIDISourceAvailableSnapshot else { return false }
            return true
        }
        guard shouldRefresh else { return }

        // Let refreshMIDISourceAvailabilitySnapshot() determine the correct
        // state based on actual connection state rather than eagerly assuming
        // available — the reconnection may fail if MIDIPortConnectSource errors.
        refreshMIDISourceAvailabilitySnapshot()
    }

    func processInput(_ drumType: DrumType, velocity: Double = 1.0) {
        let context = currentKeyboardInputContext()
        guard let songStartTime = context.songStartTime else { return }

        let now = Date()
        let hit = InputHit(drumType: drumType, velocity: velocity, timestamp: now)

        // Calculate timing relative to song start
        // Skip hits that arrive before audio has started (e.g. during the
        // 50 ms scheduled-start window).  MIDI's host-time path applies the
        // same guard via `hostElapsed >= 0`; this brings keyboard in line.
        // When resuming or speed-changing, songStartTime is backdated by elapsedOffset,
        // so we must check against the effective audio start time (songStartTime + elapsedOffset).
        let effectiveAudioStartTime = songStartTime.addingTimeInterval(context.elapsedOffset)
        guard now.timeIntervalSince(effectiveAudioStartTime) >= 0 else { return }
        let elapsedTime = now.timeIntervalSince(songStartTime)
        let result = calculateNoteMatch(for: hit, elapsedTime: elapsedTime, matcher: context.inputTimingMatcher)
        
        // Notify delegate on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.inputManager(self, didReceiveHit: hit)
            self.delegate?.inputManager(self, didMatchNote: result)
        }
    }
    
    private func calculateNoteMatch(
        for hit: InputHit,
        elapsedTime: Double,
        matcher: InputTimingMatcher?
    ) -> NoteMatchResult {
        guard let matcher else {
            preconditionFailure("InputManager.configure must be called before processing input")
        }
        return matcher.calculateNoteMatch(for: hit, elapsedTime: elapsedTime)
    }

    private func gameplayElapsedTime(
        for event: MIDINoteEvent,
        context: MIDINoteHandlingContext
    ) -> Double? {
        if let songStartHostTime = context.songStartHostTime {
            // Some MIDI drivers emit packets with timeStamp == 0, meaning the
            // device did not provide a host timestamp.  Treat hostTime == 0 as
            // "unknown host time" and fall back to wall-clock timing with the
            // same effective-audio-start guard used by the keyboard path.
            if event.hostTime == 0 {
                return wallClockElapsedTime(
                    songStartTime: context.songStartTime,
                    elapsedOffset: context.hostTimeElapsedOffset
                )
            }

            let hostElapsed = hostTimeConverter.elapsedSeconds(from: songStartHostTime, to: event.hostTime)
            if hostElapsed >= 0 {
                return hostElapsed + context.hostTimeElapsedOffset
            }
            Logger.warning(
                "Received MIDI event with host time earlier than playback start; rejecting hit"
            )
            // When hostElapsed is negative the hit arrived before audio actually started
            // (e.g. during the scheduled-start window after resume or speed change).
            // Do NOT fall back to wall-clock timing — songStartTime is backdated on
            // resume, so wall-clock would compute a large positive value and score the
            // hit against a note that hasn't been reached yet.
            return nil
        }

        if let songStartTime = context.songStartTime {
            return Date().timeIntervalSince(songStartTime)
        }

        return nil
    }

    /// Wall-clock elapsed time with effective-audio-start guard.
    ///
    /// When resuming or changing speed, `songStartTime` is backdated by
    /// `elapsedOffset`, so `Date() - songStartTime` alone would be positive
    /// even before audio actually starts.  The guard compares against the
    /// effective audio start (`songStartTime + elapsedOffset`) to reject
    /// pre-start hits.
    private func wallClockElapsedTime(songStartTime: Date?, elapsedOffset: Double) -> Double? {
        guard let songStartTime else { return nil }
        let effectiveAudioStartTime = songStartTime.addingTimeInterval(elapsedOffset)
        guard Date().timeIntervalSince(effectiveAudioStartTime) >= 0 else { return nil }
        return Date().timeIntervalSince(songStartTime)
    }

    private func consumeLearnSessionIfNeeded(_ event: MIDINoteEvent) {
        let isCapturing = withRuntimeState { learnSessionIsCapturingSnapshot }
        guard isCapturing else { return }

        let selectedSourceID = currentSelectedSourceID()
        if Thread.isMainThread {
            let consumed = MainActor.assumeIsolated {
                learnSession.consume(event, selectedSourceID: selectedSourceID)
            }
            if consumed {
                reloadMappingsFromSettings()
            }
        } else {
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.learnSession.consume(event, selectedSourceID: selectedSourceID) {
                    self.reloadMappingsFromSettings()
                }
            }
        }
    }

    private func publishMIDIDiagnostics(event: MIDINoteEvent, mappedDrumType: DrumType?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.diagnosticsStore.record(
                event: event,
                mappedDrumType: mappedDrumType,
                sourceDisplayName: self.deviceRegistry.displayName(for: event.sourceID)
            )
        }
    }

    private func notifyDelegate(hit: InputHit, result: NoteMatchResult) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.inputManager(self, didReceiveHit: hit)
            self.delegate?.inputManager(self, didMatchNote: result)
        }
    }
}

// MARK: - Keyboard Input (macOS only)

#if os(macOS)
extension InputManager {
    private func startKeyboardListening() {
        // Stop any existing monitors first
        stopKeyboardListening()
        
        // Store monitors for proper cleanup
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyboardEvent(event)
        }
        
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyboardEvent(event)
            return event
        }
    }
    
    private func stopKeyboardListening() {
        // Remove global event monitor
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
            globalEventMonitor = nil
        }
        
        // Remove local event monitor
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }
    }
    
    private func handleKeyboardEvent(_ event: NSEvent) {
        // Guard against nil or invalid events
        guard event.type == .keyDown else { return }
        
        let keyString = keyStringFromEvent(event)
        
        // Validate key string is not empty
        guard !keyString.isEmpty else { return }
        
        let context = currentKeyboardInputContext()
        if let drumType = context.keyboardMapping[keyString] {
            // Clamp velocity to valid range [0.1, 1.0]
            let rawVelocity = Double(event.pressure)
            let velocity = min(1.0, max(0.1, rawVelocity.isFinite ? rawVelocity : 1.0))
            processInput(drumType, velocity: velocity)
        }
    }
    
    private func keyStringFromEvent(_ event: NSEvent) -> String {
        // Handle special keys first
        switch event.keyCode {
        case 49: return "space"
        case 53: return "escape"
        case 36: return "return"
        case 48: return "tab"
        case 51: return "delete"
        case 123: return "left"
        case 124: return "right"
        case 125: return "down"
        case 126: return "up"
        case 3: return "f"
        case 38: return "j"
        case 2: return "d"
        case 40: return "k"
        case 1: return "s"
        case 37: return "l"
        case 41: return "semicolon"
        case 5: return "g"
        default:
            // For regular keys, use the character representation
            if let characters = event.characters?.lowercased(), !characters.isEmpty {
                return characters
            }
            // Fallback to key code for unmappable keys
            return "key\(event.keyCode)"
        }
    }
}
#else
extension InputManager {
    private func startKeyboardListening() {
        // iOS keyboard support would be implemented differently
        // Potentially using UIKit responder chain or hardware keyboard detection
    }
    
    private func stopKeyboardListening() {
        // iOS implementation
    }
}
#endif

// MARK: - MIDI Input

extension InputManager {
    private func setupMIDI() {
        var didSucceed = false
        midiConnectionQueue.sync {
            didSucceed = setupMIDILocked()
        }
        if didSucceed {
            startMIDIMonitoring()
        }
    }

    @discardableResult
    private func setupMIDILocked() -> Bool {
        var status: OSStatus
        
        // Create MIDI client
        status = MIDIClientCreateWithBlock("VirgoInputManager" as CFString, &midiClient) { [weak self] _ in
            self?.midiConnectionQueue.async { [weak self] in
                self?.refreshMIDISourceConnectionsLocked()
            }
        }
        
        guard status == noErr else {
            Logger.error("Failed to create MIDI client for InputManager (status: \(status))")
            midiSetupFailed = true
            return false
        }
        
        // Create input port
        status = MIDIInputPortCreateWithBlock(midiClient, "VirgoInput" as CFString, &midiInputPort) { [weak self] packetList, srcConnRefCon in
            guard let self,
                  let sourceID = self.beginMIDISourceCallback(refCon: srcConnRefCon) else { return }
            defer { self.endMIDISourceCallback(sourceID: sourceID) }
            self.handleMIDIPacketList(packetList, sourceID: sourceID)
        }
        
        if status != noErr {
            Logger.error("Failed to create MIDI input port for InputManager (status: \(status))")
            MIDIClientDispose(midiClient)
            midiClient = 0
            midiInputPort = 0
            midiSetupFailed = true
            return false
        }
        
        refreshMIDISourceConnectionsLocked()
        return true
    }
    
    private func teardownMIDI() {
        midiConnectionQueue.sync {
            teardownMIDILocked()
        }
    }

    private func teardownMIDILocked() {
        disconnectMIDISources()

        if midiInputPort != 0 {
            MIDIPortDispose(midiInputPort)
            midiInputPort = 0
        }
        if midiClient != 0 {
            MIDIClientDispose(midiClient)
            midiClient = 0
        }

        releaseMIDISourceContexts()
    }
    
    private func refreshMIDISourceConnections() {
        midiConnectionQueue.sync {
            refreshMIDISourceConnectionsLocked()
        }
    }

    static func shouldConnectMIDISource(
        _ source: MIDIEndpointRef,
        existingConnectedSources: Set<MIDIEndpointRef>
    ) -> Bool {
        !existingConnectedSources.contains(source)
    }

    /// Computes the diff between current system endpoints and already-connected
    /// endpoints.  Extracted as a pure static function so the decision logic can
    /// be unit-tested without CoreMIDI.
    struct MIDISourceDiff {
        let toConnect: Set<MIDIEndpointRef>
        let toDisconnect: Set<MIDIEndpointRef>
        var hasChanges: Bool { !toConnect.isEmpty || !toDisconnect.isEmpty }
    }

    static func computeMIDISourceDiff(
        currentEndpoints: Set<MIDIEndpointRef>,
        connectedEndpoints: Set<MIDIEndpointRef>
    ) -> MIDISourceDiff {
        MIDISourceDiff(
            toConnect: currentEndpoints.subtracting(connectedEndpoints),
            toDisconnect: connectedEndpoints.subtracting(currentEndpoints)
        )
    }

    /// Identifies already-connected endpoints whose stable source ID collides
    /// with a new endpoint about to be connected.  This happens when CoreMIDI
    /// re-enumerates a physical device under a new `MIDIEndpointRef` while the
    /// old ref is still visible.  Both endpoints share the same unique ID /
    /// stable source ID, so the stale one must be replaced to avoid duplicate
    /// MIDI event delivery.
    ///
    /// Pure static function for testability — callers resolve stable IDs via
    /// CoreMIDI before calling.
    static func findStaleConnectedEndpoints(
        connectedSourceIDs: [MIDIEndpointRef: String],
        newEndpointSourceIDs: [MIDIEndpointRef: String]
    ) -> Set<MIDIEndpointRef> {
        let newStableIDs = Set(newEndpointSourceIDs.values)
        var stale = Set<MIDIEndpointRef>()
        for (endpoint, sourceID) in connectedSourceIDs {
            if newStableIDs.contains(sourceID) {
                stale.insert(endpoint)
            }
        }
        return stale
    }

    static func shouldWaitForMIDICallbacksToDrain(
        activeCallbacksBySourceID: [String: Int],
        pausedSourceIDs: Set<String>
    ) -> Bool {
        guard !pausedSourceIDs.isEmpty else { return false }

        for sourceID in pausedSourceIDs {
            if let activeCount = activeCallbacksBySourceID[sourceID], activeCount > 0 {
                return true
            }
        }
        return false
    }

    private func refreshMIDISourceConnectionsLocked() {
        guard midiInputPort != 0 else { return }

        // Snapshot the current set of MIDI endpoints present on the system.
        let currentEndpoints = Set((0..<MIDIGetNumberOfSources()).map { MIDIGetSource($0) }.filter { $0 != 0 })
        let connectedEndpoints = Set(midiSourceContexts.keys)

        let diff = Self.computeMIDISourceDiff(
            currentEndpoints: currentEndpoints,
            connectedEndpoints: connectedEndpoints
        )

        // Detect stale endpoints: already-connected refs whose stable source ID
        // matches a new endpoint that's about to be connected (device re-enumeration).
        let newEndpointSourceIDs = resolveEndpointSourceIDs(diff.toConnect)
        let connectedSourceIDMap = buildConnectedSourceIDMap()
        let staleEndpoints = Self.findStaleConnectedEndpoints(
            connectedSourceIDs: connectedSourceIDMap,
            newEndpointSourceIDs: newEndpointSourceIDs
        )

        let hasStaleOrChanges = diff.hasChanges || !staleEndpoints.isEmpty
        guard hasStaleOrChanges else { return }

        // Disconnect stale endpoints first to prevent duplicate delivery.
        // Must happen before connecting new endpoints with the same stable ID.
        if !staleEndpoints.isEmpty {
            disconnectSpecificMIDISources(staleEndpoints)
        }

        // Filter toConnect: exclude endpoints whose sourceID is already covered
        // by a remaining (non-stale) connected endpoint.  Without this filter,
        // re-enumeration can oscillate — the previously-stale ref reappears in
        // toConnect on the next refresh and the just-connected replacement is
        // marked stale, causing the algorithm to flip between the two.
        let survivingSourceIDs = Set(
            connectedSourceIDMap
                .filter { !staleEndpoints.contains($0.key) }
                .values
        )
        let endpointsToConnect = diff.toConnect.filter { endpoint in
            guard let sourceID = newEndpointSourceIDs[endpoint] else { return true }
            return !survivingSourceIDs.contains(sourceID)
        }

        // Connect new sources — no pausing needed for additions.
        connectNewMIDISources(endpointsToConnect)

        // Disconnect removed sources only.
        if !diff.toDisconnect.isEmpty {
            disconnectSpecificMIDISources(diff.toDisconnect)
        }
    }

    private func resolveEndpointSourceIDs(
        _ endpoints: Set<MIDIEndpointRef>
    ) -> [MIDIEndpointRef: String] {
        var result: [MIDIEndpointRef: String] = [:]
        for endpoint in endpoints {
            guard let uniqueID = CoreMIDISourceMetadata.uniqueID(for: endpoint) else { continue }
            result[endpoint] = sourceIDResolver.stableSourceID(for: uniqueID)
        }
        return result
    }

    private func buildConnectedSourceIDMap() -> [MIDIEndpointRef: String] {
        var result: [MIDIEndpointRef: String] = [:]
        for (endpoint, context) in midiSourceContexts {
            result[endpoint] = context.takeUnretainedValue().sourceID
        }
        return result
    }

    private func connectNewMIDISources(_ newEndpoints: Set<MIDIEndpointRef>) {
        for source in newEndpoints {
            guard let uniqueID = CoreMIDISourceMetadata.uniqueID(for: source) else { continue }
            let sourceID = sourceIDResolver.stableSourceID(for: uniqueID)

            let context = Unmanaged.passRetained(
                MIDISourceConnectionContext(sourceID: sourceID)
            )

            let status = MIDIPortConnectSource(midiInputPort, source, context.toOpaque())
            guard status == noErr else {
                Logger.error(
                    "Failed to connect InputManager MIDI input port to source \(sourceID) (status: \(status))"
                )
                context.release()
                continue
            }

            midiSourceContexts[source] = context
        }
    }

    private func disconnectSpecificMIDISources(_ sources: Set<MIDIEndpointRef>) {
        // Collect source IDs before removing contexts so we know which callbacks to reject.
        var sourceIDsToPause: Set<String> = []
        for source in sources {
            if let context = midiSourceContexts[source] {
                sourceIDsToPause.insert(context.takeUnretainedValue().sourceID)
            }
        }

        pauseMIDICallbacksForSources(sourceIDsToPause)

        var contextsToRelease: [Unmanaged<MIDISourceConnectionContext>] = []

        for source in sources {
            guard let context = midiSourceContexts.removeValue(forKey: source) else { continue }

            let status = MIDIPortDisconnectSource(midiInputPort, source)
            if status == noErr {
                contextsToRelease.append(context)
            } else {
                Logger.error("Failed to disconnect InputManager MIDI source (status: \(status))")
                midiSourceContexts[source] = context
            }
        }

        waitForMIDICallbacksToDrain(pausedSourceIDs: sourceIDsToPause)

        for context in contextsToRelease {
            context.release()
        }

        resumeMIDICallbacksForSources(sourceIDsToPause)
    }
    
    private func disconnectMIDISources() {
        let retainedContexts = midiSourceContexts
        let allSourceIDs = Set(retainedContexts.values.map { $0.takeUnretainedValue().sourceID })
        pauseMIDICallbacksForSources(allSourceIDs)

        midiSourceContexts.removeAll()
        var contextsToRelease: [Unmanaged<MIDISourceConnectionContext>] = []

        for (source, context) in retainedContexts {
            guard midiInputPort != 0 else {
                contextsToRelease.append(context)
                continue
            }

            let status = MIDIPortDisconnectSource(midiInputPort, source)
            if status == noErr {
                contextsToRelease.append(context)
            } else {
                Logger.error("Failed to disconnect InputManager MIDI source \(context.takeUnretainedValue().sourceID) (status: \(status))")
                midiSourceContexts[source] = context
            }
        }

        waitForMIDICallbacksToDrain(pausedSourceIDs: allSourceIDs)

        for context in contextsToRelease {
            context.release()
        }

        resumeMIDICallbacksForSources(allSourceIDs)
    }

    private func handleMIDIPacketList(_ packetList: UnsafePointer<MIDIPacketList>, sourceID: String) {
        let packets = eventRouter.convertPacketList(packetList)
        let events = eventRouter.decodeEvents(from: packets, sourceID: sourceID)

        for event in events {
            _ = handleMIDINoteEvent(event)
        }
    }
}

// MARK: - Public Configuration Methods

extension InputManager {
    func setKeyboardMapping(_ mapping: [String: DrumType]) {
        updateRuntimeState {
            keyboardMapping = mapping
            keyboardMappingHasRuntimeOverride = true
        }
    }
    
    func setMIDIMapping(_ mapping: [UInt8: DrumType]) {
        updateRuntimeState {
            midiMapping = mapping
            midiMappingSnapshot = mapping
            midiMappingHasRuntimeOverride = true
        }
    }
    
    func getKeyboardMapping() -> [String: DrumType] {
        withRuntimeState { keyboardMapping }
    }
    
    func getMIDIMapping() -> [UInt8: DrumType] {
        withRuntimeState { midiMapping }
    }
}

private extension InputManager {
    func beginMIDISourceCallback(refCon: UnsafeMutableRawPointer?) -> String? {
        guard let refCon else { return nil }

        // Dereference refCon INSIDE the lock to prevent use-after-free.
        // disconnectSpecificMIDISources only releases contexts after
        // waitForMIDICallbacksToDrain returns, which requires the count to
        // reach zero while holding this lock.  By reading the context under
        // the same lock, we guarantee the context is still alive — the release
        // cannot happen until every in-flight callback has decremented the
        // count and released this lock.
        midiCallbackDrain.lock()
        let sourceID = Unmanaged<MIDISourceConnectionContext>.fromOpaque(refCon).takeUnretainedValue().sourceID
        guard !disconnectingSourceIDs.contains(sourceID) else {
            midiCallbackDrain.unlock()
            return nil
        }
        activeMIDICallbackCountsBySourceID[sourceID, default: 0] += 1
        midiCallbackDrain.unlock()

        return sourceID
    }

    func endMIDISourceCallback(sourceID: String) {
        midiCallbackDrain.lock()
        let nextCount = (activeMIDICallbackCountsBySourceID[sourceID] ?? 0) - 1
        if nextCount > 0 {
            activeMIDICallbackCountsBySourceID[sourceID] = nextCount
        } else {
            activeMIDICallbackCountsBySourceID.removeValue(forKey: sourceID)
        }
        midiCallbackDrain.broadcast()
        midiCallbackDrain.unlock()
    }

    func pauseMIDICallbacksForSources(_ sourceIDs: Set<String>) {
        midiCallbackDrain.lock()
        disconnectingSourceIDs.formUnion(sourceIDs)
        midiCallbackDrain.unlock()
    }

    func resumeMIDICallbacksForSources(_ sourceIDs: Set<String>) {
        midiCallbackDrain.lock()
        disconnectingSourceIDs.subtract(sourceIDs)
        midiCallbackDrain.unlock()
    }

    func waitForMIDICallbacksToDrain(pausedSourceIDs: Set<String>) {
        midiCallbackDrain.lock()
        while Self.shouldWaitForMIDICallbacksToDrain(
            activeCallbacksBySourceID: activeMIDICallbackCountsBySourceID,
            pausedSourceIDs: pausedSourceIDs
        ) {
            midiCallbackDrain.wait()
        }
        midiCallbackDrain.unlock()
    }

    func releaseMIDISourceContexts() {
        let retainedContexts = midiSourceContexts
        midiSourceContexts.removeAll()

        for (_, context) in retainedContexts {
            context.release()
        }
    }
}
