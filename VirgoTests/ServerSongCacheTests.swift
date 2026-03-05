import Testing
import SwiftData
import Foundation
@testable import Virgo

@Suite("ServerSongCache Tests", .serialized)
@MainActor
// swiftlint:disable type_body_length
struct ServerSongCacheTests {
    private enum SaveHookError: Error {
        case forced
    }

    private final class RequestedPathsStore {
        private let queue = DispatchQueue(label: "ServerSongCacheTests.requestedPaths")
        private var values: [String] = []

        func append(_ path: String) {
            queue.sync {
                values.append(path)
            }
        }

        func snapshot() -> [String] {
            queue.sync { values }
        }
    }

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

    @Test("loadServerSongs returns non-stale cache and updates download statuses")
    func testLoadServerSongsUsesCacheAndUpdatesStatus() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let cache = ServerSongCache()

            let localMatch = Song(
                title: "Matched Song",
                artist: "Matched Artist",
                bpm: 120.0,
                duration: "3:00",
                genre: "DTX Import"
            )
            context.insert(localMatch)

            let matchedServerSong = ServerSong(
                songId: "matched-song",
                title: "Matched Song",
                artist: "Matched Artist",
                bpm: 120.0,
                isDownloaded: false
            )
            matchedServerSong.lastUpdated = Date()

            let unmatchedServerSong = ServerSong(
                songId: "unmatched-song",
                title: "Unmatched Song",
                artist: "Unmatched Artist",
                bpm: 100.0,
                isDownloaded: true
            )
            unmatchedServerSong.lastUpdated = Date().addingTimeInterval(-60)

            context.insert(matchedServerSong)
            context.insert(unmatchedServerSong)
            try context.save()

            let loadedSongs = try await cache.loadServerSongs(modelContext: context)

            #expect(loadedSongs.count == 2)
            #expect(loadedSongs.first?.songId == "matched-song") // Most recently updated first
            #expect(matchedServerSong.isDownloaded == true)
            #expect(unmatchedServerSong.isDownloaded == false)
        }
    }

    @Test("loadServerSongs keeps existing statuses when no local songs exist")
    func testLoadServerSongsRetainsUndownloadedStatusWithoutMatches() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let cache = ServerSongCache()

            let serverSong = ServerSong(
                songId: "cache-only",
                title: "Cache Only",
                artist: "No Local Match",
                bpm: 128.0,
                isDownloaded: false
            )
            serverSong.lastUpdated = Date()

            context.insert(serverSong)
            try context.save()

            let loadedSongs = try await cache.loadServerSongs(modelContext: context)

            #expect(loadedSongs.count == 1)
            #expect(loadedSongs.first?.songId == "cache-only")
            #expect(serverSong.isDownloaded == false)
        }
    }

    @Test("loadServerSongs returns empty list when stale cache refresh fails")
    func testLoadServerSongsStaleCacheRefreshFailure() async throws {
        let (userDefaults, suiteName) = TestUserDefaults.makeIsolated(
            suiteName: "ServerSongCacheTests.staleRefreshFailure.\(UUID().uuidString)"
        )
        userDefaults.set("://invalid-base-url", forKey: "DTXServerURL")
        let apiClient = DTXAPIClient(userDefaults: userDefaults)
        let cache = ServerSongCache(apiClient: apiClient)

        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context

            let staleSong = ServerSong(
                songId: "stale-cache",
                title: "Stale",
                artist: "Artist",
                bpm: 120.0,
                isDownloaded: false
            )
            staleSong.lastUpdated = Date().addingTimeInterval(-301)
            context.insert(staleSong)
            try context.save()

            let loadedSongs = try await cache.loadServerSongs(modelContext: context)

            #expect(loadedSongs.isEmpty)

            let persistedSongs = try context.fetch(FetchDescriptor<ServerSong>())
            #expect(persistedSongs.count == 1)
            #expect(persistedSongs.first?.songId == "stale-cache")
        }
    }

    @Test("loadServerSongs returns empty list when initial refresh fails")
    func testLoadServerSongsEmptyCacheRefreshFailure() async throws {
        let (userDefaults, suiteName) = TestUserDefaults.makeIsolated(
            suiteName: "ServerSongCacheTests.emptyRefreshFailure.\(UUID().uuidString)"
        )
        userDefaults.set("://invalid-base-url", forKey: "DTXServerURL")
        let apiClient = DTXAPIClient(userDefaults: userDefaults)
        let cache = ServerSongCache(apiClient: apiClient)

        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context

            let loadedSongs = try await cache.loadServerSongs(modelContext: context)

            #expect(loadedSongs.isEmpty)
            let persistedSongs = try context.fetch(FetchDescriptor<ServerSong>())
            #expect(persistedSongs.isEmpty)
        }
    }

    @Test("loadServerSongs refreshes empty cache and returns fetched songs")
    func testLoadServerSongsRefreshesEmptyCacheAndReturnsFetchedSongs() async throws {
        let (userDefaults, suiteName) = TestUserDefaults.makeIsolated(
            suiteName: "ServerSongCacheTests.loadRefreshSuccess.\(UUID().uuidString)"
        )
        userDefaults.set("https://example.test", forKey: "DTXServerURL")

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let apiClient = DTXAPIClient(userDefaults: userDefaults, session: session)
        let cache = ServerSongCache(apiClient: apiClient)

        let requestedPathsStore = RequestedPathsStore()
        MockURLProtocol.requestHandler = { request in
            let path = request.url?.path ?? ""
            requestedPathsStore.append(path)

            if path == "/dtx/list" {
                let payload = """
                {
                  "songs": [
                    {
                      "song_id": "fresh-song",
                      "title": "Fresh Song",
                      "artist": "Fresh Artist",
                      "bpm": 132.0,
                      "charts": [
                        {
                          "difficulty": "easy",
                          "difficulty_label": "BASIC",
                          "level": 20,
                          "filename": "fresh_easy.dtx",
                          "size": 1024
                        }
                      ]
                    }
                  ],
                  "individual_files": []
                }
                """
                return (200, Data(payload.utf8))
            }

            return (404, Data())
        }

        defer {
            MockURLProtocol.requestHandler = nil
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context

            let loadedSongs = try await cache.loadServerSongs(modelContext: context)

            #expect(loadedSongs.count == 1)
            #expect(loadedSongs.first?.songId == "fresh-song")
            #expect(loadedSongs.first?.title == "Fresh Song")
            #expect(loadedSongs.first?.charts.count == 1)
            #expect(requestedPathsStore.snapshot() == ["/dtx/list", "/dtx/list"])
        }
    }

    private func makeMultiSongMockRequestHandler(
        requestedPathsStore: RequestedPathsStore
    ) -> ((URLRequest) throws -> (Int, Data)) {
        return { request in
            let path = request.url?.path ?? ""
            requestedPathsStore.append(path)

            if path == "/dtx/list" {
                let payload = """
                {
                  "songs": [
                    {
                      "song_id": "multi-song",
                      "title": "Multi Song",
                      "artist": null,
                      "bpm": null,
                      "charts": [
                        {
                          "difficulty": "expert",
                          "difficulty_label": "MASTER",
                          "level": 90,
                          "filename": "master.dtx",
                          "size": 2048
                        }
                      ]
                    }
                  ],
                  "individual_files": [
                    {"filename": "legacy_ok.dtx", "size": 111},
                    {"filename": "legacy_fail.dtx", "size": 222}
                  ]
                }
                """
                return (200, Data(payload.utf8))
            }

            if path == "/dtx/metadata/legacy_ok.dtx" {
                let payload = """
                {
                  "filename": "legacy_ok.dtx",
                  "metadata": {
                    "title": "Legacy Name",
                    "artist": "Legacy Artist",
                    "bpm": 140.0,
                    "level": 42
                  }
                }
                """
                return (200, Data(payload.utf8))
            }

            if path == "/dtx/metadata/legacy_fail.dtx" {
                return (500, Data())
            }

            return (404, Data())
        }
    }

    private func setupMultiSongTestContext(_ context: ModelContext) throws {
        let localSong = Song(
            title: "Multi Song",
            artist: "Unknown Artist",
            bpm: 120.0,
            duration: "3:00",
            genre: "DTX Import",
            bgmFilePath: "/tmp/bgm.ogg",
            previewFilePath: "/tmp/preview.mp3"
        )
        context.insert(localSong)

        let existingServerSong = ServerSong(
            songId: "existing-old",
            title: "Old Song",
            artist: "Old Artist",
            bpm: 100.0,
            isDownloaded: false
        )
        context.insert(existingServerSong)
        try context.save()
    }

    @Test("refreshServerSongs processes multi-difficulty songs and metadata fallback")
    func testRefreshServerSongsProcessesServerPayloads() async throws {
        let (userDefaults, suiteName) = TestUserDefaults.makeIsolated(
            suiteName: "ServerSongCacheTests.refreshPayloads.\(UUID().uuidString)"
        )
        userDefaults.set("https://example.test", forKey: "DTXServerURL")

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let apiClient = DTXAPIClient(userDefaults: userDefaults, session: session)
        let cache = ServerSongCache(apiClient: apiClient)

        let requestedPathsStore = RequestedPathsStore()
        MockURLProtocol.requestHandler = makeMultiSongMockRequestHandler(requestedPathsStore: requestedPathsStore)

        defer {
            MockURLProtocol.requestHandler = nil
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            try setupMultiSongTestContext(context)
            try await cache.refreshServerSongs(modelContext: context)

            let serverSongs = try context.fetch(FetchDescriptor<ServerSong>())
            #expect(serverSongs.count == 3)
            #expect(serverSongs.contains { $0.songId == "multi-song" })
            #expect(serverSongs.contains { $0.songId == "legacy_ok" })
            #expect(serverSongs.contains { $0.songId == "legacy_fail" })
            #expect(serverSongs.contains { $0.songId == "existing-old" } == false)

            let multiSong = serverSongs.first { $0.songId == "multi-song" }
            #expect(multiSong?.artist == "Unknown Artist")
            #expect(multiSong?.bpm == 120.0)
            #expect(multiSong?.isDownloaded == true)
            #expect(multiSong?.bgmDownloaded == true)
            #expect(multiSong?.previewDownloaded == true)
            #expect(multiSong?.charts.count == 1)
            #expect(multiSong?.charts.first?.filename == "master.dtx")

            let fallbackSong = serverSongs.first { $0.songId == "legacy_fail" }
            #expect(fallbackSong?.title == "legacy_fail")
            #expect(fallbackSong?.artist == "Unknown Artist")
            #expect(fallbackSong?.bpm == 120.0)

            let capturedPaths = requestedPathsStore.snapshot()
            #expect(capturedPaths.contains("/dtx/list"))
            #expect(capturedPaths.contains("/dtx/metadata/legacy_ok.dtx"))
            #expect(capturedPaths.contains("/dtx/metadata/legacy_fail.dtx"))
        }
    }

    @Test("refreshServerSongs forceClear skips legacy file metadata requests")
    func testRefreshServerSongsForceClearSkipsLegacyFiles() async throws {
        let (userDefaults, suiteName) = TestUserDefaults.makeIsolated(
            suiteName: "ServerSongCacheTests.forceClear.\(UUID().uuidString)"
        )
        userDefaults.set("https://example.test", forKey: "DTXServerURL")

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let apiClient = DTXAPIClient(userDefaults: userDefaults, session: session)
        let cache = ServerSongCache(apiClient: apiClient)

        let requestedPathsStore = RequestedPathsStore()

        MockURLProtocol.requestHandler = { request in
            let path = request.url?.path ?? ""
            requestedPathsStore.append(path)

            if path == "/dtx/list" {
                let payload = """
                {
                  "songs": [
                    {
                      "song_id": "force-song",
                      "title": "Force Song",
                      "artist": "Force Artist",
                      "bpm": 150.0,
                      "charts": [
                        {
                          "difficulty": "hard",
                          "difficulty_label": "EXTREME",
                          "level": 70,
                          "filename": "hard.dtx",
                          "size": 3000
                        }
                      ]
                    }
                  ],
                  "individual_files": [
                    {"filename": "legacy_should_not_load.dtx", "size": 999}
                  ]
                }
                """
                return (200, Data(payload.utf8))
            }

            return (404, Data())
        }

        defer {
            MockURLProtocol.requestHandler = nil
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context

            try await cache.refreshServerSongs(modelContext: context, forceClear: true)

            let serverSongs = try context.fetch(FetchDescriptor<ServerSong>())
            #expect(serverSongs.count == 1)
            #expect(serverSongs.first?.songId == "force-song")
            #expect(serverSongs.first?.charts.count == 1)
            #expect(serverSongs.first?.charts.first?.filename == "hard.dtx")

            let capturedPaths = requestedPathsStore.snapshot()
            #expect(capturedPaths == ["/dtx/list"])
        }
    }

    @Test("refreshServerSongs rethrows when insertion save fails")
    func testRefreshServerSongsInsertionSaveFailure() async throws {
        let (userDefaults, suiteName) = TestUserDefaults.makeIsolated(
            suiteName: "ServerSongCacheTests.insertionSaveFailure.\(UUID().uuidString)"
        )
        userDefaults.set("https://example.test", forKey: "DTXServerURL")

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let apiClient = DTXAPIClient(userDefaults: userDefaults, session: session)

        var saveCalls = 0
        let cache = ServerSongCache(
            apiClient: apiClient,
            saveContext: { _ in
                saveCalls += 1
                throw SaveHookError.forced
            }
        )

        MockURLProtocol.requestHandler = { request in
            if request.url?.path == "/dtx/list" {
                let payload = """
                {
                  "songs": [
                    {
                      "song_id": "insert-fail-song",
                      "title": "Insert Fail",
                      "artist": "Artist",
                      "bpm": 120.0,
                      "charts": []
                    }
                  ],
                  "individual_files": []
                }
                """
                return (200, Data(payload.utf8))
            }
            return (404, Data())
        }

        defer {
            MockURLProtocol.requestHandler = nil
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context

            var didThrow = false
            do {
                try await cache.refreshServerSongs(modelContext: context, forceClear: true)
            } catch {
                didThrow = true
            }

            #expect(didThrow)
            #expect(saveCalls == 1)
        }
    }

    @Test("refreshServerSongs rethrows when clearExistingServerSongs batch save fails")
    func testRefreshServerSongsClearExistingSaveFailure() async throws {
        let (userDefaults, suiteName) = TestUserDefaults.makeIsolated(
            suiteName: "ServerSongCacheTests.clearExistingSaveFailure.\(UUID().uuidString)"
        )
        userDefaults.set("https://example.test", forKey: "DTXServerURL")

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let apiClient = DTXAPIClient(userDefaults: userDefaults, session: session)

        var saveCalls = 0
        let cache = ServerSongCache(
            apiClient: apiClient,
            saveContext: { _ in
                saveCalls += 1
                throw SaveHookError.forced
            }
        )

        MockURLProtocol.requestHandler = { request in
            if request.url?.path == "/dtx/list" {
                let payload = """
                {
                  "songs": [
                    {
                      "song_id": "refresh-song",
                      "title": "Refresh Song",
                      "artist": "Artist",
                      "bpm": 123.0,
                      "charts": []
                    }
                  ],
                  "individual_files": []
                }
                """
                return (200, Data(payload.utf8))
            }
            return (404, Data())
        }

        defer {
            MockURLProtocol.requestHandler = nil
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            context.insert(ServerSong(songId: "existing-song", title: "Existing", artist: "Artist", bpm: 100.0))
            try context.save()

            var didThrow = false
            do {
                try await cache.refreshServerSongs(modelContext: context, forceClear: true)
            } catch {
                didThrow = true
            }

            #expect(didThrow)
            #expect(saveCalls == 1)
        }
    }

    @Test("refreshServerSongs applies defaults when metadata fields are null")
    func testRefreshServerSongsMetadataNullFieldDefaults() async throws {
        let (userDefaults, suiteName) = TestUserDefaults.makeIsolated(
            suiteName: "ServerSongCacheTests.metadataNullDefaults.\(UUID().uuidString)"
        )
        userDefaults.set("https://example.test", forKey: "DTXServerURL")

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let apiClient = DTXAPIClient(userDefaults: userDefaults, session: session)
        let cache = ServerSongCache(apiClient: apiClient)

        MockURLProtocol.requestHandler = { request in
            let path = request.url?.path ?? ""
            if path == "/dtx/list" {
                let payload = """
                {
                  "songs": [],
                  "individual_files": [
                    {"filename": "legacy_nulls.dtx", "size": 333}
                  ]
                }
                """
                return (200, Data(payload.utf8))
            }

            if path == "/dtx/metadata/legacy_nulls.dtx" {
                let payload = """
                {
                  "filename": "legacy_nulls.dtx",
                  "metadata": {
                    "title": null,
                    "artist": null,
                    "bpm": null,
                    "level": null
                  }
                }
                """
                return (200, Data(payload.utf8))
            }

            return (404, Data())
        }

        defer {
            MockURLProtocol.requestHandler = nil
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context

            try await cache.refreshServerSongs(modelContext: context)

            let serverSongs = try context.fetch(FetchDescriptor<ServerSong>())
            #expect(serverSongs.count == 1)

            let song = serverSongs[0]
            #expect(song.title == "legacy_nulls")
            #expect(song.artist == "Unknown Artist")
            #expect(song.bpm == 120.0)
            #expect(song.charts.first?.level == 50)
        }
    }
}
