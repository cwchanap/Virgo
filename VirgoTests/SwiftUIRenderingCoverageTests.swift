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
@testable import Virgo

@Suite("SwiftUI Rendering Coverage Tests", .serialized)
@MainActor
struct SwiftUIRenderingCoverageTests {
    private let drumNotationSettingsKey = "DrumNotationSettings"

    @Test("SettingsView renders inside a navigation stack")
    func testSettingsViewRendering() async throws {
        try await TestSetup.withTestSetup {
            let view = NavigationStack {
                SettingsView()
            }
            .environmentObject(MetronomeEngine())

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

    @Test("DrumNotationSettingsManager persists custom positions and resets defaults")
    func testDrumNotationSettingsManagerPersistence() async throws {
        try await TestSetup.withTestSetup {
            let userDefaults = UserDefaults.standard
            let originalValue = userDefaults.object(forKey: drumNotationSettingsKey)

            defer {
                if let originalValue {
                    userDefaults.set(originalValue, forKey: drumNotationSettingsKey)
                } else {
                    userDefaults.removeObject(forKey: drumNotationSettingsKey)
                }
            }

            userDefaults.removeObject(forKey: drumNotationSettingsKey)

            let manager = DrumNotationSettingsManager()
            manager.loadSettings()

            for drumType in DrumType.allCases {
                #expect(manager.getNotePosition(for: drumType) == drumType.notePosition)
            }

            manager.setNotePosition(.belowLine6, for: .snare)
            #expect(manager.getNotePosition(for: .snare) == .belowLine6)

            let reloadedManager = DrumNotationSettingsManager()
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
}
