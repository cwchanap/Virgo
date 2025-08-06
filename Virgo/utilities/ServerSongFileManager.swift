import Foundation

/// Handles BGM and preview file operations for server songs
class ServerSongFileManager {

    /// Save BGM file to local storage
    func saveBGMFile(_ data: Data, for songId: String) throws -> String {
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

    /// Save preview file to local storage
    func savePreviewFile(_ data: Data, for songId: String) throws -> String {
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

    /// Delete BGM file for a song
    func deleteBGMFile(at path: String) {
        try? FileManager.default.removeItem(atPath: path)
        Logger.database("Deleted BGM file at path: \(path)")
    }

    /// Delete preview file for a song
    func deletePreviewFile(at path: String) {
        try? FileManager.default.removeItem(atPath: path)
        Logger.database("Deleted preview file at path: \(path)")
    }
}
