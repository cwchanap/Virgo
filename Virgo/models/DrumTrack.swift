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
            do {
                return _timeSignature ?? (song?.isDeleted == false ? song?.timeSignature : nil) ?? .fourFour
            } catch {
                return .fourFour
            }
        }
        set { _timeSignature = newValue }
    }
    
    // Convenience accessors for song properties
    var title: String { 
        do {
            return (song?.isDeleted == false ? song?.title : nil) ?? "Unknown Song"
        } catch {
            return "Unknown Song"
        }
    }
    var artist: String { 
        do {
            return (song?.isDeleted == false ? song?.artist : nil) ?? "Unknown Artist"
        } catch {
            return "Unknown Artist"
        }
    }
    var bpm: Int { 
        do {
            return (song?.isDeleted == false ? song?.bpm : nil) ?? 120
        } catch {
            return 120
        }
    }
    var duration: String { 
        do {
            return (song?.isDeleted == false ? song?.duration : nil) ?? "0:00"
        } catch {
            return "0:00"
        }
    }
    var genre: String { 
        do {
            return (song?.isDeleted == false ? song?.genre : nil) ?? "Unknown"
        } catch {
            return "Unknown"
        }
    }
    
    // Safe accessor for notes count
    var notesCount: Int {
        do {
            return isDeleted ? 0 : notes.count
        } catch {
            return 0
        }
    }
    
    // Safe accessor for notes
    var safeNotes: [Note] {
        do {
            return isDeleted ? [] : notes
        } catch {
            return []
        }
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
        do {
            let difficulties = charts.compactMap { chart in
                // Only access difficulty if chart is not deleted
                chart.isDeleted ? nil : chart.difficulty
            }
            return difficulties.sorted { $0.rawValue < $1.rawValue }
        } catch {
            print("DEBUG: Error accessing availableDifficulties, returning empty: \(error)")
            return []
        }
    }
    
    var easiestChart: Chart? {
        do {
            let validCharts = charts.filter { !$0.isDeleted }
            return validCharts.min { chart1, chart2 in
                let order: [Difficulty] = [.easy, .medium, .hard, .expert]
                let index1 = order.firstIndex(of: chart1.difficulty) ?? 0
                let index2 = order.firstIndex(of: chart2.difficulty) ?? 0
                return index1 < index2
            }
        } catch {
            print("DEBUG: Error accessing easiestChart, returning nil: \(error)")
            return nil
        }
    }
    
    var measureCount: Int {
        // Safely access notes with error handling for deleted objects
        do {
            let allNotes = charts.compactMap { chart in
                // Only access notes if chart is not deleted
                chart.isDeleted ? [] : chart.safeNotes
            }.flatMap { $0 }
            
            let maxMeasure = allNotes.compactMap { note in
                // Only access measure number if note is not deleted
                note.isDeleted ? nil : note.measureNumber
            }.max() ?? 1
            
            return maxMeasure
        } catch {
            print("DEBUG: Error accessing measureCount, returning default: \(error)")
            return 1
        }
    }
    
    func chart(for difficulty: Difficulty) -> Chart? {
        do {
            return charts.first { !$0.isDeleted && $0.difficulty == difficulty }
        } catch {
            print("DEBUG: Error accessing chart for difficulty \(difficulty), returning nil: \(error)")
            return nil
        }
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

// MARK: - Server Song Models

@Model
final class ServerChart {
    var difficulty: String  // "easy", "medium", "hard", "expert"
    var difficultyLabel: String  // "BASIC", "ADVANCED", "EXTREME", "MASTER"
    var level: Int  // Numeric difficulty level (e.g., 36, 60, 74, 87)
    var filename: String  // DTX file name (e.g., "bas.dtx")
    var size: Int
    
    init(difficulty: String, difficultyLabel: String, level: Int, filename: String, size: Int) {
        self.difficulty = difficulty
        self.difficultyLabel = difficultyLabel
        self.level = level
        self.filename = filename
        self.size = size
    }
}

@Model
final class ServerSong {
    var songId: String  // Folder name identifier
    var title: String
    var artist: String
    var bpm: Double
    var charts: [ServerChart]
    var lastUpdated: Date
    var isDownloaded: Bool
    
    init(
        songId: String,
        title: String,
        artist: String,
        bpm: Double,
        charts: [ServerChart] = [],
        isDownloaded: Bool = false
    ) {
        self.songId = songId
        self.title = title
        self.artist = artist
        self.bpm = bpm
        self.charts = charts
        self.lastUpdated = Date()
        self.isDownloaded = isDownloaded
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
            isDownloaded: isDownloaded
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
        return []
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
    
    static var sampleData: [DrumTrack] {
        Song.sampleData.flatMap { song in
            song.charts.map { chart in
                DrumTrack(chart: chart)
            }
        }
    }
}
