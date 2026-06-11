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

    private func makeClient(suiteName: String) -> (DTXAPIClient, UserDefaults, String) {
        let (userDefaults, fullSuiteName) = TestUserDefaults.makeIsolated(suiteName: suiteName)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)

        let client = DTXAPIClient(userDefaults: userDefaults, session: session)
        return (client, userDefaults, fullSuiteName)
    }

    @Test("downloadData fetches bytes from an absolute URL")
    func testDownloadDataSuccess() async throws {
        let (client, userDefaults, suiteName) = makeClient(
            suiteName: "DTXAPIClientNetworkingTests.downloadData.\(UUID().uuidString)"
        )
        defer {
            MockURLProtocol.requestHandler = nil
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let target = URL(string: "https://r2.example/song-a/ext.dtx")!
        MockURLProtocol.requestHandler = { request in
            #expect(request.url == target)
            let response = HTTPURLResponse(
                url: request.url ?? target, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (response, Data("chart-bytes".utf8))
        }

        let data = try await client.downloadData(from: target)
        #expect(String(data: data, encoding: .utf8) == "chart-bytes")
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
            _ = try await client.downloadData(from: URL(string: "https://r2.example/song-a/bgm.ogg")!)
            Issue.record("Expected downloadData to throw on 500 response")
        } catch let DTXAPIError.networkError(error) {
            guard let urlError = error as? URLError else {
                Issue.record("Expected DTXAPIError.networkError wrapping URLError.badServerResponse")
                return
            }
            #expect(urlError.code == .badServerResponse)
        }
    }
}
