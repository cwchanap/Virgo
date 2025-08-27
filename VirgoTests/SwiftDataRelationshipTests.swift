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
    
    @Test("Song-Chart relationship works correctly")
    func testSongChartRelationship() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            
            let song = TestModelFactory.createSong(in: context, title: "Test Song", artist: "Test Artist")
            let chart1 = TestModelFactory.createChart(in: context, difficulty: .easy, song: song)
            let chart2 = TestModelFactory.createChart(in: context, difficulty: .medium, song: song)
            
            song.charts = [chart1, chart2]
            try context.save()
            
            // Load relationships safely
            try await AsyncTestingUtilities.loadRelationships(for: song)
            
            // Test forward relationship with safe access
            let chartsCount = try await AsyncTestingUtilities.safeRelationshipAccess(
                model: song,
                relationshipAccessor: { $0.charts.count }
            )
            #expect(chartsCount == 2)
            
            let charts = try await AsyncTestingUtilities.safeRelationshipAccess(
                model: song,
                relationshipAccessor: { $0.charts }
            )
            #expect(charts.contains(chart1))
            #expect(charts.contains(chart2))
            
            // Test backward relationship
            TestAssertions.assertEqual(chart1.song, song)
            TestAssertions.assertEqual(chart2.song, song)
            
            // Test convenience accessors
            let difficulties = try await AsyncTestingUtilities.safeRelationshipAccess(
                model: song,
                relationshipAccessor: { $0.availableDifficulties }
            )
            #expect(difficulties.count == 2)
            #expect(difficulties.contains(.easy))
            #expect(difficulties.contains(.medium))
        
            let easiest = try await AsyncTestingUtilities.safeRelationshipAccess(
                model: song,
                relationshipAccessor: { $0.easiestChart }
            )
            TestAssertions.assertEqual(easiest, chart1)
        }
    }
    
    @Test("Chart-Note relationship works correctly")
    func testChartNoteRelationship() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            
            let (song, chart) = try await TestModelFactory.createSongWithChart(
                in: context,
                title: "Test Song",
                artist: "Test Artist",
                noteCount: 2
            )
            
            // Load relationships safely
            try await AsyncTestingUtilities.loadRelationships(for: chart)
            
            // Test forward relationship with safe access
            let notesCount = try await AsyncTestingUtilities.safeRelationshipAccess(
                model: chart,
                relationshipAccessor: { $0.notes.count }
            )
            #expect(notesCount == 2)
            
            let notes = try await AsyncTestingUtilities.safeRelationshipAccess(
                model: chart,
                relationshipAccessor: { $0.notes }
            )
            
            // Test backward relationship
            for note in notes {
                TestAssertions.assertEqual(note.chart, chart)
            }
            
            // Test safe accessors
            let safeNotesCount = try await AsyncTestingUtilities.safeAccess(
                model: chart,
                accessor: { $0.notesCount }
            )
            #expect(safeNotesCount == 2)
        
            let safeNotes = try await AsyncTestingUtilities.safeAccess(
                model: chart,
                accessor: { $0.safeNotes }
            )
            #expect(safeNotes.count == 2)
        }
    }
    
    @Test("Cascade deletion works correctly")
    func testCascadeDeletion() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            
            let song = TestModelFactory.createSong(
                in: context,
                title: "Test Song",
                artist: "Test Artist",
                bpm: 120.0,
                duration: "3:00",
                genre: "Rock"
            )
            let chart = TestModelFactory.createChart(in: context, difficulty: .medium, song: song)
            let note = TestModelFactory.createNote(
                in: context,
                interval: .quarter,
                noteType: .bass,
                measureNumber: 1,
                measureOffset: 0.0,
                chart: chart
            )
            
            chart.notes = [note]
            song.charts = [chart]
            
            // Save to ensure relationships are established
            try! context.save()
            
            // Delete the song
            context.delete(song)
        
            // Chart and Note should be cascade deleted
            TestAssertions.assertDeleted(chart, in: context)
            TestAssertions.assertDeleted(note, in: context)
        }
    }
    
    @Test("ServerSong-ServerChart relationship works correctly")
    func testServerSongChartRelationship() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            
            let serverSong = TestModelFactory.createServerSong(
                in: context,
                songId: "test-song",
                title: "Test Server Song",
                artist: "Server Artist",
                bpm: 150.0
            )
            
            let serverChart1 = TestModelFactory.createServerChart(
                in: context,
                difficulty: "easy",
                difficultyLabel: "BASIC",
                level: 30,
                filename: "bas.dtx",
                size: 1024,
                serverSong: serverSong
            )
            
            let serverChart2 = TestModelFactory.createServerChart(
                in: context,
                difficulty: "hard",
                difficultyLabel: "EXTREME",
                level: 80,
                filename: "ext.dtx",
                size: 2048,
                serverSong: serverSong
            )
            
            serverSong.charts = [serverChart1, serverChart2]
            
            // Test forward relationship
            #expect(serverSong.charts.count == 2)
            #expect(serverSong.charts.contains(serverChart1))
            #expect(serverSong.charts.contains(serverChart2))
        
            // Test backward relationship
            #expect(serverChart1.serverSong == serverSong)
            #expect(serverChart2.serverSong == serverSong)
        }
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
    
    @Test("Chart cascade deletion works correctly")
    func testChartCascadeDeletion() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            
            let song = TestModelFactory.createSong(in: context, title: "Test Song", artist: "Test Artist")
            let chart = TestModelFactory.createChart(in: context, difficulty: .medium, song: song)
            song.charts = [chart]
            
            try context.save()
            
            // Load relationships before deletion
            try await AsyncTestingUtilities.loadRelationships(for: song)
            try await AsyncTestingUtilities.loadRelationships(for: chart)
            
            // Verify initial state
            TestAssertions.assertNotDeleted(song, in: context)
            TestAssertions.assertNotDeleted(chart, in: context)
            
            // Delete the song - this should cascade delete the chart immediately
            context.delete(song)
            
            // Both song and chart should be cascade deleted due to deleteRule: .cascade
            TestAssertions.assertDeleted(song, in: context)
            TestAssertions.assertDeleted(chart, in: context)
        }
    }
}
