import Foundation
import SwiftData

enum ServerSongCatalogRefreshError: LocalizedError, Equatable {
    case totalCountChanged(expected: Int, actual: Int)
    case incompleteSnapshot(expected: Int, actual: Int)
    case unexpectedSnapshotCount(expected: Int, actual: Int)
    case duplicateSongID(String)

    var errorDescription: String? {
        switch self {
        case .totalCountChanged(let expected, let actual):
            return "Catalog changed during refresh (expected \(expected) items, server now reports \(actual))."
        case .incompleteSnapshot(let expected, let actual):
            return "Catalog refresh was incomplete (expected \(expected) items, received \(actual))."
        case .unexpectedSnapshotCount(let expected, let actual):
            return "Catalog refresh returned an unexpected item count (expected \(expected), received \(actual))."
        case .duplicateSongID(let id):
            return "Catalog refresh returned duplicate song ID '\(id)'."
        }
    }
}

/// Loads and refreshes the cached server-song catalog from the GraphQL backend.
/// Refresh is manual and replaces the cached catalog metadata from a validated
/// complete snapshot. Local imported ``Song`` rows and their audio are retained.
@MainActor
class ServerSongCache {
    private let fetcher: SimfileFetching
    private let statusManager: ServerSongStatusManager
    private let pageSize: Int
    private let saveContext: (ModelContext) throws -> Void

    init(
        fetcher: SimfileFetching,
        statusManager: ServerSongStatusManager = ServerSongStatusManager(),
        pageSize: Int = 50,
        saveContext: @escaping (ModelContext) throws -> Void = { try $0.save() }
    ) {
        self.fetcher = fetcher
        self.statusManager = statusManager
        self.pageSize = pageSize
        self.saveContext = saveContext
    }

    /// Manual catalog refresh: validate and replace the complete server snapshot.
    func refreshCatalog(modelContext: ModelContext) async throws {
        let serverDTOs = try await fetchCompleteSnapshot()

        let allLevels = serverDTOs.flatMap(\.dtxFiles).map(\.level)
        if let maxLevel = allLevels.max(), maxLevel <= 10, !allLevels.isEmpty {
            Logger.warning(
                "Chart levels max at \(maxLevel) — possible 0-10 scale (expected 0-100). " +
                "Difficulty bucketing may be incorrect."
            )
        }

        let localSongs = try modelContext.fetch(FetchDescriptor<Song>())
        let existingCache = try modelContext.fetch(FetchDescriptor<ServerSong>())
        let replacement = serverDTOs.map { SimfileMapper.makeServerSong(from: $0) }

        statusManager.applyDownloadStatus(to: replacement, from: localSongs)

        for row in existingCache {
            modelContext.delete(row)
        }
        for row in replacement {
            modelContext.insert(row)
            for chart in row.charts {
                modelContext.insert(chart)
            }
        }

        do {
            try saveContext(modelContext)
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private func fetchCompleteSnapshot(maxPages: Int = 100) async throws -> [SimfileDTO] {
        var results: [SimfileDTO] = []
        var seenIDs = Set<String>()
        var expectedTotalCount: Int?

        for page in 1...maxPages {
            let pageResult = try await fetcher.fetchSimfiles(
                page: page,
                pageSize: pageSize,
                search: nil
            )

            if let expectedTotalCount {
                guard pageResult.totalCount == expectedTotalCount else {
                    throw ServerSongCatalogRefreshError.totalCountChanged(
                        expected: expectedTotalCount,
                        actual: pageResult.totalCount
                    )
                }
            } else {
                expectedTotalCount = pageResult.totalCount
            }

            for dto in pageResult.simfiles {
                guard seenIDs.insert(dto.id).inserted else {
                    throw ServerSongCatalogRefreshError.duplicateSongID(dto.id)
                }
                results.append(dto)
            }

            let expected = expectedTotalCount ?? 0
            guard results.count <= expected else {
                throw ServerSongCatalogRefreshError.unexpectedSnapshotCount(
                    expected: expected,
                    actual: results.count
                )
            }
            if results.count == expected {
                break
            }
            guard !pageResult.simfiles.isEmpty else {
                throw ServerSongCatalogRefreshError.incompleteSnapshot(
                    expected: expected,
                    actual: results.count
                )
            }
        }

        let expected = expectedTotalCount ?? 0
        guard results.count == expected else {
            throw ServerSongCatalogRefreshError.incompleteSnapshot(
                expected: expected,
                actual: results.count
            )
        }
        return results
    }
}
