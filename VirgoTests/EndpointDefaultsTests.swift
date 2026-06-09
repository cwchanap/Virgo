import Testing
import Foundation
@testable import Virgo

@Suite("EndpointDefaults Tests")
struct EndpointDefaultsTests {

    @Test("parse reads GRAPHQL_ENDPOINT and R2_BASE_URL keys")
    func testParseReadsKeys() {
        let env = EndpointDefaults.parse("""
        GRAPHQL_ENDPOINT=https://api.example.com/graphql
        R2_BASE_URL=https://r2.example.com
        """)
        #expect(env.graphQLEndpoint == "https://api.example.com/graphql")
        #expect(env.r2BaseURL == "https://r2.example.com")
    }

    @Test("parse ignores blank lines and comments")
    func testParseIgnoresBlankAndComments() {
        let env = EndpointDefaults.parse("""
        # this is a comment
        GRAPHQL_ENDPOINT=https://api.example.com/graphql


        # another comment
        R2_BASE_URL=https://r2.example.com
        """)
        #expect(env.graphQLEndpoint == "https://api.example.com/graphql")
        #expect(env.r2BaseURL == "https://r2.example.com")
    }

    @Test("parse trims surrounding whitespace and matching quotes")
    func testParseTrimsWhitespaceAndQuotes() {
        let env = EndpointDefaults.parse("""
        GRAPHQL_ENDPOINT = "https://api.example.com/graphql"
        R2_BASE_URL =  'https://r2.example.com'  
        """)
        #expect(env.graphQLEndpoint == "https://api.example.com/graphql")
        #expect(env.r2BaseURL == "https://r2.example.com")
    }

    @Test("parse returns nil for absent keys")
    func testParseAbsentKeys() {
        let env = EndpointDefaults.parse("GRAPHQL_ENDPOINT=https://api.example.com/graphql\n")
        #expect(env.graphQLEndpoint != nil)
        #expect(env.r2BaseURL == nil)
    }

    @Test("parse of empty content yields no defaults")
    func testParseEmpty() {
        let env = EndpointDefaults.parse("")
        #expect(env.graphQLEndpoint == nil)
        #expect(env.r2BaseURL == nil)
    }

    @Test("parse yields empty string for keys with no value (CI vars unset case)")
    func testParseEmptyValues() {
        // CI generates `KEY=` (empty) when repository variables are unset.
        let env = EndpointDefaults.parse("""
        GRAPHQL_ENDPOINT=
        R2_BASE_URL=
        """)
        #expect(env.graphQLEndpoint?.isEmpty == true)
        #expect(env.r2BaseURL?.isEmpty == true)
    }

    @Test("Empty-string .env values cause ServerConfig to fall back (CI vars unset)")
    func testServerConfigFallsBackOnEmptyEnvValues() {
        let (defaults, _) = TestUserDefaults.makeIsolated(suiteName: "config.emptyenv")
        // Mirrors exactly what generate-endpoints-env.sh writes when CI vars are unset.
        let config = ServerConfig(
            userDefaults: defaults,
            endpointDefaults: EndpointDefaults(graphQLEndpoint: "", r2BaseURL: "")
        )
        #expect(config.graphQLEndpoint == URL(string: "http://127.0.0.1:8001/graphql"))
        #expect(config.r2BaseURL == nil)
    }

    @Test("load returns empty defaults when resource is absent")
    func testLoadMissingResource() {
        let env = EndpointDefaults.load(resource: "DefinitelyNotPresent", extension: "env")
        #expect(env.graphQLEndpoint == nil)
        #expect(env.r2BaseURL == nil)
    }

    @Test("load accepts custom subdirectory parameter")
    func testLoadCustomSubdirectory() {
        // Should not crash and should return empty when the custom
        // subdirectory does not contain the resource.
        let env = EndpointDefaults.load(
            resource: "DefinitelyNotPresent",
            extension: "env",
            subdirectory: "NonexistentDir"
        )
        #expect(env.graphQLEndpoint == nil)
        #expect(env.r2BaseURL == nil)
    }
}
