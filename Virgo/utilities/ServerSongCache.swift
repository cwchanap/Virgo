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
        let serverDTOs = try await fetchAllPages()
        let serverIds = Set(serverDTOs.map(\.id))

        let existing = try modelContext.fetch(FetchDescriptor<ServerSong>())
        let existingIds = Set(existing.map(\.songId))

        // Prune ids no longer on the server (delete record + local files).
        for song in existing where !serverIds.contains(song.songId) {
            await statusManager.pruneCachedSong(song, modelContext: modelContext)
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

    private func fetchAllPages() async throws -> [SimfileDTO] {
        var results: [SimfileDTO] = []
        var page = 1
        while true {
            let pageResult = try await fetcher.fetchSimfiles(page: page, pageSize: pageSize, search: nil)
            results.append(contentsOf: pageResult.simfiles)
            if results.count >= pageResult.totalCount || pageResult.simfiles.isEmpty { break }
            page += 1
        }
        return results
    }
}
