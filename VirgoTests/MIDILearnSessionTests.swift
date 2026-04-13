import Testing
import Foundation
@testable import Virgo

@Suite("MIDILearnSession Tests", .serialized)
@MainActor
struct MIDILearnSessionTests {
    private let keyboardMappingsKey = "InputSettingsKeyboardMappings"
    private let midiMappingsKey = "InputSettingsMidiMappings"
    private let selectedMIDISourceKey = "InputSettingsSelectedMIDISource"

    private func clearPersistedSettings() {
        UserDefaults.standard.removeObject(forKey: keyboardMappingsKey)
        UserDefaults.standard.removeObject(forKey: midiMappingsKey)
        UserDefaults.standard.removeObject(forKey: selectedMIDISourceKey)
    }

    @Test("learn session captures the first valid note from the selected source")
    func learnSessionCapturesTheFirstValidNoteFromTheSelectedSource() {
        clearPersistedSettings()
        defer { clearPersistedSettings() }

        let settings = InputSettingsManager()
        let learnSession = MIDILearnSession(settingsManager: settings)

        learnSession.beginCapture(for: .snare)

        let accepted = learnSession.consume(
            MIDINoteEvent(sourceID: "source-2", channel: 9, note: 40, velocity: 100, hostTime: 10),
            selectedSourceID: "source-2"
        )

        #expect(accepted)
        #expect(settings.getMidiMapping(for: .snare) == 40)
        #expect(learnSession.isCapturing == false)
        #expect(learnSession.targetDrumType == nil)
    }

    @Test("learn session ignores events from the wrong source and zero velocity note-ons")
    func learnSessionRejectsWrongSourceAndZeroVelocityNoteOns() {
        clearPersistedSettings()
        defer { clearPersistedSettings() }

        let settings = InputSettingsManager()
        settings.setMidiMapping(99, for: .kick)
        let learnSession = MIDILearnSession(settingsManager: settings)

        learnSession.beginCapture(for: .kick)

        #expect(
            learnSession.consume(
                MIDINoteEvent(sourceID: "source-1", channel: 9, note: 36, velocity: 100, hostTime: 10),
                selectedSourceID: "source-2"
            ) == false
        )
        #expect(
            learnSession.consume(
                MIDINoteEvent(sourceID: "source-2", channel: 9, note: 37, velocity: 0, hostTime: 20),
                selectedSourceID: "source-2"
            ) == false
        )

        #expect(settings.getMidiMapping(for: .kick) == 99)
        #expect(learnSession.isCapturing == true)
        #expect(learnSession.targetDrumType == .kick)
    }

    @Test("learn session times out and clears capture state")
    func learnSessionTimesOutAndClearsCaptureState() async throws {
        clearPersistedSettings()
        defer { clearPersistedSettings() }

        let settings = InputSettingsManager()
        let learnSession = MIDILearnSession(settingsManager: settings)

        learnSession.beginCapture(for: .kick, timeoutSeconds: 0.01)
        try await Task.sleep(for: .milliseconds(50))

        #expect(learnSession.isCapturing == false)
        #expect(learnSession.targetDrumType == nil)
    }

    @Test("learn session records replacement feedback when an incoming note was already mapped")
    func learnSessionRecordsReplacementFeedback() {
        clearPersistedSettings()
        defer { clearPersistedSettings() }

        let settings = InputSettingsManager()
        settings.setMidiMapping(38, for: .kick)
        let learnSession = MIDILearnSession(settingsManager: settings)

        learnSession.beginCapture(for: .snare)
        let accepted = learnSession.consume(
            MIDINoteEvent(sourceID: "source-2", channel: 9, note: 38, velocity: 100, hostTime: 10),
            selectedSourceID: "source-2"
        )

        #expect(accepted)
        #expect(settings.getMidiMapping(for: .kick) == nil)
        #expect(settings.getMidiMapping(for: .snare) == 38)
        #expect(learnSession.lastConflictMessage == "Replaced Kick with Snare for note 38")
    }
}
