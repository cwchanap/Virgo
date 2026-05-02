//
//  SwiftUIRenderingCoverageTests.swift
//  VirgoTests
//
//  Created by Copilot on 22/3/2026.
//

import Testing
import SwiftUI
import Foundation
import SwiftData
#if os(macOS)
import AppKit
#endif
@testable import Virgo

@Suite("SwiftUI Rendering Coverage Tests", .serialized)
@MainActor
struct SwiftUIRenderingCoverageTests {
    private let drumNotationSettingsKey = "DrumNotationSettings"

    private struct MountedLifecycleTextView: View {
        @State private var text = "Initial Text"

        var body: some View {
            Text(text)
                .onAppear {
                    text = "Mounted Text"
                }
        }
    }

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

    @Test("Render helper does not create visible windows")
    func testRenderHelperDoesNotCreateVisibleWindows() async throws {
        try await TestSetup.withTestSetup {
            #if os(macOS)
            let initialVisibleWindowCount = NSApp.windows.filter(\.isVisible).count

            SwiftUITestUtilities.assertViewWithEnvironment(Text("Offscreen Render"))

            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
            let finalVisibleWindowCount = NSApp.windows.filter(\.isVisible).count
            #expect(finalVisibleWindowCount == initialVisibleWindowCount)
            #endif
        }
    }

    @Test("assertView inspects the mounted hierarchy after onAppear updates")
    func testAssertViewUsesMountedHierarchyAfterOnAppear() async throws {
        try await TestSetup.withTestSetup {
            SwiftUITestUtilities.assertView(
                MountedLifecycleTextView(),
                containsStrings: ["Mounted Text"],
                excludesStrings: ["Initial Text"]
            )
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

    @Test("DrumNotationSettingsManager persists custom positions and resets defaults")
    func testDrumNotationSettingsManagerPersistence() async throws {
        try await TestSetup.withTestSetup {
            let (userDefaults, _) = TestUserDefaults.makeIsolated()
            userDefaults.removeObject(forKey: drumNotationSettingsKey)

            let manager = DrumNotationSettingsManager(userDefaults: userDefaults)
            manager.loadSettings()

            for drumType in DrumType.allCases {
                #expect(manager.getNotePosition(for: drumType) == drumType.notePosition)
            }

            manager.setNotePosition(.belowLine6, for: .snare)
            #expect(manager.getNotePosition(for: .snare) == .belowLine6)

            let reloadedManager = DrumNotationSettingsManager(userDefaults: userDefaults)
            reloadedManager.loadSettings()
            #expect(reloadedManager.getNotePosition(for: .snare) == .belowLine6)

            manager.resetToDefaults()
            #expect(manager.getNotePosition(for: .snare) == DrumType.snare.notePosition)
        }
    }

    @Test("GameplayLayout note positions expose stable display names and raw values")
    func testNotePositionDisplayNamesAndRawValues() {
        let positions = GameplayLayout.NotePosition.allCases
        #expect(!positions.isEmpty)

        let rawValues = Set(positions.map(\.rawValue))
        #expect(rawValues.count == positions.count)

        for position in positions {
            #expect(!position.displayName.isEmpty)
            #expect(!position.rawValue.isEmpty)
        }
    }

    @Test("Notation primitive note head renders the expected drum symbol")
    func testNotationPrimitiveViewsRenderExpectedSymbols() async throws {
        try await TestSetup.withTestSetup {
            let note = Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0)
            let noteHead = RenderedNoteHead(
                id: 42,
                sourceNoteID: ObjectIdentifier(note),
                drumType: .snare,
                voice: .upper,
                timePosition: 0,
                measureIndex: 0,
                row: 0,
                position: CGPoint(x: 40, y: 40),
                staffStep: -4,
                stemDirection: .up,
                interval: .quarter
            )

            SwiftUITestUtilities.assertView(
                NotationNoteHeadView(noteHead: noteHead, isActive: false),
                containsStrings: [DrumType.snare.symbol],
                size: CGSize(width: 120, height: 120)
            )
        }
    }

    @Test("Gameplay sheet sizing uses notation width only when note heads are active")
    func testGameplaySheetSizingUsesNotationWidthOnlyWhenActive() async throws {
        try await TestSetup.withTestSetup {
            let emptyViewModel = GameplayViewModelCoverageTestSupport.makeViewModel(
                chart: Chart(difficulty: .medium),
                noteCount: 0
            )
            await emptyViewModel.loadChartData()
            emptyViewModel.setupGameplay()

            let gameplayView = GameplayView(chart: emptyViewModel.chart, metronome: emptyViewModel.metronome)
            #expect(!gameplayView.usesNotationLayout(viewModel: emptyViewModel))
            #expect(emptyViewModel.cachedNotationLayout.measureBars.count >= 1)
            #expect(gameplayView.sheetContentWidth(viewModel: emptyViewModel) == GameplayLayout.maxRowWidth)

            let denseChart = Chart(difficulty: .medium)
            for index in 0..<32 {
                denseChart.notes.append(
                    Note(
                        interval: .sixteenth,
                        noteType: .snare,
                        measureNumber: 1,
                        measureOffset: Double(index) / 32.0
                    )
                )
            }
            let denseViewModel = GameplayViewModelCoverageTestSupport.makeViewModel(chart: denseChart)
            await denseViewModel.loadChartData()
            denseViewModel.setupGameplay()

            #expect(gameplayView.usesNotationLayout(viewModel: denseViewModel))
            #expect(gameplayView.sheetContentWidth(viewModel: denseViewModel) > GameplayLayout.maxRowWidth)
            #expect(
                gameplayView.sheetContentHeight(viewModel: denseViewModel)
                    == denseViewModel.cachedNotationLayout.totalHeight
            )
        }
    }

    @Test("LibraryView renders empty and populated downloaded-song states")
    func testLibraryViewRenderingStates() async throws {
        try await TestSetup.withTestSetup {
            let serverSongService = ServerSongService()

            SwiftUITestUtilities.assertViewWithEnvironment(
                LibraryView(songs: [], serverSongService: serverSongService)
            )

            let populatedView = LibraryView(
                songs: [makeDownloadedSong(title: "Library Song")],
                serverSongService: serverSongService
            )
            SwiftUITestUtilities.assertViewWithEnvironment(populatedView)
        }
    }

    @Test("ServerSongsView renders empty, loading, and populated states")
    func testServerSongsViewRenderingStates() async throws {
        try await TestSetup.withTestSetup {
            let idleService = ServerSongService()
            SwiftUITestUtilities.assertViewWithEnvironment(
                ServerSongsView(serverSongs: [], serverSongService: idleService)
            )

            let loadingService = ServerSongService()
            loadingService.isRefreshing = true
            SwiftUITestUtilities.assertViewWithEnvironment(
                ServerSongsView(serverSongs: [], serverSongService: loadingService)
            )

            let populatedView = ServerSongsView(
                serverSongs: [makeServerSong(title: "Server Song", isDownloaded: true)],
                serverSongService: ServerSongService()
            )
            SwiftUITestUtilities.assertViewWithEnvironment(populatedView)
        }
    }

    @Test("SongsTabView renders downloaded content and filtering state")
    func testSongsTabViewRendering() async throws {
        try await TestSetup.withTestSetup {
            let downloadedSong = makeDownloadedSong(title: "Downloaded Groove")
            let remoteSong = makeServerSong(title: "Remote Groove")
            let audioPlaybackService = AudioPlaybackService(startPlayback: { _ in false })

            let view = SongsTabView(
                allSongs: [downloadedSong],
                serverSongs: [remoteSong],
                serverSongService: ServerSongService(),
                searchText: .constant("Downloaded"),
                currentlyPlaying: .constant(nil),
                expandedSongId: .constant(nil),
                selectedChart: .constant(nil),
                navigateToGameplay: .constant(false),
                audioPlaybackService: audioPlaybackService,
                onPlayTap: { _ in },
                onSaveTap: { _ in }
            )

            SwiftUITestUtilities.assertViewWithEnvironment(
                view,
                size: CGSize(width: 1280, height: 900)
            )
        }
    }

    @Test("SessionResultsView renders a verified new high score state")
    func testSessionResultsViewRenderingForNewRecord() async throws {
        try await TestSetup.withTestSetup {
            let view = SessionResultsView(
                finalScore: 2450,
                highScore: 2450,
                isNewRecord: true,
                scoreEngine: makeScoreEngineForResults(),
                onPlayAgain: {},
                onDone: {}
            )

            SwiftUITestUtilities.assertViewWithEnvironment(
                view,
                size: CGSize(width: 900, height: 900)
            )
        }
    }

    @Test("SessionResultsView renders non-record results without the badge path")
    func testSessionResultsViewRenderingWithoutRecordBadge() async throws {
        try await TestSetup.withTestSetup {
            var scoreEngine = ScoreEngine()
            scoreEngine.processHit(accuracy: .great, timingError: 12.0)
            scoreEngine.processHit(accuracy: .miss)

            let view = SessionResultsView(
                finalScore: 80,
                highScore: 900,
                isNewRecord: false,
                scoreEngine: scoreEngine,
                onPlayAgain: {},
                onDone: {}
            )

            SwiftUITestUtilities.assertViewWithEnvironment(
                view,
                size: CGSize(width: 900, height: 900)
            )
        }
    }

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

    @Test("DrumBeatView renders simultaneous beamed notes")
    func testDrumBeatViewRendering() async throws {
        try await TestSetup.withTestSetup {
            let beat = DrumBeat(
                id: 42,
                drums: [.snare, .crash, .ride],
                timePosition: 1.5,
                interval: .eighth
            )

            SwiftUITestUtilities.assertViewWithEnvironment(
                DrumBeatView(beat: beat, isActive: true, row: 0, isBeamed: true),
                size: CGSize(width: 240, height: 180)
            )
        }
    }

    private func makeDownloadedSong(title: String) -> Song {
        let notes = [
            Note(interval: .quarter, noteType: .bass, measureNumber: 1, measureOffset: 0.0),
            Note(interval: .quarter, noteType: .snare, measureNumber: 2, measureOffset: 0.5)
        ]
        let chart = Chart(difficulty: .hard, level: 70, notes: notes)
        let song = Song(
            title: title,
            artist: "Render Artist",
            bpm: 128.0,
            duration: "2:15",
            genre: "DTX Import",
            charts: [chart],
            isSaved: true
        )

        chart.song = song
        notes.forEach { $0.chart = chart }
        return song
    }

    private func makeServerSong(title: String, isDownloaded: Bool = false) -> ServerSong {
        let charts = [
            ServerChart(
                difficulty: "easy",
                difficultyLabel: "BASIC",
                level: 25,
                filename: "basic.dtx",
                size: 1024
            ),
            ServerChart(
                difficulty: "hard",
                difficultyLabel: "EXTREME",
                level: 70,
                filename: "extreme.dtx",
                size: 2048
            )
        ]

        let song = ServerSong(
            songId: title.lowercased().replacingOccurrences(of: " ", with: "-"),
            title: title,
            artist: "Server Artist",
            bpm: 150.0,
            charts: charts,
            isDownloaded: isDownloaded,
            hasBGM: true,
            bgmDownloaded: isDownloaded,
            hasPreview: true,
            previewDownloaded: isDownloaded
        )

        charts.forEach { $0.serverSong = song }
        return song
    }

    private func makeScoreEngineForResults() -> ScoreEngine {
        var engine = ScoreEngine()
        for _ in 0..<15 { engine.processHit(accuracy: .perfect, timingError: -8.0) }
        for _ in 0..<5 { engine.processHit(accuracy: .great, timingError: 15.0) }
        for _ in 0..<2 { engine.processHit(accuracy: .good, timingError: 45.0) }
        for _ in 0..<3 { engine.processHit(accuracy: .miss) }
        return engine
    }
}
