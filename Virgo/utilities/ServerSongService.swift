import Foundation
import SwiftData

class ServerSongService: ObservableObject {
    @MainActor @Published var isLoading = false
    @MainActor @Published var isRefreshing = false
    @MainActor @Published var errorMessage: String?
    @MainActor @Published var downloadingSongs: Set<String> = []
    @MainActor @Published var deletingSongs: Set<String> = []
    
    private let apiClient = DTXAPIClient()
    private var modelContext: ModelContext?
    
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }
    
    // MARK: - Public API
    
    @MainActor
    func loadServerSongs() async -> [ServerSong] {
        guard let modelContext = modelContext else { return [] }
        
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
                await refreshServerSongs(forceClear: false)
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
            print("Failed to load server songs from cache: \(error)")
            return []
        }
    }
    
    @MainActor
    func refreshServerSongs() async {
        await refreshServerSongs(forceClear: false)
    }
    
    @MainActor
    func forceRefreshServerSongs() async {
        await refreshServerSongs(forceClear: true)
    }
    
    // MARK: - Helper Functions
    
    private func clearExistingServerSongs() async throws {
        guard let modelContext = modelContext else { return }
        
        // Use a more robust deletion approach to avoid memory management issues
        let existingDescriptor = FetchDescriptor<ServerSong>()
        let existingSongs = try modelContext.fetch(existingDescriptor)
        
        // Delete in smaller batches to reduce memory pressure
        let batchSize = 10
        for i in stride(from: 0, to: existingSongs.count, by: batchSize) {
            let endIndex = min(i + batchSize, existingSongs.count)
            let batch = Array(existingSongs[i..<endIndex])
            
            for song in batch {
                // Ensure the song is still valid before deletion
                if !song.isDeleted {
                    modelContext.delete(song)
                }
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
    
    private func updateDownloadStatus(_ songs: [ServerSong]) async throws {
        guard let modelContext = modelContext else { return }
        
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
    
    @MainActor
    private func refreshServerSongs(forceClear: Bool = false) async {
        guard let modelContext = modelContext else { return }
        
        isRefreshing = true
        errorMessage = nil
        
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
                        print("Failed to get metadata for \(file.filename): \(error)")
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
            try await updateDownloadStatus(updatedSongs)
            
            // Clear existing server songs and charts
            try await clearExistingServerSongs()
            
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
                print("DEBUG: Error during insertion save: \(error)")
                throw error
            }
            
        } catch {
            errorMessage = "Failed to refresh server songs: \(error.localizedDescription)"
            print("Failed to refresh server songs: \(error)")
        }
        
        isRefreshing = false
    }
    
    func downloadAndImportSong(_ serverSong: ServerSong) async -> Bool {
        // Cache needed values to avoid MainActor calls in background
        let isAlreadyDownloaded = serverSong.isDownloaded
        let songId = serverSong.songId
        
        // Check if already downloading to prevent race condition
        let isDownloading = await MainActor.run { downloadingSongs.contains(songId) }
        if isDownloading {
            return false
        }
        
        // Check if song is already downloaded
        if isAlreadyDownloaded {
            return false
        }
        
        // Update UI state on main thread
        await MainActor.run {
            downloadingSongs.insert(songId)
            errorMessage = nil
        }
        
        // Perform download work on background thread with proper actor isolation
        let (success, errorMsg): (Bool, String?) = await Task { [weak self] in
            guard let self = self else { 
                return (false, "Service unavailable")
            }
            
            // For multi-difficulty songs, download all charts
            if !serverSong.charts.isEmpty {
                return await self.downloadAndImportMultiDifficultySongBackground(serverSong)
            }
            
            // Legacy: single DTX file (for backward compatibility) - should not reach here for multi-difficulty songs
            return (false, "No charts available for legacy download")
        }.value
        
        // Update UI state back on main thread and refresh download status
        await MainActor.run {
            downloadingSongs.remove(songId)
            if !success, let errorMsg = errorMsg {
                errorMessage = errorMsg
            }
        }
        
        if success {
            // Mark the server song as downloaded and refresh the UI - ensure main actor
            await MainActor.run {
                serverSong.isDownloaded = true
                
                // Save the updated status to ensure UI reflects the change
                if let modelContext = modelContext {
                    do {
                        try modelContext.save()
                    } catch {
                        print("Failed to save download status: \(error)")
                    }
                }
            }
            
            await refreshDownloadStatus()
        }
        
        return success
    }
    
    private func downloadAndImportMultiDifficultySong(_ serverSong: ServerSong) async -> Bool {
        // This method now just delegates to the background version
        let (success, _) = await downloadAndImportMultiDifficultySongBackground(serverSong)
        return success
    }
    
    private func downloadAndImportMultiDifficultySongBackground(_ serverSong: ServerSong) async -> (Bool, String?) {
        
        // Get container from main context safely
        let container = await MainActor.run { self.modelContext?.container }
        guard let container = container else {
            return (false, "No model context available")
        }
        
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
                    print("Failed to decode \(serverChart.filename) with Shift-JIS encoding")
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
                let bgmPath = try saveBGMFile(bgmData, for: serverSong.songId)
                song.bgmFilePath = bgmPath
                Logger.database("Downloaded BGM file for song: \(song.title)")
            } catch {
                // BGM download is optional - continue even if it fails
                Logger.database("Failed to download BGM for song \(song.title): \(error.localizedDescription)")
            }
            
            // Download preview file if available
            do {
                let previewData = try await apiClient.downloadPreviewFile(songId: serverSong.songId)
                let previewPath = try savePreviewFile(previewData, for: serverSong.songId)
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
    
    private func saveBGMFile(_ data: Data, for songId: String) throws -> String {
        // Get the Documents directory
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        
        // Create BGM directory if it doesn't exist
        let bgmDirectory = documentsPath.appendingPathComponent("BGM")
        if !FileManager.default.fileExists(atPath: bgmDirectory.path) {
            try FileManager.default.createDirectory(at: bgmDirectory, withIntermediateDirectories: true)
        }
        
        // Save BGM file with song ID as filename
        let bgmFilePath = bgmDirectory.appendingPathComponent("\(songId).ogg")
        try data.write(to: bgmFilePath)
        
        return bgmFilePath.path
    }
    
    private func savePreviewFile(_ data: Data, for songId: String) throws -> String {
        // Get the Documents directory
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        
        // Create Preview directory if it doesn't exist
        let previewDirectory = documentsPath.appendingPathComponent("Preview")
        if !FileManager.default.fileExists(atPath: previewDirectory.path) {
            try FileManager.default.createDirectory(at: previewDirectory, withIntermediateDirectories: true)
        }
        
        // Save preview file with song ID as filename
        let previewFilePath = previewDirectory.appendingPathComponent("\(songId).mp3")
        try data.write(to: previewFilePath)
        
        return previewFilePath.path
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
    
    @MainActor
    func deleteDownloadedSong(_ serverSong: ServerSong) async -> Bool {
        guard let modelContext = modelContext else { return false }
        
        do {
            // Get all songs and filter manually for better compatibility
            let descriptor = FetchDescriptor<Song>()
            let allSongs = try modelContext.fetch(descriptor)
            
            // IMPORTANT: Only delete songs that match title/artist AND are from DTX Import genre
            // This prevents deleting sample data or other local songs
            let songsToDelete = allSongs.filter { song in
                song.title.lowercased() == serverSong.title.lowercased() &&
                song.artist.lowercased() == serverSong.artist.lowercased() &&
                song.genre == "DTX Import" // Only delete downloaded songs, not sample data
            }
            
            for song in songsToDelete {
                // Delete all charts and their notes (cascade will handle this)
                modelContext.delete(song)
            }
            
            try modelContext.save()
            
            // Update server song status
            serverSong.isDownloaded = false
            
            return true
        } catch {
            errorMessage = "Failed to delete song: \(error.localizedDescription)"
            return false
        }
    }
    
    func deleteLocalSong(_ song: Song) async -> Bool {
        // Create song key for tracking deletion state
        let songKey = "\(song.title.lowercased())|\(song.artist.lowercased())"
        
        // Check if already deleting to prevent race condition
        let isAlreadyDeleting = await MainActor.run { deletingSongs.contains(songKey) }
        if isAlreadyDeleting {
            return false
        }
        
        await MainActor.run {
            deletingSongs.insert(songKey)
            errorMessage = nil
        }
        
        // Perform deletion work on background thread
        let success = await performDeletionBackground(song: song, songKey: songKey)
        
        // Remove from deleting set on main thread
        await MainActor.run {
            deletingSongs.remove(songKey)
        }
        
        return success
    }
    
    private func performDeletionBackground(song: Song, songKey: String) async -> Bool {
        // Get container from main context safely
        let container = await MainActor.run { self.modelContext?.container }
        guard let container = container else {
            await MainActor.run { self.errorMessage = "No model context available" }
            return false
        }
        
        // Store song information before deletion for server song matching
        let songTitle = song.title.lowercased()
        let songArtist = song.artist.lowercased()
        let songId = song.persistentModelID
        
        // Create background ModelContext using the same container
        let backgroundContext = ModelContext(container)
        
        return await Task {
            do {
                // Find the song in the background context
                let songDescriptor = FetchDescriptor<Song>(predicate: #Predicate<Song> { songModel in
                    songModel.persistentModelID == songId
                })
                let songs = try backgroundContext.fetch(songDescriptor)
                
                guard let songToDelete = songs.first else {
                    print("DEBUG: Song not found in background context")
                    return true // Already deleted or not found
                }
                
                // Ensure the song is still attached to this context
                guard !songToDelete.isDeleted else {
                    print("DEBUG: Song is already deleted")
                    return true
                }
                
                // Delete BGM file if it exists
                if let bgmPath = songToDelete.bgmFilePath {
                    try? FileManager.default.removeItem(atPath: bgmPath)
                    Logger.database("Deleted BGM file for song: \(songToDelete.title)")
                }
                
                // Delete preview file if it exists
                if let previewPath = songToDelete.previewFilePath {
                    try? FileManager.default.removeItem(atPath: previewPath)
                    Logger.database("Deleted preview file for song: \(songToDelete.title)")
                }
                
                // IMPORTANT: Only delete the specific song, not all songs with same title/artist
                // SwiftData will handle cascade deletion of charts and notes automatically
                backgroundContext.delete(songToDelete)
                try backgroundContext.save()
                
                // Update matching server songs to mark as not downloaded
                // Only update server songs that match title/artist AND are from DTX Import genre
                let serverSongsDescriptor = FetchDescriptor<ServerSong>()
                let allServerSongs = try backgroundContext.fetch(serverSongsDescriptor)
                
                var hasUpdates = false
                for serverSong in allServerSongs {
                    if serverSong.title.lowercased() == songTitle && 
                       serverSong.artist.lowercased() == songArtist &&
                       serverSong.isDownloaded {
                        // Check if there are still other songs with same title/artist before marking as not downloaded
                        let songsDescriptor = FetchDescriptor<Song>()
                        let remainingSongs = try backgroundContext.fetch(songsDescriptor)
                        let hasOtherMatchingSongs = remainingSongs.contains { otherSong in
                            otherSong.persistentModelID != songId &&
                            otherSong.title.lowercased() == songTitle &&
                            otherSong.artist.lowercased() == songArtist &&
                            otherSong.genre == "DTX Import"
                        }
                        
                        // Only mark as not downloaded if no other matching DTX Import songs exist
                        if !hasOtherMatchingSongs {
                            serverSong.isDownloaded = false
                            hasUpdates = true
                        }
                    }
                }
                
                if hasUpdates {
                    try backgroundContext.save()
                }
                
                return true
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to delete song: \(error.localizedDescription)"
                }
                print("DEBUG: Delete error details: \(error)")
                return false
            }
        }.value
    }
    
    @MainActor
    private func refreshDownloadStatus() async {
        // Get all local songs and update server song status
        guard let modelContext = modelContext else { return }
        
        do {
            let localSongsDescriptor = FetchDescriptor<Song>()
            let localSongs = try modelContext.fetch(localSongsDescriptor)
            
            let serverSongsDescriptor = FetchDescriptor<ServerSong>()
            let allServerSongs = try modelContext.fetch(serverSongsDescriptor)
            
            var hasUpdates = false
            for serverSong in allServerSongs {
                let isDownloaded = isAlreadyDownloaded(serverSong, in: localSongs)
                let bgmDownloaded = hasBGMFile(serverSong, in: localSongs)
                let previewDownloaded = hasPreviewFile(serverSong, in: localSongs)
                
                if serverSong.isDownloaded != isDownloaded {
                    serverSong.isDownloaded = isDownloaded
                    hasUpdates = true
                }
                
                if serverSong.bgmDownloaded != bgmDownloaded {
                    serverSong.bgmDownloaded = bgmDownloaded
                    hasUpdates = true
                }
                
                if serverSong.previewDownloaded != previewDownloaded {
                    serverSong.previewDownloaded = previewDownloaded
                    hasUpdates = true
                }
            }
            
            if hasUpdates {
                try modelContext.save()
            }
        } catch {
            print("Failed to refresh download status: \(error)")
        }
    }
    
    // MARK: - Helper Methods
    
    @MainActor
    func isDownloading(_ serverSong: ServerSong) -> Bool {
        return downloadingSongs.contains(serverSong.songId)
    }
    
    @MainActor
    func isDeleting(_ song: Song) -> Bool {
        let songKey = "\(song.title.lowercased())|\(song.artist.lowercased())"
        return deletingSongs.contains(songKey)
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
