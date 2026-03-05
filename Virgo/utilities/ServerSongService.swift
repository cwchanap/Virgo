import Foundation
import SwiftData

@MainActor
class ServerSongService: ObservableObject {
    @Published var isLoading = false
    @Published var isRefreshing = false
    @Published var errorMessage: String?
    @Published var downloadingSongs: Set<String> = []
    @Published var deletingSongs: Set<String> = []

    private var modelContext: ModelContext?
    private let cache: ServerSongCache
    private let downloader: ServerSongDownloader
    private let statusManager: ServerSongStatusManager
    private let saveModelContext: (ModelContext) throws -> Void

    init(
        cache: ServerSongCache = ServerSongCache(),
        downloader: ServerSongDownloader = ServerSongDownloader(),
        statusManager: ServerSongStatusManager? = nil,
        saveModelContext: @escaping (ModelContext) throws -> Void = { context in try context.save() }
    ) {
        self.cache = cache
        self.downloader = downloader
        self.saveModelContext = saveModelContext
        self.statusManager = statusManager ?? ServerSongStatusManager(saveContext: saveModelContext)
    }

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    // MARK: - Public API

    func loadServerSongs() async -> [ServerSong] {
        guard let modelContext = modelContext else { return [] }
        do {
            return try await cache.loadServerSongs(modelContext: modelContext)
        } catch {
            Logger.debug("Failed to load server songs: \(error)")
            return []
        }
    }

    func refreshServerSongs() async {
        await refreshServerSongs(forceClear: false)
    }

    func forceRefreshServerSongs() async {
        await refreshServerSongs(forceClear: true)
    }

    private func refreshServerSongs(forceClear: Bool = false) async {
        guard let modelContext = modelContext else { return }

        isRefreshing = true
        errorMessage = nil

        do {
            try await cache.refreshServerSongs(modelContext: modelContext, forceClear: forceClear)
        } catch {
            errorMessage = "Failed to refresh server songs: \(error.localizedDescription)"
            Logger.debug("Failed to refresh server songs: \(error)")
        }

        isRefreshing = false
    }

    func downloadAndImportSong(_ serverSong: ServerSong) async -> Bool {
        let isAlreadyDownloaded = serverSong.isDownloaded
        let songId = serverSong.songId

        // Check if already downloading to prevent race condition
        let isDownloading = downloadingSongs.contains(songId)
        if isDownloading {
            return false
        }

        // Check if song is already downloaded
        if isAlreadyDownloaded {
            return false
        }

        downloadingSongs.insert(songId)
        errorMessage = nil

        // Get container for background context
        let container = modelContext?.container
        guard let container = container else {
            downloadingSongs.remove(songId)
            errorMessage = "No model context available"
            return false
        }

        // Perform download work on background thread
        let (success, errorMsg) = await downloader.downloadAndImportSong(serverSong, container: container)

        downloadingSongs.remove(songId)
        if !success, let errorMsg = errorMsg {
            errorMessage = errorMsg
        }

        if success {
            serverSong.isDownloaded = true

            // Save the updated status to ensure UI reflects the change
            if let modelContext = modelContext {
                do {
                    try saveModelContext(modelContext)
                } catch {
                    Logger.debug("Failed to save download status: \(error)")
                }
            }

            await refreshDownloadStatus()
        }

        return success
    }

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
        let isAlreadyDeleting = deletingSongs.contains(songKey)
        if isAlreadyDeleting {
            return false
        }

        deletingSongs.insert(songKey)
        errorMessage = nil

        // Get container for background context
        let container = modelContext?.container
        guard let container = container else {
            deletingSongs.remove(songKey)
            errorMessage = "No model context available"
            return false
        }

        // Perform deletion work on background thread
        let success = await statusManager.deleteLocalSong(song, container: container)

        deletingSongs.remove(songKey)
        if !success {
            errorMessage = "Failed to delete local song"
        }

        return success
    }

    private func refreshDownloadStatus() async {
        guard let modelContext = modelContext else { return }
        await statusManager.refreshDownloadStatus(modelContext: modelContext)
    }

    // MARK: - Helper Methods

    func isDownloading(_ serverSong: ServerSong) -> Bool {
        return downloadingSongs.contains(serverSong.songId)
    }

    func isDeleting(_ song: Song) -> Bool {
        let songKey = "\(song.title.lowercased())|\(song.artist.lowercased())"
        return deletingSongs.contains(songKey)
    }
}
