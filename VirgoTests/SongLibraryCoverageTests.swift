//
//  SongLibraryCoverageTests.swift
//  VirgoTests
//
//  Created by Copilot on 31/3/2026.
//

import Testing
import SwiftUI
@testable import Virgo

@Suite("Song Library Coverage Tests", .serialized)
@MainActor
struct SongLibraryCoverageTests {
    @Test("ServerSongRow renders loading state with chart and audio indicators")
    func testServerSongRowLoadingState() async throws {
        try await TestSetup.withTestSetup {
            let serverSong = SwiftUICoverageFixtures.makeServerSong(
                title: "Loading Groove",
                charts: [
                    SwiftUICoverageFixtures.makeServerChart(
                        difficulty: "hard",
                        difficultyLabel: "EXTREME",
                        level: 65,
                        filename: "loading.dtx",
                        size: 2_048
                    )
                ],
                hasBGM: true,
                hasPreview: true
            )

            SwiftUITestUtilities.assertView(
                ServerSongRow(serverSong: serverSong, isLoading: true, onDownload: {}),
                containsStrings: ["Loading Groove", "Downloading...", "Chart files", "Background music", "Preview audio"],
                excludesStrings: ["Download", "Charts", "BGM", "Preview"]
            )
        }
    }

    @Test("ServerSongRow renders single-chart download CTA")
    func testServerSongRowNotDownloadedSingleChartState() async throws {
        try await TestSetup.withTestSetup {
            let serverSong = SwiftUICoverageFixtures.makeServerSong(
                title: "Single Chart",
                charts: [
                    SwiftUICoverageFixtures.makeServerChart(
                        difficulty: "medium",
                        difficultyLabel: "STANDARD",
                        level: 36,
                        filename: "single.dtx",
                        size: 1_024
                    )
                ]
            )

            let mountedView = SwiftUITestUtilities.assertViewWithEnvironment(
                ServerSongRow(serverSong: serverSong, isLoading: false, onDownload: {})
            )
            let texts = SwiftUITestUtilities.renderedTexts(from: mountedView.root)

            #expect(texts.contains("Single Chart"), "Expected title; got \(texts)")
            #expect(texts.contains("Level 36"), "Expected level; got \(texts)")
            #expect(!texts.contains("Downloading..."), "Should not show downloading; got \(texts)")
            #expect(!texts.contains("Levels 36"), "Single chart should not show Levels; got \(texts)")
        }
    }

    @Test("ServerSongRow renders downloaded multi-chart summary and badges")
    func testServerSongRowDownloadedMultiChartState() async throws {
        try await TestSetup.withTestSetup {
            let serverSong = SwiftUICoverageFixtures.makeServerSong(
                title: "Downloaded Anthem",
                charts: [
                    SwiftUICoverageFixtures.makeServerChart(
                        difficulty: "easy",
                        difficultyLabel: "BASIC",
                        level: 25,
                        filename: "basic.dtx",
                        size: 1_024
                    ),
                    SwiftUICoverageFixtures.makeServerChart(
                        difficulty: "hard",
                        difficultyLabel: "EXTREME",
                        level: 70,
                        filename: "extreme.dtx",
                        size: 2_048
                    )
                ],
                isDownloaded: true,
                hasBGM: true,
                bgmDownloaded: true,
                hasPreview: true,
                previewDownloaded: true
            )

            SwiftUITestUtilities.assertView(
                ServerSongRow(serverSong: serverSong, isLoading: false, onDownload: {}),
                containsStrings: [
                    "Downloaded Anthem",
                    "Levels 25, 70",
                    "Charts",
                    "BGM",
                    "Preview"
                ],
                excludesStrings: ["Download", "Downloading..."]
            )
        }
    }

    @Test("ServerSongRow renders partial BGM download warning")
    func testServerSongRowPartialBGMState() async throws {
        try await TestSetup.withTestSetup {
            let serverSong = SwiftUICoverageFixtures.makeServerSong(
                title: "Missing BGM",
                charts: [
                    SwiftUICoverageFixtures.makeServerChart(level: 48, filename: "bgm.dtx", size: 3_072)
                ],
                isDownloaded: true,
                hasBGM: true,
                bgmDownloaded: false,
                hasPreview: false,
                previewDownloaded: false
            )

            SwiftUITestUtilities.assertView(
                ServerSongRow(serverSong: serverSong, isLoading: false, onDownload: {}),
                containsStrings: ["Missing BGM", "Charts", "BGM"]
            )
        }
    }

    @Test("ServerSongRow renders partial preview download warning")
    func testServerSongRowPartialPreviewState() async throws {
        try await TestSetup.withTestSetup {
            let serverSong = SwiftUICoverageFixtures.makeServerSong(
                title: "Missing Preview",
                charts: [
                    SwiftUICoverageFixtures.makeServerChart(level: 52, filename: "preview.dtx", size: 4_096)
                ],
                isDownloaded: true,
                hasBGM: false,
                bgmDownloaded: false,
                hasPreview: true,
                previewDownloaded: false
            )

            SwiftUITestUtilities.assertView(
                ServerSongRow(serverSong: serverSong, isLoading: false, onDownload: {}),
                containsStrings: ["Missing Preview", "Charts", "Preview"]
            )
        }
    }

    @Test("LibraryView renders empty downloaded-song state")
    func testLibraryViewEmptyState() async throws {
        try await TestSetup.withTestSetup {
            SwiftUITestUtilities.assertView(
                LibraryView(songs: [], serverSongService: ServerSongService()),
                containsStrings: ["Downloaded Songs", "0 songs downloaded", "No Downloaded Songs", "Download songs from the server to see them here"]
            )
        }
    }

    @Test("LibraryView filters songs by DTX Import genre")
    func testLibraryViewFiltersByGenre() async throws {
        try await TestSetup.withTestSetup {
            let dtxSong1 = SwiftUICoverageFixtures.makeSong(
                title: "DTX Track One",
                genre: "DTX Import",
                charts: [SwiftUICoverageFixtures.makeChart(difficulty: .easy, level: 20)]
            )
            let dtxSong2 = SwiftUICoverageFixtures.makeSong(
                title: "DTX Track Two",
                genre: "DTX Import",
                charts: [SwiftUICoverageFixtures.makeChart(difficulty: .hard, level: 60)]
            )
            let rockSong = SwiftUICoverageFixtures.makeSong(title: "Rock Anthem", genre: "Rock")
            let popSong = SwiftUICoverageFixtures.makeSong(title: "Pop Hit", genre: "Pop")

            let allSongs = [dtxSong1, dtxSong2, rockSong, popSong]

            let filtered = allSongs.filter { $0.genre == "DTX Import" }
            #expect(filtered.count == 2)
            #expect(filtered.allSatisfy { $0.genre == "DTX Import" })
            let filteredTitles = Set(filtered.map(\.title))
            #expect(filteredTitles == ["DTX Track One", "DTX Track Two"])
            #expect(!filtered.contains { $0.genre == "Rock" || $0.genre == "Pop" })

            SwiftUITestUtilities.assertView(
                LibraryView(songs: allSongs, serverSongService: ServerSongService()),
                containsStrings: ["Downloaded Songs", "2 songs downloaded"],
                excludesStrings: ["No Downloaded Songs"]
            )
        }
    }

    @Test("LibraryView header reflects populated downloaded songs count")
    func testLibraryViewPopulatedState() async throws {
        try await TestSetup.withTestSetup {
            let downloadedSong = SwiftUICoverageFixtures.makeSong(
                title: "Stored Groove",
                genre: "DTX Import",
                charts: [
                    SwiftUICoverageFixtures.makeChart(
                        difficulty: .easy,
                        level: 25,
                        notes: [SwiftUICoverageFixtures.makeNote(measureNumber: 1)]
                    ),
                    SwiftUICoverageFixtures.makeChart(
                        difficulty: .hard,
                        level: 65,
                        notes: [SwiftUICoverageFixtures.makeNote(noteType: .snare, measureNumber: 2)]
                    )
                ]
            )
            let nonDownloadedSong = SwiftUICoverageFixtures.makeSong(title: "Streaming Only", genre: "Rock")
            let allSongs = [downloadedSong, nonDownloadedSong]

            let downloadedSongs = allSongs.filter { $0.genre == "DTX Import" }
            #expect(downloadedSongs.count == 1)
            #expect(downloadedSongs.first?.title == "Stored Groove")
            #expect(!downloadedSongs.contains { $0.title == "Streaming Only" })

            SwiftUITestUtilities.assertView(
                LibraryView(songs: allSongs, serverSongService: ServerSongService()),
                containsStrings: ["Downloaded Songs", "1 songs downloaded"],
                excludesStrings: ["No Downloaded Songs"]
            )
        }
    }

    @Test("SavedSongRow renders deleting progress state")
    func testSavedSongRowDeletingState() async throws {
        try await TestSetup.withTestSetup {
            let song = SwiftUICoverageFixtures.makeSong(
                title: "Deleting Song",
                genre: "DTX Import",
                charts: [
                    SwiftUICoverageFixtures.makeChart(difficulty: .medium, level: 40)
                ]
            )

            SwiftUITestUtilities.assertView(
                SavedSongRow(song: song, isDeleting: true, onDelete: {}),
                containsStrings: ["Deleting Song", "Deleting..."],
                excludesStrings: ["Delete"]
            )
        }
    }

    @Test("SavedSongRow hides delete button when onDelete is nil")
    func testSavedSongRowNoDeleteFallback() async throws {
        try await TestSetup.withTestSetup {
            let song = SwiftUICoverageFixtures.makeSong(
                title: "Read Only Song",
                genre: "DTX Import",
                charts: [
                    SwiftUICoverageFixtures.makeChart(difficulty: .expert, level: 90)
                ]
            )

            SwiftUITestUtilities.assertView(
                SavedSongRow(song: song, isDeleting: false, onDelete: nil),
                containsStrings: ["Read Only Song"],
                excludesStrings: ["Deleting...", "Delete"]
            )
        }
    }
}
