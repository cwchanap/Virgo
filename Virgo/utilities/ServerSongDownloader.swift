import Foundation
import SwiftData

/// Errors that can occur during server song import.
enum ServerSongImportError: LocalizedError {
    case invalidChartURL(String)
    case decodeFailed(String)
    case chartFailure(reason: String)

    var errorDescription: String? {
        switch self {
        case .invalidChartURL(let url):
            return "Invalid chart URL: \(url)"
        case .decodeFailed(let filename):
            return "Failed to decode chart file: \(filename)"
        case .chartFailure(let reason):
            return "Chart import failed: \(reason)"
        }
    }
}

/// Downloads and imports a server song's charts and optional audio.
class ServerSongDownloader {
    private let downloader: FileDownloading
    private let fileManager: ServerSongFileManager
    private let config: ServerConfig

    init(
        downloader: FileDownloading = DTXAPIClient(),
        fileManager: ServerSongFileManager = ServerSongFileManager(),
        config: ServerConfig = ServerConfig()
    ) {
        self.downloader = downloader
        self.fileManager = fileManager
        self.config = config
    }

    @MainActor
    func downloadAndImportSong(_ serverSong: ServerSong, container: ModelContainer) async -> (Bool, String?) {
        let context = ModelContext(container)
        do {
            if try songAlreadyExists(serverSong, in: context) {
                return (false, "Song already exists in database")
            }
            let song = createSong(from: serverSong)
            try await processCharts(for: song, from: serverSong, in: context)
            await downloadOptionalFiles(for: song, serverSong: serverSong)
            context.insert(song)
            try context.save()
            return (true, nil)
        } catch {
            context.rollback()
            return (false, "Import failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Decoding (testable)

    static func decode(_ data: Data, encoding: String) -> String? {
        let enc: String.Encoding = (encoding == "UTF_8") ? .utf8 : .shiftJIS
        if let decoded = String(data: data, encoding: enc) { return decoded }
        Logger.warning("Primary decode (\(encoding)) failed; trying UTF-8 fallback")
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Private

    @MainActor
    private func songAlreadyExists(_ serverSong: ServerSong, in context: ModelContext) throws -> Bool {
        let existing = try context.fetch(FetchDescriptor<Song>())
        return existing.contains {
            $0.title.lowercased() == serverSong.title.lowercased() &&
            $0.artist.lowercased() == serverSong.artist.lowercased()
        }
    }

    private func createSong(from serverSong: ServerSong) -> Song {
        Song(
            title: serverSong.title,
            artist: serverSong.artist,
            bpm: serverSong.bpm,
            duration: serverSong.durationSeconds.map(Self.formatDuration) ?? "3:30",
            genre: serverSong.genre ?? "DTX Import",
            timeSignature: .fourFour,
            isServerImported: true
        )
    }

    @MainActor
    private func processCharts(for song: Song, from serverSong: ServerSong, in context: ModelContext) async throws {
        for (index, serverChart) in serverSong.charts.enumerated() {
            if index > 0 { try await Task.sleep(nanoseconds: 100_000_000) }
            do {
                try await processChart(serverChart, for: song, in: context)
            } catch {
                Logger.warning("Failed to process chart \(serverChart.filename): \(error.localizedDescription)")
                throw ServerSongImportError.chartFailure(
                    reason: "Chart '\(serverChart.filename)' failed: \(error.localizedDescription)"
                )
            }
        }
    }

    @MainActor
    private func processChart(_ serverChart: ServerChart, for song: Song, in context: ModelContext) async throws {
        guard let url = URL(string: serverChart.fileURL) else {
            throw ServerSongImportError.invalidChartURL(serverChart.fileURL)
        }
        let data = try await downloader.downloadData(from: url)
        guard let content = Self.decode(data, encoding: serverChart.fileEncoding) else {
            throw ServerSongImportError.decodeFailed(serverChart.filename)
        }
        let chartData = try DTXFileParser.parseChartMetadata(from: content)
        if song.charts.isEmpty {
            if chartData.bpm.isFinite && chartData.bpm > 0 { song.bpm = chartData.bpm }
            if serverChart.serverSong?.durationSeconds == nil {
                song.duration = Self.formatDuration(Int(calculateDuration(from: chartData.notes)))
            }
        }
        let difficulty = mapServerDifficultyToApp(serverChart.difficulty)
        let chart = Chart(difficulty: difficulty, level: serverChart.level, song: song)
        chartData.toNotes(for: chart).forEach { chart.notes.append($0) }
        context.insert(chart)
    }

    @MainActor
    private func downloadOptionalFiles(for song: Song, serverSong: ServerSong) async {
        guard let base = config.r2BaseURL else {
            Logger.database("No R2 base URL configured; skipping audio for \(song.title)")
            return
        }
        if serverSong.hasBGM {
            await download(SimfileMapper.bgmURL(base: base, songId: serverSong.songId), kind: .bgm,
                           songId: serverSong.songId, song: song)
        }
        if serverSong.hasPreview {
            await download(SimfileMapper.previewURL(base: base, songId: serverSong.songId), kind: .preview,
                           songId: serverSong.songId, song: song)
        }
    }

    private enum AudioKind { case bgm, preview }

    @MainActor
    private func download(_ url: URL, kind: AudioKind, songId: String, song: Song) async {
        do {
            let data = try await downloader.downloadData(from: url)
            switch kind {
            case .bgm: song.bgmFilePath = try fileManager.saveBGMFile(data, for: songId)
            case .preview: song.previewFilePath = try fileManager.savePreviewFile(data, for: songId)
            }
        } catch {
            Logger.database("Failed to download \(kind) for \(song.title): \(error.localizedDescription)")
        }
    }

    private func mapServerDifficultyToApp(_ serverDifficulty: String) -> Difficulty {
        Difficulty(rawValue: serverDifficulty.capitalized) ?? .medium
    }

    private func calculateDuration(from notes: [DTXNote]) -> TimeInterval {
        guard !notes.isEmpty else { return 60.0 }
        let maxMeasure = notes.reduce(Int.min) { max($0, $1.measureNumber) }
        return Double(maxMeasure + 1) / 30.0 * 60.0
    }

    private static func formatDuration(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
