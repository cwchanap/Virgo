import Testing
import SwiftData
import Foundation
@testable import Virgo

@Suite("Patch Coverage Tests", .serialized)
@MainActor
struct PatchCoverageTests {

    // MARK: - ServerSongDownloader.decode UTF-8 fallback (lines 74-75)

    @Test("decode falls back to UTF-8 when Shift-JIS decode fails")
    func testDecodeUTF8Fallback() {
        // 0xC2 0x80 is valid UTF-8 (U+0080) but invalid Shift-JIS
        // because 0x80 is an undefined byte in Shift-JIS.
        let data = Data([0xC2, 0x80])
        let result = ServerSongDownloader.decode(data, encoding: "SHIFT_JIS")
        #expect(result != nil)
        #expect(result == String(data: data, encoding: .utf8))
    }

    // MARK: - ServerSongDownloader audio download error path (line 207)

    @Test("download continues successfully when audio download fails")
    func testAudioDownloadFailureIsNonFatal() async throws {
        final class SelectiveFailDownloader: FileDownloading, @unchecked Sendable {
            let dtxData: Data
            init(dtxData: Data) { self.dtxData = dtxData }
            func downloadData(from url: URL) async throws -> Data {
                if url.absoluteString.hasSuffix(".dtx") { return dtxData }
                throw URLError(.fileDoesNotExist)
            }
        }

        final class MockFileManager: ServerSongFileManager {
            var savedBGM = false
            var savedPreview = false
            override func saveBGMFile(_ data: Data, for songId: String) throws -> String {
                savedBGM = true
                return "/tmp/mock.ogg"
            }
            override func savePreviewFile(_ data: Data, for songId: String) throws -> String {
                savedPreview = true
                return "/tmp/mock.mp3"
            }
        }

        let r2Base = "https://r2.example"
        let (defaults, _) = TestUserDefaults.makeIsolated(suiteName: "patch.audio.\(UUID().uuidString)")
        defaults.set(r2Base, forKey: ServerConfig.r2BaseURLKey)
        let config = ServerConfig(userDefaults: defaults)

        let dtxContent = "#TITLE: Audio Fail\n#ARTIST: Tester\n#BPM: 120\n#DLEVEL: 50\n#03113: 01000000"
        let dtx = dtxContent.data(using: .shiftJIS) ?? Data(dtxContent.utf8)
        let downloader = SelectiveFailDownloader(dtxData: dtx)
        let fileManager = MockFileManager()
        let subject = ServerSongDownloader(downloader: downloader, fileManager: fileManager, config: config)

        try await TestSetup.withTestSetup {
            let container = TestContainer.shared.container
            let chart = ServerChart(
                difficulty: "easy", difficultyLabel: "Easy", level: 10,
                filename: "chart.dtx", size: 100,
                fileURL: "\(r2Base)/audio-fail/chart.dtx", fileEncoding: "SHIFT_JIS"
            )
            let serverSong = ServerSong(
                songId: "audio-fail", title: "Audio Fail", artist: "Tester", bpm: 120.0,
                charts: [chart], isDownloaded: false, hasBGM: true, hasPreview: true
            )

            let (success, errorMessage) = await subject.downloadAndImportSong(serverSong, container: container)
            #expect(success, "Import should succeed even when audio download fails")
            #expect(errorMessage == nil)
            #expect(!fileManager.savedBGM, "BGM must not be saved when download fails")
            #expect(!fileManager.savedPreview, "Preview must not be saved when download fails")
        }
    }

    // MARK: - ServerSongDownloader no R2 base URL skip (line 183)

    @Test("downloadOptionalFiles skips audio when R2 is not configured even with audio flags")
    func testNoR2SkipsAudioDownload() async throws {
        let r2Base = "https://r2.example"
        let (defaults, _) = TestUserDefaults.makeIsolated(suiteName: "patch.nor2.\(UUID().uuidString)")
        let config = ServerConfig(userDefaults: defaults, endpointDefaults: EndpointDefaults())

        let dtxContent = "#TITLE: No R2\n#ARTIST: Tester\n#BPM: 120\n#DLEVEL: 50\n#03113: 01000000"
        let dtx = dtxContent.data(using: .shiftJIS) ?? Data(dtxContent.utf8)

        final class StubDownloader: FileDownloading, @unchecked Sendable {
            let dtx: Data
            init(dtx: Data) { self.dtx = dtx }
            func downloadData(from url: URL) async throws -> Data { dtx }
        }

        let fileManager = MockTrackingFileManager()
        let subject = ServerSongDownloader(
            downloader: StubDownloader(dtx: dtx), fileManager: fileManager, config: config
        )

        try await TestSetup.withTestSetup {
            let container = TestContainer.shared.container
            let chart = ServerChart(
                difficulty: "easy", difficultyLabel: "Easy", level: 10,
                filename: "chart.dtx", size: 100,
                fileURL: "\(r2Base)/no-r2/chart.dtx", fileEncoding: "SHIFT_JIS"
            )
            let serverSong = ServerSong(
                songId: "no-r2", title: "No R2", artist: "Tester", bpm: 120.0,
                charts: [chart], isDownloaded: false, hasBGM: true, hasPreview: true
            )

            let (success, errorMessage) = await subject.downloadAndImportSong(serverSong, container: container)
            #expect(success, "Import should succeed without R2")
            #expect(errorMessage == nil)
            #expect(!fileManager.savedBGM)
            #expect(!fileManager.savedPreview)
        }
    }

    // MARK: - ServerConfig.setR2BaseURL invalid value (lines 64-65)

    @Test("setR2BaseURL removes key when value is invalid")
    func testSetR2BaseURLRemovesKeyOnInvalid() {
        let (defaults, _) = TestUserDefaults.makeIsolated(suiteName: "patch.r2invalid.\(UUID().uuidString)")
        let config = ServerConfig(userDefaults: defaults, endpointDefaults: EndpointDefaults())

        config.setR2BaseURL("https://r2.example.com")
        #expect(config.r2BaseURL != nil)
        #expect(defaults.string(forKey: ServerConfig.r2BaseURLKey) != nil)

        config.setR2BaseURL("not-a-url")
        #expect(config.r2BaseURL == nil)
        #expect(defaults.string(forKey: ServerConfig.r2BaseURLKey) == nil,
               "Key must be removed from UserDefaults when value is invalid")
    }
}

// MARK: - Shared Mock

private final class MockTrackingFileManager: ServerSongFileManager {
    var savedBGM = false
    var savedPreview = false
    override func saveBGMFile(_ data: Data, for songId: String) throws -> String {
        savedBGM = true
        return "/tmp/mock.ogg"
    }
    override func savePreviewFile(_ data: Data, for songId: String) throws -> String {
        savedPreview = true
        return "/tmp/mock.mp3"
    }
}
