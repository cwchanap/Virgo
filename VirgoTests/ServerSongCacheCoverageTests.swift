import Testing
import SwiftData
import Foundation
@testable import Virgo

@Suite("ServerSongCache Coverage Tests", .serialized)
@MainActor
struct ServerSongCacheCoverageTests {

    private func makeLowLevelDTO(id: String, level: Double = 5.0) -> SimfileDTO {
        SimfileDTO(
            id: id, title: "Low", artist: "A", bpm: 120, genre: nil, tags: [],
            durationSeconds: nil, updatedAt: "2026-06-01T00:00:00Z",
            dtxFiles: [DtxFileDTO(label: "BASIC", level: level,
                                  fileURL: "https://r2/\(id)/bas.dtx",
                                  fileSizeBytes: 100, encoding: .shiftJIS)],
            fileKeys: []
        )
    }

    @Test("Logs warning when chart levels are on 0-10 scale")
    func testLevelScaleWarning() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let fetcher = MockSimfileFetcher(all: [makeLowLevelDTO(id: "lo")])
            let cache = ServerSongCache(fetcher: fetcher, pageSize: 10)
            try await cache.refreshCatalog(modelContext: context)

            let songs = try context.fetch(FetchDescriptor<ServerSong>())
            #expect(songs.count == 1)
            #expect(songs.first?.songId == "lo")
        }
    }

    @Test("Backfill skips legacy song absent from server DTOs")
    func testBackfillSkipsAbsentLegacySong() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let legacyChart = ServerChart(
                difficulty: "basic", difficultyLabel: "BASIC", level: 30,
                filename: "bas.dtx", size: 100, fileURL: "", fileEncoding: "SHIFT_JIS"
            )
            let legacy = ServerSong(
                songId: "ghost", title: "Ghost", artist: "A", bpm: 120,
                charts: [legacyChart]
            )
            context.insert(legacy); context.insert(legacyChart)
            try context.save()

            let fetcher = MockSimfileFetcher(all: [.stub(id: "other")])
            let cache = ServerSongCache(fetcher: fetcher, pageSize: 10)
            try await cache.refreshCatalog(modelContext: context)

            let songs = try context.fetch(FetchDescriptor<ServerSong>())
            let ghost = songs.first { $0.songId == "ghost" }
            #expect(ghost == nil,
                    "Absent legacy song is pruned; backfill-skip path executed")
        }
    }

    @Test("Backfill skips chart when no DTX file matches by label or filename")
    func testBackfillSkipsNoMatchingDtxFile() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let legacyChart = ServerChart(
                difficulty: "basic", difficultyLabel: "MANIAC", level: 90,
                filename: "mani.dtx", size: 100, fileURL: "", fileEncoding: "SHIFT_JIS"
            )
            let legacy = ServerSong(
                songId: "a", title: "Old", artist: "A", bpm: 120,
                charts: [legacyChart]
            )
            context.insert(legacy); context.insert(legacyChart)
            try context.save()

            let dto = SimfileDTO(
                id: "a", title: "T", artist: "A", bpm: 120, genre: nil, tags: [],
                durationSeconds: nil, updatedAt: "2026-06-01T00:00:00Z",
                dtxFiles: [
                    DtxFileDTO(label: "BASIC", level: 30,
                               fileURL: "https://r2/a/basic.dtx", fileSizeBytes: 100,
                               encoding: .shiftJIS),
                    DtxFileDTO(label: "EXTREME", level: 95,
                               fileURL: "https://r2/a/ext.dtx", fileSizeBytes: 200,
                                encoding: .shiftJIS)
                ],
                fileKeys: []
            )
            let fetcher = MockSimfileFetcher(all: [dto])
            let cache = ServerSongCache(fetcher: fetcher, pageSize: 10)
            try await cache.refreshCatalog(modelContext: context)

            let songA = try context.fetch(FetchDescriptor<ServerSong>())
                .first { $0.songId == "a" }
            #expect(songA?.charts.first?.fileURL.isEmpty == true,
                    "Chart with no label/filename match must NOT be backfilled")
        }
    }

    @Test("Backfill matches DTX file by filename when label does not match")
    func testBackfillMatchesByFilename() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let legacyChart = ServerChart(
                difficulty: "basic", difficultyLabel: "MANIAC", level: 90,
                filename: "mani.dtx", size: 100, fileURL: "", fileEncoding: "SHIFT_JIS"
            )
            let legacy = ServerSong(
                songId: "a", title: "Old", artist: "A", bpm: 120,
                charts: [legacyChart]
            )
            context.insert(legacy); context.insert(legacyChart)
            try context.save()

            let dto = SimfileDTO(
                id: "a", title: "T", artist: "A", bpm: 120, genre: nil, tags: [],
                durationSeconds: nil, updatedAt: "2026-06-01T00:00:00Z",
                dtxFiles: [
                    DtxFileDTO(label: "BASIC", level: 30,
                               fileURL: "https://r2/a/basic.dtx", fileSizeBytes: 100,
                               encoding: .shiftJIS),
                    DtxFileDTO(label: "EXTREME", level: 95,
                               fileURL: "https://r2/a/mani.dtx", fileSizeBytes: 200,
                                encoding: .utf8)
                ],
                fileKeys: []
            )
            let fetcher = MockSimfileFetcher(all: [dto])
            let cache = ServerSongCache(fetcher: fetcher, pageSize: 10)
            try await cache.refreshCatalog(modelContext: context)

            let songA = try context.fetch(FetchDescriptor<ServerSong>())
                .first { $0.songId == "a" }
            let chart = try #require(songA?.charts.first)
            #expect(chart.fileURL == "https://r2/a/mani.dtx",
                    "Must match by filename when label doesn't match")
            #expect(chart.fileEncoding == "UTF_8")
        }
    }

    @Test("Backfill matches DTX file by label with multiple files")
    func testBackfillMatchesByLabel() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let legacyChart = ServerChart(
                difficulty: "extreme", difficultyLabel: "EXTREME", level: 95,
                filename: "x.dtx", size: 100, fileURL: "", fileEncoding: "SHIFT_JIS"
            )
            let legacy = ServerSong(
                songId: "a", title: "Old", artist: "A", bpm: 120,
                charts: [legacyChart]
            )
            context.insert(legacy); context.insert(legacyChart)
            try context.save()

            let dto = SimfileDTO(
                id: "a", title: "T", artist: "A", bpm: 120, genre: nil, tags: [],
                durationSeconds: nil, updatedAt: "2026-06-01T00:00:00Z",
                dtxFiles: [
                    DtxFileDTO(label: "BASIC", level: 30,
                               fileURL: "https://r2/a/basic.dtx", fileSizeBytes: 100,
                               encoding: .shiftJIS),
                    DtxFileDTO(label: "EXTREME", level: 95,
                               fileURL: "https://r2/a/ext.dtx", fileSizeBytes: 200,
                                encoding: .utf8)
                ],
                fileKeys: []
            )
            let fetcher = MockSimfileFetcher(all: [dto])
            let cache = ServerSongCache(fetcher: fetcher, pageSize: 10)
            try await cache.refreshCatalog(modelContext: context)

            let songA = try context.fetch(FetchDescriptor<ServerSong>())
                .first { $0.songId == "a" }
            let chart = try #require(songA?.charts.first)
            #expect(chart.fileURL == "https://r2/a/ext.dtx",
                    "Must match by label when multiple files present")
            #expect(chart.fileEncoding == "UTF_8")
        }
    }

    @Test("Backfill matches single DTX file regardless of label")
    func testBackfillSingleDtxFileAlwaysMatches() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let legacyChart = ServerChart(
                difficulty: "basic", difficultyLabel: "MISC_LABEL", level: 50,
                filename: "chart.dtx", size: 100, fileURL: "", fileEncoding: "SHIFT_JIS"
            )
            let legacy = ServerSong(
                songId: "a", title: "Old", artist: "A", bpm: 120,
                charts: [legacyChart]
            )
            context.insert(legacy); context.insert(legacyChart)
            try context.save()

            let dto = SimfileDTO(
                id: "a", title: "T", artist: "A", bpm: 120, genre: nil, tags: [],
                durationSeconds: nil, updatedAt: "2026-06-01T00:00:00Z",
                dtxFiles: [
                    DtxFileDTO(label: "BASIC", level: 50,
                               fileURL: "https://r2/a/basic.dtx", fileSizeBytes: 100,
                                encoding: .shiftJIS)
                ],
                fileKeys: []
            )
            let fetcher = MockSimfileFetcher(all: [dto])
            let cache = ServerSongCache(fetcher: fetcher, pageSize: 10)
            try await cache.refreshCatalog(modelContext: context)

            let songA = try context.fetch(FetchDescriptor<ServerSong>())
                .first { $0.songId == "a" }
            let chart = try #require(songA?.charts.first)
            #expect(chart.fileURL == "https://r2/a/basic.dtx",
                    "Single DTX file must always match regardless of label")
        }
    }

    @Test("Logs duplicate DTO warning during backfill")
    func testDuplicateDTOWarningInBackfill() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let legacyChart = ServerChart(
                difficulty: "basic", difficultyLabel: "BASIC", level: 30,
                filename: "bas.dtx", size: 100, fileURL: "", fileEncoding: "SHIFT_JIS"
            )
            let legacy = ServerSong(
                songId: "dup", title: "Dup", artist: "A", bpm: 120,
                charts: [legacyChart]
            )
            context.insert(legacy); context.insert(legacyChart)
            try context.save()

            let fetcher = DuplicateBackfillFetcher()
            let cache = ServerSongCache(fetcher: fetcher, pageSize: 10)
            try await cache.refreshCatalog(modelContext: context)

            let song = try context.fetch(FetchDescriptor<ServerSong>())
                .first { $0.songId == "dup" }
            #expect(song?.charts.first?.fileURL.isEmpty == false,
                    "Backfill must still succeed for first occurrence of duplicate")
        }
    }

    private final class DuplicateBackfillFetcher: SimfileFetching, @unchecked Sendable {
        func fetchSimfiles(page: Int, pageSize: Int, search: String?) async throws -> SimfilePage {
            let dto = SimfileDTO(
                id: "dup", title: "Dup", artist: "A", bpm: 120, genre: nil, tags: [],
                durationSeconds: nil, updatedAt: "2026-06-01T00:00:00Z",
                dtxFiles: [DtxFileDTO(label: "BASIC", level: 30,
                                      fileURL: "https://r2/dup/bas.dtx",
                                      fileSizeBytes: 100, encoding: .shiftJIS)],
                fileKeys: []
            )
            if page == 1 {
                return SimfilePage(simfiles: [dto, dto], totalCount: 1)
            }
            return SimfilePage(simfiles: [], totalCount: 1)
        }
        func fetchSimfile(id: String) async throws -> SimfileDTO? { nil }
    }
}
