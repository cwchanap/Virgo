import Foundation
import SwiftData

/// Handles server song loading, caching, and data processing
class ServerSongCache {
    private let apiClient = DTXAPIClient()

    /// Load server songs from cache or refresh from server if needed
    @MainActor
    func loadServerSongs(modelContext: ModelContext) async throws -> [ServerSong] {
        // First load from cache
        let descriptor = FetchDescriptor<ServerSong>(
            sortBy: [SortDescriptor(\.lastUpdated, order: .reverse)]
        )

        do {
            let cachedSongs = try modelContext.fetch(descriptor)

            // If cache is empty or stale (older than 5 minutes for development), refresh from server
            let fiveMinutesAgo = Date().addingTimeInterval(-300)
            let shouldRefresh = cachedSongs.isEmpty ||
                cachedSongs.first?.lastUpdated ?? Date.distantPast < fiveMinutesAgo

            if shouldRefresh {
                try await refreshServerSongs(modelContext: modelContext, forceClear: false)
                return try modelContext.fetch(descriptor)
            }

            // Update download status for cached songs
            let localSongsDescriptor = FetchDescriptor<Song>()
            let localSongs = try modelContext.fetch(localSongsDescriptor)

            var hasUpdates = false
            for serverSong in cachedSongs {
                let wasDownloaded = serverSong.isDownloaded
                let isCurrentlyDownloaded = isAlreadyDownloaded(serverSong, in: localSongs)

                // Update if status changed
                if wasDownloaded != isCurrentlyDownloaded {
                    serverSong.isDownloaded = isCurrentlyDownloaded
                    hasUpdates = true
                }
            }

            // Save any status updates
            if hasUpdates {
                try modelContext.save()
            }

            return cachedSongs
        } catch {
            Logger.debug("Failed to load server songs from cache: \(error)")
            return []
        }
    }

    /// Refresh server songs from API
    @MainActor
    func refreshServerSongs(modelContext: ModelContext, forceClear: Bool = false) async throws {
        do {
            // Fetch song list from server with multi-difficulty support
            let serverSongs = try await apiClient.listDTXSongs()

            // Process multi-difficulty songs
            var updatedSongs = processMultiDifficultySongs(serverSongs)

            // Only process individual DTX files if not force clearing (backward compatibility)
            if !forceClear {
                let serverFiles = try await apiClient.listDTXFiles()

                for file in serverFiles {
                    do {
                        let metadata = try await apiClient.getDTXMetadata(filename: file.filename)

                        let serverSong = ServerSong(
                            filename: file.filename,
                            title: metadata.title ?? file.filename.replacingOccurrences(of: ".dtx", with: ""),
                            artist: metadata.artist ?? "Unknown Artist",
                            bpm: metadata.bpm ?? 120.0,
                            difficultyLevel: metadata.level ?? 50,
                            size: file.size
                        )

                        updatedSongs.append(serverSong)
                    } catch {
                        Logger.debug("Failed to get metadata for \(file.filename): \(error)")
                        // Create song with filename only
                        let serverSong = ServerSong(
                            filename: file.filename,
                            title: file.filename.replacingOccurrences(of: ".dtx", with: ""),
                            artist: "Unknown Artist",
                            bpm: 120.0,
                            difficultyLevel: 50,
                            size: file.size
                        )
                        updatedSongs.append(serverSong)
                    }
                }
            }

            // Update download status for all songs
            try await updateDownloadStatus(updatedSongs, modelContext: modelContext)

            // Clear existing server songs and charts
            try await clearExistingServerSongs(modelContext: modelContext)

            // Then insert new songs
            for song in updatedSongs {
                modelContext.insert(song)
                // Insert charts separately to ensure proper relationships
                for chart in song.charts {
                    modelContext.insert(chart)
                }
            }

            // Save the insertions
            do {
                try modelContext.save()
            } catch {
                Logger.debug("Error during insertion save: \(error)")
                throw error
            }

        } catch {
            Logger.debug("Failed to refresh server songs: \(error)")
            throw error
        }
    }

    // MARK: - Private Helper Methods

    private func clearExistingServerSongs(modelContext: ModelContext) async throws {
        // Use a more robust deletion approach to avoid memory management issues
        let existingDescriptor = FetchDescriptor<ServerSong>()
        let existingSongs = try modelContext.fetch(existingDescriptor)

        // Delete in smaller batches to reduce memory pressure
        let batchSize = 10
        for i in stride(from: 0, to: existingSongs.count, by: batchSize) {
            let endIndex = min(i + batchSize, existingSongs.count)
            let batch = Array(existingSongs[i..<endIndex])

            for song in batch where !song.isDeleted {
                modelContext.delete(song)
            }

            // Save after each batch to avoid accumulating too many changes
            do {
                try modelContext.save()
            } catch {
                Logger.database("Failed to save deletion batch: \(error)")
                throw error
            }
        }
    }

    private func processMultiDifficultySongs(_ serverSongs: [DTXServerSongData]) -> [ServerSong] {
        var updatedSongs: [ServerSong] = []

        // Process multi-difficulty songs
        for songData in serverSongs {
            let charts = songData.charts.map { chartData in
                ServerChart(
                    difficulty: chartData.difficulty,
                    difficultyLabel: chartData.difficultyLabel,
                    level: chartData.level,
                    filename: chartData.filename,
                    size: chartData.size
                )
            }

            let serverSong = ServerSong(
                songId: songData.songId,
                title: songData.title,
                artist: songData.artist ?? "Unknown Artist",
                bpm: songData.bpm ?? 120.0,
                charts: charts,
                isDownloaded: false,
                hasBGM: true, // Assume BGM is available for multi-difficulty songs
                hasPreview: true // Assume preview is available for multi-difficulty songs
            )

            updatedSongs.append(serverSong)
        }

        return updatedSongs
    }

    private func updateDownloadStatus(_ songs: [ServerSong], modelContext: ModelContext) async throws {
        // Check for existing downloads and preserve download status
        let localSongsDescriptor = FetchDescriptor<Song>()
        let localSongs = try modelContext.fetch(localSongsDescriptor)

        // Update download status based on existing local songs
        for serverSong in songs {
            serverSong.isDownloaded = isAlreadyDownloaded(serverSong, in: localSongs)
            serverSong.bgmDownloaded = hasBGMFile(serverSong, in: localSongs)
            serverSong.previewDownloaded = hasPreviewFile(serverSong, in: localSongs)
        }
    }

    private func isAlreadyDownloaded(_ serverSong: ServerSong, in localSongs: [Song]) -> Bool {
        return localSongs.contains { localSong in
            // Match by title and artist (case-insensitive)
            localSong.title.lowercased() == serverSong.title.lowercased() &&
                localSong.artist.lowercased() == serverSong.artist.lowercased()
        }
    }

    private func hasBGMFile(_ serverSong: ServerSong, in localSongs: [Song]) -> Bool {
        return localSongs.contains { localSong in
            // Match by title and artist (case-insensitive) and has BGM file
            localSong.title.lowercased() == serverSong.title.lowercased() &&
                localSong.artist.lowercased() == serverSong.artist.lowercased() &&
                localSong.bgmFilePath != nil
        }
    }

    private func hasPreviewFile(_ serverSong: ServerSong, in localSongs: [Song]) -> Bool {
        return localSongs.contains { localSong in
            // Match by title and artist (case-insensitive) and has preview file
            localSong.title.lowercased() == serverSong.title.lowercased() &&
                localSong.artist.lowercased() == serverSong.artist.lowercased() &&
                localSong.previewFilePath != nil
        }
    }
}
