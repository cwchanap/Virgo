import Foundation
@testable import Virgo

/// In-memory `SimfileFetching` that paginates a fixed list. Thread-safe enough
/// for serialized test suites.
final class MockSimfileFetcher: SimfileFetching, @unchecked Sendable {
    var all: [SimfileDTO]
    var error: Error?
    private(set) var fetchSimfilesCallCount = 0

    init(all: [SimfileDTO] = []) { self.all = all }

    func fetchSimfiles(page: Int, pageSize: Int, search: String?) async throws -> SimfilePage {
        fetchSimfilesCallCount += 1
        if let error { throw error }
        let start = max(0, (page - 1) * pageSize)
        guard start < all.count else { return SimfilePage(simfiles: [], totalCount: all.count) }
        let end = min(start + pageSize, all.count)
        return SimfilePage(simfiles: Array(all[start..<end]), totalCount: all.count)
    }

    func fetchSimfile(id: String) async throws -> SimfileDTO? {
        if let error { throw error }
        return all.first { $0.id == id }
    }
}

extension SimfileDTO {
    /// Convenience builder for tests.
    static func stub(
        id: String,
        title: String = "T",
        fileKeys: [String] = [],
        encoding: SimfileEncoding = .shiftJIS
    ) -> SimfileDTO {
        SimfileDTO(
            id: id, title: title, artist: "A", bpm: 120, genre: nil, tags: [],
            durationSeconds: nil, updatedAt: "2026-06-01T00:00:00Z",
            dtxFiles: [DtxFileDTO(label: "BASIC", level: 30, fileURL: "https://r2/\(id)/bas.dtx",
                                  fileSizeBytes: 100, encoding: encoding)],
            fileKeys: fileKeys
        )
    }
}
