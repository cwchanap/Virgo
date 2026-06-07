import Foundation
import SwiftData

/// Loads and refreshes the cached server-song catalog from the GraphQL backend.
/// Refresh is manual and additive: new ids are inserted, existing ids are left
/// untouched, and ids absent from the server are pruned (with local files).
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

    /// Load the cached catalog. No network — refresh is explicit (see `refreshCatalog`).
    func loadServerSongs(modelContext: ModelContext) async throws -> [ServerSong] {
        let descriptor = FetchDescriptor<ServerSong>(
            sortBy: [SortDescriptor(\.lastUpdated, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Manual catalog refresh: page-walk PUBLISHED, insert new, prune stale.
    func refreshCatalog(modelContext: ModelContext) async throws {
        let (serverDTOs, isComplete) = try await fetchAllPages()
        let serverIds = Set(serverDTOs.map(\.id))

        // Warn if levels appear to be on a 0-10 scale instead of the expected 0-100.
        let allLevels = serverDTOs.flatMap(\.dtxFiles).map(\.level)
        if let maxLevel = allLevels.max(), maxLevel <= 10, !allLevels.isEmpty {
            Logger.warning(
                "Chart levels max at \(maxLevel) — possible 0-10 scale (expected 0-100). " +
                "Difficulty bucketing may be incorrect."
            )
        }

        let existing = try modelContext.fetch(FetchDescriptor<ServerSong>())
        let existingIds = Set(existing.map(\.songId))

        // Only prune stale ids when the page-walk completed fully. An incomplete
        // walk (e.g. a transient empty page mid-walk) must NOT trigger destructive
        // deletes of songs that may still be valid on the server.
        if isComplete {
            for song in existing where !serverIds.contains(song.songId) {
                await statusManager.pruneCachedSong(song, modelContext: modelContext)
            }
        } else {
            Logger.warning(
                "Catalog refresh incomplete (\(serverDTOs.count) fetched); skipping prune to avoid data loss"
            )
        }

        // Insert only new ids; never overwrite existing entries.
        for dto in serverDTOs where !existingIds.contains(dto.id) {
            let song = SimfileMapper.makeServerSong(from: dto)
            modelContext.insert(song)
            for chart in song.charts { modelContext.insert(chart) }
        }

        try saveContext(modelContext)
        await statusManager.refreshDownloadStatus(modelContext: modelContext)
    }

    /// Walks all pages, returning the accumulated DTOs and whether the walk
    /// reached `totalCount` (true) or stopped early on an empty page (false).
    private func fetchAllPages() async throws -> (simfiles: [SimfileDTO], isComplete: Bool) {
        var results: [SimfileDTO] = []
        var page = 1
        while true {
            let pageResult = try await fetcher.fetchSimfiles(page: page, pageSize: pageSize, search: nil)
            results.append(contentsOf: pageResult.simfiles)
            if results.count >= pageResult.totalCount { return (results, true) }
            if pageResult.simfiles.isEmpty { return (results, false) }
            page += 1
        }
    }
}
