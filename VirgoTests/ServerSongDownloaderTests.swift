import Testing
import SwiftData
import Foundation
@testable import Virgo

@Suite("ServerSongDownloader Tests", .serialized)
@MainActor
struct ServerSongDownloaderTests {
    private final class MockURLProtocol: URLProtocol {
        static var requestHandler: ((URLRequest) throws -> (Int, Data))?

        override static func canInit(with request: URLRequest) -> Bool { true }
        override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            guard let handler = Self.requestHandler else {
                client?.urlProtocol(self, didFailWithError: URLError(.badURL))
                return
            }

            do {
                let (statusCode, data) = try handler(request)
                let response = HTTPURLResponse(
                    url: request.url ?? URL(string: "https://example.test")!,
                    statusCode: statusCode,
                    httpVersion: nil,
                    headerFields: nil
                )!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }

        override func stopLoading() {}
    }

    private final class RequestedPathsStore {
        var values: [String] = []
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

    private func makeMultiDifficultyServerSong() -> ServerSong {
        let serverSong = ServerSong(
            songId: "multi-diff",
            title: "Multi Diff",
            artist: "Tester",
            bpm: 120.0,
            charts: [],
            isDownloaded: false
        )
        let easyChart = ServerChart(
            difficulty: "easy",
            difficultyLabel: "Easy",
            level: 10,
            filename: "easy.dtx",
            size: 111
        )
        let mediumChart = ServerChart(
            difficulty: "medium",
            difficultyLabel: "Normal",
            level: 20,
            filename: "medium.dtx",
            size: 222
        )
        let hardChart = ServerChart(
            difficulty: "hard",
            difficultyLabel: "Hard",
            level: 30,
            filename: "hard.dtx",
            size: 333
        )
        let expertChart = ServerChart(
            difficulty: "expert",
            difficultyLabel: "Expert",
            level: 40,
            filename: "expert.dtx",
            size: 444
        )
        serverSong.charts = [easyChart, mediumChart, hardChart, expertChart]
        return serverSong
    }

    private func makeMultiDifficultyRequestHandler(
        pathsQueue: DispatchQueue,
        requestedPathsStore: RequestedPathsStore
    ) -> (URLRequest) throws -> (Int, Data) {
        return { request in
            let path = request.url?.path ?? ""
            pathsQueue.sync { requestedPathsStore.values.append(path) }

            if path.hasSuffix("/multi-diff/easy.dtx") || path.hasSuffix("/multi-diff/medium.dtx")
                || path.hasSuffix("/multi-diff/hard.dtx") || path.hasSuffix("/multi-diff/expert.dtx") {
                let dtxContent = "#TITLE: Multi Diff\n#ARTIST: Tester\n#BPM: 170\n#DLEVEL: 88\n#03113: 01000000"
                let data = dtxContent.data(using: .shiftJIS) ?? Data(dtxContent.utf8)
                return (200, data)
            }

            if path.hasSuffix("/multi-diff/bgm.ogg") { return (200, Data([0x10, 0x11, 0x12])) }
            if path.hasSuffix("/multi-diff/preview.mp3") { return (200, Data([0x20, 0x21, 0x22])) }
            return (404, Data())
        }
    }

    private func assertSavedFiles(_ fileManager: MockServerSongFileManager) {
        #expect(fileManager.savedBGMData == [Data([0x10, 0x11, 0x12])])
        #expect(fileManager.savedPreviewData == [Data([0x20, 0x21, 0x22])])
    }

    private func assertImportedSongAndCharts(in container: ModelContainer) throws {
        let verificationContext = ModelContext(container)
        let songs = try verificationContext.fetch(FetchDescriptor<Song>())
        let importedSong = songs.first {
            $0.title == "Multi Diff" && $0.artist == "Tester" && $0.genre == "DTX Import"
        }
        guard importedSong != nil else {
            #expect(Bool(false), "Expected imported song to exist")
            return
        }

        #expect(importedSong?.bgmFilePath == "/tmp/mock-bgm.ogg")
        #expect(importedSong?.previewFilePath == "/tmp/mock-preview.mp3")

        let allCharts = try verificationContext.fetch(FetchDescriptor<Chart>())
        let importedCharts = allCharts.filter { $0.song?.title == "Multi Diff" && $0.song?.artist == "Tester" }
        #expect(importedCharts.count == 4)
        #expect(importedCharts.contains { $0.difficulty == .easy })
        #expect(importedCharts.contains { $0.difficulty == .medium })
        #expect(importedCharts.contains { $0.difficulty == .hard })
        #expect(importedCharts.contains { $0.difficulty == .expert })
    }

    private func assertDownloadedPaths(_ capturedPaths: [String]) {
        #expect(capturedPaths.contains("/dtx/download/multi-diff/easy.dtx"))
        #expect(capturedPaths.contains("/dtx/download/multi-diff/medium.dtx"))
        #expect(capturedPaths.contains("/dtx/download/multi-diff/hard.dtx"))
        #expect(capturedPaths.contains("/dtx/download/multi-diff/expert.dtx"))
        #expect(capturedPaths.contains("/dtx/download/multi-diff/bgm.ogg"))
        #expect(capturedPaths.contains("/dtx/download/multi-diff/preview.mp3"))
    }

    @Test("downloadAndImportSong maps all known difficulties and downloads optional files")
    func testDownloadAndImportSongMapsDifficultiesAndDownloadsOptionalFiles() async throws {
        let (userDefaults, suiteName) = TestUserDefaults.makeIsolated(
            suiteName: "ServerSongDownloaderTests.multiDifficulty.\(UUID().uuidString)"
        )
        userDefaults.set("https://example.test", forKey: "DTXServerURL")

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let apiClient = DTXAPIClient(userDefaults: userDefaults, session: session)
        let fileManager = MockServerSongFileManager()
        let downloader = ServerSongDownloader(apiClient: apiClient, fileManager: fileManager)

        let pathsQueue = DispatchQueue(label: "ServerSongDownloaderTests.paths")
        let requestedPathsStore = RequestedPathsStore()
        MockURLProtocol.requestHandler = makeMultiDifficultyRequestHandler(
            pathsQueue: pathsQueue,
            requestedPathsStore: requestedPathsStore
        )

        defer {
            MockURLProtocol.requestHandler = nil
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        try await TestSetup.withTestSetup {
            let container = TestContainer.shared.container

            let serverSong = makeMultiDifficultyServerSong()

            let (success, errorMessage) = await downloader.downloadAndImportSong(serverSong, container: container)

            guard success else {
                let message = errorMessage ?? "nil"
                #expect(Bool(false), "Expected success, got error: \(message)")
                return
            }

            #expect(errorMessage == nil)
            assertSavedFiles(fileManager)
            try assertImportedSongAndCharts(in: container)

            let capturedPaths = pathsQueue.sync { requestedPathsStore.values }
            assertDownloadedPaths(capturedPaths)
        }
    }

    @Test("downloadAndImportSong tolerates non Shift-JIS chart content and still imports song")
    func testDownloadAndImportSongHandlesNonShiftJISChartData() async throws {
        let (userDefaults, suiteName) = TestUserDefaults.makeIsolated(
            suiteName: "ServerSongDownloaderTests.nonShiftJIS.\(UUID().uuidString)"
        )
        userDefaults.set("https://example.test", forKey: "DTXServerURL")

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let apiClient = DTXAPIClient(userDefaults: userDefaults, session: session)
        let downloader = ServerSongDownloader(apiClient: apiClient)

        MockURLProtocol.requestHandler = { request in
            let path = request.url?.path ?? ""
            if path == "/dtx/download/non-shift/broken.dtx" {
                return (200, Data([0xFF, 0xFF, 0xFF]))
            }
            return (404, Data())
        }

        defer {
            MockURLProtocol.requestHandler = nil
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        try await TestSetup.withTestSetup {
            let container = TestContainer.shared.container

            let chart = ServerChart(
                difficulty: "easy",
                difficultyLabel: "Easy",
                level: 7,
                filename: "broken.dtx",
                size: 42
            )
            let serverSong = ServerSong(
                songId: "non-shift",
                title: "Broken Encoding",
                artist: "Tester",
                bpm: 123.0,
                charts: [chart],
                isDownloaded: false
            )

            let (success, errorMessage) = await downloader.downloadAndImportSong(serverSong, container: container)

            #expect(success)
            #expect(errorMessage == nil)

            let verificationContext = ModelContext(container)
            let songs = try verificationContext.fetch(FetchDescriptor<Song>())
            let importedSong = songs.first { $0.title == "Broken Encoding" && $0.artist == "Tester" }
            #expect(importedSong != nil)
            #expect(importedSong?.bpm == 123.0)
            #expect(importedSong?.duration == "3:30")

            let allCharts = try verificationContext.fetch(FetchDescriptor<Chart>())
            let importedCharts = allCharts.filter { $0.song?.title == "Broken Encoding" }
            #expect(importedCharts.isEmpty)
        }
    }

    @Test("downloadAndImportSong uses 1:00 duration fallback for charts with no notes")
    func testDownloadAndImportSongUsesEmptyNotesDurationFallback() async throws {
        let (userDefaults, suiteName) = TestUserDefaults.makeIsolated(
            suiteName: "ServerSongDownloaderTests.emptyNotesDuration.\(UUID().uuidString)"
        )
        userDefaults.set("https://example.test", forKey: "DTXServerURL")

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let apiClient = DTXAPIClient(userDefaults: userDefaults, session: session)
        let downloader = ServerSongDownloader(apiClient: apiClient)

        MockURLProtocol.requestHandler = { request in
            let path = request.url?.path ?? ""
            if path == "/dtx/download/empty-notes/empty.dtx" {
                let dtxContent = "#TITLE: Empty Notes\n#ARTIST: Tester\n#BPM: 120\n#DLEVEL: 12"
                let data = dtxContent.data(using: .shiftJIS) ?? Data(dtxContent.utf8)
                return (200, data)
            }
            return (404, Data())
        }

        defer {
            MockURLProtocol.requestHandler = nil
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        try await TestSetup.withTestSetup {
            let container = TestContainer.shared.container

            let chart = ServerChart(
                difficulty: "easy",
                difficultyLabel: "Easy",
                level: 12,
                filename: "empty.dtx",
                size: 10
            )
            let serverSong = ServerSong(
                songId: "empty-notes",
                title: "Empty Notes",
                artist: "Tester",
                bpm: 120.0,
                charts: [chart],
                isDownloaded: false
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
}
