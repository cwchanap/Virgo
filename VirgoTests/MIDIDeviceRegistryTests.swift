import Testing
import Foundation
@testable import Virgo

@Suite("MIDIDeviceRegistry Tests", .serialized)
@MainActor
struct MIDIDeviceRegistryTests {
    private let keyboardMappingsKey = "InputSettingsKeyboardMappings"
    private let midiMappingsKey = "InputSettingsMidiMappings"
    private let selectedMIDISourceKey = "InputSettingsSelectedMIDISource"

    private func clearPersistedSettings() {
        UserDefaults.standard.removeObject(forKey: keyboardMappingsKey)
        UserDefaults.standard.removeObject(forKey: midiMappingsKey)
        UserDefaults.standard.removeObject(forKey: selectedMIDISourceKey)
    }

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

        func start(_ onChange: @escaping () -> Void) {
            self.onChange = onChange
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
        clearPersistedSettings()
        defer { clearPersistedSettings() }

        let settings = InputSettingsManager()
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
        clearPersistedSettings()
        defer { clearPersistedSettings() }

        let settings = InputSettingsManager()
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
    func startMonitoringRefreshesOnSourceChange() async throws {
        clearPersistedSettings()
        defer { clearPersistedSettings() }

        let listener = StubMIDISourceChangeListener()
        let provider = StubMIDISourceProvider([
            .init(id: "coremidi:1", displayName: "SPD-SX", isConnected: true)
        ])
        let settings = InputSettingsManager()

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
        try await Task.sleep(for: .milliseconds(10))

        #expect(registry.sources.first?.id == "coremidi:2")
    }

    @Test("selectSource persists the chosen source")
    func selectSourcePersistsTheChosenSource() {
        clearPersistedSettings()
        defer { clearPersistedSettings() }

        let settings = InputSettingsManager()
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
    func selectedSourceUnavailableCallbackFiresWhenAvailableSourceDisappears() async throws {
        clearPersistedSettings()
        defer { clearPersistedSettings() }

        let settings = InputSettingsManager()
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
        try await Task.sleep(for: .milliseconds(10))

        #expect(unavailableSourceID == "coremidi:2")
        #expect(registry.isSelectedSourceAvailable == false)
    }
}
