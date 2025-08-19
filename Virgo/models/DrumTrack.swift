//
//  DrumTrack.swift (formerly Item.swift)
//  Virgo
//
//  Created by Chan Wai Chan on 29/6/2025.
//

import Foundation
import SwiftData
import SwiftUI

@Model
final class Note {
    var interval: NoteInterval
    var noteType: NoteType
    var measureNumber: Int
    var measureOffset: Double
    var chart: Chart?

    init(interval: NoteInterval, noteType: NoteType, measureNumber: Int, measureOffset: Double, chart: Chart? = nil) {
        self.interval = interval
        self.noteType = noteType
        self.measureNumber = measureNumber
        self.measureOffset = measureOffset
        self.chart = chart
    }
}

@Model
final class Chart {
    var difficulty: Difficulty
    var level: Int = 50
    private var _timeSignature: TimeSignature?
    var song: Song?
    @Relationship(deleteRule: .cascade, inverse: \Note.chart)
    var notes: [Note]

    var timeSignature: TimeSignature {
        get {
            _timeSignature ?? (song?.isDeleted == false ? song?.timeSignature : nil) ?? .fourFour
        }
        set { _timeSignature = newValue }
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
        notes.count
    }

    // Safe accessor for notes
    var safeNotes: [Note] {
        notes.filter { !$0.isDeleted }
    }

    init(difficulty: Difficulty, level: Int? = nil, timeSignature: TimeSignature? = nil,
         notes: [Note] = [], song: Song? = nil) {
        self.difficulty = difficulty
        // If no level provided, assign based on difficulty
        self.level = level ?? difficulty.defaultLevel
        self._timeSignature = timeSignature
        self.notes = notes
        self.song = song
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
    var bgmFilePath: String? // Path to downloaded BGM audio file
    var previewFilePath: String? // Path to downloaded preview audio file
    @Relationship(deleteRule: .cascade, inverse: \Chart.song)
    var charts: [Chart]

    var timeSignature: TimeSignature {
        get { _timeSignature ?? .fourFour }
        set { _timeSignature = newValue }
    }

    // Convenience accessors
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
        return charts.first { $0.difficulty == difficulty }
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
        bgmFilePath: String? = nil,
        previewFilePath: String? = nil
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
        self.bgmFilePath = bgmFilePath
        self.previewFilePath = previewFilePath
    }
}

// MARK: - Server Song Models

@Model
final class ServerChart {
    var difficulty: String  // "easy", "medium", "hard", "expert"
    var difficultyLabel: String  // "BASIC", "ADVANCED", "EXTREME", "MASTER"
    var level: Int  // Numeric difficulty level (e.g., 36, 60, 74, 87)
    var filename: String  // DTX file name (e.g., "bas.dtx")
    var size: Int
    var serverSong: ServerSong?

    init(
        difficulty: String,
        difficultyLabel: String,
        level: Int,
        filename: String,
        size: Int,
        serverSong: ServerSong? = nil
    ) {
        self.difficulty = difficulty
        self.difficultyLabel = difficultyLabel
        self.level = level
        self.filename = filename
        self.size = size
        self.serverSong = serverSong
    }
}

@Model
final class ServerSong {
    var songId: String  // Folder name identifier
    var title: String
    var artist: String
    var bpm: Double
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
        self.charts = charts
        self.lastUpdated = Date()
        self.isDownloaded = isDownloaded
        self.hasBGM = hasBGM
        self.bgmDownloaded = bgmDownloaded
        self.hasPreview = hasPreview
        self.previewDownloaded = previewDownloaded
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
        let chart = ServerChart(
            difficulty: "medium",
            difficultyLabel: "STANDARD",
            level: difficultyLevel,
            filename: filename,
            size: size
        )
        self.init(
            songId: filename.replacingOccurrences(of: ".dtx", with: ""),
            title: title,
            artist: artist,
            bpm: bpm,
            charts: [chart],
            isDownloaded: isDownloaded,
            hasBGM: false,
            hasPreview: false
        )
    }

}

// MARK: - Extensions
extension Chart {
    var difficultyColor: Color {
        return difficulty.color
    }
}

extension Song {
    static var sampleData: [Song] {
        let song1 = Song(
            title: "Thunder Beat",
            artist: "Rock Masters",
            bpm: 140.0,
            duration: "3:45",
            genre: "Rock",
            timeSignature: .fourFour
        )
        
        let song2 = Song(
            title: "Blast Beat Fury",
            artist: "Metal Gods",
            bpm: 180.0,
            duration: "4:20",
            genre: "Metal",
            timeSignature: .fourFour
        )
        
        let song3 = Song(
            title: "Jazz Groove",
            artist: "Smooth Collective",
            bpm: 120.0,
            duration: "5:30",
            genre: "Jazz",
            timeSignature: .fourFour
        )
        
        let song4 = Song(
            title: "Electronic Pulse",
            artist: "Digital Beats",
            bpm: 128.0,
            duration: "3:15",
            genre: "Electronic",
            timeSignature: .fourFour
        )
        
        let song5 = Song(
            title: "Latin Rhythm",
            artist: "Salsa Kings",
            bpm: 95.0,
            duration: "4:00",
            genre: "Latin",
            timeSignature: .fourFour
        )
        
        let song6 = Song(
            title: "Progressive Complex",
            artist: "Time Masters",
            bpm: 160.0,
            duration: "6:45",
            genre: "Progressive",
            timeSignature: .fiveFour
        )
        
        let song7 = Song(
            title: "Hip Hop Foundation",
            artist: "Beat Makers",
            bpm: 85.0,
            duration: "3:30",
            genre: "Hip Hop",
            timeSignature: .fourFour
        )
        
        // Create charts for each song with different difficulties
        let chart1Easy = Chart(difficulty: .easy, song: song1)
        let chart1Medium = Chart(difficulty: .medium, song: song1)
        song1.charts = [chart1Easy, chart1Medium]
        
        let chart2Hard = Chart(difficulty: .hard, song: song2)
        let chart2Expert = Chart(difficulty: .expert, song: song2)
        song2.charts = [chart2Hard, chart2Expert]
        
        let chart3Easy = Chart(difficulty: .easy, song: song3)
        let chart3Medium = Chart(difficulty: .medium, song: song3)
        let chart3Hard = Chart(difficulty: .hard, song: song3)
        song3.charts = [chart3Easy, chart3Medium, chart3Hard]
        
        let chart4Medium = Chart(difficulty: .medium, song: song4)
        song4.charts = [chart4Medium]
        
        let chart5Easy = Chart(difficulty: .easy, song: song5)
        let chart5Medium = Chart(difficulty: .medium, song: song5)
        song5.charts = [chart5Easy, chart5Medium]
        
        let chart6Expert = Chart(difficulty: .expert, song: song6)
        song6.charts = [chart6Expert]
        
        let chart7Easy = Chart(difficulty: .easy, song: song7)
        song7.charts = [chart7Easy]
        
        return [song1, song2, song3, song4, song5, song6, song7]
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

    static var sampleData: [DrumTrack] {
        Song.sampleData.flatMap { song in
            song.charts.map { chart in
                DrumTrack(chart: chart)
            }
        }
    }
}
