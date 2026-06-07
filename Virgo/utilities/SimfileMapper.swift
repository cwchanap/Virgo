import Foundation

/// Pure conversion from catalog DTOs to SwiftData models, plus audio URL helpers.
enum SimfileMapper {
    static func makeServerSong(from dto: SimfileDTO) -> ServerSong {
        let charts = dto.dtxFiles.map { makeServerChart(from: $0) }
        let song = ServerSong(
            songId: dto.id,
            title: dto.title,
            artist: dto.artist,
            bpm: dto.bpm,
            genre: dto.genre,
            durationSeconds: dto.durationSeconds,
            charts: charts,
            isDownloaded: false,
            hasBGM: hasFile(named: "bgm.ogg", in: dto.fileKeys),
            hasPreview: hasFile(named: "preview.mp3", in: dto.fileKeys)
        )
        song.lastUpdated = parseDate(dto.updatedAt)
        return song
    }

    static func makeServerChart(from dto: DtxFileDTO) -> ServerChart {
        let level = Int(dto.level.rounded())
        let difficulty = DifficultyClassifier.classify(label: dto.label, level: level)
        let filename = Self.filename(from: dto.fileURL) ?? dto.label
        return ServerChart(
            difficulty: difficulty.rawValue.lowercased(),
            difficultyLabel: dto.label,
            level: level,
            filename: filename,
            size: dto.fileSizeBytes,
            fileURL: dto.fileURL,
            fileEncoding: dto.encoding.rawValue
        )
    }

    static func bgmURL(base: URL, songId: String) -> URL {
        base.appendingPathComponent(songId).appendingPathComponent("bgm.ogg")
    }

    static func previewURL(base: URL, songId: String) -> URL {
        base.appendingPathComponent(songId).appendingPathComponent("preview.mp3")
    }

    // MARK: - Helpers

    /// Extract the last path component from a URL string (e.g. "ext.dtx" from
    /// "https://r2/song-1/ext.dtx"). Returns nil when the URL is empty or has
    /// no path component, so callers can fall back to the label.
    private static func filename(from fileURL: String) -> String? {
        guard !fileURL.isEmpty else { return nil }
        let last = URL(string: fileURL)?.lastPathComponent
        return (last?.isEmpty == false) ? last : nil
    }

    private static func hasFile(named name: String, in keys: [String]) -> Bool {
        keys.contains { $0.hasSuffix(name) }
    }

    private static func parseDate(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: iso) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: iso) ?? Date()
    }
}
