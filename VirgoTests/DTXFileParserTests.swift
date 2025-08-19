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

    @Test func testParseNoteLine() throws {
        // Test quarter note parsing: #00113: 01010101
        let quarterNoteLine = "#00113: 01010101"
        let quarterNotes = try DTXFileParser.parseNoteLine(quarterNoteLine)

        #expect(quarterNotes.count == 4)
        for (index, note) in quarterNotes.enumerated() {
            #expect(note.measureNumber == 1)
            #expect(note.laneID == "13") // Bass drum
            #expect(note.noteID == "01")
            #expect(note.notePosition == index)
            #expect(note.totalPositions == 4)
            #expect(note.measureOffset == Double(index) / 4.0)
        }
    }

    @Test func testParseNoteLineWithGaps() throws {
        // Test with gaps: #00112: 00050005
        let gapNoteLine = "#00112: 00050005"
        let gapNotes = try DTXFileParser.parseNoteLine(gapNoteLine)

        #expect(gapNotes.count == 2) // Only non-00 notes
        #expect(gapNotes[0].notePosition == 1)
        #expect(gapNotes[0].measureOffset == 0.25)
        #expect(gapNotes[1].notePosition == 3)
        #expect(gapNotes[1].measureOffset == 0.75)
    }

    @Test func testParseEighthNotes() throws {
        // Test eighth notes: #00211: 0I0J0I0J0I0J0I0J
        let eighthNoteLine = "#00211: 0I0J0I0J0I0J0I0J"
        let eighthNotes = try DTXFileParser.parseNoteLine(eighthNoteLine)

        #expect(eighthNotes.count == 8)
        #expect(eighthNotes[0].totalPositions == 8)
        #expect(eighthNotes[0].toNoteInterval() == .eighth)
    }

    @Test func testDTXNoteConversion() throws {
        let dtxNote = DTXNote(
            measureNumber: 0,
            laneID: "13", // Bass drum
            noteID: "01",
            notePosition: 2,
            totalPositions: 4
        )

        #expect(dtxNote.toNoteType() == .bass)
        #expect(dtxNote.toNoteInterval() == .quarter)
        #expect(dtxNote.measureOffset == 0.5)
    }

    @Test func testDTXLaneMapping() throws {
        #expect(DTXLane.bd.noteType == .bass)
        #expect(DTXLane.sn.noteType == .snare)
        #expect(DTXLane.hhc.noteType == .hiHat)
        #expect(DTXLane.hh.noteType == .openHiHat)
        #expect(DTXLane.cy.noteType == .crash)
        #expect(DTXLane.rd.noteType == .ride)
        #expect(DTXLane.ht.noteType == .highTom)
        #expect(DTXLane.lt.noteType == .midTom)
        #expect(DTXLane.ft.noteType == .lowTom)

        // Non-playable lanes
        #expect(DTXLane.bpm.noteType == nil)
        #expect(DTXLane.bgm.noteType == nil)
    }

    @Test func testComplexDTXContent() throws {
        // Use embedded test data instead of external files
        let complexDTXContent = """
        ; DTXCreator test file
        
        #TITLE: 休暇列車の窓辺で
        #ARTIST: hapadona feat. Suno AI
        #PREVIEW: preview.mp3
        #PREIMAGE: preview.jpg
        #STAGEFILE: preview.jpg
        #BPM: 200
        #DLEVEL: 74
        
        ; Measure 1 - Quarter notes on bass drum
        #00113: 01010101
        
        ; Measure 2 - Eighth notes on snare
        #00112: 0I0J0I0J0I0J0I0J
        
        ; Measure 3 - Hi-hat pattern
        #00111: 01000100
        
        ; Measure 4 - Crash cymbal
        #00118: 01000000
        """

        let chartData = try DTXFileParser.parseChartMetadata(from: complexDTXContent)

        #expect(chartData.title == "休暇列車の窓辺で")
        #expect(chartData.artist == "hapadona feat. Suno AI")
        #expect(chartData.bpm == 200)
        #expect(chartData.difficultyLevel == 74)
        #expect(chartData.toDifficulty() == .expert)

        // Verify notes were parsed
        #expect(!chartData.notes.isEmpty)

        // Check for expected note types from the patterns
        let noteTypes = Set(chartData.notes.compactMap { $0.toNoteType() })
        #expect(noteTypes.contains(NoteType.bass))
        #expect(noteTypes.contains(NoteType.snare))
        #expect(noteTypes.contains(NoteType.hiHat))
        #expect(noteTypes.contains(NoteType.crash))
        
        // Verify measure distribution
        let measureNumbers = Set(chartData.notes.map { $0.measureNumber })
        #expect(measureNumbers.contains(0)) // DTX uses 0-based measures
        #expect(measureNumbers.contains(1))
        #expect(measureNumbers.contains(2))
        #expect(measureNumbers.contains(3))
    }
    
    @Test func testDTXFileWithMissingOptionalFields() throws {
        // Test DTX content with only required fields
        let minimalDTXContent = """
        #TITLE: Minimal Song
        #ARTIST: Test Artist
        #BPM: 120
        #DLEVEL: 45
        
        ; Simple pattern
        #00113: 01000000
        """

        let chartData = try DTXFileParser.parseChartMetadata(from: minimalDTXContent)

        #expect(chartData.title == "Minimal Song")
        #expect(chartData.artist == "Test Artist")
        #expect(chartData.bpm == 120)
        #expect(chartData.difficultyLevel == 45)
        #expect(chartData.preview == nil)
        #expect(chartData.previewImage == nil)
        #expect(chartData.stageFile == nil)
        
        // Should still have parsed the note
        #expect(!chartData.notes.isEmpty)
        #expect(chartData.notes.first?.toNoteType() == .bass)
    }
}
