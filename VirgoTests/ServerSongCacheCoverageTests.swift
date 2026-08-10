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
}
