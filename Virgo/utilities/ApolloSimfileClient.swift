import Foundation
import Apollo

/// Apollo-backed implementation of `SimfileFetching`.
/// This is the only type that depends on the generated GraphQL code.
final class ApolloSimfileClient: SimfileFetching {
    private let apollo: ApolloClient

    init(endpointURL: URL) {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30.0
        config.timeoutIntervalForResource = 60.0
        config.httpMaximumConnectionsPerHost = 2
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.waitsForConnectivity = true

        let store = ApolloStore(cache: InMemoryNormalizedCache())
        let client = URLSessionClient(sessionConfiguration: config)
        let provider = DefaultInterceptorProvider(client: client, store: store)
        let transport = RequestChainNetworkTransport(
            interceptorProvider: provider,
            endpointURL: endpointURL
        )
        self.apollo = ApolloClient(networkTransport: transport, store: store)
    }

    func fetchSimfiles(page: Int, pageSize: Int, search: String?) async throws -> SimfilePage {
        let query = VirgoGraphQL.SimfilesQuery(
            page: page,
            pageSize: pageSize,
            search: search.map { GraphQLNullable.some($0) } ?? .null
        )
        let data = try await fetch(query)
        let connection = data.simfiles
        let dtos = connection.data.map { Self.map(VirgoGraphQL.SimfileFields(_dataDict: $0.__data)) }
        return SimfilePage(simfiles: dtos, totalCount: connection.count)
    }

    func fetchSimfile(id: String) async throws -> SimfileDTO? {
        let data = try await fetch(VirgoGraphQL.SimfileQuery(id: id))
        return data.simfile.map { Self.map(VirgoGraphQL.SimfileFields(_dataDict: $0.__data)) }
    }

    // MARK: - Apollo bridging

    /// Fetches a GraphQL query, preserving partial data when field-level errors occur.
    ///
    /// GraphQL spec allows `{ data, errors }` coexistence — e.g. one chart's `fileUrl`
    /// may error while the rest of the payload is valid. We return available `data`
    /// and only throw when `data` is absent (true failure).
    private func fetch<Q: GraphQLQuery>(_ query: Q) async throws -> Q.Data {
        try await withCheckedThrowingContinuation { continuation in
            apollo.fetch(query: query, cachePolicy: .fetchIgnoringCacheCompletely) { result in
                switch result {
                case .success(let response):
                    if let data = response.data {
                        if let errors = response.errors, !errors.isEmpty {
                            Logger.warning(
                                "GraphQL partial data: \(errors.count) error(s) — " +
                                errors.compactMap(\.message).joined(separator: "; ")
                            )
                        }
                        continuation.resume(returning: data)
                    } else if let errors = response.errors, !errors.isEmpty {
                        continuation.resume(throwing: SimfileGraphQLError(graphQLErrors: errors))
                    } else {
                        continuation.resume(throwing: SimfileGraphQLError(graphQLErrors: []))
                    }
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Generated -> DTO mapping

    private static func map(_ s: VirgoGraphQL.SimfileFields) -> SimfileDTO {
        SimfileDTO(
            id: s.id,
            title: s.title,
            artist: s.artist,
            bpm: s.bpm,
            genre: s.genre,
            tags: s.tags,
            durationSeconds: s.durationSeconds,
            updatedAt: s.updatedAt,
            dtxFiles: s.dtxFiles.map { f in
                let rawEncoding = f.fileEncoding.rawValue
                let encoding: SimfileEncoding
                if let parsed = SimfileEncoding(rawValue: rawEncoding) {
                    encoding = parsed
                } else {
                    Logger.warning("Unknown file encoding '\(rawEncoding)' for \(f.label); defaulting to Shift-JIS")
                    encoding = .shiftJIS
                }
                return DtxFileDTO(
                    label: f.label,
                    level: f.level,
                    fileURL: f.fileUrl,
                    fileSizeBytes: f.fileSizeBytes,
                    encoding: encoding
                )
            },
            fileKeys: s.files.map { $0.key }
        )
    }
}

/// Wraps backend GraphQL `errors[]` for surfacing to the user.
struct SimfileGraphQLError: LocalizedError {
    let graphQLErrors: [GraphQLError]
    var errorDescription: String? {
        if let first = graphQLErrors.first { return first.message }
        return "GraphQL request failed"
    }
}
