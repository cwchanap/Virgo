import Testing
import SwiftData
import Foundation
@testable import Virgo

@Suite("ServerSongService Tests", .serialized)
@MainActor
// swiftlint:disable:next type_body_length
struct ServerSongServiceTests {
    /// Coordinates a real detached deletion save with the cache replacement save.
    /// The two save closures block at their exact persistence boundaries so the
    /// test observes the replacement row after the deletion/refresh overlap,
    /// rather than asserting only that a mock method was called.
    private final class DeletionRefreshRaceCoordinator: @unchecked Sendable {
        let deletionSaveStarted = DispatchSemaphore(value: 0)
        let deletionSavePermission = DispatchSemaphore(value: 0)
        let deletionSaveCompleted = DispatchSemaphore(value: 0)
        let cacheSaveStarted = DispatchSemaphore(value: 0)
        let cacheSavePermission = DispatchSemaphore(value: 0)

        static func wait(on semaphore: DispatchSemaphore) {
            semaphore.wait()
        }
    }

    /// In-memory `FileDownloading` keyed by absolute URL; can throw for missing keys.
    private final class MockFileDownloader: FileDownloading, @unchecked Sendable {
        var responses: [String: Data] = [:]
        var throwsForAll = false

        func downloadData(from url: URL) async throws -> Data {
            if throwsForAll { throw URLError(.notConnectedToInternet) }
            guard let data = responses[url.absoluteString] else {
                throw URLError(.fileDoesNotExist)
            }
            return data
        }
    }

    @MainActor
    private final class MockServerSongCache: ServerSongCache {
        var refreshError: Error?
        var refreshCallCount = 0

        init() { super.init(fetcher: MockSimfileFetcher()) }

        override func refreshCatalog(modelContext: ModelContext) async throws {
            refreshCallCount += 1
            if let refreshError {
                throw refreshError
            }
        }
    }

    final class MockServerSongDownloader: ServerSongDownloader {
        var result: (Bool, String?) = (true, nil)
        var receivedSongIDs: [String] = []

        @MainActor
        override func downloadAndImportSong(
            _ serverSong: ServerSong, container: ModelContainer
        ) async -> (Bool, String?) {
            receivedSongIDs.append(serverSong.songId)
            return result
        }
    }

    @MainActor
    final class MockServerSongStatusManager: ServerSongStatusManager {
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

    private func makeConfig(_ name: String, withR2: Bool) -> ServerConfig {
        let (defaults, _) = TestUserDefaults.makeIsolated(suiteName: name)
        if withR2 { defaults.set("https://r2.example", forKey: ServerConfig.r2BaseURLKey) }
        return ServerConfig(userDefaults: defaults)
    }

    @Test("loadServerSongs without model context is a no-op")
    func testLoadServerSongsWithoutModelContext() async {
        let status = MockServerSongStatusManager()
        let service = ServerSongService(statusManager: status)

        await service.loadServerSongs()

        #expect(status.refreshDownloadStatusCalled == false)
        #expect(service.isLoading == false)
    }

    @Test("refreshCatalog is a no-op when modelContext is not set")
    func testRefreshWithoutModelContext() async {
        let service = ServerSongService()

        await service.refreshCatalog()
        #expect(service.isRefreshing == false)
        #expect(service.errorMessage == nil)
    }

    @Test("loadServerSongs reconciles status without owning catalog rows")
    func testLoadServerSongsReconcilesStatus() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let status = MockServerSongStatusManager()

            let service = ServerSongService(statusManager: status)
            service.setModelContext(context)

            await service.loadServerSongs()
            #expect(status.refreshDownloadStatusCalled)
            #expect(service.isLoading == false)
        }
    }

    @Test("refreshCatalog delegates to the cache")
    func testRefreshCatalogCallsCache() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let cache = MockServerSongCache()
            let service = ServerSongService(cache: cache)
            service.setModelContext(context)

            await service.refreshCatalog()

            #expect(cache.refreshCallCount == 1)
            #expect(service.isRefreshing == false)
            #expect(service.errorMessage == nil)
            #expect(service.catalogRefreshFailed == false)
        }
    }

    @Test("refreshCatalog populates cache from fetcher")
    func testServiceRefreshCatalog() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let fetcher = MockSimfileFetcher(all: [.stub(id: "x"), .stub(id: "y")])
            let service = ServerSongService(cache: ServerSongCache(fetcher: fetcher, pageSize: 50))
            service.setModelContext(context)

            await service.refreshCatalog()

            let songs = try context.fetch(FetchDescriptor<ServerSong>())
            #expect(Set(songs.map(\.songId)) == ["x", "y"])
        }
    }

    @Test("refreshCatalog sets error message when cache refresh fails")
    func testRefreshCatalogFailureSetsError() async throws {
        struct RefreshFailure: LocalizedError {
            var errorDescription: String? { "boom" }
        }

        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let cache = MockServerSongCache()
            cache.refreshError = RefreshFailure()
            let service = ServerSongService(cache: cache)
            service.setModelContext(context)

            await service.refreshCatalog()

            #expect(cache.refreshCallCount == 1)
            #expect(service.isRefreshing == false)
            #expect(service.errorMessage?.text.contains("Failed to refresh server songs") == true)
            #expect(service.errorMessage?.text.contains("boom") == true)
            #expect(service.catalogRefreshFailed)
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
            #expect(service.errorMessage?.text == "Failed to delete downloaded song")
        }
    }

    @Test("deleteLocalSong returns false and sets error when modelContext is missing")
    func testDeleteLocalSongWithoutModelContext() async {
        let service = ServerSongService()
        let song = Song(title: "Missing", artist: "Context", bpm: 100.0, duration: "1:00", genre: "DTX Import")

        let success = await service.deleteLocalSong(song)

        #expect(success == false)
        #expect(service.errorMessage?.text == "No model context available")
        #expect(service.deletingSongs.isEmpty)
    }

    @Test("deleteLocalSong returns false immediately when song is already deleting")
    func testDeleteLocalSongWhenAlreadyDeleting() async {
        let service = ServerSongService()
        let song = Song(title: "A", artist: "B", bpm: 100.0, duration: "1:00", genre: "DTX Import")
        let key = song.persistentModelID
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
            #expect(service.errorMessage?.text == "Failed to delete local song")
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

    @Test("local deletion reconciles a replacement cache row after refresh overlap")
    func testDeleteLocalSongReconcilesReplacementAfterRefreshOverlap() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let container = TestContainer.shared.container
            let coordinator = DeletionRefreshRaceCoordinator()
            let temporaryDirectory = FileManager.default.temporaryDirectory

            let statusManager = ServerSongStatusManager(
                saveContext: { backgroundContext in
                    coordinator.deletionSaveStarted.signal()
                    coordinator.deletionSavePermission.wait()
                    defer { coordinator.deletionSaveCompleted.signal() }
                    try backgroundContext.save()
                }
            )
            let fetcher = MockSimfileFetcher(all: [.stub(id: "overlap")])
            let cache = ServerSongCache(
                fetcher: fetcher,
                statusManager: statusManager,
                saveContext: { replacementContext in
                    coordinator.cacheSaveStarted.signal()
                    coordinator.cacheSavePermission.wait()
                    try replacementContext.save()
                }
            )
            let service = ServerSongService(cache: cache, statusManager: statusManager)
            service.setModelContext(context)

            let cachedSong = ServerSong(
                songId: "overlap",
                title: "Overlap",
                artist: "Race",
                bpm: 120,
                isDownloaded: true,
                bgmDownloaded: true,
                previewDownloaded: true
            )
            let localSong = Song(
                title: "Overlap",
                artist: "Race",
                bpm: 120,
                duration: "3:00",
                genre: "DTX Import",
                isServerImported: true,
                serverSongId: "overlap",
                bgmFilePath: temporaryDirectory.appendingPathComponent("virgo-overlap-bgm.ogg").path,
                previewFilePath: temporaryDirectory.appendingPathComponent("virgo-overlap-preview.mp3").path
            )
            context.insert(cachedSong)
            context.insert(localSong)
            try context.save()

            // Keep the detached deletion paused before persistence. The refresh
            // then snapshots the still-present local song and blocks at its own
            // replacement save, guaranteeing the intended interleaving.
            let deletionReady = Task.detached {
                DeletionRefreshRaceCoordinator.wait(on: coordinator.deletionSaveStarted)
            }
            let arbiter = Task.detached {
                DeletionRefreshRaceCoordinator.wait(on: coordinator.cacheSaveStarted)
                coordinator.deletionSavePermission.signal()
                DeletionRefreshRaceCoordinator.wait(on: coordinator.deletionSaveCompleted)
                // The service reconciliation saves the now-cleared replacement
                // row after the cache save resumes, using the same injected hook.
                coordinator.deletionSavePermission.signal()
                coordinator.cacheSavePermission.signal()
            }

            let deletionTask = Task { @MainActor in
                await service.deleteLocalSong(localSong)
            }
            await deletionReady.value

            let refreshTask = Task { @MainActor in
                await service.refreshCatalog()
            }

            await refreshTask.value
            _ = await deletionTask.value
            await arbiter.value

            let verificationContext = ModelContext(container)
            let replacement = try #require(
                verificationContext.fetch(FetchDescriptor<ServerSong>())
                    .first { $0.songId == "overlap" }
            )
            #expect(replacement.isDownloaded == false)
            #expect(replacement.bgmDownloaded == false)
            #expect(replacement.previewDownloaded == false)
            let remainingSongs = try verificationContext.fetch(FetchDescriptor<Song>())
            #expect(remainingSongs.isEmpty)
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
            #expect(service.errorMessage?.text == "Synthetic downloader failure")
            #expect(service.downloadingSongs.isEmpty)
            #expect(serverSong.isDownloaded == false)
            #expect(downloader.receivedSongIDs == ["download-fail"])
        }
    }

    @Test("download success delegates cache status without direct cache write")
    func testDownloadSuccessDoesNotAuthorCapturedServerSong() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let downloader = MockServerSongDownloader()
            downloader.result = (true, nil)
            let statusManager = MockServerSongStatusManager()
            var serviceSaveHookCalls = 0

            let service = ServerSongService(
                downloader: downloader,
                statusManager: statusManager,
                saveModelContext: { context in
                    serviceSaveHookCalls += 1
                    try context.save()
                }
            )
            service.setModelContext(context)

            let serverSong = ServerSong(songId: "download-ok", title: "OK", artist: "Artist", bpm: 120.0)
            context.insert(serverSong)
            try context.save()

            let success = await service.downloadAndImportSong(serverSong)

            #expect(success)
            #expect(serverSong.isDownloaded == false)
            #expect(serviceSaveHookCalls == 0)
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
        #expect(service.errorMessage?.text == "No model context available")
        #expect(service.downloadingSongs.isEmpty)
    }

    @Test("isDownloading and isDeleting helpers reflect tracking sets")
    func testHelperMethodsTrackState() async {
        let service = ServerSongService()
        let serverSong = ServerSong(songId: "song-x", title: "Song X", artist: "Artist X", bpm: 120.0)
        let localSong = Song(title: "Mixed Case", artist: "Artist", bpm: 100.0, duration: "1:00", genre: "Rock")

        service.downloadingSongs = ["song-x"]
        service.deletingSongs = [localSong.persistentModelID]

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
                genre: "DTX Import",
                isServerImported: true,
                serverSongId: "service-delete"
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
        let config = makeConfig("ServerSongServiceTests.noCharts.\(UUID().uuidString)", withR2: false)
        let downloader = ServerSongDownloader(downloader: MockFileDownloader(), config: config)

        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let service = ServerSongService(downloader: downloader)
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

    @Test("downloadAndImportSong rejects duplicate local song by serverSongId and reports message")
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
                genre: "DTX Import",
                isServerImported: true,
                serverSongId: "duplicate-server-song"
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
            #expect(service.errorMessage?.text == "Song already exists in database")
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
        let mock = MockFileDownloader()
        mock.throwsForAll = true
        let config = makeConfig("ServerSongServiceTests.chartFail.\(UUID().uuidString)", withR2: false)
        let downloader = ServerSongDownloader(downloader: mock, config: config)

        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let service = ServerSongService(downloader: downloader)
            service.setModelContext(context)

            let serverChart = ServerChart(
                difficulty: "expert",
                difficultyLabel: "MASTER",
                level: 90,
                filename: "master.dtx",
                size: 1024,
                fileURL: "https://r2.example/invalid-download/master.dtx"
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
            #expect(service.errorMessage?.text.contains("Import failed") == true)
            #expect(serverSong.isDownloaded == false)

            let allSongs = try context.fetch(FetchDescriptor<Song>())
            let matchedSongs = allSongs.filter { $0.title == "Invalid Download" && $0.artist == "Networkless" }
            #expect(matchedSongs.isEmpty)
        }
    }

    @Test("downloadAndImportSong imports chart notes and maps unknown difficulty to medium")
    func testDownloadAndImportSongWithChartSuccess() async throws {
        let mock = MockFileDownloader()
        let dtxContent = """
        #TITLE: Long Song
        #ARTIST: Long Artist
        #BPM: 165.55
        #DLEVEL: 88
        #03113: 01000000
        """
        mock.responses["https://r2.example/networked-song/master.dtx"] =
            dtxContent.data(using: .shiftJIS) ?? Data(dtxContent.utf8)
        let config = makeConfig("ServerSongServiceTests.chartOK.\(UUID().uuidString)", withR2: false)
        let downloader = ServerSongDownloader(downloader: mock, config: config)
        let service = ServerSongService(downloader: downloader)

        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            service.setModelContext(context)

            let serverChart = ServerChart(
                difficulty: "insane",
                difficultyLabel: "MASTER",
                level: 88,
                filename: "master.dtx",
                size: 4096,
                fileURL: "https://r2.example/networked-song/master.dtx"
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
            #expect(imported?.duration == "0:46")

            let charts = try context.fetch(FetchDescriptor<Chart>())
            let importedChart = charts.first { $0.song?.title == "Networked Song" }
            #expect(importedChart != nil)
            #expect(importedChart?.difficulty == .medium)
            #expect(importedChart?.level == 88)
            #expect(importedChart?.notesCount == 1)
        }
    }

}
