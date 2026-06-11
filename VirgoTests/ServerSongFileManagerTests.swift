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
}
