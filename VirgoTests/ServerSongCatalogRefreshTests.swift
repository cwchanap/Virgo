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
            let localSong = Song(title: "OLD", artist: "A", bpm: 120, duration: "3:30", genre: "DTX Import", isServerImported: true)
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
                                 duration: "3:30", genre: "DTX Import", isServerImported: true)
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

    @Test("Backfills legacy charts AND prunes stale entries in the same refresh without crash")
    func testBackfillAndPruneSameRefresh() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            // Song "a": legacy chart with empty fileURL — needs backfill.
            let legacyChart = ServerChart(
                difficulty: "basic", difficultyLabel: "BASIC", level: 30,
                filename: "bas.dtx", size: 100, fileURL: "", fileEncoding: "SHIFT_JIS"
            )
            let legacy = ServerSong(
                songId: "a", title: "LEGACY", artist: "A", bpm: 120,
                charts: [legacyChart], isDownloaded: false
            )
            // Song "z": stale — absent from server, will be pruned.
            let stale = ServerSong(songId: "z", title: "STALE", artist: "Z", bpm: 120)
            context.insert(legacy); context.insert(legacyChart); context.insert(stale)
            try context.save()

            // Server only returns "a"; "z" is stale and should be pruned.
            let fetcher = MockSimfileFetcher(all: [.stub(id: "a")])
            let cache = ServerSongCache(fetcher: fetcher, pageSize: 10)
            // Must not crash when backfilling "a" and pruning "z" in one pass.
            try await cache.refreshCatalog(modelContext: context)

            let songs = try context.fetch(FetchDescriptor<ServerSong>())
            let byId = Dictionary(uniqueKeysWithValues: songs.map { ($0.songId, $0) })
            #expect(Set(byId.keys) == ["a"], "Only 'a' should remain; 'z' pruned")
            let chart = try #require(byId["a"]?.charts.first)
            #expect(chart.fileURL == "https://r2/a/bas.dtx", "Legacy chart backfilled")
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

    @Test("Rolls back inserted songs when saveContext fails")
    func testRefreshCatalogRollsBackOnSaveFailure() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let fetcher = MockSimfileFetcher(all: [.stub(id: "a"), .stub(id: "b")])

            // saveContext always fails
            let cache = ServerSongCache(fetcher: fetcher, pageSize: 10) { _ in
                throw URLError(.cannotWriteToFile)
            }

            await #expect(throws: URLError.self) {
                try await cache.refreshCatalog(modelContext: context)
            }

            // After rollback, the context must not contain phantom unsaved inserts.
            // A fetch in the same context includes unsaved inserts, so if rollback
            // worked the result should be empty.
            let songs = try context.fetch(FetchDescriptor<ServerSong>())
            #expect(songs.isEmpty, "Context must be empty after rollback — no phantom inserts")
        }
    }

    @Test("Handles duplicate DTO IDs from server without crash")
    func testDuplicateDTOsDontCrash() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            // Simulate a server bug returning the same simfile on two pages.
            let fetcher = DuplicateIdFetcher(
                duplicates: [.stub(id: "a"), .stub(id: "a"), .stub(id: "b")],
                pageSize: 2
            )
            let cache = ServerSongCache(fetcher: fetcher, pageSize: 2)

            // Must not crash from uniqueKeysWithValues on duplicate keys
            try await cache.refreshCatalog(modelContext: context)

            let songs = try context.fetch(FetchDescriptor<ServerSong>())
            let ids = Set(songs.map(\.songId))
            // Only one entry per unique ID
            #expect(ids == ["a", "b"], "Duplicate DTOs must produce only one entry per unique ID")
            #expect(songs.count == 2, "Expected exactly 2 songs, got \(songs.count)")
        }
    }

    @Test("Handles duplicate DTO IDs in backfill without crash")
    func testDuplicateDTOsBackfillSafe() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            // Legacy chart with empty fileURL — needs backfill
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

            // Server returns "a" twice — backfill must not crash on duplicate keys
            let fetcher = DuplicateIdFetcher(
                duplicates: [.stub(id: "a"), .stub(id: "a")],
                pageSize: 2
            )
            let cache = ServerSongCache(fetcher: fetcher, pageSize: 2)
            try await cache.refreshCatalog(modelContext: context)

            let songA = try context.fetch(FetchDescriptor<ServerSong>()).first { $0.songId == "a" }
            #expect(songA?.charts.first?.fileURL == "https://r2/a/bas.dtx", "Backfill must succeed despite duplicate DTOs")
        }
    }

    /// Fetcher that returns duplicate simfile IDs to simulate server pagination bugs.
    /// Returns all items in one page. `totalCount` is set to the **unique** count so
    /// the walk completes after one page (the server knows its own unique count).
    private final class DuplicateIdFetcher: SimfileFetching, @unchecked Sendable {
        let duplicates: [SimfileDTO]
        let pageSize: Int
        init(duplicates: [SimfileDTO], pageSize: Int) {
            self.duplicates = duplicates; self.pageSize = pageSize
        }
        func fetchSimfiles(page: Int, pageSize: Int, search: String?) async throws -> SimfilePage {
            let uniqueCount = Set(duplicates.map(\.id)).count
            return SimfilePage(simfiles: duplicates, totalCount: uniqueCount)
        }
        func fetchSimfile(id: String) async throws -> SimfileDTO? { duplicates.first { $0.id == id } }
    }

    /// Fetcher that returns duplicate IDs *across pages*, simulating a server bug
    /// where the same simfile appears on multiple pages. The raw result count
    /// reaches totalCount before all unique IDs are fetched.
    private final class CrossPageDuplicateFetcher: SimfileFetching, @unchecked Sendable {
        /// All unique DTOs the server knows about.
        let allUnique: [SimfileDTO]
        let pageSize: Int
        /// Total count reported by the server (unique count).
        let totalCount: Int

        init(allUnique: [SimfileDTO], pageSize: Int) {
            self.allUnique = allUnique
            self.pageSize = pageSize
            self.totalCount = allUnique.count
        }

        func fetchSimfiles(page: Int, pageSize: Int, search: String?) async throws -> SimfilePage {
            // Page 1: returns first pageSize items + one duplicate from the "next"
            // page to simulate a server pagination bug that duplicates entries.
            // Page 2: returns the remaining unique items.
            // Page 3+: empty.
            if page == 1 {
                let items = Array(allUnique.prefix(pageSize))
                // If there are more items, duplicate one from beyond the page boundary.
                if allUnique.count > pageSize {
                    var page = items
                    page.append(allUnique[pageSize]) // duplicate from "next page"
                    return SimfilePage(simfiles: page, totalCount: totalCount)
                }
                return SimfilePage(simfiles: items, totalCount: totalCount)
            } else if page == 2 {
                let remaining = Array(allUnique.dropFirst(pageSize))
                return SimfilePage(simfiles: remaining, totalCount: totalCount)
            }
            return SimfilePage(simfiles: [], totalCount: totalCount)
        }

        func fetchSimfile(id: String) async throws -> SimfileDTO? { allUnique.first { $0.id == id } }
    }

    @Test("Duplicate IDs across pages do not mark walk complete prematurely")
    func testCrossPageDuplicatesDoNotMarkCompleteEarly() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            // Seed existing songs for "a", "b", "c". All three should survive pruning.
            let songA = ServerSong(songId: "a", title: "A", artist: "X", bpm: 120)
            let songB = ServerSong(songId: "b", title: "B", artist: "X", bpm: 120)
            let songC = ServerSong(songId: "c", title: "C", artist: "X", bpm: 120)
            context.insert(songA); context.insert(songB); context.insert(songC)
            try context.save()

            // 3 unique items, pageSize 2. Page 1 returns [a, b, b(dup)] → raw=3,
            // unique=2. Old code: results.count(3) >= totalCount(3) → premature complete.
            // New code: seenIds.count(2) >= totalCount(3) → false, keeps paging.
            // Page 2 returns [c] → seenIds.count(3) >= totalCount(3) → complete.
            let fetcher = CrossPageDuplicateFetcher(
                allUnique: [.stub(id: "a"), .stub(id: "b"), .stub(id: "c")],
                pageSize: 2
            )
            let cache = ServerSongCache(fetcher: fetcher, pageSize: 2)
            try await cache.refreshCatalog(modelContext: context)

            let songs = try context.fetch(FetchDescriptor<ServerSong>())
            let ids = Set(songs.map(\.songId))
            // All three songs must survive — no premature pruning.
            #expect(ids == ["a", "b", "c"], "All unique IDs must survive when duplicates delay completion")
        }
    }

    @Test("loadServerSongs reconciles stale download status against local store")
    func testLoadServerSongsReconcilesDownloadStatus() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            // Seed a ServerSong marked as downloaded but with NO matching local Song
            // (simulating a local Song deleted outside this service path).
            let serverSong = ServerSong(
                songId: "orphan",
                title: "Orphan",
                artist: "X",
                bpm: 120,
                isDownloaded: true
            )
            context.insert(serverSong)
            try context.save()

            let fetcher = MockSimfileFetcher()
            let cache = ServerSongCache(fetcher: fetcher, pageSize: 10)

            let loaded = try await cache.loadServerSongs(modelContext: context)
            #expect(loaded.count == 1)
            // refreshDownloadStatus should have corrected the stale flag.
            #expect(loaded.first?.isDownloaded == false,
                    "Stale isDownloaded must be reconciled on load")
        }
    }
}
