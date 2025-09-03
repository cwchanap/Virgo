//
//  ServerChartModelTests.swift
//  VirgoTests
//
//  Created by Claude Code on 26/8/2025.
//

import Testing
import Foundation
import SwiftData
@testable import Virgo

@Suite("Server Chart Model Tests", .serialized)
@MainActor
struct ServerChartModelTests {
    
    @Test("ServerChart initializes with correct properties")
    func testServerChartInitialization() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
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
    }
    
    @Test("ServerChart can be created with server song reference")
    func testServerChartWithServerSong() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let serverSong = ServerSong(songId: "test_song", title: "Test", artist: "Artist", bpm: 120.0)
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
    }
    
    @Test("ServerChart handles various difficulty levels")
    func testServerChartDifficultyLevels() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let basicChart = ServerChart(
                difficulty: "easy", difficultyLabel: "BASIC", level: 10, filename: "bas.dtx", size: 300
            )
            context.insert(basicChart)
            let advancedChart = ServerChart(
                difficulty: "medium", difficultyLabel: "ADVANCED", level: 50, filename: "adv.dtx", size: 600
            )
            context.insert(advancedChart)
            let extremeChart = ServerChart(
                difficulty: "hard", difficultyLabel: "EXTREME", level: 80, filename: "ext.dtx", size: 900
            )
            context.insert(extremeChart)
            let expertChart = ServerChart(
                difficulty: "expert", difficultyLabel: "MASTER", level: 95, filename: "mas.dtx", size: 1200
            )
            context.insert(expertChart)
            
            #expect(basicChart.level == 10)
            #expect(advancedChart.level == 50)
            #expect(extremeChart.level == 80)
            #expect(expertChart.level == 95)
        }
    }
    
    @Test("ServerChart handles various file sizes")
    func testServerChartFileSizes() async throws {
        // Add controlled delay for better test isolation 
        try await Task.sleep(nanoseconds: 250_000_000) // 250ms
        
        try await TestSetup.withTestSetup {
            
            let context = TestContainer.shared.context
            let smallChart = ServerChart(
                difficulty: "easy", difficultyLabel: "BASIC", level: 20, filename: "small.dtx", size: 100
            )
            context.insert(smallChart)
            let mediumChart = ServerChart(
                difficulty: "medium", difficultyLabel: "ADVANCED", level: 50, filename: "medium.dtx", size: 1000
            )
            context.insert(mediumChart)
            let largeChart = ServerChart(
                difficulty: "hard", difficultyLabel: "EXTREME", level: 80, filename: "large.dtx", size: 10000
            )
            context.insert(largeChart)
            
            #expect(smallChart.size == 100)
            #expect(mediumChart.size == 1000)
            #expect(largeChart.size == 10000)
        }
    }
    
    @Test("ServerChart filename validation")
    func testServerChartFilenames() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let dtxChart = ServerChart(
                difficulty: "medium", difficultyLabel: "ADVANCED", level: 50, filename: "song.dtx", size: 1000
            )
            context.insert(dtxChart)
            let alternativeChart = ServerChart(
                difficulty: "hard", difficultyLabel: "EXTREME", level: 75, filename: "alternative_file.dtx", size: 1500
            )
            context.insert(alternativeChart)
            
            #expect(dtxChart.filename.hasSuffix(".dtx"))
            #expect(alternativeChart.filename.hasSuffix(".dtx"))
            #expect(dtxChart.filename == "song.dtx")
            #expect(alternativeChart.filename == "alternative_file.dtx")
        }
    }
}
