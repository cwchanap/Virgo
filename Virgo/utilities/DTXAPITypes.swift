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
    let metadata: DTXChartMetadata?
}

struct DTXChartMetadata {
    let title: String?
    let artist: String?
    let bpm: Double?
    let level: Int?
}

struct DTXServerMetadata {
    let filename: String
    let title: String?
    let artist: String?
    let bpm: Double?
    let level: Int?
}

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

struct DTXFileInfo: Codable {
    let filename: String
    let size: Int
}

struct DTXListResponse: Codable {
    let songs: [DTXSongInfo]
    let individualFiles: [DTXFileInfo]

    enum CodingKeys: String, CodingKey {
        case songs
        case individualFiles = "individual_files"
    }
}

struct DTXMetadataInfo: Codable {
    let title: String?
    let artist: String?
    let bpm: Double?
    let level: Int?
}

struct DTXMetadataResponse: Codable {
    let filename: String
    let metadata: DTXMetadataInfo
}