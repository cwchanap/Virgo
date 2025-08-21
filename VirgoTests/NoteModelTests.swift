//
//  NoteModelTests.swift
//  VirgoTests
//
//  Created by Claude Code on 19/8/2025.
//

import Testing
import Foundation
import SwiftData
@testable import Virgo

@Suite("Note Model Tests")
struct NoteModelTests {
    
    // Create a test model container for SwiftData models
    static let testContainer: ModelContainer = {
        do {
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            return try ModelContainer(for: Song.self, Chart.self, Note.self, configurations: config)
        } catch {
            fatalError("Failed to create test container: \(error)")
        }
    }()
    
    @Test("Note initializes with correct properties")
    func testNoteInitialization() {
        let context = ModelContext(Self.testContainer)
        let note = Note(
            interval: .eighth, 
            noteType: .bass, 
            measureNumber: 2, 
            measureOffset: 0.5
        )
        context.insert(note)
        
        #expect(note.interval == .eighth)
        #expect(note.noteType == .bass)
        #expect(note.measureNumber == 2)
        #expect(note.measureOffset == 0.5)
        #expect(note.chart == nil)
    }
    
    @Test("Note can be created with chart reference")
    func testNoteWithChart() {
        let context = ModelContext(Self.testContainer)
        let song = Song(title: "Test", artist: "Artist", bpm: 120, duration: "3:00", genre: "Rock")
        let chart = Chart(difficulty: .medium, song: song)
        context.insert(song)
        context.insert(chart)
        let note = Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0.0, chart: chart)
        context.insert(note)
        
        #expect(note.chart === chart)
    }
    
    @Test("Note handles various intervals correctly")
    func testNoteIntervals() {
        let context = ModelContext(Self.testContainer)
        let intervals: [NoteInterval] = [.full, .half, .quarter, .eighth, .sixteenth, .thirtysecond]
        
        for interval in intervals {
            let note = Note(interval: interval, noteType: .bass, measureNumber: 1, measureOffset: 0.0)
            context.insert(note)
            #expect(note.interval == interval)
        }
    }
    
    @Test("Note handles various drum types correctly")
    func testNoteDrumTypes() {
        let context = ModelContext(Self.testContainer)
        let drumTypes: [NoteType] = [.bass, .snare, .hiHat, .crash, .ride, .highTom, .midTom, .lowTom]
        
        for drumType in drumTypes {
            let note = Note(interval: .quarter, noteType: drumType, measureNumber: 1, measureOffset: 0.0)
            context.insert(note)
            #expect(note.noteType == drumType)
        }
    }
    
    @Test("Note measure number validation")
    func testNoteMeasureValidation() {
        let context = ModelContext(Self.testContainer)
        let note1 = Note(interval: .quarter, noteType: .bass, measureNumber: 0, measureOffset: 0.0)
        let note2 = Note(interval: .quarter, noteType: .bass, measureNumber: 100, measureOffset: 0.0)
        context.insert(note1)
        context.insert(note2)
        
        #expect(note1.measureNumber == 0)
        #expect(note2.measureNumber == 100)
    }
    
    @Test("Note measure offset validation")
    func testNoteMeasureOffset() {
        let context = ModelContext(Self.testContainer)
        let note1 = Note(interval: .quarter, noteType: .bass, measureNumber: 1, measureOffset: 0.0)
        let note2 = Note(interval: .quarter, noteType: .bass, measureNumber: 1, measureOffset: 0.75)
        let note3 = Note(interval: .quarter, noteType: .bass, measureNumber: 1, measureOffset: 1.0)
        context.insert(note1)
        context.insert(note2)
        context.insert(note3)
        
        #expect(note1.measureOffset == 0.0)
        #expect(note2.measureOffset == 0.75)
        #expect(note3.measureOffset == 1.0)
    }
}

@Suite("Chart Model Tests")
struct ChartModelTests {
    
    @Test("Chart initializes with default values")
    func testChartDefaultInitialization() {
        let chart = Chart(difficulty: .medium)
        
        #expect(chart.difficulty == .medium)
        #expect(chart.level == 50) // medium default level
        #expect(chart.timeSignature == .fourFour)
        #expect(chart.notes.isEmpty)
        #expect(chart.song == nil)
    }
    
    @Test("Chart initializes with custom values")
    func testChartCustomInitialization() {
        let song = Song(title: "Test", artist: "Artist", bpm: 120, duration: "3:00", genre: "Rock")
        let notes = [
            Note(interval: .quarter, noteType: .bass, measureNumber: 1, measureOffset: 0.0),
            Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0.5)
        ]
        
        let chart = Chart(
            difficulty: .hard, 
            level: 75, 
            timeSignature: .threeFour, 
            notes: notes, 
            song: song
        )
        
        #expect(chart.difficulty == .hard)
        #expect(chart.level == 75)
        #expect(chart.timeSignature == .threeFour)
        #expect(chart.notes.count == 2)
        #expect(chart.song === song)
    }
    
    @Test("Chart convenience accessors work correctly")
    func testChartConvenienceAccessors() {
        let song = Song(title: "Test Song", artist: "Test Artist", bpm: 140, duration: "4:30", genre: "Jazz")
        let chart = Chart(difficulty: .expert, song: song)
        
        #expect(chart.title == "Test Song")
        #expect(chart.artist == "Test Artist")
        #expect(chart.bpm == 140)
        #expect(chart.duration == "4:30")
        #expect(chart.genre == "Jazz")
    }
    
    @Test("Chart handles nil song gracefully")
    func testChartNilSong() {
        let chart = Chart(difficulty: .easy)
        
        #expect(chart.title == "Unknown Song")
        #expect(chart.artist == "Unknown Artist")
        #expect(chart.bpm == 120.0)
        #expect(chart.duration == "0:00")
        #expect(chart.genre == "Unknown")
    }
    
    @Test("Chart notes count works correctly")
    func testChartNotesCount() {
        let chart = Chart(difficulty: .medium)
        #expect(chart.notesCount == 0)
        
        let notes = [
            Note(interval: .quarter, noteType: .bass, measureNumber: 1, measureOffset: 0.0),
            Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: 0.25),
            Note(interval: .quarter, noteType: .hiHat, measureNumber: 1, measureOffset: 0.5)
        ]
        chart.notes = notes
        
        #expect(chart.notesCount == 3)
    }
    
    @Test("Chart safe notes filtering")
    func testChartSafeNotes() {
        let chart = Chart(difficulty: .medium)
        let notes = [
            Note(interval: .quarter, noteType: .bass, measureNumber: 1, measureOffset: 0.0),
            Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: 0.25)
        ]
        chart.notes = notes
        
        let safeNotes = chart.safeNotes
        #expect(safeNotes.count == 2)
    }
    
    @Test("Chart difficulty color mapping")
    func testChartDifficultyColor() {
        let easyChart = Chart(difficulty: .easy)
        let mediumChart = Chart(difficulty: .medium)
        let hardChart = Chart(difficulty: .hard)
        let expertChart = Chart(difficulty: .expert)
        
        #expect(easyChart.difficultyColor == .green)
        #expect(mediumChart.difficultyColor == .orange)
        #expect(hardChart.difficultyColor == .red)
        #expect(expertChart.difficultyColor == .purple)
    }
    
    @Test("Chart time signature inheritance from song")
    func testChartTimeSignatureInheritance() {
        let song = Song(title: "Test", artist: "Artist", bpm: 120, duration: "3:00", genre: "Rock", timeSignature: .sixEight)
        let chart = Chart(difficulty: .medium, song: song)
        
        #expect(chart.timeSignature == .sixEight)
        
        // Override should work
        chart.timeSignature = .fiveFour
        #expect(chart.timeSignature == .fiveFour)
    }
}

@Suite("Song Model Tests")
struct SongModelTests {
    
    @Test("Song initializes with correct properties")
    func testSongInitialization() {
        let song = Song(
            title: "Test Song",
            artist: "Test Artist", 
            bpm: 120,
            duration: "3:45",
            genre: "Rock"
        )
        
        #expect(song.title == "Test Song")
        #expect(song.artist == "Test Artist")
        #expect(song.bpm == 120)
        #expect(song.duration == "3:45")
        #expect(song.genre == "Rock")
        #expect(song.timeSignature == .fourFour)
        #expect(song.isPlaying == false)
        #expect(song.playCount == 0)
        #expect(song.isSaved == false)
        #expect(song.charts.isEmpty)
        #expect(song.bgmFilePath == nil)
        #expect(song.previewFilePath == nil)
    }
    
    @Test("Song initializes with custom values")
    func testSongCustomInitialization() {
        let charts = [Chart(difficulty: .easy), Chart(difficulty: .hard)]
        let song = Song(
            title: "Custom Song",
            artist: "Custom Artist",
            bpm: 140,
            duration: "5:20",
            genre: "Electronic",
            timeSignature: .threeFour,
            charts: charts,
            isPlaying: true,
            playCount: 10,
            isSaved: true,
            bgmFilePath: "/path/to/bgm.wav",
            previewFilePath: "/path/to/preview.wav"
        )
        
        #expect(song.timeSignature == .threeFour)
        #expect(song.isPlaying == true)
        #expect(song.playCount == 10)
        #expect(song.isSaved == true)
        #expect(song.charts.count == 2)
        #expect(song.bgmFilePath == "/path/to/bgm.wav")
        #expect(song.previewFilePath == "/path/to/preview.wav")
    }
    
    @Test("Song available difficulties computation")
    func testSongAvailableDifficulties() {
        let song = Song(title: "Test", artist: "Artist", bpm: 120, duration: "3:00", genre: "Rock")
        let charts = [
            Chart(difficulty: .hard, song: song),
            Chart(difficulty: .easy, song: song),
            Chart(difficulty: .expert, song: song)
        ]
        song.charts = charts
        
        let difficulties = song.availableDifficulties
        #expect(difficulties.count == 3)
        #expect(difficulties == [.easy, .hard, .expert]) // Should be sorted
    }
    
    @Test("Song easiest chart selection")
    func testSongEasiestChart() {
        let song = Song(title: "Test", artist: "Artist", bpm: 120, duration: "3:00", genre: "Rock")
        let hardChart = Chart(difficulty: .hard, song: song)
        let easyChart = Chart(difficulty: .easy, song: song)
        let expertChart = Chart(difficulty: .expert, song: song)
        song.charts = [hardChart, easyChart, expertChart]
        
        let easiest = song.easiestChart
        #expect(easiest?.difficulty == .easy)
    }
    
    @Test("Song measure count calculation")
    func testSongMeasureCount() {
        let song = Song(title: "Test", artist: "Artist", bpm: 120, duration: "3:00", genre: "Rock")
        let chart = Chart(difficulty: .medium, song: song)
        let notes = [
            Note(interval: .quarter, noteType: .bass, measureNumber: 1, measureOffset: 0.0),
            Note(interval: .quarter, noteType: .snare, measureNumber: 3, measureOffset: 0.0),
            Note(interval: .quarter, noteType: .hiHat, measureNumber: 5, measureOffset: 0.0)
        ]
        chart.notes = notes
        song.charts = [chart]
        
        #expect(song.measureCount == 5)
    }
    
    @Test("Song chart lookup by difficulty")
    func testSongChartLookup() {
        let song = Song(title: "Test", artist: "Artist", bpm: 120, duration: "3:00", genre: "Rock")
        let easyChart = Chart(difficulty: .easy, song: song)
        let hardChart = Chart(difficulty: .hard, song: song)
        song.charts = [easyChart, hardChart]
        
        #expect(song.chart(for: .easy) === easyChart)
        #expect(song.chart(for: .hard) === hardChart)
        #expect(song.chart(for: .medium) == nil)
    }
    
    @Test("Song date added is set correctly")
    func testSongDateAdded() {
        let beforeCreation = Date()
        let song = Song(title: "Test", artist: "Artist", bpm: 120, duration: "3:00", genre: "Rock")
        let afterCreation = Date()
        
        #expect(song.dateAdded >= beforeCreation)
        #expect(song.dateAdded <= afterCreation)
    }
}
