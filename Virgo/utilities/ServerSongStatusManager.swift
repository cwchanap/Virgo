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
                    fileManager.deleteBGMFile(at: bgmPath)
                }
                
                // Delete preview file if it exists
                if let previewPath = songToDelete.previewFilePath {
                    fileManager.deletePreviewFile(at: previewPath)
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