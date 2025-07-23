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
    private var _timeSignature: TimeSignature?
    var song: Song?
    @Relationship(deleteRule: .cascade, inverse: \Note.chart)
    var notes: [Note]
    
    var timeSignature: TimeSignature {
        get { _timeSignature ?? song?.timeSignature ?? .fourFour }
        set { _timeSignature = newValue }
    }
    
    // Convenience accessors for song properties
    var title: String { song?.title ?? "Unknown Song" }
    var artist: String { song?.artist ?? "Unknown Artist" }
    var bpm: Int { song?.bpm ?? 120 }
    var duration: String { song?.duration ?? "0:00" }
    var genre: String { song?.genre ?? "Unknown" }
    
    init(difficulty: Difficulty, timeSignature: TimeSignature? = nil, notes: [Note] = [], song: Song? = nil) {
        self.difficulty = difficulty
        self._timeSignature = timeSignature
        self.notes = notes
        self.song = song
    }
}

@Model
final class Song {
    var title: String
    var artist: String
    var bpm: Int
    var duration: String
    var genre: String
    private var _timeSignature: TimeSignature?
    var isPlaying: Bool
    var dateAdded: Date
    var playCount: Int
    var isSaved: Bool = false
    @Relationship(deleteRule: .cascade, inverse: \Chart.song)
    var charts: [Chart]
    
    var timeSignature: TimeSignature {
        get { _timeSignature ?? .fourFour }
        set { _timeSignature = newValue }
    }
    
    // Convenience accessors
    var availableDifficulties: [Difficulty] {
        charts.map { $0.difficulty }.sorted { $0.rawValue < $1.rawValue }
    }
    
    var easiestChart: Chart? {
        charts.min { chart1, chart2 in
            let order: [Difficulty] = [.easy, .medium, .hard, .expert]
            let index1 = order.firstIndex(of: chart1.difficulty) ?? 0
            let index2 = order.firstIndex(of: chart2.difficulty) ?? 0
            return index1 < index2
        }
    }
    
    var measureCount: Int {
        let maxMeasure = charts.flatMap { $0.notes }.map { $0.measureNumber }.max() ?? 1
        return maxMeasure
    }
    
    func chart(for difficulty: Difficulty) -> Chart? {
        charts.first { $0.difficulty == difficulty }
    }
    
    init(
        title: String,
        artist: String,
        bpm: Int,
        duration: String,
        genre: String,
        timeSignature: TimeSignature = .fourFour,
        charts: [Chart] = [],
        isPlaying: Bool = false,
        playCount: Int = 0,
        isSaved: Bool = false
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
    }
}

@Model
final class ServerSong {
    var filename: String
    var title: String
    var artist: String
    var bpm: Double
    var difficultyLevel: Int
    var size: Int
    var lastUpdated: Date
    var isDownloaded: Bool
    
    init(
        filename: String,
        title: String,
        artist: String,
        bpm: Double,
        difficultyLevel: Int,
        size: Int,
        isDownloaded: Bool = false
    ) {
        self.filename = filename
        self.title = title
        self.artist = artist
        self.bpm = bpm
        self.difficultyLevel = difficultyLevel
        self.size = size
        self.lastUpdated = Date()
        self.isDownloaded = isDownloaded
    }
    
    func toDifficulty() -> Difficulty {
        switch difficultyLevel {
        case 0..<25:
            return .easy
        case 25..<50:
            return .medium
        case 50..<75:
            return .hard
        case 75...100:
            return .expert
        default:
            return .medium
        }
    }
    
    func formatFileSize() -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(size))
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
        return [
            createThunderBeatSong(),
            createHipHopSong(),
            createJazzSong()
        ]
    }
    
    private static func createThunderBeatSong() -> Song {
        let song = Song(
            title: "Thunder Beat",
            artist: "DrumMaster Pro",
            bpm: 120,
            duration: "3:45",
            genre: "Rock",
            timeSignature: .fourFour
        )
        
        let easyChart = Chart(difficulty: .easy, song: song)
        easyChart.notes = [
            Note(interval: .quarter, noteType: .bass, measureNumber: 1, measureOffset: 0.0, chart: easyChart),
            Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0.5, chart: easyChart),
            Note(interval: .quarter, noteType: .hiHat, measureNumber: 1, measureOffset: 0.0, chart: easyChart),
            Note(interval: .quarter, noteType: .hiHat, measureNumber: 1, measureOffset: 0.5, chart: easyChart)
        ]
        
        let mediumChart = Chart(difficulty: .medium, song: song)
        mediumChart.notes = [
            Note(interval: .quarter, noteType: .bass, measureNumber: 1, measureOffset: 0.0, chart: mediumChart),
            Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0.5, chart: mediumChart),
            Note(interval: .eighth, noteType: .hiHat, measureNumber: 1, measureOffset: 0.0, chart: mediumChart),
            Note(interval: .eighth, noteType: .hiHat, measureNumber: 1, measureOffset: 0.25, chart: mediumChart),
            Note(interval: .eighth, noteType: .hiHat, measureNumber: 1, measureOffset: 0.5, chart: mediumChart),
            Note(interval: .eighth, noteType: .hiHat, measureNumber: 1, measureOffset: 0.75, chart: mediumChart)
        ]
        
        let hardChart = Chart(difficulty: .hard, song: song)
        hardChart.notes = [
            Note(interval: .quarter, noteType: .bass, measureNumber: 1, measureOffset: 0.0, chart: hardChart),
            Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0.5, chart: hardChart),
            Note(interval: .eighth, noteType: .hiHat, measureNumber: 1, measureOffset: 0.0, chart: hardChart),
            Note(interval: .eighth, noteType: .hiHat, measureNumber: 1, measureOffset: 0.25, chart: hardChart),
            Note(interval: .eighth, noteType: .hiHat, measureNumber: 1, measureOffset: 0.5, chart: hardChart),
            Note(interval: .eighth, noteType: .hiHat, measureNumber: 1, measureOffset: 0.75, chart: hardChart),
            Note(interval: .eighth, noteType: .highTom, measureNumber: 1, measureOffset: 0.875, chart: hardChart),
            Note(interval: .eighth, noteType: .midTom, measureNumber: 1, measureOffset: 0.9375, chart: hardChart)
        ]
        
        song.charts = [easyChart, mediumChart, hardChart]
        return song
    }
    
    private static func createHipHopSong() -> Song {
        let song = Song(
            title: "Hip Hop Beats",
            artist: "Urban Flow",
            bpm: 85,
            duration: "3:30",
            genre: "Hip Hop",
            timeSignature: .fourFour
        )
        
        let easyChart = Chart(difficulty: .easy, song: song)
        easyChart.notes = [
            Note(interval: .quarter, noteType: .bass, measureNumber: 1, measureOffset: 0.0, chart: easyChart),
            Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0.5, chart: easyChart),
            Note(interval: .quarter, noteType: .hiHat, measureNumber: 1, measureOffset: 0.0, chart: easyChart),
            Note(interval: .quarter, noteType: .hiHat, measureNumber: 1, measureOffset: 0.5, chart: easyChart)
        ]
        
        let mediumChart = Chart(difficulty: .medium, song: song)
        mediumChart.notes = [
            Note(interval: .quarter, noteType: .bass, measureNumber: 1, measureOffset: 0.0, chart: mediumChart),
            Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0.5, chart: mediumChart),
            Note(interval: .eighth, noteType: .hiHat, measureNumber: 1, measureOffset: 0.0, chart: mediumChart),
            Note(interval: .eighth, noteType: .hiHat, measureNumber: 1, measureOffset: 0.25, chart: mediumChart),
            Note(interval: .eighth, noteType: .openHiHat, measureNumber: 1, measureOffset: 0.75, chart: mediumChart)
        ]
        
        song.charts = [easyChart, mediumChart]
        return song
    }
    
    private static func createJazzSong() -> Song {
        let song = Song(
            title: "Jazz Swing",
            artist: "Blue Note",
            bpm: 125,
            duration: "6:15",
            genre: "Jazz",
            timeSignature: .threeFour
        )
        
        let hardChart = Chart(difficulty: .hard, song: song)
        hardChart.notes = [
            Note(interval: .quarter, noteType: .bass, measureNumber: 1, measureOffset: 0.0, chart: hardChart),
            Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0.5, chart: hardChart),
            Note(interval: .eighth, noteType: .ride, measureNumber: 1, measureOffset: 0.0, chart: hardChart),
            Note(interval: .eighth, noteType: .ride, measureNumber: 1, measureOffset: 0.33, chart: hardChart),
            Note(interval: .eighth, noteType: .ride, measureNumber: 1, measureOffset: 0.66, chart: hardChart)
        ]
        
        song.charts = [hardChart]
        return song
    }
}

// MARK: - Legacy Support for DrumTrack
// Keeping DrumTrack as a computed structure for backward compatibility
struct DrumTrack {
    let chart: Chart
    
    // Forward all properties to the chart and its song
    var title: String { chart.title }
    var artist: String { chart.artist }
    var bpm: Int { chart.bpm }
    var duration: String { chart.duration }
    var genre: String { chart.genre }
    var difficulty: Difficulty { chart.difficulty }
    var timeSignature: TimeSignature { chart.timeSignature }
    var notes: [Note] { chart.notes }
    var difficultyColor: Color { chart.difficultyColor }
    
    // Legacy properties (these would need to be tracked elsewhere or computed)
    var isPlaying: Bool { chart.song?.isPlaying ?? false }
    var dateAdded: Date { chart.song?.dateAdded ?? Date() }
    var playCount: Int { chart.song?.playCount ?? 0 }
    var isSaved: Bool { chart.song?.isSaved ?? false }
    
    init(chart: Chart) {
        self.chart = chart
    }
    
    static var sampleData: [DrumTrack] {
        Song.sampleData.flatMap { song in
            song.charts.map { chart in
                DrumTrack(chart: chart)
            }
        }
    }
}
