import Foundation

struct DTXServerFile {
    let filename: String
    let size: Int
}

struct DTXServerSongData {
    let songId: String
    let title: String
    let artist: String?
    let bpm: Double?
    let charts: [DTXServerChartData]
}

struct DTXServerChartData {
    let difficulty: String
    let difficultyLabel: String
    let level: Int
    let filename: String
    let size: Int
}

struct DTXServerMetadata {
    let filename: String
    let title: String?
    let artist: String?
    let bpm: Double?
    let level: Int?
}

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

class DTXAPIClient: ObservableObject {
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let session: URLSession

    init() {
        // Configure URLSession for background networking with optimized settings
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30.0
        config.timeoutIntervalForResource = 60.0

        // Reduce connection pooling to prevent socket warnings
        config.httpMaximumConnectionsPerHost = 2
        config.requestCachePolicy = .reloadIgnoringLocalCacheData

        // Configure for better network efficiency
        config.waitsForConnectivity = true
        config.allowsConstrainedNetworkAccess = true
        config.allowsExpensiveNetworkAccess = true

        self.session = URLSession(configuration: config)
    }

    // Configurable base URL - defaults to local development server
    var baseURL: String {
        if let customURL = UserDefaults.standard.string(forKey: "DTXServerURL"), !customURL.isEmpty {
            return customURL
        }
        return "http://127.0.0.1:8001"
    }

    // MARK: - Public API

    func listDTXFiles() async throws -> [DTXServerFile] {
        guard let url = URL(string: "\(baseURL)/dtx/list") else {
            throw DTXAPIError.invalidURL
        }

        // Update UI state on main thread
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }

        do {
            // Network call runs in background
            let (data, _) = try await session.data(from: url)
            let response = try JSONDecoder().decode(DTXListResponse.self, from: data)

            // Update UI state on main thread
            await MainActor.run {
                isLoading = false
            }

            return response.individualFiles?.map { DTXServerFile(filename: $0.filename, size: $0.size) } ?? []
        } catch {
            // Update UI state on main thread
            await MainActor.run {
                isLoading = false
                errorMessage = error.localizedDescription
            }
            throw DTXAPIError.networkError(error)
        }
    }

    func listDTXSongs() async throws -> [DTXServerSongData] {
        guard let url = URL(string: "\(baseURL)/dtx/list") else {
            throw DTXAPIError.invalidURL
        }

        // Update UI state on main thread
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }

        do {
            // Network call runs in background
            let (data, _) = try await session.data(from: url)
            let response = try JSONDecoder().decode(DTXListResponse.self, from: data)

            // Update UI state on main thread
            await MainActor.run {
                isLoading = false
            }

            return response.songs.map { songInfo in
                DTXServerSongData(
                    songId: songInfo.songId,
                    title: songInfo.title,
                    artist: songInfo.artist,
                    bpm: songInfo.bpm,
                    charts: songInfo.charts.map { chartInfo in
                        DTXServerChartData(
                            difficulty: chartInfo.difficulty,
                            difficultyLabel: chartInfo.difficultyLabel,
                            level: chartInfo.level,
                            filename: chartInfo.filename,
                            size: chartInfo.size
                        )
                    }
                )
            }
        } catch {
            // Update UI state on main thread
            await MainActor.run {
                isLoading = false
                errorMessage = error.localizedDescription
            }
            throw DTXAPIError.networkError(error)
        }
    }

    func getDTXMetadata(filename: String) async throws -> DTXServerMetadata {
        guard let url = URL(string: "\(baseURL)/dtx/metadata/\(filename)") else {
            throw DTXAPIError.invalidURL
        }

        // Update UI state on main thread
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }

        do {
            // Network call runs in background
            let (data, _) = try await session.data(from: url)
            let response = try JSONDecoder().decode(DTXMetadataResponse.self, from: data)

            // Update UI state on main thread
            await MainActor.run {
                isLoading = false
            }

            return DTXServerMetadata(
                filename: response.filename,
                title: response.metadata.title,
                artist: response.metadata.artist,
                bpm: response.metadata.bpm,
                level: response.metadata.level
            )
        } catch {
            // Update UI state on main thread
            await MainActor.run {
                isLoading = false
                errorMessage = error.localizedDescription
            }
            throw DTXAPIError.networkError(error)
        }
    }

    func downloadDTXFile(filename: String) async throws -> Data {
        guard let url = URL(string: "\(baseURL)/dtx/download/\(filename)") else {
            throw DTXAPIError.invalidURL
        }

        // Update UI state on main thread
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }

        do {
            // Network call runs in background - this is the heavy operation
            let (data, response) = try await session.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw DTXAPIError.networkError(URLError(.badServerResponse))
            }

            guard httpResponse.statusCode == 200 else {
                throw DTXAPIError.networkError(URLError(.badServerResponse))
            }

            // Update UI state on main thread
            await MainActor.run {
                isLoading = false
            }

            return data
        } catch {
            // Update UI state on main thread
            await MainActor.run {
                isLoading = false
                errorMessage = error.localizedDescription
            }
            throw DTXAPIError.networkError(error)
        }
    }

    func downloadBGMFile(songId: String) async throws -> Data {
        guard let url = URL(string: "\(baseURL)/dtx/download/\(songId)/bgm.ogg") else {
            throw DTXAPIError.invalidURL
        }

        // Update UI state on main thread
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }

        do {
            // Network call runs in background - this is the heavy operation
            let (data, response) = try await session.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw DTXAPIError.networkError(URLError(.badServerResponse))
            }

            guard httpResponse.statusCode == 200 else {
                throw DTXAPIError.networkError(URLError(.badServerResponse))
            }

            // Update UI state on main thread
            await MainActor.run {
                isLoading = false
            }

            return data
        } catch {
            // Update UI state on main thread
            await MainActor.run {
                isLoading = false
                errorMessage = error.localizedDescription
            }
            throw DTXAPIError.networkError(error)
        }
    }

    func downloadPreviewFile(songId: String) async throws -> Data {
        guard let url = URL(string: "\(baseURL)/dtx/download/\(songId)/preview.mp3") else {
            throw DTXAPIError.invalidURL
        }

        // Update UI state on main thread
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }

        do {
            // Network call runs in background - this is the heavy operation
            let (data, response) = try await session.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw DTXAPIError.networkError(URLError(.badServerResponse))
            }

            guard httpResponse.statusCode == 200 else {
                throw DTXAPIError.networkError(URLError(.badServerResponse))
            }

            // Update UI state on main thread
            await MainActor.run {
                isLoading = false
            }

            return data
        } catch {
            // Update UI state on main thread
            await MainActor.run {
                isLoading = false
                errorMessage = error.localizedDescription
            }
            throw DTXAPIError.networkError(error)
        }
    }

    func downloadChartFile(songId: String, chartFilename: String) async throws -> Data {
        guard let url = URL(string: "\(baseURL)/dtx/download/\(songId)/\(chartFilename)") else {
            throw DTXAPIError.invalidURL
        }

        // Update UI state on main thread
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }

        do {
            // Network call runs in background - this is the heavy chart download operation
            let (data, response) = try await session.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw DTXAPIError.networkError(URLError(.badServerResponse))
            }

            guard httpResponse.statusCode == 200 else {
                throw DTXAPIError.networkError(URLError(.badServerResponse))
            }

            // Update UI state on main thread
            await MainActor.run {
                isLoading = false
            }

            return data
        } catch {
            // Update UI state on main thread
            await MainActor.run {
                isLoading = false
                errorMessage = error.localizedDescription
            }
            throw DTXAPIError.networkError(error)
        }
    }

    // MARK: - Configuration

    func setServerURL(_ url: String) {
        UserDefaults.standard.set(url, forKey: "DTXServerURL")
    }

    func resetToLocalServer() {
        UserDefaults.standard.removeObject(forKey: "DTXServerURL")
    }

    // Test server connectivity
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

// MARK: - Response Models

private struct DTXListResponse: Codable {
    let songs: [DTXSongInfo]
    let individualFiles: [DTXFileInfo]?

    struct DTXSongInfo: Codable {
        let songId: String
        let title: String
        let artist: String?
        let bpm: Double?
        let charts: [DTXChartInfo]

        enum CodingKeys: String, CodingKey {
            case songId = "song_id"
            case title, artist, bpm, charts
        }
    }

    struct DTXChartInfo: Codable {
        let difficulty: String
        let difficultyLabel: String
        let level: Int
        let filename: String
        let size: Int

        enum CodingKeys: String, CodingKey {
            case difficulty
            case difficultyLabel = "difficulty_label"
            case level, filename, size
        }
    }

    enum CodingKeys: String, CodingKey {
        case songs
        case individualFiles = "individual_files"
    }

    struct DTXFileInfo: Codable {
        let filename: String
        let size: Int
    }
}

private struct DTXMetadataResponse: Codable {
    let filename: String
    let metadata: DTXMetadataInfo

    struct DTXMetadataInfo: Codable {
        let title: String?
        let artist: String?
        let bpm: Double?
        let level: Int?
    }
}
