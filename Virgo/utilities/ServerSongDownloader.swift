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
        // Extract all needed data from serverSong BEFORE creating a new context
        // to avoid cross-context SwiftData relationship access.
        let snapshot = ServerSongSnapshot(from: serverSong)

        let context = ModelContext(container)
        var savedFilePaths: [String] = []
        do {
            if try songAlreadyExists(snapshot: snapshot, in: context) {
                return (false, "Song already exists in database")
            }
            let song = createSong(from: snapshot)
            try await processCharts(for: song, from: snapshot, in: context)
            await downloadOptionalFiles(for: song, snapshot: snapshot)
            // Track saved file paths so we can clean them up if the database save fails
            if let bgmPath = song.bgmFilePath { savedFilePaths.append(bgmPath) }
            if let previewPath = song.previewFilePath { savedFilePaths.append(previewPath) }
            context.insert(song)
            try context.save()
            return (true, nil)
        } catch {
            context.rollback()
            // Delete any audio files that were written before the database save failed
            for path in savedFilePaths {
                fileManager.deleteFile(at: path, label: "audio")
            }
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
    private func songAlreadyExists(snapshot: ServerSongSnapshot, in context: ModelContext) throws -> Bool {
        // Check by stable serverSongId first (targeted fetch, avoids loading all songs)
        let songId = snapshot.songId
        let serverIdPredicate = #Predicate<Song> { song in
            song.serverSongId == songId
        }
        if !(try context.fetch(FetchDescriptor<Song>(predicate: serverIdPredicate)).isEmpty) { return true }

        // Fallback: exact title/artist match for legacy songs without serverSongId.
        // Only matches songs that have no serverSongId so that distinct server
        // songs sharing the same title/artist are not treated as duplicates.
        let title = snapshot.title
        let artist = snapshot.artist
        let titleArtistPredicate = #Predicate<Song> { song in
            song.title == title && song.artist == artist && song.serverSongId == nil
        }
        if !(try context.fetch(FetchDescriptor<Song>(predicate: titleArtistPredicate)).isEmpty) { return true }

        // Final fallback: case-insensitive match for legacy songs without serverSongId.
        // #Predicate cannot call .lowercased(), so this secondary check runs in
        // memory over the small set of songs that lack a serverSongId.
        let noServerIdPredicate = #Predicate<Song> { song in
            song.serverSongId == nil
        }
        let legacySongs = try context.fetch(FetchDescriptor<Song>(predicate: noServerIdPredicate))
        return legacySongs.contains { song in
            song.title.lowercased() == snapshot.title.lowercased() &&
                song.artist.lowercased() == snapshot.artist.lowercased()
        }
    }

    private func createSong(from snapshot: ServerSongSnapshot) -> Song {
        Song(
            title: snapshot.title,
            artist: snapshot.artist,
            bpm: snapshot.bpm,
            duration: snapshot.durationSeconds.map(Self.formatDuration) ?? "3:30",
            genre: snapshot.genre ?? "DTX Import",
            timeSignature: .fourFour,
            isServerImported: true,
            serverSongId: snapshot.songId
        )
    }

    @MainActor
    private func processCharts(for song: Song, from snapshot: ServerSongSnapshot, in context: ModelContext) async throws {
        var successCount = 0
        var failedCharts: [String] = []
        let serverDuration = snapshot.durationSeconds
        for (index, chartSnapshot) in snapshot.charts.enumerated() {
            // Throttle chart downloads to avoid overwhelming the server.
            if index > 0 { try await Task.sleep(nanoseconds: 100_000_000) }
            do {
                try await processChart(chartSnapshot, for: song, in: context, serverDurationSeconds: serverDuration)
                successCount += 1
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                Logger.warning("Failed to process chart \(chartSnapshot.filename): \(error.localizedDescription)")
                failedCharts.append(chartSnapshot.filename)
            }
        }
        if successCount == 0, !snapshot.charts.isEmpty {
            throw ServerSongImportError.chartFailure(
                reason: "All charts failed: \(failedCharts.joined(separator: ", "))"
            )
        }
    }

    @MainActor
    private func processChart(
        _ chartSnapshot: ServerChartSnapshot,
        for song: Song,
        in context: ModelContext,
        serverDurationSeconds: Int?
    ) async throws {
        guard !chartSnapshot.fileURL.isEmpty else {
            throw ServerSongImportError.invalidChartURL("(empty fileURL for \(chartSnapshot.filename))")
        }
        guard let url = URL(string: chartSnapshot.fileURL) else {
            throw ServerSongImportError.invalidChartURL(chartSnapshot.fileURL)
        }
        let data = try await downloader.downloadData(from: url)
        guard let content = Self.decode(data, encoding: chartSnapshot.fileEncoding) else {
            throw ServerSongImportError.decodeFailed(chartSnapshot.filename)
        }
        let chartData = try DTXFileParser.parseChartMetadata(from: content)
        song.setBGMStartOffsetIfUnset(chartData.bgmStartOffsetSeconds)
        if song.charts.isEmpty {
            if chartData.bpm.isFinite && chartData.bpm > 0 { song.bpm = chartData.bpm }
            if serverDurationSeconds == nil {
                song.duration = Self.formatDuration(Int(calculateDuration(from: chartData.notes)))
            }
        }
        let difficulty = mapServerDifficultyToApp(chartSnapshot.difficulty)
        let chart = Chart(difficulty: difficulty, level: chartSnapshot.level, song: song)
        chartData.toNotes(for: chart).forEach { chart.notes.append($0) }
        context.insert(chart)
    }

    @MainActor
    private func downloadOptionalFiles(for song: Song, snapshot: ServerSongSnapshot) async {
        guard let base = config.r2BaseURL else {
            Logger.database("No R2 base URL configured; skipping audio for \(song.title)")
            return
        }
        if snapshot.hasBGM {
            await download(SimfileMapper.bgmURL(base: base, songId: snapshot.songId), kind: .bgm,
                           songId: snapshot.songId, song: song)
        }
        if snapshot.hasPreview {
            await download(SimfileMapper.previewURL(base: base, songId: snapshot.songId), kind: .preview,
                           songId: snapshot.songId, song: song)
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

// MARK: - Value-type snapshots for cross-context safety

/// Captures all needed data from a `ServerSong` to avoid accessing SwiftData
/// model relationships across different `ModelContext` boundaries.
struct ServerSongSnapshot: Sendable {
    let songId: String
    let title: String
    let artist: String
    let bpm: Double
    let genre: String?
    let durationSeconds: Int?
    let charts: [ServerChartSnapshot]
    let hasBGM: Bool
    let hasPreview: Bool

    @MainActor
    init(from serverSong: ServerSong) {
        self.songId = serverSong.songId
        self.title = serverSong.title
        self.artist = serverSong.artist
        self.bpm = serverSong.bpm
        self.genre = serverSong.genre
        self.durationSeconds = serverSong.durationSeconds
        self.charts = serverSong.charts.map { ServerChartSnapshot(from: $0) }
        self.hasBGM = serverSong.hasBGM
        self.hasPreview = serverSong.hasPreview
    }
}

/// Captures all needed data from a `ServerChart` for cross-context-safe processing.
struct ServerChartSnapshot: Sendable {
    let difficulty: String
    let difficultyLabel: String
    let level: Int
    let filename: String
    let size: Int
    let fileURL: String
    let fileEncoding: String

    @MainActor
    init(from chart: ServerChart) {
        self.difficulty = chart.difficulty
        self.difficultyLabel = chart.difficultyLabel
        self.level = chart.level
        self.filename = chart.filename
        self.size = chart.size
        self.fileURL = chart.fileURL
        self.fileEncoding = chart.fileEncoding
    }
}
