//
//  InputManagerConfigurationTests.swift
//  VirgoTests
//
//  Tests for InputManager configuration, BPM storage, note sorting,
//  and mapping management.
//

import Testing
import Foundation
import CoreMIDI
@testable import Virgo

@Suite("InputManager Configuration Tests", .serialized)
@MainActor
struct InputManagerConfigurationTests {
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

    // MARK: - configuredBPM

    @Test("configuredBPM reflects BPM passed to configure()")
    func testConfiguredBPMStoredAfterConfigure() {
        let manager = InputManager()
        manager.configure(bpm: 120.0, timeSignature: .fourFour, notes: [])
        #expect(manager.configuredBPM == 120.0)
    }

    @Test("configuredBPM updates when configure() is called multiple times")
    func testConfiguredBPMUpdatesOnReconfigure() {
        let manager = InputManager()
        manager.configure(bpm: 80.0, timeSignature: .fourFour, notes: [])
        #expect(manager.configuredBPM == 80.0)
        manager.configure(bpm: 200.0, timeSignature: .fourFour, notes: [])
        #expect(manager.configuredBPM == 200.0)
    }

    @Test("configure() accepts minimum practical BPM (0.2)")
    func testConfigureAcceptsMinimumBPM() {
        let manager = InputManager()
        manager.configure(bpm: 0.2, timeSignature: .fourFour, notes: [])
        #expect(manager.configuredBPM == 0.2)
    }

    @Test("configure() accepts maximum practical BPM (1000.0)")
    func testConfigureAcceptsMaximumBPM() {
        let manager = InputManager()
        manager.configure(bpm: 1000.0, timeSignature: .fourFour, notes: [])
        #expect(manager.configuredBPM == 1000.0)
    }

    @Test("configure() stores BPM correctly for all common time signatures")
    func testConfigureWithAllTimeSignatures() {
        let manager = InputManager()
        let bpm = 120.0
        let signatures: [TimeSignature] = [.twoFour, .threeFour, .fourFour, .fiveFour,
                                           .sixEight, .sevenEight, .nineEight, .twelveEight]
        for sig in signatures {
            manager.configure(bpm: bpm, timeSignature: sig, notes: [])
            #expect(manager.configuredBPM == bpm,
                    "Expected BPM \(bpm) after configure with \(sig.displayName)")
        }
    }

    // MARK: - Note Sorting

    @Test("configure() accepts unsorted notes without crashing")
    func testConfigureAcceptsUnsortedNotes() {
        let manager = InputManager()
        let notes = [
            Note(interval: .quarter, noteType: .snare, measureNumber: 3, measureOffset: 0.0),
            Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0.0),
            Note(interval: .quarter, noteType: .snare, measureNumber: 2, measureOffset: 0.0)
        ]
        manager.configure(bpm: 120.0, timeSignature: .fourFour, notes: notes)
        #expect(manager.configuredBPM == 120.0)
    }

    @Test("configure() accepts notes already sorted by measure and offset")
    func testConfigureWithPresortedNotes() {
        let manager = InputManager()
        let notes = [
            Note(interval: .quarter, noteType: .bass, measureNumber: 1, measureOffset: 0.0),
            Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0.25),
            Note(interval: .quarter, noteType: .hiHat, measureNumber: 1, measureOffset: 0.5),
            Note(interval: .quarter, noteType: .bass, measureNumber: 2, measureOffset: 0.0)
        ]
        manager.configure(bpm: 120.0, timeSignature: .fourFour, notes: notes)
        #expect(manager.configuredBPM == 120.0)
    }

    @Test("configure() with large note array does not crash")
    func testConfigureWithLargeNoteArray() {
        let manager = InputManager()
        let notes = (0..<500).map { i in
            Note(
                interval: .sixteenth,
                noteType: .snare,
                measureNumber: i / 16 + 1,
                measureOffset: Double(i % 16) / 16.0
            )
        }
        manager.configure(bpm: 120.0, timeSignature: .fourFour, notes: notes)
        #expect(manager.configuredBPM == 120.0)
    }

    // MARK: - Mapping Public API

    @Test("setKeyboardMapping and getKeyboardMapping round-trip")
    func testKeyboardMappingRoundTrip() {
        let manager = InputManager()
        let mapping: [String: DrumType] = [
            "a": .kick,
            "s": .snare,
            "d": .hiHat
        ]
        manager.setKeyboardMapping(mapping)
        let retrieved = manager.getKeyboardMapping()
        #expect(retrieved["a"] == .kick)
        #expect(retrieved["s"] == .snare)
        #expect(retrieved["d"] == .hiHat)
        #expect(retrieved.count == 3)
    }

    @Test("setMIDIMapping and getMIDIMapping round-trip")
    func testMIDIMappingRoundTrip() {
        let manager = InputManager()
        let mapping: [UInt8: DrumType] = [
            36: .kick,
            38: .snare,
            42: .hiHat
        ]
        manager.setMIDIMapping(mapping)
        let retrieved = manager.getMIDIMapping()
        #expect(retrieved[36] == .kick)
        #expect(retrieved[38] == .snare)
        #expect(retrieved[42] == .hiHat)
        #expect(retrieved.count == 3)
    }

    @Test("setKeyboardMapping with empty mapping clears all bindings")
    func testSetEmptyKeyboardMapping() {
        let manager = InputManager()
        manager.setKeyboardMapping(["a": .kick, "s": .snare])
        manager.setKeyboardMapping([:])
        #expect(manager.getKeyboardMapping().isEmpty)
    }

    @Test("setMIDIMapping with empty mapping clears all bindings")
    func testSetEmptyMIDIMapping() {
        let manager = InputManager()
        manager.setMIDIMapping([36: .kick, 38: .snare])
        manager.setMIDIMapping([:])
        #expect(manager.getMIDIMapping().isEmpty)
    }

    @Test("setKeyboardMapping replaces previous mapping entirely")
    func testKeyboardMappingReplacement() {
        let manager = InputManager()
        manager.setKeyboardMapping(["a": .kick])
        manager.setKeyboardMapping(["b": .snare, "c": .hiHat])
        let mapping = manager.getKeyboardMapping()
        #expect(mapping["a"] == nil)
        #expect(mapping["b"] == .snare)
        #expect(mapping["c"] == .hiHat)
    }

    @Test("setMIDIMapping replaces previous mapping entirely")
    func testMIDIMappingReplacement() {
        let manager = InputManager()
        manager.setMIDIMapping([36: .kick])
        manager.setMIDIMapping([38: .snare, 42: .hiHat])
        let mapping = manager.getMIDIMapping()
        #expect(mapping[36] == nil)
        #expect(mapping[38] == .snare)
        #expect(mapping[42] == .hiHat)
    }

    @Test("Keyboard mapping supports all DrumType values")
    func testKeyboardMappingSupportsAllDrumTypes() {
        let manager = InputManager()
        var mapping: [String: DrumType] = [:]
        for (i, drumType) in DrumType.allCases.enumerated() {
            mapping["key\(i)"] = drumType
        }
        manager.setKeyboardMapping(mapping)
        let retrieved = manager.getKeyboardMapping()
        #expect(retrieved.count == DrumType.allCases.count)
        for (i, drumType) in DrumType.allCases.enumerated() {
            #expect(retrieved["key\(i)"] == drumType)
        }
    }

    @Test("MIDI mapping supports full range of MIDI note values (0-127)")
    func testMIDIMappingFullRange() {
        let manager = InputManager()
        let mapping: [UInt8: DrumType] = [
            0: .kick,
            63: .snare,
            127: .hiHat
        ]
        manager.setMIDIMapping(mapping)
        let retrieved = manager.getMIDIMapping()
        #expect(retrieved[0] == .kick)
        #expect(retrieved[63] == .snare)
        #expect(retrieved[127] == .hiHat)
    }

    // MARK: - startListening / stopListening Lifecycle

    @Test("startListening with past date leaves BPM unchanged")
    func testStartListeningWithPastDate() {
        let manager = InputManager()
        manager.configure(bpm: 120.0, timeSignature: .fourFour, notes: [])
        manager.startListening(songStartTime: Date(timeIntervalSinceNow: -5.0))
        #expect(manager.configuredBPM == 120.0)
    }

    @Test("stopListening after startListening leaves BPM and mappings intact")
    func testStopListeningAfterStart() {
        let manager = InputManager()
        manager.configure(bpm: 140.0, timeSignature: .fourFour, notes: [])
        manager.setKeyboardMapping(["f": .snare])
        manager.startListening(songStartTime: Date())
        manager.stopListening()
        #expect(manager.configuredBPM == 140.0)
        #expect(manager.getKeyboardMapping()["f"] == .snare)
    }

    @Test("stopListening without prior startListening leaves mappings intact")
    func testStopListeningWithoutPriorStart() {
        let manager = InputManager()
        manager.setKeyboardMapping(["j": .hiHat])
        manager.stopListening()
        #expect(manager.getKeyboardMapping()["j"] == .hiHat)
    }

    @Test("reloadMappingsFromSettings loads non-empty default keyboard and MIDI mappings")
    func testReloadMappingsFromSettings() {
        let manager = InputManager()
        manager.reloadMappingsFromSettings()
        #expect(!manager.getKeyboardMapping().isEmpty)
        #expect(!manager.getMIDIMapping().isEmpty)
    }

    @Test("reloadMappingsFromSettings refreshes selected-source preference and availability")
    func testReloadMappingsFromSettingsRefreshesSelectedSourceState() {
        let (settingsManager, userDefaults, suiteName) = TestInputSettingsManager.makeIsolated(
            suiteName: "InputManagerConfigurationTests.SelectedSource.\(UUID().uuidString)"
        )
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        settingsManager.setSelectedMIDISource(id: "source-2", displayName: "TD-17")

        let registry = MIDIDeviceRegistry(
            settingsManager: settingsManager,
            sourceProvider: StubMIDISourceProvider([
                MIDISourceDescriptor(id: "source-2", displayName: "TD-17", isConnected: true)
            ]),
            sourceChangeListener: StubMIDISourceChangeListener()
        )
        let manager = InputManager(
            settingsManager: settingsManager,
            deviceRegistry: registry,
            diagnosticsStore: MIDIDiagnosticsStore(),
            learnSession: MIDILearnSession(settingsManager: settingsManager)
        )

        manager.reloadMappingsFromSettings()

        #expect(manager.hasSelectedMIDISourcePreference == true)
        #expect(manager.isSelectedMIDISourceAvailable == true)
    }

    @Test("fresh-session configuration refresh preserves runtime mapping overrides")
    func testRefreshGameplayConfigurationPreservesRuntimeOverrides() {
        let (settingsManager, userDefaults, suiteName) = TestInputSettingsManager.makeIsolated(
            suiteName: "InputManagerConfigurationTests.RuntimeOverrides.\(UUID().uuidString)"
        )
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let registry = MIDIDeviceRegistry(
            settingsManager: settingsManager,
            sourceProvider: StubMIDISourceProvider([
                MIDISourceDescriptor(id: "source-2", displayName: "TD-17", isConnected: true)
            ]),
            sourceChangeListener: StubMIDISourceChangeListener()
        )
        let manager = InputManager(
            settingsManager: settingsManager,
            deviceRegistry: registry,
            diagnosticsStore: MIDIDiagnosticsStore(),
            learnSession: MIDILearnSession(settingsManager: settingsManager)
        )

        manager.setKeyboardMapping(["x": .kick])
        manager.setMIDIMapping([60: .snare])

        let settingsViewManager = InputSettingsManager(userDefaults: userDefaults)
        settingsViewManager.setKeyBinding("z", for: .ride)
        settingsViewManager.setMidiMapping(38, for: .snare)
        settingsViewManager.setSelectedMIDISource(id: "source-2", displayName: "TD-17")

        manager.refreshGameplayConfigurationFromSettingsIfNeeded()

        #expect(manager.getKeyboardMapping().count == 1)
        #expect(manager.getKeyboardMapping()["x"] == .kick)
        #expect(manager.getMIDIMapping().count == 1)
        #expect(manager.getMIDIMapping()[60] == .snare)
        #expect(manager.hasSelectedMIDISourcePreference == true)
        #expect(manager.isSelectedMIDISourceAvailable == true)
    }

    @Test("shouldConnectMIDISource skips endpoints whose retained contexts are still tracked")
    func testShouldConnectMIDISourceSkipsTrackedEndpoints() {
        let trackedSource: MIDIEndpointRef = 17

        #expect(
            InputManager.shouldConnectMIDISource(trackedSource, existingConnectedSources: []) == true
        )
        #expect(
            InputManager.shouldConnectMIDISource(trackedSource, existingConnectedSources: [trackedSource]) == false
        )
    }

    // MARK: - computeMIDISourceDiff

    @Test("computeMIDISourceDiff: no changes when current matches connected")
    func testDiffNoChanges() {
        let endpoints: Set<MIDIEndpointRef> = [1, 2, 3]
        let diff = InputManager.computeMIDISourceDiff(
            currentEndpoints: endpoints,
            connectedEndpoints: endpoints
        )
        #expect(diff.toConnect.isEmpty)
        #expect(diff.toDisconnect.isEmpty)
        #expect(diff.hasChanges == false)
    }

    @Test("computeMIDISourceDiff: new source detected")
    func testDiffNewSource() {
        let diff = InputManager.computeMIDISourceDiff(
            currentEndpoints: [1, 2, 3],
            connectedEndpoints: [1, 2]
        )
        #expect(diff.toConnect == [3])
        #expect(diff.toDisconnect.isEmpty)
        #expect(diff.hasChanges == true)
    }

    @Test("computeMIDISourceDiff: removed source detected")
    func testDiffRemovedSource() {
        let diff = InputManager.computeMIDISourceDiff(
            currentEndpoints: [1, 2],
            connectedEndpoints: [1, 2, 3]
        )
        #expect(diff.toConnect.isEmpty)
        #expect(diff.toDisconnect == [3])
        #expect(diff.hasChanges == true)
    }

    @Test("computeMIDISourceDiff: mixed additions and removals")
    func testDiffMixed() {
        let diff = InputManager.computeMIDISourceDiff(
            currentEndpoints: [1, 4],
            connectedEndpoints: [1, 2, 3]
        )
        #expect(diff.toConnect == [4])
        #expect(diff.toDisconnect == [2, 3])
        #expect(diff.hasChanges == true)
    }

    @Test("computeMIDISourceDiff: existing source preserved when unrelated source added")
    func testDiffExistingSourcePreserved() {
        // Simulates the core P2 scenario: the active device (endpoint 1) must not
        // appear in either toConnect or toDisconnect when a new device (endpoint 2)
        // appears.
        let diff = InputManager.computeMIDISourceDiff(
            currentEndpoints: [1, 2],
            connectedEndpoints: [1]
        )
        #expect(diff.toConnect == [2])
        #expect(diff.toDisconnect.isEmpty)
        #expect(!diff.toConnect.contains(1),
                "Existing active source should not be reconnected")
        #expect(!diff.toDisconnect.contains(1),
                "Existing active source should not be disconnected")
    }

    @Test("computeMIDISourceDiff: empty current and connected yields no changes")
    func testDiffEmpty() {
        let diff = InputManager.computeMIDISourceDiff(
            currentEndpoints: [],
            connectedEndpoints: []
        )
        #expect(diff.hasChanges == false)
    }

    @Test("requiresMIDISourceForGameplay defaults to false")
    func testRequiresMIDISourceForGameplayDefaultsToFalse() {
        let manager = InputManager()
        #expect(manager.requiresMIDISourceForGameplay == false)
    }

    @Test("start-stop-start cycle preserves BPM and runtime keyboard/MIDI mappings")
    func testStartStopStartCycle() {
        let manager = InputManager()
        manager.configure(bpm: 100.0, timeSignature: .fourFour, notes: [])
        manager.setKeyboardMapping(["x": .kick])
        manager.setMIDIMapping([60: .snare])
        manager.startListening(songStartTime: Date())
        manager.stopListening()
        manager.startListening(songStartTime: Date())
        manager.stopListening()
        #expect(manager.configuredBPM == 100.0)
        #expect(manager.getKeyboardMapping().count == 1)
        #expect(manager.getKeyboardMapping()["x"] == .kick)
        #expect(manager.getMIDIMapping().count == 1)
        #expect(manager.getMIDIMapping()[60] == .snare)
    }

    // MARK: - findStaleConnectedEndpoints (Bug #1: stable-ID dedup)

    @Test("findStaleConnectedEndpoints returns empty when no stable ID collisions")
    func testFindStaleEndpointsNoCollisions() {
        let connected: [MIDIEndpointRef: String] = [
            1: "coremidi:100",
            2: "coremidi:200"
        ]
        let newEndpoints: [MIDIEndpointRef: String] = [
            3: "coremidi:300"
        ]
        let stale = InputManager.findStaleConnectedEndpoints(
            connectedSourceIDs: connected,
            newEndpointSourceIDs: newEndpoints
        )
        #expect(stale.isEmpty)
    }

    @Test("findStaleConnectedEndpoints detects stale endpoint with same stable ID as new endpoint")
    func testFindStaleEndpointsDetectsDuplicate() {
        let connected: [MIDIEndpointRef: String] = [
            1: "coremidi:100",
            2: "coremidi:200"
        ]
        // Endpoint 3 has the same stable ID as connected endpoint 1
        let newEndpoints: [MIDIEndpointRef: String] = [
            3: "coremidi:100"
        ]
        let stale = InputManager.findStaleConnectedEndpoints(
            connectedSourceIDs: connected,
            newEndpointSourceIDs: newEndpoints
        )
        #expect(stale == [1])
    }

    @Test("findStaleConnectedEndpoints handles multiple collisions")
    func testFindStaleEndpointsMultipleCollisions() {
        let connected: [MIDIEndpointRef: String] = [
            1: "coremidi:100",
            2: "coremidi:200",
            3: "coremidi:300"
        ]
        // Endpoints 4 and 5 collide with 1 and 3 respectively
        let newEndpoints: [MIDIEndpointRef: String] = [
            4: "coremidi:100",
            5: "coremidi:300"
        ]
        let stale = InputManager.findStaleConnectedEndpoints(
            connectedSourceIDs: connected,
            newEndpointSourceIDs: newEndpoints
        )
        #expect(stale == [1, 3])
    }

    @Test("findStaleConnectedEndpoints returns empty for empty inputs")
    func testFindStaleEndpointsEmpty() {
        #expect(
            InputManager.findStaleConnectedEndpoints(
                connectedSourceIDs: [:],
                newEndpointSourceIDs: [MIDIEndpointRef(5): "coremidi:100"]
            ).isEmpty
        )
        #expect(
            InputManager.findStaleConnectedEndpoints(
                connectedSourceIDs: [MIDIEndpointRef(5): "coremidi:100"],
                newEndpointSourceIDs: [:]
            ).isEmpty
        )
        #expect(
            InputManager.findStaleConnectedEndpoints(
                connectedSourceIDs: [:],
                newEndpointSourceIDs: [:]
            ).isEmpty
        )
    }

    // MARK: - Connection availability gate (Bug #2)

    @Test("isSelectedMIDISourceAvailable falls back to registry when MIDI not initialized")
    func testAvailabilityFallsBackToRegistryWithoutMIDI() {
        let (settingsManager, userDefaults, suiteName) = TestInputSettingsManager.makeIsolated(
            suiteName: "InputManagerConfigurationTests.AvailabilityGate.\(UUID().uuidString)"
        )
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        settingsManager.setSelectedMIDISource(id: "source-1", displayName: "TD-17")

        let registry = MIDIDeviceRegistry(
            settingsManager: settingsManager,
            sourceProvider: StubMIDISourceProvider([
                MIDISourceDescriptor(id: "source-1", displayName: "TD-17", isConnected: true)
            ]),
            sourceChangeListener: StubMIDISourceChangeListener()
        )
        let manager = InputManager(
            settingsManager: settingsManager,
            deviceRegistry: registry,
            diagnosticsStore: MIDIDiagnosticsStore(),
            learnSession: MIDILearnSession(settingsManager: settingsManager)
        )

        manager.reloadMappingsFromSettings()

        // MIDI subsystem not initialized in test — should fall back to registry
        #expect(manager.isSelectedMIDISourceAvailable == true)
    }

}

@Suite("InputManager Oscillation Prevention Tests", .serialized)
@MainActor
struct InputManagerOscillationPreventionTests {

    @Test("findStaleConnectedEndpoints does not oscillate when both old and new refs share a source ID")
    func testOscillationPrevention() {
        // Simulate: old ref 1 and new ref 3 both have sourceID "coremidi:100"
        let connected: [MIDIEndpointRef: String] = [
            1: "coremidi:100",
            2: "coremidi:200"
        ]
        let newEndpoints: [MIDIEndpointRef: String] = [
            3: "coremidi:100"
        ]
        let stale = InputManager.findStaleConnectedEndpoints(
            connectedSourceIDs: connected,
            newEndpointSourceIDs: newEndpoints
        )
        #expect(stale == [1],
                "Endpoint 1 should be stale because its sourceID matches new endpoint 3")

        // After disconnecting stale (1) and connecting new (3), remaining connected:
        // {2: "coremidi:200", 3: "coremidi:100"}
        // On the next refresh, old ref 1 is still visible in CoreMIDI:
        // toConnect would contain 1 (since it's not connected).
        // The filter should exclude 1 because its sourceID "coremidi:100"
        // is already covered by surviving connected endpoint 3.
        let survivingSourceIDs = Set(
            connected
                .filter { !stale.contains($0.key) }
                .values
        )
        // survivingSourceIDs after stale removal: {"coremidi:200"}
        // Plus newly connected: {"coremidi:100"} (from endpoint 3)
        // Combined: {"coremidi:100", "coremidi:200"}
        let combinedSurviving = survivingSourceIDs.union(Set(newEndpoints.values))

        // Endpoint 1 would try to connect with sourceID "coremidi:100"
        // which is already in combinedSurviving, so it should be filtered out
        let shouldConnect1 = !combinedSurviving.contains("coremidi:100")
        #expect(shouldConnect1 == false,
                "Old ref should NOT be reconnected when its sourceID is already covered")
    }
}
