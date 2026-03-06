import Foundation
import SwiftData

/// Manages download and deletion status for server songs
class ServerSongStatusManager {
    private let fileManager: ServerSongFileManager
    private let saveContext: (ModelContext) throws -> Void

    init(
        fileManager: ServerSongFileManager = ServerSongFileManager(),
        saveContext: @escaping (ModelContext) throws -> Void = { context in try context.save() }
    ) {
        self.fileManager = fileManager
        self.saveContext = saveContext
    }

    /// Delete a downloaded server song from local storage
    @MainActor
    func deleteDownloadedSong(_ serverSong: ServerSong, modelContext: ModelContext) async -> Bool {
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

            let associatedFilePaths = songsToDelete.map { song in
                (bgmPath: song.bgmFilePath, previewPath: song.previewFilePath)
            }

            for song in songsToDelete {
                // Delete all charts and their notes (cascade will handle this)
                modelContext.delete(song)
            }

            // Update server song status in the same transaction
            serverSong.isDownloaded = false
            serverSong.bgmDownloaded = false
            serverSong.previewDownloaded = false
            try saveContext(modelContext)

            for filePaths in associatedFilePaths {
                deleteAssociatedFiles(bgmPath: filePaths.bgmPath, previewPath: filePaths.previewPath)
            }

            return true
        } catch {
            modelContext.rollback()
            Logger.debug("Failed to delete song: \(error.localizedDescription)")
            return false
        }
    }

    /// Delete a local song from storage
    func deleteLocalSong(_ song: Song, container: ModelContainer) async -> Bool {
        let songTitle = song.title.lowercased()
        let songArtist = song.artist.lowercased()
        let songId = song.persistentModelID
        let backgroundContext = ModelContext(container)

        return await Task {
            do {
                guard let songToDelete = try findSongInContext(songId: songId, context: backgroundContext) else {
                    return true // Already deleted or not found
                }

                let bgmFilePath = songToDelete.bgmFilePath
                let previewFilePath = songToDelete.previewFilePath

                try deleteSongFromContext(songToDelete, context: backgroundContext)

                _ = try updateServerSongStatus(
                    songTitle: songTitle,
                    songArtist: songArtist,
                    songId: songId,
                    context: backgroundContext
                )

                try saveContext(backgroundContext)
                deleteAssociatedFiles(bgmPath: bgmFilePath, previewPath: previewFilePath)

                return true
            } catch {
                backgroundContext.rollback()
                Logger.debug("Delete error details: \(error)")
                return false
            }
        }.value
    }

    /// Refresh download status for all server songs
    @MainActor
    func refreshDownloadStatus(modelContext: ModelContext) async {
        // Get all local songs and update server song status
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
                try saveContext(modelContext)
            }
        } catch {
            Logger.debug("Failed to refresh download status: \(error)")
        }
    }

    // MARK: - Private Helper Methods

    /// Find a song by ID in the given context
    private func findSongInContext(songId: PersistentIdentifier, context: ModelContext) throws -> Song? {
        let songDescriptor = FetchDescriptor<Song>(predicate: #Predicate<Song> { songModel in
            songModel.persistentModelID == songId
        })
        let songs = try context.fetch(songDescriptor)

        guard let songToDelete = songs.first else {
            Logger.debug("Song not found in background context")
            return nil
        }

        return songToDelete
    }

    /// Delete associated BGM and preview files for a song
    private func deleteAssociatedFiles(bgmPath: String?, previewPath: String?) {
        if let bgmPath {
            fileManager.deleteBGMFile(at: bgmPath)
        }

        if let previewPath {
            fileManager.deletePreviewFile(at: previewPath)
        }
    }

    /// Delete song from context
    private func deleteSongFromContext(_ song: Song, context: ModelContext) throws {
        context.delete(song)
    }

    /// Update server song download status after local song deletion
    private func updateServerSongStatus(
        songTitle: String,
        songArtist: String,
        songId: PersistentIdentifier,
        context: ModelContext
    ) throws -> Bool {
        let serverSongsDescriptor = FetchDescriptor<ServerSong>()
        let allServerSongs = try context.fetch(serverSongsDescriptor)

        var hasUpdates = false
        for serverSong in allServerSongs {
            if serverSong.title.lowercased() == songTitle &&
                serverSong.artist.lowercased() == songArtist &&
                serverSong.isDownloaded {

                let hasOtherMatchingSongs = try checkForOtherMatchingSongs(
                    songTitle: songTitle,
                    songArtist: songArtist,
                    excludingSongId: songId,
                    context: context
                )

                if !hasOtherMatchingSongs {
                    serverSong.isDownloaded = false
                    hasUpdates = true
                }
            }
        }

        return hasUpdates
    }

    /// Check if there are other DTX Import songs with the same title/artist
    private func checkForOtherMatchingSongs(
        songTitle: String,
        songArtist: String,
        excludingSongId: PersistentIdentifier,
        context: ModelContext
    ) throws -> Bool {
        let songsDescriptor = FetchDescriptor<Song>()
        let remainingSongs = try context.fetch(songsDescriptor)

        return remainingSongs.contains { otherSong in
            otherSong.persistentModelID != excludingSongId &&
                otherSong.title.lowercased() == songTitle &&
                otherSong.artist.lowercased() == songArtist &&
                otherSong.genre == "DTX Import"
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
