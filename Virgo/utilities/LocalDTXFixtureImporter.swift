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
            try refreshBGMStartOffsetIfMissing(for: existingSong, from: folderURL, in: context)
            try refreshDurationIfStale(for: existingSong, from: folderURL, in: context)
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
        let importedCharts = try loadImportedCharts(from: folderURL, setList: setList)

        guard let firstChart = importedCharts.first else {
            throw LocalDTXFixtureImportError.noPlayableCharts(songId)
        }

        let song = Song(
            title: setList.title ?? firstChart.data.title,
            artist: firstChart.data.artist,
            bpm: firstChart.data.bpm,
            duration: formatDuration(Int(calculateDuration(from: importedCharts, bpm: firstChart.data.bpm))),
            genre: "DTX Import",
            timeSignature: .fourFour,
            isServerImported: true,
            serverSongId: songId,
            bgmFilePath: existingAudioPath(named: "bgm.m4a", in: folderURL),
            previewFilePath: existingAudioPath(named: "preview.mp3", in: folderURL),
            bgmStartOffsetSeconds: nil
        )
        importedCharts.forEach { song.setBGMStartOffsetIfUnset($0.data.bgmStartOffsetSeconds) }

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
        bundle: Bundle = .main,
        deletionStore: BundledFixtureDeletionStore = .standard
    ) throws -> Song? {
        // Respect a user's explicit deletion of the bundled demo. `seedLocalDTXFixtures`
        // runs on every production launch and otherwise recreates a deleted demo
        // because the only dedupe key is `serverSongId`. If the user removed the
        // bundled Soukyuu song AND it is no longer present, skip re-seeding so the
        // Delete action is durable. If the record still exists (e.g. a delete that
        // did not persist), fall through to the normal path so the self-healing
        // refresh logic (audio paths, BGM offset, duration) still repairs it.
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
        return try importSong(
            from: setURL.deletingLastPathComponent(),
            songId: soukyuuSongId,
            into: context
        )
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
            return ImportedChart(reference: reference, difficulty: difficulty, data: data)
        }
    }

    @MainActor
    private static func existingSong(with songId: String, in context: ModelContext) throws -> Song? {
        try context.fetch(FetchDescriptor<Song>())
            .first { $0.serverSongId == songId }
    }

    @MainActor
    private static func refreshAudioPaths(for song: Song, from folderURL: URL, in context: ModelContext) throws {
        var didChange = false

        // Re-resolve both audio paths from disk. If a previously-recorded asset is no
        // longer present in the bundle, clear it to nil rather than leaving a dangling
        // reference that would silently disable BGM/preview at playback time. This is
        // the symmetric case to the "refresh stale bgm.ogg -> bgm.m4a" fix in
        // CLAUDE.md's gameplay regression notes.
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

    /// Backfills `bgmStartOffsetSeconds` on an existing record that predates offset
    /// parsing (nil), by reading the fixture's charts and applying the same
    /// "first writer wins" rule as a fresh import.
    ///
    /// Idempotent and cheap on the steady-state path: the leading guard returns
    /// immediately once the offset is already set (including the legitimate 0.0
    /// "BGM starts at time zero" case), so the chart-parse cost is paid at most
    /// once per legacy record (the first launch after this code ships).
    /// Mirrors the fresh-import loop above (lines that build `importedCharts`) so the
    /// two paths stay consistent rather than drifting again.
    @MainActor
    private static func refreshBGMStartOffsetIfMissing(
        for song: Song,
        from folderURL: URL,
        in context: ModelContext
    ) throws {
        guard song.bgmStartOffsetSeconds == nil else { return }

        guard let setContent = decodeSETFile(at: folderURL.appendingPathComponent(setFilename)) else { return }
        let setList = SETList(content: setContent)

        for reference in setList.chartReferences {
            guard reference.difficulty != nil else { continue }
            let chartURL = folderURL.appendingPathComponent(reference.filename)
            guard FileManager.default.fileExists(atPath: chartURL.path) else { continue }
            guard let data = try? DTXFileParser.parseChartMetadata(from: chartURL) else { continue }
            song.setBGMStartOffsetIfUnset(data.bgmStartOffsetSeconds)
            // First writer wins; stop once setBGMStartOffsetIfUnset accepted any
            // offset (including 0.0 for "BGM starts at time zero").
            if song.bgmStartOffsetSeconds != nil { break }
        }

        if song.bgmStartOffsetSeconds != nil {
            try context.save()
        }
    }

    /// Recomputes `Song.duration` from the fixture's charts and migrates any
    /// stale value persisted by an older importer version.
    ///
    /// `GameplayViewModel.calculateTrackDurationInSeconds` trusts `Song.duration`
    /// verbatim, so a record created before the BPM-derived duration fix (which
    /// hard-coded 2 sec/measure and overstated tempo-divergent charts such as the
    /// 165.55-BPM Soukyuu fixture as "5:14") keeps that wrong value across app
    /// upgrades unless the refresh path recomputes it. Mirrors the fresh-import
    /// derivation exactly and only writes (and saves) when the persisted value
    /// actually differs, so a correct record is left untouched.
    @MainActor
    private static func refreshDurationIfStale(
        for song: Song,
        from folderURL: URL,
        in context: ModelContext
    ) throws {
        guard let setContent = decodeSETFile(at: folderURL.appendingPathComponent(setFilename)) else { return }
        let setList = SETList(content: setContent)

        let importedCharts = try loadImportedCharts(from: folderURL, setList: setList)
        guard let firstChart = importedCharts.first else { return }

        let recomputed = formatDuration(
            Int(calculateDuration(from: importedCharts, bpm: firstChart.data.bpm))
        )
        guard song.duration != recomputed else { return }
        song.duration = recomputed
        try context.save()
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

    /// Derives the imported song's duration from the highest measure number across
    /// all charts and the chart BPM.
    ///
    /// The previous implementation hard-coded `2 seconds per measure` (`/ 30.0 * 60.0`
    /// = 30 measures/minute at 4/4), which is only correct at 120 BPM. For charts at
    /// other tempos (the bundled Soukyuu fixture is 165.55 BPM) it overstates
    /// `Song.duration`, and `GameplayViewModel.calculateTrackDurationInSeconds` trusts
    /// that value, so gameplay progress keeps running well past the chart/audio end.
    /// Using `4.0 * 60.0 / bpm` matches the per-measure seconds convention already used
    /// by `DTXChartData.bgmStartOffsetSeconds` and the `.fourFour` time signature set
    /// on the `Song`.
    private static func calculateDuration(from importedCharts: [ImportedChart], bpm: Double) -> TimeInterval {
        let maxMeasure = importedCharts
            .flatMap(\.data.notes)
            .map(\.measureNumber)
            .max()
        guard let maxMeasure else { return 60.0 }
        let secondsPerMeasure = 4.0 * 60.0 / bpm
        return Double(maxMeasure + 1) * secondsPerMeasure
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
}
