import Testing
import SwiftData
import Foundation
@testable import Virgo

@Suite("ServerSongCache Tests", .serialized)
@MainActor
struct ServerSongCacheTests {
    @Test("loadServerSongs returns non-stale cache and updates download statuses")
    func testLoadServerSongsUsesCacheAndUpdatesStatus() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let cache = ServerSongCache()

            let localMatch = Song(
                title: "Matched Song",
                artist: "Matched Artist",
                bpm: 120.0,
                duration: "3:00",
                genre: "DTX Import"
            )
            context.insert(localMatch)

            let matchedServerSong = ServerSong(
                songId: "matched-song",
                title: "Matched Song",
                artist: "Matched Artist",
                bpm: 120.0,
                isDownloaded: false
            )
            matchedServerSong.lastUpdated = Date()

            let unmatchedServerSong = ServerSong(
                songId: "unmatched-song",
                title: "Unmatched Song",
                artist: "Unmatched Artist",
                bpm: 100.0,
                isDownloaded: true
            )
            unmatchedServerSong.lastUpdated = Date().addingTimeInterval(-60)

            context.insert(matchedServerSong)
            context.insert(unmatchedServerSong)
            try context.save()

            let loadedSongs = try await cache.loadServerSongs(modelContext: context)

            #expect(loadedSongs.count == 2)
            #expect(loadedSongs.first?.songId == "matched-song") // Most recently updated first
            #expect(matchedServerSong.isDownloaded == true)
            #expect(unmatchedServerSong.isDownloaded == false)
        }
    }

    @Test("loadServerSongs keeps existing statuses when no local songs exist")
    func testLoadServerSongsRetainsUndownloadedStatusWithoutMatches() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let cache = ServerSongCache()

            let serverSong = ServerSong(
                songId: "cache-only",
                title: "Cache Only",
                artist: "No Local Match",
                bpm: 128.0,
                isDownloaded: false
            )
            serverSong.lastUpdated = Date()

            context.insert(serverSong)
            try context.save()

            let loadedSongs = try await cache.loadServerSongs(modelContext: context)

            #expect(loadedSongs.count == 1)
            #expect(loadedSongs.first?.songId == "cache-only")
            #expect(serverSong.isDownloaded == false)
        }
    }
}
