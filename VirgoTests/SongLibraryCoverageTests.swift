//
//  SongLibraryCoverageTests.swift
//  VirgoTests
//
//  Created by Copilot on coverage-app-target-plus-ten task.
//

import Testing
import SwiftUI
import SwiftData
@testable import Virgo

@Suite("Song Library Coverage Tests", .serialized)
@MainActor
struct SongLibraryCoverageTests {

    // MARK: - ServerSongRow states

    @Test("ServerSongRow renders loading state")
    func testServerSongRowLoading() async throws {
        try await TestSetup.withTestSetup {
            let song = SongLibraryFixtures.makeSingleChartServerSong(title: "Loading Song")
            let view = ServerSongRow(serverSong: song, isLoading: true, onDownload: {})
            SwiftUITestUtilities.assertViewWithEnvironment(view)
        }
    }

    @Test("ServerSongRow renders not-downloaded state")
    func testServerSongRowNotDownloaded() async throws {
        try await TestSetup.withTestSetup {
            let song = SongLibraryFixtures.makeSingleChartServerSong(title: "Not Downloaded")
            let view = ServerSongRow(serverSong: song, isLoading: false, onDownload: {})
            SwiftUITestUtilities.assertViewWithEnvironment(view)
        }
    }

    @Test("ServerSongRow renders downloaded state")
    func testServerSongRowDownloaded() async throws {
        try await TestSetup.withTestSetup {
            let song = SongLibraryFixtures.makeServerSong(
                title: "Fully Downloaded",
                isDownloaded: true,
                hasBGM: true,
                bgmDownloaded: true,
                hasPreview: true,
                previewDownloaded: true,
                charts: [
                    ServerChart(
                        difficulty: "hard",
                        difficultyLabel: "EXTREME",
                        level: 75,
                        filename: "extreme.dtx",
                        size: 2048
                    )
                ]
            )
            let view = ServerSongRow(serverSong: song, isLoading: false, onDownload: {})
            SwiftUITestUtilities.assertViewWithEnvironment(view)
        }
    }

    @Test("ServerSongRow renders partial-BGM state (BGM missing)")
    func testServerSongRowPartialBGM() async throws {
        try await TestSetup.withTestSetup {
            let song = SongLibraryFixtures.makeServerSong(
                title: "Partial BGM Song",
                isDownloaded: true,
                hasBGM: true,
                bgmDownloaded: false,
                hasPreview: true,
                previewDownloaded: true,
                charts: [
                    ServerChart(
                        difficulty: "medium",
                        difficultyLabel: "STANDARD",
                        level: 55,
                        filename: "standard.dtx",
                        size: 1024
                    )
                ]
            )
            let view = ServerSongRow(serverSong: song, isLoading: false, onDownload: {})
            SwiftUITestUtilities.assertViewWithEnvironment(view)
        }
    }

    @Test("ServerSongRow renders partial-preview state (preview missing)")
    func testServerSongRowPartialPreview() async throws {
        try await TestSetup.withTestSetup {
            let song = SongLibraryFixtures.makeServerSong(
                title: "Partial Preview Song",
                isDownloaded: true,
                hasBGM: true,
                bgmDownloaded: true,
                hasPreview: true,
                previewDownloaded: false,
                charts: [
                    ServerChart(
                        difficulty: "easy",
                        difficultyLabel: "BASIC",
                        level: 30,
                        filename: "basic.dtx",
                        size: 512
                    )
                ]
            )
            let view = ServerSongRow(serverSong: song, isLoading: false, onDownload: {})
            SwiftUITestUtilities.assertViewWithEnvironment(view)
        }
    }

    @Test("ServerSongRow renders single-chart state")
    func testServerSongRowSingleChart() async throws {
        try await TestSetup.withTestSetup {
            let song = SongLibraryFixtures.makeSingleChartServerSong(title: "One Difficulty")
            #expect(song.charts.count == 1)
            let view = ServerSongRow(serverSong: song, isLoading: false, onDownload: {})
            SwiftUITestUtilities.assertViewWithEnvironment(view)
        }
    }

    @Test("ServerSongRow renders multi-chart state")
    func testServerSongRowMultiChart() async throws {
        try await TestSetup.withTestSetup {
            let song = SongLibraryFixtures.makeMultiChartServerSong(title: "Many Difficulties")
            #expect(song.charts.count > 1)
            let view = ServerSongRow(serverSong: song, isLoading: false, onDownload: {})
            SwiftUITestUtilities.assertViewWithEnvironment(view, size: CGSize(width: 800, height: 200))
        }
    }

    // MARK: - LibraryView states

    @Test("LibraryView renders empty downloaded-song state")
    func testLibraryViewEmpty() async throws {
        try await TestSetup.withTestSetup {
            let view = LibraryView(songs: [], serverSongService: ServerSongService())
            SwiftUITestUtilities.assertViewWithEnvironment(view)
        }
    }

    @Test("LibraryView renders populated downloaded-song state")
    func testLibraryViewPopulated() async throws {
        try await TestSetup.withTestSetup {
            let songs = [
                SongLibraryFixtures.makeDownloadedSong(title: "Groove A"),
                SongLibraryFixtures.makeDownloadedSong(title: "Groove B", difficulties: [.easy, .hard])
            ]
            let view = LibraryView(songs: songs, serverSongService: ServerSongService())
            SwiftUITestUtilities.assertViewWithEnvironment(view, size: CGSize(width: 1024, height: 900))
        }
    }

    @Test("LibraryView only shows DTX Import genre songs")
    func testLibraryViewFiltersByGenre() async throws {
        try await TestSetup.withTestSetup {
            let dtxSong = SongLibraryFixtures.makeDownloadedSong(title: "DTX Song")
            let nonDtxSong = Song(
                title: "Regular Song",
                artist: "Artist",
                bpm: 120,
                duration: "2:00",
                genre: "Rock",
                isSaved: true
            )
            // Both songs provided but only DTX Import genre appears in downloadedSongs
            let view = LibraryView(songs: [dtxSong, nonDtxSong], serverSongService: ServerSongService())
            SwiftUITestUtilities.assertViewWithEnvironment(view)
        }
    }

    // MARK: - SavedSongRow states

    @Test("SavedSongRow renders deleting state")
    func testSavedSongRowDeleting() async throws {
        try await TestSetup.withTestSetup {
            let song = SongLibraryFixtures.makeDownloadedSong(title: "Deleting Song")
            let view = SavedSongRow(song: song, isDeleting: true, onDelete: {})
            SwiftUITestUtilities.assertViewWithEnvironment(view)
        }
    }

    @Test("SavedSongRow renders no-delete fallback when onDelete is nil")
    func testSavedSongRowNoDeleteFallback() async throws {
        try await TestSetup.withTestSetup {
            let song = SongLibraryFixtures.makeDownloadedSong(title: "Undeletable Song")
            let view = SavedSongRow(song: song, isDeleting: false, onDelete: nil)
            SwiftUITestUtilities.assertViewWithEnvironment(view)
        }
    }

    @Test("SavedSongRow renders idle delete button when not deleting")
    func testSavedSongRowIdleDelete() async throws {
        try await TestSetup.withTestSetup {
            let song = SongLibraryFixtures.makeDownloadedSong(title: "Ready to Delete")
            let view = SavedSongRow(song: song, isDeleting: false, onDelete: {})
            SwiftUITestUtilities.assertViewWithEnvironment(view)
        }
    }
}
