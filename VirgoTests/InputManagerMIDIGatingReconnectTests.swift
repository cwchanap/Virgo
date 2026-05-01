//
//  InputManagerMIDIGatingReconnectTests.swift
//  VirgoTests
//

import Testing
import Foundation
import AVFoundation
@testable import Virgo

@Suite("InputManager MIDI Gating & Reconnect Tests", .serialized)
@MainActor
struct InputManagerMIDIGatingReconnectTests {
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

    // MARK: - Stale source bypass

    @Test("MIDI events from alternate sources are accepted when selected source is unavailable")
    func midiEventsAcceptedFromAlternateSourceWhenSelectedIsUnavailable() {
        let (settingsManager, userDefaults, suiteName) = TestInputSettingsManager.makeIsolated(
            suiteName: "InputManagerMIDIGatingReconnectTests.midiEventsAcceptedFromAlternateSourceWhenSelectedIsUnavailable"
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
            suiteName: "InputManagerMIDIGatingReconnectTests.midiEventsFromNonSelectedSourcesStillRejectedWhenSelectedIsAvailable"
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
            suiteName: "InputManagerMIDIGatingReconnectTests.gatedModeRejectsNonSelectedEventsWhenSelectedSourceUnavailable"
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
            suiteName: "InputManagerMIDIGatingReconnectTests.ungatedModeAcceptsAlternateSourceWhenSelectedSourceUnavailable"
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
            suiteName: "InputManagerMIDIGatingReconnectTests.handleSelectedSourceReconnectRefreshesAvailabilitySnapshot"
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
            suiteName: "InputManagerMIDIGatingReconnectTests.handleSelectedSourceReconnectIgnoresNonSelectedSource"
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

    @Test("handleSelectedSourceReconnect does not eagerly set available when connection gate rejects")
    func handleSelectedSourceReconnectDoesNotEagerlySetAvailable() {
        let (settingsManager, userDefaults, suiteName) = TestInputSettingsManager.makeIsolated(
            suiteName: "InputManagerMIDIGatingReconnectTests.handleSelectedSourceReconnectDoesNotEagerlySetAvailable"
        )
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let manager = makeInputManagerForTest(
            settingsManager: settingsManager,
            selectedSourceID: "source-2",
            midiMapping: [38: .snare],
            availableSourceIDs: ["source-2"]
        )

        // Simulate disconnect
        manager.handleSelectedSourceDisconnect(sourceID: "source-2")
        #expect(manager.isSelectedMIDISourceAvailable == false)

        // Simulate MIDI setup failure so the connection gate rejects the source
        // even though the registry reports it as available.
        manager.simulateMIDISetupFailureForTesting()

        // Reconnect should NOT eagerly set available — the connection gate
        // rejects because InputManager has no working MIDI port.
        manager.handleSelectedSourceReconnect(sourceID: "source-2")
        #expect(manager.isSelectedMIDISourceAvailable == false,
                "Availability must stay false when connection gate rejects, even after reconnect signal")
    }
}
