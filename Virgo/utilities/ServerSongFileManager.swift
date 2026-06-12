import Foundation

/// Handles BGM and preview file operations for server songs
class ServerSongFileManager: @unchecked Sendable {

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

    /// Delete a file at the given path with a descriptive label for logging.
    /// Idempotent: missing-file errors are treated as a no-op rather than an error.
    func deleteFile(at path: String, label: String = "file") {
        do {
            try FileManager.default.removeItem(atPath: path)
            Logger.database("Deleted \(label) file at path: \(path)")
        } catch let error as NSError where error.domain == NSCocoaErrorDomain
                    && error.code == NSFileNoSuchFileError {
            Logger.database("\(label) file already absent at path: \(path)")
        } catch {
            Logger.error("Failed to delete \(label) file at \(path): \(error.localizedDescription)")
        }
    }

    /// Delete BGM file for a song
    func deleteBGMFile(at path: String) {
        deleteFile(at: path, label: "BGM")
    }

    /// Delete preview file for a song
    func deletePreviewFile(at path: String) {
        deleteFile(at: path, label: "preview")
    }

    /// Delete BGM and preview files saved under this songId, if present.
    func deleteFiles(forSongId songId: String) {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let bgm = documents.appendingPathComponent("BGM").appendingPathComponent("\(songId).ogg")
        let preview = documents.appendingPathComponent("Preview").appendingPathComponent("\(songId).mp3")

        deleteFile(at: bgm.path, label: "BGM for songId \(songId)")
        deleteFile(at: preview.path, label: "preview for songId \(songId)")
    }
}
