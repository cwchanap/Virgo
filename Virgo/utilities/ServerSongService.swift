import Foundation
import SwiftData

class ServerSongService: ObservableObject {
    @MainActor @Published var isLoading = false
    @MainActor @Published var isRefreshing = false
    @MainActor @Published var errorMessage: String?
    @MainActor @Published var downloadingSongs: Set<String> = []
    @MainActor @Published var deletingSongs: Set<String> = []
    
    private var modelContext: ModelContext?
    private let cache = ServerSongCache()
    private let downloader = ServerSongDownloader()
    private let statusManager = ServerSongStatusManager()
    
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }
    
    // MARK: - Public API
    
    @MainActor
    func loadServerSongs() async -> [ServerSong] {
        guard let modelContext = modelContext else { return [] }
        do {
            return try await cache.loadServerSongs(modelContext: modelContext)
        } catch {
            print("Failed to load server songs: \(error)")
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
    
    @MainActor
    private func refreshServerSongs(forceClear: Bool = false) async {
        guard let modelContext = modelContext else { return }
        
        isRefreshing = true
        errorMessage = nil
        
        do {
            try await cache.refreshServerSongs(modelContext: modelContext, forceClear: forceClear)
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
        
        // Get container for background context
        let container = await MainActor.run { self.modelContext?.container }
        guard let container = container else {
            await MainActor.run {
                downloadingSongs.remove(songId)
                errorMessage = "No model context available"
            }
            return false
        }
        
        // Perform download work on background thread
        let (success, errorMsg) = await downloader.downloadAndImportSong(serverSong, container: container)
        
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
    
    @MainActor
    func deleteDownloadedSong(_ serverSong: ServerSong) async -> Bool {
        guard let modelContext = modelContext else { return false }
        
        let success = await statusManager.deleteDownloadedSong(serverSong, modelContext: modelContext)
        if !success {
            errorMessage = "Failed to delete downloaded song"
        }
        return success
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
        
        // Get container for background context
        let container = await MainActor.run { self.modelContext?.container }
        guard let container = container else {
            await MainActor.run {
                deletingSongs.remove(songKey)
                errorMessage = "No model context available"
            }
            return false
        }
        
        // Perform deletion work on background thread
        let success = await statusManager.deleteLocalSong(song, container: container)
        
        // Remove from deleting set on main thread
        await MainActor.run {
            deletingSongs.remove(songKey)
            if !success {
                errorMessage = "Failed to delete local song"
            }
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
