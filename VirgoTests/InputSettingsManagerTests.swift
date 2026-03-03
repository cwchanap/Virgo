import Testing
import Foundation
@testable import Virgo

@Suite("InputSettingsManager Tests", .serialized)
@MainActor
struct InputSettingsManagerTests {
    private let keyboardMappingsKey = "InputSettingsKeyboardMappings"
    private let midiMappingsKey = "InputSettingsMidiMappings"

    private func clearPersistedMappings() {
        UserDefaults.standard.removeObject(forKey: keyboardMappingsKey)
        UserDefaults.standard.removeObject(forKey: midiMappingsKey)
    }

    @Test("Initialization seeds defaults when persisted values are missing")
    func testInitializationSeedsDefaults() {
        clearPersistedMappings()
        defer { clearPersistedMappings() }

        let manager = InputSettingsManager()

        let keyboard = manager.getKeyboardMappings()
        #expect(keyboard.count == 9)
        #expect(keyboard["space"] == .kick)
        #expect(keyboard["f"] == .snare)
        #expect(keyboard["semicolon"] == .ride)

        let midi = manager.getMidiMappings()
        #expect(midi.count == 10)
        #expect(midi[36] == .kick)
        #expect(midi[44] == .hiHatPedal)
        #expect(midi[56] == .cowbell)

        #expect(UserDefaults.standard.data(forKey: keyboardMappingsKey) != nil)
        #expect(UserDefaults.standard.data(forKey: midiMappingsKey) != nil)
    }

    @Test("Initialization loads persisted keyboard and MIDI mappings")
    func testInitializationLoadsPersistedMappings() throws {
        clearPersistedMappings()
        defer { clearPersistedMappings() }

        let encodedKeyboard = try JSONEncoder().encode([
            "q": "snare",
            "w": "kick",
            "e": "invalid-drum"
        ])
        let persistedMidi: [UInt8: String] = [
            UInt8(10): "ride",
            UInt8(11): "tom1",
            UInt8(12): "unknown"
        ]
        let encodedMidi = try JSONEncoder().encode(persistedMidi)

        UserDefaults.standard.set(encodedKeyboard, forKey: keyboardMappingsKey)
        UserDefaults.standard.set(encodedMidi, forKey: midiMappingsKey)

        let manager = InputSettingsManager()

        let keyboard = manager.getKeyboardMappings()
        #expect(keyboard.count == 2)
        #expect(keyboard["q"] == .snare)
        #expect(keyboard["w"] == .kick)
        #expect(keyboard["e"] == nil)

        let midi = manager.getMidiMappings()
        #expect(midi.count == 2)
        #expect(midi[10] == .ride)
        #expect(midi[11] == .tom1)
        #expect(midi[12] == nil)
    }

    @Test("Invalid persisted payload falls back to defaults")
    func testInvalidPersistedDataFallsBackToDefaults() {
        clearPersistedMappings()
        defer { clearPersistedMappings() }

        UserDefaults.standard.set(Data("not-json".utf8), forKey: keyboardMappingsKey)
        UserDefaults.standard.set(Data("still-not-json".utf8), forKey: midiMappingsKey)

        let manager = InputSettingsManager()

        #expect(manager.getKeyboardMappings()["space"] == .kick)
        #expect(manager.getMidiMappings()[36] == .kick)
    }

    @Test("setKeyBinding enforces unique key and unique drum mapping")
    func testSetKeyBindingConflictResolution() {
        clearPersistedMappings()
        defer { clearPersistedMappings() }

        let manager = InputSettingsManager()

        manager.setKeyBinding("x", for: .kick)
        #expect(manager.getKeyBinding(for: .kick) == "x")
        #expect(manager.getKeyboardMappings()["space"] == nil)

        manager.setKeyBinding("x", for: .snare)
        #expect(manager.getKeyBinding(for: .snare) == "x")
        #expect(manager.getKeyBinding(for: .kick) == nil)
    }

    @Test("removeKeyBinding persists removal across manager instances")
    func testRemoveKeyBindingPersistence() {
        clearPersistedMappings()
        defer { clearPersistedMappings() }

        let manager = InputSettingsManager()
        manager.setKeyBinding("z", for: .ride)
        #expect(manager.getKeyBinding(for: .ride) == "z")

        manager.removeKeyBinding(for: .ride)
        #expect(manager.getKeyBinding(for: .ride) == nil)

        let reloadedManager = InputSettingsManager()
        #expect(reloadedManager.getKeyBinding(for: .ride) == nil)
    }

    @Test("setMidiMapping and removeMidiMapping enforce uniqueness and persist")
    func testMidiMappingLifecycle() {
        clearPersistedMappings()
        defer { clearPersistedMappings() }

        let manager = InputSettingsManager()

        manager.setMidiMapping(60, for: .snare)
        #expect(manager.getMidiMapping(for: .snare) == 60)
        #expect(manager.getMidiMappings()[38] == nil)

        manager.setMidiMapping(60, for: .kick)
        #expect(manager.getMidiMapping(for: .kick) == 60)
        #expect(manager.getMidiMapping(for: .snare) == nil)

        manager.removeMidiMapping(for: .kick)
        #expect(manager.getMidiMapping(for: .kick) == nil)

        let reloadedManager = InputSettingsManager()
        #expect(reloadedManager.getMidiMapping(for: .kick) == nil)
    }

    @Test("resetToDefaults restores default keyboard and MIDI values")
    func testResetToDefaults() {
        clearPersistedMappings()
        defer { clearPersistedMappings() }

        let manager = InputSettingsManager()
        manager.setKeyBinding("x", for: .kick)
        manager.setMidiMapping(10, for: .snare)

        manager.resetToDefaults()

        #expect(manager.getKeyBinding(for: .kick) == "space")
        #expect(manager.getKeyBinding(for: .snare) == "f")
        #expect(manager.getMidiMapping(for: .kick) == 36)
        #expect(manager.getMidiMapping(for: .snare) == 38)
    }

    @Test("saveSettings writes current state to UserDefaults")
    func testSaveSettingsWritesPersistedData() throws {
        clearPersistedMappings()
        defer { clearPersistedMappings() }

        let manager = InputSettingsManager()
        manager.setKeyBinding("x", for: .kick)
        manager.setMidiMapping(99, for: .ride)
        manager.saveSettings()

        let keyboardData = UserDefaults.standard.data(forKey: keyboardMappingsKey)
        let midiData = UserDefaults.standard.data(forKey: midiMappingsKey)

        #expect(keyboardData != nil)
        #expect(midiData != nil)

        guard let keyboardData, let midiData else {
            return
        }

        let keyboardPayload = try JSONDecoder().decode([String: String].self, from: keyboardData)
        let midiPayload = try JSONDecoder().decode([UInt8: String].self, from: midiData)

        #expect(keyboardPayload["x"] == "kick")
        #expect(midiPayload[99] == "ride")
    }

    @Test("DrumType.fromString converts known values and rejects unknown values")
    func testDrumTypeFromStringMapping() {
        #expect(DrumType.fromString("kick") == .kick)
        #expect(DrumType.fromString("snare") == .snare)
        #expect(DrumType.fromString("hiHat") == .hiHat)
        #expect(DrumType.fromString("hiHatPedal") == .hiHatPedal)
        #expect(DrumType.fromString("crash") == .crash)
        #expect(DrumType.fromString("ride") == .ride)
        #expect(DrumType.fromString("tom1") == .tom1)
        #expect(DrumType.fromString("tom2") == .tom2)
        #expect(DrumType.fromString("tom3") == .tom3)
        #expect(DrumType.fromString("cowbell") == .cowbell)
        #expect(DrumType.fromString("unknown") == nil)
    }
}
