//
//  SongsTabCoverageTests.swift
//  VirgoTests
//

import Testing
import SwiftUI
@testable import Virgo

@Suite("SongsTabView Coverage Tests", .serialized)
@MainActor
struct SongsTabCoverageTests {

    // MARK: - Helpers

    private func makeSUT(
        allSongs: [Song] = [],
        serverSongs: [ServerSong] = [],
        searchText: String = ""
    ) -> SongsTabView {
        var search = searchText
        let binding = Binding(get: { search }, set: { search = $0 })
        return SongsTabView(
            allSongs: allSongs,
            serverSongs: serverSongs,
            serverSongService: ServerSongService(),
            searchText: binding,
            currentlyPlaying: .constant(nil),
            expandedSongId: .constant(nil),
            selectedChart: .constant(nil),
            navigateToGameplay: .constant(false),
            audioPlaybackService: AudioPlaybackService(startPlayback: { _ in false }),
            onPlayTap: { _ in },
            onSaveTap: { _ in }
        )
    }

    // MARK: - songs filtering

    @Test("songs returns all songs when searchText is empty")
    func testSongsReturnsAllWhenSearchEmpty() async throws {
        try await TestSetup.withTestSetup {
            let song1 = SwiftUICoverageFixtures.makeSong(title: "Alpha", artist: "Artist A")
            let song2 = SwiftUICoverageFixtures.makeSong(title: "Beta", artist: "Artist B")
            let sut = makeSUT(allSongs: [song1, song2], searchText: "")
            #expect(sut.songs.count == 2)
        }
    }

    @Test("songs filters by title match")
    func testSongsFiltersByTitle() async throws {
        try await TestSetup.withTestSetup {
            let song1 = SwiftUICoverageFixtures.makeSong(title: "Alpha Groove", artist: "Artist A")
            let song2 = SwiftUICoverageFixtures.makeSong(title: "Beta Blast", artist: "Artist B")
            let song3 = SwiftUICoverageFixtures.makeSong(title: "Alpha Night", artist: "Artist C")
            let sut = makeSUT(allSongs: [song1, song2, song3], searchText: "alpha")
            #expect(sut.songs.count == 2)
            #expect(sut.songs.allSatisfy { $0.title.lowercased().contains("alpha") })
        }
    }

    @Test("songs filters by artist match")
    func testSongsFiltersByArtist() async throws {
        try await TestSetup.withTestSetup {
            let song1 = SwiftUICoverageFixtures.makeSong(title: "Track 1", artist: "Neon Dreams")
            let song2 = SwiftUICoverageFixtures.makeSong(title: "Track 2", artist: "Pixel Beats")
            let sut = makeSUT(allSongs: [song1, song2], searchText: "Neon")
            #expect(sut.songs.count == 1)
            #expect(sut.songs.first?.artist == "Neon Dreams")
        }
    }

    @Test("songs returns empty when no title or artist match")
    func testSongsReturnsEmptyForNoMatch() async throws {
        try await TestSetup.withTestSetup {
            let song1 = SwiftUICoverageFixtures.makeSong(title: "Groove", artist: "Artist A")
            let sut = makeSUT(allSongs: [song1], searchText: "zzz-no-match")
            #expect(sut.songs.isEmpty)
        }
    }

    @Test("songs is case-insensitive")
    func testSongsCaseInsensitive() async throws {
        try await TestSetup.withTestSetup {
            let song = SwiftUICoverageFixtures.makeSong(title: "CaseSong", artist: "CaseArtist")
            let sut = makeSUT(allSongs: [song], searchText: "CASESONG")
            #expect(sut.songs.count == 1)
        }
    }

    // MARK: - filteredServerSongs filtering

    @Test("filteredServerSongs returns all when searchText is empty")
    func testFilteredServerSongsReturnsAllWhenEmpty() async throws {
        try await TestSetup.withTestSetup {
            let s1 = SwiftUICoverageFixtures.makeServerSong(title: "Server Alpha")
            let s2 = SwiftUICoverageFixtures.makeServerSong(title: "Server Beta")
            let sut = makeSUT(serverSongs: [s1, s2], searchText: "")
            #expect(sut.filteredServerSongs.count == 2)
        }
    }

    @Test("filteredServerSongs filters by server song title")
    func testFilteredServerSongsFiltersByTitle() async throws {
        try await TestSetup.withTestSetup {
            let s1 = SwiftUICoverageFixtures.makeServerSong(title: "Server Alpha")
            let s2 = SwiftUICoverageFixtures.makeServerSong(title: "Server Beta")
            let sut = makeSUT(serverSongs: [s1, s2], searchText: "alpha")
            #expect(sut.filteredServerSongs.count == 1)
            #expect(sut.filteredServerSongs.first?.title == "Server Alpha")
        }
    }

    @Test("filteredServerSongs filters by server song artist")
    func testFilteredServerSongsFiltersByArtist() async throws {
        try await TestSetup.withTestSetup {
            let s1 = SwiftUICoverageFixtures.makeServerSong(title: "Song A", artist: "CloudBand")
            let s2 = SwiftUICoverageFixtures.makeServerSong(title: "Song B", artist: "LocalCrew")
            let sut = makeSUT(serverSongs: [s1, s2], searchText: "CloudBand")
            #expect(sut.filteredServerSongs.count == 1)
            #expect(sut.filteredServerSongs.first?.artist == "CloudBand")
        }
    }

    @Test("filteredServerSongs returns empty for no match")
    func testFilteredServerSongsReturnsEmptyForNoMatch() async throws {
        try await TestSetup.withTestSetup {
            let s1 = SwiftUICoverageFixtures.makeServerSong(title: "Server Track")
            let sut = makeSUT(serverSongs: [s1], searchText: "zzz-no-match")
            #expect(sut.filteredServerSongs.isEmpty)
        }
    }

    @Test("filteredServerSongs is case-insensitive")
    func testFilteredServerSongsCaseInsensitive() async throws {
        try await TestSetup.withTestSetup {
            let s1 = SwiftUICoverageFixtures.makeServerSong(title: "ServerTitle", artist: "ServerArtist")
            let sut = makeSUT(serverSongs: [s1], searchText: "SERVERTITLE")
            #expect(sut.filteredServerSongs.count == 1)
        }
    }

    // MARK: - Render tests

    @Test("SongsTabView renders default downloaded-tab body with populated songs")
    func testSongsTabViewRendersDownloadedTab() async throws {
        try await TestSetup.withTestSetup {
            let song1 = SwiftUICoverageFixtures.makeSong(
                title: "Downloaded Hit",
                artist: "Local Artist",
                charts: [SwiftUICoverageFixtures.makeChart(difficulty: .medium, level: 50)]
            )
            let song2 = SwiftUICoverageFixtures.makeSong(
                title: "Downloaded Track 2",
                artist: "Local Artist 2"
            )
            let serverSong = SwiftUICoverageFixtures.makeServerSong(title: "Remote Track")

            let view = makeSUT(
                allSongs: [song1, song2],
                serverSongs: [serverSong],
                searchText: ""
            )

            SwiftUITestUtilities.assertViewWithEnvironment(
                view,
                size: CGSize(width: 1280, height: 900)
            )

            // Prove the default branch is the downloaded tab (selectedSubTab == 0):
            // With 2 downloaded songs and 1 server song, the count label is
            // "2 songs available" only when selectedSubTab == 0 is active.
            // Were selectedSubTab == 1 the default, the label would read "1 songs available".
            let texts = renderedTexts(from: view.body)
            #expect(
                texts.contains("2 songs available"),
                "Expected '2 songs available' proving the downloaded-tab (selectedSubTab==0) is the default; got \(texts)"
            )
        }
    }

    @Test("SongsTabView renders downloaded-tab body with active search filter")
    func testSongsTabViewRendersWithSearchFilter() async throws {
        try await TestSetup.withTestSetup {
            let matchingSong = SwiftUICoverageFixtures.makeSong(title: "Searchable Song", artist: "Test Artist")
            let nonMatchingSong = SwiftUICoverageFixtures.makeSong(title: "Other Song", artist: "Other Artist")

            let view = makeSUT(
                allSongs: [matchingSong, nonMatchingSong],
                serverSongs: [],
                searchText: "Searchable"
            )

            SwiftUITestUtilities.assertViewWithEnvironment(
                view,
                size: CGSize(width: 1280, height: 900)
            )
        }
    }

    @Test("SongsTabView renders empty downloaded-tab body")
    func testSongsTabViewRendersEmptyState() async throws {
        try await TestSetup.withTestSetup {
            let view = makeSUT(allSongs: [], serverSongs: [], searchText: "")

            SwiftUITestUtilities.assertViewWithEnvironment(
                view,
                size: CGSize(width: 1280, height: 900)
            )
        }
    }

    // MARK: - View body text helpers

    private func renderedTexts(from value: Any) -> [String] {
        var texts: [String] = []
        var visited = Set<ObjectIdentifier>()
        collectTexts(from: value, into: &texts, visited: &visited)
        return texts
    }

    private func collectTexts(from value: Any, into texts: inout [String], visited: inout Set<ObjectIdentifier>) {
        let mirror = Mirror(reflecting: value)

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
        let description = String(describing: value)
        guard let openingQuote = description.firstIndex(of: "\""),
              let closingQuote = description.lastIndex(of: "\""),
              openingQuote < closingQuote else { return [] }
        let text = String(description[description.index(after: openingQuote)..<closingQuote])
        return text.isEmpty ? [] : [text]
    }
}
