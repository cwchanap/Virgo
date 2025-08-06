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
        // Remove any old sample songs that are not DTX Import data
        let oldSampleSongs = songs.filter { song in
            song.genre != "DTX Import"
        }

        if !oldSampleSongs.isEmpty {
            Logger.database("Found \(oldSampleSongs.count) old sample songs to remove")

            for song in oldSampleSongs {
                Logger.database("Removing old sample song: \(song.title) by \(song.artist) (genre: \(song.genre))")

                // Delete all charts and their notes first for proper cleanup
                for chart in song.charts {
                    for note in chart.notes {
                        modelContext.delete(note)
                    }
                    modelContext.delete(chart)
                }

                // Then delete the song
                modelContext.delete(song)
            }

            do {
                try modelContext.save()
                Logger.database("Successfully cleaned up \(oldSampleSongs.count) old sample songs")
            } catch {
                Logger.databaseError(error)
            }
        } else {
            Logger.database("No old sample songs found to clean up")
        }
    }
}
