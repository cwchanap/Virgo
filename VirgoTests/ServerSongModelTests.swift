//
//  ServerSongModelTests.swift
//  VirgoTests
//
//  Created by Claude Code on 19/8/2025.
//

import Testing
import Foundation
import SwiftData
@testable import Virgo

@Suite("Server Song Model Tests")
@MainActor
struct ServerSongModelTests {
    
    @Test("ServerSong initializes with default values")
    func testServerSongDefaultInitialization() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let serverSong = ServerSong(
                songId: "test_song_001",
                title: "Test Song",
                artist: "Test Artist",
                bpm: 140.0
            )
            context.insert(serverSong)
            
            #expect(serverSong.songId == "test_song_001")
            #expect(serverSong.title == "Test Song")
            #expect(serverSong.artist == "Test Artist")
            #expect(serverSong.bpm == 140.0)
            #expect(serverSong.charts.isEmpty)
            #expect(serverSong.isDownloaded == false)
            #expect(serverSong.hasBGM == false)
            #expect(serverSong.bgmDownloaded == false)
            #expect(serverSong.hasPreview == false)
            #expect(serverSong.previewDownloaded == false)
            #expect(serverSong.lastUpdated <= Date())
        }
    }
    
    @Test("ServerSong initializes with custom values")
    func testServerSongCustomInitialization() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let charts = [
                ServerChart(difficulty: "easy", difficultyLabel: "BASIC", level: 25, filename: "bas.dtx", size: 400),
                ServerChart(difficulty: "hard", difficultyLabel: "EXTREME", level: 85, filename: "ext.dtx", size: 1200)
            ]
            
            charts.forEach { context.insert($0) }
            
            let serverSong = ServerSong(
                songId: "custom_song_002",
                title: "Custom Song",
                artist: "Custom Artist",
                bpm: 160.0,
                charts: charts,
                isDownloaded: true,
                hasBGM: true,
                bgmDownloaded: true,
                hasPreview: true,
                previewDownloaded: false
            )
            context.insert(serverSong)
            
            #expect(serverSong.charts.count == 2)
            #expect(serverSong.isDownloaded == true)
            #expect(serverSong.hasBGM == true)
            #expect(serverSong.bgmDownloaded == true)
            #expect(serverSong.hasPreview == true)
            #expect(serverSong.previewDownloaded == false)
        }
    }
    
    @Test("ServerSong legacy convenience initializer works correctly")
    func testServerSongLegacyInitializer() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let serverSong = ServerSong(
                filename: "legacy_song.dtx",
                title: "Legacy Song",
                artist: "Legacy Artist",
                bpm: 130.0,
                difficultyLevel: 45,
                size: 800,
                isDownloaded: true
            )
            context.insert(serverSong)
            
            #expect(serverSong.songId == "legacy_song")
            #expect(serverSong.title == "Legacy Song")
            #expect(serverSong.artist == "Legacy Artist")
            #expect(serverSong.bpm == 130.0)
            #expect(serverSong.isDownloaded == true)
            #expect(serverSong.charts.count == 1)
            
            let chart = serverSong.charts.first!
            #expect(chart.difficulty == "medium")
            #expect(chart.difficultyLabel == "STANDARD")
            #expect(chart.level == 45)
            #expect(chart.filename == "legacy_song.dtx")
            #expect(chart.size == 800)
            #expect(serverSong.hasBGM == false)
            #expect(serverSong.hasPreview == false)
        }
    }
    
    @Test("ServerSong handles various BPM values")
    func testServerSongBPMValues() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let slowSong = ServerSong(songId: "slow", title: "Slow", artist: "Artist", bpm: 60.0)
            context.insert(slowSong)
            let mediumSong = ServerSong(songId: "medium", title: "Medium", artist: "Artist", bpm: 120.0)
            context.insert(mediumSong)
            let fastSong = ServerSong(songId: "fast", title: "Fast", artist: "Artist", bpm: 200.0)
            context.insert(fastSong)
            
            #expect(slowSong.bpm == 60.0)
            #expect(mediumSong.bpm == 120.0)
            #expect(fastSong.bpm == 200.0)
        }
    }
    
    @Test("ServerSong tracks download status correctly")
    func testServerSongDownloadStatus() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let serverSong = ServerSong(songId: "download_test", title: "Test", artist: "Artist", bpm: 120.0)
            context.insert(serverSong)
            
            // Initially not downloaded
            #expect(serverSong.isDownloaded == false)
            #expect(serverSong.bgmDownloaded == false)
            #expect(serverSong.previewDownloaded == false)
            
            // Simulate downloads
            serverSong.isDownloaded = true
            serverSong.bgmDownloaded = true
            serverSong.previewDownloaded = true
            
            #expect(serverSong.isDownloaded == true)
            #expect(serverSong.bgmDownloaded == true)
            #expect(serverSong.previewDownloaded == true)
        }
    }
    
    @Test("ServerSong tracks media availability correctly")
    func testServerSongMediaAvailability() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let serverSong = ServerSong(songId: "media_test", title: "Test", artist: "Artist", bpm: 120.0)
            context.insert(serverSong)
            
            // Initially no media available
            #expect(serverSong.hasBGM == false)
            #expect(serverSong.hasPreview == false)
            
            // Add media availability
            serverSong.hasBGM = true
            serverSong.hasPreview = true
            
            #expect(serverSong.hasBGM == true)
            #expect(serverSong.hasPreview == true)
        }
    }
    
    @Test("ServerSong lastUpdated is set correctly")
    func testServerSongLastUpdated() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let beforeCreation = Date()
            let serverSong = ServerSong(songId: "time_test", title: "Test", artist: "Artist", bpm: 120.0)
            context.insert(serverSong)
            let afterCreation = Date()
            
            #expect(serverSong.lastUpdated >= beforeCreation)
            #expect(serverSong.lastUpdated <= afterCreation)
        }
    }
    
    @Test("ServerSong song ID extraction from filename")
    func testServerSongIDExtraction() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let serverSong = ServerSong(
                filename: "test_song_with_spaces.dtx",
                title: "Test Song",
                artist: "Artist",
                bpm: 120.0,
                difficultyLevel: 50,
                size: 1000
            )
            context.insert(serverSong)
            
            #expect(serverSong.songId == "test_song_with_spaces")
        }
    }
}