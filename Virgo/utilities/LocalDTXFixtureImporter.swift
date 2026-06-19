//
//  LocalDTXFixtureImporter.swift
//  Virgo
//

import Foundation
import SwiftData

enum LocalDTXFixtureImportError: LocalizedError {
    case missingSETFile(URL)
    case unreadableSETFile(URL)
    case noPlayableCharts(String)

    var errorDescription: String? {
        switch self {
        case .missingSETFile(let url):
            return "Missing SET.def at \(url.path)"
        case .unreadableSETFile(let url):
            return "Unable to decode SET.def at \(url.path)"
        case .noPlayableCharts(let songId):
            return "No playable charts found for local DTX fixture \(songId)"
        }
    }
}

enum LocalDTXFixtureImporter {
    static let soukyuuSongId = "soukyuu_e_no_shouka"

    private static let setFilename = "SET.def"
    private static let bundledSoukyuuChartFilename = "bas.dtx"

    @MainActor
    @discardableResult
    static func importSong(from folderURL: URL, into context: ModelContext) throws -> Song {
        try importSong(from: folderURL, songId: folderURL.lastPathComponent, into: context)
    }

    @MainActor
    @discardableResult
    static func importSong(from folderURL: URL, songId: String, into context: ModelContext) throws -> Song {
        if let existingSong = try existingSong(with: songId, in: context) {
            try refreshAudioPaths(for: existingSong, from: folderURL, in: context)
            return existingSong
        }

        let setURL = folderURL.appendingPathComponent(setFilename)
        guard FileManager.default.fileExists(atPath: setURL.path) else {
            throw LocalDTXFixtureImportError.missingSETFile(setURL)
        }
        guard let setContent = decodeSETFile(at: setURL) else {
            throw LocalDTXFixtureImportError.unreadableSETFile(setURL)
        }

        let setList = SETList(content: setContent)
        let importedCharts = try setList.chartReferences.compactMap { reference -> ImportedChart? in
            guard let difficulty = reference.difficulty else { return nil }

            let chartURL = folderURL.appendingPathComponent(reference.filename)
            guard FileManager.default.fileExists(atPath: chartURL.path) else { return nil }

            let data = try DTXFileParser.parseChartMetadata(from: chartURL)
            return ImportedChart(reference: reference, difficulty: difficulty, data: data)
        }

        guard let firstChart = importedCharts.first else {
            throw LocalDTXFixtureImportError.noPlayableCharts(songId)
        }

        let song = Song(
            title: setList.title ?? firstChart.data.title,
            artist: firstChart.data.artist,
            bpm: firstChart.data.bpm,
            duration: formatDuration(Int(calculateDuration(from: importedCharts))),
            genre: "DTX Import",
            timeSignature: .fourFour,
            isServerImported: true,
            serverSongId: songId,
            bgmFilePath: existingAudioPath(named: "bgm.m4a", in: folderURL),
            previewFilePath: existingAudioPath(named: "preview.mp3", in: folderURL),
            bgmStartOffsetSeconds: importedCharts
                .map(\.data.bgmStartOffsetSeconds)
                .first { $0 > 0 }
        )

        context.insert(song)
        song.charts = importedCharts.map { importedChart in
            let chart = Chart(
                difficulty: importedChart.difficulty,
                level: importedChart.data.difficultyLevel,
                timeSignature: .fourFour,
                song: song
            )
            chart.notes = importedChart.data.toNotes(for: chart)
            context.insert(chart)
            for note in chart.notes {
                context.insert(note)
            }
            return chart
        }

        try context.save()
        return song
    }

    @MainActor
    @discardableResult
    static func importBundledSoukyuuIfAvailable(
        into context: ModelContext,
        bundle: Bundle = .main
    ) throws -> Song? {
        guard let chartURL = bundle.url(forResource: bundledSoukyuuChartFilename, withExtension: nil) else {
            return nil
        }
        return try importSong(from: chartURL.deletingLastPathComponent(), songId: soukyuuSongId, into: context)
    }

    @MainActor
    private static func existingSong(with songId: String, in context: ModelContext) throws -> Song? {
        try context.fetch(FetchDescriptor<Song>())
            .first { $0.serverSongId == songId }
    }

    @MainActor
    private static func refreshAudioPaths(for song: Song, from folderURL: URL, in context: ModelContext) throws {
        var didChange = false
        if let bgmPath = existingAudioPath(named: "bgm.m4a", in: folderURL),
           song.bgmFilePath != bgmPath {
            song.bgmFilePath = bgmPath
            didChange = true
        }
        if let previewPath = existingAudioPath(named: "preview.mp3", in: folderURL),
           song.previewFilePath != previewPath {
            song.previewFilePath = previewPath
            didChange = true
        }
        if didChange {
            try context.save()
        }
    }

    private static func decodeSETFile(at url: URL) -> String? {
        [.utf16, .shiftJIS, .utf8]
            .lazy
            .compactMap { encoding in try? String(contentsOf: url, encoding: encoding) }
            .first
    }

    private static func existingAudioPath(named filename: String, in folderURL: URL) -> String? {
        let url = folderURL.appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: url.path) ? url.path : nil
    }

    private static func calculateDuration(from importedCharts: [ImportedChart]) -> TimeInterval {
        let maxMeasure = importedCharts
            .flatMap(\.data.notes)
            .map(\.measureNumber)
            .max()
        guard let maxMeasure else { return 60.0 }
        return Double(maxMeasure + 1) / 30.0 * 60.0
    }

    private static func formatDuration(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private struct SETList {
    let title: String?
    let chartReferences: [SETChartReference]

    init(content: String) {
        var title: String?
        var entries: [Int: SETChartEntry] = [:]

        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.hasPrefix("#") else { continue }

            if let parsedTitle = Self.value(from: line, key: "TITLE"), !parsedTitle.isEmpty {
                title = parsedTitle
                continue
            }

            guard let match = Self.chartDirective(from: line) else { continue }
            var entry = entries[match.slot] ?? SETChartEntry()
            switch match.field {
            case "LABEL":
                entry.label = match.value
            case "FILE":
                entry.filename = match.value
            default:
                break
            }
            entries[match.slot] = entry
        }

        self.title = title
        self.chartReferences = entries
            .sorted { $0.key < $1.key }
            .compactMap { slot, entry in
                guard let label = entry.label, let filename = entry.filename else { return nil }
                return SETChartReference(slot: slot, label: label, filename: filename)
            }
    }

    private static func value(from line: String, key: String) -> String? {
        let hashKey = "#\(key)"
        guard line.hasPrefix(hashKey) else { return nil }

        let remainder = line.dropFirst(hashKey.count)
        if remainder.first == ":" {
            return remainder.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return remainder.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func chartDirective(from line: String) -> (slot: Int, field: String, value: String)? {
        guard line.count > 3, line.hasPrefix("#L") else { return nil }

        let afterPrefix = line.dropFirst(2)
        guard let slotCharacter = afterPrefix.first, let slot = Int(String(slotCharacter)) else {
            return nil
        }

        let fieldStart = afterPrefix.index(after: afterPrefix.startIndex)
        let remainder = afterPrefix[fieldStart...]
        let field = remainder.prefix { !$0.isWhitespace && $0 != ":" }.uppercased()
        guard !field.isEmpty else { return nil }

        let valueStart = remainder.index(remainder.startIndex, offsetBy: field.count)
        let rawValue = remainder[valueStart...].drop { $0.isWhitespace || $0 == ":" }
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        return (slot, String(field), value)
    }
}

private struct SETChartEntry {
    var label: String?
    var filename: String?
}

private struct SETChartReference {
    let slot: Int
    let label: String
    let filename: String

    var difficulty: Difficulty? {
        switch label.uppercased() {
        case "BASIC":
            return .easy
        case "ADVANCED":
            return .medium
        case "EXTREME":
            return .hard
        case "MASTER", "REAL":
            return .expert
        default:
            return nil
        }
    }
}

private struct ImportedChart {
    let reference: SETChartReference
    let difficulty: Difficulty
    let data: DTXChartData
}
