import Testing
import Foundation
@testable import Virgo

@Suite("ServerConfig Tests")
struct ServerConfigTests {
    private func makeConfig(
        _ name: String,
        endpointDefaults: EndpointDefaults = EndpointDefaults()
    ) -> (ServerConfig, UserDefaults) {
        let (defaults, _) = TestUserDefaults.makeIsolated(suiteName: name)
        return (ServerConfig(userDefaults: defaults, endpointDefaults: endpointDefaults), defaults)
    }

    private let envGraphQL = "https://api.dtx.hapadona.com/graphql"
    private let envR2 = "https://pub-771b4400b6c14fa8995fea39c3eff077.r2.dev"

    @Test("Defaults to .env-provided endpoints when no override is set")
    func testDefaultsFromEnv() {
        let env = EndpointDefaults(graphQLEndpoint: envGraphQL, r2BaseURL: envR2)
        let (config, _) = makeConfig("config.defaults", endpointDefaults: env)
        #expect(config.graphQLEndpoint == URL(string: envGraphQL))
        #expect(config.r2BaseURL == URL(string: envR2))
    }

    @Test("Falls back to local-dev placeholder when .env is absent")
    func testFallbackWhenNoEnv() {
        // Empty EndpointDefaults simulates a fresh checkout with no ServerEndpoints.env.
        let (config, _) = makeConfig("config.fallback", endpointDefaults: EndpointDefaults())
        #expect(config.graphQLEndpoint == URL(string: "http://127.0.0.1:8001/graphql"))
        #expect(config.r2BaseURL == nil)
    }

    @Test("Stores and trims overrides")
    func testOverrides() {
        let env = EndpointDefaults(graphQLEndpoint: envGraphQL, r2BaseURL: envR2)
        let (config, _) = makeConfig("config.override", endpointDefaults: env)
        config.setGraphQLEndpoint("https://api.example.com/graphql/")
        config.setR2BaseURL("https://r2.example.com/bucket/")
        #expect(config.graphQLEndpoint == URL(string: "https://api.example.com/graphql"))
        #expect(config.r2BaseURL == URL(string: "https://r2.example.com/bucket"))
    }

    @Test("UserDefaults override beats .env default")
    func testOverrideBeatsEnv() {
        let env = EndpointDefaults(graphQLEndpoint: envGraphQL, r2BaseURL: envR2)
        let (config, defaults) = makeConfig("config.envoverride", endpointDefaults: env)
        defaults.set("https://staging.example.com/graphql", forKey: ServerConfig.graphQLEndpointKey)
        #expect(config.graphQLEndpoint == URL(string: "https://staging.example.com/graphql"))
    }

    @Test("Rejects non-http schemes and falls back")
    func testInvalidScheme() {
        let (config, _) = makeConfig("config.invalid")
        config.setGraphQLEndpoint("ftp://nope")
        #expect(config.graphQLEndpoint == URL(string: "http://127.0.0.1:8001/graphql"))
    }

    @Test("Read-path rejects an invalid scheme pre-seeded directly in UserDefaults")
    func testInvalidSchemePreseeded() {
        let (config, defaults) = makeConfig("config.preseeded")
        // Bypass the setter to simulate a stale/corrupt persisted value.
        defaults.set("ftp://nope", forKey: ServerConfig.graphQLEndpointKey)
        #expect(config.graphQLEndpoint == URL(string: "http://127.0.0.1:8001/graphql"))
    }

    @Test("r2BaseURL falls back to nil when override is invalid and no .env default exists")
    func testR2BaseURLInvalidFallback() {
        let (config, defaults) = makeConfig("config.r2fallback")
        // Stale/corrupt persisted value must not produce a broken URL.
        defaults.set("ftp://nope", forKey: ServerConfig.r2BaseURLKey)
        #expect(config.r2BaseURL == nil)
    }
}
