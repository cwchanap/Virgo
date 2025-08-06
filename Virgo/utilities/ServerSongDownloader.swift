import Foundation
import SwiftData

/// Handles downloading and importing server songs
class ServerSongDownloader {
    private let apiClient = DTXAPIClient()
    private let fileManager = ServerSongFileManager()

    /// Download and import a multi-difficulty song
    func downloadAndImportSong(_ serverSong: ServerSong, container: ModelContainer) async -> (Bool, String?) {
        // Create background ModelContext using the same container
        let backgroundContext = ModelContext(container)

        do {
            // Check if song already exists to prevent duplicates
            let existingDescriptor = FetchDescriptor<Song>()
            let existingSongs = try backgroundContext.fetch(existingDescriptor)

            let songAlreadyExists = existingSongs.contains { existingSong in
                existingSong.title.lowercased() == serverSong.title.lowercased() &&
                    existingSong.artist.lowercased() == serverSong.artist.lowercased()
            }

            if songAlreadyExists {
                return (false, "Song already exists in database")
            }

            // Create the Song object first
            let song = Song(
                title: serverSong.title,
                artist: serverSong.artist,
                bpm: Int(serverSong.bpm),
                duration: "3:30", // Will be updated after parsing first chart
                genre: "DTX Import",
                timeSignature: .fourFour
            )

            // Download and process each chart with throttling to reduce system stress
            for (index, serverChart) in serverSong.charts.enumerated() {
                // Add small delay between downloads to reduce system stress
                if index > 0 {
                    try await Task.sleep(nanoseconds: 100_000_000) // 100ms delay
                }

                let fileData = try await apiClient.downloadChartFile(
                    songId: serverSong.songId,
                    chartFilename: serverChart.filename
                )

                // Convert data to string with Shift-JIS encoding
                guard let dtxContent = String(data: fileData, encoding: .shiftJIS) else {
                    Logger.debug("Failed to decode \(serverChart.filename) with Shift-JIS encoding")
                    continue
                }

                // Parse the DTX content
                let chartData = try DTXFileParser.parseChartMetadata(from: dtxContent)

                // Update song BPM from the first chart if not already set (use rounded value)
                if song.charts.isEmpty {
                    song.bpm = Int(chartData.bpm.rounded())
                }

                // Map server difficulty to app difficulty
                let difficulty = mapServerDifficultyToApp(serverChart.difficulty)

                let chart = Chart(difficulty: difficulty, level: serverChart.level, song: song)

                // Add notes to the chart
                let notes = chartData.toNotes(for: chart)
                notes.forEach { note in
                    chart.notes.append(note)
                }

                // Update song duration from first chart
                if song.charts.isEmpty {
                    song.duration = formatDuration(calculateDuration(from: chartData.notes))
                }

                backgroundContext.insert(chart)
            }

            // Download BGM file if available
            do {
                let bgmData = try await apiClient.downloadBGMFile(songId: serverSong.songId)
                let bgmPath = try fileManager.saveBGMFile(bgmData, for: serverSong.songId)
                song.bgmFilePath = bgmPath
                Logger.database("Downloaded BGM file for song: \(song.title)")
            } catch {
                // BGM download is optional - continue even if it fails
                Logger.database("Failed to download BGM for song \(song.title): \(error.localizedDescription)")
            }

            // Download preview file if available
            do {
                let previewData = try await apiClient.downloadPreviewFile(songId: serverSong.songId)
                let previewPath = try fileManager.savePreviewFile(previewData, for: serverSong.songId)
                song.previewFilePath = previewPath
                Logger.database("Downloaded preview file for song: \(song.title)")
            } catch {
                // Preview download is optional - continue even if it fails
                Logger.database("Failed to download preview for song \(song.title): \(error.localizedDescription)")
            }

            // Save to SwiftData using background context
            backgroundContext.insert(song)
            try backgroundContext.save()

            return (true, nil)

        } catch {
            return (false, "Multi-difficulty import failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Private Helper Methods

    private func mapServerDifficultyToApp(_ serverDifficulty: String) -> Difficulty {
        switch serverDifficulty.lowercased() {
        case "easy":
            return .easy
        case "medium":
            return .medium
        case "hard":
            return .hard
        case "expert":
            return .expert
        default:
            return .medium
        }
    }

    private func calculateDuration(from notes: [DTXNote]) -> TimeInterval {
        guard !notes.isEmpty else { return 60.0 }

        let maxMeasure = notes.map(\.measureNumber).max() ?? 0
        let estimatedMeasures = maxMeasure + 1

        // Estimate duration based on 4/4 time signature and average BPM
        let measuresPerMinute = 30.0 // Assuming ~120 BPM average
        return Double(estimatedMeasures) / measuresPerMinute * 60.0
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}
