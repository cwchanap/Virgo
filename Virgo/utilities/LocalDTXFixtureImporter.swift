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

struct LocalDTXFixtureImportWarning: Hashable {
    let chartFilename: String
    let message: String
}

struct LocalDTXFixtureImportResult {
    let song: Song
    let warnings: [LocalDTXFixtureImportWarning]
}

enum LocalDTXFixtureImporter {
    static let soukyuuSongId = "soukyuu_e_no_shouka"

    private static let setFilename = "SET.def"

    @MainActor
    @discardableResult
    static func importSong(from folderURL: URL, into context: ModelContext) throws -> Song {
        try importSongResult(from: folderURL, into: context).song
    }

    @MainActor
    static func importSongResult(
        from folderURL: URL,
        into context: ModelContext,
        save: (ModelContext) throws -> Void = { try $0.save() }
    ) throws -> LocalDTXFixtureImportResult {
        try importSongResult(
            from: folderURL,
            songId: folderURL.lastPathComponent,
            into: context,
            save: save
        )
    }

    @MainActor
    @discardableResult
    private static func importSongResult(
        from folderURL: URL,
        songId: String,
        into context: ModelContext,
        save: (ModelContext) throws -> Void
    ) throws -> LocalDTXFixtureImportResult {
        if let existingSong = try existingSong(with: songId, in: context) {
            try refreshAudioPaths(for: existingSong, from: folderURL, in: context)
            return LocalDTXFixtureImportResult(song: existingSong, warnings: [])
        }

        let setURL = folderURL.appendingPathComponent(setFilename)
        guard FileManager.default.fileExists(atPath: setURL.path) else {
            throw LocalDTXFixtureImportError.missingSETFile(setURL)
        }
        guard let setContent = decodeSETFile(at: setURL) else {
            throw LocalDTXFixtureImportError.unreadableSETFile(setURL)
        }

        let setList = SETList(content: setContent)
        let importedCharts = try loadImportedCharts(from: folderURL, setList: setList)

        guard let firstChart = importedCharts.first else {
            throw LocalDTXFixtureImportError.noPlayableCharts(songId)
        }

        let song = Song(
            title: setList.title ?? firstChart.data.title,
            artist: firstChart.data.artist,
            bpm: firstChart.data.bpm,
            duration: formatDuration(Int(calculateDuration(from: importedCharts))),
            genre: "DTX Import",
            timeSignature: firstChart.projection.timeSignature,
            isServerImported: true,
            serverSongId: songId,
            bgmFilePath: existingAudioPath(named: "bgm.m4a", in: folderURL),
            previewFilePath: existingAudioPath(named: "preview.mp3", in: folderURL),
            bgmStartOffsetSeconds: nil
        )

        do {
            context.insert(song)
            song.charts = try buildCharts(from: importedCharts, for: song, into: context)
            try save(context)
            let warnings = importedCharts.compactMap { importedChart in
                importedChart.projection.warning.map {
                    LocalDTXFixtureImportWarning(
                        chartFilename: importedChart.reference.filename,
                        message: $0.message
                    )
                }
            }
            return LocalDTXFixtureImportResult(song: song, warnings: warnings)
        } catch {
            context.rollback()
            throw error
        }
    }

    @MainActor
    private static func buildCharts(
        from importedCharts: [ImportedChart],
        for song: Song,
        into context: ModelContext
    ) throws -> [Chart] {
        try importedCharts.map { importedChart in
            let chart = Chart(
                difficulty: importedChart.difficulty,
                level: importedChart.data.difficultyLevel,
                timeSignature: importedChart.projection.timeSignature,
                song: song
            )
            try chart.setRhythmMetadata(importedChart.projection.chartMetadata)
            chart.notes = importedChart.projection.notes.map { $0.makeNote(for: chart) }
            chart.controlEvents = importedChart.projection.controls.map { $0.makeControl(for: chart) }
            chart.bumpTimingRevision()
            if let warning = importedChart.projection.warning {
                Logger.warning(warning.message)
            }
            context.insert(chart)
            for note in chart.notes {
                context.insert(note)
            }
            for control in chart.controlEvents {
                context.insert(control)
            }
            return chart
        }
    }

    @MainActor
    @discardableResult
    static func importBundledSoukyuuIfAvailable(
        into context: ModelContext,
        bundle: Bundle = .main,
        deletionStore: BundledFixtureDeletionStore = .standard
    ) throws -> Song? {
        // Respect a user's explicit deletion of the bundled demo. `seedLocalDTXFixtures`
        // runs on every production launch and otherwise recreates a deleted demo
        // because the only dedupe key is `serverSongId`. If the user removed the
        // bundled Soukyuu song AND it is no longer present, skip re-seeding so the
        // Delete action is durable. If the record still exists (e.g. a delete that
        // did not persist), fall through to the normal path so the existing
        // stable-ID record retains its persisted graph while BGM/preview paths
        // are re-resolved from current fixture assets.
        if deletionStore.isDeleted(songId: soukyuuSongId),
           try existingSong(with: soukyuuSongId, in: context) == nil {
            Logger.info(
                "Skipping bundled DTX fixture import: user deleted '\(soukyuuSongId)'"
            )
            return nil
        }

        // Locate SET.def (the import entry point) in the bundle. Try the flat
        // resource-root lookup first — verified in the built Virgo.app,
        // fileSystemSynchronizedGroups flattens Virgo/Fixtures/soukyuu_e_no_shouka/*
        // into Contents/Resources/ root, so SET.def lands at the resource root and the
        // two-arg lookup resolves. If that returns nil, fall back to a whole-bundle
        // walk via `locateBundledSETDef` so a folder-reference layout (which preserves
        // Fixtures/soukyuu_e_no_shouka/ and is invisible to the 2-arg lookup) still
        // imports the bundled demo song instead of failing silently. Using SET.def
        // (not a chart file like bas.dtx) is correct because SET.def is the logical
        // root of a DTX fixture and references all chart/audio files by relative path.
        guard let setURL = locateBundledSETDef(in: bundle) else {
            // This is the entry the caller (ContentView.seedLocalDTXFixtures) only logs on
            // the success/error branches. If the bundled SET.def goes missing (fresh
            // checkout, fileSystemSynchronizedGroups regression, CI without the resource)
            // import returns nil and — without this warning — produces zero log output,
            // which is the silent-failure regression class called out in CLAUDE.md.
            Logger.warning(
                "Bundled DTX fixture not imported: SET.def not found in bundle \(bundle.bundlePath)"
            )
            return nil
        }
        return try importSongResult(
            from: setURL.deletingLastPathComponent(),
            songId: soukyuuSongId,
            into: context,
            save: { try $0.save() }
        ).song
    }

    /// Locates `SET.def` in `bundle`, trying the flat resource-root lookup first and
    /// falling back to a whole-bundle walk. The fallback handles a folder-reference
    /// resource layout where the fixture directory is preserved and the 2-arg
    /// `Bundle.url(forResource:withExtension:)` cannot recurse into it.
    private static func locateBundledSETDef(in bundle: Bundle) -> URL? {
        if let url = bundle.url(forResource: "SET", withExtension: "def") {
            return url
        }
        // Search the bundle's resources tree (and, if that's unavailable, the whole
        // bundle) for SET.def anywhere under it.
        let searchRoot = bundle.resourceURL ?? bundle.bundleURL
        return locateSETFile(in: searchRoot)
    }

    /// Walks `directory` recursively and returns the first `SET.def` it finds.
    ///
    /// Internal (not private) so it can be unit-tested directly with a synthetic
    /// directory tree — constructing a loadable `Bundle` with a folder-reference
    /// layout in-process is impractical, but the filesystem walk is the part that
    /// needs coverage. Used by `locateBundledSETDef` as the folder-reference-layout
    /// fallback.
    static func locateSETFile(in directory: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: nil
        ) else {
            return nil
        }
        for case let url as URL in enumerator where url.lastPathComponent == "SET.def" {
            return url
        }
        return nil
    }

    @MainActor
    private static func loadImportedCharts(
        from folderURL: URL,
        setList: SETList
    ) throws -> [ImportedChart] {
        try setList.chartReferences.compactMap { reference -> ImportedChart? in
            guard let difficulty = reference.difficulty else {
                // A SET.def entry whose LABEL is not one of the known difficulties
                // (BASIC/ADVANCED/EXTREME/MASTER/REAL) is dropped. Without this log a
                // song would silently ship missing a difficulty.
                Logger.warning(
                    "DTX fixture: dropping chart '\(reference.label)' — unrecognized difficulty label"
                )
                return nil
            }

            let chartURL = folderURL.appendingPathComponent(reference.filename)
            guard FileManager.default.fileExists(atPath: chartURL.path) else {
                // A chart referenced by SET.def but absent from the bundle would otherwise
                // vanish with no signal — exactly the regression class CLAUDE.md warns about.
                Logger.warning(
                    "DTX fixture: dropping chart '\(reference.label)' — missing file \(reference.filename)"
                )
                return nil
            }

            let data = try DTXFileParser.parseChartMetadata(from: chartURL)
            let projection = try data.persistenceProjection()
            return ImportedChart(
                reference: reference,
                difficulty: difficulty,
                data: data,
                projection: projection
            )
        }
    }

    @MainActor
    private static func existingSong(with songId: String, in context: ModelContext) throws -> Song? {
        try context.fetch(FetchDescriptor<Song>())
            .first { $0.serverSongId == songId }
    }

    @MainActor
    private static func refreshAudioPaths(
        for song: Song,
        from folderURL: URL,
        in context: ModelContext
    ) throws {
        var didChange = false

        // Re-resolve persisted absolute paths from the fixture's current assets. If
        // an asset disappeared, clear its stale path instead of leaving playback with
        // a dangling filesystem reference.
        let bgmPath = existingAudioPath(named: "bgm.m4a", in: folderURL)
        if song.bgmFilePath != bgmPath {
            if bgmPath == nil, let stalePath = song.bgmFilePath {
                Logger.warning("DTX fixture: bgm.m4a no longer bundled — clearing stale path \(stalePath)")
            }
            song.bgmFilePath = bgmPath
            didChange = true
        }

        let previewPath = existingAudioPath(named: "preview.mp3", in: folderURL)
        if song.previewFilePath != previewPath {
            if previewPath == nil, let stalePath = song.previewFilePath {
                Logger.warning("DTX fixture: preview.mp3 no longer bundled — clearing stale path \(stalePath)")
            }
            song.previewFilePath = previewPath
            didChange = true
        }

        if didChange {
            try context.save()
        }
    }

    private static func decodeSETFile(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }

        // Only trust UTF-16 when the file actually starts with a UTF-16 BOM. A naive
        // `[.utf16, .shiftJIS, .utf8].lazy.first` chain is unsafe because
        // `String(contentsOf:encoding: .utf16)` *lossily succeeds* on UTF-8 / Shift-JIS
        // bytes — it returns garbage CJK that contains no #LxLABEL/#LxFILE directives,
        // so the importer then rejects the fixture with `noPlayableCharts`. The bundled
        // Soukyuu SET.def ships with a UTF-16LE BOM (0xFF 0xFE), so this routes real
        // fixtures correctly while keeping BOM-less UTF-8/Shift-JIS files off the
        // garbage decode path.
        let bomPrefix = Array(data.prefix(2))
        if bomPrefix == [0xFE, 0xFF] || bomPrefix == [0xFF, 0xFE],
           let decoded = String(data: data, encoding: .utf16) {
            return decoded
        }

        // BOM-less fallback: UTF-8 is strict (rejects most Shift-JIS byte sequences),
        // so try it first; Shift-JIS is the common Japanese-encoded DTX fallback.
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .shiftJIS)
    }

    private static func existingAudioPath(named filename: String, in folderURL: URL) -> String? {
        let url = folderURL.appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: url.path) ? url.path : nil
    }

    private static func calculateDuration(from importedCharts: [ImportedChart]) -> TimeInterval {
        importedCharts.compactMap { importedChart in
            importedChart.projection.timeline?.endSeconds(
                bpm: importedChart.data.bpm,
                speed: 1
            )
        }.max() ?? 60.0
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

    private static func chartDirective(from line: String) -> SETChartDirective? {
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

        return SETChartDirective(slot: slot, field: String(field), value: value)
    }
}

private struct SETChartDirective {
    let slot: Int
    let field: String
    let value: String
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
    let projection: DTXChartPersistenceProjection
}
