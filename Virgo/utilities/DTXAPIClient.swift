import Foundation

struct DTXServerFile {
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

@MainActor
class DTXAPIClient: ObservableObject {
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let session = URLSession.shared
    
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
        
        isLoading = true
        errorMessage = nil
        
        do {
            let (data, _) = try await session.data(from: url)
            let response = try JSONDecoder().decode(DTXListResponse.self, from: data)
            isLoading = false
            return response.files.map { DTXServerFile(filename: $0.filename, size: $0.size) }
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
            throw DTXAPIError.networkError(error)
        }
    }
    
    func getDTXMetadata(filename: String) async throws -> DTXServerMetadata {
        guard let url = URL(string: "\(baseURL)/dtx/metadata/\(filename)") else {
            throw DTXAPIError.invalidURL
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            let (data, _) = try await session.data(from: url)
            let response = try JSONDecoder().decode(DTXMetadataResponse.self, from: data)
            isLoading = false
            
            return DTXServerMetadata(
                filename: response.filename,
                title: response.metadata.title,
                artist: response.metadata.artist,
                bpm: response.metadata.bpm,
                level: response.metadata.level
            )
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
            throw DTXAPIError.networkError(error)
        }
    }
    
    func downloadDTXFile(filename: String) async throws -> Data {
        guard let url = URL(string: "\(baseURL)/dtx/download/\(filename)") else {
            throw DTXAPIError.invalidURL
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            let (data, response) = try await session.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw DTXAPIError.networkError(URLError(.badServerResponse))
            }
            
            guard httpResponse.statusCode == 200 else {
                throw DTXAPIError.networkError(URLError(.badServerResponse))
            }
            
            isLoading = false
            return data
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
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
    let files: [DTXFileInfo]
    
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
