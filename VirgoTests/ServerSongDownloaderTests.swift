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
        let dtxWithoutBGM = dtxData(
            "#TITLE: Multi Diff\n#ARTIST: Tester\n#BPM: 200\n#DLEVEL: 88\n#03113: 01000000"
        )
        let dtxWithBGM = dtxData(
            "#TITLE: Multi Diff\n#ARTIST: Tester\n#BPM: 200\n#DLEVEL: 88\n#00001: 0000001A\n#03113: 01000000"
        )
        mock.responses["\(r2Base)/multi-diff/easy.dtx"] = dtxWithoutBGM
        for file in ["medium.dtx", "hard.dtx", "expert.dtx"] {
            mock.responses["\(r2Base)/multi-diff/\(file)"] = dtxWithBGM
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
            #expect(importedSong?.bgmStartOffsetSeconds == nil)

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

    @Test("downloadAndImportSong imports valid charts when some charts fail")
    func testDownloadAndImportSongSucceedsWithPartialChartFailure() async throws {
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
            #expect(success)
            #expect(errorMessage == nil)

            // The valid chart should be persisted; the broken chart should be skipped.
            let verificationContext = ModelContext(container)
            let allCharts = try verificationContext.fetch(FetchDescriptor<Chart>())
            let importedCharts = allCharts.filter { $0.song?.title == "Partial" }
            #expect(importedCharts.count == 1)
            #expect(importedCharts.contains { $0.difficulty == .easy })

            let allSongs = try verificationContext.fetch(FetchDescriptor<Song>())
            let importedSong = allSongs.first { $0.title == "Partial" && $0.artist == "Tester" }
            #expect(importedSong != nil)
        }
    }

    @Test("downloadAndImportSong fails when all charts fail with multiple charts")
    func testDownloadAndImportSongFailsWhenAllChartsFail() async throws {
        let mock = MockFileDownloader()
        mock.responses["\(r2Base)/all-bad/bad1.dtx"] = Data([0xFF, 0xFF, 0xFF])
        mock.responses["\(r2Base)/all-bad/bad2.dtx"] = Data([0xFE, 0xFE, 0xFE])
        let config = makeConfig("ServerSongDownloaderTests.allbad.\(UUID().uuidString)", withR2: false)
        let downloader = ServerSongDownloader(downloader: mock, fileManager: ServerSongFileManager(), config: config)

        try await TestSetup.withTestSetup {
            let container = TestContainer.shared.container
            let brokenChart1 = chart("easy", label: "Easy", level: 10, file: "bad1.dtx", songId: "all-bad")
            let brokenChart2 = chart("hard", label: "Hard", level: 30, file: "bad2.dtx", songId: "all-bad")
            let serverSong = ServerSong(
                songId: "all-bad", title: "All Bad", artist: "Tester", bpm: 130.0,
                charts: [brokenChart1, brokenChart2], isDownloaded: false
            )

            let (success, errorMessage) = await downloader.downloadAndImportSong(serverSong, container: container)
            #expect(success == false)
            #expect(errorMessage != nil)

            // Song must NOT be persisted when all charts fail.
            let verificationContext = ModelContext(container)
            let songs = try verificationContext.fetch(FetchDescriptor<Song>())
            let importedSong = songs.first { $0.title == "All Bad" && $0.artist == "Tester" }
            #expect(importedSong == nil)
        }
    }

    @Test("downloadAndImportSong uses canonical one-measure duration for charts with no notes")
    func testDownloadAndImportSongUsesEmptyNotesCanonicalDuration() async throws {
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
            #expect(importedSong?.duration == "0:02")
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

    @Test("downloadAndImportSong preserves server durationSeconds over chart-based estimate")
    func testPreservesServerDurationWhenAvailable() async throws {
        let mock = MockFileDownloader()
        // DTX with a note that would produce a chart-based estimate different from server duration
        let dtx = dtxData("#TITLE: Duration Test\n#ARTIST: Tester\n#BPM: 120\n#DLEVEL: 50\n#03113: 01000000")
        mock.responses["\(r2Base)/dur-test/chart.dtx"] = dtx
        let config = makeConfig("ServerSongDownloaderTests.dur.\(UUID().uuidString)", withR2: false)
        let downloader = ServerSongDownloader(downloader: mock, fileManager: ServerSongFileManager(), config: config)

        try await TestSetup.withTestSetup {
            let container = TestContainer.shared.container
            let serverChart = chart("easy", label: "Easy", level: 10, file: "chart.dtx", songId: "dur-test")
            // Server reports 210 seconds (3:30); chart-based estimate would differ
            let serverSong = ServerSong(
                songId: "dur-test",
                title: "Duration Test",
                artist: "Tester",
                bpm: 120.0,
                durationSeconds: 210,
                charts: [serverChart],
                isDownloaded: false
            )

            let (success, errorMessage) = await downloader.downloadAndImportSong(serverSong, container: container)
            #expect(success)
            #expect(errorMessage == nil)

            let verificationContext = ModelContext(container)
            let songs = try verificationContext.fetch(FetchDescriptor<Song>())
            let importedSong = songs.first { $0.title == "Duration Test" && $0.artist == "Tester" }
            #expect(importedSong != nil)
            // Must use server's 210s (3:30), not the chart-based estimate
            #expect(importedSong?.duration == "3:30")
        }
    }

    @Test("downloadAndImportSong falls back to chart-based duration when server has none")
    func testFallsBackToChartDurationWhenServerHasNone() async throws {
        let mock = MockFileDownloader()
        let dtx = dtxData("#TITLE: No Dur\n#ARTIST: Tester\n#BPM: 120\n#DLEVEL: 50\n#03113: 01000000")
        mock.responses["\(r2Base)/no-dur/chart.dtx"] = dtx
        let config = makeConfig("ServerSongDownloaderTests.nodur.\(UUID().uuidString)", withR2: false)
        let downloader = ServerSongDownloader(downloader: mock, fileManager: ServerSongFileManager(), config: config)

        try await TestSetup.withTestSetup {
            let container = TestContainer.shared.container
            let serverChart = chart("easy", label: "Easy", level: 10, file: "chart.dtx", songId: "no-dur")
            // No durationSeconds from server
            let serverSong = ServerSong(
                songId: "no-dur",
                title: "No Dur",
                artist: "Tester",
                bpm: 120.0,
                charts: [serverChart],
                isDownloaded: false
            )

            let (success, errorMessage) = await downloader.downloadAndImportSong(serverSong, container: container)
            #expect(success)
            #expect(errorMessage == nil)

            let verificationContext = ModelContext(container)
            let songs = try verificationContext.fetch(FetchDescriptor<Song>())
            let importedSong = songs.first { $0.title == "No Dur" && $0.artist == "Tester" }
            #expect(importedSong != nil)
            // Should use chart-based estimate, not "3:30" default from createSong
            // Exact value depends on parsed measure numbers from DTX content
            #expect(importedSong?.duration != "3:30")
        }
    }

    @Test("processCharts propagates CancellationError instead of treating it as a chart failure")
    func testCancellationErrorPropagation() async throws {
        /// Downloader that throws CancellationError on the second chart's download.
        final class CancellingDownloader: FileDownloading, @unchecked Sendable {
            var callCount = 0
            func downloadData(from url: URL) async throws -> Data {
                callCount += 1
                if callCount > 1 { throw CancellationError() }
                let dtx = "#TITLE: Cancel\n#ARTIST: T\n#BPM: 120\n#DLEVEL: 10\n#03113: 01"
                return dtx.data(using: .shiftJIS) ?? Data(dtx.utf8)
            }
        }

        let downloader = MockServerSongFileManager()
        let config = makeConfig("ServerSongDownloaderTests.cancel.\(UUID().uuidString)", withR2: false)
        let subject = ServerSongDownloader(
            downloader: CancellingDownloader(),
            fileManager: downloader,
            config: config
        )

        try await TestSetup.withTestSetup {
            let container = TestContainer.shared.container
            let chart1 = ServerChart(
                difficulty: "easy", difficultyLabel: "Easy", level: 10,
                filename: "c1.dtx", size: 100,
                fileURL: "\(r2Base)/cancel/c1.dtx", fileEncoding: "SHIFT_JIS"
            )
            let chart2 = ServerChart(
                difficulty: "hard", difficultyLabel: "Hard", level: 30,
                filename: "c2.dtx", size: 100,
                fileURL: "\(r2Base)/cancel/c2.dtx", fileEncoding: "SHIFT_JIS"
            )
            let serverSong = ServerSong(
                songId: "cancel", title: "Cancel", artist: "T", bpm: 120.0,
                charts: [chart1, chart2], isDownloaded: false
            )

            let (success, errorMessage) = await subject.downloadAndImportSong(serverSong, container: container)
            // The download should fail with the CancellationError bubbled up as an import failure
            #expect(success == false, "Download must fail when CancellationError is thrown")
            #expect(errorMessage != nil)
        }
    }

    @Test("downloadAndImportSong gives descriptive error for empty fileURL")
    func testEmptyFileURLGivesDescriptiveError() async throws {
        let config = makeConfig("ServerSongDownloaderTests.emptyurl.\(UUID().uuidString)", withR2: false)
        let downloader = ServerSongDownloader(
            downloader: MockFileDownloader(),
            fileManager: ServerSongFileManager(),
            config: config
        )

        try await TestSetup.withTestSetup {
            let container = TestContainer.shared.container
            let emptyURLChart = ServerChart(
                difficulty: "easy", difficultyLabel: "Easy", level: 10,
                filename: "empty.dtx", size: 100,
                fileURL: "", fileEncoding: "SHIFT_JIS"
            )
            let serverSong = ServerSong(
                songId: "empty-url", title: "Empty URL", artist: "Tester", bpm: 120.0,
                charts: [emptyURLChart], isDownloaded: false
            )

            let (success, errorMessage) = await downloader.downloadAndImportSong(serverSong, container: container)
            #expect(success == false)
            // Empty fileURL causes chartFailure since the single chart can't be processed.
            // The error message includes the filename.
            #expect(errorMessage?.contains("empty.dtx") == true,
                    "Error must reference the chart filename, got: \(errorMessage ?? "nil")")
        }
    }

    @Test("downloadAndImportSong allows distinct server songs with same title/artist")
    func testAllowsDistinctServerSongsWithSameTitleArtist() async throws {
        let mock = MockFileDownloader()
        let dtx = dtxData("#TITLE: Same Name\n#ARTIST: Same Artist\n#BPM: 120\n#DLEVEL: 50\n#03113: 01000000")
        mock.responses["\(r2Base)/server-song-a/chart.dtx"] = dtx
        mock.responses["\(r2Base)/server-song-b/chart.dtx"] = dtx
        let config = makeConfig("ServerSongDownloaderTests.diffta.\(UUID().uuidString)", withR2: false)
        let downloader = ServerSongDownloader(downloader: mock, fileManager: ServerSongFileManager(), config: config)

        try await TestSetup.withTestSetup {
            let container = TestContainer.shared.container
            let context = TestContainer.shared.context

            // Insert first server song with serverSongId "server-song-a"
            let existing = Song(
                title: "Same Name",
                artist: "Same Artist",
                bpm: 120.0,
                duration: "3:00",
                genre: "DTX Import",
                isServerImported: true,
                serverSongId: "server-song-a"
            )
            context.insert(existing)
            try context.save()

            // Import a second distinct server song with same title/artist but different serverSongId
            let serverChart = chart("easy", label: "Easy", level: 10, file: "chart.dtx", songId: "server-song-b")
            let serverSong = ServerSong(
                songId: "server-song-b",
                title: "Same Name",
                artist: "Same Artist",
                bpm: 140.0,
                charts: [serverChart],
                isDownloaded: false
            )

            let (success, errorMessage) = await downloader.downloadAndImportSong(serverSong, container: container)
            #expect(success, "Distinct server song with different serverSongId should be importable, got: \(errorMessage ?? "nil")")

            let verificationContext = ModelContext(container)
            let songs = try verificationContext.fetch(FetchDescriptor<Song>())
            let matchingSongs = songs.filter { $0.title == "Same Name" && $0.artist == "Same Artist" }
            #expect(matchingSongs.count == 2, "Both songs should exist in database")
        }
    }

    @Test("downloadAndImportSong rejects import when legacy song matches title/artist")
    func testRejectsImportWhenLegacySongMatchesTitleArtist() async throws {
        let mock = MockFileDownloader()
        let config = makeConfig("ServerSongDownloaderTests.legacy.\(UUID().uuidString)", withR2: false)
        let downloader = ServerSongDownloader(downloader: mock, fileManager: ServerSongFileManager(), config: config)

        try await TestSetup.withTestSetup {
            let container = TestContainer.shared.container
            let context = TestContainer.shared.context

            // Insert a legacy song with NO serverSongId
            let legacy = Song(
                title: "Legacy Song",
                artist: "Legacy Artist",
                bpm: 100.0,
                duration: "2:30",
                genre: "Rock",
                isServerImported: false,
                serverSongId: nil
            )
            context.insert(legacy)
            try context.save()

            // Try to import a server song with the same title/artist
            let serverSong = ServerSong(
                songId: "new-server-id",
                title: "Legacy Song",
                artist: "Legacy Artist",
                bpm: 110.0,
                charts: [],
                isDownloaded: false
            )

            let (success, errorMessage) = await downloader.downloadAndImportSong(serverSong, container: container)
            #expect(success == false)
            #expect(errorMessage == "Song already exists in database")
        }
    }

    @Test("downloadAndImportSong rejects import when legacy song matches title/artist with different case")
    func testRejectsImportWhenLegacySongMatchesCaseInsensitive() async throws {
        let mock = MockFileDownloader()
        let config = makeConfig("ServerSongDownloaderTests.cicase.\(UUID().uuidString)", withR2: false)
        let downloader = ServerSongDownloader(downloader: mock, fileManager: ServerSongFileManager(), config: config)

        try await TestSetup.withTestSetup {
            let container = TestContainer.shared.container
            let context = TestContainer.shared.context

            // Insert a legacy song with mixed-case title/artist and NO serverSongId
            let legacy = Song(
                title: "LEGACY SONG",
                artist: "legacy artist",
                bpm: 100.0,
                duration: "2:30",
                genre: "Rock",
                isServerImported: false,
                serverSongId: nil
            )
            context.insert(legacy)
            try context.save()

            // Try to import a server song whose title/artist differs only by case
            let serverSong = ServerSong(
                songId: "case-insensitive-id",
                title: "legacy song",
                artist: "Legacy Artist",
                bpm: 110.0,
                charts: [],
                isDownloaded: false
            )

            let (success, errorMessage) = await downloader.downloadAndImportSong(serverSong, container: container)
            #expect(success == false)
            #expect(errorMessage == "Song already exists in database")
        }
    }
}
