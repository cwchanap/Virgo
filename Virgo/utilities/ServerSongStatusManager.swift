import Foundation
import SwiftData

/// Manages download and deletion status for server songs
class ServerSongStatusManager {
    private let fileManager = ServerSongFileManager()
    
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
            
            for song in songsToDelete {
                // Delete all charts and their notes (cascade will handle this)
                modelContext.delete(song)
            }
            
            try modelContext.save()
            
            // Update server song status
            serverSong.isDownloaded = false
            
            return true
        } catch {
            print("Failed to delete song: \(error.localizedDescription)")
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
                
                deleteAssociatedFiles(for: songToDelete)
                deleteSongFromContext(songToDelete, context: backgroundContext)
                
                let hasUpdates = try updateServerSongStatus(
                    songTitle: songTitle,
                    songArtist: songArtist,
                    songId: songId,
                    context: backgroundContext
                )
                
                if hasUpdates {
                    try backgroundContext.save()
                }
                
                return true
            } catch {
                print("DEBUG: Delete error details: \(error)")
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
                try modelContext.save()
            }
        } catch {
            print("Failed to refresh download status: \(error)")
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
            print("DEBUG: Song not found in background context")
            return nil
        }
        
        guard !songToDelete.isDeleted else {
            print("DEBUG: Song is already deleted")
            return nil
        }
        
        return songToDelete
    }
    
    /// Delete associated BGM and preview files for a song
    private func deleteAssociatedFiles(for song: Song) {
        if let bgmPath = song.bgmFilePath {
            fileManager.deleteBGMFile(at: bgmPath)
        }
        
        if let previewPath = song.previewFilePath {
            fileManager.deletePreviewFile(at: previewPath)
        }
    }
    
    /// Delete song from context and save
    private func deleteSongFromContext(_ song: Song, context: ModelContext) throws {
        context.delete(song)
        try context.save()
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