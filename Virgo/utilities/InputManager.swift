//
//  InputManager.swift
//  Virgo
//
//  Created by Claude Code on 9/8/2025.
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
    let measureNumber: Int
    let measureOffset: Double
    let timingError: Double? // in milliseconds, positive = late, negative = early; nil when no note matched
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
    private var activeMIDICallbackCount = 0
    private var midiCallbacksPaused = false
    
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
        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                deviceRegistry.isSelectedSourceAvailable
            }
        }
        return withRuntimeState { selectedMIDISourceAvailableSnapshot }
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
    private var learnSessionCaptureCancellable: AnyCancellable?
    
    // MIDI setup
    private var midiClient: MIDIClientRef = 0
    private var midiInputPort: MIDIPortRef = 0
    private var midiSourceContexts: [MIDIEndpointRef: Unmanaged<MIDISourceConnectionContext>] = [:]
    
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
        let midiMapping: [UInt8: DrumType]
        let inputTimingMatcher: InputTimingMatcher?
    }

    private struct KeyboardInputContext {
        let songStartTime: Date?
        let keyboardMapping: [String: DrumType]
        let inputTimingMatcher: InputTimingMatcher?
    }
    
    /// Creates an `InputManager`.
    ///
    /// When you use the default MIDI dependencies, instantiate `InputManager` on the main thread.
    /// The factory helpers `makeDefaultDeviceRegistry`, `makeDefaultDiagnosticsStore`, and
    /// `makeDefaultLearnSession` must be invoked on the main thread and call
    /// `preconditionFailure` otherwise. If you need to create `InputManager` off the main thread,
    /// provide custom `deviceRegistry`, `diagnosticsStore`, and `learnSession` instances.
    init(
        settingsManager: InputSettingsManager? = nil,
        deviceRegistry: MIDIDeviceRegistry? = nil,
        eventRouter: MIDIEventRouter = MIDIEventRouter(),
        hostTimeConverter: MIDIHostTimeConverter = MIDIHostTimeConverter(),
        diagnosticsStore: MIDIDiagnosticsStore? = nil,
        learnSession: MIDILearnSession? = nil,
        sourceIDResolver: MIDISourceIDResolving = CoreMIDISourceIDResolver()
    ) {
        let settingsManager = settingsManager ?? InputSettingsManager()

        self.settingsManager = settingsManager
        self.deviceRegistry = deviceRegistry ?? Self.makeDefaultDeviceRegistry(settingsManager: settingsManager)
        self.eventRouter = eventRouter
        self.hostTimeConverter = hostTimeConverter
        self.diagnosticsStore = diagnosticsStore ?? Self.makeDefaultDiagnosticsStore()
        self.learnSession = learnSession ?? Self.makeDefaultLearnSession(settingsManager: settingsManager)
        self.sourceIDResolver = sourceIDResolver
        self.isTestEnvironment = TestEnvironment.isRunningTests
        bindLearnSessionCaptureState()
        reloadMappingsFromSettings()

        // Only set up MIDI if not in test environment
        if !isTestEnvironment {
            setupMIDI()
        }
    }

    deinit {
        guard !isTestEnvironment else { return }
        
        // Clean up keyboard event monitors
        #if os(macOS)
        stopKeyboardListening()
        #endif
        
        // Clean up MIDI resources
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
                midiMapping: midiMappingSnapshot,
                inputTimingMatcher: inputTimingMatcher
            )
        }
    }

    private func currentKeyboardInputContext() -> KeyboardInputContext {
        withRuntimeState {
            KeyboardInputContext(
                songStartTime: songStartTime,
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
        // Validate BPM range to prevent division by zero and unrealistic values
        guard bpm > 0.1 && bpm <= 1000.0 else {
            preconditionFailure("BPM must be between 0.1 and 1000.0, got: \(bpm)")
        }
        
        // Validate time signature
        guard timeSignature.beatsPerMeasure > 0 else {
            preconditionFailure("Time signature beats per measure must be positive, got: \(timeSignature.beatsPerMeasure)")
        }
        
        let sortedNotes = notes.sorted { $0.measureNumber < $1.measureNumber ||
            ($0.measureNumber == $1.measureNumber && $0.measureOffset < $1.measureOffset) }
        let secondsPerBeat = 60.0 / bpm
        let secondsPerMeasure = secondsPerBeat * Double(timeSignature.beatsPerMeasure)
        let timingMatcher = InputTimingMatcher(bpm: bpm, timeSignature: timeSignature, notes: sortedNotes)

        updateRuntimeState {
            self.bpm = bpm
            self.timeSignature = timeSignature
            self.notes = sortedNotes
            self.secondsPerBeat = secondsPerBeat
            self.secondsPerMeasure = secondsPerMeasure
            self.inputTimingMatcher = timingMatcher
        }
    }
    
    func startListening(songStartTime: Date, elapsedOffset: Double = 0.0) {
        let songStartHostTime = mach_absolute_time()
        updateRuntimeState {
            self.songStartTime = songStartTime
            self.songStartHostTime = songStartHostTime
            self.hostTimeElapsedOffset = elapsedOffset
        }
        refreshSelectedMIDISourceStateFromSettings()
        startKeyboardListening()
        // MIDI is already listening from setup
    }
    
    func stopListening() {
        updateRuntimeState {
            self.songStartTime = nil
            self.songStartHostTime = nil
            self.hostTimeElapsedOffset = 0.0
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
                deviceRegistry.startMonitoring()
                updateSelectedMIDISourceAvailabilitySnapshot(deviceRegistry.isSelectedSourceAvailable)
            }
        } else {
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.deviceRegistry.onSelectedSourceUnavailable = { [weak self] sourceID in
                    self?.handleSelectedSourceDisconnect(sourceID: sourceID)
                }
                self.deviceRegistry.startMonitoring()
                self.updateSelectedMIDISourceAvailabilitySnapshot(self.deviceRegistry.isSelectedSourceAvailable)
            }
        }
    }

    private func refreshMIDISourceAvailabilitySnapshot() {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                deviceRegistry.refreshSources()
                updateSelectedMIDISourceAvailabilitySnapshot(deviceRegistry.isSelectedSourceAvailable)
            }
        } else {
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.deviceRegistry.refreshSources()
                self.updateSelectedMIDISourceAvailabilitySnapshot(self.deviceRegistry.isSelectedSourceAvailable)
            }
        }
    }
}

// MARK: - Input Processing

extension InputManager {
    @discardableResult
    func handleMIDINoteEvent(_ event: MIDINoteEvent) -> NoteMatchResult? {
        consumeLearnSessionIfNeeded(event)
        let context = currentMIDINoteHandlingContext()

        guard context.selectedSourceID == nil || event.sourceID == context.selectedSourceID else {
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

    private func processInput(_ drumType: DrumType, velocity: Double = 1.0) {
        let context = currentKeyboardInputContext()
        guard let songStartTime = context.songStartTime else { return }
        
        let now = Date()
        let hit = InputHit(drumType: drumType, velocity: velocity, timestamp: now)
        
        // Calculate timing relative to song start
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
            let hostElapsed = hostTimeConverter.elapsedSeconds(from: songStartHostTime, to: event.hostTime)
            if hostElapsed >= 0 {
                return hostElapsed + context.hostTimeElapsedOffset
            }
            Logger.warning(
                "Received MIDI event with host time earlier than playback start; falling back to wall-clock timing"
            )
        }

        if let songStartTime = context.songStartTime {
            return max(0, Date().timeIntervalSince(songStartTime))
        }

        return nil
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
        midiConnectionQueue.sync {
            setupMIDILocked()
        }
        startMIDIMonitoring()
    }

    private func setupMIDILocked() {
        var status: OSStatus
        
        // Create MIDI client
        status = MIDIClientCreateWithBlock("VirgoInputManager" as CFString, &midiClient) { [weak self] _ in
            self?.midiConnectionQueue.async { [weak self] in
                self?.refreshMIDISourceConnectionsLocked()
            }
        }
        
        guard status == noErr else {
            Logger.error("Failed to create MIDI client for InputManager (status: \(status))")
            return
        }
        
        // Create input port
        status = MIDIInputPortCreateWithBlock(midiClient, "VirgoInput" as CFString, &midiInputPort) { [weak self] packetList, srcConnRefCon in
            guard let self,
                  let sourceID = self.beginMIDISourceCallback(refCon: srcConnRefCon) else { return }
            defer { self.endMIDISourceCallback() }
            self.handleMIDIPacketList(packetList, sourceID: sourceID)
        }
        
        if status != noErr {
            Logger.error("Failed to create MIDI input port for InputManager (status: \(status))")
            MIDIClientDispose(midiClient)
            midiClient = 0
            midiInputPort = 0
            return
        }
        
        refreshMIDISourceConnectionsLocked()
    }
    
    private func connectToAllMIDISources() {
        let sourceCount = MIDIGetNumberOfSources()
        
        for i in 0..<sourceCount {
            let source = MIDIGetSource(i)
            guard source != 0,
                  let uniqueID = CoreMIDISourceMetadata.uniqueID(for: source) else { continue }

            let context = Unmanaged.passRetained(
                MIDISourceConnectionContext(sourceID: sourceIDResolver.stableSourceID(for: uniqueID))
            )

            let status = MIDIPortConnectSource(midiInputPort, source, context.toOpaque())
            guard status == noErr else {
                Logger.error(
                    "Failed to connect InputManager MIDI input port to source \(sourceIDResolver.stableSourceID(for: uniqueID)) (status: \(status))"
                )
                context.release()
                continue
            }

            midiSourceContexts[source] = context
        }
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

    private func refreshMIDISourceConnectionsLocked() {
        defer { resumeMIDICallbacks() }
        disconnectMIDISources()

        guard midiInputPort != 0 else { return }
        connectToAllMIDISources()
    }
    
    private func disconnectMIDISources() {
        pauseMIDICallbacks()

        let retainedContexts = midiSourceContexts
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

        waitForMIDICallbacksToDrain()

        for context in contextsToRelease {
            context.release()
        }
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

        midiCallbackDrain.lock()
        guard !midiCallbacksPaused else {
            midiCallbackDrain.unlock()
            return nil
        }
        activeMIDICallbackCount += 1
        midiCallbackDrain.unlock()

        return Unmanaged<MIDISourceConnectionContext>.fromOpaque(refCon).takeUnretainedValue().sourceID
    }

    func endMIDISourceCallback() {
        midiCallbackDrain.lock()
        activeMIDICallbackCount -= 1
        if activeMIDICallbackCount == 0 {
            midiCallbackDrain.broadcast()
        }
        midiCallbackDrain.unlock()
    }

    func pauseMIDICallbacks() {
        midiCallbackDrain.lock()
        midiCallbacksPaused = true
        midiCallbackDrain.unlock()
    }

    func resumeMIDICallbacks() {
        midiCallbackDrain.lock()
        midiCallbacksPaused = false
        midiCallbackDrain.unlock()
    }

    func waitForMIDICallbacksToDrain() {
        midiCallbackDrain.lock()
        while activeMIDICallbackCount > 0 {
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
