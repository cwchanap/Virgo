import Testing
import SwiftData
import Foundation
@testable import Virgo

@Suite("ServerSong Catalog Refresh Tests", .serialized)
@MainActor
struct ServerSongCatalogRefreshTests {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([ServerSong.self, ServerChart.self, Song.self, Chart.self, Note.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    @Test("Inserts new simfiles on refresh")
    func testInsertsNew() async throws {
        let context = try makeContext()
        let fetcher = MockSimfileFetcher(all: [.stub(id: "a"), .stub(id: "b")])
        let cache = ServerSongCache(fetcher: fetcher, pageSize: 1)

        try await cache.refreshCatalog(modelContext: context)

        let songs = try context.fetch(FetchDescriptor<ServerSong>())
        #expect(Set(songs.map(\.songId)) == ["a", "b"])
        #expect(fetcher.fetchSimfilesCallCount >= 2) // paged at size 1
    }

    @Test("Leaves existing ids untouched and prunes stale ids")
    func testAdditiveAndPrune() async throws {
        let context = try makeContext()
        // Seed an existing entry "a" (downloaded, with a matching local Song so the
        // download-status reconciliation keeps it downloaded) and a stale "z".
        let existing = ServerSong(songId: "a", title: "OLD", artist: "A", bpm: 120, isDownloaded: true)
        let localSong = Song(title: "OLD", artist: "A", bpm: 120, duration: "3:30", genre: "DTX Import")
        let stale = ServerSong(songId: "z", title: "Z", artist: "A", bpm: 120)
        context.insert(existing); context.insert(localSong); context.insert(stale)
        try context.save()

        let fetcher = MockSimfileFetcher(all: [.stub(id: "a", title: "NEW"), .stub(id: "b")])
        let cache = ServerSongCache(fetcher: fetcher, pageSize: 10)
        try await cache.refreshCatalog(modelContext: context)

        let songs = try context.fetch(FetchDescriptor<ServerSong>())
        let byId = Dictionary(uniqueKeysWithValues: songs.map { ($0.songId, $0) })
        #expect(Set(byId.keys) == ["a", "b"])            // z pruned, b added
        #expect(byId["a"]?.title == "OLD")               // existing NOT overwritten
        #expect(byId["a"]?.isDownloaded == true)
    }
}
