import Testing
import SwiftData
import Foundation
@testable import Virgo

@Suite("ServerSongDownloader Tests", .serialized)
@MainActor
struct ServerSongDownloaderTests {
    /// In-memory `FileDownloading` keyed by absolute URL; records requests.
    private final class MockFileDownloader: FileDownloading, @unchecked Sendable {
        var responses: [String: Data] = [:]
        private(set) var requestedURLs: [String] = []

        func downloadData(from url: URL) async throws -> Data {
            requestedURLs.append(url.absoluteString)
            guard let data = responses[url.absoluteString] else {
                throw URLError(.fileDoesNotExist)
            }
            return data
        }
    }

    private final class MockServerSongFileManager: ServerSongFileManager {
        var savedBGMData: [Data] = []
        var savedPreviewData: [Data] = []
        var bgmPathToReturn = "/tmp/mock-bgm.ogg"
        var previewPathToReturn = "/tmp/mock-preview.mp3"

        override func saveBGMFile(_ data: Data, for songId: String) throws -> String {
            savedBGMData.append(data)
            return bgmPathToReturn
        }

        override func savePreviewFile(_ data: Data, for songId: String) throws -> String {
            savedPreviewData.append(data)
            return previewPathToReturn
        }
    }

    private let r2Base = "https://r2.example"

    private func makeConfig(_ name: String, withR2: Bool) -> ServerConfig {
        let (defaults, _) = TestUserDefaults.makeIsolated(suiteName: name)
        if withR2 { defaults.set(r2Base, forKey: ServerConfig.r2BaseURLKey) }
        return ServerConfig(userDefaults: defaults)
    }

    private func chart(_ diff: String, label: String, level: Int, file: String, songId: String) -> ServerChart {
        ServerChart(
            difficulty: diff, difficultyLabel: label, level: level,
            filename: file, size: 100,
            fileURL: "\(r2Base)/\(songId)/\(file)", fileEncoding: "SHIFT_JIS"
        )
    }

    private func makeMultiDifficultyServerSong() -> ServerSong {
        let songId = "multi-diff"
        let serverSong = ServerSong(
            songId: songId, title: "Multi Diff", artist: "Tester", bpm: 120.0,
            charts: [], isDownloaded: false, hasBGM: true, hasPreview: true
        )
        serverSong.charts = [
            chart("easy", label: "Easy", level: 10, file: "easy.dtx", songId: songId),
            chart("medium", label: "Normal", level: 20, file: "medium.dtx", songId: songId),
            chart("hard", label: "Hard", level: 30, file: "hard.dtx", songId: songId),
            chart("expert", label: "Expert", level: 40, file: "expert.dtx", songId: songId)
        ]
        return serverSong
    }

    private func dtxData(_ content: String) -> Data {
        content.data(using: .shiftJIS) ?? Data(content.utf8)
    }

    @Test("downloadAndImportSong maps all known difficulties and downloads optional files")
    func testDownloadAndImportSongMapsDifficultiesAndDownloadsOptionalFiles() async throws {
        let fileManager = MockServerSongFileManager()
        let mock = MockFileDownloader()
        let dtx = dtxData("#TITLE: Multi Diff\n#ARTIST: Tester\n#BPM: 170\n#DLEVEL: 88\n#03113: 01000000")
        for file in ["easy.dtx", "medium.dtx", "hard.dtx", "expert.dtx"] {
            mock.responses["\(r2Base)/multi-diff/\(file)"] = dtx
        }
        mock.responses["\(r2Base)/multi-diff/bgm.ogg"] = Data([0x10, 0x11, 0x12])
        mock.responses["\(r2Base)/multi-diff/preview.mp3"] = Data([0x20, 0x21, 0x22])

        let config = makeConfig("ServerSongDownloaderTests.multi.\(UUID().uuidString)", withR2: true)
        let downloader = ServerSongDownloader(downloader: mock, fileManager: fileManager, config: config)

        try await TestSetup.withTestSetup {
            let container = TestContainer.shared.container
            let serverSong = makeMultiDifficultyServerSong()

            let (success, errorMessage) = await downloader.downloadAndImportSong(serverSong, container: container)
            guard success else {
                #expect(Bool(false), "Expected success, got error: \(errorMessage ?? "nil")")
                return
            }
            #expect(errorMessage == nil)
            #expect(fileManager.savedBGMData == [Data([0x10, 0x11, 0x12])])
            #expect(fileManager.savedPreviewData == [Data([0x20, 0x21, 0x22])])

            let verificationContext = ModelContext(container)
            let songs = try verificationContext.fetch(FetchDescriptor<Song>())
            let importedSong = songs.first {
                $0.title == "Multi Diff" && $0.artist == "Tester" && $0.genre == "DTX Import"
            }
            #expect(importedSong?.isServerImported == true, "Downloaded song must be marked as server-imported")
            #expect(importedSong?.serverSongId == "multi-diff", "Downloaded song must persist the server songId")
            #expect(importedSong?.bgmFilePath == "/tmp/mock-bgm.ogg")
            #expect(importedSong?.previewFilePath == "/tmp/mock-preview.mp3")

            let allCharts = try verificationContext.fetch(FetchDescriptor<Chart>())
            let importedCharts = allCharts.filter { $0.song?.title == "Multi Diff" && $0.song?.artist == "Tester" }
            #expect(importedCharts.count == 4)
            #expect(importedCharts.contains { $0.difficulty == .easy })
            #expect(importedCharts.contains { $0.difficulty == .medium })
            #expect(importedCharts.contains { $0.difficulty == .hard })
            #expect(importedCharts.contains { $0.difficulty == .expert })

            #expect(mock.requestedURLs.contains("\(r2Base)/multi-diff/bgm.ogg"))
            #expect(mock.requestedURLs.contains("\(r2Base)/multi-diff/preview.mp3"))
        }
    }

    @Test("downloadAndImportSong fails when all charts are undecodable")
    func testDownloadAndImportSongFailsWhenAllChartsUndecodable() async throws {
        let mock = MockFileDownloader()
        mock.responses["\(r2Base)/non-shift/broken.dtx"] = Data([0xFF, 0xFF, 0xFF])
        let config = makeConfig("ServerSongDownloaderTests.broken.\(UUID().uuidString)", withR2: false)
        let downloader = ServerSongDownloader(downloader: mock, fileManager: ServerSongFileManager(), config: config)

        try await TestSetup.withTestSetup {
            let container = TestContainer.shared.container
            let brokenChart = chart("easy", label: "Easy", level: 7, file: "broken.dtx", songId: "non-shift")
            let serverSong = ServerSong(
                songId: "non-shift", title: "Broken Encoding", artist: "Tester", bpm: 123.0,
                charts: [brokenChart], isDownloaded: false
            )

            let (success, errorMessage) = await downloader.downloadAndImportSong(serverSong, container: container)
            #expect(success == false)
            #expect(errorMessage != nil)

            // Song must NOT be persisted when all charts fail.
            let verificationContext = ModelContext(container)
            let songs = try verificationContext.fetch(FetchDescriptor<Song>())
            let importedSong = songs.first { $0.title == "Broken Encoding" && $0.artist == "Tester" }
            #expect(importedSong == nil)
        }
    }

    @Test("downloadAndImportSong fails when any chart fails to process")
    func testDownloadAndImportSongFailsOnPartialChartFailure() async throws {
        let mock = MockFileDownloader()
        let dtx = dtxData("#TITLE: Partial\n#ARTIST: Tester\n#BPM: 150\n#DLEVEL: 50\n#03113: 01000000")
        mock.responses["\(r2Base)/partial-fail/good.dtx"] = dtx
        // broken.dtx returns non-decodable bytes
        mock.responses["\(r2Base)/partial-fail/broken.dtx"] = Data([0xFF, 0xFF, 0xFF])
        let config = makeConfig("ServerSongDownloaderTests.partial.\(UUID().uuidString)", withR2: false)
        let downloader = ServerSongDownloader(downloader: mock, fileManager: ServerSongFileManager(), config: config)

        try await TestSetup.withTestSetup {
            let container = TestContainer.shared.container
            let goodChart = chart("easy", label: "Easy", level: 10, file: "good.dtx", songId: "partial-fail")
            let brokenChart = chart("hard", label: "Hard", level: 30, file: "broken.dtx", songId: "partial-fail")
            let serverSong = ServerSong(
                songId: "partial-fail", title: "Partial", artist: "Tester", bpm: 150.0,
                charts: [goodChart, brokenChart], isDownloaded: false
            )

            let (success, errorMessage) = await downloader.downloadAndImportSong(serverSong, container: container)
            #expect(success == false)
            #expect(errorMessage != nil)

            // No charts or songs should be persisted when any chart fails.
            let verificationContext = ModelContext(container)
            let allCharts = try verificationContext.fetch(FetchDescriptor<Chart>())
            let importedCharts = allCharts.filter { $0.song?.title == "Partial" }
            #expect(importedCharts.isEmpty)

            let allSongs = try verificationContext.fetch(FetchDescriptor<Song>())
            let importedSong = allSongs.first { $0.title == "Partial" && $0.artist == "Tester" }
            #expect(importedSong == nil)
        }
    }

    @Test("downloadAndImportSong uses 1:00 duration fallback for charts with no notes")
    func testDownloadAndImportSongUsesEmptyNotesDurationFallback() async throws {
        let mock = MockFileDownloader()
        mock.responses["\(r2Base)/empty-notes/empty.dtx"] =
            dtxData("#TITLE: Empty Notes\n#ARTIST: Tester\n#BPM: 120\n#DLEVEL: 12")
        let config = makeConfig("ServerSongDownloaderTests.empty.\(UUID().uuidString)", withR2: false)
        let downloader = ServerSongDownloader(downloader: mock, fileManager: ServerSongFileManager(), config: config)

        try await TestSetup.withTestSetup {
            let container = TestContainer.shared.container
            let emptyChart = chart("easy", label: "Easy", level: 12, file: "empty.dtx", songId: "empty-notes")
            let serverSong = ServerSong(
                songId: "empty-notes", title: "Empty Notes", artist: "Tester", bpm: 120.0,
                charts: [emptyChart], isDownloaded: false
            )

            let (success, errorMessage) = await downloader.downloadAndImportSong(serverSong, container: container)
            #expect(success)
            #expect(errorMessage == nil)

            let verificationContext = ModelContext(container)
            let songs = try verificationContext.fetch(FetchDescriptor<Song>())
            let importedSong = songs.first { $0.title == "Empty Notes" && $0.artist == "Tester" }
            #expect(importedSong != nil)
            #expect(importedSong?.duration == "1:00")
        }
    }

    @Test("downloadAndImportSong rejects duplicate by serverSongId even with different title")
    func testDuplicateDetectionByServerSongId() async throws {
        let mock = MockFileDownloader()
        let config = makeConfig("ServerSongDownloaderTests.dupId.\(UUID().uuidString)", withR2: false)
        let downloader = ServerSongDownloader(downloader: mock, fileManager: ServerSongFileManager(), config: config)

        try await TestSetup.withTestSetup {
            let container = TestContainer.shared.container
            let context = TestContainer.shared.context

            // Pre-existing song with serverSongId "dup-test" but different title
            let existing = Song(
                title: "Original Title",
                artist: "Original Artist",
                bpm: 120.0,
                duration: "3:00",
                genre: "DTX Import",
                isServerImported: true,
                serverSongId: "dup-test"
            )
            context.insert(existing)
            try context.save()

            // Attempt to import a different server song with same serverSongId
            let serverSong = ServerSong(
                songId: "dup-test",
                title: "Different Title",
                artist: "Different Artist",
                bpm: 140.0,
                charts: [],
                isDownloaded: false
            )

            let (success, errorMessage) = await downloader.downloadAndImportSong(serverSong, container: container)
            #expect(success == false)
            #expect(errorMessage == "Song already exists in database")
        }
    }
}
