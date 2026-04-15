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
        MetronomeEngine()
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
        func start(_ onChange: @escaping () -> Void) {}
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

    @Test("selected-source disconnects are ignored when MIDI is not required for gameplay")
    func testSelectedSourceDisconnectIgnoredWhenMIDINotRequired() async throws {
        let (settingsManager, userDefaults, suiteName) = TestInputSettingsManager.makeIsolated(
            suiteName: "GameplayMIDIDisconnectTests.testSelectedSourceDisconnectIgnoredWhenMIDINotRequired"
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

        #expect(viewModel.isPlaying == true)
        #expect(viewModel.isShowingMIDIDeviceAlert == false)
    }
}
