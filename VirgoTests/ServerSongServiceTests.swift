import Testing
import SwiftData
import Foundation
@testable import Virgo

@Suite("ServerSongService Tests", .serialized)
@MainActor
// swiftlint:disable type_body_length
struct ServerSongServiceTests {
    private final class MockURLProtocol: URLProtocol {
        static var requestHandler: ((URLRequest) throws -> (Int, Data))?

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

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

    @MainActor
    private final class MockServerSongCache: ServerSongCache {
        var loadResult: Result<[ServerSong], Error> = .success([])
        var refreshError: Error?
        var refreshCalls: [Bool] = []

        override func loadServerSongs(modelContext: ModelContext) async throws -> [ServerSong] {
            switch loadResult {
            case .success(let songs):
                return songs
            case .failure(let error):
                throw error
            }
        }

        override func refreshServerSongs(modelContext: ModelContext, forceClear: Bool = false) async throws {
            refreshCalls.append(forceClear)
            if let refreshError {
                throw refreshError
            }
        }
    }

    private final class MockServerSongDownloader: ServerSongDownloader {
        var result: (Bool, String?) = (true, nil)
        var receivedSongIDs: [String] = []

        override func downloadAndImportSong(_ serverSong: ServerSong, container: ModelContainer) async -> (Bool, String?) {
            receivedSongIDs.append(serverSong.songId)
            return result
        }
    }

    @MainActor
    private final class MockServerSongStatusManager: ServerSongStatusManager {
        var deleteDownloadedResult = true
        var deleteLocalResult = true
        var refreshDownloadStatusCalled = false

        override func deleteDownloadedSong(_ serverSong: ServerSong, modelContext: ModelContext) async -> Bool {
            deleteDownloadedResult
        }

        override func deleteLocalSong(_ song: Song, container: ModelContainer) async -> Bool {
            deleteLocalResult
        }

        override func refreshDownloadStatus(modelContext: ModelContext) async {
            refreshDownloadStatusCalled = true
        }
    }

    @Test("loadServerSongs returns empty list when modelContext is not set")
    func testLoadServerSongsWithoutModelContext() async {
        let service = ServerSongService()

        let songs = await service.loadServerSongs()

        #expect(songs.isEmpty)
    }

    @Test("refresh methods are no-op when modelContext is not set")
    func testRefreshWithoutModelContext() async {
        let service = ServerSongService()

        await service.refreshServerSongs()
        #expect(service.isRefreshing == false)
        #expect(service.errorMessage == nil)

        await service.forceRefreshServerSongs()
        #expect(service.isRefreshing == false)
        #expect(service.errorMessage == nil)
    }

    @Test("loadServerSongs returns cache data when context is available")
    func testLoadServerSongsWithContextUsesCacheResult() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let cache = MockServerSongCache()
            let expectedSong = ServerSong(songId: "cached-song", title: "Cached", artist: "Artist", bpm: 120.0)
            cache.loadResult = .success([expectedSong])

            let service = ServerSongService(cache: cache)
            service.setModelContext(context)

            let songs = await service.loadServerSongs()
            #expect(songs.count == 1)
            #expect(songs.first?.songId == "cached-song")
        }
    }

    @Test("loadServerSongs returns empty list when cache throws")
    func testLoadServerSongsHandlesCacheError() async throws {
        struct ExpectedError: Error {}

        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let cache = MockServerSongCache()
            cache.loadResult = .failure(ExpectedError())

            let service = ServerSongService(cache: cache)
            service.setModelContext(context)

            let songs = await service.loadServerSongs()
            #expect(songs.isEmpty)
        }
    }

    @Test("refreshServerSongs calls cache with forceClear false")
    func testRefreshServerSongsUsesForceClearFalse() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let cache = MockServerSongCache()
            let service = ServerSongService(cache: cache)
            service.setModelContext(context)

            await service.refreshServerSongs()

            #expect(cache.refreshCalls == [false])
            #expect(service.isRefreshing == false)
            #expect(service.errorMessage == nil)
        }
    }

    @Test("forceRefreshServerSongs calls cache with forceClear true")
    func testForceRefreshServerSongsUsesForceClearTrue() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let cache = MockServerSongCache()
            let service = ServerSongService(cache: cache)
            service.setModelContext(context)

            await service.forceRefreshServerSongs()

            #expect(cache.refreshCalls == [true])
            #expect(service.isRefreshing == false)
            #expect(service.errorMessage == nil)
        }
    }

    @Test("refreshServerSongs sets error message when cache refresh fails")
    func testRefreshServerSongsFailureSetsError() async throws {
        struct RefreshFailure: LocalizedError {
            var errorDescription: String? { "boom" }
        }

        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let cache = MockServerSongCache()
            cache.refreshError = RefreshFailure()
            let service = ServerSongService(cache: cache)
            service.setModelContext(context)

            await service.refreshServerSongs()

            #expect(cache.refreshCalls == [false])
            #expect(service.isRefreshing == false)
            #expect(service.errorMessage?.contains("Failed to refresh server songs") == true)
            #expect(service.errorMessage?.contains("boom") == true)
        }
    }

    @Test("deleteDownloadedSong returns false when modelContext is not set")
    func testDeleteDownloadedSongWithoutModelContext() async {
        let service = ServerSongService()
        let serverSong = ServerSong(songId: "song-1", title: "Song", artist: "Artist", bpm: 120.0)

        let success = await service.deleteDownloadedSong(serverSong)

        #expect(success == false)
    }

    @Test("deleteDownloadedSong sets error when status manager fails")
    func testDeleteDownloadedSongFailureSetsError() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let statusManager = MockServerSongStatusManager()
            statusManager.deleteDownloadedResult = false
            let service = ServerSongService(statusManager: statusManager)
            service.setModelContext(context)

            let serverSong = ServerSong(songId: "song-fail", title: "Fail", artist: "Artist", bpm: 120.0)
            let success = await service.deleteDownloadedSong(serverSong)

            #expect(success == false)
            #expect(service.errorMessage == "Failed to delete downloaded song")
        }
    }

    @Test("deleteLocalSong returns false and sets error when modelContext is missing")
    func testDeleteLocalSongWithoutModelContext() async {
        let service = ServerSongService()
        let song = Song(title: "Missing", artist: "Context", bpm: 100.0, duration: "1:00", genre: "DTX Import")

        let success = await service.deleteLocalSong(song)

        #expect(success == false)
        #expect(service.errorMessage == "No model context available")
        #expect(service.deletingSongs.isEmpty)
    }

    @Test("deleteLocalSong returns false immediately when song is already deleting")
    func testDeleteLocalSongWhenAlreadyDeleting() async {
        let service = ServerSongService()
        let song = Song(title: "A", artist: "B", bpm: 100.0, duration: "1:00", genre: "DTX Import")
        let key = "a|b"
        service.deletingSongs = [key]

        let success = await service.deleteLocalSong(song)

        #expect(success == false)
        #expect(service.deletingSongs == [key])
    }

    @Test("deleteLocalSong sets error and clears deleting state when manager fails")
    func testDeleteLocalSongFailureWithContext() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let statusManager = MockServerSongStatusManager()
            statusManager.deleteLocalResult = false
            let service = ServerSongService(statusManager: statusManager)
            service.setModelContext(context)

            let song = Song(title: "Fail Local", artist: "Artist", bpm: 100.0, duration: "1:00", genre: "DTX Import")
            let success = await service.deleteLocalSong(song)

            #expect(success == false)
            #expect(service.errorMessage == "Failed to delete local song")
            #expect(service.deletingSongs.isEmpty)
        }
    }

    @Test("deleteLocalSong succeeds and clears deleting state when manager succeeds")
    func testDeleteLocalSongSuccessWithContext() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let statusManager = MockServerSongStatusManager()
            statusManager.deleteLocalResult = true
            let service = ServerSongService(statusManager: statusManager)
            service.setModelContext(context)

            let song = Song(title: "Delete Local", artist: "Artist", bpm: 100.0, duration: "1:00", genre: "DTX Import")
            let success = await service.deleteLocalSong(song)

            #expect(success)
            #expect(service.errorMessage == nil)
            #expect(service.deletingSongs.isEmpty)
        }
    }

    @Test("downloadAndImportSong returns false when song is already downloaded")
    func testDownloadAndImportSongAlreadyDownloaded() async {
        let service = ServerSongService()
        let serverSong = ServerSong(
            songId: "already-downloaded",
            title: "Downloaded",
            artist: "Artist",
            bpm: 120.0,
            isDownloaded: true
        )

        let success = await service.downloadAndImportSong(serverSong)

        #expect(success == false)
        #expect(service.downloadingSongs.isEmpty)
    }

    @Test("downloadAndImportSong sets error from downloader failure")
    func testDownloadAndImportSongDownloaderFailureSetsError() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let downloader = MockServerSongDownloader()
            downloader.result = (false, "Synthetic downloader failure")
            let service = ServerSongService(downloader: downloader)
            service.setModelContext(context)

            let serverSong = ServerSong(songId: "download-fail", title: "Fail", artist: "Artist", bpm: 120.0)
            let success = await service.downloadAndImportSong(serverSong)

            #expect(success == false)
            #expect(service.errorMessage == "Synthetic downloader failure")
            #expect(service.downloadingSongs.isEmpty)
            #expect(serverSong.isDownloaded == false)
            #expect(downloader.receivedSongIDs == ["download-fail"])
        }
    }

    @Test("downloadAndImportSong success marks song downloaded and refreshes status")
    func testDownloadAndImportSongSuccessRefreshesStatus() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let downloader = MockServerSongDownloader()
            downloader.result = (true, nil)
            let statusManager = MockServerSongStatusManager()
            let service = ServerSongService(downloader: downloader, statusManager: statusManager)
            service.setModelContext(context)

            let serverSong = ServerSong(songId: "download-ok", title: "OK", artist: "Artist", bpm: 120.0)
            context.insert(serverSong)
            try context.save()

            let success = await service.downloadAndImportSong(serverSong)

            #expect(success)
            #expect(serverSong.isDownloaded == true)
            #expect(service.errorMessage == nil)
            #expect(service.downloadingSongs.isEmpty)
            #expect(statusManager.refreshDownloadStatusCalled)
            #expect(downloader.receivedSongIDs == ["download-ok"])
        }
    }

    @Test("downloadAndImportSong returns false when song is already being downloaded")
    func testDownloadAndImportSongAlreadyDownloading() async {
        let service = ServerSongService()
        let serverSong = ServerSong(songId: "in-flight", title: "In Flight", artist: "Artist", bpm: 120.0)
        service.downloadingSongs = ["in-flight"]

        let success = await service.downloadAndImportSong(serverSong)

        #expect(success == false)
        #expect(service.downloadingSongs == ["in-flight"])
    }

    @Test("downloadAndImportSong returns false and reports missing context when modelContext is nil")
    func testDownloadAndImportSongWithoutModelContext() async {
        let service = ServerSongService()
        let serverSong = ServerSong(songId: "no-context", title: "No Context", artist: "Artist", bpm: 120.0)

        let success = await service.downloadAndImportSong(serverSong)

        #expect(success == false)
        #expect(service.errorMessage == "No model context available")
        #expect(service.downloadingSongs.isEmpty)
    }

    @Test("isDownloading and isDeleting helpers reflect tracking sets")
    func testHelperMethodsTrackState() async {
        let service = ServerSongService()
        let serverSong = ServerSong(songId: "song-x", title: "Song X", artist: "Artist X", bpm: 120.0)
        let localSong = Song(title: "Mixed Case", artist: "Artist", bpm: 100.0, duration: "1:00", genre: "Rock")

        service.downloadingSongs = ["song-x"]
        service.deletingSongs = ["mixed case|artist"]

        #expect(service.isDownloading(serverSong))
        #expect(service.isDeleting(localSong))
    }

    @Test("setModelContext enables deleteDownloadedSong delegation")
    func testDeleteDownloadedSongWithContext() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let service = ServerSongService()
            service.setModelContext(context)

            let serverSong = ServerSong(
                songId: "service-delete",
                title: "Delete Me",
                artist: "Artist",
                bpm: 120.0,
                isDownloaded: true
            )
            let importedSong = Song(
                title: "Delete Me",
                artist: "Artist",
                bpm: 120.0,
                duration: "3:00",
                genre: "DTX Import"
            )
            context.insert(serverSong)
            context.insert(importedSong)
            try context.save()

            let success = await service.deleteDownloadedSong(serverSong)

            #expect(success)
            #expect(serverSong.isDownloaded == false)
            TestAssertions.assertDeleted(importedSong, in: context)
        }
    }

    @Test("downloadAndImportSong imports song without charts and marks as downloaded")
    func testDownloadAndImportSongSuccessWithoutCharts() async throws {
        let serverURLKey = "DTXServerURL"
        let originalURL = UserDefaults.standard.string(forKey: serverURLKey)
        UserDefaults.standard.set("://invalid-base-url", forKey: serverURLKey)
        defer {
            if let originalURL {
                UserDefaults.standard.set(originalURL, forKey: serverURLKey)
            } else {
                UserDefaults.standard.removeObject(forKey: serverURLKey)
            }
        }

        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let service = ServerSongService()
            service.setModelContext(context)

            let serverSong = ServerSong(
                songId: "download-success",
                title: "Fresh Song",
                artist: "Fresh Artist",
                bpm: 135.5,
                charts: [],
                isDownloaded: false
            )
            context.insert(serverSong)
            try context.save()

            let success = await service.downloadAndImportSong(serverSong)

            #expect(success)
            #expect(service.errorMessage == nil)
            #expect(service.downloadingSongs.isEmpty)
            #expect(serverSong.isDownloaded == true)

            let importedSongs = try context.fetch(FetchDescriptor<Song>())
            let matchedSongs = importedSongs.filter {
                $0.title == "Fresh Song" &&
                    $0.artist == "Fresh Artist" &&
                    $0.genre == "DTX Import"
            }
            #expect(matchedSongs.count == 1)
            #expect(matchedSongs.first?.duration == "3:30")
        }
    }

    @Test("downloadAndImportSong rejects duplicate local song and reports message")
    func testDownloadAndImportSongDuplicateLocalSong() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let service = ServerSongService()
            service.setModelContext(context)

            let existingSong = Song(
                title: "Duplicate Song",
                artist: "Duplicate Artist",
                bpm: 120.0,
                duration: "3:00",
                genre: "DTX Import"
            )
            context.insert(existingSong)
            try context.save()

            let serverSong = ServerSong(
                songId: "duplicate-server-song",
                title: "Duplicate Song",
                artist: "Duplicate Artist",
                bpm: 120.0,
                isDownloaded: false
            )

            let success = await service.downloadAndImportSong(serverSong)

            #expect(success == false)
            #expect(service.errorMessage == "Song already exists in database")
            #expect(service.downloadingSongs.isEmpty)

            let allSongs = try context.fetch(FetchDescriptor<Song>())
            let duplicates = allSongs.filter {
                $0.title == "Duplicate Song" && $0.artist == "Duplicate Artist"
            }
            #expect(duplicates.count == 1)
        }
    }

    @Test("downloadAndImportSong surfaces chart download failures")
    func testDownloadAndImportSongChartDownloadFailure() async throws {
        let serverURLKey = "DTXServerURL"
        let originalURL = UserDefaults.standard.string(forKey: serverURLKey)
        UserDefaults.standard.set("://invalid-base-url", forKey: serverURLKey)
        defer {
            if let originalURL {
                UserDefaults.standard.set(originalURL, forKey: serverURLKey)
            } else {
                UserDefaults.standard.removeObject(forKey: serverURLKey)
            }
        }

        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let service = ServerSongService()
            service.setModelContext(context)

            let serverChart = ServerChart(
                difficulty: "expert",
                difficultyLabel: "MASTER",
                level: 90,
                filename: "master.dtx",
                size: 1024
            )
            let serverSong = ServerSong(
                songId: "invalid-download",
                title: "Invalid Download",
                artist: "Networkless",
                bpm: 160.0,
                charts: [serverChart],
                isDownloaded: false
            )

            let success = await service.downloadAndImportSong(serverSong)

            #expect(success == false)
            #expect(service.downloadingSongs.isEmpty)
            #expect(service.errorMessage?.contains("Multi-difficulty import failed") == true)
            #expect(serverSong.isDownloaded == false)

            let allSongs = try context.fetch(FetchDescriptor<Song>())
            let matchedSongs = allSongs.filter { $0.title == "Invalid Download" && $0.artist == "Networkless" }
            #expect(matchedSongs.isEmpty)
        }
    }

    @Test("downloadAndImportSong imports chart notes and maps unknown difficulty to medium")
    func testDownloadAndImportSongWithChartSuccess() async throws {
        let (userDefaults, suiteName) = TestUserDefaults.makeIsolated(
            suiteName: "ServerSongServiceTests.chartSuccess.\(UUID().uuidString)"
        )
        userDefaults.set("https://example.test", forKey: "DTXServerURL")

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let apiClient = DTXAPIClient(userDefaults: userDefaults, session: session)
        let downloader = ServerSongDownloader(apiClient: apiClient)
        let service = ServerSongService(downloader: downloader)

        let lock = NSLock()
        var requestedPaths: [String] = []

        MockURLProtocol.requestHandler = { request in
            let path = request.url?.path ?? ""
            lock.lock()
            requestedPaths.append(path)
            lock.unlock()

            if path == "/dtx/download/networked-song/master.dtx" {
                let dtxContent = """
                #TITLE: Long Song
                #ARTIST: Long Artist
                #BPM: 165.55
                #DLEVEL: 88
                #03113: 01000000
                """
                let data = dtxContent.data(using: .shiftJIS) ?? Data(dtxContent.utf8)
                return (200, data)
            }

            if path == "/dtx/download/networked-song/bgm.ogg" || path == "/dtx/download/networked-song/preview.mp3" {
                return (404, Data())
            }

            return (404, Data())
        }

        defer {
            MockURLProtocol.requestHandler = nil
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            service.setModelContext(context)

            let serverChart = ServerChart(
                difficulty: "insane",
                difficultyLabel: "MASTER",
                level: 88,
                filename: "master.dtx",
                size: 4096
            )
            let serverSong = ServerSong(
                songId: "networked-song",
                title: "Networked Song",
                artist: "Networked Artist",
                bpm: 100.0,
                charts: [serverChart],
                isDownloaded: false
            )
            context.insert(serverSong)
            try context.save()

            let success = await service.downloadAndImportSong(serverSong)

            #expect(success)
            #expect(service.errorMessage == nil)
            #expect(service.downloadingSongs.isEmpty)
            #expect(serverSong.isDownloaded == true)

            let importedSongs = try context.fetch(FetchDescriptor<Song>())
            let imported = importedSongs.first {
                $0.title == "Networked Song" && $0.artist == "Networked Artist"
            }
            #expect(imported != nil)
            #expect(imported?.bpm == 165.55)
            #expect(imported?.duration == "1:04")

            let charts = try context.fetch(FetchDescriptor<Chart>())
            let importedChart = charts.first { $0.song?.title == "Networked Song" }
            #expect(importedChart != nil)
            #expect(importedChart?.difficulty == .medium)
            #expect(importedChart?.level == 88)
            #expect(importedChart?.notesCount == 1)

            lock.lock()
            let capturedPaths = requestedPaths
            lock.unlock()
            #expect(capturedPaths.contains("/dtx/download/networked-song/master.dtx"))
            #expect(capturedPaths.contains("/dtx/download/networked-song/bgm.ogg"))
            #expect(capturedPaths.contains("/dtx/download/networked-song/preview.mp3"))
        }
    }
}
