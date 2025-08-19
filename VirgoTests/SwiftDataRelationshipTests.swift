//
//  SwiftDataRelationshipTests.swift
//  VirgoTests
//
//  Created by Claude Code on 19/8/2025.
//

import Testing
import SwiftData
import Foundation
@testable import Virgo

@Suite("SwiftData Relationship Tests")
@MainActor
struct SwiftDataRelationshipTests {
    
    private var testContainer: ModelContainer {
        let schema = Schema([Song.self, Chart.self, Note.self, ServerSong.self, ServerChart.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [configuration])
    }
    
    @Test("Song-Chart relationship works correctly")
    func testSongChartRelationship() {
        let container = testContainer
        let context = container.mainContext
        
        let song = Song(title: "Test Song", artist: "Test Artist", bpm: 120.0, duration: "3:00", genre: "Rock")
        let chart1 = Chart(difficulty: .easy, song: song)
        let chart2 = Chart(difficulty: .medium, song: song)
        
        song.charts = [chart1, chart2]
        
        context.insert(song)
        
        // Test forward relationship
        #expect(song.charts.count == 2)
        #expect(song.charts.contains(chart1))
        #expect(song.charts.contains(chart2))
        
        // Test backward relationship
        #expect(chart1.song == song)
        #expect(chart2.song == song)
        
        // Test convenience accessors
        #expect(song.availableDifficulties.count == 2)
        #expect(song.availableDifficulties.contains(.easy))
        #expect(song.availableDifficulties.contains(.medium))
        
        #expect(song.easiestChart == chart1) // Easy should be first
    }
    
    @Test("Chart-Note relationship works correctly")
    func testChartNoteRelationship() {
        let container = testContainer
        let context = container.mainContext
        
        let song = Song(title: "Test Song", artist: "Test Artist", bpm: 120.0, duration: "3:00", genre: "Rock")
        let chart = Chart(difficulty: .medium, song: song)
        let note1 = Note(interval: .quarter, noteType: .bass, measureNumber: 1, measureOffset: 0.0, chart: chart)
        let note2 = Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0.25, chart: chart)
        
        chart.notes = [note1, note2]
        song.charts = [chart]
        
        context.insert(song)
        
        // Test forward relationship
        #expect(chart.notes.count == 2)
        #expect(chart.notes.contains(note1))
        #expect(chart.notes.contains(note2))
        
        // Test backward relationship
        #expect(note1.chart == chart)
        #expect(note2.chart == chart)
        
        // Test safe accessors
        #expect(chart.notesCount == 2)
        #expect(chart.safeNotes.count == 2)
    }
    
    @Test("Cascade deletion works correctly")
    func testCascadeDeletion() {
        let container = testContainer
        let context = container.mainContext
        
        let song = Song(title: "Test Song", artist: "Test Artist", bpm: 120.0, duration: "3:00", genre: "Rock")
        let chart = Chart(difficulty: .medium, song: song)
        let note = Note(interval: .quarter, noteType: .bass, measureNumber: 1, measureOffset: 0.0, chart: chart)
        
        chart.notes = [note]
        song.charts = [chart]
        
        context.insert(song)
        
        // Save to ensure relationships are established
        try! context.save()
        
        // Delete the song
        context.delete(song)
        
        // Chart and Note should be cascade deleted
        #expect(chart.isDeleted)
        #expect(note.isDeleted)
    }
    
    @Test("ServerSong-ServerChart relationship works correctly")
    func testServerSongChartRelationship() {
        let container = testContainer
        let context = container.mainContext
        
        let serverSong = ServerSong(
            songId: "test-song",
            title: "Test Server Song",
            artist: "Server Artist",
            bpm: 150.0
        )
        
        let serverChart1 = ServerChart(
            difficulty: "easy",
            difficultyLabel: "BASIC",
            level: 30,
            filename: "bas.dtx",
            size: 1024,
            serverSong: serverSong
        )
        
        let serverChart2 = ServerChart(
            difficulty: "hard",
            difficultyLabel: "EXTREME",
            level: 80,
            filename: "ext.dtx",
            size: 2048,
            serverSong: serverSong
        )
        
        serverSong.charts = [serverChart1, serverChart2]
        
        context.insert(serverSong)
        
        // Test forward relationship
        #expect(serverSong.charts.count == 2)
        #expect(serverSong.charts.contains(serverChart1))
        #expect(serverSong.charts.contains(serverChart2))
        
        // Test backward relationship
        #expect(serverChart1.serverSong == serverSong)
        #expect(serverChart2.serverSong == serverSong)
    }
    
    @Test("Chart difficulty and level relationship")
    func testChartDifficultyLevel() {
        let song = Song(title: "Test Song", artist: "Test Artist", bpm: 120.0, duration: "3:00", genre: "Rock")
        
        // Test that charts get default levels based on difficulty
        let easyChart = Chart(difficulty: .easy, song: song)
        let mediumChart = Chart(difficulty: .medium, song: song)
        let hardChart = Chart(difficulty: .hard, song: song)
        let expertChart = Chart(difficulty: .expert, song: song)
        
        #expect(easyChart.level == Difficulty.easy.defaultLevel)
        #expect(mediumChart.level == Difficulty.medium.defaultLevel)
        #expect(hardChart.level == Difficulty.hard.defaultLevel)
        #expect(expertChart.level == Difficulty.expert.defaultLevel)
        
        // Test custom level override
        let customChart = Chart(difficulty: .medium, level: 75, song: song)
        #expect(customChart.level == 75)
    }
    
    @Test("Song measure count calculation")
    func testSongMeasureCount() {
        let song = Song(title: "Test Song", artist: "Test Artist", bpm: 120.0, duration: "3:00", genre: "Rock")
        let chart = Chart(difficulty: .medium, song: song)
        
        // Test with no notes
        song.charts = [chart]
        #expect(song.measureCount == 1) // Default minimum
        
        // Add notes spanning multiple measures
        let note1 = Note(interval: .quarter, noteType: .bass, measureNumber: 1, measureOffset: 0.0, chart: chart)
        let note2 = Note(interval: .quarter, noteType: .snare, measureNumber: 3, measureOffset: 0.5, chart: chart)
        let note3 = Note(interval: .quarter, noteType: .hiHat, measureNumber: 5, measureOffset: 0.75, chart: chart)
        
        chart.notes = [note1, note2, note3]
        
        #expect(song.measureCount == 5) // Should be max measure number
    }
    
    @Test("Chart convenience accessors work correctly")
    func testChartConvenienceAccessors() {
        let song = Song(
            title: "Complex Song",
            artist: "Amazing Artist",
            bpm: 175.0,
            duration: "6:30",
            genre: "Progressive Metal",
            timeSignature: .fiveFour
        )
        
        let chart = Chart(difficulty: .expert, song: song)
        song.charts = [chart]
        
        // Test that chart can access song properties
        #expect(chart.title == "Complex Song")
        #expect(chart.artist == "Amazing Artist")
        #expect(chart.bpm == 175.0)
        #expect(chart.duration == "6:30")
        #expect(chart.genre == "Progressive Metal")
        #expect(chart.timeSignature == .fiveFour)
    }
    
    @Test("Chart handles deleted song gracefully")
    func testChartWithDeletedSong() {
        let container = testContainer
        let context = container.mainContext
        
        let song = Song(title: "Test Song", artist: "Test Artist", bpm: 120.0, duration: "3:00", genre: "Rock")
        let chart = Chart(difficulty: .medium, song: song)
        song.charts = [chart]
        
        context.insert(song)
        try! context.save()
        
        // Delete the song
        context.delete(song)
        
        // Chart should handle the deleted song gracefully
        #expect(chart.title == "Unknown Song")
        #expect(chart.artist == "Unknown Artist")
        #expect(chart.bpm == 120.0) // Default fallback
        #expect(chart.duration == "0:00")
        #expect(chart.genre == "Unknown")
        #expect(chart.timeSignature == .fourFour) // Default fallback
    }
}
