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

    // MARK: - serverSongId-aware dedup

    @Test("cleanupDuplicateSongs preserves server songs with different serverSongIds")
    func testPreservesServerSongsWithDifferentServerSongIds() async throws {
        try await TestSetup.withTestSetup {
            let service = DatabaseMaintenanceService(modelContext: context)

            // Two server-imported songs with same title/artist but different serverSongIds
            let songA = Song(
                title: "Same Name", artist: "Same Artist", bpm: 120, duration: "3:00",
                genre: "DTX Import", isServerImported: true, serverSongId: "server-song-a"
            )
            let songB = Song(
                title: "Same Name", artist: "Same Artist", bpm: 140, duration: "3:30",
                genre: "DTX Import", isServerImported: true, serverSongId: "server-song-b"
            )
            context.insert(songA)
            context.insert(songB)
            try context.save()

            service.performInitialMaintenance(songs: [songA, songB])

            // Both songs survive — they have different serverSongIds
            TestAssertions.assertNotDeleted(songA, in: context)
            TestAssertions.assertNotDeleted(songB, in: context)
        }
    }

    @Test("cleanupDuplicateSongs removes server songs with same serverSongId and same title/artist")
    func testRemovesServerSongsWithSameServerSongId() async throws {
        try await TestSetup.withTestSetup {
            let service = DatabaseMaintenanceService(modelContext: context)

            // Two server-imported songs with the same serverSongId AND same title/artist
            let songA = Song(
                title: "Same Name", artist: "Same Artist", bpm: 120, duration: "3:00",
                genre: "DTX Import", isServerImported: true, serverSongId: "server-song-a"
            )
            let songB = Song(
                title: "Same Name", artist: "Same Artist", bpm: 140, duration: "3:30",
                genre: "DTX Import", isServerImported: true, serverSongId: "server-song-a"
            )
            context.insert(songA)
            context.insert(songB)
            try context.save()

            service.performInitialMaintenance(songs: [songA, songB])

            // First survives, second (exact duplicate) is removed
            TestAssertions.assertNotDeleted(songA, in: context)
            TestAssertions.assertDeleted(songB, in: context)
        }
    }

    // MARK: - isServerImported backfill (legacy "DTX Import" genre -> flag)

    @Test("performInitialMaintenance backfills isServerImported for legacy DTX Import songs")
    func testBackfillServerImportedFlagForLegacyDTXImportSongs() async throws {
        try await TestSetup.withTestSetup {
            let service = DatabaseMaintenanceService(modelContext: context)

            // Legacy downloaded song: pre-migration it was classified by genre only,
            // so after the additive SwiftData migration isServerImported defaults to false.
            let legacyDownloaded = TestModelFactory.createSong(
                in: context, title: "Legacy DL", artist: "Server", genre: "DTX Import"
            )
            // Local (non-downloaded) song must be left untouched.
            let localSong = TestModelFactory.createSong(
                in: context, title: "Local Jam", artist: "Me", genre: "Rock"
            )
            // A server-imported song with a curated genre that already has the flag set
            // must not be reclassified or disturbed.
            let curatedImported = Song(
                title: "Curated", artist: "Server", bpm: 120, duration: "3:00",
                genre: "Pop", isServerImported: true
            )
            context.insert(curatedImported)
            try context.save()

            // Sanity: legacy song starts un-flagged (simulating the migration default).
            #expect(legacyDownloaded.isServerImported == false)

            service.performInitialMaintenance(
                songs: [legacyDownloaded, localSong, curatedImported]
            )

            // Legacy DTX Import song is backfilled to the explicit flag.
            #expect(legacyDownloaded.isServerImported == true,
                    "Legacy server-imported song must be backfilled to isServerImported == true")
            // Local song is never marked as server-imported.
            #expect(localSong.isServerImported == false)
            // Already-flagged curated song is unchanged.
            #expect(curatedImported.isServerImported == true)
        }
    }

    @Test("Backfill is idempotent across repeated maintenance runs")
    func testBackfillServerImportedFlagIsIdempotent() async throws {
        try await TestSetup.withTestSetup {
            let service = DatabaseMaintenanceService(modelContext: context)

            let localSong = TestModelFactory.createSong(
                in: context, title: "Local", artist: "Me", genre: "Jazz"
            )
            try context.save()

            service.performInitialMaintenance(songs: [localSong])
            service.performInitialMaintenance(songs: [localSong])

            // A genuinely local song must not get flipped to server-imported even after
            // repeated runs — the backfill predicate is scoped to genre == "DTX Import".
            #expect(localSong.isServerImported == false)
        }
    }
}
