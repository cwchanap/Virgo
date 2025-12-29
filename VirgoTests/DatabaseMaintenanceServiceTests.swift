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
    
    private var container: ModelContainer {
        TestContainer.shared.container
    }
    
    private var context: ModelContext {
        TestContainer.shared.context
    }
    
    @Test("DatabaseMaintenanceService updates chart levels correctly")
    func testUpdateExistingChartLevels() async throws {
        try await TestSetup.withTestSetup {
            let service = DatabaseMaintenanceService(modelContext: context)
            
            // Create songs with charts that have default level 50
            let song1 = TestModelFactory.createSong(
                in: context, title: "Song 1", artist: "Artist 1", bpm: 120.0, duration: "3:00", genre: "Rock"
            )
            let chart1 = TestModelFactory.createChart(
                in: context, difficulty: .easy, level: 50, song: song1
            ) // Should be updated to 30
            let chart2 = TestModelFactory.createChart(
                in: context, difficulty: .expert, level: 50, song: song1
            ) // Should be updated to 90
            song1.charts = [chart1, chart2]
            
            let song2 = TestModelFactory.createSong(
                in: context, title: "Song 2", artist: "Artist 2", bpm: 140.0, duration: "4:00", genre: "Jazz"
            )
            let chart3 = TestModelFactory.createChart(
                in: context, difficulty: .medium, level: 60, song: song2
            ) // Should not be updated (not default 50)
            song2.charts = [chart3]
            
            try context.save()
            
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
    }
    
    @Test("DatabaseMaintenanceService removes duplicate songs")
    func testCleanupDuplicateSongs() async throws {
        try await TestSetup.withTestSetup {
            let service = DatabaseMaintenanceService(modelContext: context)
            
            // Create duplicate songs (same title and artist, case insensitive)
            let song1 = TestModelFactory.createSong(
                in: context, title: "Rock Song", artist: "Rock Band", bpm: 120.0, duration: "3:00", genre: "Rock"
            )
            let song2 = TestModelFactory.createSong(
                in: context, title: "rock song", artist: "ROCK BAND", bpm: 125.0, duration: "3:10", genre: "Rock"
            ) // Duplicate
            let song3 = TestModelFactory.createSong(
                in: context, title: "Jazz Song", artist: "Jazz Band", bpm: 140.0, duration: "4:00", genre: "Jazz"
            )
            let song4 = TestModelFactory.createSong(
                in: context, title: "Rock Song", artist: "Rock Band", bpm: 130.0, duration: "3:05", genre: "Rock"
            ) // Another duplicate
            
            try context.save()
            
            // Verify initial state
            let initialSongs = [song1, song2, song3, song4]
            #expect(initialSongs.count == 4)
            
            // Run maintenance
            service.performInitialMaintenance(songs: initialSongs)
            
            // Verify duplicates were removed (song2 and song4 should be deleted)
            TestAssertions.assertNotDeleted(song1, in: context) // Original should remain
            TestAssertions.assertDeleted(song2, in: context) // Duplicate should be deleted
            TestAssertions.assertNotDeleted(song3, in: context) // Different song should remain
            TestAssertions.assertDeleted(song4, in: context) // Duplicate should be deleted
        }
    }
    
    @Test("DatabaseMaintenanceService handles songs with same title but different artists")
    func testDifferentArtistsSameTitleHandling() async throws {
        try await TestSetup.withTestSetup {
            let service = DatabaseMaintenanceService(modelContext: context)
            
            // Create songs with same title but different artists
            let song1 = TestModelFactory.createSong(
                in: context, title: "Love Song", artist: "Band A", bpm: 120.0, duration: "3:00", genre: "Rock"
            )
            let song2 = TestModelFactory.createSong(
                in: context, title: "Love Song", artist: "Band B", bpm: 140.0, duration: "4:00", genre: "Pop"
            )
            
            try context.save()
            
            // Run maintenance
            service.performInitialMaintenance(songs: [song1, song2])
            
            // Both songs should remain (different artists)
            TestAssertions.assertNotDeleted(song1, in: context)
            TestAssertions.assertNotDeleted(song2, in: context)
        }
    }
    
    @Test("DatabaseMaintenanceService handles songs with same artist but different titles")
    func testDifferentTitlesSameArtistHandling() async throws {
        try await TestSetup.withTestSetup {
            let service = DatabaseMaintenanceService(modelContext: context)
            
            // Create songs with same artist but different titles
            let song1 = TestModelFactory.createSong(
                in: context, title: "Song One", artist: "Great Band", bpm: 120.0, duration: "3:00", genre: "Rock"
            )
            let song2 = TestModelFactory.createSong(
                in: context, title: "Song Two", artist: "Great Band", bpm: 140.0, duration: "4:00", genre: "Rock"
            )
            
            try context.save()
            
            // Run maintenance
            service.performInitialMaintenance(songs: [song1, song2])
            
            // Both songs should remain (different titles)
            TestAssertions.assertNotDeleted(song1, in: context)
            TestAssertions.assertNotDeleted(song2, in: context)
        }
    }
    
    @Test("DatabaseMaintenanceService handles empty song list")
    func testEmptySongListHandling() async throws {
        try await TestSetup.withTestSetup {
            let service = DatabaseMaintenanceService(modelContext: context)
            
            // Run maintenance with empty list (should not crash)
            service.performInitialMaintenance(songs: [])
            
            // Should complete without error
            #expect(true) // Test passes if we reach this point
        }
    }
    
    @Test("DatabaseMaintenanceService preserves charts when removing duplicate songs")
    func testChartsPreservationDuringDuplicateRemoval() async throws {
        try await TestSetup.withTestSetup {
            let service = DatabaseMaintenanceService(modelContext: context)
            
            // Create duplicate songs with charts
            let song1 = TestModelFactory.createSong(
                in: context,
                title: "Test Song",
                artist: "Test Artist",
                bpm: 120.0,
                duration: "3:00",
                genre: "Rock"
            )
            let chart1 = TestModelFactory.createChart(in: context, difficulty: .easy, song: song1)
            let note1 = TestModelFactory.createNote(
                in: context,
                interval: .quarter,
                noteType: .bass,
                measureNumber: 1,
                measureOffset: 0.0,
                chart: chart1
            )
            chart1.notes = [note1]
            song1.charts = [chart1]
            
            let song2 = TestModelFactory.createSong(
                in: context,
                title: "test song",
                artist: "TEST ARTIST",
                bpm: 125.0,
                duration: "3:10",
                genre: "Rock"
            ) // Duplicate
            let chart2 = TestModelFactory.createChart(in: context, difficulty: .medium, song: song2)
            song2.charts = [chart2]
            
            try context.save()
            
            // Run maintenance
            service.performInitialMaintenance(songs: [song1, song2])
            
            // Original song and its data should remain
            TestAssertions.assertNotDeleted(song1, in: context)
            TestAssertions.assertNotDeleted(chart1, in: context)
            TestAssertions.assertNotDeleted(note1, in: context)
            
            // Duplicate song should be deleted (cascade deletion will handle its charts)
            TestAssertions.assertDeleted(song2, in: context)
            TestAssertions.assertDeleted(chart2, in: context) // Should be cascade deleted
        }
    }
    
    @Test("DatabaseMaintenanceService handles special characters in song titles")
    func testSpecialCharactersInTitles() async throws {
        try await TestSetup.withTestSetup {
            let service = DatabaseMaintenanceService(modelContext: context)
            
            // Create songs with special characters
            let song1 = TestModelFactory.createSong(
                in: context, title: "Rock & Roll", artist: "The Band", bpm: 120.0, duration: "3:00", genre: "Rock"
            )
            let song2 = TestModelFactory.createSong(
                in: context, title: "rock & roll", artist: "the band", bpm: 125.0, duration: "3:10", genre: "Rock"
            ) // Duplicate
            let song3 = TestModelFactory.createSong(
                in: context, title: "Hip-Hop Beat", artist: "MC Producer", bpm: 95.0, duration: "3:30", genre: "Hip Hop"
            )
            
            try context.save()
            
            // Run maintenance
            service.performInitialMaintenance(songs: [song1, song2, song3])
            
            // First song should remain, duplicate should be removed
            TestAssertions.assertNotDeleted(song1, in: context)
            TestAssertions.assertDeleted(song2, in: context)
            TestAssertions.assertNotDeleted(song3, in: context) // Different song should remain
        }
    }
}
