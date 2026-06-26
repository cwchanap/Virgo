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

            // Only delete songs that match the server song identity AND were imported from the server.
            // Prefer stable serverSongId match; fall back to title/artist for legacy data.
            // This prevents deleting sample data or other local songs.
            let songsToDelete = allSongs.filter { song in
                song.isServerImported && matchesServerSong(song, serverSong: serverSong)
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
        let songTitle = song.title.lowercased()
        let songArtist = song.artist.lowercased()
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

                backgroundContext.delete(songToDelete)

                _ = try Self.updateServerSongStatus(
                    songTitle: songTitle,
                    songArtist: songArtist,
                    songServerSongId: songServerSongId,
                    songId: songId,
                    context: backgroundContext
                )

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

            // Build lookup dictionaries keyed by serverSongId and (title, artist)
            // for O(N+M) instead of O(N×M).
            let serverImported = localSongs.filter(\.isServerImported)
            var byServerSongId: [String: [Song]] = [:]
            var byTitleArtist: [String: [Song]] = [:]
            for song in serverImported {
                if let serverId = song.serverSongId {
                    byServerSongId[serverId, default: []].append(song)
                }
                let key = "\(song.title.lowercased())|\(song.artist.lowercased())"
                byTitleArtist[key, default: []].append(song)
            }

            var hasUpdates = false
            for serverSong in allServerSongs {
                let matched = matchedLocalSongs(for: serverSong, byServerSongId: byServerSongId, byTitleArtist: byTitleArtist)
                let isDownloaded = !matched.isEmpty
                let bgmDownloaded = matched.contains { $0.bgmFilePath != nil }
                let previewDownloaded = matched.contains { $0.previewFilePath != nil }

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
            modelContext.rollback()
            Logger.error("Failed to refresh download status: \(error)")
        }
    }

    /// Remove a cached server song that is no longer on the server: delete any
    /// downloaded local Song + files for the same title/artist, then delete the
    /// ServerSong/ServerChart records and the by-songId audio files.
    @MainActor
    func pruneCachedSong(_ serverSong: ServerSong, modelContext: ModelContext) async {
        let songId = serverSong.songId

        // Derive from local database rather than relying on the potentially-stale
        // `isDownloaded` flag.  During `refreshCatalog`, pruning runs BEFORE
        // `refreshDownloadStatus`, so the flag may not reflect reality yet.
        let hasLocalSong: Bool
        do {
            let localSongs = try modelContext.fetch(FetchDescriptor<Song>())
            hasLocalSong = isAlreadyDownloaded(serverSong, in: localSongs)
        } catch {
            Logger.error("Prune: failed to query local songs, assuming none: \(error)")
            hasLocalSong = false
        }

        if serverSong.isDownloaded || hasLocalSong {
            let deleted = await deleteDownloadedSong(serverSong, modelContext: modelContext)
            guard deleted else {
                // If we can't clean up the downloaded local song, abort the prune
                // to avoid orphaning the local Song + audio files.
                Logger.error("Prune aborted: failed to delete downloaded song \(serverSong.title)")
                return
            }
        }

        modelContext.delete(serverSong)
        do {
            try saveContext(modelContext)
        } catch {
            modelContext.rollback()
            Logger.error("Failed to persist pruned song deletion: \(error)")
            return
        }
        fileManager.deleteFiles(forSongId: songId)
    }

    // MARK: - Private Helper Methods (instance wrappers delegating to static)

    /// Find a song by ID in the given context
    private func findSongInContext(songId: PersistentIdentifier, context: ModelContext) throws -> Song? {
        try Self.findSongInContext(songId: songId, context: context)
    }

    /// Delete associated BGM and preview files for a song
    private func deleteAssociatedFiles(bgmPath: String?, previewPath: String?) {
        Self.deleteAssociatedFiles(bgmPath: bgmPath, previewPath: previewPath, fileManager: fileManager)
    }

    /// Update server song download status after local song deletion
    private func updateServerSongStatus(
        songTitle: String,
        songArtist: String,
        songServerSongId: String?,
        songId: PersistentIdentifier,
        context: ModelContext
    ) throws -> Bool {
        try Self.updateServerSongStatus(
            songTitle: songTitle,
            songArtist: songArtist,
            songServerSongId: songServerSongId,
            songId: songId,
            context: context
        )
    }

    /// Check if there are other server-imported songs with the same identity
    private func checkForOtherMatchingSongs(
        songTitle: String,
        songArtist: String,
        songServerSongId: String?,
        excludingSongId: PersistentIdentifier,
        context: ModelContext
    ) throws -> Bool {
        try Self.checkForOtherMatchingSongs(
            songTitle: songTitle,
            songArtist: songArtist,
            songServerSongId: songServerSongId,
            excludingSongId: excludingSongId,
            context: context
        )
    }

    private func isAlreadyDownloaded(_ serverSong: ServerSong, in localSongs: [Song]) -> Bool {
        return localSongs.contains { localSong in
            // Only match server-imported songs to avoid false positives from
            // local/sample songs that share the same title and artist.
            localSong.isServerImported && matchesServerSong(localSong, serverSong: serverSong)
        }
    }

    private func hasBGMFile(_ serverSong: ServerSong, in localSongs: [Song]) -> Bool {
        return localSongs.contains { localSong in
            // Only match server-imported songs to avoid false positives from
            // local/sample songs that share the same title and artist.
            localSong.isServerImported &&
                matchesServerSong(localSong, serverSong: serverSong) &&
                localSong.bgmFilePath != nil
        }
    }

    private func hasPreviewFile(_ serverSong: ServerSong, in localSongs: [Song]) -> Bool {
        return localSongs.contains { localSong in
            // Only match server-imported songs to avoid false positives from
            // local/sample songs that share the same title and artist.
            localSong.isServerImported &&
                matchesServerSong(localSong, serverSong: serverSong) &&
                localSong.previewFilePath != nil
        }
    }

    // MARK: - Identity Matching Helpers

    /// Find matching local songs for a ServerSong using pre-built lookup dicts.
    /// Preserves original matching semantics: songs WITH a serverSongId only match
    /// via that ID; only legacy songs (no serverSongId) fall back to title/artist.
    private func matchedLocalSongs(
        for serverSong: ServerSong,
        byServerSongId: [String: [Song]],
        byTitleArtist: [String: [Song]]
    ) -> [Song] {
        if let matched = byServerSongId[serverSong.songId], !matched.isEmpty {
            return matched
        }
        // Title/artist fallback only returns songs WITHOUT a serverSongId
        // (legacy songs). Songs with a serverSongId must only match via that ID.
        let key = "\(serverSong.title.lowercased())|\(serverSong.artist.lowercased())"
        return (byTitleArtist[key] ?? []).filter { $0.serverSongId == nil }
    }

    /// Match a local Song to a ServerSong, preferring stable serverSongId when available.
    private func matchesServerSong(_ song: Song, serverSong: ServerSong) -> Bool {
        if let songServerId = song.serverSongId {
            return songServerId == serverSong.songId
        }
        // Legacy fallback for songs imported before serverSongId was added
        return song.title.lowercased() == serverSong.title.lowercased() &&
            song.artist.lowercased() == serverSong.artist.lowercased()
    }

    /// Match a local Song to title/artist/serverSongId tuple.
    private func matchesSongIdentity(
        song: Song,
        songTitle: String,
        songArtist: String,
        songServerSongId: String?
    ) -> Bool {
        Self.matchesSongIdentity(song: song, songTitle: songTitle, songArtist: songArtist, songServerSongId: songServerSongId)
    }

    /// Match a ServerSong to serverSongId/title/artist tuple.
    private func matchesServerSongByServerSongId(
        serverSongId: String,
        songServerSongId: String?,
        serverSongTitle: String,
        serverSongArtist: String,
        songTitle: String,
        songArtist: String
    ) -> Bool {
        Self.matchesServerSongByServerSongId(
            serverSongId: serverSongId,
            songServerSongId: songServerSongId,
            serverSongTitle: serverSongTitle,
            serverSongArtist: serverSongArtist,
            songTitle: songTitle,
            songArtist: songArtist
        )
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

    private static func updateServerSongStatus(
        songTitle: String,
        songArtist: String,
        songServerSongId: String?,
        songId: PersistentIdentifier,
        context: ModelContext
    ) throws -> Bool {
        let allServerSongs = try context.fetch(FetchDescriptor<ServerSong>())

        var hasUpdates = false
        for serverSong in allServerSongs {
            let matchesServerSong = matchesServerSongByServerSongId(
                serverSongId: serverSong.songId,
                songServerSongId: songServerSongId,
                serverSongTitle: serverSong.title,
                serverSongArtist: serverSong.artist,
                songTitle: songTitle,
                songArtist: songArtist
            )

            if matchesServerSong && serverSong.isDownloaded {
                let hasOtherMatchingSongs = try checkForOtherMatchingSongs(
                    songTitle: songTitle,
                    songArtist: songArtist,
                    songServerSongId: songServerSongId,
                    excludingSongId: songId,
                    context: context
                )

                if !hasOtherMatchingSongs {
                    serverSong.isDownloaded = false
                    serverSong.bgmDownloaded = false
                    serverSong.previewDownloaded = false
                    hasUpdates = true
                }
            }
        }

        return hasUpdates
    }

    private static func checkForOtherMatchingSongs(
        songTitle: String,
        songArtist: String,
        songServerSongId: String?,
        excludingSongId: PersistentIdentifier,
        context: ModelContext
    ) throws -> Bool {
        let remainingSongs = try context.fetch(FetchDescriptor<Song>())

        return remainingSongs.contains { otherSong in
            otherSong.persistentModelID != excludingSongId &&
                otherSong.isServerImported &&
                matchesSongIdentity(
                    song: otherSong,
                    songTitle: songTitle,
                    songArtist: songArtist,
                    songServerSongId: songServerSongId
                )
        }
    }

    private static func matchesSongIdentity(
        song: Song,
        songTitle: String,
        songArtist: String,
        songServerSongId: String?
    ) -> Bool {
        if let songServerId = song.serverSongId, let targetServerId = songServerSongId {
            return songServerId == targetServerId
        }
        return song.title.lowercased() == songTitle &&
            song.artist.lowercased() == songArtist
    }

    private static func matchesServerSongByServerSongId(
        serverSongId: String,
        songServerSongId: String?,
        serverSongTitle: String,
        serverSongArtist: String,
        songTitle: String,
        songArtist: String
    ) -> Bool {
        if let songServerId = songServerSongId {
            return serverSongId == songServerId
        }
        return serverSongTitle.lowercased() == songTitle &&
            serverSongArtist.lowercased() == songArtist
    }
}
