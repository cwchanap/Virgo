import Testing
import SwiftData
import Foundation
@testable import Virgo

@Suite("ServerSong Catalog Refresh Tests", .serialized)
@MainActor
struct ServerSongCatalogRefreshTests {

    /// SimfileFetcher that returns an empty page after the first page, simulating
    /// a transient truncation despite a non-zero totalCount.
    private final class TruncatingFetcher: SimfileFetching, @unchecked Sendable {
        let all: [SimfileDTO]
        let pageSize: Int
        init(all: [SimfileDTO], pageSize: Int) { self.all = all; self.pageSize = pageSize }
        func fetchSimfiles(page: Int, pageSize: Int, search: String?) async throws -> SimfilePage {
            if page == 1 {
                return SimfilePage(simfiles: Array(all.prefix(self.pageSize)), totalCount: all.count)
            }
            return SimfilePage(simfiles: [], totalCount: all.count)
        }
        func fetchSimfile(id: String) async throws -> SimfileDTO? { all.first { $0.id == id } }
    }

    @Test("Inserts new simfiles on refresh")
    func testInsertsNew() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let fetcher = MockSimfileFetcher(all: [.stub(id: "a"), .stub(id: "b")])
            let cache = ServerSongCache(fetcher: fetcher, pageSize: 1)

            try await cache.refreshCatalog(modelContext: context)

            let songs = try context.fetch(FetchDescriptor<ServerSong>())
            #expect(Set(songs.map(\.songId)) == ["a", "b"])
            #expect(fetcher.fetchSimfilesCallCount >= 2) // paged at size 1
        }
    }

    @Test("Leaves existing ids untouched and prunes stale ids")
    func testAdditiveAndPrune() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
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

    @Test("Does NOT prune when page-walk is truncated (empty page before totalCount)")
    func testNoPruneOnTruncatedWalk() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            // Seed two songs; the fetcher will only return "a" on page 1 then an
            // empty page 2 (truncation). "z" must NOT be pruned.
            let songA = ServerSong(songId: "a", title: "A", artist: "X", bpm: 120)
            let songZ = ServerSong(songId: "z", title: "Z", artist: "X", bpm: 120)
            context.insert(songA); context.insert(songZ)
            try context.save()

            let fetcher = TruncatingFetcher(all: [.stub(id: "a"), .stub(id: "b")], pageSize: 1)
            let cache = ServerSongCache(fetcher: fetcher, pageSize: 1)
            try await cache.refreshCatalog(modelContext: context)

            let songs = try context.fetch(FetchDescriptor<ServerSong>())
            let ids = Set(songs.map(\.songId))
            // "z" survives because the walk was incomplete; "b" was inserted from page 1.
            #expect(ids.contains("z"), "Stale song must survive truncated walk")
        }
    }

    @Test("Propagates fetch errors from refreshCatalog")
    func testRefreshCatalogThrowsOnFetchError() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let fetcher = MockSimfileFetcher(all: [])
            fetcher.error = URLError(.notConnectedToInternet)
            let cache = ServerSongCache(fetcher: fetcher, pageSize: 10)

            await #expect(throws: Error.self) {
                try await cache.refreshCatalog(modelContext: context)
            }
        }
    }
}
