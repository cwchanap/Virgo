import Foundation

/// Handles BGM and preview file operations for server songs
class ServerSongFileManager: @unchecked Sendable {

    /// Root URL of the app bundle. Paths inside this tree are read-only app
    /// resources and must never be deleted. Defaults to `Bundle.main.bundleURL`;
    /// injectable so the guard is unit-testable without mutating the real bundle.
    private let bundleRootURL: URL

    init(bundleRootURL: URL = Bundle.main.bundleURL) {
        self.bundleRootURL = bundleRootURL
    }

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
    ///
    /// Guards against paths inside the app bundle: bundled songs (e.g. the demo
    /// Soukyuu fixture) record `bgmFilePath`/`previewFilePath` that point directly
    /// into `Bundle.main` resources. Deleting those would either throw sandbox
    /// errors on read-only iOS bundles or — worse — actually remove the audio
    /// from writable macOS/dev bundles, so a later re-import comes back without
    /// BGM/preview. Bundle resources are app assets, not user-managed storage.
    func deleteFile(at path: String, label: String = "file") {
        if Self.isPath(path, inside: bundleRootURL) {
            Logger.database("Skipping \(label) deletion — path is inside app bundle: \(path)")
            return
        }
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

    /// Returns true when `path` is the bundle root itself or lives anywhere beneath it.
    /// Uses standardized absolute paths and a trailing-slash prefix match so a bundle
    /// at `/X.app` cannot accidentally match `/X.app.other/file`.
    static func isPath(_ path: String, inside root: URL) -> Bool {
        let rootPath = root.standardizedFileURL.path
        let targetPath = URL(fileURLWithPath: path).standardizedFileURL.path
        return targetPath == rootPath || targetPath.hasPrefix(rootPath + "/")
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
