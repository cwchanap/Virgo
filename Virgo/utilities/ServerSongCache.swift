import Foundation
import SwiftData

/// Loads and refreshes the cached server-song catalog from the GraphQL backend.
/// Refresh is manual and additive: new ids are inserted, existing ids are left
/// untouched (except for a one-time backfill of legacy charts missing a
/// `fileURL` — see `backfillLegacyChartURLs`), and ids absent from the server
/// are pruned (with local files).
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

        // Backfill charts on legacy entries whose `fileURL` column was defaulted
        // to "" by SwiftData lightweight migration (REST-catalog era). Without
        // this, `downloadAndImportSong` throws `invalidChartURL` for every chart
        // and the song can never be downloaded. Only charts missing a URL are
        // touched; other fields and user state (isDownloaded, etc.) are preserved.
        //
        // Must run BEFORE pruning: `existing` still holds valid SwiftData
        // references at this point. After pruning, deleted objects in the
        // array would fault or crash when accessing `song.charts`.
        backfillLegacyChartURLs(existing: existing, dtos: serverDTOs)

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
        // Track inserted ids to skip duplicates within the same fetch batch.
        var insertedIds = Set<String>()
        for dto in serverDTOs where !existingIds.contains(dto.id) && !insertedIds.contains(dto.id) {
            insertedIds.insert(dto.id)
            let song = SimfileMapper.makeServerSong(from: dto)
            modelContext.insert(song)
            for chart in song.charts { modelContext.insert(chart) }
        }
        if insertedIds.count < serverDTOs.count - existingIds.intersection(serverIds).count {
            Logger.warning(
                "Skipped \(serverDTOs.count - insertedIds.count - existingIds.intersection(serverIds).count) " +
                "duplicate DTO(s) during catalog insert"
            )
        }

        do {
            try saveContext(modelContext)
        } catch {
            modelContext.rollback()
            throw error
        }
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

    /// Patches `fileURL`/`fileEncoding` on legacy `ServerChart`s that predate
    /// those columns (defaulted to "" / "SHIFT_JIS" by SwiftData lightweight
    /// migration). Safe because `ServerChart` holds only catalog metadata — no
    /// user state lives on it. Charts that already have a URL are left alone so
    /// the additive refresh contract is unchanged for non-legacy entries.
    private func backfillLegacyChartURLs(existing: [ServerSong], dtos: [SimfileDTO]) {
        // Use grouping + first to avoid crashing on duplicate DTO IDs (pagination bugs,
        // data inconsistencies). Logs a warning so the issue is visible.
        var dtoById: [String: SimfileDTO] = [:]
        for dto in dtos {
            if dtoById[dto.id] != nil {
                Logger.warning("Duplicate simfile ID '\(dto.id)' in server response; using first occurrence")
            }
            if dtoById[dto.id] == nil {
                dtoById[dto.id] = dto
            }
        }
        var backfilled = 0
        for song in existing {
            guard song.charts.contains(where: { $0.fileURL.isEmpty }) else { continue }
            guard let dto = dtoById[song.songId] else {
                Logger.warning(
                    "Backfill skipped: legacy song \(song.songId) has empty chart fileURL " +
                    "but is absent from the server DTO set"
                )
                continue
            }
            for chart in song.charts where chart.fileURL.isEmpty {
                guard let match = Self.matchingDtxFile(for: chart, in: dto.dtxFiles) else {
                    Logger.warning(
                        "Backfill skipped: no DTO chart match for \(song.songId)/\(chart.difficultyLabel)"
                    )
                    continue
                }
                chart.fileURL = match.fileURL
                chart.fileEncoding = match.encoding.rawValue
                backfilled += 1
            }
        }
        if backfilled > 0 {
            Logger.database("Backfilled fileURL/fileEncoding for \(backfilled) legacy chart(s)")
        }
    }

    /// Matches a legacy chart to its DTO counterpart. Single-chart songs match
    /// trivially; otherwise prefer the stable `difficultyLabel`, then the
    /// filename derived from the DTO's URL.
    private static func matchingDtxFile(for chart: ServerChart, in files: [DtxFileDTO]) -> DtxFileDTO? {
        if files.count == 1 { return files.first }
        if let byLabel = files.first(where: { $0.label == chart.difficultyLabel }) { return byLabel }
        return files.first { URL(string: $0.fileURL)?.lastPathComponent == chart.filename }
    }
}
