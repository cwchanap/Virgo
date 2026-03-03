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
}
