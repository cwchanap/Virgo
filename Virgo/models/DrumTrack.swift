//
//  DrumTrack.swift (formerly Item.swift)
//  Virgo
//
//  Created by Chan Wai Chan on 29/6/2025.
//

import Foundation
import SwiftData
import SwiftUI

enum NoteOriginKind: String, Codable, CaseIterable {
    case manual
    case dtx
}

enum NormalizedNotationVoice: String, Codable, CaseIterable {
    case upper
    case lower
}

enum NormalizedArticulation: String, Codable, CaseIterable {
    case none
}

@Model
final class Note {
    var interval: NoteInterval
    var noteType: NoteType
    var measureNumber: Int
    var measureOffset: Double
    var chart: Chart?

    var originKind: NoteOriginKind = NoteOriginKind.manual
    var sourceLaneID: String?
    var sourceNoteID: String?
    var sourceGridPosition: Int?
    var sourceGridSize: Int?
    var normalizedMeasureIndex: Int?
    var normalizedAbsoluteTick: Int?
    var normalizedTickWithinMeasure: Int?
    var normalizedTicksPerMeasure: Int?
    /// Notation voice hint captured from the DTX source during import.
    /// Currently unused by the rendering pipeline — `DrumNotationCatalog`
    /// resolves voice from the lane definition. Retained on the model for
    /// future per-note voice overrides and diagnostic tooling.
    var notationVoiceCandidate: NormalizedNotationVoice?
    var visualDurationCandidate: NoteInterval?
    var articulationCandidate: NormalizedArticulation?

    init(
        interval: NoteInterval,
        noteType: NoteType,
        measureNumber: Int,
        measureOffset: Double,
        chart: Chart? = nil,
        originKind: NoteOriginKind = .manual,
        sourceLaneID: String? = nil,
        sourceNoteID: String? = nil,
        sourceGridPosition: Int? = nil,
        sourceGridSize: Int? = nil,
        normalizedMeasureIndex: Int? = nil,
        normalizedAbsoluteTick: Int? = nil,
        normalizedTickWithinMeasure: Int? = nil,
        normalizedTicksPerMeasure: Int? = nil,
        notationVoiceCandidate: NormalizedNotationVoice? = nil,
        visualDurationCandidate: NoteInterval? = nil,
        articulationCandidate: NormalizedArticulation? = nil
    ) {
        self.interval = interval
        self.noteType = noteType
        self.measureNumber = measureNumber
        self.measureOffset = measureOffset
        self.chart = chart
        self.originKind = originKind
        self.sourceLaneID = sourceLaneID
        self.sourceNoteID = sourceNoteID
        self.sourceGridPosition = sourceGridPosition
        self.sourceGridSize = sourceGridSize
        self.normalizedMeasureIndex = normalizedMeasureIndex
        self.normalizedAbsoluteTick = normalizedAbsoluteTick
        self.normalizedTickWithinMeasure = normalizedTickWithinMeasure
        self.normalizedTicksPerMeasure = normalizedTicksPerMeasure
        self.notationVoiceCandidate = notationVoiceCandidate
        self.visualDurationCandidate = visualDurationCandidate
        self.articulationCandidate = articulationCandidate
    }
}

/// Lightweight fingerprint of a ``Chart``'s timing-affecting state,
/// used to invalidate cached practice-state without traversing SwiftData
/// relationships. See ``Chart/timingFingerprint``.
///
/// Uses only ``Chart/timingRevision`` — a chart-owned stored scalar bumped on
/// every timing mutation — so evaluating this is safe during SwiftUI view
/// rendering and never faults the ``Song`` relationship.
struct ChartTimingFingerprint: Hashable {
    let timingRevision: Int
}

@Model
final class Chart {
    var difficulty: Difficulty
    var level: Int = 50
    private var _timeSignature: TimeSignature?
    var song: Song?
    @Relationship(deleteRule: .cascade, inverse: \Note.chart)
    var notes: [Note]
    @Relationship(deleteRule: .cascade, inverse: \ChartControlEvent.chart)
    var controlEvents: [ChartControlEvent]
    var bestScore: Int = 0
    var rhythmMetadataData: Data?
    /// Monotonic counter bumped on every timing-affecting mutation (time
    /// signature, rhythm metadata, notes, control events, or song BPM). Used
    /// by ``timingFingerprint`` to invalidate cached practice state without
    /// traversing SwiftData relationships. Stored as a chart-owned scalar so
    /// it is safe to read during SwiftUI view rendering.
    var timingRevision: Int = 0
    @Relationship(deleteRule: .cascade, inverse: \ScoreRecord.chart)
    var scoreRecords: [ScoreRecord] = []

    var rhythmMetadataState: ChartRhythmMetadataLoadState {
        guard let rhythmMetadataData else { return .missing }
        return ChartRhythmMetadataCodec.decode(rhythmMetadataData)
    }

    var timeSignature: TimeSignature {
        get {
            _timeSignature ?? (song?.isDeleted == false ? song?.timeSignature : nil) ?? .fourFour
        }
        set {
            _timeSignature = newValue
            bumpTimingRevision()
        }
    }

    /// Increment ``timingRevision`` to invalidate cached practice state.
    /// Call after any mutation to notes, control events, or song BPM that
    /// affects timing resolution. The ``timeSignature`` setter and
    /// ``setRhythmMetadata(_:)`` bump automatically.
    func bumpTimingRevision() {
        timingRevision &+= 1
    }

    // Convenience accessors for song properties
    var title: String {
        song?.title ?? "Unknown Song"
    }
    var artist: String {
        song?.artist ?? "Unknown Artist"
    }
    var bpm: Double {
        song?.bpm ?? 120.0
    }
    var duration: String {
        song?.duration ?? "0:00"
    }
    var genre: String {
        song?.genre ?? "Unknown"
    }

    // Safe accessor for notes count
    var notesCount: Int {
        // Ensure we don't access notes relationship during concurrent operations
        guard !isDeleted else { return 0 }
        return notes.filter { !$0.isDeleted }.count
    }

    // Safe accessor for notes
    var safeNotes: [Note] {
        // Ensure we don't access notes relationship during concurrent operations  
        guard !isDeleted else { return [] }
        return notes.filter { !$0.isDeleted }
    }

    var safeControlEvents: [ChartControlEvent] {
        guard !isDeleted else { return [] }
        return controlEvents.filter { !$0.isDeleted }
    }

    func setRhythmMetadata(_ metadata: ChartRhythmMetadata) throws {
        rhythmMetadataData = try ChartRhythmMetadataCodec.encode(metadata)
        bumpTimingRevision()
    }

    /// A cheap, relationship-free fingerprint of the timing-affecting state
    /// that ``ChartPracticeStateLoader`` and SwiftUI `.task` modifiers use to
    /// detect in-place mutations (e.g. rhythm backfill) without traversing
    /// SwiftData relationships. Reads only ``timingRevision`` — a chart-owned
    /// stored scalar — so this is safe to evaluate during view rendering.
    var timingFingerprint: ChartTimingFingerprint {
        ChartTimingFingerprint(timingRevision: timingRevision)
    }

    init(
        difficulty: Difficulty,
        level: Int? = nil,
        timeSignature: TimeSignature? = nil,
        notes: [Note] = [],
        controlEvents: [ChartControlEvent] = [],
        song: Song? = nil
    ) {
        self.difficulty = difficulty
        // If no level provided, assign based on difficulty
        self.level = level ?? difficulty.defaultLevel
        self._timeSignature = timeSignature
        self.notes = notes
        self.controlEvents = controlEvents
        self.song = song
        self.rhythmMetadataData = nil
    }
}

@Model
final class Song {
    var title: String
    var artist: String
    var bpm: Double
    var duration: String
    var genre: String
    private var _timeSignature: TimeSignature?
    var isPlaying: Bool
    var dateAdded: Date
    var playCount: Int
    var isSaved: Bool = false
    var isServerImported: Bool = false // True for songs downloaded from the server
    var serverSongId: String? // Stable ID from the server catalog (folder name). Used for download status, deletion, and duplicate checks.
    var bgmFilePath: String? // Path to downloaded BGM audio file
    var previewFilePath: String? // Path to downloaded preview audio file
    var bgmStartOffsetSeconds: Double? // DTX lane 01 start time at 1.0x speed
    @Relationship(deleteRule: .cascade, inverse: \Chart.song)
    var charts: [Chart]

    var timeSignature: TimeSignature {
        get { _timeSignature ?? .fourFour }
        set { _timeSignature = newValue }
    }

    // WARNING: These convenience accessors access SwiftData relationships directly
    // They should be used carefully to avoid concurrency issues in multi-threaded contexts
    var availableDifficulties: [Difficulty] {
        guard !isDeleted else { return [] }

        let validCharts = charts.filter { !$0.isDeleted }
        let difficulties = validCharts.compactMap { chart in
            chart.difficulty
        }
        return difficulties.sorted { $0.sortOrder < $1.sortOrder }
    }

    var easiestChart: Chart? {
        guard !isDeleted else { return nil }

        let validCharts = charts.filter { !$0.isDeleted }
        return validCharts.min { chart1, chart2 in
            chart1.difficulty.sortOrder < chart2.difficulty.sortOrder
        }
    }

    var measureCount: Int {
        // Safe access to charts and their notes
        guard !isDeleted else { return 1 }

        let validCharts = charts.filter { !$0.isDeleted }
        let allNotes = validCharts.flatMap { chart in
            chart.safeNotes
        }
        return allNotes.map(\.measureNumber).max() ?? 1
    }

    func chart(for difficulty: Difficulty) -> Chart? {
        guard !isDeleted else { return nil }
        
        return charts.first { $0.difficulty == difficulty && !$0.isDeleted }
    }

    init(
        title: String,
        artist: String,
        bpm: Double,
        duration: String,
        genre: String,
        timeSignature: TimeSignature = .fourFour,
        charts: [Chart] = [],
        isPlaying: Bool = false,
        playCount: Int = 0,
        isSaved: Bool = false,
        isServerImported: Bool = false,
        serverSongId: String? = nil,
        bgmFilePath: String? = nil,
        previewFilePath: String? = nil,
        bgmStartOffsetSeconds: Double? = nil
    ) {
        self.title = title
        self.artist = artist
        self.bpm = bpm
        self.duration = duration
        self.genre = genre
        self._timeSignature = timeSignature
        self.charts = charts
        self.isPlaying = isPlaying
        self.dateAdded = Date()
        self.playCount = playCount
        self.isSaved = isSaved
        self.isServerImported = isServerImported
        self.serverSongId = serverSongId
        self.bgmFilePath = bgmFilePath
        self.previewFilePath = previewFilePath
        self.bgmStartOffsetSeconds = bgmStartOffsetSeconds
    }
}

// MARK: - Server Song Models

@Model
final class ServerChart {
    var difficulty: String  // "easy", "medium", "hard", "expert"
    var difficultyLabel: String  // "BASIC", "ADVANCED", "EXTREME", "MASTER", "REAL"
    var level: Int  // Numeric difficulty level (e.g., 36, 60, 74, 87)
    var filename: String  // DTX file name (e.g., "bas.dtx")
    var size: Int
    var fileURL: String = ""  // Public R2 URL for the .dtx file (DtxFile.fileUrl)
    var fileEncoding: String = "SHIFT_JIS"  // "SHIFT_JIS" | "UTF_8" (DtxFile.fileEncoding)
    var serverSong: ServerSong?

    init(
        difficulty: String,
        difficultyLabel: String,
        level: Int,
        filename: String,
        size: Int,
        fileURL: String = "",
        fileEncoding: String = "SHIFT_JIS",
        serverSong: ServerSong? = nil
    ) {
        self.difficulty = difficulty
        self.difficultyLabel = difficultyLabel
        self.level = level
        self.filename = filename
        self.size = size
        self.fileURL = fileURL
        self.fileEncoding = fileEncoding
        self.serverSong = serverSong
    }
}

@Model
final class ServerSong {
    var songId: String  // Folder name identifier
    var title: String
    var artist: String
    var bpm: Double
    var genre: String?            // server-curated; nil -> client falls back to "DTX Import"
    var durationSeconds: Int?     // accurate duration if known
    @Relationship(deleteRule: .cascade) var charts: [ServerChart]
    var lastUpdated: Date
    var isDownloaded: Bool
    var hasBGM: Bool = false // Whether BGM file is available for download
    var bgmDownloaded: Bool = false // Whether BGM file was successfully downloaded
    var hasPreview: Bool = false // Whether preview file is available for download
    var previewDownloaded: Bool = false // Whether preview file was successfully downloaded

    init(
        songId: String,
        title: String,
        artist: String,
        bpm: Double,
        genre: String? = nil,
        durationSeconds: Int? = nil,
        charts: [ServerChart] = [],
        isDownloaded: Bool = false,
        hasBGM: Bool = false,
        bgmDownloaded: Bool = false,
        hasPreview: Bool = false,
        previewDownloaded: Bool = false
    ) {
        self.songId = songId
        self.title = title
        self.artist = artist
        self.bpm = bpm
        self.genre = genre
        self.durationSeconds = durationSeconds
        self.charts = charts
        self.lastUpdated = Date()
        self.isDownloaded = isDownloaded
        self.hasBGM = hasBGM
        self.bgmDownloaded = bgmDownloaded
        self.hasPreview = hasPreview
        self.previewDownloaded = previewDownloaded

        // SwiftData automatically manages bidirectional relationships
        // No need to manually set back-references as it causes duplication
    }

    // Legacy compatibility for single-file DTX
    convenience init(
        filename: String,
        title: String,
        artist: String,
        bpm: Double,
        difficultyLevel: Int,
        size: Int,
        isDownloaded: Bool = false
    ) {
        // Initialize without charts first
        self.init(
            songId: filename.replacingOccurrences(of: ".dtx", with: ""),
            title: title,
            artist: artist,
            bpm: bpm,
            charts: [],
            isDownloaded: isDownloaded,
            hasBGM: false,
            hasPreview: false
        )
        
        // Create and add the chart after initialization
        let chart = ServerChart(
            difficulty: "medium",
            difficultyLabel: "STANDARD",
            level: difficultyLevel,
            filename: filename,
            size: size,
            serverSong: self
        )
        self.charts.append(chart)
    }

}

// MARK: - Extensions
extension Chart {
    var difficultyColor: Color {
        return difficulty.color
    }
}

// MARK: - Legacy Support for DrumTrack
// Keeping DrumTrack as a computed structure for backward compatibility
struct DrumTrack: Equatable {
    let chart: Chart
    // Forward all properties to the chart and its song
    var title: String { chart.title }
    var artist: String { chart.artist }
    var bpm: Double { chart.bpm }
    var duration: String { chart.duration }
    var genre: String { chart.genre }
    var difficulty: Difficulty { chart.difficulty }
    var timeSignature: TimeSignature { chart.timeSignature }
    var notes: [Note] { chart.safeNotes }
    var difficultyColor: Color { chart.difficultyColor }
    // Legacy properties (these would need to be tracked elsewhere or computed)
    var isPlaying: Bool { chart.song?.isPlaying ?? false }
    var dateAdded: Date { chart.song?.dateAdded ?? Date() }
    var playCount: Int { chart.song?.playCount ?? 0 }
    var isSaved: Bool { chart.song?.isSaved ?? false }
    init(chart: Chart) {
        self.chart = chart
    }
    static func == (lhs: DrumTrack, rhs: DrumTrack) -> Bool {
        return lhs.chart.persistentModelID == rhs.chart.persistentModelID
    }
}
