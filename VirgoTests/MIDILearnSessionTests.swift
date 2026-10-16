import Testing
import Foundation
@testable import Virgo

@Suite("MIDILearnSession Tests", .serialized)
@MainActor
struct MIDILearnSessionTests {
    /// Deterministic timeout scheduler for tests that only need to verify what
    /// happens once the timeout *fires*. It schedules the action on the main queue
    /// (via a `DispatchSourceTimer` at `deadline: .now()`) instead of waiting for a
    /// real wall-clock delay, so the test does not flake under CI load where the
    /// cooperative thread pool can be starved. The returned timer is cancellable,
    /// so `cancelTimeout()` still prevents a superseded capture from firing.
    private static let immediateTimeoutScheduler: MIDILearnTimeoutTimerFactory = { _, action in
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now())
        timer.setEventHandler { MainActor.assumeIsolated { action() } }
        timer.resume()
        return timer
    }

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

        // Inject an immediate-fire timeout scheduler so this test never depends on
        // wall-clock timing. The scheduler fires the timeout on the next main
        // run-loop turn regardless of `timeoutSeconds`, making the assertion
        // deterministic even when the CI runner's cooperative thread pool is loaded.
        let learnSession = MIDILearnSession(
            settingsManager: settings,
            makeTimeoutTimer: Self.immediateTimeoutScheduler
        )
        settings.setSelectedMIDISource(id: "source-2", displayName: "TD-17")

        learnSession.beginCapture(for: .kick, timeoutSeconds: 0.5)

        // The injected scheduler fires on the main queue; yield until capture clears.
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while clock.now < deadline && learnSession.isCapturing {
            try await Task.sleep(for: .milliseconds(5))
        }

        #expect(learnSession.isCapturing == false, "Session should time out and stop capturing")
        #expect(learnSession.targetDrumType == nil)
    }

    @Test("starting a new capture cancels the previous in-flight timeout")
    func startingNewCaptureCancelsPreviousTimeout() async throws {
        let (settings, userDefaults, suiteName) = TestInputSettingsManager.makeIsolated(
            suiteName: "MIDILearnSessionTests.startingNewCaptureCancelsPreviousTimeout"
        )
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let learnSession = MIDILearnSession(settingsManager: settings)
        settings.setSelectedMIDISource(id: "source-2", displayName: "TD-17")

        // Begin a capture with a short timeout, then immediately supersede it.
        learnSession.beginCapture(for: .kick, timeoutSeconds: 0.3)
        let firstCaptureTarget = learnSession.targetDrumType
        learnSession.beginCapture(for: .snare, timeoutSeconds: 3)

        #expect(firstCaptureTarget == .kick)
        #expect(learnSession.targetDrumType == .snare, "New capture should win immediately")
        #expect(learnSession.isCapturing)

        // Wait well past the FIRST capture's 0.3s timeout. The stale timer must not
        // fire — if it did, isCapturing would be false and targetDrumType would be nil.
        try await Task.sleep(for: .milliseconds(600))

        #expect(learnSession.isCapturing, "Superseded timeout must not have fired")
        #expect(learnSession.targetDrumType == .snare)

        // Now the second capture's timeout should fire and clear state.
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(3))
        while clock.now < deadline && learnSession.isCapturing {
            try await Task.sleep(for: .milliseconds(20))
        }
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

    @Test("learn session does not start capture when the selected MIDI source is offline")
    func learnSessionRequiresAvailableSelectedMIDISourceBeforeCaptureBegins() {
        let (settings, userDefaults, suiteName) = TestInputSettingsManager.makeIsolated(
            suiteName: "MIDILearnSessionTests.learnSessionRequiresAvailableSelectedMIDISourceBeforeCaptureBegins"
        )
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        settings.setSelectedMIDISource(id: "source-2", displayName: "TD-17")
        let learnSession = MIDILearnSession(
            settingsManager: settings,
            isSelectedSourceAvailable: { false }
        )

        #expect(learnSession.canBeginCapture == false)

        learnSession.beginCapture(for: .snare)

        #expect(learnSession.isCapturing == false)
        #expect(learnSession.targetDrumType == nil)
    }

    @Test("cancelCapture prevents consume from accepting events, matching source-picker-change behavior")
    func learnSessionCancelCapturePreventsConsume() {
        let (settings, userDefaults, suiteName) = TestInputSettingsManager.makeIsolated(
            suiteName: "MIDILearnSessionTests.learnSessionCancelCapturePreventsConsume"
        )
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        settings.setSelectedMIDISource(id: "source-A", displayName: "Device A")
        let learnSession = MIDILearnSession(settingsManager: settings)

        learnSession.beginCapture(for: .snare)
        #expect(learnSession.isCapturing == true)

        // Simulate source-picker change: caller cancels before the new source sends events
        learnSession.cancelCapture()
        #expect(learnSession.isCapturing == false)

        // Even if an event from the correct (new) source arrives, it should be rejected
        let accepted = learnSession.consume(
            MIDINoteEvent(sourceID: "source-B", channel: 9, note: 40, velocity: 100, hostTime: 10),
            selectedSourceID: "source-B"
        )
        #expect(accepted == false,
                "consume should reject events after cancelCapture")
        #expect(!learnSession.isCapturing,
                "Session should remain non-capturing after rejected event")
    }

    // MARK: - learnDisplayName switch + conflict branches (consolidated from ContentViewMIDILearnCoverageTests)

    /// Expected display names emitted by MIDILearnSession's private
    /// `learnDisplayName` switch. Asserting every case locks the formatting
    /// (hyphens, "Pedal", ordinal tom names) and exercises each switch branch.
    /// The pre-existing conflict test only covered `.kick` / `.snare`.
    private static let expectedLearnNames: [DrumType: String] = [
        .kick: "Kick",
        .snare: "Snare",
        .hiHat: "Hi-Hat",
        .hiHatPedal: "Hi-Hat Pedal",
        .crash: "Crash",
        .ride: "Ride",
        .tom1: "High Tom",
        .tom2: "Mid Tom",
        .tom3: "Low Tom",
        .cowbell: "Cowbell"
    ]

    @Test("learn conflict message uses each drum type display name")
    func learnConflictMessageUsesEachDrumTypeDisplayName() {
        let (settings, userDefaults, suiteName) = TestInputSettingsManager.makeIsolated(
            suiteName: "MIDILearnSessionTests.learnConflictMessageUsesEachDrumTypeDisplayName"
        )
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        settings.setSelectedMIDISource(id: "src", displayName: "Kit")

        let all = DrumType.allCases
        for (index, target) in all.enumerated() {
            // Pair each target with a distinct previous drum so the conflict
            // branch fires and BOTH learnDisplayName lookups run for every case.
            let previous = all[(index + 1) % all.count]
            settings.setMidiMapping(60, for: previous)

            let session = MIDILearnSession(settingsManager: settings)
            session.beginCapture(for: target)
            let accepted = session.consume(
                MIDINoteEvent(sourceID: "src", channel: 9, note: 60, velocity: 100, hostTime: 0),
                selectedSourceID: "src"
            )

            let expected = "Replaced \(Self.expectedLearnNames[previous]!) " +
                "with \(Self.expectedLearnNames[target]!) for note 60"
            #expect(accepted, "Capture for \(target) should accept the mapped note")
            #expect(session.lastConflictMessage == expected)
            #expect(settings.getMidiMapping(for: target) == 60)
        }
    }

    @Test("learn remaps silently when note already mapped to the same drum type")
    func learnRemapsSilentlyWhenNoteAlreadyMappedToSameDrum() {
        let (settings, userDefaults, suiteName) = TestInputSettingsManager.makeIsolated(
            suiteName: "MIDILearnSessionTests.learnRemapsSilentlyWhenNoteAlreadyMappedToSameDrum"
        )
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        settings.setSelectedMIDISource(id: "src", displayName: "Kit")
        settings.setMidiMapping(44, for: .snare)

        let session = MIDILearnSession(settingsManager: settings)
        session.beginCapture(for: .snare)
        let accepted = session.consume(
            MIDINoteEvent(sourceID: "src", channel: 9, note: 44, velocity: 100, hostTime: 0),
            selectedSourceID: "src"
        )

        #expect(accepted)
        // Covers the false branch of `previousDrum != targetDrumType`: no message.
        #expect(session.lastConflictMessage == nil)
        #expect(settings.getMidiMapping(for: .snare) == 44)
    }

    @Test("canBeginCapture is true when a source is selected and available")
    func canBeginCaptureIsTrueWhenSourceSelectedAndAvailable() {
        let (settings, userDefaults, suiteName) = TestInputSettingsManager.makeIsolated(
            suiteName: "MIDILearnSessionTests.canBeginCaptureIsTrueWhenSourceSelectedAndAvailable"
        )
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        settings.setSelectedMIDISource(id: "src", displayName: "Kit")

        let alwaysAvailable = MIDILearnSession(settingsManager: settings)
        #expect(alwaysAvailable.canBeginCapture)

        let offline = MIDILearnSession(settingsManager: settings, isSelectedSourceAvailable: { false })
        #expect(offline.canBeginCapture == false)
    }

    @Test("cancelCapture on a session that never began is a safe no-op")
    func cancelCaptureOnSessionThatNeverBeganIsSafeNoOp() {
        let (settings, userDefaults, suiteName) = TestInputSettingsManager.makeIsolated(
            suiteName: "MIDILearnSessionTests.cancelCaptureOnSessionThatNeverBeganIsSafeNoOp"
        )
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let session = MIDILearnSession(settingsManager: settings)
        // No timeout timer was ever scheduled -> exercises the nil path in
        // cancelTimeout (timeoutTimer?.cancel() on a nil timer).
        session.cancelCapture()

        #expect(session.isCapturing == false)
        #expect(session.targetDrumType == nil)
    }

    @Test("capture transitions idle -> capturing -> idle and clears prior conflict on restart")
    func captureTransitionsIdleToCapturingToIdleAndClearsPriorConflictOnRestart() {
        let (settings, userDefaults, suiteName) = TestInputSettingsManager.makeIsolated(
            suiteName: "MIDILearnSessionTests.captureTransitionsIdleToCapturingToIdleAndClearsPriorConflictOnRestart"
        )
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        settings.setSelectedMIDISource(id: "src", displayName: "Kit")
        settings.setMidiMapping(38, for: .kick)

        let session = MIDILearnSession(settingsManager: settings)
        #expect(session.isCapturing == false && session.targetDrumType == nil)

        session.beginCapture(for: .snare)
        #expect(session.isCapturing && session.targetDrumType == .snare)

        _ = session.consume(
            MIDINoteEvent(sourceID: "src", channel: 9, note: 38, velocity: 100, hostTime: 0),
            selectedSourceID: "src"
        )
        #expect(session.lastConflictMessage != nil)
        #expect(session.isCapturing == false)

        // A fresh capture must clear the previous conflict message.
        session.beginCapture(for: .crash)
        #expect(session.lastConflictMessage == nil)
        #expect(session.isCapturing && session.targetDrumType == .crash)
    }
}
