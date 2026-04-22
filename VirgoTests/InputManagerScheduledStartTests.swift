import Testing
import Foundation
import AVFoundation
@testable import Virgo

@Suite("InputManager Scheduled Start Tests", .serialized)
@MainActor
struct InputManagerScheduledStartTests {
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
        func start(_ onChange: @escaping () -> Void) -> Bool { true }
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
        let manager = InputManager(
            settingsManager: settingsManager,
            deviceRegistry: registry,
            diagnosticsStore: MIDIDiagnosticsStore(),
            learnSession: MIDILearnSession(settingsManager: settingsManager)
        )
        let delegate = RecordingInputManagerDelegate()
        manager.delegate = delegate
        manager.reloadMappingsFromSettings()

        return manager
    }

    @Test("MIDI event at scheduled playback start scores with zero elapsed offset")
    func midiEventAtScheduledPlaybackStartScoresZero() {
        let (settingsManager, userDefaults, suiteName) = TestInputSettingsManager.makeIsolated(
            suiteName: "InputManagerScheduledStartTests.midiEventAtScheduledPlaybackStartScoresZero"
        )
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let manager = makeInputManagerForTest(
            settingsManager: settingsManager,
            selectedSourceID: "source-1",
            midiMapping: [38: .snare]
        )

        manager.configure(
            bpm: 120,
            timeSignature: .fourFour,
            notes: [
                Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0.0)
            ]
        )

        let setupDelay = 0.05
        let capturedHostTime = mach_absolute_time()
        manager.startListening(
            songStartTime: Date().addingTimeInterval(setupDelay),
            scheduledStartDelay: setupDelay,
            capturedHostTime: capturedHostTime
        )

        let converter = MIDIHostTimeConverter()
        let scheduledHostTime = converter.hostTimeByAdding(seconds: setupDelay, to: capturedHostTime)

        let result = manager.handleMIDINoteEvent(
            MIDINoteEvent(sourceID: "source-1", channel: 9, note: 38, velocity: 100, hostTime: scheduledHostTime)
        )

        #expect(result?.matchedNote != nil, "MIDI event at scheduled start should match a note")
        #expect(result?.timingAccuracy == .perfect)
        if let error = result?.timingError {
            #expect(abs(error) < 5.0)
        }
    }

    @Test("MIDI event before scheduled start is ignored")
    func midiEventBeforeScheduledStartTimeIsIgnored() {
        let (settingsManager, userDefaults, suiteName) = TestInputSettingsManager.makeIsolated(
            suiteName: "InputManagerScheduledStartTests.midiEventBeforeScheduledStartTimeIsIgnored"
        )
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let manager = makeInputManagerForTest(
            settingsManager: settingsManager,
            selectedSourceID: "source-1",
            midiMapping: [38: .snare]
        )

        manager.configure(
            bpm: 120,
            timeSignature: .fourFour,
            notes: [
                Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0.0)
            ]
        )

        let setupDelay = 0.05
        let capturedHostTime = mach_absolute_time()
        manager.startListening(
            songStartTime: Date().addingTimeInterval(setupDelay),
            scheduledStartDelay: setupDelay,
            capturedHostTime: capturedHostTime
        )

        let result = manager.handleMIDINoteEvent(
            MIDINoteEvent(sourceID: "source-1", channel: 9, note: 38, velocity: 100, hostTime: capturedHostTime)
        )

        #expect(result == nil, "MIDI event before scheduled start should be ignored")
    }

    @Test("MIDI event before scheduled start is rejected even when songStartTime is backdated (resume)")
    func preStartMIDIRejectedWithBackdatedStartTime() {
        let (settingsManager, userDefaults, suiteName) = TestInputSettingsManager.makeIsolated(
            suiteName: "InputManagerScheduledStartTests.preStartMIDIRejectedWithBackdatedStartTime"
        )
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let manager = makeInputManagerForTest(
            settingsManager: settingsManager,
            selectedSourceID: "source-1",
            midiMapping: [38: .snare]
        )

        // Note at measure 5 (expectedTime ≈ 8.0s at 120 BPM 4/4) — well past the
        // backdated start time, so a wall-clock fallback would incorrectly match it.
        manager.configure(
            bpm: 120,
            timeSignature: .fourFour,
            notes: [
                Note(interval: .quarter, noteType: .snare, measureNumber: 5, measureOffset: 0.0)
            ]
        )

        // Simulate resume: songStartTime is backdated by 8.0s, with a 50ms scheduled delay.
        // If wall-clock fallback were active, Date() - backdatedStart ≈ 8.0s would match the note.
        let elapsedOffset = 8.0
        let scheduledDelay = 0.05
        let capturedHostTime = mach_absolute_time()
        manager.startListening(
            songStartTime: Date().addingTimeInterval(scheduledDelay - elapsedOffset),
            elapsedOffset: elapsedOffset,
            scheduledStartDelay: scheduledDelay,
            capturedHostTime: capturedHostTime
        )

        // MIDI event arrives NOW (before the 50ms scheduled start).
        // hostElapsed is negative, so the hit must be rejected.
        let result = manager.handleMIDINoteEvent(
            MIDINoteEvent(sourceID: "source-1", channel: 9, note: 38, velocity: 100, hostTime: capturedHostTime)
        )

        #expect(result == nil, "MIDI event before scheduled start must be rejected even with backdated songStartTime")
    }
}
