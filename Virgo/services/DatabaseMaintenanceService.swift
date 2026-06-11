//
//  DatabaseMaintenanceService.swift
//  Virgo
//
//  Created by Claude Code on 27/7/2025.
//

import SwiftUI
import SwiftData

@MainActor
class DatabaseMaintenanceService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func performInitialMaintenance(songs: [Song]) {
        backfillServerImportedFlag(songs: songs)
        updateExistingChartLevels(songs: songs)
        cleanupDuplicateSongs(songs: songs)
        cleanupOldSampleSongs(songs: songs)
        
        // Force a final save to ensure all changes are persisted
        do {
            try modelContext.save()
            Logger.database("performInitialMaintenance completed successfully")
        } catch {
            Logger.databaseError(error)
        }
    }

    /// Backfills `Song.isServerImported` for stores created before the flag existed.
    ///
    /// Prior to the dedicated `isServerImported` Bool, server-imported songs were
    /// identified by `genre == "DTX Import"`. The additive SwiftData migration that
    /// introduced the property defaults existing rows to `false`, which would make
    /// already-downloaded songs vanish from downloaded views, lose preview playback,
    /// and become undeletable as server imports. This one-time, idempotent pass
    /// promotes the legacy genre signal to the explicit flag so existing users keep
    /// their downloaded songs. Safe because only the legacy server-imported songs ever
    /// carried the "DTX Import" genre, and the predicate is empty after the first run.
    private func backfillServerImportedFlag(songs: [Song]) {
        var migrated = 0
        for song in songs where song.genre == "DTX Import" && !song.isServerImported {
            song.isServerImported = true
            migrated += 1
        }
        if migrated > 0 {
            Logger.database("Backfilled isServerImported for \(migrated) legacy server-imported song(s)")
        }
    }

    private func updateExistingChartLevels(songs: [Song]) {
        // Update any existing charts that still have the default level of 50
        // and haven't been assigned proper difficulty-based levels
        var needsUpdate = false

        for song in songs {
            for chart in song.charts {
                // Only update charts that have the default level (50) and would get a different level
                if chart.level == 50 && chart.difficulty.defaultLevel != 50 {
                    chart.level = chart.difficulty.defaultLevel
                    needsUpdate = true
                }
            }
        }

        if needsUpdate {
            do {
                try modelContext.save()
                Logger.database("Updated existing chart levels based on difficulty")
            } catch {
                Logger.databaseError(error)
            }
        }
    }

    private func cleanupDuplicateSongs(songs: [Song]) {
        // Find and remove duplicate songs.
        // Server-imported songs use title+artist+serverSongId as the key so that
        // distinct catalog entries sharing the same title/artist are preserved.
        // Local songs (no serverSongId) use title+artist only.
        var seenKeys: Set<String> = []
        var duplicatesToRemove: [Song] = []

        for song in songs {
            let baseKey = "\(song.title.lowercased())|\(song.artist.lowercased())"
            let key: String
            if let serverId = song.serverSongId {
                key = "\(baseKey)|server:\(serverId)"
            } else {
                key = baseKey
            }
            if seenKeys.contains(key) {
                duplicatesToRemove.append(song)
                Logger.database("Found duplicate song to remove: \(song.title) by \(song.artist)")
            } else {
                seenKeys.insert(key)
            }
        }

        if !duplicatesToRemove.isEmpty {
            for song in duplicatesToRemove {
                modelContext.delete(song)
            }

            do {
                try modelContext.save()
                Logger.database("Cleaned up \(duplicatesToRemove.count) duplicate songs")
            } catch {
                Logger.databaseError(error)
            }
        }
    }

    private func cleanupOldSampleSongs(songs: [Song]) {
        // Don't remove sample songs - they provide content for the app
        // Only remove truly problematic duplicates or corrupted data
        Logger.database("Skipping sample song cleanup to preserve app content")
    }
}
