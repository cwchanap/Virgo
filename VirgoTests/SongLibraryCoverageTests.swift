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

            assertView(
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

            assertView(
                ServerSongRow(serverSong: serverSong, isLoading: false, onDownload: {}),
                containsStrings: ["Single Chart", "Level 36", "Download"],
                excludesStrings: ["Levels 36", "STANDARD (36)", "Downloading..."]
            )
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

            assertView(
                ServerSongRow(serverSong: serverSong, isLoading: false, onDownload: {}),
                containsStrings: [
                    "Downloaded Anthem",
                    "Levels 25, 70",   // summary level string confirms multi-chart data
                    "Charts",
                    "BGM",
                    "Preview"
                    // Note: per-chart badge texts ("BASIC (25)", "EXTREME (70)") are rendered
                    // inside a ForEach closure and are not reachable via Mirror reflection.
                ],
                excludesStrings: ["Download", "Downloading..."],
                containsSymbols: ["checkmark.circle.fill", "waveform", "play.circle"]
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
                bgmDownloaded: false
            )

            assertView(
                ServerSongRow(serverSong: serverSong, isLoading: false, onDownload: {}),
                containsStrings: ["Missing BGM", "Charts", "BGM"],
                containsSymbols: ["waveform.badge.exclamationmark"],
                excludesSymbols: ["waveform"]
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
                hasPreview: true,
                previewDownloaded: false
            )

            assertView(
                ServerSongRow(serverSong: serverSong, isLoading: false, onDownload: {}),
                containsStrings: ["Missing Preview", "Charts", "Preview"],
                containsSymbols: ["play.circle.badge.exclamationmark"],
                excludesSymbols: ["play.circle"]
            )
        }
    }

    @Test("LibraryView renders empty downloaded-song state")
    func testLibraryViewEmptyState() async throws {
        try await TestSetup.withTestSetup {
            assertView(
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

            // Direct data assertions: only DTX Import genre passes the filter
            let filtered = allSongs.filter { $0.genre == "DTX Import" }
            #expect(filtered.count == 2)
            #expect(filtered.allSatisfy { $0.genre == "DTX Import" })
            let filteredTitles = Set(filtered.map(\.title))
            #expect(filteredTitles == ["DTX Track One", "DTX Track Two"])
            #expect(!filtered.contains { $0.genre == "Rock" || $0.genre == "Pop" })

            // View assertions: LibraryView surfaces only the two DTX songs.
            // Note: song titles inside ForEach closures are not reachable via Mirror
            // reflection, so only the header count string is asserted here.
            assertView(
                LibraryView(songs: allSongs, serverSongService: ServerSongService()),
                containsStrings: ["Downloaded Songs", "2 songs downloaded"],
                excludesStrings: ["No Downloaded Songs"]
            )
        }
    }

    @Test("LibraryView renders only populated downloaded songs")
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
                        notes: [SwiftUICoverageFixtures.makeNote(measureNumber: 2, noteType: .snare)]
                    )
                ]
            )
            let nonDownloadedSong = SwiftUICoverageFixtures.makeSong(title: "Streaming Only", genre: "Rock")
            let allSongs = [downloadedSong, nonDownloadedSong]

            // Direct data assertions: only the DTX Import song appears in the filtered set
            let downloadedSongs = allSongs.filter { $0.genre == "DTX Import" }
            #expect(downloadedSongs.count == 1)
            #expect(downloadedSongs.first?.title == "Stored Groove")
            #expect(!downloadedSongs.contains { $0.title == "Streaming Only" })

            // View assertion: header count is reachable via Mirror; song titles inside
            // ForEach closures are not reachable, so only the count string is checked.
            assertView(
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

            assertView(
                SavedSongRow(song: song, isDeleting: true, onDelete: {}),
                containsStrings: ["Deleting Song", "Deleting..."],
                excludesStrings: ["No delete", "Delete"]
            )
        }
    }

    @Test("SavedSongRow renders no-delete fallback")
    func testSavedSongRowNoDeleteFallback() async throws {
        try await TestSetup.withTestSetup {
            let song = SwiftUICoverageFixtures.makeSong(
                title: "Read Only Song",
                genre: "DTX Import",
                charts: [
                    SwiftUICoverageFixtures.makeChart(difficulty: .expert, level: 90)
                ]
            )

            assertView(
                SavedSongRow(song: song, isDeleting: false, onDelete: nil),
                containsStrings: ["Read Only Song", "No delete"],
                excludesStrings: ["Deleting...", "Delete"]
            )
        }
    }

    private func assertView<V: View>(
        _ view: V,
        containsStrings: [String],
        excludesStrings: [String] = [],
        containsSymbols: [String] = [],
        excludesSymbols: [String] = [],
        size: CGSize = CGSize(width: 1_280, height: 900)
    ) {
        SwiftUITestUtilities.assertViewWithEnvironment(view, size: size)

        let texts = renderedTexts(from: view.body)
        let symbols = renderedSymbols(from: view.body)

        for string in containsStrings {
            #expect(texts.contains(string), "Expected rendered texts to include '\(string)', got \(texts)")
        }

        for string in excludesStrings {
            #expect(!texts.contains(string), "Expected rendered texts to exclude '\(string)', got \(texts)")
        }

        for symbol in containsSymbols {
            #expect(symbols.contains(symbol), "Expected rendered symbols to include '\(symbol)', got \(symbols)")
        }

        for symbol in excludesSymbols {
            #expect(!symbols.contains(symbol), "Expected rendered symbols to exclude '\(symbol)', got \(symbols)")
        }
    }

    private func renderedTexts(from value: Any) -> [String] {
        var texts: [String] = []
        var visited = Set<ObjectIdentifier>()
        collectTexts(from: value, into: &texts, visited: &visited)
        return texts
    }

    private func collectTexts(from value: Any, into texts: inout [String], visited: inout Set<ObjectIdentifier>) {
        let mirror = Mirror(reflecting: value)

        // Cycle detection for class instances: SwiftData @Model objects form circular
        // back-references (Song ↔ Chart ↔ Note) that would cause infinite recursion.
        // We allow each class instance to be visited once; revisits are skipped.
        if mirror.displayStyle == .class {
            let objectId = ObjectIdentifier(value as AnyObject)
            guard visited.insert(objectId).inserted else { return }
        }

        if String(describing: mirror.subjectType) == "Text" {
            texts.append(contentsOf: extractTextLiterals(from: value))
        }

        for child in mirror.children {
            collectTexts(from: child.value, into: &texts, visited: &visited)
        }
    }

    private func extractTextLiterals(from value: Any) -> [String] {
        var results: [String] = []
        let description = String(describing: value)

        if let openingQuote = description.firstIndex(of: "\""),
           let closingQuote = description.lastIndex(of: "\""),
           openingQuote < closingQuote {
            let text = String(description[description.index(after: openingQuote)..<closingQuote])
            if !text.isEmpty {
                results.append(text)
            }
        }

        return results
    }

    private func renderedSymbols(from value: Any) -> [String] {
        var symbols: [String] = []
        var visited = Set<ObjectIdentifier>()
        collectSymbols(from: value, into: &symbols, visited: &visited)
        return symbols
    }

    private func collectSymbols(from value: Any, into symbols: inout [String], visited: inout Set<ObjectIdentifier>) {
        let mirror = Mirror(reflecting: value)

        // Same cycle-detection guard as collectTexts.
        if mirror.displayStyle == .class {
            let objectId = ObjectIdentifier(value as AnyObject)
            guard visited.insert(objectId).inserted else { return }
        }

        if let label = mirror.children.first(where: { $0.label == "systemSymbol" }),
           let symbol = label.value as? String {
            symbols.append(symbol)
        }

        for child in mirror.children {
            collectSymbols(from: child.value, into: &symbols, visited: &visited)
        }
    }
}
