import Foundation

/// Configurable backend URLs.
///
/// Resolution order (highest precedence first):
/// 1. `UserDefaults` override (set via the settings UI).
/// 2. `EndpointDefaults` loaded from the bundled `ServerEndpoints.env`.
/// 3. A hard-coded local-dev fallback so the build never breaks when neither
///    is present (e.g. a fresh checkout with no `.env`).
///
/// - GraphQL endpoint is the sole server access path (legacy REST `DTXServerURL` removed).
/// - R2 base URL is used to assemble public audio URLs.
final class ServerConfig {
    static let graphQLEndpointKey = "GraphQLEndpointURL"
    static let r2BaseURLKey = "R2BaseURL"
    /// Used only when no override and no `.env` default are available.
    private static let fallbackEndpoint = "http://127.0.0.1:8001/graphql"

    private let userDefaults: UserDefaults
    private let endpointDefaults: EndpointDefaults

    init(
        userDefaults: UserDefaults = .standard,
        endpointDefaults: EndpointDefaults = .load()
    ) {
        self.userDefaults = userDefaults
        self.endpointDefaults = endpointDefaults
    }

    var graphQLEndpoint: URL {
        let resolved = userDefaults.string(forKey: Self.graphQLEndpointKey)
            ?? endpointDefaults.graphQLEndpoint
            ?? Self.fallbackEndpoint
        let validated = Self.normalized(resolved) ?? Self.fallbackEndpoint
        return URL(string: validated) ?? URL(string: Self.fallbackEndpoint)!
    }

    var r2BaseURL: URL? {
        // 1. Explicit UserDefaults override wins.
        if let raw = userDefaults.string(forKey: Self.r2BaseURLKey),
           !raw.isEmpty,
           let normalized = Self.normalized(raw) {
            return URL(string: normalized)
        }
        // 2. `.env` default.
        if let raw = endpointDefaults.r2BaseURL,
           let normalized = Self.normalized(raw) {
            return URL(string: normalized)
        }
        // 3. No R2 base configured → audio downloads are skipped (by the downloader).
        return nil
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
