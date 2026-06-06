import Testing
import Foundation
@testable import Virgo

@Suite("ServerConfig Tests")
struct ServerConfigTests {
    private func makeConfig(_ name: String) -> (ServerConfig, UserDefaults) {
        let (defaults, _) = TestUserDefaults.makeIsolated(suiteName: name)
        return (ServerConfig(userDefaults: defaults), defaults)
    }

    @Test("Defaults to local endpoint and empty R2 base")
    func testDefaults() {
        let (config, _) = makeConfig("config.defaults")
        #expect(config.graphQLEndpoint == URL(string: "http://127.0.0.1:8001/graphql"))
        #expect(config.r2BaseURL == nil)
    }

    @Test("Stores and trims overrides")
    func testOverrides() {
        let (config, _) = makeConfig("config.override")
        config.setGraphQLEndpoint("https://api.example.com/graphql/")
        config.setR2BaseURL("https://r2.example.com/bucket/")
        #expect(config.graphQLEndpoint == URL(string: "https://api.example.com/graphql"))
        #expect(config.r2BaseURL == URL(string: "https://r2.example.com/bucket"))
    }

    @Test("Rejects non-http schemes and falls back")
    func testInvalidScheme() {
        let (config, _) = makeConfig("config.invalid")
        config.setGraphQLEndpoint("ftp://nope")
        #expect(config.graphQLEndpoint == URL(string: "http://127.0.0.1:8001/graphql"))
    }
}
