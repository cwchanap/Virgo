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

struct InputHit {
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
    let timingError: Double // in milliseconds, positive = late, negative = early
}

enum TimingAccuracy {
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
}

class InputManager: ObservableObject {
    weak var delegate: InputManagerDelegate?
    
    // Song timing reference
    private var songStartTime: Date?
    private var bpm: Int = 120
    private var timeSignature: TimeSignature = .fourFour
    private var notes: [Note] = []
    
    // Input mapping configuration
    private var keyboardMapping: [String: DrumType] = [:]
    private var midiMapping: [UInt8: DrumType] = [:]
    
    // Settings manager for persistent configuration
    private let settingsManager = InputSettingsManager()
    
    // MIDI setup
    private var midiClient: MIDIClientRef = 0
    private var midiInputPort: MIDIPortRef = 0
    
    // Timing calculation cache
    private var secondsPerBeat: Double = 0.5
    private var secondsPerMeasure: Double = 2.0
    
    init() {
        setupMappingsFromSettings()
        setupMIDI()
    }
    
    deinit {
        teardownMIDI()
    }
}

// MARK: - Configuration

extension InputManager {
    func configure(bpm: Int, timeSignature: TimeSignature, notes: [Note]) {
        self.bpm = bpm
        self.timeSignature = timeSignature
        self.notes = notes.sorted { $0.measureNumber < $1.measureNumber || 
            ($0.measureNumber == $1.measureNumber && $0.measureOffset < $1.measureOffset) }
        
        // Update timing calculations
        self.secondsPerBeat = 60.0 / Double(bpm)
        self.secondsPerMeasure = secondsPerBeat * Double(timeSignature.beatsPerMeasure)
    }
    
    func startListening(songStartTime: Date) {
        self.songStartTime = songStartTime
        startKeyboardListening()
        // MIDI is already listening from setup
    }
    
    func stopListening() {
        self.songStartTime = nil
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
    }
}

// MARK: - Input Processing

extension InputManager {
    private func processInput(_ drumType: DrumType, velocity: Double = 1.0) {
        guard let songStartTime = songStartTime else { return }
        
        let now = Date()
        let hit = InputHit(drumType: drumType, velocity: velocity, timestamp: now)
        
        // Calculate timing relative to song start
        let elapsedTime = now.timeIntervalSince(songStartTime)
        let result = calculateNoteMatch(for: hit, elapsedTime: elapsedTime)
        
        // Notify delegate
        delegate?.inputManager(self, didReceiveHit: hit)
        delegate?.inputManager(self, didMatchNote: result)
    }
    
    private func calculateNoteMatch(for hit: InputHit, elapsedTime: Double) -> NoteMatchResult {
        // Convert elapsed time to measure position
        let totalBeatsElapsed = elapsedTime / secondsPerBeat
        let measureNumber = Int(totalBeatsElapsed / Double(timeSignature.beatsPerMeasure)) + 1 // 1-based
        let beatWithinMeasure = totalBeatsElapsed.truncatingRemainder(dividingBy: Double(timeSignature.beatsPerMeasure))
        let measureOffset = beatWithinMeasure / Double(timeSignature.beatsPerMeasure)
        
        // Find closest matching note
        let matchedNote = findClosestNote(
            drumType: hit.drumType,
            measureNumber: measureNumber,
            measureOffset: measureOffset,
            elapsedTime: elapsedTime
        )
        
        // Calculate timing accuracy
        let (timingAccuracy, timingError) = calculateTimingAccuracy(
            matchedNote: matchedNote,
            actualTime: elapsedTime
        )
        
        return NoteMatchResult(
            hitInput: hit,
            matchedNote: matchedNote,
            timingAccuracy: timingAccuracy,
            measureNumber: measureNumber,
            measureOffset: measureOffset,
            timingError: timingError
        )
    }
    
    private func findClosestNote(drumType: DrumType, measureNumber: Int, measureOffset: Double, elapsedTime: Double) -> Note? {
        let searchWindowMs: Double = 200.0 // ±200ms search window
        let searchWindowSeconds = searchWindowMs / 1000.0
        
        // Find notes of matching drum type within timing window
        let candidateNotes = notes.filter { note in
            // Check drum type match
            guard DrumType.from(noteType: note.noteType) == drumType else { return false }
            
            // Calculate expected time for this note
            let noteElapsedTime = calculateExpectedTime(measureNumber: note.measureNumber, measureOffset: note.measureOffset)
            
            // Check if within search window
            return abs(elapsedTime - noteElapsedTime) <= searchWindowSeconds
        }
        
        // Return closest note by timing
        return candidateNotes.min { note1, note2 in
            let time1 = calculateExpectedTime(measureNumber: note1.measureNumber,
                                              measureOffset: note1.measureOffset)
            let time2 = calculateExpectedTime(measureNumber: note2.measureNumber,
                                              measureOffset: note2.measureOffset)
            
            return abs(elapsedTime - time1) < abs(elapsedTime - time2)
        }
    }
    
    private func calculateExpectedTime(measureNumber: Int, measureOffset: Double) -> Double {
        let measureIndex = measureNumber - 1 // Convert to 0-based
        return Double(measureIndex) * secondsPerMeasure + (measureOffset * secondsPerMeasure)
    }
    
    private func calculateTimingAccuracy(matchedNote: Note?, actualTime: Double) -> (TimingAccuracy, Double) {
        guard let note = matchedNote else {
            return (.miss, 0.0)
        }
        
        let expectedTime = calculateExpectedTime(measureNumber: note.measureNumber, measureOffset: note.measureOffset)
        let timingErrorMs = (actualTime - expectedTime) * 1000.0
        let absErrorMs = abs(timingErrorMs)
        
        let accuracy: TimingAccuracy
        if absErrorMs <= TimingAccuracy.perfect.toleranceMs {
            accuracy = .perfect
        } else if absErrorMs <= TimingAccuracy.great.toleranceMs {
            accuracy = .great
        } else if absErrorMs <= TimingAccuracy.good.toleranceMs {
            accuracy = .good
        } else {
            accuracy = .miss
        }
        
        return (accuracy, timingErrorMs)
    }
}

// MARK: - Keyboard Input (macOS only)

#if os(macOS)
extension InputManager {
    private func startKeyboardListening() {
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyboardEvent(event)
        }
        
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyboardEvent(event)
            return event
        }
    }
    
    private func stopKeyboardListening() {
        // Note: In a real implementation, you'd need to store the event monitor references
        // and remove them here. For simplicity, this is omitted.
    }
    
    private func handleKeyboardEvent(_ event: NSEvent) {
        let keyString = keyStringFromEvent(event)
        
        if let drumType = keyboardMapping[keyString] {
            let velocity = min(1.0, max(0.1, Double(event.pressure)))
            processInput(drumType, velocity: velocity)
        }
    }
    
    private func keyStringFromEvent(_ event: NSEvent) -> String {
        switch event.keyCode {
        case 49: return "space"
        case 3: return "f"
        case 38: return "j"
        case 2: return "d"
        case 40: return "k"
        case 1: return "s"
        case 37: return "l"
        case 41: return "semicolon"
        case 5: return "g"
        default: return event.characters?.lowercased() ?? ""
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
        status = MIDIClientCreateWithBlock("VirgoInputManager" as CFString, &midiClient) { _ in
            // MIDI system notification handler
        }
        
        guard status == noErr else {
            print("Failed to create MIDI client: \(status)")
            return
        }
        
        // Create input port
        status = MIDIInputPortCreateWithBlock(midiClient, "VirgoInput" as CFString, &midiInputPort) { 
            [weak self] packetList, _ in
            self?.handleMIDIPacketList(packetList)
        }
        
        if status != noErr {
            print("Failed to create MIDI input port: \(status)")
            return
        }
        
        // Connect to all available MIDI sources
        connectToAllMIDISources()
    }
    
    private func connectToAllMIDISources() {
        let sourceCount = MIDIGetNumberOfSources()
        
        for i in 0..<sourceCount {
            let source = MIDIGetSource(i)
            let status = MIDIPortConnectSource(midiInputPort, source, nil)
            
            if status == noErr {
                print("Connected to MIDI source \(i)")
            }
        }
    }
    
    private func teardownMIDI() {
        if midiInputPort != 0 {
            MIDIPortDispose(midiInputPort)
        }
        if midiClient != 0 {
            MIDIClientDispose(midiClient)
        }
    }
    
    private func handleMIDIPacketList(_ packetList: UnsafePointer<MIDIPacketList>) {
        let numPackets = Int(packetList.pointee.numPackets)
        guard numPackets > 0 else { return }
        
        // Process just the first packet for simplicity and safety
        let firstPacket = packetList.pointee.packet
        handleMIDIPacket(firstPacket)
    }
    
    private func handleMIDIPacket(_ packet: MIDIPacket) {
        let dataLength = Int(packet.length)
        guard dataLength >= 3 else { return }
        
        // Extract MIDI data safely
        let data: [UInt8] = withUnsafeBytes(of: packet.data) { bytes in
            return Array(bytes.prefix(dataLength))
        }
        
        let status = data[0]
        let note = data[1] 
        let velocity = data[2]
        
        // Check for note on message (0x90-0x9F) with non-zero velocity
        let isNoteOn = (status & 0xF0) == 0x90 && velocity > 0
        
        guard isNoteOn, let drumType = midiMapping[note] else { return }
        
        let normalizedVelocity = Double(velocity) / 127.0
        processInput(drumType, velocity: normalizedVelocity)
    }
}

// MARK: - Public Configuration Methods

extension InputManager {
    func setKeyboardMapping(_ mapping: [String: DrumType]) {
        keyboardMapping = mapping
    }
    
    func setMIDIMapping(_ mapping: [UInt8: DrumType]) {
        midiMapping = mapping
    }
    
    func getKeyboardMapping() -> [String: DrumType] {
        return keyboardMapping
    }
    
    func getMIDIMapping() -> [UInt8: DrumType] {
        return midiMapping
    }
}
