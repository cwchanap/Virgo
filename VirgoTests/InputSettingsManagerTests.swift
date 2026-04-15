import Testing
import Foundation
@testable import Virgo

@Suite("InputSettingsManager Tests", .serialized)
@MainActor
struct InputSettingsManagerTests {
    private func makeUserDefaults(
        _ name: String
    ) -> (UserDefaults, String) {
        TestUserDefaults.makeIsolated(suiteName: "InputSettingsManagerTests.\(name)")
    }

    @Test("Initialization seeds defaults when persisted values are missing")
    func testInitializationSeedsDefaults() {
        let (userDefaults, suiteName) = makeUserDefaults("testInitializationSeedsDefaults")
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let manager = InputSettingsManager(userDefaults: userDefaults)

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

        #expect(userDefaults.data(forKey: "InputSettingsKeyboardMappings") != nil)
        #expect(userDefaults.data(forKey: "InputSettingsMidiMappings") != nil)
    }

    @Test("Initialization loads persisted keyboard and MIDI mappings")
    func testInitializationLoadsPersistedMappings() throws {
        let (userDefaults, suiteName) = makeUserDefaults("testInitializationLoadsPersistedMappings")
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

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

        userDefaults.set(encodedKeyboard, forKey: "InputSettingsKeyboardMappings")
        userDefaults.set(encodedMidi, forKey: "InputSettingsMidiMappings")

        let manager = InputSettingsManager(userDefaults: userDefaults)

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
        let (userDefaults, suiteName) = makeUserDefaults("testInvalidPersistedDataFallsBackToDefaults")
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        userDefaults.set(Data("not-json".utf8), forKey: "InputSettingsKeyboardMappings")
        userDefaults.set(Data("still-not-json".utf8), forKey: "InputSettingsMidiMappings")

        let manager = InputSettingsManager(userDefaults: userDefaults)

        #expect(manager.getKeyboardMappings()["space"] == .kick)
        #expect(manager.getMidiMappings()[36] == .kick)
    }

    @Test("setKeyBinding enforces unique key and unique drum mapping")
    func testSetKeyBindingConflictResolution() {
        let (userDefaults, suiteName) = makeUserDefaults("testSetKeyBindingConflictResolution")
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let manager = InputSettingsManager(userDefaults: userDefaults)

        manager.setKeyBinding("x", for: .kick)
        #expect(manager.getKeyBinding(for: .kick) == "x")
        #expect(manager.getKeyboardMappings()["space"] == nil)

        manager.setKeyBinding("x", for: .snare)
        #expect(manager.getKeyBinding(for: .snare) == "x")
        #expect(manager.getKeyBinding(for: .kick) == nil)
    }

    @Test("removeKeyBinding persists removal across manager instances")
    func testRemoveKeyBindingPersistence() {
        let (userDefaults, suiteName) = makeUserDefaults("testRemoveKeyBindingPersistence")
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let manager = InputSettingsManager(userDefaults: userDefaults)
        manager.setKeyBinding("z", for: .ride)
        #expect(manager.getKeyBinding(for: .ride) == "z")

        manager.removeKeyBinding(for: .ride)
        #expect(manager.getKeyBinding(for: .ride) == nil)

        let reloadedManager = InputSettingsManager(userDefaults: userDefaults)
        #expect(reloadedManager.getKeyBinding(for: .ride) == nil)
    }

    @Test("setMidiMapping and removeMidiMapping enforce uniqueness and persist")
    func testMidiMappingLifecycle() {
        let (userDefaults, suiteName) = makeUserDefaults("testMidiMappingLifecycle")
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let manager = InputSettingsManager(userDefaults: userDefaults)

        manager.setMidiMapping(60, for: .snare)
        #expect(manager.getMidiMapping(for: .snare) == 60)
        #expect(manager.getMidiMappings()[38] == nil)

        manager.setMidiMapping(60, for: .kick)
        #expect(manager.getMidiMapping(for: .kick) == 60)
        #expect(manager.getMidiMapping(for: .snare) == nil)

        manager.removeMidiMapping(for: .kick)
        #expect(manager.getMidiMapping(for: .kick) == nil)

        let reloadedManager = InputSettingsManager(userDefaults: userDefaults)
        #expect(reloadedManager.getMidiMapping(for: .kick) == nil)
    }

    @Test("resetToDefaults restores default keyboard and MIDI values")
    func testResetToDefaults() {
        let (userDefaults, suiteName) = makeUserDefaults("testResetToDefaults")
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let manager = InputSettingsManager(userDefaults: userDefaults)
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
        let (userDefaults, suiteName) = makeUserDefaults("testSaveSettingsWritesPersistedData")
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let manager = InputSettingsManager(userDefaults: userDefaults)
        manager.setKeyBinding("x", for: .kick)
        manager.setMidiMapping(99, for: .ride)
        manager.setSelectedMIDISource(id: "device-123", displayName: "Test Device")
        manager.saveSettings()

        let keyboardData = userDefaults.data(forKey: "InputSettingsKeyboardMappings")
        let midiData = userDefaults.data(forKey: "InputSettingsMidiMappings")
        let sourceData = userDefaults.data(forKey: "InputSettingsSelectedMIDISource")

        #expect(keyboardData != nil)
        #expect(midiData != nil)
        #expect(sourceData != nil)

        guard let keyboardData, let midiData, let sourceData else {
            return
        }

        let keyboardPayload = try JSONDecoder().decode([String: String].self, from: keyboardData)
        let midiPayload = try JSONDecoder().decode([UInt8: String].self, from: midiData)
        let sourcePayload = try JSONDecoder().decode(SelectedMIDISource.self, from: sourceData)

        #expect(keyboardPayload["x"] == "kick")
        #expect(midiPayload[99] == "ride")
        #expect(sourcePayload.id == "device-123")
        #expect(sourcePayload.displayName == "Test Device")
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

    @Test("Selected MIDI source persists across manager instances")
    func testSelectedMIDISourcePersistence() {
        let (userDefaults, suiteName) = makeUserDefaults("testSelectedMIDISourcePersistence")
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let manager = InputSettingsManager(userDefaults: userDefaults)
        manager.setSelectedMIDISource(id: "device-123", displayName: "USB MIDI Device")

        #expect(manager.getSelectedMIDISource()?.id == "device-123")
        #expect(manager.getSelectedMIDISource()?.displayName == "USB MIDI Device")

        let reloadedManager = InputSettingsManager(userDefaults: userDefaults)
        #expect(reloadedManager.getSelectedMIDISource()?.id == "device-123")
        #expect(reloadedManager.getSelectedMIDISource()?.displayName == "USB MIDI Device")
    }

    @Test("resetToDefaults clears selected MIDI source and persists removal")
    func testResetToDefaultsClearsSelectedMIDISource() {
        let (userDefaults, suiteName) = makeUserDefaults("testResetToDefaultsClearsSelectedMIDISource")
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let manager = InputSettingsManager(userDefaults: userDefaults)
        manager.setSelectedMIDISource(id: "device-456", displayName: "Another Device")

        #expect(manager.getSelectedMIDISource() != nil)

        manager.resetToDefaults()

        #expect(manager.getSelectedMIDISource() == nil)

        // Verify that a fresh manager instance loads nil (cross-instance persistence)
        let reloadedManager = InputSettingsManager(userDefaults: userDefaults)
        #expect(reloadedManager.getSelectedMIDISource() == nil)
    }

    @Test("clearSelectedMIDISource persists removal across manager instances")
    func testClearSelectedMIDISourcePersistence() {
        let (userDefaults, suiteName) = makeUserDefaults("testClearSelectedMIDISourcePersistence")
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let manager = InputSettingsManager(userDefaults: userDefaults)
        manager.setSelectedMIDISource(id: "device-789", displayName: "Test Device")
        #expect(manager.getSelectedMIDISource() != nil)

        manager.clearSelectedMIDISource()
        #expect(manager.getSelectedMIDISource() == nil)

        let reloadedManager = InputSettingsManager(userDefaults: userDefaults)
        #expect(reloadedManager.getSelectedMIDISource() == nil)
    }

    @Test("Injected user defaults keep settings isolated between stores")
    func testInjectedUserDefaultsIsolation() {
        let (firstDefaults, firstSuiteName) = makeUserDefaults("testInjectedUserDefaultsIsolation.first")
        defer { firstDefaults.removePersistentDomain(forName: firstSuiteName) }
        let (secondDefaults, secondSuiteName) = makeUserDefaults("testInjectedUserDefaultsIsolation.second")
        defer { secondDefaults.removePersistentDomain(forName: secondSuiteName) }

        let firstManager = InputSettingsManager(userDefaults: firstDefaults)
        let secondManager = InputSettingsManager(userDefaults: secondDefaults)

        firstManager.setMidiMapping(60, for: .snare)
        firstManager.setSelectedMIDISource(id: "device-1", displayName: "First Device")

        #expect(secondManager.getMidiMapping(for: .snare) == 38)
        #expect(secondManager.getSelectedMIDISource() == nil)
    }
}
