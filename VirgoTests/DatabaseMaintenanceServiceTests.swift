//
//  DatabaseMaintenanceServiceTests.swift
//  VirgoTests
//
//  Created by Claude Code on 19/8/2025.
//

import Testing
import SwiftData
import Foundation
@testable import Virgo

@Suite("DatabaseMaintenanceService Tests")
@MainActor
struct DatabaseMaintenanceServiceTests {
    
    private var testContainer: ModelContainer {
        let schema = Schema([Song.self, Chart.self, Note.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [configuration])
    }
    
    @Test("DatabaseMaintenanceService updates chart levels correctly")
    func testUpdateExistingChartLevels() {
        let container = testContainer
        let context = container.mainContext
        let service = DatabaseMaintenanceService(modelContext: context)
        
        // Create songs with charts that have default level 50
        let song1 = Song(title: "Song 1", artist: "Artist 1", bpm: 120.0, duration: "3:00", genre: "Rock")
        let chart1 = Chart(difficulty: .easy, level: 50, song: song1) // Should be updated to 30
        let chart2 = Chart(difficulty: .expert, level: 50, song: song1) // Should be updated to 90
        song1.charts = [chart1, chart2]
        
        let song2 = Song(title: "Song 2", artist: "Artist 2", bpm: 140.0, duration: "4:00", genre: "Jazz")
        let chart3 = Chart(difficulty: .medium, level: 60, song: song2) // Should not be updated (not default 50)
        song2.charts = [chart3]
        
        context.insert(song1)
        context.insert(song2)
        try! context.save()
        
        // Verify initial state
        #expect(chart1.level == 50)
        #expect(chart2.level == 50)
        #expect(chart3.level == 60)
        
        // Run maintenance
        service.performInitialMaintenance(songs: [song1, song2])
        
        // Verify levels were updated correctly
        #expect(chart1.level == Difficulty.easy.defaultLevel) // 30
        #expect(chart2.level == Difficulty.expert.defaultLevel) // 90
        #expect(chart3.level == 60) // Should remain unchanged
    }
    
    @Test("DatabaseMaintenanceService removes duplicate songs")
    func testCleanupDuplicateSongs() {
        let container = testContainer
        let context = container.mainContext
        let service = DatabaseMaintenanceService(modelContext: context)
        
        // Create duplicate songs (same title and artist, case insensitive)
        let song1 = Song(title: "Rock Song", artist: "Rock Band", bpm: 120.0, duration: "3:00", genre: "Rock")
        let song2 = Song(title: "rock song", artist: "ROCK BAND", bpm: 125.0, duration: "3:10", genre: "Rock") // Duplicate
        let song3 = Song(title: "Jazz Song", artist: "Jazz Band", bpm: 140.0, duration: "4:00", genre: "Jazz")
        let song4 = Song(title: "Rock Song", artist: "Rock Band", bpm: 130.0, duration: "3:05", genre: "Rock") // Another duplicate
        
        context.insert(song1)
        context.insert(song2)
        context.insert(song3)
        context.insert(song4)
        try! context.save()
        
        // Verify initial state
        let initialSongs = [song1, song2, song3, song4]
        #expect(initialSongs.count == 4)
        
        // Run maintenance
        service.performInitialMaintenance(songs: initialSongs)
        
        // Verify duplicates were removed (song2 and song4 should be deleted)
        #expect(!song1.isDeleted) // Original should remain
        #expect(song2.isDeleted) // Duplicate should be deleted
        #expect(!song3.isDeleted) // Different song should remain
        #expect(song4.isDeleted) // Duplicate should be deleted
    }
    
    @Test("DatabaseMaintenanceService handles songs with same title but different artists")
    func testDifferentArtistsSameTitleHandling() {
        let container = testContainer
        let context = container.mainContext
        let service = DatabaseMaintenanceService(modelContext: context)
        
        // Create songs with same title but different artists
        let song1 = Song(title: "Love Song", artist: "Band A", bpm: 120.0, duration: "3:00", genre: "Rock")
        let song2 = Song(title: "Love Song", artist: "Band B", bpm: 140.0, duration: "4:00", genre: "Pop")
        
        context.insert(song1)
        context.insert(song2)
        try! context.save()
        
        // Run maintenance
        service.performInitialMaintenance(songs: [song1, song2])
        
        // Both songs should remain (different artists)
        #expect(!song1.isDeleted)
        #expect(!song2.isDeleted)
    }
    
    @Test("DatabaseMaintenanceService handles songs with same artist but different titles")
    func testDifferentTitlesSameArtistHandling() {
        let container = testContainer
        let context = container.mainContext
        let service = DatabaseMaintenanceService(modelContext: context)
        
        // Create songs with same artist but different titles
        let song1 = Song(title: "Song One", artist: "Great Band", bpm: 120.0, duration: "3:00", genre: "Rock")
        let song2 = Song(title: "Song Two", artist: "Great Band", bpm: 140.0, duration: "4:00", genre: "Rock")
        
        context.insert(song1)
        context.insert(song2)
        try! context.save()
        
        // Run maintenance
        service.performInitialMaintenance(songs: [song1, song2])
        
        // Both songs should remain (different titles)
        #expect(!song1.isDeleted)
        #expect(!song2.isDeleted)
    }
    
    @Test("DatabaseMaintenanceService handles empty song list")
    func testEmptySongListHandling() {
        let container = testContainer
        let context = container.mainContext
        let service = DatabaseMaintenanceService(modelContext: context)
        
        // Run maintenance with empty list (should not crash)
        service.performInitialMaintenance(songs: [])
        
        // Should complete without error
        #expect(true) // Test passes if we reach this point
    }
    
    @Test("DatabaseMaintenanceService preserves charts when removing duplicate songs")
    func testChartsPreservationDuringDuplicateRemoval() {
        let container = testContainer
        let context = container.mainContext
        let service = DatabaseMaintenanceService(modelContext: context)
        
        // Create duplicate songs with charts
        let song1 = Song(title: "Test Song", artist: "Test Artist", bpm: 120.0, duration: "3:00", genre: "Rock")
        let chart1 = Chart(difficulty: .easy, song: song1)
        let note1 = Note(interval: .quarter, noteType: .bass, measureNumber: 1, measureOffset: 0.0, chart: chart1)
        chart1.notes = [note1]
        song1.charts = [chart1]
        
        let song2 = Song(title: "test song", artist: "TEST ARTIST", bpm: 125.0, duration: "3:10", genre: "Rock") // Duplicate
        let chart2 = Chart(difficulty: .medium, song: song2)
        song2.charts = [chart2]
        
        context.insert(song1)
        context.insert(song2)
        try! context.save()
        
        // Run maintenance
        service.performInitialMaintenance(songs: [song1, song2])
        
        // Original song and its data should remain
        #expect(!song1.isDeleted)
        #expect(!chart1.isDeleted)
        #expect(!note1.isDeleted)
        
        // Duplicate song should be deleted (cascade deletion will handle its charts)
        #expect(song2.isDeleted)
        #expect(chart2.isDeleted) // Should be cascade deleted
    }
    
    @Test("DatabaseMaintenanceService handles special characters in song titles")
    func testSpecialCharactersInTitles() {
        let container = testContainer
        let context = container.mainContext
        let service = DatabaseMaintenanceService(modelContext: context)
        
        // Create songs with special characters
        let song1 = Song(title: "Rock & Roll", artist: "The Band", bpm: 120.0, duration: "3:00", genre: "Rock")
        let song2 = Song(title: "rock & roll", artist: "the band", bpm: 125.0, duration: "3:10", genre: "Rock") // Duplicate
        let song3 = Song(title: "Hip-Hop Beat", artist: "MC Producer", bpm: 95.0, duration: "3:30", genre: "Hip Hop")
        
        context.insert(song1)
        context.insert(song2)
        context.insert(song3)
        try! context.save()
        
        // Run maintenance
        service.performInitialMaintenance(songs: [song1, song2, song3])
        
        // First song should remain, duplicate should be removed
        #expect(!song1.isDeleted)
        #expect(song2.isDeleted)
        #expect(!song3.isDeleted) // Different song should remain
    }
}
