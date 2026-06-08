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

    @Test("Backfills empty fileURL on legacy charts without clobbering user state")
    func testBackfillLegacyChartURLs() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            // Seed a legacy "a" entry: downloaded, with a chart whose fileURL
            // predated the column (""), as SwiftData lightweight migration would
            // produce for REST-catalog upgraders.
            let legacyChart = ServerChart(
                difficulty: "basic",
                difficultyLabel: "BASIC",
                level: 30,
                filename: "bas.dtx",
                size: 100,
                fileURL: "",
                fileEncoding: "SHIFT_JIS"
            )
            let legacy = ServerSong(
                songId: "a",
                title: "OLD TITLE",
                artist: "A",
                bpm: 120,
                charts: [legacyChart],
                isDownloaded: true
            )
            // Matching local Song so refreshDownloadStatus reconciles isDownloaded
            // to true (mirrors testAdditiveAndPrune); isolates the backfill check
            // from the download-status reconciliation path.
            let localSong = Song(title: "OLD TITLE", artist: "A", bpm: 120,
                                 duration: "3:30", genre: "DTX Import")
            context.insert(legacy); context.insert(legacyChart); context.insert(localSong)
            try context.save()

            let fetcher = MockSimfileFetcher(all: [.stub(id: "a", title: "NEW TITLE")])
            let cache = ServerSongCache(fetcher: fetcher, pageSize: 10)
            try await cache.refreshCatalog(modelContext: context)

            let songs = try context.fetch(FetchDescriptor<ServerSong>())
            let songA = try #require(songs.first { $0.songId == "a" })
            // fileURL backfilled from the DTO (download would otherwise throw invalidChartURL).
            #expect(songA.charts.first?.fileURL == "https://r2/a/bas.dtx")
            #expect(songA.charts.first?.fileEncoding == "SHIFT_JIS")
            // Additive contract preserved: existing entry not replaced.
            #expect(songA.title == "OLD TITLE")
            #expect(songA.isDownloaded == true)
        }
    }

    @Test("Backfills fileEncoding alongside fileURL when DTO differs")
    func testBackfillLegacyChartEncoding() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            // Legacy chart carries the migration default ("SHIFT_JIS"); the DTO
            // reports UTF_8. Backfill must correct both fileURL and fileEncoding.
            let legacyChart = ServerChart(
                difficulty: "basic", difficultyLabel: "BASIC", level: 30,
                filename: "bas.dtx", size: 100, fileURL: "", fileEncoding: "SHIFT_JIS"
            )
            let legacy = ServerSong(
                songId: "a", title: "OLD", artist: "A", bpm: 120,
                charts: [legacyChart], isDownloaded: false
            )
            context.insert(legacy); context.insert(legacyChart)
            try context.save()

            let fetcher = MockSimfileFetcher(all: [.stub(id: "a", encoding: .utf8)])
            let cache = ServerSongCache(fetcher: fetcher, pageSize: 10)
            try await cache.refreshCatalog(modelContext: context)

            let songA = try context.fetch(FetchDescriptor<ServerSong>()).first { $0.songId == "a" }
            let chart = try #require(songA?.charts.first)
            #expect(chart.fileURL == "https://r2/a/bas.dtx")
            #expect(chart.fileEncoding == "UTF_8")
        }
    }

    @Test("Leaves charts with a fileURL untouched (no double-backfill)")
    func testNoBackfillWhenFileURLPresent() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let chart = ServerChart(
                difficulty: "basic", difficultyLabel: "BASIC", level: 30,
                filename: "bas.dtx", size: 100,
                fileURL: "https://example/legacy.dtx", fileEncoding: "SHIFT_JIS"
            )
            let song = ServerSong(
                songId: "a", title: "OLD", artist: "A", bpm: 120, charts: [chart]
            )
            context.insert(song); context.insert(chart)
            try context.save()

            let fetcher = MockSimfileFetcher(all: [.stub(id: "a")])
            let cache = ServerSongCache(fetcher: fetcher, pageSize: 10)
            try await cache.refreshCatalog(modelContext: context)

            let songA = try context.fetch(FetchDescriptor<ServerSong>()).first { $0.songId == "a" }
            // Non-empty fileURL is preserved — backfill must not overwrite it.
            #expect(songA?.charts.first?.fileURL == "https://example/legacy.dtx")
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
