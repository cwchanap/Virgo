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
        // Find and remove duplicate songs (same title + artist)
        var songTitleArtistPairs: Set<String> = []
        var duplicatesToRemove: [Song] = []

        for song in songs {
            let key = "\(song.title.lowercased())|\(song.artist.lowercased())"
            if songTitleArtistPairs.contains(key) {
                // This is a duplicate
                duplicatesToRemove.append(song)
                Logger.database("Found duplicate song to remove: \(song.title) by \(song.artist)")
            } else {
                songTitleArtistPairs.insert(key)
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
