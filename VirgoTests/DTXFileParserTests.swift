//
//  DTXFileParserTests.swift
//  VirgoTests
//
//  Created by Claude Code on 21/7/2025.
//

import Testing
import Foundation
@testable import Virgo

struct DTXFileParserTests {
    
    @Test func testParseDTXMetadata() throws {
        let sampleDTXContent = """
        ; Created by DTXCreator 025(verK)

        #TITLE: 休暇列車の窓辺で
        #ARTIST: hapadona feat. Suno AI
        #PREVIEW: preview.mp3
        #PREIMAGE: preview.jpg
        #STAGEFILE: preview.jpg
        #BPM: 200
        #DLEVEL: 74
        """
        
        let chartData = try DTXFileParser.parseChartMetadata(from: sampleDTXContent)
        
        #expect(chartData.title == "休暇列車の窓辺で")
        #expect(chartData.artist == "hapadona feat. Suno AI")
        #expect(chartData.bpm == 200)
        #expect(chartData.difficultyLevel == 74)
        #expect(chartData.toDifficulty() == .expert)
        #expect(chartData.preview == "preview.mp3")
        #expect(chartData.previewImage == "preview.jpg")
        #expect(chartData.stageFile == "preview.jpg")
    }
    
    @Test func testParseDTXMetadataMinimal() throws {
        let minimalDTXContent = """
        #TITLE: Test Song
        #ARTIST: Test Artist
        #BPM: 120
        #DLEVEL: 50
        """
        
        let chartData = try DTXFileParser.parseChartMetadata(from: minimalDTXContent)
        
        #expect(chartData.title == "Test Song")
        #expect(chartData.artist == "Test Artist")
        #expect(chartData.bpm == 120)
        #expect(chartData.difficultyLevel == 50)
        #expect(chartData.preview == nil)
        #expect(chartData.previewImage == nil)
        #expect(chartData.stageFile == nil)
    }
    
    @Test func testParseDTXMissingTitle() throws {
        let invalidDTXContent = """
        #ARTIST: Test Artist
        #BPM: 120
        #DLEVEL: 50
        """
        
        do {
            _ = try DTXFileParser.parseChartMetadata(from: invalidDTXContent)
            #expect(Bool(false), "Should throw missing required field error")
        } catch DTXParseError.missingRequiredField(let field) {
            #expect(field == "TITLE")
        }
    }
    
    @Test func testParseDTXInvalidBPM() throws {
        let invalidDTXContent = """
        #TITLE: Test Song
        #ARTIST: Test Artist
        #BPM: invalid
        #DLEVEL: 50
        """
        
        do {
            _ = try DTXFileParser.parseChartMetadata(from: invalidDTXContent)
            #expect(Bool(false), "Should throw invalid BPM error")
        } catch DTXParseError.invalidBPM {
            // Expected error
        }
    }
    
    @Test func testParseDTXInvalidDifficultyLevel() throws {
        let invalidDTXContent = """
        #TITLE: Test Song
        #ARTIST: Test Artist
        #BPM: 120
        #DLEVEL: invalid
        """
        
        do {
            _ = try DTXFileParser.parseChartMetadata(from: invalidDTXContent)
            #expect(Bool(false), "Should throw invalid difficulty level error")
        } catch DTXParseError.invalidDifficultyLevel {
            // Expected error
        }
    }
    
    @Test func testDifficultyConversion() throws {
        let testCases: [(Int, Difficulty)] = [
            (10, .easy),
            (40, .medium),
            (60, .hard),
            (80, .expert),
            (150, .medium) // Default fallback
        ]
        
        for (level, expectedDifficulty) in testCases {
            let chartData = DTXChartData(
                title: "Test",
                artist: "Test",
                bpm: 120,
                difficultyLevel: level
            )
            #expect(chartData.toDifficulty() == expectedDifficulty)
        }
    }
    
    @Test func testTimeSignatureConversion() throws {
        let chartData = DTXChartData(
            title: "Test",
            artist: "Test",
            bpm: 120,
            difficultyLevel: 50
        )
        #expect(chartData.toTimeSignature() == .fourFour)
    }
    
    @Test func testActualDTXFile() throws {
        let dtxPath = "/Users/chanwaichan/Documents (Local)/Test DTX/Kyuuka ressha no madobe de/mas.dtx"
        let url = URL(fileURLWithPath: dtxPath)
        
        guard FileManager.default.fileExists(atPath: dtxPath) else {
            // Skip test if file doesn't exist in CI or other environments
            return
        }
        
        let chartData = try DTXFileParser.parseChartMetadata(from: url)
        
        #expect(chartData.title == "休暇列車の窓辺で")
        #expect(chartData.artist == "hapadona feat. Suno AI")
        #expect(chartData.bpm == 200)
        #expect(chartData.difficultyLevel == 74)
        #expect(chartData.toDifficulty() == .expert)
    }
}