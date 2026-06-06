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

// MARK: - Protocol Definitions

protocol DTXNetworking {
    func performRequest<T: Codable>(url: URL, responseType: T.Type) async throws -> T
    func downloadData(from url: URL) async throws -> Data
}

protocol DTXConfiguration {
    var baseURL: String { get }
    func setServerURL(_ url: String)
    func resetToLocalServer()
    func testConnection() async -> Bool
}

// MARK: - Main DTXAPIClient Class

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

// MARK: - Configuration Extension

extension DTXAPIClient: DTXConfiguration {
    var baseURL: String {
        if let customURL = userDefaults.string(forKey: "DTXServerURL"), !customURL.isEmpty {
            return customURL
        }
        return "http://127.0.0.1:8001"
    }

    func setServerURL(_ url: String) {
        // If URL is empty or whitespace only, remove the custom URL to fall back to default
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedURL.isEmpty {
            userDefaults.removeObject(forKey: "DTXServerURL")
            return
        }
        
        // Validate and normalize the URL
        guard let parsedURL = URL(string: trimmedURL),
              let scheme = parsedURL.scheme,
              let host = parsedURL.host,
              ["http", "https"].contains(scheme.lowercased()),
              !host.isEmpty else {
            // Invalid URL: clear override to fall back to default
            userDefaults.removeObject(forKey: "DTXServerURL")
            return
        }
        
        // Normalize by removing single trailing slash to avoid // in path composition
        var normalizedURL = trimmedURL
        if normalizedURL.hasSuffix("/") && !normalizedURL.hasSuffix("//") {
            normalizedURL = String(normalizedURL.dropLast())
        }
        
        userDefaults.set(normalizedURL, forKey: "DTXServerURL")
    }

    func resetToLocalServer() {
        userDefaults.removeObject(forKey: "DTXServerURL")
    }

    func testConnection() async -> Bool {
        guard let url = URL(string: "\(baseURL)/") else {
            return false
        }

        do {
            let (_, response) = try await session.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
}

// MARK: - Networking Extension

extension DTXAPIClient: DTXNetworking {
    func performRequest<T: Codable>(url: URL, responseType: T.Type) async throws -> T {
        await updateLoadingState(isLoading: true, error: nil)

        do {
            let (data, _) = try await session.data(from: url)
            let response = try JSONDecoder().decode(responseType, from: data)

            await updateLoadingState(isLoading: false, error: nil)
            return response
        } catch {
            await updateLoadingState(isLoading: false, error: error.localizedDescription)
            throw DTXAPIError.networkError(error)
        }
    }

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

// MARK: - File Downloading Extension

extension DTXAPIClient: FileDownloading {}
