import Foundation
import Apollo

/// Apollo-backed implementation of `SimfileFetching`.
/// This is the only type that depends on the generated GraphQL code.
final class ApolloSimfileClient: SimfileFetching {
    private let apollo: ApolloClient

    init(endpointURL: URL) {
        self.apollo = ApolloClient(url: endpointURL)
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

    private func fetch<Q: GraphQLQuery>(_ query: Q) async throws -> Q.Data {
        try await withCheckedThrowingContinuation { continuation in
            apollo.fetch(query: query, cachePolicy: .fetchIgnoringCacheCompletely) { result in
                switch result {
                case .success(let response):
                    if let errors = response.errors, !errors.isEmpty {
                        continuation.resume(throwing: SimfileGraphQLError(graphQLErrors: errors))
                    } else if let data = response.data {
                        continuation.resume(returning: data)
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
