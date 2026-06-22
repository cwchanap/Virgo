import Testing
import Foundation
@testable import Virgo

@Suite("ServerSongFileManager Tests", .serialized)
@MainActor
struct ServerSongFileManagerTests {
    @Test("saveBGMFile writes file and deleteBGMFile removes it")
    func testSaveAndDeleteBGMFile() throws {
        let fileManager = ServerSongFileManager()
        let songId = "bgm-test-\(UUID().uuidString)"
        let payload = Data("bgm-payload".utf8)

        let savedPath = try fileManager.saveBGMFile(payload, for: songId)

        #expect(savedPath.hasSuffix("/BGM/\(songId).ogg"))
        #expect(FileManager.default.fileExists(atPath: savedPath))

        let loadedData = try Data(contentsOf: URL(fileURLWithPath: savedPath))
        #expect(loadedData == payload)

        fileManager.deleteBGMFile(at: savedPath)
        #expect(!FileManager.default.fileExists(atPath: savedPath))
    }

    @Test("savePreviewFile writes file and deletePreviewFile removes it")
    func testSaveAndDeletePreviewFile() throws {
        let fileManager = ServerSongFileManager()
        let songId = "preview-test-\(UUID().uuidString)"
        let payload = Data("preview-payload".utf8)

        let savedPath = try fileManager.savePreviewFile(payload, for: songId)

        #expect(savedPath.hasSuffix("/Preview/\(songId).mp3"))
        #expect(FileManager.default.fileExists(atPath: savedPath))

        let loadedData = try Data(contentsOf: URL(fileURLWithPath: savedPath))
        #expect(loadedData == payload)

        fileManager.deletePreviewFile(at: savedPath)
        #expect(!FileManager.default.fileExists(atPath: savedPath))
    }

    @Test("delete methods tolerate non-existent paths")
    func testDeleteOnNonExistentPaths() {
        let fileManager = ServerSongFileManager()
        let missingBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("virgo-missing-\(UUID().uuidString)")

        fileManager.deleteBGMFile(at: missingBase.appendingPathComponent("bgm.ogg").path)
        fileManager.deletePreviewFile(at: missingBase.appendingPathComponent("preview.mp3").path)

        #expect(true)
    }

    @Test("Deletes BGM and preview by songId")
    func testDeleteBySongId() throws {
        let manager = ServerSongFileManager()
        let bgm = try manager.saveBGMFile(Data([1, 2, 3]), for: "del-test")
        let preview = try manager.savePreviewFile(Data([4, 5, 6]), for: "del-test")
        #expect(FileManager.default.fileExists(atPath: bgm))
        #expect(FileManager.default.fileExists(atPath: preview))

        manager.deleteFiles(forSongId: "del-test")

        #expect(!FileManager.default.fileExists(atPath: bgm))
        #expect(!FileManager.default.fileExists(atPath: preview))
    }

    @Test("deleteFile(at:label:) removes any file at the given path")
    func testDeleteFileGeneric() throws {
        let fileManager = ServerSongFileManager()
        let songId = "generic-delete-\(UUID().uuidString)"
        let savedPath = try fileManager.saveBGMFile(Data("payload".utf8), for: songId)
        #expect(FileManager.default.fileExists(atPath: savedPath))

        fileManager.deleteFile(at: savedPath, label: "audio")
        #expect(!FileManager.default.fileExists(atPath: savedPath))
    }

    @Test("deleteFile(at:label:) tolerates non-existent paths")
    func testDeleteFileGenericNonExistent() {
        let fileManager = ServerSongFileManager()
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("virgo-missing-\(UUID().uuidString)").path

        fileManager.deleteFile(at: missing, label: "audio")
        #expect(true)
    }

    @Test("deleteFile(at:label:) refuses to delete files inside the app bundle")
    func testDeleteFileSkipsBundlePaths() throws {
        // Treat a throwaway temp directory as the "bundle root" so the guard is
        // exercised without mutating the real app bundle. Bundled songs (e.g. the
        // demo Soukyuu fixture) record audio paths that resolve into Bundle.main;
        // deleting those would corrupt the bundle on writable macOS/dev builds.
        let bundleRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("virgo-test-bundle-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: bundleRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: bundleRoot) }

        let bundleAudio = bundleRoot.appendingPathComponent("bgm.m4a")
        try Data("bundle-audio".utf8).write(to: bundleAudio)
        #expect(FileManager.default.fileExists(atPath: bundleAudio.path))

        let manager = ServerSongFileManager(bundleRootURL: bundleRoot)
        manager.deleteFile(at: bundleAudio.path, label: "BGM")

        #expect(FileManager.default.fileExists(atPath: bundleAudio.path))
    }

    @Test("deleteFile(at:label:) still deletes user-storage paths when a custom bundle root is set")
    func testDeleteFileStillRemovesNonBundlePaths() throws {
        let bundleRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("virgo-test-bundle-\(UUID().uuidString)", isDirectory: true)
        let externalAudio = FileManager.default.temporaryDirectory
            .appendingPathComponent("virgo-external-\(UUID().uuidString).m4a")
        try Data("external".utf8).write(to: externalAudio)
        defer { try? FileManager.default.removeItem(at: externalAudio) }

        let manager = ServerSongFileManager(bundleRootURL: bundleRoot)
        manager.deleteFile(at: externalAudio.path, label: "BGM")

        #expect(!FileManager.default.fileExists(atPath: externalAudio.path))
    }

    @Test("isPath(_:inside:) matches nested bundle resources but not sibling apps")
    func testIsPathInsideBundle() {
        let bundleRoot = URL(fileURLWithPath: "/Applications/Virgo.app")

        // Resource nested under the bundle.
        #expect(ServerSongFileManager.isPath(
            "/Applications/Virgo.app/Contents/Resources/bgm.m4a", inside: bundleRoot))
        // Sibling whose name shares a prefix component must NOT match.
        #expect(!ServerSongFileManager.isPath(
            "/Applications/Virgo.app.other/Contents/Resources/bgm.m4a", inside: bundleRoot))
        // Path outside the bundle entirely.
        #expect(!ServerSongFileManager.isPath(
            "/Users/u/Documents/BGM/song.ogg", inside: bundleRoot))
        // The bundle root itself.
        #expect(ServerSongFileManager.isPath("/Applications/Virgo.app", inside: bundleRoot))
    }
}
