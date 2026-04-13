//
//  InputManager.swift
//  Virgo
//
//  Created by Claude Code on 9/8/2025.
//

import Foundation
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
    
    // Song timing reference
    private var songStartTime: Date?
    private var songStartHostTime: UInt64?
    private var bpm: Double = 120.0
    private var timeSignature: TimeSignature = .fourFour
    private var notes: [Note] = []

    var configuredBPM: Double { bpm }
    var hasSelectedMIDISourcePreference: Bool { settingsManager.getSelectedMIDISource() != nil }
    var requiresMIDISourceForGameplay = false
    var isSelectedMIDISourceAvailable: Bool {
        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                deviceRegistry.isSelectedSourceAvailable
            }
        }
        return selectedMIDISourceAvailableSnapshot
    }
    
    // Input mapping configuration
    private var keyboardMapping: [String: DrumType] = [:]
    private var midiMapping: [UInt8: DrumType] = [:]
    private var midiMappingSnapshot: [UInt8: DrumType] = [:]
    private var selectedSourceIDSnapshot: String?
    private var selectedMIDISourceAvailableSnapshot = false
    
    // Settings manager for persistent configuration
    private let settingsManager: InputSettingsManager
    private let deviceRegistry: MIDIDeviceRegistry
    private let eventRouter: MIDIEventRouter
    private let hostTimeConverter: MIDIHostTimeConverter
    private let diagnosticsStore: MIDIDiagnosticsStore
    private let learnSession: MIDILearnSession
    private let sourceIDResolver: MIDISourceIDResolving
    
    // MIDI setup
    private var midiClient: MIDIClientRef = 0
    private var midiInputPort: MIDIPortRef = 0
    private var midiSourceContexts: [MIDIEndpointRef: UnsafeMutablePointer<MIDISourceConnectionContext>] = [:]
    
    // Keyboard event monitors for proper cleanup
    #if os(macOS)
    private var globalEventMonitor: Any?
    private var localEventMonitor: Any?
    #endif
    
    // Timing calculation cache
    private var secondsPerBeat: Double = 0.5
    private var secondsPerMeasure: Double = 2.0
    private var inputTimingMatcher: InputTimingMatcher?
    
    // Test environment detection
    private let isTestEnvironment: Bool

    private struct MIDISourceConnectionContext {
        let sourceID: String
    }
    
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
        
        self.bpm = bpm
        self.timeSignature = timeSignature
        self.notes = notes.sorted { $0.measureNumber < $1.measureNumber || 
            ($0.measureNumber == $1.measureNumber && $0.measureOffset < $1.measureOffset) }
        
        // Update timing calculations with validated values
        self.secondsPerBeat = 60.0 / bpm
        self.secondsPerMeasure = secondsPerBeat * Double(timeSignature.beatsPerMeasure)
        self.inputTimingMatcher = InputTimingMatcher(bpm: bpm, timeSignature: timeSignature, notes: self.notes)
    }
    
    func startListening(songStartTime: Date) {
        self.songStartTime = songStartTime
        self.songStartHostTime = mach_absolute_time()
        reloadMappingsFromSettings()
        startKeyboardListening()
        // MIDI is already listening from setup
    }
    
    func stopListening() {
        self.songStartTime = nil
        self.songStartHostTime = nil
        stopKeyboardListening()
        // MIDI continues to listen but won't process hits without songStartTime
    }
    
    private func setupMappingsFromSettings() {
        // Load mappings from persistent settings
        keyboardMapping = settingsManager.getKeyboardMappings()
        midiMapping = settingsManager.getMidiMappings()
    }
    
    /// Reload mappings from settings (call this when settings are updated)
    func reloadMappingsFromSettings() {
        setupMappingsFromSettings()
        midiMappingSnapshot = midiMapping
        selectedSourceIDSnapshot = settingsManager.getSelectedMIDISource()?.id
        refreshMIDISourceAvailabilitySnapshot()
    }

    func startMIDIMonitoring() {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                deviceRegistry.onSelectedSourceUnavailable = { [weak self] sourceID in
                    self?.handleSelectedSourceDisconnect(sourceID: sourceID)
                }
                deviceRegistry.startMonitoring()
                selectedMIDISourceAvailableSnapshot = deviceRegistry.isSelectedSourceAvailable
            }
        } else {
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.deviceRegistry.onSelectedSourceUnavailable = { [weak self] sourceID in
                    self?.handleSelectedSourceDisconnect(sourceID: sourceID)
                }
                self.deviceRegistry.startMonitoring()
                self.selectedMIDISourceAvailableSnapshot = self.deviceRegistry.isSelectedSourceAvailable
            }
        }
    }

    private func refreshMIDISourceAvailabilitySnapshot() {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                deviceRegistry.refreshSources()
                selectedMIDISourceAvailableSnapshot = deviceRegistry.isSelectedSourceAvailable
            }
        } else {
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.deviceRegistry.refreshSources()
                self.selectedMIDISourceAvailableSnapshot = self.deviceRegistry.isSelectedSourceAvailable
            }
        }
    }
}

// MARK: - Input Processing

extension InputManager {
    @discardableResult
    func handleMIDINoteEvent(_ event: MIDINoteEvent) -> NoteMatchResult? {
        consumeLearnSessionIfNeeded(event)

        guard event.sourceID == selectedSourceIDSnapshot else {
            publishMIDIDiagnostics(event: event, mappedDrumType: nil)
            return nil
        }

        guard let drumType = midiMappingSnapshot[event.note] else {
            publishMIDIDiagnostics(event: event, mappedDrumType: nil)
            return nil
        }

        let elapsedTime = gameplayElapsedTime(for: event)
        guard let elapsedTime else {
            publishMIDIDiagnostics(event: event, mappedDrumType: drumType)
            return nil
        }

        let hitTimestamp = songStartTime?.addingTimeInterval(elapsedTime) ?? Date()
        let velocity = min(1.0, max(0.0, Double(event.velocity) / 127.0))
        let hit = InputHit(drumType: drumType, velocity: velocity, timestamp: hitTimestamp)
        let result = calculateNoteMatch(for: hit, elapsedTime: elapsedTime)

        publishMIDIDiagnostics(event: event, mappedDrumType: drumType)
        notifyDelegate(hit: hit, result: result)
        return result
    }

    func handleSelectedSourceDisconnect(sourceID: String) {
        guard sourceID == selectedSourceIDSnapshot else { return }

        selectedMIDISourceAvailableSnapshot = false

        if Thread.isMainThread {
            delegate?.inputManagerSelectedMIDISourceDisconnected(self)
        } else {
            DispatchQueue.main.async {
                self.delegate?.inputManagerSelectedMIDISourceDisconnected(self)
            }
        }
    }

    private func processInput(_ drumType: DrumType, velocity: Double = 1.0) {
        guard let songStartTime = songStartTime else { return }
        
        let now = Date()
        let hit = InputHit(drumType: drumType, velocity: velocity, timestamp: now)
        
        // Calculate timing relative to song start
        let elapsedTime = now.timeIntervalSince(songStartTime)
        let result = calculateNoteMatch(for: hit, elapsedTime: elapsedTime)
        
        // Notify delegate on main thread
        DispatchQueue.main.async {
            self.delegate?.inputManager(self, didReceiveHit: hit)
            self.delegate?.inputManager(self, didMatchNote: result)
        }
    }
    
    private func calculateNoteMatch(for hit: InputHit, elapsedTime: Double) -> NoteMatchResult {
        guard let matcher = inputTimingMatcher else {
            preconditionFailure("InputManager.configure must be called before processing input")
        }
        return matcher.calculateNoteMatch(for: hit, elapsedTime: elapsedTime)
    }

    private func gameplayElapsedTime(for event: MIDINoteEvent) -> Double? {
        if let songStartHostTime {
            let hostElapsed = hostTimeConverter.elapsedSeconds(from: songStartHostTime, to: event.hostTime)
            if hostElapsed >= 0 {
                return hostElapsed
            }
        }

        if let songStartTime {
            return max(0, Date().timeIntervalSince(songStartTime))
        }

        return nil
    }

    private func consumeLearnSessionIfNeeded(_ event: MIDINoteEvent) {
        if Thread.isMainThread {
            let consumed = MainActor.assumeIsolated {
                learnSession.consume(event, selectedSourceID: selectedSourceIDSnapshot)
            }
            if consumed {
                reloadMappingsFromSettings()
            }
        } else {
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.learnSession.consume(event, selectedSourceID: self.selectedSourceIDSnapshot) {
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
        DispatchQueue.main.async {
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
        
        if let drumType = keyboardMapping[keyString] {
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
        var status: OSStatus
        
        // Create MIDI client
        status = MIDIClientCreateWithBlock("VirgoInputManager" as CFString, &midiClient) { [weak self] _ in
            self?.refreshMIDISourceConnections()
        }
        
        guard status == noErr else {
            print("Failed to create MIDI client: \(status)")
            return
        }
        
        // Create input port
        status = MIDIInputPortCreateWithBlock(midiClient, "VirgoInput" as CFString, &midiInputPort) { [weak self] packetList, srcConnRefCon in
            guard let srcConnRefCon else { return }

            let context = srcConnRefCon.assumingMemoryBound(to: MIDISourceConnectionContext.self).pointee
            self?.handleMIDIPacketList(packetList, sourceID: context.sourceID)
        }
        
        if status != noErr {
            print("Failed to create MIDI input port: \(status)")
            return
        }
        
        refreshMIDISourceConnections()
        startMIDIMonitoring()
    }
    
    private func connectToAllMIDISources() {
        let sourceCount = MIDIGetNumberOfSources()
        
        for i in 0..<sourceCount {
            let source = MIDIGetSource(i)
            guard source != 0,
                  let uniqueID = CoreMIDISourceMetadata.uniqueID(for: source) else { continue }

            let contextPointer = UnsafeMutablePointer<MIDISourceConnectionContext>.allocate(capacity: 1)
            contextPointer.initialize(
                to: MIDISourceConnectionContext(sourceID: sourceIDResolver.stableSourceID(for: uniqueID))
            )

            let status = MIDIPortConnectSource(midiInputPort, source, contextPointer)
            guard status == noErr else {
                contextPointer.deinitialize(count: 1)
                contextPointer.deallocate()
                continue
            }

            midiSourceContexts[source] = contextPointer
        }
    }
    
    private func teardownMIDI() {
        disconnectMIDISources()

        if midiInputPort != 0 {
            MIDIPortDispose(midiInputPort)
            midiInputPort = 0
        }
        if midiClient != 0 {
            MIDIClientDispose(midiClient)
            midiClient = 0
        }
    }
    
    private func refreshMIDISourceConnections() {
        disconnectMIDISources()

        guard midiInputPort != 0 else { return }
        connectToAllMIDISources()
    }
    
    private func disconnectMIDISources() {
        for (source, contextPointer) in midiSourceContexts {
            if midiInputPort != 0 {
                MIDIPortDisconnectSource(midiInputPort, source)
            }

            contextPointer.deinitialize(count: 1)
            contextPointer.deallocate()
        }

        midiSourceContexts.removeAll()
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
        keyboardMapping = mapping
    }
    
    func setMIDIMapping(_ mapping: [UInt8: DrumType]) {
        midiMapping = mapping
        midiMappingSnapshot = mapping
    }
    
    func getKeyboardMapping() -> [String: DrumType] {
        return keyboardMapping
    }
    
    func getMIDIMapping() -> [UInt8: DrumType] {
        return midiMapping
    }
}
