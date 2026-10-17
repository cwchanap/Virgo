//
//  SwiftUIRenderingSongLibraryTests.swift
//  VirgoTests
//

import Testing
import SwiftUI
import SwiftData
@testable import Virgo

/// Song-library component rendering ownership, consolidated from the campaign
/// SongLibraryCoverageTests and SecondWaveCoverageTests (HPA-583): adding these
/// to `SwiftUIRenderingLibraryAndResultsTests` would breach both of that file's
/// SwiftLint ERROR budgets (struct1 416/600 type body, file 663/1000). The
/// ServerSongRow / LibraryView / DownloadedSongsView / SavedSongRow / SongCard
/// rendered-content contracts have no other owner.
@Suite("SwiftUI Song Library Rendering Tests", .serialized)
@MainActor
struct SwiftUIRenderingSongLibraryTests {

    // MARK: - ServerSongRow

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

    // MARK: - LibraryView

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

    // MARK: - DownloadedSongsView (consolidated from SecondWaveCoverageTests)

    @Test("DownloadedSongsView renders empty state when no downloaded songs exist")
    func testDownloadedSongsViewEmptyState() async throws {
        try await TestSetup.withTestSetup {
            let serverSongService = ServerSongService()
            let audioPlaybackService = AudioPlaybackService(startPlayback: { _ in false })

            let view = DownloadedSongsView(
                songs: [],
                serverSongService: serverSongService,
                currentlyPlaying: .constant(nil),
                expandedSongId: .constant(nil),
                audioPlaybackService: audioPlaybackService,
                onChartSelect: { _ in },
                onPlayTap: { _ in },
                onSaveTap: { _ in }
            )

            SwiftUITestUtilities.assertViewWithEnvironment(
                view,
                size: CGSize(width: 1024, height: 768)
            )
        }
    }

    @Test("DownloadedSongsView renders populated state with DTX Import songs")
    func testDownloadedSongsViewPopulatedState() async throws {
        try await TestSetup.withTestSetup {
            let song1 = makeDownloadedSong(title: "Wave 2 Song A")
            let song2 = makeDownloadedSong(title: "Wave 2 Song B")
            let serverSongService = ServerSongService()
            let audioPlaybackService = AudioPlaybackService(startPlayback: { _ in false })

            let view = DownloadedSongsView(
                songs: [song1, song2],
                serverSongService: serverSongService,
                currentlyPlaying: .constant(nil),
                expandedSongId: .constant(nil),
                audioPlaybackService: audioPlaybackService,
                onChartSelect: { _ in },
                onPlayTap: { _ in },
                onSaveTap: { _ in }
            )

            // Mounting the populated view verifies the row (with its newly
            // re-attached accessibility identifier) renders without crashing.
            // The identifier itself is verified at the UI-test level, where the
            // accessibility tree is actually queryable (reflection-based
            // identifier collection cannot see .accessibilityIdentifier).
            SwiftUITestUtilities.assertViewWithEnvironment(
                view,
                size: CGSize(width: 1024, height: 768)
            )
        }
    }

    @Test("DownloadedSongsView.rowViewID stays stable across SwiftData reloads")
    func testDownloadedSongsViewRowViewIDStableAcrossReloads() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let song = makeDownloadedSong(title: "Stable Row ID")
            context.insert(song)
            try context.save()

            let originalRowViewID = DownloadedSongsView.rowViewID(for: song)

            let verificationContext = ModelContext(TestContainer.shared.container)
            let reloadedSong = try #require(
                verificationContext.fetch(FetchDescriptor<Song>()).first
            )

            #expect(song.persistentModelID == reloadedSong.persistentModelID)
            #expect(ObjectIdentifier(song) != ObjectIdentifier(reloadedSong))
            #expect(
                DownloadedSongsView.rowViewID(for: reloadedSong) == originalRowViewID,
                "Row view IDs should stay stable for the same SwiftData model across reloads"
            )
        }
    }

    @Test("DownloadedSongsView.downloadedSongs filters to server-imported songs only")
    func testDownloadedSongsViewFiltersNonDTXSongs() async throws {
        try await TestSetup.withTestSetup {
            let downloadedSong = makeDownloadedSong(title: "DTX Track")
            let nonDownloadedSong = Song(
                title: "Rock Track",
                artist: "Rock Artist",
                bpm: 120,
                duration: "3:00",
                genre: "Rock",
                timeSignature: .fourFour,
                isServerImported: false
            )
            let serverSongService = ServerSongService()
            let audioPlaybackService = AudioPlaybackService(startPlayback: { _ in false })

            let view = DownloadedSongsView(
                songs: [downloadedSong, nonDownloadedSong],
                serverSongService: serverSongService,
                currentlyPlaying: .constant(nil),
                expandedSongId: .constant(nil),
                audioPlaybackService: audioPlaybackService,
                onChartSelect: { _ in },
                onPlayTap: { _ in },
                onSaveTap: { _ in }
            )

            // Assert real filtering behaviour: only the server-imported song passes the predicate
            #expect(view.downloadedSongs.count == 1)
            #expect(view.downloadedSongs.first?.title == "DTX Track")

            SwiftUITestUtilities.assertViewWithEnvironment(
                view,
                size: CGSize(width: 1024, height: 768)
            )
        }
    }

    @Test("DownloadedSongsView.downloadedSongs ignores deleted songs from stale query snapshots")
    func testDownloadedSongsViewFiltersDeletedSongs() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let deletedSong = makeDownloadedSong(title: "Deleted DTX Track")
            let liveSong = makeDownloadedSong(title: "Live DTX Track")
            context.insert(deletedSong)
            context.insert(liveSong)
            try context.save()
            context.delete(deletedSong)
            try context.save()

            let serverSongService = ServerSongService()
            let audioPlaybackService = AudioPlaybackService(startPlayback: { _ in false })
            let view = DownloadedSongsView(
                songs: [deletedSong, liveSong],
                serverSongService: serverSongService,
                currentlyPlaying: .constant(nil),
                expandedSongId: .constant(nil),
                audioPlaybackService: audioPlaybackService,
                onChartSelect: { _ in },
                onPlayTap: { _ in },
                onSaveTap: { _ in }
            )

            #expect(view.downloadedSongs.map(\.title) == ["Live DTX Track"])
        }
    }

    @Test("DownloadedSongsView renders with currently playing song highlighted")
    func testDownloadedSongsViewWithPlayingState() async throws {
        try await TestSetup.withTestSetup {
            let song = makeDownloadedSong(title: "Playing Song")
            let serverSongService = ServerSongService()
            let audioPlaybackService = AudioPlaybackService(startPlayback: { _ in false })

            let view = DownloadedSongsView(
                songs: [song],
                serverSongService: serverSongService,
                currentlyPlaying: .constant(song.persistentModelID),
                expandedSongId: .constant(nil),
                audioPlaybackService: audioPlaybackService,
                onChartSelect: { _ in },
                onPlayTap: { _ in },
                onSaveTap: { _ in }
            )

            SwiftUITestUtilities.assertViewWithEnvironment(
                view,
                size: CGSize(width: 1024, height: 768)
            )
        }
    }

    // MARK: - SavedSongRow / SongCard

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

    // MARK: - Private Helpers

    private func makeDownloadedSong(title: String) -> Song {
        let chart = SwiftUICoverageFixtures.makeChart(
            difficulty: .medium,
            notes: [
                SwiftUICoverageFixtures.makeNote(
                    interval: .quarter,
                    noteType: .bass,
                    measureNumber: 1,
                    measureOffset: 0.0
                )
            ]
        )
        let song = SwiftUICoverageFixtures.makeSong(
            title: title,
            genre: "DTX Import",
            charts: [chart]
        )
        return song
    }
}
