//
//  ServerSongModelTests.swift
//  VirgoTests
//
//  Created by Claude Code on 19/8/2025.
//

import Testing
import Foundation
@testable import Virgo

@Suite("Server Song Model Tests")
struct ServerSongModelTests {
    
    @Test("ServerChart initializes with correct properties")
    func testServerChartInitialization() {
        let chart = ServerChart(
            difficulty: "medium",
            difficultyLabel: "ADVANCED",
            level: 60,
            filename: "adv.dtx",
            size: 1024
        )
        
        #expect(chart.difficulty == "medium")
        #expect(chart.difficultyLabel == "ADVANCED")
        #expect(chart.level == 60)
        #expect(chart.filename == "adv.dtx")
        #expect(chart.size == 1024)
        #expect(chart.serverSong == nil)
    }
    
    @Test("ServerChart can be created with server song reference")
    func testServerChartWithServerSong() {
        let serverSong = ServerSong(songId: "test_song", title: "Test", artist: "Artist", bpm: 120)
        let chart = ServerChart(
            difficulty: "easy",
            difficultyLabel: "BASIC",
            level: 30,
            filename: "bas.dtx",
            size: 512,
            serverSong: serverSong
        )
        
        #expect(chart.serverSong === serverSong)
    }
    
    @Test("ServerSong initializes with default values")
    func testServerSongDefaultInitialization() {
        let serverSong = ServerSong(
            songId: "test_song_001",
            title: "Test Song",
            artist: "Test Artist",
            bpm: 140.0
        )
        
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
        let charts = [
            ServerChart(difficulty: "easy", difficultyLabel: "BASIC", level: 25, filename: "bas.dtx", size: 400),
            ServerChart(difficulty: "hard", difficultyLabel: "EXTREME", level: 85, filename: "ext.dtx", size: 1200)
        ]
        
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
        
        #expect(serverSong.charts.count == 2)
        #expect(serverSong.isDownloaded == true)
        #expect(serverSong.hasBGM == true)
        #expect(serverSong.bgmDownloaded == true)
        #expect(serverSong.hasPreview == true)
        #expect(serverSong.previewDownloaded == false)
    }
    
    @Test("ServerSong legacy convenience initializer works correctly")
    func testServerSongLegacyInitializer() {
        let serverSong = ServerSong(
            filename: "legacy_song.dtx",
            title: "Legacy Song",
            artist: "Legacy Artist",
            bpm: 130.0,
            difficultyLevel: 45,
            size: 800,
            isDownloaded: true
        )
        
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
        let slowSong = ServerSong(songId: "slow", title: "Slow", artist: "Artist", bpm: 60.0)
        let mediumSong = ServerSong(songId: "medium", title: "Medium", artist: "Artist", bpm: 120.0)
        let fastSong = ServerSong(songId: "fast", title: "Fast", artist: "Artist", bpm: 200.0)
        
        #expect(slowSong.bpm == 60.0)
        #expect(mediumSong.bpm == 120.0)
        #expect(fastSong.bpm == 200.0)
    }
    
    @Test("ServerSong tracks download status correctly")
    func testServerSongDownloadStatus() {
        let serverSong = ServerSong(songId: "download_test", title: "Test", artist: "Artist", bpm: 120)
        
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
        let serverSong = ServerSong(songId: "media_test", title: "Test", artist: "Artist", bpm: 120)
        
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
        let basicChart = ServerChart(difficulty: "easy", difficultyLabel: "BASIC", level: 10, filename: "bas.dtx", size: 300)
        let advancedChart = ServerChart(difficulty: "medium", difficultyLabel: "ADVANCED", level: 50, filename: "adv.dtx", size: 600)
        let extremeChart = ServerChart(difficulty: "hard", difficultyLabel: "EXTREME", level: 80, filename: "ext.dtx", size: 900)
        let masterChart = ServerChart(difficulty: "expert", difficultyLabel: "MASTER", level: 95, filename: "mas.dtx", size: 1200)
        
        #expect(basicChart.level == 10)
        #expect(advancedChart.level == 50)
        #expect(extremeChart.level == 80)
        #expect(masterChart.level == 95)
    }
    
    @Test("ServerChart handles various file sizes")
    func testServerChartFileSizes() {
        let smallChart = ServerChart(difficulty: "easy", difficultyLabel: "BASIC", level: 20, filename: "small.dtx", size: 100)
        let mediumChart = ServerChart(difficulty: "medium", difficultyLabel: "ADVANCED", level: 50, filename: "medium.dtx", size: 1000)
        let largeChart = ServerChart(difficulty: "hard", difficultyLabel: "EXTREME", level: 80, filename: "large.dtx", size: 10000)
        
        #expect(smallChart.size == 100)
        #expect(mediumChart.size == 1000)
        #expect(largeChart.size == 10000)
    }
    
    @Test("ServerSong lastUpdated is set correctly")
    func testServerSongLastUpdated() {
        let beforeCreation = Date()
        let serverSong = ServerSong(songId: "time_test", title: "Test", artist: "Artist", bpm: 120)
        let afterCreation = Date()
        
        #expect(serverSong.lastUpdated >= beforeCreation)
        #expect(serverSong.lastUpdated <= afterCreation)
    }
    
    @Test("ServerSong song ID extraction from filename")
    func testServerSongIDExtraction() {
        let serverSong = ServerSong(
            filename: "test_song_with_spaces.dtx",
            title: "Test Song",
            artist: "Artist",
            bpm: 120,
            difficultyLevel: 50,
            size: 1000
        )
        
        #expect(serverSong.songId == "test_song_with_spaces")
    }
    
    @Test("ServerChart filename validation")
    func testServerChartFilenames() {
        let dtxChart = ServerChart(difficulty: "medium", difficultyLabel: "ADVANCED", level: 50, filename: "song.dtx", size: 1000)
        let alternativeChart = ServerChart(difficulty: "hard", difficultyLabel: "EXTREME", level: 75, filename: "alternative_file.dtx", size: 1500)
        
        #expect(dtxChart.filename.hasSuffix(".dtx"))
        #expect(alternativeChart.filename.hasSuffix(".dtx"))
        #expect(dtxChart.filename == "song.dtx")
        #expect(alternativeChart.filename == "alternative_file.dtx")
    }
}