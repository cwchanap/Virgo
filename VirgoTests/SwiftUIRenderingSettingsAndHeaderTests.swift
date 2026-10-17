//
//  SwiftUIRenderingSettingsAndHeaderTests.swift
//  VirgoTests
//
//  Created by Devin on 30/5/2026.
//

import Testing
import SwiftUI
import Foundation
import SwiftData
#if os(macOS)
import AppKit
#endif
@testable import Virgo

@Suite("SwiftUI Settings and Header Rendering Tests", .serialized)
@MainActor
struct SwiftUIRenderingSettingsAndHeaderTests {
    @Test("ProfileView renders inside a navigation stack")
    func testProfileViewRendering() async throws {
        try await TestSetup.withTestSetup {
            let view = NavigationStack {
                ProfileView()
            }

            SwiftUITestUtilities.assertViewWithEnvironment(view)
        }
    }

    @Test("InputSettingsView renders its default mapping state")
    func testInputSettingsViewRendering() async throws {
        try await TestSetup.withTestSetup {
            SwiftUITestUtilities.assertViewWithEnvironment(
                InputSettingsView(),
                size: CGSize(width: 1440, height: 1400)
            )
        }
    }

    @Test("InputSettingsView renders key capture overlay state")
    func testInputSettingsViewRenderingWithCaptureOverlay() async throws {
        try await TestSetup.withTestSetup {
            #if os(macOS)
            let keyCaptureState = InputKeyCaptureState()
            keyCaptureState.selectedDrumType = .snare
            keyCaptureState.isCapturingKey = true
            let mountedView = SwiftUITestUtilities.assertViewWithEnvironment(
                InputSettingsView(keyCaptureState: keyCaptureState),
                size: CGSize(width: 1440, height: 1400)
            )
            let renderedTexts = SwiftUITestUtilities.renderedTexts(from: mountedView.root)
            #expect(
                renderedTexts.contains("Press any key"),
                "Expected the mounted overlay prompt to be rendered; got \(renderedTexts)"
            )
            #expect(
                renderedTexts.contains("for \(DrumType.snare.description)"),
                "Expected the mounted overlay to include the selected drum; got \(renderedTexts)"
            )
            #endif
        }
    }

    // MARK: - keyCapturingOverlay (consolidated from SecondWaveCoverageTests)

    @Test("InputSettingsView.keyCapturingOverlay renders without a drum selection")
    func testKeyCapturingOverlayRendersWithoutDrumSelection() async throws {
        try await TestSetup.withTestSetup {
            let keyCaptureState = InputKeyCaptureState()
            keyCaptureState.isCapturingKey = true

            SwiftUITestUtilities.assertViewWithEnvironment(
                InputSettingsView(keyCaptureState: keyCaptureState),
                size: CGSize(width: 1024, height: 768)
            )
        }
    }

    // MARK: - InputKeyCaptureViewModel (consolidated from InputNotationCoverageTests)

    @Test("InputKeyCaptureViewModel mirrors the injected capture state")
    func inputKeyCaptureViewModelMirrorsInjectedState() async throws {
        try await TestSetup.withTestSetup {
            let keyCaptureState = InputKeyCaptureState()
            let viewModel = InputKeyCaptureViewModel(state: keyCaptureState)

            viewModel.startCapture(for: .snare)

            let started = await TestHelpers.waitFor {
                viewModel.selectedDrumType == .snare &&
                    viewModel.isCapturingKey &&
                    keyCaptureState.selectedDrumType == .snare &&
                    keyCaptureState.isCapturingKey
            }
            #expect(started, "Expected startCapture(for:) to update the shared capture state")

            viewModel.cancelCapture()

            let cancelled = await TestHelpers.waitFor {
                viewModel.selectedDrumType == nil &&
                    !viewModel.isCapturingKey &&
                    keyCaptureState.selectedDrumType == nil &&
                    !keyCaptureState.isCapturingKey
            }
            #expect(cancelled, "Expected cancelCapture() to clear the shared capture state")
        }
    }

    @Test("InputKeyCaptureViewModel deallocates after references are released")
    func inputKeyCaptureViewModelDeallocatesAfterRelease() async throws {
        try await TestSetup.withTestSetup {
            let keyCaptureState = InputKeyCaptureState()
            weak var weakViewModel: InputKeyCaptureViewModel?

            var viewModel: InputKeyCaptureViewModel? = InputKeyCaptureViewModel(state: keyCaptureState)
            weakViewModel = viewModel

            #expect(weakViewModel != nil)

            viewModel = nil
            await Task.yield()

            #expect(weakViewModel == nil, "View model should release its Combine subscriptions on deinit")
        }
    }

    // MARK: - InputSettingsView MIDI panels (consolidated from InputSettingsMIDICoverageTests)

    private final class StubMIDISourceProvider: MIDISourceProviding {
        let sources: [MIDISourceDescriptor]

        init(_ sources: [MIDISourceDescriptor]) {
            self.sources = sources
        }

        func currentSources() -> [MIDISourceDescriptor] {
            sources
        }
    }

    @Test("InputSettingsView renders source picker and diagnostics panel")
    func inputSettingsViewRendersMIDISourceAndDiagnostics() async throws {
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
    func inputSettingsViewRendersReplaceAndLearnFeedback() async throws {
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

    @Test("MetronomeView renders practice tips and settings layout")
    func testMetronomeViewRendering() async throws {
        try await TestSetup.withTestSetup {
            let view = NavigationStack {
                MetronomeView()
            }
            .environmentObject(MetronomeEngine(audioDriver: RecordingAudioDriver()))

            SwiftUITestUtilities.assertViewWithEnvironment(view)
        }
    }

    @Test("GameplayHeaderView renders score and transport controls")
    func testGameplayHeaderViewRendering() async throws {
        try await TestSetup.withTestSetup {
            let chart = Chart(difficulty: .hard, level: 70)
            let song = Song(
                title: "Header Song",
                artist: "Header Artist",
                bpm: 160,
                duration: "2:34",
                genre: "Render Test",
                charts: [chart]
            )
            chart.song = song
            let track = DrumTrack(chart: chart)

            let view = GameplayHeaderView(
                track: track,
                isPlaying: .constant(true),
                viewModel: nil,
                onDismiss: {},
                onPlayPause: {},
                onRestart: {}
            )
            .background(Color.black)

            SwiftUITestUtilities.assertViewWithEnvironment(view, size: CGSize(width: 1280, height: 120))
        }
    }

    @Test("GameplayHeaderView renders score snapshot stats")
    func testGameplayHeaderViewRendersScoreSnapshotStats() async throws {
        try await TestSetup.withTestSetup {
            let vm = await GameplayViewModelCoverageTestSupport.makePreparedViewModel()
            vm.isPlaying = true
            let note = try #require(vm.cachedNotes.first)
            let result = NoteMatchResult(
                hitInput: InputHit(drumType: .kick, velocity: 1.0, timestamp: Date()),
                matchedNote: note,
                timingAccuracy: .perfect,
                measureNumber: note.measureNumber,
                measureOffset: note.measureOffset,
                timingError: 0.0
            )
            vm.recordHit(result: result)

            let track = try #require(vm.track)
            let view = GameplayHeaderView(
                track: track,
                isPlaying: .constant(true),
                viewModel: vm,
                onDismiss: {},
                onPlayPause: {},
                onRestart: {}
            )
            .background(Color.black)

            SwiftUITestUtilities.assertView(
                view,
                containsStrings: ["SCORE", "ACC", "QLTY", "100%", "1x"],
                size: CGSize(width: 1280, height: 130)
            )
            vm.cleanup()
        }
    }

    @Test("GameplayHeaderView uses compact score layout at compact portrait width")
    func testGameplayHeaderViewUsesCompactScoreLayoutAtPortraitWidth() async throws {
        try await TestSetup.withTestSetup {
            let vm = await GameplayViewModelCoverageTestSupport.makePreparedViewModel()
            vm.isPlaying = true
            let note = try #require(vm.cachedNotes.first)
            let result = NoteMatchResult(
                hitInput: InputHit(drumType: .kick, velocity: 1.0, timestamp: Date()),
                matchedNote: note,
                timingAccuracy: .perfect,
                measureNumber: note.measureNumber,
                measureOffset: note.measureOffset,
                timingError: 0.0
            )
            vm.recordHit(result: result)

            let track = try #require(vm.track)
            let view = GameplayHeaderView(
                track: track,
                isPlaying: .constant(true),
                viewModel: vm,
                onDismiss: {},
                onPlayPause: {},
                onRestart: {}
            )
            .background(Color.black)

            let mountedView = SwiftUITestUtilities.assertViewWithEnvironment(
                view,
                size: CGSize(width: 390, height: 160)
            )
            let texts = SwiftUITestUtilities.renderedTexts(from: mountedView.root)

            for string in ["SCORE", "ACC", "QLTY", "100%", "1x"] {
                #expect(
                    texts.contains(string),
                    "Expected compact header texts to include '\(string)', got \(texts)"
                )
            }

            vm.cleanup()
        }
    }

    @Test("MainMenuView renders the start menu without entering ContentView")
    func testMainMenuViewRendersStartMenu() async throws {
        try await TestSetup.withTestSetup {
            let menu = MainMenuView()

            SwiftUITestUtilities.assertView(
                menu,
                containsStrings: ["VIRGO", "START"],
                size: CGSize(width: 1024, height: 768)
            )
        }
    }

    // MARK: - Settings views (consolidated from SwiftUIRenderingCoverageTests)

    @Test("SettingsView renders inside a navigation stack")
    func testSettingsViewRendering() async throws {
        try await TestSetup.withTestSetup {
            let view = NavigationStack {
                SettingsView()
            }
            .environmentObject(MetronomeEngine(audioDriver: RecordingAudioDriver()))

            SwiftUITestUtilities.assertViewWithEnvironment(view)
        }
    }

    @Test("AudioSettingsView renders its sections")
    func testAudioSettingsViewRendering() async throws {
        try await TestSetup.withTestSetup {
            let view = NavigationStack {
                AudioSettingsView()
            }

            SwiftUITestUtilities.assertViewWithEnvironment(view)
        }
    }

    @Test("DrumNotationSettingsView renders interactive notation controls")
    func testDrumNotationSettingsViewRendering() async throws {
        try await TestSetup.withTestSetup {
            let view = NavigationStack {
                DrumNotationSettingsView()
            }

            SwiftUITestUtilities.assertViewWithEnvironment(
                view,
                size: CGSize(width: 1280, height: 1600)
            )
        }
    }
}
