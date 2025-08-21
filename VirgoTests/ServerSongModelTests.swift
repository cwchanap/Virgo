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
struct ServerSongModelTests {
    
    // Create a test model container for SwiftData models
    static let testContainer: ModelContainer = {
        do {
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            return try ModelContainer(for: Song.self, Chart.self, Note.self, ServerSong.self, ServerChart.self, configurations: config)
        } catch {
            fatalError("Failed to create test container: \(error)")
        }
    }()
    
    @Test("ServerChart initializes with correct properties")
    func testServerChartInitialization() {
        let context = ModelContext(Self.testContainer)
        let chart = ServerChart(
            difficulty: "medium",
            difficultyLabel: "ADVANCED",
            level: 60,
            filename: "adv.dtx",
            size: 1024
        )
        context.insert(chart)
        
        #expect(chart.difficulty == "medium")
        #expect(chart.difficultyLabel == "ADVANCED")
        #expect(chart.level == 60)
        #expect(chart.filename == "adv.dtx")
        #expect(chart.size == 1024)
        #expect(chart.serverSong == nil)
    }
    
    @Test("ServerChart can be created with server song reference")
    func testServerChartWithServerSong() {
        let context = ModelContext(Self.testContainer)
        let serverSong = ServerSong(songId: "test_song", title: "Test", artist: "Artist", bpm: 120)
        context.insert(serverSong)
        let chart = ServerChart(
            difficulty: "easy",
            difficultyLabel: "BASIC",
            level: 30,
            filename: "bas.dtx",
            size: 512,
            serverSong: serverSong
        )
        context.insert(chart)
        
        #expect(chart.serverSong === serverSong)
    }
    
    @Test("ServerSong initializes with default values")
    func testServerSongDefaultInitialization() {
        let context = ModelContext(Self.testContainer)
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
    
    @Test("ServerSong initializes with custom values")
    func testServerSongCustomInitialization() {
        let context = ModelContext(Self.testContainer)
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
    
    @Test("ServerSong legacy convenience initializer works correctly")
    func testServerSongLegacyInitializer() {
        let context = ModelContext(Self.testContainer)
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
    
    @Test("ServerSong handles various BPM values")
    func testServerSongBPMValues() {
        let context = ModelContext(Self.testContainer)
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
    
    @Test("ServerSong tracks download status correctly")
    func testServerSongDownloadStatus() {
        let context = ModelContext(Self.testContainer)
        let serverSong = ServerSong(songId: "download_test", title: "Test", artist: "Artist", bpm: 120)
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
    
    @Test("ServerSong tracks media availability correctly")
    func testServerSongMediaAvailability() {
        let context = ModelContext(Self.testContainer)
        let serverSong = ServerSong(songId: "media_test", title: "Test", artist: "Artist", bpm: 120)
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
    
    @Test("ServerChart handles various difficulty levels")
    func testServerChartDifficultyLevels() {
        let context = ModelContext(Self.testContainer)
        let basicChart = ServerChart(difficulty: "easy", difficultyLabel: "BASIC", level: 10, filename: "bas.dtx", size: 300)
        context.insert(basicChart)
        let advancedChart = ServerChart(difficulty: "medium", difficultyLabel: "ADVANCED", level: 50, filename: "adv.dtx", size: 600)
        context.insert(advancedChart)
        let extremeChart = ServerChart(difficulty: "hard", difficultyLabel: "EXTREME", level: 80, filename: "ext.dtx", size: 900)
        context.insert(extremeChart)
        let masterChart = ServerChart(difficulty: "expert", difficultyLabel: "MASTER", level: 95, filename: "mas.dtx", size: 1200)
        context.insert(masterChart)
        
        #expect(basicChart.level == 10)
        #expect(advancedChart.level == 50)
        #expect(extremeChart.level == 80)
        #expect(masterChart.level == 95)
    }
    
    @Test("ServerChart handles various file sizes")
    func testServerChartFileSizes() {
        let context = ModelContext(Self.testContainer)
        let smallChart = ServerChart(difficulty: "easy", difficultyLabel: "BASIC", level: 20, filename: "small.dtx", size: 100)
        context.insert(smallChart)
        let mediumChart = ServerChart(difficulty: "medium", difficultyLabel: "ADVANCED", level: 50, filename: "medium.dtx", size: 1000)
        context.insert(mediumChart)
        let largeChart = ServerChart(difficulty: "hard", difficultyLabel: "EXTREME", level: 80, filename: "large.dtx", size: 10000)
        context.insert(largeChart)
        
        #expect(smallChart.size == 100)
        #expect(mediumChart.size == 1000)
        #expect(largeChart.size == 10000)
    }
    
    @Test("ServerSong lastUpdated is set correctly")
    func testServerSongLastUpdated() {
        let context = ModelContext(Self.testContainer)
        let beforeCreation = Date()
        let serverSong = ServerSong(songId: "time_test", title: "Test", artist: "Artist", bpm: 120)
        context.insert(serverSong)
        let afterCreation = Date()
        
        #expect(serverSong.lastUpdated >= beforeCreation)
        #expect(serverSong.lastUpdated <= afterCreation)
    }
    
    @Test("ServerSong song ID extraction from filename")
    func testServerSongIDExtraction() {
        let context = ModelContext(Self.testContainer)
        let serverSong = ServerSong(
            filename: "test_song_with_spaces.dtx",
            title: "Test Song",
            artist: "Artist",
            bpm: 120,
            difficultyLevel: 50,
            size: 1000
        )
        context.insert(serverSong)
        
        #expect(serverSong.songId == "test_song_with_spaces")
    }
    
    @Test("ServerChart filename validation")
    func testServerChartFilenames() {
        let context = ModelContext(Self.testContainer)
        let dtxChart = ServerChart(difficulty: "medium", difficultyLabel: "ADVANCED", level: 50, filename: "song.dtx", size: 1000)
        context.insert(dtxChart)
        let alternativeChart = ServerChart(difficulty: "hard", difficultyLabel: "EXTREME", level: 75, filename: "alternative_file.dtx", size: 1500)
        context.insert(alternativeChart)
        
        #expect(dtxChart.filename.hasSuffix(".dtx"))
        #expect(alternativeChart.filename.hasSuffix(".dtx"))
        #expect(dtxChart.filename == "song.dtx")
        #expect(alternativeChart.filename == "alternative_file.dtx")
    }
}
