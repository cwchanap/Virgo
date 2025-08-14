import Foundation
import SwiftData

/// Handles downloading and importing server songs
class ServerSongDownloader {
    private let apiClient = DTXAPIClient()
    private let fileManager = ServerSongFileManager()

    /// Download and import a multi-difficulty song
    func downloadAndImportSong(_ serverSong: ServerSong, container: ModelContainer) async -> (Bool, String?) {
        let backgroundContext = ModelContext(container)
        
        do {
            // Check if song already exists
            if try await songAlreadyExists(serverSong, in: backgroundContext) {
                return (false, "Song already exists in database")
            }
            
            // Create and populate the song
            let song = createSong(from: serverSong)
            try await processCharts(for: song, from: serverSong, in: backgroundContext)
            await downloadOptionalFiles(for: song, serverSong: serverSong)
            
            // Save to SwiftData
            backgroundContext.insert(song)
            try backgroundContext.save()
            
            return (true, nil)
        } catch {
            return (false, "Multi-difficulty import failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Private Helper Methods
    
    /// Check if a song with the same title and artist already exists
    private func songAlreadyExists(_ serverSong: ServerSong, in context: ModelContext) async throws -> Bool {
        let existingDescriptor = FetchDescriptor<Song>()
        let existingSongs = try context.fetch(existingDescriptor)
        
        return existingSongs.contains { existingSong in
            existingSong.title.lowercased() == serverSong.title.lowercased() &&
                existingSong.artist.lowercased() == serverSong.artist.lowercased()
        }
    }
    
    /// Create a new Song object from server song data
    private func createSong(from serverSong: ServerSong) -> Song {
        return Song(
            title: serverSong.title,
            artist: serverSong.artist,
            bpm: serverSong.bpm, // Preserve Double precision (e.g., 165.55)
            duration: "3:30", // Will be updated after parsing first chart
            genre: "DTX Import",
            timeSignature: .fourFour
        )
    }
    
    /// Process all charts for a song
    private func processCharts(for song: Song, from serverSong: ServerSong, in context: ModelContext) async throws {
        for (index, serverChart) in serverSong.charts.enumerated() {
            // Add small delay between downloads to reduce system stress
            if index > 0 {
                try await Task.sleep(nanoseconds: 100_000_000) // 100ms delay
            }
            
            try await processChart(serverChart, for: song, from: serverSong, in: context)
        }
    }
    
    /// Process a single chart
    private func processChart(
        _ serverChart: ServerChart,
        for song: Song,
        from serverSong: ServerSong,
        in context: ModelContext
    ) async throws {
        let fileData = try await apiClient.downloadChartFile(
            songId: serverSong.songId,
            chartFilename: serverChart.filename
        )
        
        guard let dtxContent = String(data: fileData, encoding: .shiftJIS) else {
            Logger.debug("Failed to decode \(serverChart.filename) with Shift-JIS encoding")
            return
        }
        
        let chartData = try DTXFileParser.parseChartMetadata(from: dtxContent)
        
        // Update song BPM from the first chart if not already set
        if song.charts.isEmpty {
            song.bpm = chartData.bpm // Preserve Double precision (e.g., 165.55)
            song.duration = formatDuration(calculateDuration(from: chartData.notes))
        }
        
        // Create and populate chart
        let difficulty = mapServerDifficultyToApp(serverChart.difficulty)
        let chart = Chart(difficulty: difficulty, level: serverChart.level, song: song)
        
        let notes = chartData.toNotes(for: chart)
        notes.forEach { note in
            chart.notes.append(note)
        }
        
        context.insert(chart)
    }
    
    /// Download optional BGM and preview files
    private func downloadOptionalFiles(for song: Song, serverSong: ServerSong) async {
        // Download BGM file if available
        do {
            let bgmData = try await apiClient.downloadBGMFile(songId: serverSong.songId)
            let bgmPath = try fileManager.saveBGMFile(bgmData, for: serverSong.songId)
            song.bgmFilePath = bgmPath
            Logger.database("Downloaded BGM file for song: \(song.title)")
        } catch {
            Logger.database("Failed to download BGM for song \(song.title): \(error.localizedDescription)")
        }
        
        // Download preview file if available
        do {
            let previewData = try await apiClient.downloadPreviewFile(songId: serverSong.songId)
            let previewPath = try fileManager.savePreviewFile(previewData, for: serverSong.songId)
            song.previewFilePath = previewPath
            Logger.database("Downloaded preview file for song: \(song.title)")
        } catch {
            Logger.database("Failed to download preview for song \(song.title): \(error.localizedDescription)")
        }
    }

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
