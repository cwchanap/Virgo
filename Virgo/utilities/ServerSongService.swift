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
        guard let container = await MainActor.run({ self.modelContext?.container }) else {
            await MainActor.run { self.errorMessage = "No model context available" }
            return false
        }
        
        let success = await statusManager.deleteLocalSong(song, container: container)
        if !success {
            await MainActor.run {
                self.errorMessage = "Failed to delete song"
            }
        }
        
        return success
    }
    
    @MainActor
    private func refreshDownloadStatus() async {
        guard let modelContext = modelContext else { return }
        await statusManager.refreshDownloadStatus(modelContext: modelContext)
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
