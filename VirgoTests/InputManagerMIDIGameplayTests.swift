import Testing
import Foundation
@testable import Virgo

@Suite("InputManager MIDI Gameplay Tests", .serialized)
@MainActor
struct InputManagerMIDIGameplayTests {
    final class StubMIDISourceProvider: MIDISourceProviding {
        var sources: [MIDISourceDescriptor]

        init(_ sources: [MIDISourceDescriptor]) {
            self.sources = sources
        }

        func currentSources() -> [MIDISourceDescriptor] {
            sources
        }
    }

    final class StubMIDISourceChangeListener: MIDISourceChangeListening {
        func start(_ onChange: @escaping () -> Void) {}
        func stop() {}
    }

    final class RecordingInputManagerDelegate: InputManagerDelegate {
        var receivedHits: [InputHit] = []
        var receivedResults: [NoteMatchResult] = []
        var didReceiveSelectedSourceDisconnect = false

        func inputManager(_ manager: InputManager, didReceiveHit hit: InputHit) {
            receivedHits.append(hit)
        }

        func inputManager(_ manager: InputManager, didMatchNote result: NoteMatchResult) {
            receivedResults.append(result)
        }

        func inputManagerSelectedMIDISourceDisconnected(_ manager: InputManager) {
            didReceiveSelectedSourceDisconnect = true
        }
    }

    private func makeInputManagerForTest(
        settingsManager: InputSettingsManager,
        selectedSourceID: String,
        midiMapping: [UInt8: DrumType],
        availableSourceIDs: [String]? = nil
    ) -> InputManager {
        settingsManager.setSelectedMIDISource(id: selectedSourceID, displayName: "TD-17")

        for (note, drumType) in midiMapping {
            settingsManager.setMidiMapping(note, for: drumType)
        }

        let sources = (availableSourceIDs ?? [selectedSourceID]).map {
            MIDISourceDescriptor(
                id: $0,
                displayName: $0 == selectedSourceID ? "TD-17" : "Other Device",
                isConnected: true
            )
        }
        let registry = MIDIDeviceRegistry(
            settingsManager: settingsManager,
            sourceProvider: StubMIDISourceProvider(sources),
            sourceChangeListener: StubMIDISourceChangeListener()
        )
        let diagnosticsStore = MIDIDiagnosticsStore()
        let learnSession = MIDILearnSession(settingsManager: settingsManager)
        let manager = InputManager(
            settingsManager: settingsManager,
            deviceRegistry: registry,
            diagnosticsStore: diagnosticsStore,
            learnSession: learnSession
        )

        manager.reloadMappingsFromSettings()
        return manager
    }

    @Test("selected-source MIDI event routes into note matching")
    func selectedSourceMIDIRoutesIntoTimingMatcher() {
        let (settingsManager, userDefaults, suiteName) = TestInputSettingsManager.makeIsolated(
            suiteName: "InputManagerMIDIGameplayTests.selectedSourceMIDIRoutesIntoTimingMatcher"
        )
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let manager = makeInputManagerForTest(
            settingsManager: settingsManager,
            selectedSourceID: "source-2",
            midiMapping: [38: .snare]
        )
        manager.configure(
            bpm: 120,
            timeSignature: .fourFour,
            notes: [
                Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0.0)
            ]
        )
        manager.startListening(songStartTime: Date())

        let result = manager.handleMIDINoteEvent(
            MIDINoteEvent(sourceID: "source-2", channel: 9, note: 38, velocity: 120, hostTime: 10)
        )

        #expect(result?.matchedNote != nil)
        #expect(result?.timingAccuracy == .perfect)
    }

    @Test("disconnecting the selected source notifies the delegate")
    func disconnectingTheSelectedSourceNotifiesTheDelegate() {
        let (settingsManager, userDefaults, suiteName) = TestInputSettingsManager.makeIsolated(
            suiteName: "InputManagerMIDIGameplayTests.disconnectingTheSelectedSourceNotifiesTheDelegate"
        )
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let delegate = RecordingInputManagerDelegate()
        let manager = makeInputManagerForTest(
            settingsManager: settingsManager,
            selectedSourceID: "source-2",
            midiMapping: [38: .snare]
        )
        manager.delegate = delegate

        manager.handleSelectedSourceDisconnect(sourceID: "source-2")

        #expect(delegate.didReceiveSelectedSourceDisconnect == true)
    }

    @Test("MIDI events from non-selected sources are ignored")
    func midiEventsFromNonSelectedSourcesAreIgnored() {
        let (settingsManager, userDefaults, suiteName) = TestInputSettingsManager.makeIsolated(
            suiteName: "InputManagerMIDIGameplayTests.midiEventsFromNonSelectedSourcesAreIgnored"
        )
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let manager = makeInputManagerForTest(
            settingsManager: settingsManager,
            selectedSourceID: "source-2",
            midiMapping: [38: .snare],
            availableSourceIDs: ["source-1", "source-2"]
        )
        manager.configure(
            bpm: 120,
            timeSignature: .fourFour,
            notes: [
                Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0.0)
            ]
        )
        manager.startListening(songStartTime: Date())

        let result = manager.handleMIDINoteEvent(
            MIDINoteEvent(sourceID: "source-1", channel: 9, note: 38, velocity: 120, hostTime: 10)
        )

        #expect(result == nil)
    }
}
