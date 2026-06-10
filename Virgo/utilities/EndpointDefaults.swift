import Foundation

/// Loads server endpoint defaults from a bundled `.env`-style file.
///
/// `ServerConfig` consults this before falling back to its hard-coded local-dev
/// placeholder. The file (`ServerEndpoints.env`) is gitignored and bundled as a
/// resource; it is absent on a fresh checkout, in which case `load` returns an
/// empty value and `ServerConfig` uses its safe fallbacks so the build never breaks.
///
/// Format (one `KEY=value` per line):
///   - Blank lines and lines starting with `#` are ignored.
///  - Surrounding whitespace and matching surrounding quotes are stripped.
struct EndpointDefaults {
    let graphQLEndpoint: String?
    let r2BaseURL: String?

    init(graphQLEndpoint: String? = nil, r2BaseURL: String? = nil) {
        self.graphQLEndpoint = graphQLEndpoint
        self.r2BaseURL = r2BaseURL
    }

    /// Reads and parses `ServerEndpoints.env` from `bundle`.
    /// Returns an empty `EndpointDefaults` if the file is missing or unreadable.
    static func load(
        from bundle: Bundle = .main,
        resource: String = "ServerEndpoints",
        extension ext: String = "env",
        subdirectory: String = "Config"
    ) -> EndpointDefaults {
        guard let url = bundle.url(forResource: resource, withExtension: ext, subdirectory: subdirectory),
              let data = try? Data(contentsOf: url),
              let content = String(data: data, encoding: .utf8) else {
            return EndpointDefaults()
        }
        return parse(content)
    }

    /// Parses `.env`-style content into keyed values, then maps the two consumed keys.
    static func parse(_ content: String) -> EndpointDefaults {
        var values: [String: String] = [:]
        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespacesAndNewlines)
            var value = String(line[line.index(after: eq)...].trimmingCharacters(in: .whitespacesAndNewlines))
            value = stripMatchingQuotes(value)
            values[String(key)] = value
        }
        return EndpointDefaults(
            graphQLEndpoint: values["GRAPHQL_ENDPOINT"],
            r2BaseURL: values["R2_BASE_URL"]
        )
    }

    /// Removes one matching pair of surrounding single or double quotes.
    private static func stripMatchingQuotes(_ value: String) -> String {
        guard value.count >= 2 else { return value }
        let first = value.first
        let last = value.last
        if (first == "\"" && last == "\"") || (first == "'" && last == "'") {
            return String(value.dropFirst().dropLast())
        }
        return value
    }
}
