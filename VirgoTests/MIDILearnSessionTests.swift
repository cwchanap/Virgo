import Testing
import Foundation
@testable import Virgo

@Suite("MIDILearnSession Tests", .serialized)
@MainActor
struct MIDILearnSessionTests {
    @Test("learn session captures the first valid note from the selected source")
    func learnSessionCapturesTheFirstValidNoteFromTheSelectedSource() {
        let (settings, userDefaults, suiteName) = TestInputSettingsManager.makeIsolated(
            suiteName: "MIDILearnSessionTests.learnSessionCapturesTheFirstValidNoteFromTheSelectedSource"
        )
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let learnSession = MIDILearnSession(settingsManager: settings)
        settings.setSelectedMIDISource(id: "source-2", displayName: "TD-17")

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
        let (settings, userDefaults, suiteName) = TestInputSettingsManager.makeIsolated(
            suiteName: "MIDILearnSessionTests.learnSessionRejectsWrongSourceAndZeroVelocityNoteOns"
        )
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        settings.setMidiMapping(99, for: .kick)
        settings.setSelectedMIDISource(id: "source-2", displayName: "TD-17")
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
        let (settings, userDefaults, suiteName) = TestInputSettingsManager.makeIsolated(
            suiteName: "MIDILearnSessionTests.learnSessionTimesOutAndClearsCaptureState"
        )
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let learnSession = MIDILearnSession(settingsManager: settings)
        settings.setSelectedMIDISource(id: "source-2", displayName: "TD-17")

        learnSession.beginCapture(for: .kick, timeoutSeconds: 0.05)
        let didTimeout = try await Task.detached { () throws -> Bool in
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: .seconds(5))

            while clock.now < deadline {
                let isCapturing = await MainActor.run { learnSession.isCapturing }
                if !isCapturing {
                    return true
                }

                try await Task.sleep(for: .milliseconds(20))
            }

            return false
        }.value

        #expect(didTimeout)
        #expect(learnSession.isCapturing == false)
        #expect(learnSession.targetDrumType == nil)
    }

    @Test("learn session records replacement feedback when an incoming note was already mapped")
    func learnSessionRecordsReplacementFeedback() {
        let (settings, userDefaults, suiteName) = TestInputSettingsManager.makeIsolated(
            suiteName: "MIDILearnSessionTests.learnSessionRecordsReplacementFeedback"
        )
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        settings.setMidiMapping(38, for: .kick)
        settings.setSelectedMIDISource(id: "source-2", displayName: "TD-17")
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

    @Test("a stale timeout cannot cancel a newer capture")
    func learnSessionIgnoresStaleTimeoutsAfterStartingANewCapture() async throws {
        let (settings, userDefaults, suiteName) = TestInputSettingsManager.makeIsolated(
            suiteName: "MIDILearnSessionTests.learnSessionIgnoresStaleTimeoutsAfterStartingANewCapture"
        )
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let learnSession = MIDILearnSession(settingsManager: settings)
        settings.setSelectedMIDISource(id: "source-2", displayName: "TD-17")

        learnSession.beginCapture(for: .kick, timeoutSeconds: 0.01)
        learnSession.beginCapture(for: .snare, timeoutSeconds: 1)
        try await Task.sleep(for: .milliseconds(100))

        #expect(learnSession.isCapturing == true)
        #expect(learnSession.targetDrumType == .snare)

        learnSession.cancelCapture()
    }

    @Test("learn session does not start capture without a selected MIDI source")
    func learnSessionRequiresSelectedMIDISourceBeforeCaptureBegins() {
        let (settings, userDefaults, suiteName) = TestInputSettingsManager.makeIsolated(
            suiteName: "MIDILearnSessionTests.learnSessionRequiresSelectedMIDISourceBeforeCaptureBegins"
        )
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let learnSession = MIDILearnSession(settingsManager: settings)

        learnSession.beginCapture(for: .snare)

        #expect(learnSession.isCapturing == false)
        #expect(learnSession.targetDrumType == nil)
    }
}
