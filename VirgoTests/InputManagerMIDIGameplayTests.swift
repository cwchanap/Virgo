import Testing
import Foundation
import AVFoundation
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

    /// Make an InputManager with NO selected MIDI source (simulates macOS first-run)
    private func makeInputManagerWithoutSelectedSource(
        settingsManager: InputSettingsManager,
        midiMapping: [UInt8: DrumType],
        availableSourceIDs: [String]
    ) -> InputManager {
        for (note, drumType) in midiMapping {
            settingsManager.setMidiMapping(note, for: drumType)
        }

        let sources = availableSourceIDs.map {
            MIDISourceDescriptor(id: $0, displayName: "Device \($0)", isConnected: true)
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
            MIDINoteEvent(sourceID: "source-2", channel: 9, note: 38, velocity: 120, hostTime: mach_absolute_time())
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

    @Test("disconnecting a non-selected source does not notify the delegate")
    func disconnectingANonSelectedSourceDoesNotNotifyTheDelegate() {
        let (settingsManager, userDefaults, suiteName) = TestInputSettingsManager.makeIsolated(
            suiteName: "InputManagerMIDIGameplayTests.disconnectingANonSelectedSourceDoesNotNotifyTheDelegate"
        )
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let delegate = RecordingInputManagerDelegate()
        let manager = makeInputManagerForTest(
            settingsManager: settingsManager,
            selectedSourceID: "source-2",
            midiMapping: [38: .snare],
            availableSourceIDs: ["source-1", "source-2"]
        )
        manager.delegate = delegate

        manager.handleSelectedSourceDisconnect(sourceID: "source-1")

        #expect(delegate.didReceiveSelectedSourceDisconnect == false)
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

    @Test("long-lived InputManager reloads a newly persisted selected source before handling MIDI events")
    func longLivedInputManagerReloadsPersistedSelectedSourceBeforeHandlingEvents() {
        let (staleSettingsManager, userDefaults, suiteName) = TestInputSettingsManager.makeIsolated(
            suiteName: "InputManagerMIDIGameplayTests.longLivedInputManagerReloadsPersistedSelectedSourceBeforeHandlingEvents"
        )
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let registry = MIDIDeviceRegistry(
            settingsManager: staleSettingsManager,
            sourceProvider: StubMIDISourceProvider([
                .init(id: "source-1", displayName: "SPD-SX", isConnected: true),
                .init(id: "source-2", displayName: "TD-17", isConnected: true)
            ]),
            sourceChangeListener: StubMIDISourceChangeListener()
        )
        let manager = InputManager(
            settingsManager: staleSettingsManager,
            deviceRegistry: registry,
            diagnosticsStore: MIDIDiagnosticsStore(),
            learnSession: MIDILearnSession(settingsManager: staleSettingsManager)
        )

        staleSettingsManager.setMidiMapping(38, for: .snare)
        manager.configure(
            bpm: 120,
            timeSignature: .fourFour,
            notes: [
                Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0.0)
            ]
        )

        let settingsViewManager = InputSettingsManager(userDefaults: userDefaults)
        settingsViewManager.setSelectedMIDISource(id: "source-2", displayName: "TD-17")

        manager.startListening(songStartTime: Date())

        let acceptedResult = manager.handleMIDINoteEvent(
            MIDINoteEvent(sourceID: "source-2", channel: 9, note: 38, velocity: 120, hostTime: mach_absolute_time())
        )
        let rejectedResult = manager.handleMIDINoteEvent(
            MIDINoteEvent(sourceID: "source-1", channel: 9, note: 38, velocity: 120, hostTime: mach_absolute_time())
        )

        #expect(manager.hasSelectedMIDISourcePreference == true)
        #expect(manager.isSelectedMIDISourceAvailable == true)
        #expect(acceptedResult?.matchedNote != nil)
        #expect(rejectedResult == nil)
    }

    @Test("startListening refreshes the selected source without clobbering runtime MIDI overrides")
    func startListeningRefreshesSelectedSourceWithoutClobberingRuntimeMIDIMapping() {
        let (staleSettingsManager, userDefaults, suiteName) = TestInputSettingsManager.makeIsolated(
            suiteName: "InputManagerMIDIGameplayTests.startListeningRefreshesSelectedSourceWithoutClobberingRuntimeMIDIMapping"
        )
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let registry = MIDIDeviceRegistry(
            settingsManager: staleSettingsManager,
            sourceProvider: StubMIDISourceProvider([
                .init(id: "source-2", displayName: "TD-17", isConnected: true)
            ]),
            sourceChangeListener: StubMIDISourceChangeListener()
        )
        let manager = InputManager(
            settingsManager: staleSettingsManager,
            deviceRegistry: registry,
            diagnosticsStore: MIDIDiagnosticsStore(),
            learnSession: MIDILearnSession(settingsManager: staleSettingsManager)
        )

        manager.setMIDIMapping([60: .snare])
        manager.configure(
            bpm: 120,
            timeSignature: .fourFour,
            notes: [
                Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0.0)
            ]
        )

        let settingsViewManager = InputSettingsManager(userDefaults: userDefaults)
        settingsViewManager.setSelectedMIDISource(id: "source-2", displayName: "TD-17")
        settingsViewManager.setMidiMapping(38, for: .snare)

        manager.startListening(songStartTime: Date())

        let acceptedResult = manager.handleMIDINoteEvent(
            MIDINoteEvent(sourceID: "source-2", channel: 9, note: 60, velocity: 120, hostTime: mach_absolute_time())
        )
        let persistedMappingResult = manager.handleMIDINoteEvent(
            MIDINoteEvent(sourceID: "source-2", channel: 9, note: 38, velocity: 120, hostTime: mach_absolute_time())
        )
        let rejectedSourceResult = manager.handleMIDINoteEvent(
            MIDINoteEvent(sourceID: "source-1", channel: 9, note: 60, velocity: 120, hostTime: mach_absolute_time())
        )

        #expect(manager.hasSelectedMIDISourcePreference == true)
        #expect(manager.isSelectedMIDISourceAvailable == true)
        #expect(manager.getMIDIMapping().count == 1)
        #expect(manager.getMIDIMapping()[60] == .snare)
        #expect(acceptedResult?.matchedNote != nil)
        #expect(persistedMappingResult == nil)
        #expect(rejectedSourceResult == nil)
    }

    // MARK: - P2: MIDI events accepted when no source is selected

    @Test("MIDI events from any source are accepted when no source is selected")
    func midiEventsAcceptedWithoutSelectedSource() {
        let (settingsManager, userDefaults, suiteName) = TestInputSettingsManager.makeIsolated(
            suiteName: "InputManagerMIDIGameplayTests.midiEventsAcceptedWithoutSelectedSource"
        )
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        // No source selected — simulates macOS first-run before user opens Settings
        let manager = makeInputManagerWithoutSelectedSource(
            settingsManager: settingsManager,
            midiMapping: [38: .snare],
            availableSourceIDs: ["midi-kit-1"]
        )
        manager.configure(
            bpm: 120,
            timeSignature: .fourFour,
            notes: [
                Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0.0)
            ]
        )
        manager.startListening(songStartTime: Date())

        // Event from a connected device that is NOT explicitly selected
        let result = manager.handleMIDINoteEvent(
            MIDINoteEvent(sourceID: "midi-kit-1", channel: 9, note: 38, velocity: 120, hostTime: mach_absolute_time())
        )

        #expect(result?.matchedNote != nil)
        #expect(result?.timingAccuracy == .perfect)
    }

    @Test("MIDI events before startListening are dropped without crashing")
    func midiEventsBeforeStartListeningAreDroppedGracefully() {
        let (settingsManager, userDefaults, suiteName) = TestInputSettingsManager.makeIsolated(
            suiteName: "InputManagerMIDIGameplayTests.midiEventsBeforeStartListeningAreDroppedGracefully"
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

        let result = manager.handleMIDINoteEvent(
            MIDINoteEvent(sourceID: "source-1", channel: 9, note: 38, velocity: 100, hostTime: mach_absolute_time())
        )

        #expect(result == nil)
    }

    @Test("InputManager routes a matching MIDI event into an active learn session")
    func inputManagerRoutesAMatchingMIDIEventIntoAnActiveLearnSession() {
        let (settingsManager, userDefaults, suiteName) = TestInputSettingsManager.makeIsolated(
            suiteName: "InputManagerMIDIGameplayTests.inputManagerRoutesAMatchingMIDIEventIntoAnActiveLearnSession"
        )
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        settingsManager.setSelectedMIDISource(id: "source-2", displayName: "TD-17")

        let registry = MIDIDeviceRegistry(
            settingsManager: settingsManager,
            sourceProvider: StubMIDISourceProvider([
                .init(id: "source-2", displayName: "TD-17", isConnected: true)
            ]),
            sourceChangeListener: StubMIDISourceChangeListener()
        )
        let learnSession = MIDILearnSession(settingsManager: settingsManager)
        let manager = InputManager(
            settingsManager: settingsManager,
            deviceRegistry: registry,
            diagnosticsStore: MIDIDiagnosticsStore(),
            learnSession: learnSession
        )
        manager.reloadMappingsFromSettings()

        learnSession.beginCapture(for: .snare)

        _ = manager.handleMIDINoteEvent(
            MIDINoteEvent(sourceID: "source-2", channel: 9, note: 40, velocity: 110, hostTime: mach_absolute_time())
        )

        #expect(settingsManager.getMidiMapping(for: .snare) == 40)
        #expect(learnSession.isCapturing == false)
    }

    // MARK: - P1: elapsedOffset preserves resume timing for MIDI

    @Test("MIDI elapsed time includes elapsedOffset after resume")
    func midiElapsedTimeIncludesOffsetAfterResume() {
        let (settingsManager, userDefaults, suiteName) = TestInputSettingsManager.makeIsolated(
            suiteName: "InputManagerMIDIGameplayTests.midiElapsedTimeIncludesOffsetAfterResume"
        )
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let manager = makeInputManagerForTest(
            settingsManager: settingsManager,
            selectedSourceID: "source-1",
            midiMapping: [38: .snare]
        )

        // At 120 BPM in 4/4, each measure = 2.0 seconds
        // Note at measure 2, offset 0.0 → expected time = 2.0 seconds
        manager.configure(
            bpm: 120,
            timeSignature: .fourFour,
            notes: [
                Note(interval: .quarter, noteType: .snare, measureNumber: 2, measureOffset: 0.0)
            ]
        )

        // Simulate resume: elapsedOffset = 2.0 seconds (paused at the start of measure 2)
        let elapsedOffset = 2.0
        manager.startListening(
            songStartTime: Date().addingTimeInterval(-elapsedOffset),
            elapsedOffset: elapsedOffset
        )

        // Send a MIDI event right at the resume point.
        // The hostTime is close to now (just captured by startListening), so hostElapsed ≈ 0.
        // With elapsedOffset = 2.0, the effective elapsed time ≈ 2.0 seconds.
        // That should match the note at measure 2 (expectedTime = 2.0s).
        let nowHostTime = mach_absolute_time()
        let result = manager.handleMIDINoteEvent(
            MIDINoteEvent(sourceID: "source-1", channel: 9, note: 38, velocity: 100, hostTime: nowHostTime)
        )

        #expect(result?.matchedNote != nil)
        // With offset=2.0 and hostElapsed≈0, total elapsed ≈ 2.0s
        // Expected note time = 2.0s → timing accuracy should be perfect (within 25ms)
        #expect(result?.timingAccuracy == .perfect)
    }

    @Test("MIDI elapsed time includes elapsedOffset after speed change")
    func midiElapsedTimeIncludesOffsetAfterSpeedChange() {
        let (settingsManager, userDefaults, suiteName) = TestInputSettingsManager.makeIsolated(
            suiteName: "InputManagerMIDIGameplayTests.midiElapsedTimeIncludesOffsetAfterSpeedChange"
        )
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let manager = makeInputManagerForTest(
            settingsManager: settingsManager,
            selectedSourceID: "source-1",
            midiMapping: [38: .snare]
        )

        // After speed change at 120 BPM, effectiveBPM stays 120 for simplicity.
        // Note at measure 3, offset 0.0 → expected time = 4.0 seconds (3 measures × 2.0s/measure, 0-indexed)
        manager.configure(
            bpm: 120,
            timeSignature: .fourFour,
            notes: [
                Note(interval: .quarter, noteType: .snare, measureNumber: 3, measureOffset: 0.0)
            ]
        )

        // Simulate a speed change that recomputed elapsedOffset = 4.0
        let elapsedOffset = 4.0
        manager.startListening(
            songStartTime: Date().addingTimeInterval(-elapsedOffset),
            elapsedOffset: elapsedOffset
        )

        // MIDI event right at the speed-change point
        let nowHostTime = mach_absolute_time()
        let result = manager.handleMIDINoteEvent(
            MIDINoteEvent(sourceID: "source-1", channel: 9, note: 38, velocity: 100, hostTime: nowHostTime)
        )

        #expect(result?.matchedNote != nil)
        #expect(result?.timingAccuracy == .perfect)
    }

    @Test("MIDI elapsed time without offset starts from zero")
    func midiElapsedTimeWithoutOffsetStartsFromZero() {
        let (settingsManager, userDefaults, suiteName) = TestInputSettingsManager.makeIsolated(
            suiteName: "InputManagerMIDIGameplayTests.midiElapsedTimeWithoutOffsetStartsFromZero"
        )
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let manager = makeInputManagerForTest(
            settingsManager: settingsManager,
            selectedSourceID: "source-1",
            midiMapping: [38: .snare]
        )

        // Note at measure 1, offset 0.0 → expected time = 0.0 seconds
        manager.configure(
            bpm: 120,
            timeSignature: .fourFour,
            notes: [
                Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0.0)
            ]
        )

        // Fresh start, no offset
        manager.startListening(songStartTime: Date())

        // MIDI event immediately after start
        let nowHostTime = mach_absolute_time()
        let result = manager.handleMIDINoteEvent(
            MIDINoteEvent(sourceID: "source-1", channel: 9, note: 38, velocity: 100, hostTime: nowHostTime)
        )

        #expect(result?.matchedNote != nil)
        #expect(result?.timingAccuracy == .perfect)
    }

    @Test("restarting without elapsedOffset matches notes from time zero")
    func restartingWithoutOffsetMatchesFromZero() {
        let (settingsManager, userDefaults, suiteName) = TestInputSettingsManager.makeIsolated(
            suiteName: "InputManagerMIDIGameplayTests.restartingWithoutOffsetMatchesFromZero"
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

        // Start with an offset
        manager.startListening(
            songStartTime: Date().addingTimeInterval(-2.0),
            elapsedOffset: 2.0
        )

        // Stop and restart without offset
        manager.stopListening()
        manager.startListening(songStartTime: Date())

        // Event at measure 1 (expectedTime = 0.0s) should match with no offset
        let nowHostTime = mach_absolute_time()
        let result = manager.handleMIDINoteEvent(
            MIDINoteEvent(sourceID: "source-1", channel: 9, note: 38, velocity: 100, hostTime: nowHostTime)
        )

        #expect(result?.matchedNote != nil)
        #expect(result?.timingAccuracy == .perfect)
    }

    // MARK: - Stale source bypass

    @Test("MIDI events from alternate sources are accepted when selected source is unavailable")
    func midiEventsAcceptedFromAlternateSourceWhenSelectedIsUnavailable() {
        let (settingsManager, userDefaults, suiteName) = TestInputSettingsManager.makeIsolated(
            suiteName: "InputManagerMIDIGameplayTests.midiEventsAcceptedFromAlternateSourceWhenSelectedIsUnavailable"
        )
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        // User has previously selected source-2, but only source-1 is currently connected.
        let manager = makeInputManagerForTest(
            settingsManager: settingsManager,
            selectedSourceID: "source-2",
            midiMapping: [38: .snare],
            availableSourceIDs: ["source-1"]
        )
        manager.configure(
            bpm: 120,
            timeSignature: .fourFour,
            notes: [
                Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0.0)
            ]
        )
        manager.startListening(songStartTime: Date())

        // Selected source (source-2) is unavailable, so events from source-1 should be accepted.
        let result = manager.handleMIDINoteEvent(
            MIDINoteEvent(sourceID: "source-1", channel: 9, note: 38, velocity: 120, hostTime: mach_absolute_time())
        )

        #expect(result?.matchedNote != nil)
        #expect(result?.timingAccuracy == .perfect)
    }

    @Test("MIDI events from non-selected sources are still rejected when selected source IS available")
    func midiEventsFromNonSelectedSourcesStillRejectedWhenSelectedIsAvailable() {
        let (settingsManager, userDefaults, suiteName) = TestInputSettingsManager.makeIsolated(
            suiteName: "InputManagerMIDIGameplayTests.midiEventsFromNonSelectedSourcesStillRejectedWhenSelectedIsAvailable"
        )
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        // Both source-1 and source-2 are available; source-2 is selected.
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

        // Selected source IS available, so events from source-1 should still be rejected.
        let result = manager.handleMIDINoteEvent(
            MIDINoteEvent(sourceID: "source-1", channel: 9, note: 38, velocity: 120, hostTime: 10)
        )

        #expect(result == nil)
    }

    // MARK: - Gated mode: selected-source disconnect race

    @Test("Gated mode rejects non-selected MIDI events even when selected source becomes unavailable")
    func gatedModeRejectsNonSelectedEventsWhenSelectedSourceUnavailable() {
        let (settingsManager, userDefaults, suiteName) = TestInputSettingsManager.makeIsolated(
            suiteName: "InputManagerMIDIGameplayTests.gatedModeRejectsNonSelectedEventsWhenSelectedSourceUnavailable"
        )
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        // source-2 is selected and available; source-1 is also connected
        let manager = makeInputManagerForTest(
            settingsManager: settingsManager,
            selectedSourceID: "source-2",
            midiMapping: [38: .snare],
            availableSourceIDs: ["source-1", "source-2"]
        )
        manager.requiresMIDISourceForGameplay = true
        manager.configure(
            bpm: 120,
            timeSignature: .fourFour,
            notes: [
                Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0.0)
            ]
        )
        manager.startListening(songStartTime: Date())

        // Simulate disconnect: selected source becomes unavailable
        manager.handleSelectedSourceDisconnect(sourceID: "source-2")

        // In gated mode, events from the WRONG device must be rejected even though
        // the selected source is now unavailable. The delegate pause hasn't run yet.
        let result = manager.handleMIDINoteEvent(
            MIDINoteEvent(sourceID: "source-1", channel: 9, note: 38, velocity: 120, hostTime: mach_absolute_time())
        )

        #expect(result == nil,
                "Gated mode must reject events from non-selected sources even when selected source is unavailable")
    }

    @Test("Ungated mode accepts alternate-source MIDI events when selected source is unavailable")
    func ungatedModeAcceptsAlternateSourceWhenSelectedSourceUnavailable() {
        let (settingsManager, userDefaults, suiteName) = TestInputSettingsManager.makeIsolated(
            suiteName: "InputManagerMIDIGameplayTests.ungatedModeAcceptsAlternateSourceWhenSelectedSourceUnavailable"
        )
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        // source-2 is selected; only source-1 is available
        let manager = makeInputManagerForTest(
            settingsManager: settingsManager,
            selectedSourceID: "source-2",
            midiMapping: [38: .snare],
            availableSourceIDs: ["source-1"]
        )
        // Ungated (macOS default): requiresMIDISourceForGameplay = false
        manager.configure(
            bpm: 120,
            timeSignature: .fourFour,
            notes: [
                Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0.0)
            ]
        )
        manager.startListening(songStartTime: Date())

        // In ungated mode, events from alternate sources are accepted when
        // the selected source is unavailable (fallback behavior).
        let result = manager.handleMIDINoteEvent(
            MIDINoteEvent(sourceID: "source-1", channel: 9, note: 38, velocity: 120, hostTime: mach_absolute_time())
        )

        #expect(result?.matchedNote != nil,
                "Ungated mode should accept events from alternate source when selected is unavailable")
    }

    // MARK: - Reconnect availability refresh

    @Test("handleSelectedSourceReconnect refreshes availability snapshot back to true")
    func handleSelectedSourceReconnectRefreshesAvailabilitySnapshot() {
        let (settingsManager, userDefaults, suiteName) = TestInputSettingsManager.makeIsolated(
            suiteName: "InputManagerMIDIGameplayTests.handleSelectedSourceReconnectRefreshesAvailabilitySnapshot"
        )
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let manager = makeInputManagerForTest(
            settingsManager: settingsManager,
            selectedSourceID: "source-2",
            midiMapping: [38: .snare],
            availableSourceIDs: ["source-2"]
        )
        manager.configure(
            bpm: 120,
            timeSignature: .fourFour,
            notes: [
                Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0.0)
            ]
        )
        manager.startListening(songStartTime: Date())

        #expect(manager.isSelectedMIDISourceAvailable == true)

        // Simulate disconnect
        manager.handleSelectedSourceDisconnect(sourceID: "source-2")
        #expect(manager.isSelectedMIDISourceAvailable == false)

        // Simulate reconnect
        manager.handleSelectedSourceReconnect(sourceID: "source-2")
        #expect(manager.isSelectedMIDISourceAvailable == true,
                "Availability snapshot must refresh to true on reconnect")
    }

    @Test("handleSelectedSourceReconnect ignores non-selected source")
    func handleSelectedSourceReconnectIgnoresNonSelectedSource() {
        let (settingsManager, userDefaults, suiteName) = TestInputSettingsManager.makeIsolated(
            suiteName: "InputManagerMIDIGameplayTests.handleSelectedSourceReconnectIgnoresNonSelectedSource"
        )
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let manager = makeInputManagerForTest(
            settingsManager: settingsManager,
            selectedSourceID: "source-2",
            midiMapping: [38: .snare],
            availableSourceIDs: ["source-2"]
        )

        manager.handleSelectedSourceDisconnect(sourceID: "source-2")
        #expect(manager.isSelectedMIDISourceAvailable == false)

        // Reconnect of a different source should not change availability
        manager.handleSelectedSourceReconnect(sourceID: "source-1")
        #expect(manager.isSelectedMIDISourceAvailable == false,
                "Reconnect of a non-selected source should not affect availability")
    }
}
