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

    // MARK: - P2: Keyboard input rejected during scheduled-start window with backdated start time

    @Test("Keyboard hit before scheduled start is rejected when songStartTime is backdated (resume)")
    func preStartKeyboardHitRejectedWithBackdatedStartTime() {
        let (settingsManager, userDefaults, suiteName) = TestInputSettingsManager.makeIsolated(
            suiteName: "InputManagerScheduledStartTests.preStartKeyboardHitRejectedWithBackdatedStartTime"
        )
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let manager = makeInputManagerForTest(
            settingsManager: settingsManager,
            selectedSourceID: "source-1",
            midiMapping: [:]
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
        // The effective audio start time is songStartTime + elapsedOffset (8.0s after songStartTime).
        //
        // Without the fix (using only wall-clock elapsedTime >= 0 check):
        //   elapsedTime = now - backdatedStart = ~8.0s (positive, passes guard, WRONGLY matches note)
        //
        // With the fix (using effectiveAudioStartTime = songStartTime + elapsedOffset):
        //   effectiveAudioStartTime = backdatedStart + 8.0s = ~now + 0.05s
        //   now.timeIntervalSince(effectiveAudioStartTime) = -0.05s (negative, rejected correctly)
        let elapsedOffset = 8.0
        let scheduledDelay = 0.05
        let backdatedStartTime = Date().addingTimeInterval(scheduledDelay - elapsedOffset)
        manager.startListening(
            songStartTime: backdatedStartTime,
            elapsedOffset: elapsedOffset,
            scheduledStartDelay: scheduledDelay
        )

        let delegate = RecordingInputManagerDelegate()
        manager.delegate = delegate
        let hitCountBefore = delegate.receivedHits.count

        // Process a keyboard hit NOW, before the scheduled start time has been reached.
        // With the fix, this should be rejected because effectiveAudioStartTime is in the future.
        manager.processInput(.snare, velocity: 1.0)

        // The hit should be rejected (no delegate callback) because it arrived before audio started.
        // Without the fix, the hit would be incorrectly processed because elapsedTime ≈ 8.0s >= 0.
        #expect(delegate.receivedHits.count == hitCountBefore,
                "Keyboard hit before scheduled start should be rejected when songStartTime is backdated")
    }

    @Test("Keyboard hit at/after scheduled start is accepted (fresh start)")
    func keyboardHitAtScheduledStartAcceptedFreshStart() async throws {
        let (settingsManager, userDefaults, suiteName) = TestInputSettingsManager.makeIsolated(
            suiteName: "InputManagerScheduledStartTests.keyboardHitAtScheduledStartAcceptedFreshStart"
        )
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let manager = makeInputManagerForTest(
            settingsManager: settingsManager,
            selectedSourceID: "source-1",
            midiMapping: [:]
        )

        // Note at measure 1, beat 1 (expectedTime = 0.0s, immediately at start)
        manager.configure(
            bpm: 120,
            timeSignature: .fourFour,
            notes: [
                Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0.0)
            ]
        )

        // Fresh start: songStartTime is 50ms in the future, no elapsedOffset
        let scheduledDelay = 0.05
        let futureStartTime = Date().addingTimeInterval(scheduledDelay)
        manager.startListening(
            songStartTime: futureStartTime,
            elapsedOffset: 0.0,
            scheduledStartDelay: scheduledDelay
        )

        let delegate = RecordingInputManagerDelegate()
        manager.delegate = delegate

        // Wait for the scheduled start time to pass
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms

        // Process a keyboard hit AFTER the scheduled start time.
        // This should be accepted because effectiveAudioStartTime has been reached.
        manager.processInput(.snare, velocity: 1.0)

        // processInput dispatches delegate callbacks asynchronously on the main queue.
        // Yield to allow the async blocks to fire before checking delegate state.
        try await Task.sleep(nanoseconds: 50_000_000)

        // The hit should be processed and delegate callback should fire
        #expect(delegate.receivedHits.count == 1,
                "Keyboard hit after scheduled start should be accepted")
        #expect(delegate.receivedResults.count == 1,
                "Keyboard hit should produce a match result")
    }

    // MARK: - Zero-timestamp MIDI packets

    @Test("MIDI event with hostTime == 0 is accepted during active playback")
    func zeroHostTimeAcceptedAfterStart() {
        let (settingsManager, userDefaults, suiteName) = TestInputSettingsManager.makeIsolated(
            suiteName: "InputManagerScheduledStartTests.zeroHostTimeAcceptedAfterStart"
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

        // Start listening NOW — no scheduled delay, no offset.
        // Audio has already begun, so a zero-timestamp packet should be accepted.
        manager.startListening(songStartTime: Date())

        // Simulate a MIDI device that emits packets with timeStamp == 0
        let result = manager.handleMIDINoteEvent(
            MIDINoteEvent(sourceID: "source-1", channel: 9, note: 38, velocity: 100, hostTime: 0)
        )

        #expect(result?.matchedNote != nil,
                "MIDI event with hostTime == 0 should match a note during active playback")
        #expect(result?.timingAccuracy == .perfect)
    }

    @Test("MIDI event with hostTime == 0 is rejected before effective audio start (resume)")
    func zeroHostTimeRejectedBeforeEffectiveStart() {
        let (settingsManager, userDefaults, suiteName) = TestInputSettingsManager.makeIsolated(
            suiteName: "InputManagerScheduledStartTests.zeroHostTimeRejectedBeforeEffectiveStart"
        )
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let manager = makeInputManagerForTest(
            settingsManager: settingsManager,
            selectedSourceID: "source-1",
            midiMapping: [38: .snare]
        )

        // Note at measure 5 (expectedTime ≈ 8.0s at 120 BPM 4/4) — well past the
        // backdated start time, so a wall-clock fallback without the guard would
        // incorrectly match it.
        manager.configure(
            bpm: 120,
            timeSignature: .fourFour,
            notes: [
                Note(interval: .quarter, noteType: .snare, measureNumber: 5, measureOffset: 0.0)
            ]
        )

        // Simulate resume: songStartTime is backdated by 8.0s, with a 50ms scheduled delay.
        // The effective audio start time is songStartTime + elapsedOffset, which is ~50ms in the future.
        // A zero-host-time event that falls back to wall-clock should still be rejected
        // because the effective audio start has not been reached yet.
        let elapsedOffset = 8.0
        let scheduledDelay = 0.05
        manager.startListening(
            songStartTime: Date().addingTimeInterval(scheduledDelay - elapsedOffset),
            elapsedOffset: elapsedOffset,
            scheduledStartDelay: scheduledDelay
        )

        let result = manager.handleMIDINoteEvent(
            MIDINoteEvent(sourceID: "source-1", channel: 9, note: 38, velocity: 100, hostTime: 0)
        )

        #expect(result == nil,
                "MIDI event with hostTime == 0 must be rejected before effective audio start")
    }

    @Test("MIDI event with hostTime == 0 is accepted after effective audio start (resume)")
    func zeroHostTimeAcceptedAfterEffectiveStart() async throws {
        let (settingsManager, userDefaults, suiteName) = TestInputSettingsManager.makeIsolated(
            suiteName: "InputManagerScheduledStartTests.zeroHostTimeAcceptedAfterEffectiveStart"
        )
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let manager = makeInputManagerForTest(
            settingsManager: settingsManager,
            selectedSourceID: "source-1",
            midiMapping: [38: .snare]
        )

        // Note at measure 2 (expectedTime = 2.0s at 120 BPM 4/4)
        manager.configure(
            bpm: 120,
            timeSignature: .fourFour,
            notes: [
                Note(interval: .quarter, noteType: .snare, measureNumber: 2, measureOffset: 0.0)
            ]
        )

        // Simulate resume at measure 2 (elapsedOffset = 2.0s), no scheduled delay.
        // effectiveAudioStartTime = songStartTime + elapsedOffset ≈ now (already past).
        let elapsedOffset = 2.0
        manager.startListening(
            songStartTime: Date().addingTimeInterval(-elapsedOffset),
            elapsedOffset: elapsedOffset
        )

        // Wait a small moment to ensure effective audio start has passed
        try await Task.sleep(nanoseconds: 10_000_000) // 10ms

        let result = manager.handleMIDINoteEvent(
            MIDINoteEvent(sourceID: "source-1", channel: 9, note: 38, velocity: 100, hostTime: 0)
        )

        #expect(result?.matchedNote != nil,
                "MIDI event with hostTime == 0 should be accepted after effective audio start")
    }
}
