import Testing
import SwiftUI
@testable import Virgo

@Suite("Input Settings MIDI Coverage Tests", .serialized)
@MainActor
struct InputSettingsMIDICoverageTests {
    final class StubMIDISourceProvider: MIDISourceProviding {
        let sources: [MIDISourceDescriptor]

        init(_ sources: [MIDISourceDescriptor]) {
            self.sources = sources
        }

        func currentSources() -> [MIDISourceDescriptor] {
            sources
        }
    }

    @Test("InputSettingsView renders source picker and diagnostics panel")
    func testInputSettingsViewRendersMIDISourceAndDiagnostics() async throws {
        try await TestSetup.withTestSetup {
            let (settings, userDefaults, suiteName) = TestInputSettingsManager.makeIsolated(
                suiteName: "InputSettingsMIDICoverageTests.testInputSettingsViewRendersMIDISourceAndDiagnostics"
            )
            defer { userDefaults.removePersistentDomain(forName: suiteName) }
            let registry = MIDIDeviceRegistry(
                settingsManager: settings,
                sourceProvider: StubMIDISourceProvider([
                    .init(id: "source-2", displayName: "TD-17", isConnected: true)
                ])
            )
            let diagnostics = MIDIDiagnosticsStore()
            diagnostics.record(
                event: MIDINoteEvent(sourceID: "source-2", channel: 9, note: 38, velocity: 120, hostTime: 10),
                mappedDrumType: .snare,
                sourceDisplayName: "TD-17"
            )

            let mounted = SwiftUITestUtilities.assertViewWithEnvironment(
                InputSettingsView(
                    settingsManager: settings,
                    midiDeviceRegistry: registry,
                    midiDiagnosticsStore: diagnostics,
                    midiLearnSession: MIDILearnSession(settingsManager: settings)
                ),
                size: CGSize(width: 1440, height: 1400)
            )

            let texts = SwiftUITestUtilities.renderedTexts(from: mounted.root)
            #expect(texts.contains("Gameplay MIDI Source"))
            #expect(texts.contains("TD-17"))
            #expect(texts.contains("Last MIDI Event"))
            #expect(texts.contains("Channel 10"))
            #expect(texts.contains("Learn"))
        }
    }

    @Test("InputSettingsView renders replace action and learn feedback")
    func testInputSettingsViewRendersReplaceAndLearnFeedback() async throws {
        try await TestSetup.withTestSetup {
            let (settings, userDefaults, suiteName) = TestInputSettingsManager.makeIsolated(
                suiteName: "InputSettingsMIDICoverageTests.testInputSettingsViewRendersReplaceAndLearnFeedback"
            )
            defer { userDefaults.removePersistentDomain(forName: suiteName) }
            settings.setSelectedMIDISource(id: "source-2", displayName: "TD-17")
            settings.setMidiMapping(38, for: .kick)

            let learnSession = MIDILearnSession(settingsManager: settings)
            learnSession.beginCapture(for: .snare)
            _ = learnSession.consume(
                MIDINoteEvent(sourceID: "source-2", channel: 9, note: 38, velocity: 120, hostTime: 10),
                selectedSourceID: "source-2"
            )

            let mounted = SwiftUITestUtilities.assertViewWithEnvironment(
                InputSettingsView(
                    settingsManager: settings,
                    midiLearnSession: learnSession
                ),
                size: CGSize(width: 1440, height: 1400)
            )

            let texts = SwiftUITestUtilities.renderedTexts(from: mounted.root)
            #expect(texts.contains("Replace"))
            #expect(texts.contains("Replaced Kick with Snare for note 38"))
        }
    }
}
