import Testing
import Foundation
@testable import Virgo

@Suite("MIDIDeviceRegistry Tests", .serialized)
@MainActor
struct MIDIDeviceRegistryTests {
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
        private var onChange: (() -> Void)?
        var startResult = true

        func start(_ onChange: @escaping () -> Void) -> Bool {
            self.onChange = onChange
            return startResult
        }

        func stop() {
            onChange = nil
        }

        func fire() {
            onChange?()
        }
    }

    @Test("refreshSources keeps persisted selection when the source still exists")
    func refreshSourcesKeepsPersistedSelection() {
        let (settings, userDefaults, suiteName) = TestInputSettingsManager.makeIsolated(
            suiteName: "MIDIDeviceRegistryTests.refreshSourcesKeepsPersistedSelection"
        )
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        settings.setSelectedMIDISource(id: "source-2", displayName: "TD-17")

        let registry = MIDIDeviceRegistry(
            settingsManager: settings,
            sourceProvider: StubMIDISourceProvider([
                .init(id: "source-1", displayName: "SPD-SX", isConnected: true),
                .init(id: "source-2", displayName: "TD-17", isConnected: true)
            ])
        )

        registry.refreshSources()

        #expect(registry.selectedSourceID == "source-2")
        #expect(registry.isSelectedSourceAvailable == true)
    }

    @Test("refreshSources preserves preferred selection when the source disappears")
    func refreshSourcesPreservesPreferredSelectionWhenSourceIsMissing() {
        let (settings, userDefaults, suiteName) = TestInputSettingsManager.makeIsolated(
            suiteName: "MIDIDeviceRegistryTests.refreshSourcesPreservesPreferredSelectionWhenSourceIsMissing"
        )
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        settings.setSelectedMIDISource(id: "source-2", displayName: "TD-17")

        let registry = MIDIDeviceRegistry(
            settingsManager: settings,
            sourceProvider: StubMIDISourceProvider([
                .init(id: "source-1", displayName: "SPD-SX", isConnected: true)
            ])
        )

        registry.refreshSources()

        #expect(registry.selectedSourceID == "source-2")
        #expect(registry.isSelectedSourceAvailable == false)
        #expect(settings.getSelectedMIDISource()?.id == "source-2")
        #expect(registry.displayName(for: "source-2") == "TD-17")
    }

    @Test("source-change notifications trigger a refresh")
    func startMonitoringRefreshesOnSourceChange() {
        let (settings, userDefaults, suiteName) = TestInputSettingsManager.makeIsolated(
            suiteName: "MIDIDeviceRegistryTests.startMonitoringRefreshesOnSourceChange"
        )
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let listener = StubMIDISourceChangeListener()
        let provider = StubMIDISourceProvider([
            .init(id: "coremidi:1", displayName: "SPD-SX", isConnected: true)
        ])

        let registry = MIDIDeviceRegistry(
            settingsManager: settings,
            sourceProvider: provider,
            sourceChangeListener: listener
        )

        registry.startMonitoring()
        provider.sources = [
            .init(id: "coremidi:2", displayName: "TD-17", isConnected: true)
        ]

        listener.fire()

        #expect(registry.sources.first?.id == "coremidi:2")
    }

    @Test("startMonitoring reports listener startup failure")
    func startMonitoringReportsListenerStartupFailure() {
        let (settings, userDefaults, suiteName) = TestInputSettingsManager.makeIsolated(
            suiteName: "MIDIDeviceRegistryTests.startMonitoringReportsListenerStartupFailure"
        )
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let listener = StubMIDISourceChangeListener()
        listener.startResult = false
        let registry = MIDIDeviceRegistry(
            settingsManager: settings,
            sourceProvider: StubMIDISourceProvider([
                .init(id: "coremidi:2", displayName: "TD-17", isConnected: true)
            ]),
            sourceChangeListener: listener
        )

        let didStart = registry.startMonitoring()

        #expect(didStart == false)
        #expect(registry.sources.first?.id == "coremidi:2")
    }

    @Test("selectSource persists the chosen source")
    func selectSourcePersistsTheChosenSource() {
        let (settings, userDefaults, suiteName) = TestInputSettingsManager.makeIsolated(
            suiteName: "MIDIDeviceRegistryTests.selectSourcePersistsTheChosenSource"
        )
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let source = MIDISourceDescriptor(id: "coremidi:2", displayName: "TD-17", isConnected: true)
        let registry = MIDIDeviceRegistry(
            settingsManager: settings,
            sourceProvider: StubMIDISourceProvider([source])
        )

        registry.refreshSources()
        registry.selectSource(source)

        #expect(registry.selectedSourceID == "coremidi:2")
        #expect(registry.isSelectedSourceAvailable == true)
        #expect(settings.getSelectedMIDISource()?.id == "coremidi:2")
        #expect(settings.getSelectedMIDISource()?.displayName == "TD-17")
    }

    @Test("selected-source-unavailable callback fires after a disconnect")
    func selectedSourceUnavailableCallbackFiresWhenAvailableSourceDisappears() {
        let (settings, userDefaults, suiteName) = TestInputSettingsManager.makeIsolated(
            suiteName: "MIDIDeviceRegistryTests.selectedSourceUnavailableCallbackFiresWhenAvailableSourceDisappears"
        )
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        settings.setSelectedMIDISource(id: "coremidi:2", displayName: "TD-17")

        let listener = StubMIDISourceChangeListener()
        let provider = StubMIDISourceProvider([
            .init(id: "coremidi:2", displayName: "TD-17", isConnected: true)
        ])
        let registry = MIDIDeviceRegistry(
            settingsManager: settings,
            sourceProvider: provider,
            sourceChangeListener: listener
        )

        var unavailableSourceID: String?
        registry.onSelectedSourceUnavailable = { sourceID in
            unavailableSourceID = sourceID
        }

        registry.startMonitoring()
        provider.sources = []

        listener.fire()

        #expect(unavailableSourceID == "coremidi:2")
        #expect(registry.isSelectedSourceAvailable == false)
    }
}
