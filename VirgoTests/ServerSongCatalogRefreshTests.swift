import Testing
import SwiftData
import Foundation
@testable import Virgo

private struct ReplacementFixture {
    let changedAWithNewBPM: SimfileDTO
}

private func makeChangedAWithNewBPM() -> SimfileDTO {
    let base = SimfileDTO.stub(id: "a", title: "NEW")
    return SimfileDTO(
        id: base.id,
        title: base.title,
        artist: base.artist,
        bpm: 150,
        genre: base.genre,
        tags: base.tags,
        durationSeconds: base.durationSeconds,
        updatedAt: base.updatedAt,
        dtxFiles: [
            DtxFileDTO(
                label: "BASIC",
                level: 30,
                fileURL: "https://r2/a/new-bas.dtx",
                fileSizeBytes: 100,
                encoding: .shiftJIS
            )
        ],
        fileKeys: ["bgm.ogg", "preview.mp3"]
    )
}

private func seedReplacementFixture(into context: ModelContext) throws -> ReplacementFixture {
    let oldChart = ServerChart(
        difficulty: "basic",
        difficultyLabel: "BASIC",
        level: 30,
        filename: "old-bas.dtx",
        size: 100,
        fileURL: "https://r2/a/old-bas.dtx"
    )
    let existing = ServerSong(
        songId: "a",
        title: "OLD",
        artist: "A",
        bpm: 120,
        charts: [oldChart],
        isDownloaded: true,
        bgmDownloaded: true,
        previewDownloaded: true
    )
    let stale = ServerSong(songId: "z", title: "STALE", artist: "Z", bpm: 100)
    let localSong = Song(
        title: "Local A",
        artist: "A",
        bpm: 120,
        duration: "3:30",
        genre: "DTX Import",
        isServerImported: true,
        serverSongId: "a",
        bgmFilePath: "/tmp/a.ogg",
        previewFilePath: "/tmp/a.mp3"
    )
    context.insert(existing)
    context.insert(oldChart)
    context.insert(stale)
    context.insert(localSong)
    try context.save()

    return ReplacementFixture(changedAWithNewBPM: makeChangedAWithNewBPM())
}

@Suite("ServerSong Catalog Refresh Tests", .serialized)
@MainActor
struct ServerSongCatalogRefreshTests {

    /// SimfileFetcher that returns an empty page after the first page, simulating
    /// a transient truncation despite a non-zero totalCount.
    private final class TruncatingFetcher: SimfileFetching, @unchecked Sendable {
        let all: [SimfileDTO]
        let pageSize: Int

        init(all: [SimfileDTO], pageSize: Int) {
            self.all = all
            self.pageSize = pageSize
        }

        func fetchSimfiles(page: Int, pageSize: Int, search: String?) async throws -> SimfilePage {
            if page == 1 {
                return SimfilePage(simfiles: Array(all.prefix(self.pageSize)), totalCount: all.count)
            }
            return SimfilePage(simfiles: [], totalCount: all.count)
        }

        func fetchSimfile(id: String) async throws -> SimfileDTO? {
            all.first { $0.id == id }
        }
    }

    /// SimfileFetcher whose first page deterministically contains a duplicate ID.
    private final class DuplicateIDFetcher: SimfileFetching, @unchecked Sendable {
        let duplicateID: String

        init(duplicateID: String) {
            self.duplicateID = duplicateID
        }

        func fetchSimfiles(page: Int, pageSize: Int, search: String?) async throws -> SimfilePage {
            guard page == 1 else {
                return SimfilePage(simfiles: [], totalCount: 2)
            }
            let dto = SimfileDTO.stub(id: duplicateID)
            return SimfilePage(simfiles: [dto, dto], totalCount: 2)
        }

        func fetchSimfile(id: String) async throws -> SimfileDTO? {
            id == duplicateID ? .stub(id: duplicateID) : nil
        }
    }

    /// SimfileFetcher that changes totalCount on page 2 after a valid first page.
    private final class ChangingTotalCountFetcher: SimfileFetching, @unchecked Sendable {
        func fetchSimfiles(page: Int, pageSize: Int, search: String?) async throws -> SimfilePage {
            switch page {
            case 1:
                return SimfilePage(simfiles: [.stub(id: "a")], totalCount: 2)
            case 2:
                return SimfilePage(simfiles: [.stub(id: "b")], totalCount: 3)
            default:
                return SimfilePage(simfiles: [], totalCount: 3)
            }
        }

        func fetchSimfile(id: String) async throws -> SimfileDTO? {
            [.stub(id: "a"), .stub(id: "b")].first { $0.id == id }
        }
    }

    @MainActor
    private final class RecordingStatusManager: ServerSongStatusManager, @unchecked Sendable {
        private(set) var refreshDownloadStatusCallCount = 0

        override func refreshDownloadStatus(modelContext: ModelContext) async {
            refreshDownloadStatusCallCount += 1
        }
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

    @Test("Replaces the complete snapshot and preserves local imported songs")
    func testCompleteReplacementOverwritesMetadataAndPreservesLocalSong() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let fixture = try seedReplacementFixture(into: context)

            let fetcher = MockSimfileFetcher(all: [fixture.changedAWithNewBPM, .stub(id: "b")])
            let cache = ServerSongCache(fetcher: fetcher, pageSize: 10)

            try await cache.refreshCatalog(modelContext: context)

            let rows = try context.fetch(FetchDescriptor<ServerSong>())
            let byID = Dictionary(uniqueKeysWithValues: rows.map { ($0.songId, $0) })
            #expect(Set(byID.keys) == ["a", "b"])
            #expect(byID["a"]?.title == "NEW")
            #expect(byID["a"]?.bpm == 150)
            #expect(byID["a"]?.charts.first?.fileURL == "https://r2/a/new-bas.dtx")
            #expect(byID["a"]?.isDownloaded == true)
            #expect(byID["a"]?.bgmDownloaded == true)
            #expect(byID["a"]?.previewDownloaded == true)

            let local = try #require(
                context.fetch(FetchDescriptor<Song>())
                    .first { $0.serverSongId == "a" }
            )
            #expect(local.title == "Local A")
            #expect(local.bgmFilePath == "/tmp/a.ogg")
            #expect(local.previewFilePath == "/tmp/a.mp3")
        }
    }

    @Test("Rejects and preserves cache on a truncated snapshot")
    func testTruncatedSnapshotThrowsAndPreservesCache() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let old = ServerSong(songId: "old", title: "OLD", artist: "A", bpm: 120)
            context.insert(old)
            try context.save()

            let fetcher = TruncatingFetcher(all: [.stub(id: "a"), .stub(id: "b")], pageSize: 1)
            let cache = ServerSongCache(fetcher: fetcher, pageSize: 1)

            do {
                try await cache.refreshCatalog(modelContext: context)
                Issue.record("Expected incomplete snapshot error")
            } catch let error as ServerSongCatalogRefreshError {
                #expect(error == .incompleteSnapshot(expected: 2, actual: 1))
            } catch {
                Issue.record("Unexpected error: \(error)")
            }

            let rows = try context.fetch(FetchDescriptor<ServerSong>())
            #expect(rows.count == 1)
            #expect(rows.first?.songId == "old")
            #expect(rows.first?.title == "OLD")
        }
    }

    @Test("Rejects duplicate IDs and preserves cache")
    func testDuplicateIDsThrowAndPreserveCache() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let old = ServerSong(songId: "old", title: "OLD", artist: "A", bpm: 120)
            context.insert(old)
            try context.save()

            let cache = ServerSongCache(fetcher: DuplicateIDFetcher(duplicateID: "dup"), pageSize: 2)

            do {
                try await cache.refreshCatalog(modelContext: context)
                Issue.record("Expected duplicate ID error")
            } catch let error as ServerSongCatalogRefreshError {
                #expect(error == .duplicateSongID("dup"))
            } catch {
                Issue.record("Unexpected error: \(error)")
            }

            let rows = try context.fetch(FetchDescriptor<ServerSong>())
            #expect(rows.count == 1)
            #expect(rows.first?.songId == "old")
        }
    }

    @Test("Rejects a changing totalCount and preserves cache")
    func testChangingTotalCountThrowsAndPreservesCache() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let old = ServerSong(songId: "old", title: "OLD", artist: "A", bpm: 120)
            context.insert(old)
            try context.save()

            let cache = ServerSongCache(fetcher: ChangingTotalCountFetcher(), pageSize: 1)

            do {
                try await cache.refreshCatalog(modelContext: context)
                Issue.record("Expected changing totalCount error")
            } catch let error as ServerSongCatalogRefreshError {
                #expect(error == .totalCountChanged(expected: 2, actual: 3))
            } catch {
                Issue.record("Unexpected error: \(error)")
            }

            let rows = try context.fetch(FetchDescriptor<ServerSong>())
            #expect(rows.count == 1)
            #expect(rows.first?.songId == "old")
        }
    }

    @Test("Propagates fetch errors and preserves old cache")
    func testRefreshCatalogThrowsOnFetchError() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let old = ServerSong(songId: "old", title: "OLD", artist: "A", bpm: 120)
            context.insert(old)
            try context.save()

            let fetcher = MockSimfileFetcher(all: [])
            fetcher.error = URLError(.notConnectedToInternet)
            let cache = ServerSongCache(fetcher: fetcher, pageSize: 10)

            do {
                try await cache.refreshCatalog(modelContext: context)
                Issue.record("Expected fetch error")
            } catch let error as URLError {
                #expect(error.code == .notConnectedToInternet)
            } catch {
                Issue.record("Unexpected error: \(error)")
            }

            let rows = try context.fetch(FetchDescriptor<ServerSong>())
            #expect(rows.count == 1)
            #expect(rows.first?.songId == "old")
        }
    }

    @Test("Restores old cache rows when replacement save fails")
    func testRefreshCatalogRollsBackOnSaveFailure() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let old = ServerSong(songId: "old", title: "OLD", artist: "A", bpm: 120)
            context.insert(old)
            try context.save()

            let fetcher = MockSimfileFetcher(all: [.stub(id: "a"), .stub(id: "b")])
            let cache = ServerSongCache(fetcher: fetcher, pageSize: 10) { _ in
                throw URLError(.cannotWriteToFile)
            }

            await #expect(throws: URLError.self) {
                try await cache.refreshCatalog(modelContext: context)
            }

            let rows = try context.fetch(FetchDescriptor<ServerSong>())
            #expect(rows.count == 1)
            #expect(rows.first?.songId == "old")
            #expect(rows.first?.title == "OLD")
        }
    }

    @Test("Clears server cache for a valid empty snapshot but preserves local songs")
    func testValidEmptySnapshotClearsOnlyServerCache() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let old = ServerSong(songId: "old", title: "OLD", artist: "A", bpm: 120)
            let local = Song(
                title: "Local Old",
                artist: "A",
                bpm: 120,
                duration: "3:30",
                genre: "DTX Import",
                isServerImported: true,
                serverSongId: "old",
                bgmFilePath: "/tmp/old.ogg",
                previewFilePath: "/tmp/old.mp3"
            )
            context.insert(old)
            context.insert(local)
            try context.save()

            let cache = ServerSongCache(fetcher: MockSimfileFetcher(all: []), pageSize: 10)
            try await cache.refreshCatalog(modelContext: context)

            #expect(try context.fetch(FetchDescriptor<ServerSong>()).isEmpty)
            let remainingLocal = try context.fetch(FetchDescriptor<Song>())
            let preserved = try #require(remainingLocal.first { $0.serverSongId == "old" })
            #expect(preserved.title == "Local Old")
            #expect(preserved.bgmFilePath == "/tmp/old.ogg")
            #expect(preserved.previewFilePath == "/tmp/old.mp3")
        }
    }

    @Test("Replaces cache with one save and no post-save status refresh")
    func testReplacementUsesOneSaveWithoutPostSaveStatusRefresh() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let local = Song(
                title: "Local A",
                artist: "A",
                bpm: 120,
                duration: "3:30",
                genre: "DTX Import",
                isServerImported: true,
                serverSongId: "a",
                bgmFilePath: "/tmp/a.ogg",
                previewFilePath: "/tmp/a.mp3"
            )
            context.insert(local)
            try context.save()

            var cacheSaveCount = 0
            let statusManager = RecordingStatusManager()
            let cache = ServerSongCache(
                fetcher: MockSimfileFetcher(all: [.stub(id: "a")]),
                statusManager: statusManager,
                pageSize: 10,
                saveContext: { context in
                    cacheSaveCount += 1
                    try context.save()
                }
            )

            try await cache.refreshCatalog(modelContext: context)

            #expect(cacheSaveCount == 1)
            #expect(statusManager.refreshDownloadStatusCallCount == 0)
            let row = try #require(context.fetch(FetchDescriptor<ServerSong>()).first)
            #expect(row.isDownloaded)
        }
    }

}
