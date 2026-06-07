import Foundation

/// Configurable backend URLs, persisted in UserDefaults.
/// - GraphQL endpoint is the sole server access path (legacy REST `DTXServerURL` removed).
/// - R2 base URL is used to assemble public audio URLs.
final class ServerConfig {
    static let graphQLEndpointKey = "GraphQLEndpointURL"
    static let r2BaseURLKey = "R2BaseURL"
    private static let defaultEndpoint = "http://127.0.0.1:8001/graphql"

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var graphQLEndpoint: URL {
        let raw = userDefaults.string(forKey: Self.graphQLEndpointKey) ?? Self.defaultEndpoint
        let validated = Self.normalized(raw) ?? Self.defaultEndpoint
        return URL(string: validated) ?? URL(string: Self.defaultEndpoint)!
    }

    var r2BaseURL: URL? {
        guard let raw = userDefaults.string(forKey: Self.r2BaseURLKey),
              !raw.isEmpty,
              let normalized = Self.normalized(raw) else { return nil }
        return URL(string: normalized)
    }

    func setGraphQLEndpoint(_ value: String) {
        guard let normalized = Self.normalized(value) else {
            userDefaults.removeObject(forKey: Self.graphQLEndpointKey)
            return
        }
        userDefaults.set(normalized, forKey: Self.graphQLEndpointKey)
    }

    func setR2BaseURL(_ value: String) {
        guard let normalized = Self.normalized(value) else {
            userDefaults.removeObject(forKey: Self.r2BaseURLKey)
            return
        }
        userDefaults.set(normalized, forKey: Self.r2BaseURLKey)
    }

    /// Validate http/https + host, drop a single trailing slash.
    private static func normalized(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty else {
            return nil
        }
        if trimmed.hasSuffix("/") && !trimmed.hasSuffix("//") {
            return String(trimmed.dropLast())
        }
        return trimmed
    }
}
