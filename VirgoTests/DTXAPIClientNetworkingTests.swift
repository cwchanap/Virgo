import Testing
import Foundation
@testable import Virgo

@Suite("DTX API Client Networking Tests", .serialized)
struct DTXAPIClientNetworkingTests {
    private final class MockURLProtocol: URLProtocol {
        static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

        override class func canInit(with request: URLRequest) -> Bool {
            true
        }

        override class func canonicalRequest(for request: URLRequest) -> URLRequest {
            request
        }

        override func startLoading() {
            guard let handler = Self.requestHandler else {
                client?.urlProtocol(self, didFailWithError: URLError(.badURL))
                return
            }

            do {
                let (response, data) = try handler(request)
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }

        override func stopLoading() {}
    }

    private func makeClient(
        suiteName: String,
        baseURL: String = "https://example.test"
    ) -> (DTXAPIClient, UserDefaults, String) {
        let (userDefaults, fullSuiteName) = TestUserDefaults.makeIsolated(suiteName: suiteName)
        userDefaults.set(baseURL, forKey: "DTXServerURL")

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)

        let client = DTXAPIClient(userDefaults: userDefaults, session: session)
        return (client, userDefaults, fullSuiteName)
    }

    @Test("listDTXFiles decodes individual files from API response")
    func testListDTXFilesSuccess() async throws {
        let (client, userDefaults, suiteName) = makeClient(
            suiteName: "DTXAPIClientNetworkingTests.listFiles.\(UUID().uuidString)"
        )
        defer {
            MockURLProtocol.requestHandler = nil
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        MockURLProtocol.requestHandler = { request in
            #expect(request.url?.absoluteString == "https://example.test/dtx/list")

            let payload = """
            {
              "songs": [],
              "individual_files": [
                {"filename": "alpha.dtx", "size": 123},
                {"filename": "beta.dtx", "size": 456}
              ]
            }
            """

            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://example.test")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(payload.utf8))
        }

        let files = try await client.listDTXFiles()

        #expect(files.count == 2)
        #expect(files[0].filename == "alpha.dtx")
        #expect(files[0].size == 123)
        #expect(files[1].filename == "beta.dtx")
        #expect(client.errorMessage == nil)
        #expect(client.isLoading == false)
    }

    @Test("listDTXSongs decodes songs and nested chart metadata")
    func testListDTXSongsSuccess() async throws {
        let (client, userDefaults, suiteName) = makeClient(
            suiteName: "DTXAPIClientNetworkingTests.listSongs.\(UUID().uuidString)"
        )
        defer {
            MockURLProtocol.requestHandler = nil
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        MockURLProtocol.requestHandler = { request in
            #expect(request.url?.absoluteString == "https://example.test/dtx/list")

            let payload = """
            {
              "songs": [
                {
                  "song_id": "song-a",
                  "title": "Song A",
                  "artist": "Artist A",
                  "bpm": 150.5,
                  "charts": [
                    {
                      "difficulty": "hard",
                      "difficulty_label": "EXTREME",
                      "level": 72,
                      "filename": "ext.dtx",
                      "size": 2048
                    }
                  ]
                }
              ],
              "individual_files": []
            }
            """

            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://example.test")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(payload.utf8))
        }

        let songs = try await client.listDTXSongs()

        #expect(songs.count == 1)
        #expect(songs[0].songId == "song-a")
        #expect(songs[0].title == "Song A")
        #expect(songs[0].artist == "Artist A")
        #expect(songs[0].bpm == 150.5)
        #expect(songs[0].charts.count == 1)
        #expect(songs[0].charts[0].difficulty == "hard")
        #expect(songs[0].charts[0].difficultyLabel == "EXTREME")
        #expect(songs[0].charts[0].filename == "ext.dtx")
    }

    @Test("getDTXMetadata decodes metadata payload")
    func testGetDTXMetadataSuccess() async throws {
        let (client, userDefaults, suiteName) = makeClient(
            suiteName: "DTXAPIClientNetworkingTests.metadata.\(UUID().uuidString)"
        )
        defer {
            MockURLProtocol.requestHandler = nil
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        MockURLProtocol.requestHandler = { request in
            #expect(request.url?.absoluteString == "https://example.test/dtx/metadata/master.dtx")

            let payload = """
            {
              "filename": "master.dtx",
              "metadata": {
                "title": "Master Song",
                "artist": "Master Artist",
                "bpm": 188.0,
                "level": 90
              }
            }
            """

            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://example.test")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(payload.utf8))
        }

        let metadata = try await client.getDTXMetadata(filename: "master.dtx")

        #expect(metadata.filename == "master.dtx")
        #expect(metadata.title == "Master Song")
        #expect(metadata.artist == "Master Artist")
        #expect(metadata.bpm == 188.0)
        #expect(metadata.level == 90)
    }

    @Test("download endpoints request expected URL paths and return data")
    func testDownloadEndpointsSuccess() async throws {
        let (client, userDefaults, suiteName) = makeClient(
            suiteName: "DTXAPIClientNetworkingTests.downloads.\(UUID().uuidString)"
        )
        defer {
            MockURLProtocol.requestHandler = nil
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        var requestedPaths: [String] = []
        MockURLProtocol.requestHandler = { request in
            let path = request.url?.path ?? ""
            requestedPaths.append(path)

            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://example.test")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("payload:\(path)".utf8))
        }

        let dtxData = try await client.downloadDTXFile(filename: "song.dtx")
        let bgmData = try await client.downloadBGMFile(songId: "song-a")
        let previewData = try await client.downloadPreviewFile(songId: "song-a")
        let chartData = try await client.downloadChartFile(songId: "song-a", chartFilename: "master.dtx")

        #expect(String(data: dtxData, encoding: .utf8) == "payload:/dtx/download/song.dtx")
        #expect(String(data: bgmData, encoding: .utf8) == "payload:/dtx/download/song-a/bgm.ogg")
        #expect(String(data: previewData, encoding: .utf8) == "payload:/dtx/download/song-a/preview.mp3")
        #expect(String(data: chartData, encoding: .utf8) == "payload:/dtx/download/song-a/master.dtx")

        #expect(requestedPaths == [
            "/dtx/download/song.dtx",
            "/dtx/download/song-a/bgm.ogg",
            "/dtx/download/song-a/preview.mp3",
            "/dtx/download/song-a/master.dtx"
        ])
    }

    @Test("performRequest stores error message when decoding fails")
    func testPerformRequestDecodingFailureSetsError() async throws {
        let (client, userDefaults, suiteName) = makeClient(
            suiteName: "DTXAPIClientNetworkingTests.decodeFailure.\(UUID().uuidString)"
        )
        defer {
            MockURLProtocol.requestHandler = nil
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://example.test")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("{\"songs\":\"not-an-array\"}".utf8))
        }

        do {
            _ = try await client.listDTXFiles()
            Issue.record("Expected listDTXFiles to throw on invalid payload")
        } catch let DTXAPIError.networkError(error) {
            #expect(error is DecodingError)
        }

        #expect(client.isLoading == false)
        #expect(client.errorMessage?.isEmpty == false)
    }

    @Test("downloadData throws network error for non-200 response")
    func testDownloadDataHandlesBadStatusCode() async throws {
        let (client, userDefaults, suiteName) = makeClient(
            suiteName: "DTXAPIClientNetworkingTests.badStatus.\(UUID().uuidString)"
        )
        defer {
            MockURLProtocol.requestHandler = nil
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://example.test")!,
                statusCode: 500,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        do {
            _ = try await client.downloadBGMFile(songId: "song-a")
            Issue.record("Expected downloadBGMFile to throw on 500 response")
        } catch let DTXAPIError.networkError(error) {
            guard case let DTXAPIError.networkError(innerError) = error,
                  let urlError = innerError as? URLError else {
                Issue.record("Expected nested DTXAPIError.networkError wrapping URLError.badServerResponse")
                return
            }
            #expect(urlError.code == .badServerResponse)
        }

        #expect(client.isLoading == false)
        #expect(client.errorMessage?.contains("Network error") == true)
    }
}
