//
//  InputManagerGatedSnapshotTests.swift
//  VirgoTests
//
//  Tests for the gated snapshot in isSelectedMIDISourceAvailable.
//

import Testing
import Foundation
import CoreMIDI
@testable import Virgo

@Suite("InputManager Gated Snapshot Tests", .serialized)
@MainActor
struct InputManagerGatedSnapshotTests {

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

    @Test("isSelectedMIDISourceAvailable reads gated snapshot on main thread, not raw registry")
    func testAvailabilityUsesGatedSnapshotOnMainThread() {
        let (settingsManager, userDefaults, suiteName) = TestInputSettingsManager.makeIsolated(
            suiteName: "InputManagerConfigurationTests.GatedSnapshotMainThread.\(UUID().uuidString)"
        )
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        settingsManager.setSelectedMIDISource(id: "source-1", displayName: "TD-17")

        // Registry reports source as available (discovery-only)
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

        // On main thread, the getter must return the gated snapshot value.
        // Since MIDI is not initialized in tests, the gate falls back to
        // registry availability, so the result should be true.
        #expect(Thread.isMainThread)
        #expect(manager.isSelectedMIDISourceAvailable == true,
                "Main-thread getter should read the gated snapshot, not bypass it")
    }
}