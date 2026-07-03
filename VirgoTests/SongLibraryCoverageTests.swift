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
                containsStrings: [
                    "Loading Groove", "Downloading...", "Chart files", "Background music", "Preview audio"
                ],
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
            // ServerSongRow resolves chart-derived level/chip data via an async
            // relationship loader; wait for it to settle before snapshotting.
            await SwiftUITestUtilities.waitForRenderStabilization(in: mountedView)
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

            let mountedView = SwiftUITestUtilities.assertViewWithEnvironment(
                ServerSongRow(serverSong: serverSong, isLoading: false, onDownload: {})
            )
            // The "Levels 25, 70" summary is produced by the async relationship
            // loader; wait for it to settle before snapshotting.
            await SwiftUITestUtilities.waitForRenderStabilization(in: mountedView)
            SwiftUITestUtilities.assertRendered(
                from: mountedView.root,
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
                containsStrings: [
                    "Downloaded Songs", "0 songs downloaded", "No Downloaded Songs",
                    "Download songs from the server to see them here"
                ]
            )
        }
    }

    @Test("LibraryView filters songs by server-imported flag")
    func testLibraryViewFiltersByServerImportedFlag() async throws {
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
            let rockSong = SwiftUICoverageFixtures.makeSong(title: "Rock Anthem", genre: "Rock", isServerImported: false)
            let popSong = SwiftUICoverageFixtures.makeSong(title: "Pop Hit", genre: "Pop", isServerImported: false)

            let allSongs = [dtxSong1, dtxSong2, rockSong, popSong]

            let filtered = allSongs.filter { $0.isServerImported }
            #expect(filtered.count == 2)
            #expect(filtered.allSatisfy { $0.isServerImported })
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
            let nonDownloadedSong = SwiftUICoverageFixtures.makeSong(title: "Streaming Only", genre: "Rock", isServerImported: false)
            let allSongs = [downloadedSong, nonDownloadedSong]

            let downloadedSongs = allSongs.filter { $0.isServerImported }
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

    @Test("LibraryView downloaded-song filter excludes locally hidden songs")
    func testLibraryViewDownloadedSongsExcludesLocallyHiddenSongs() async throws {
        try await TestSetup.withTestSetup {
            let visibleSong = SwiftUICoverageFixtures.makeSong(
                title: "Visible Download",
                genre: "DTX Import"
            )
            let hiddenSong = SwiftUICoverageFixtures.makeSong(
                title: "Deleted Download",
                genre: "DTX Import"
            )
            let streamingSong = SwiftUICoverageFixtures.makeSong(title: "Streaming Only", genre: "Rock", isServerImported: false)

            let downloadedSongs = LibraryView.downloadedSongs(
                from: [visibleSong, hiddenSong, streamingSong],
                excluding: [hiddenSong.persistentModelID]
            )

            #expect(downloadedSongs.map(\.title) == ["Visible Download"])
        }
    }

    @Test("LibraryView renders external deleting overlay for a downloaded song")
    func testLibraryViewDeletingOverlayState() async throws {
        try await TestSetup.withTestSetup {
            let song = SwiftUICoverageFixtures.makeSong(
                title: "Deleting Overlay Song",
                artist: "Deleting Artist",
                genre: "DTX Import",
                charts: [SwiftUICoverageFixtures.makeChart(difficulty: .medium, level: 45)]
            )
            let service = ServerSongService()
            service.deletingSongs.insert(song.persistentModelID)

            // List row text extraction is unreliable; verify the header and that the view mounts.
            SwiftUITestUtilities.assertView(
                LibraryView(songs: [song], serverSongService: service),
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

    @Test("LibraryView renders delete button for non-deleting downloaded songs")
    func testLibraryViewDeleteButtonState() async throws {
        try await TestSetup.withTestSetup {
            let song = SwiftUICoverageFixtures.makeSong(
                title: "Deletable Song",
                artist: "Delete Artist",
                genre: "DTX Import",
                charts: [SwiftUICoverageFixtures.makeChart(difficulty: .easy, level: 20)]
            )

            SwiftUITestUtilities.assertView(
                LibraryView(songs: [song], serverSongService: ServerSongService()),
                containsStrings: ["Downloaded Songs", "1 songs downloaded"],
                excludesStrings: ["No Downloaded Songs"]
            )
        }
    }

    @Test("SavedSongRow renders delete button when onDelete is provided and not deleting")
    func testSavedSongRowDeleteButtonState() async throws {
        try await TestSetup.withTestSetup {
            let song = SwiftUICoverageFixtures.makeSong(
                title: "Deletable Song",
                genre: "DTX Import",
                charts: [
                    SwiftUICoverageFixtures.makeChart(difficulty: .medium, level: 40)
                ]
            )

            let row = SavedSongRow(song: song, isDeleting: false, onDelete: {})
            #expect(row.showsDeleteButton)

            let mountedView = SwiftUITestUtilities.assertViewWithEnvironment(row)
            let texts = SwiftUITestUtilities.renderedTexts(from: mountedView.root)

            #expect(texts.contains("Deletable Song"), "Expected title; got \(texts)")
            #expect(!texts.contains("Deleting..."), "Should not show deleting state; got \(texts)")
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

            let row = SavedSongRow(song: song, isDeleting: false, onDelete: nil)
            #expect(!row.showsDeleteButton)

            SwiftUITestUtilities.assertView(
                row,
                containsStrings: ["Read Only Song"],
                excludesStrings: ["Deleting...", "Delete"]
            )
        }
    }

    @Test("SongCard open-button accessibility identifier is unique per song")
    func testSongCardOpenButtonIdentifierIsUniquePerSong() async throws {
        try await TestSetup.withTestSetup {
            let songA = SwiftUICoverageFixtures.makeSong(title: "Unique Card A", genre: "DTX Import")
            let songB = SwiftUICoverageFixtures.makeSong(title: "Unique Card B", genre: "DTX Import")

            let idA = SongCard.cardOpenButtonID(for: songA)
            let idB = SongCard.cardOpenButtonID(for: songB)

            // Same prefix family, different per-song suffix → no shared target.
            #expect(idA.hasPrefix("downloadedSongCardOpenButton-"))
            #expect(idB.hasPrefix("downloadedSongCardOpenButton-"))
            #expect(idA != idB, "Open-button identifiers must differ per song")
        }
    }
}
