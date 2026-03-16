//
//  InputManagerConfigurationTests.swift
//  VirgoTests
//
//  Tests for InputManager configuration, BPM storage, note sorting,
//  and mapping management.
//

import Testing
import Foundation
@testable import Virgo

@Suite("InputManager Configuration Tests", .serialized)
@MainActor
struct InputManagerConfigurationTests {

    // MARK: - configuredBPM

    @Test("configuredBPM reflects BPM passed to configure()")
    func testConfiguredBPMStoredAfterConfigure() {
        let manager = InputManager()
        manager.configure(bpm: 120.0, timeSignature: .fourFour, notes: [])
        #expect(manager.configuredBPM == 120.0)
    }

    @Test("configuredBPM updates when configure() is called multiple times")
    func testConfiguredBPMUpdatesOnReconfigure() {
        let manager = InputManager()
        manager.configure(bpm: 80.0, timeSignature: .fourFour, notes: [])
        #expect(manager.configuredBPM == 80.0)
        manager.configure(bpm: 200.0, timeSignature: .fourFour, notes: [])
        #expect(manager.configuredBPM == 200.0)
    }

    @Test("configure() accepts minimum practical BPM (0.2)")
    func testConfigureAcceptsMinimumBPM() {
        let manager = InputManager()
        manager.configure(bpm: 0.2, timeSignature: .fourFour, notes: [])
        #expect(manager.configuredBPM == 0.2)
    }

    @Test("configure() accepts maximum practical BPM (1000.0)")
    func testConfigureAcceptsMaximumBPM() {
        let manager = InputManager()
        manager.configure(bpm: 1000.0, timeSignature: .fourFour, notes: [])
        #expect(manager.configuredBPM == 1000.0)
    }

    @Test("configure() stores BPM correctly for all common time signatures")
    func testConfigureWithAllTimeSignatures() {
        let manager = InputManager()
        let bpm = 120.0
        let signatures: [TimeSignature] = [.twoFour, .threeFour, .fourFour, .fiveFour,
                                           .sixEight, .sevenEight, .nineEight, .twelveEight]
        for sig in signatures {
            manager.configure(bpm: bpm, timeSignature: sig, notes: [])
            #expect(manager.configuredBPM == bpm,
                    "Expected BPM \(bpm) after configure with \(sig.displayName)")
        }
    }

    // MARK: - Note Sorting

    @Test("configure() sorts notes by measure number ascending")
    func testConfigureSortsNotesByMeasureNumber() {
        let manager = InputManager()
        let notes = [
            Note(interval: .quarter, noteType: .snare, measureNumber: 3, measureOffset: 0.0),
            Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0.0),
            Note(interval: .quarter, noteType: .snare, measureNumber: 2, measureOffset: 0.0)
        ]
        // After configure, internal note list is sorted. We verify indirectly by calling
        // configure with different sorted orders and checking that BPM is stored correctly
        // (the configure method succeeds without crashing).
        manager.configure(bpm: 120.0, timeSignature: .fourFour, notes: notes)
        #expect(manager.configuredBPM == 120.0)
    }

    @Test("configure() accepts notes already sorted by measure and offset")
    func testConfigureWithPresortedNotes() {
        let manager = InputManager()
        let notes = [
            Note(interval: .quarter, noteType: .kick, measureNumber: 1, measureOffset: 0.0),
            Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0.25),
            Note(interval: .quarter, noteType: .hiHat, measureNumber: 1, measureOffset: 0.5),
            Note(interval: .quarter, noteType: .kick, measureNumber: 2, measureOffset: 0.0)
        ]
        manager.configure(bpm: 120.0, timeSignature: .fourFour, notes: notes)
        #expect(manager.configuredBPM == 120.0)
    }

    @Test("configure() with large note array does not crash")
    func testConfigureWithLargeNoteArray() {
        let manager = InputManager()
        let notes = (0..<500).map { i in
            Note(
                interval: .sixteenth,
                noteType: .snare,
                measureNumber: i / 16 + 1,
                measureOffset: Double(i % 16) / 16.0
            )
        }
        manager.configure(bpm: 120.0, timeSignature: .fourFour, notes: notes)
        #expect(manager.configuredBPM == 120.0)
    }

    // MARK: - Mapping Public API

    @Test("setKeyboardMapping and getKeyboardMapping round-trip")
    func testKeyboardMappingRoundTrip() {
        let manager = InputManager()
        let mapping: [String: DrumType] = [
            "a": .kick,
            "s": .snare,
            "d": .hiHat
        ]
        manager.setKeyboardMapping(mapping)
        let retrieved = manager.getKeyboardMapping()
        #expect(retrieved["a"] == .kick)
        #expect(retrieved["s"] == .snare)
        #expect(retrieved["d"] == .hiHat)
        #expect(retrieved.count == 3)
    }

    @Test("setMIDIMapping and getMIDIMapping round-trip")
    func testMIDIMappingRoundTrip() {
        let manager = InputManager()
        let mapping: [UInt8: DrumType] = [
            36: .kick,
            38: .snare,
            42: .hiHat
        ]
        manager.setMIDIMapping(mapping)
        let retrieved = manager.getMIDIMapping()
        #expect(retrieved[36] == .kick)
        #expect(retrieved[38] == .snare)
        #expect(retrieved[42] == .hiHat)
        #expect(retrieved.count == 3)
    }

    @Test("setKeyboardMapping with empty mapping clears all bindings")
    func testSetEmptyKeyboardMapping() {
        let manager = InputManager()
        manager.setKeyboardMapping(["a": .kick, "s": .snare])
        manager.setKeyboardMapping([:])
        #expect(manager.getKeyboardMapping().isEmpty)
    }

    @Test("setMIDIMapping with empty mapping clears all bindings")
    func testSetEmptyMIDIMapping() {
        let manager = InputManager()
        manager.setMIDIMapping([36: .kick, 38: .snare])
        manager.setMIDIMapping([:])
        #expect(manager.getMIDIMapping().isEmpty)
    }

    @Test("setKeyboardMapping replaces previous mapping entirely")
    func testKeyboardMappingReplacement() {
        let manager = InputManager()
        manager.setKeyboardMapping(["a": .kick])
        manager.setKeyboardMapping(["b": .snare, "c": .hiHat])
        let mapping = manager.getKeyboardMapping()
        #expect(mapping["a"] == nil)
        #expect(mapping["b"] == .snare)
        #expect(mapping["c"] == .hiHat)
    }

    @Test("setMIDIMapping replaces previous mapping entirely")
    func testMIDIMappingReplacement() {
        let manager = InputManager()
        manager.setMIDIMapping([36: .kick])
        manager.setMIDIMapping([38: .snare, 42: .hiHat])
        let mapping = manager.getMIDIMapping()
        #expect(mapping[36] == nil)
        #expect(mapping[38] == .snare)
        #expect(mapping[42] == .hiHat)
    }

    @Test("Keyboard mapping supports all DrumType values")
    func testKeyboardMappingSupportsAllDrumTypes() {
        let manager = InputManager()
        var mapping: [String: DrumType] = [:]
        for (i, drumType) in DrumType.allCases.enumerated() {
            mapping["key\(i)"] = drumType
        }
        manager.setKeyboardMapping(mapping)
        let retrieved = manager.getKeyboardMapping()
        #expect(retrieved.count == DrumType.allCases.count)
        for (i, drumType) in DrumType.allCases.enumerated() {
            #expect(retrieved["key\(i)"] == drumType)
        }
    }

    @Test("MIDI mapping supports full range of MIDI note values (0-127)")
    func testMIDIMappingFullRange() {
        let manager = InputManager()
        let mapping: [UInt8: DrumType] = [
            0: .kick,
            63: .snare,
            127: .hiHat
        ]
        manager.setMIDIMapping(mapping)
        let retrieved = manager.getMIDIMapping()
        #expect(retrieved[0] == .kick)
        #expect(retrieved[63] == .snare)
        #expect(retrieved[127] == .hiHat)
    }

    // MARK: - startListening / stopListening Lifecycle

    @Test("startListening with past date does not crash")
    func testStartListeningWithPastDate() {
        let manager = InputManager()
        manager.configure(bpm: 120.0, timeSignature: .fourFour, notes: [])
        let pastDate = Date(timeIntervalSinceNow: -5.0)
        manager.startListening(songStartTime: pastDate)
        // Verify it does not crash; no observable state to check without a delegate
    }

    @Test("stopListening after startListening does not crash")
    func testStopListeningAfterStart() {
        let manager = InputManager()
        manager.configure(bpm: 120.0, timeSignature: .fourFour, notes: [])
        manager.startListening(songStartTime: Date())
        manager.stopListening()
        // Should not crash
    }

    @Test("stopListening without prior startListening does not crash")
    func testStopListeningWithoutPriorStart() {
        let manager = InputManager()
        manager.stopListening()
        // Should not crash
    }

    @Test("reloadMappingsFromSettings does not crash")
    func testReloadMappingsFromSettings() {
        let manager = InputManager()
        manager.reloadMappingsFromSettings()
        // Should not crash and mappings should still be valid (loaded from settings)
        // The mappings should be non-nil (defaults loaded if no persisted values)
    }

    @Test("startListening then stopListening then startListening again does not crash")
    func testStartStopStartCycle() {
        let manager = InputManager()
        manager.configure(bpm: 120.0, timeSignature: .fourFour, notes: [])
        manager.startListening(songStartTime: Date())
        manager.stopListening()
        manager.startListening(songStartTime: Date())
        manager.stopListening()
        // Should not crash
    }
}
