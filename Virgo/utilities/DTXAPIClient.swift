import Foundation

enum DTXAPIError: LocalizedError {
    case invalidURL
    case noData
    case decodingError
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid server URL"
        case .noData:
            return "No data received from server"
        case .decodingError:
            return "Failed to decode server response"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

/// HTTP client used as a `FileDownloading` implementation by `ServerSongDownloader`.
/// The legacy REST configuration layer (`DTXServerURL`, `setServerURL`,
/// `testConnection`, `performRequest`) was removed after the GraphQL migration;
/// catalog access now goes through `ApolloSimfileClient` → `ServerConfig`.
class DTXAPIClient: ObservableObject {
    @Published var isLoading = false
    @Published var errorMessage: String?

    internal let session: URLSession
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard, session: URLSession? = nil) {
        self.userDefaults = userDefaults

        if let session = session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 30.0
            config.timeoutIntervalForResource = 60.0
            config.httpMaximumConnectionsPerHost = 2
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            config.waitsForConnectivity = true
            config.allowsConstrainedNetworkAccess = true
            config.allowsExpensiveNetworkAccess = true

            self.session = URLSession(configuration: config)
        }
    }
}

// MARK: - File Downloading

extension DTXAPIClient {
    func downloadData(from url: URL) async throws -> Data {
        await updateLoadingState(isLoading: true, error: nil)

        do {
            let (data, response) = try await session.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw DTXAPIError.networkError(URLError(.badServerResponse))
            }

            await updateLoadingState(isLoading: false, error: nil)
            return data
        } catch let error as DTXAPIError {
            await updateLoadingState(isLoading: false, error: error.localizedDescription)
            throw error
        } catch {
            await updateLoadingState(isLoading: false, error: error.localizedDescription)
            throw DTXAPIError.networkError(error)
        }
    }

    @MainActor
    private func updateLoadingState(isLoading: Bool, error: String?) {
        self.isLoading = isLoading
        self.errorMessage = error
    }
}

extension DTXAPIClient: FileDownloading {}
