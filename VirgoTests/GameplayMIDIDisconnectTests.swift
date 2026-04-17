import Testing
import Foundation
@testable import Virgo

@Suite("Gameplay MIDI Disconnect Tests", .serialized)
@MainActor
struct GameplayMIDIDisconnectTests {
    private func createTestPracticeSettings() -> PracticeSettingsService {
        let (userDefaults, _) = TestUserDefaults.makeIsolated()
        return PracticeSettingsService(userDefaults: userDefaults)
    }

    private func createTestChart(noteCount: Int = 4) -> Chart {
        let chart = Chart(difficulty: .medium)

        for index in 0..<noteCount {
            let note = Note(
                interval: .quarter,
                noteType: index.isMultiple(of: 2) ? .bass : .snare,
                measureNumber: (index / 4) + 1,
                measureOffset: Double(index % 4) * 0.25
            )
            chart.notes.append(note)
        }

        return chart
    }

    private func createTestMetronome() -> MetronomeEngine {
        MetronomeEngine(audioDriver: RecordingAudioDriver())
    }

    final class StubMIDISourceProvider: MIDISourceProviding {
        let sources: [MIDISourceDescriptor]

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
        selectedSourceID: String?,
        midiMapping: [UInt8: DrumType],
        requiresMIDISourceForGameplay: Bool,
        selectedSourceAvailable: Bool
    ) -> InputManager {
        if let selectedSourceID {
            settingsManager.setSelectedMIDISource(id: selectedSourceID, displayName: "TD-17")
        }

        for (note, drumType) in midiMapping {
            settingsManager.setMidiMapping(note, for: drumType)
        }

        let sources: [MIDISourceDescriptor]
        if selectedSourceAvailable, let selectedSourceID {
            sources = [
                MIDISourceDescriptor(id: selectedSourceID, displayName: "TD-17", isConnected: true)
            ]
        } else {
            sources = []
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
        manager.requiresMIDISourceForGameplay = requiresMIDISourceForGameplay
        manager.reloadMappingsFromSettings()
        return manager
    }

    @Test("startPlayback refuses MIDI gameplay when a selected source is unavailable")
    func testStartPlaybackRequiresAvailableMIDISource() async throws {
        let (settingsManager, userDefaults, suiteName) = TestInputSettingsManager.makeIsolated(
            suiteName: "GameplayMIDIDisconnectTests.testStartPlaybackRequiresAvailableMIDISource"
        )
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let chart = createTestChart()
        let metronome = createTestMetronome()
        let viewModel = GameplayViewModel(
            chart: chart,
            metronome: metronome,
            practiceSettings: createTestPracticeSettings()
        )
        defer { viewModel.cleanup() }

        viewModel.inputManager = makeInputManagerForTest(
            settingsManager: settingsManager,
            selectedSourceID: "coremidi:2",
            midiMapping: [38: .snare],
            requiresMIDISourceForGameplay: true,
            selectedSourceAvailable: false
        )
        await viewModel.loadChartData()
        viewModel.setupGameplay()

        viewModel.startPlayback()

        #expect(viewModel.isPlaying == false)
        #expect(viewModel.isShowingMIDIDeviceAlert == true)
        #expect(viewModel.midiDeviceAlertMessage.contains("Reconnect"))
    }

    @Test("startPlayback prompts for source selection when no MIDI source is selected")
    func testStartPlaybackPromptsForSourceSelection() async throws {
        let (settingsManager, userDefaults, suiteName) = TestInputSettingsManager.makeIsolated(
            suiteName: "GameplayMIDIDisconnectTests.testStartPlaybackPromptsForSourceSelection"
        )
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let chart = createTestChart()
        let metronome = createTestMetronome()
        let viewModel = GameplayViewModel(
            chart: chart,
            metronome: metronome,
            practiceSettings: createTestPracticeSettings()
        )
        defer { viewModel.cleanup() }

        viewModel.inputManager = makeInputManagerForTest(
            settingsManager: settingsManager,
            selectedSourceID: nil,
            midiMapping: [:],
            requiresMIDISourceForGameplay: true,
            selectedSourceAvailable: false
        )
        await viewModel.loadChartData()
        viewModel.setupGameplay()

        viewModel.startPlayback()

        #expect(viewModel.isPlaying == false)
        #expect(viewModel.isShowingMIDIDeviceAlert == true)
        #expect(viewModel.midiDeviceAlertMessage.contains("Select"))
    }

    @Test("startPlayback reloads a newly persisted selected source before gating MIDI gameplay")
    func testStartPlaybackReloadsPersistedSelectedSourceBeforeGatingGameplay() async throws {
        let (staleSettingsManager, userDefaults, suiteName) = TestInputSettingsManager.makeIsolated(
            suiteName: "GameplayMIDIDisconnectTests.testStartPlaybackReloadsPersistedSelectedSourceBeforeGatingGameplay"
        )
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let chart = createTestChart()
        let metronome = createTestMetronome()
        let viewModel = GameplayViewModel(
            chart: chart,
            metronome: metronome,
            practiceSettings: createTestPracticeSettings()
        )
        defer { viewModel.cleanup() }

        let registry = MIDIDeviceRegistry(
            settingsManager: staleSettingsManager,
            sourceProvider: StubMIDISourceProvider([
                MIDISourceDescriptor(id: "coremidi:2", displayName: "TD-17", isConnected: true)
            ]),
            sourceChangeListener: StubMIDISourceChangeListener()
        )
        let manager = InputManager(
            settingsManager: staleSettingsManager,
            deviceRegistry: registry,
            diagnosticsStore: MIDIDiagnosticsStore(),
            learnSession: MIDILearnSession(settingsManager: staleSettingsManager)
        )
        manager.requiresMIDISourceForGameplay = true

        let settingsViewManager = InputSettingsManager(userDefaults: userDefaults)
        settingsViewManager.setSelectedMIDISource(id: "coremidi:2", displayName: "TD-17")

        viewModel.inputManager = manager
        await viewModel.loadChartData()
        viewModel.setupGameplay()

        viewModel.startPlayback()

        #expect(viewModel.isShowingMIDIDeviceAlert == false)
        #expect(viewModel.midiDeviceAlertMessage.isEmpty)
        #expect(viewModel.isPlaying == true)
    }

    @Test("selected source disconnect auto-pauses active gameplay")
    func testSelectedSourceDisconnectAutoPausesGameplay() async throws {
        let (settingsManager, userDefaults, suiteName) = TestInputSettingsManager.makeIsolated(
            suiteName: "GameplayMIDIDisconnectTests.testSelectedSourceDisconnectAutoPausesGameplay"
        )
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let chart = createTestChart()
        let metronome = createTestMetronome()
        let viewModel = GameplayViewModel(
            chart: chart,
            metronome: metronome,
            practiceSettings: createTestPracticeSettings()
        )
        defer { viewModel.cleanup() }

        viewModel.inputManager = makeInputManagerForTest(
            settingsManager: settingsManager,
            selectedSourceID: "coremidi:2",
            midiMapping: [38: .snare],
            requiresMIDISourceForGameplay: true,
            selectedSourceAvailable: true
        )
        await viewModel.loadChartData()
        viewModel.setupGameplay()
        viewModel.startPlayback()

        viewModel.handleSelectedMIDISourceDisconnect()

        #expect(viewModel.isPlaying == false)
        #expect(viewModel.isShowingMIDIDeviceAlert == true)
    }

    @Test("macOS selected-source start gating still applies when a source was explicitly chosen")
    func testMacOSSelectedSourceStillGatesWhenPreferenceExists() async throws {
        let (settingsManager, userDefaults, suiteName) = TestInputSettingsManager.makeIsolated(
            suiteName: "GameplayMIDIDisconnectTests.testMacOSSelectedSourceStillGatesWhenPreferenceExists"
        )
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let chart = createTestChart()
        let metronome = createTestMetronome()
        let viewModel = GameplayViewModel(
            chart: chart,
            metronome: metronome,
            practiceSettings: createTestPracticeSettings()
        )
        defer { viewModel.cleanup() }

        viewModel.inputManager = makeInputManagerForTest(
            settingsManager: settingsManager,
            selectedSourceID: "coremidi:2",
            midiMapping: [38: .snare],
            requiresMIDISourceForGameplay: false,
            selectedSourceAvailable: false
        )
        await viewModel.loadChartData()
        viewModel.setupGameplay()

        viewModel.startPlayback()

        #expect(viewModel.isPlaying == false)
        #expect(viewModel.isShowingMIDIDeviceAlert == true)
        #expect(viewModel.midiDeviceAlertMessage.contains("Reconnect"))
    }

    @Test("wireInputHandler routes selected-source disconnects through the input manager delegate")
    func testWireInputHandlerRoutesSelectedSourceDisconnects() async throws {
        let (settingsManager, userDefaults, suiteName) = TestInputSettingsManager.makeIsolated(
            suiteName: "GameplayMIDIDisconnectTests.testWireInputHandlerRoutesSelectedSourceDisconnects"
        )
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let chart = createTestChart()
        let metronome = createTestMetronome()
        let viewModel = GameplayViewModel(
            chart: chart,
            metronome: metronome,
            practiceSettings: createTestPracticeSettings()
        )
        defer { viewModel.cleanup() }

        viewModel.inputManager = makeInputManagerForTest(
            settingsManager: settingsManager,
            selectedSourceID: "coremidi:2",
            midiMapping: [38: .snare],
            requiresMIDISourceForGameplay: true,
            selectedSourceAvailable: true
        )
        viewModel.inputManager.delegate = viewModel.inputHandler
        viewModel.wireInputHandler()
        await viewModel.loadChartData()
        viewModel.setupGameplay()
        viewModel.startPlayback()

        viewModel.inputManager.handleSelectedSourceDisconnect(sourceID: "coremidi:2")

        #expect(viewModel.isPlaying == false)
        #expect(viewModel.isShowingMIDIDeviceAlert == true)
    }

    @Test("selected-source disconnects still pause gameplay when a macOS source was explicitly chosen")
    func testSelectedSourceDisconnectPausesGameplayWhenSelectionExistsOnMacOS() async throws {
        let (settingsManager, userDefaults, suiteName) = TestInputSettingsManager.makeIsolated(
            suiteName: "GameplayMIDIDisconnectTests.testSelectedSourceDisconnectPausesGameplayWhenSelectionExistsOnMacOS"
        )
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let chart = createTestChart()
        let metronome = createTestMetronome()
        let viewModel = GameplayViewModel(
            chart: chart,
            metronome: metronome,
            practiceSettings: createTestPracticeSettings()
        )
        defer { viewModel.cleanup() }

        viewModel.inputManager = makeInputManagerForTest(
            settingsManager: settingsManager,
            selectedSourceID: "coremidi:2",
            midiMapping: [38: .snare],
            requiresMIDISourceForGameplay: false,
            selectedSourceAvailable: true
        )
        viewModel.inputManager.delegate = viewModel.inputHandler
        viewModel.wireInputHandler()
        await viewModel.loadChartData()
        viewModel.setupGameplay()
        viewModel.startPlayback()

        viewModel.inputManager.handleSelectedSourceDisconnect(sourceID: "coremidi:2")

        #expect(viewModel.isPlaying == false)
        #expect(viewModel.isShowingMIDIDeviceAlert == true)
    }

    @Test("keyboard-first macOS playback remains ungated when no MIDI source is selected")
    func testKeyboardFirstMacOSPlaybackRemainsUngatedWithoutSelectedSource() async throws {
        let (settingsManager, userDefaults, suiteName) = TestInputSettingsManager.makeIsolated(
            suiteName: "GameplayMIDIDisconnectTests.testKeyboardFirstMacOSPlaybackRemainsUngatedWithoutSelectedSource"
        )
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let chart = createTestChart()
        let metronome = createTestMetronome()
        let viewModel = GameplayViewModel(
            chart: chart,
            metronome: metronome,
            practiceSettings: createTestPracticeSettings()
        )
        defer { viewModel.cleanup() }

        viewModel.inputManager = makeInputManagerForTest(
            settingsManager: settingsManager,
            selectedSourceID: nil,
            midiMapping: [:],
            requiresMIDISourceForGameplay: false,
            selectedSourceAvailable: false
        )
        await viewModel.loadChartData()
        viewModel.setupGameplay()

        viewModel.startPlayback()

        #expect(viewModel.isPlaying == true)
        #expect(viewModel.isShowingMIDIDeviceAlert == false)
    }
}
