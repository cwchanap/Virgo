import Foundation
import SwiftData

/// Manages download and deletion status for server songs
class ServerSongStatusManager: @unchecked Sendable {
    private let fileManager: ServerSongFileManager
    private let saveContext: @Sendable (ModelContext) throws -> Void
    private let deletionStore: BundledFixtureDeletionStore

    init(
        fileManager: ServerSongFileManager = ServerSongFileManager(),
        saveContext: @escaping @Sendable (ModelContext) throws -> Void = { context in try context.save() },
        // Defaults to the production `.standard`-backed store. Injectable so tests
        // (and any future non-standard caller) can route the bundled-fixture
        // tombstone through an isolated `UserDefaults` suite instead of polluting
        // `UserDefaults.standard`, and so the delete→record wiring is assertable.
        deletionStore: BundledFixtureDeletionStore = .standard
    ) {
        self.fileManager = fileManager
        self.saveContext = saveContext
        self.deletionStore = deletionStore
    }

    /// Delete a downloaded server song from local storage
    @MainActor
    func deleteDownloadedSong(_ serverSong: ServerSong, modelContext: ModelContext) async -> Bool {
        do {
            // Get all songs and filter manually for better compatibility
            let descriptor = FetchDescriptor<Song>()
            let allSongs = try modelContext.fetch(descriptor)

            // Only delete songs that carry this exact server identity and were imported
            // from the server. This prevents deleting sample data or another server
            // song that happens to share the same title and artist.
            let songsToDelete = allSongs.filter { song in
                song.isServerImported && song.serverSongId == serverSong.songId
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
            Logger.error("Failed to delete song: \(error.localizedDescription)")
            return false
        }
    }

    /// Delete a local song from storage
    @MainActor
    func deleteLocalSong(_ song: Song, container: ModelContainer) async -> Bool {
        let songServerSongId = song.serverSongId
        let songId = song.persistentModelID
        // Capture immutable dependencies to avoid capturing `self` in detached task.
        let fileManager = self.fileManager
        let saveContext = self.saveContext
        let deletionStore = self.deletionStore

        return await Task.detached {
            let backgroundContext = ModelContext(container)
            do {
                guard let songToDelete = try Self.findSongInContext(songId: songId, context: backgroundContext) else {
                    return true // Already deleted or not found
                }

                let bgmFilePath = songToDelete.bgmFilePath
                let previewFilePath = songToDelete.previewFilePath

                // Only delete the durable local Song here. The server cache
                // status flags are reconciled exclusively by the caller's
                // post-success `refreshDownloadStatus()` on the main context.
                // Mutating cache rows in this detached context raced with
                // `refreshCatalog`'s cache replacement: a stale cache write
                // could fail the combined save and roll back the Song deletion.
                backgroundContext.delete(songToDelete)

                try saveContext(backgroundContext)

                // Record the user's intent to remove a bundled demo song so the
                // startup seed path does not recreate it on the next launch.
                // `recordIfBundled` ignores non-bundled ids (e.g. server-downloaded
                // songs), so this is a no-op for the normal server-download delete.
                // Uses the injected store so tests isolate the tombstone to a unique
                // UserDefaults suite rather than writing to `UserDefaults.standard`.
                deletionStore.recordIfBundled(songId: songServerSongId)

                Self.deleteAssociatedFiles(
                    bgmPath: bgmFilePath, previewPath: previewFilePath, fileManager: fileManager
                )

                return true
            } catch {
                backgroundContext.rollback()
                Logger.error("Delete error details: \(error)")
                return false
            }
        }.value
    }

    /// Refresh download status for all server songs
    @MainActor
    func refreshDownloadStatus(modelContext: ModelContext) async {
        do {
            let localSongs = try modelContext.fetch(FetchDescriptor<Song>())
            let allServerSongs = try modelContext.fetch(FetchDescriptor<ServerSong>())
            if applyDownloadStatus(to: allServerSongs, from: localSongs) {
                try saveContext(modelContext)
            }
        } catch {
            modelContext.rollback()
            Logger.error("Failed to refresh download status: \(error)")
        }
    }

    /// Delete associated BGM and preview files for a song
    private func deleteAssociatedFiles(bgmPath: String?, previewPath: String?) {
        Self.deleteAssociatedFiles(bgmPath: bgmPath, previewPath: previewPath, fileManager: fileManager)
    }

    /// Project local server-imported rows onto the cached server status flags.
    @MainActor
    @discardableResult
    func applyDownloadStatus(
        to serverSongs: [ServerSong],
        from localSongs: [Song]
    ) -> Bool {
        var localByServerSongID: [String: [Song]] = [:]
        for song in localSongs where song.isServerImported {
            guard let serverSongId = song.serverSongId else { continue }
            localByServerSongID[serverSongId, default: []].append(song)
        }

        var changed = false
        for serverSong in serverSongs {
            let matched = localByServerSongID[serverSong.songId] ?? []
            let isDownloaded = !matched.isEmpty
            let bgmDownloaded = matched.contains { $0.bgmFilePath != nil }
            let previewDownloaded = matched.contains { $0.previewFilePath != nil }

            if serverSong.isDownloaded != isDownloaded {
                serverSong.isDownloaded = isDownloaded
                changed = true
            }
            if serverSong.bgmDownloaded != bgmDownloaded {
                serverSong.bgmDownloaded = bgmDownloaded
                changed = true
            }
            if serverSong.previewDownloaded != previewDownloaded {
                serverSong.previewDownloaded = previewDownloaded
                changed = true
            }
        }
        return changed
    }

    // MARK: - Static Helpers (single source of truth; safe for Task.detached)

    private static func findSongInContext(songId: PersistentIdentifier, context: ModelContext) throws -> Song? {
        let songDescriptor = FetchDescriptor<Song>(predicate: #Predicate<Song> { songModel in
            songModel.persistentModelID == songId
        })
        let songs = try context.fetch(songDescriptor)

        guard let songToDelete = songs.first else {
            Logger.warning("Song not found in background context")
            return nil
        }

        return songToDelete
    }

    private static func deleteAssociatedFiles(
        bgmPath: String?,
        previewPath: String?,
        fileManager: ServerSongFileManager
    ) {
        if let bgmPath {
            fileManager.deleteFile(at: bgmPath, label: "BGM")
        }
        if let previewPath {
            fileManager.deleteFile(at: previewPath, label: "preview")
        }
    }
}
