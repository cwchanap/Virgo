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

    @Test func testParseEighthNotes() throws {
        // Test eighth-grid chips: #00211: 0I0J0I0J0I0J0I0J
        let eighthNoteLine = "#00211: 0I0J0I0J0I0J0I0J"
        let eighthNotes = try DTXFileParser.parseNoteLine(eighthNoteLine)

        #expect(eighthNotes.count == 8)
        #expect(eighthNotes[0].totalPositions == 8)
        #expect(eighthNotes[0].gridSize == 8)
        #expect(eighthNotes[0].gridPosition == 0)
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
        #expect(dtxNote.measureOffset == 0.5)
    }

    @Test func testDTXLaneMapping() throws {
        #expect(DTXLane.bd.noteType == .bass)
        #expect(DTXLane.lb.noteType == .bass)
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
        #00212: 0I0J0I0J0I0J0I0J
        
        ; Measure 3 - Hi-hat pattern
        #00311: 01000100
        
        ; Measure 4 - Crash cymbal (lane 16)
        #00416: 01000000
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
        #expect(measureNumbers.contains(1)) // DTX uses 1-based measures
        #expect(measureNumbers.contains(2))
        #expect(measureNumbers.contains(3))
        #expect(measureNumbers.contains(4))
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

    @Test func testParseDTXMetadataFromFileURL() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("virgo-dtx-\(UUID().uuidString)")
            .appendingPathExtension("dtx")

        let content = """
        #TITLE: File Song
        #ARTIST: File Artist
        #BPM: 128
        #DLEVEL: 35
        #00113: 01000000
        """

        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let chartData = try DTXFileParser.parseChartMetadata(from: fileURL)

        #expect(chartData.title == "File Song")
        #expect(chartData.artist == "File Artist")
        #expect(chartData.bpm == 128)
        #expect(chartData.difficultyLevel == 35)
        #expect(chartData.notes.count == 1)
    }

    @Test func testParseDTXMetadataMissingFileURLThrows() {
        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-\(UUID().uuidString)")
            .appendingPathExtension("dtx")

        do {
            _ = try DTXFileParser.parseChartMetadata(from: missingURL)
            Issue.record("Expected parseChartMetadata(from:) to throw fileNotFound")
        } catch DTXParseError.fileNotFound {
            // Expected path
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func testParseDTXMissingRequiredFields() {
        let testCases: [(content: String, field: String)] = [
            (
                """
                #TITLE: Missing Artist
                #BPM: 120
                #DLEVEL: 50
                """,
                "ARTIST"
            ),
            (
                """
                #TITLE: Missing BPM
                #ARTIST: Test Artist
                #DLEVEL: 50
                """,
                "BPM"
            ),
            (
                """
                #TITLE: Missing Level
                #ARTIST: Test Artist
                #BPM: 120
                """,
                "DLEVEL"
            )
        ]

        for testCase in testCases {
            do {
                _ = try DTXFileParser.parseChartMetadata(from: testCase.content)
                Issue.record("Expected missing required field error for \(testCase.field)")
            } catch DTXParseError.missingRequiredField(let field) {
                #expect(field == testCase.field)
            } catch {
                Issue.record("Unexpected error for \(testCase.field): \(error)")
            }
        }
    }

    @Test func testParseNoteLineRejectsMalformedInput() throws {
        let malformedLines = [
            "invalid",
            "#0013: 01",
            "#00A13: 0101",
            "#00113: 010",
            "#00113:"
        ]

        for line in malformedLines {
            let notes = try DTXFileParser.parseNoteLine(line)
            #expect(notes.isEmpty)
        }
    }

    // MARK: - Control Event Parsing

    @Test("header absent produces no control events even with lane-22 chips")
    func controlEventsEmptyWithoutHeader() throws {
        let dtx = """
        #TITLE: No Control
        #ARTIST: Tester
        #BPM: 120
        #DLEVEL: 50
        #00022: 16000000
        """
        let data = try DTXFileParser.parseChartMetadata(from: dtx)
        let chart = Chart(difficulty: .medium)
        #expect(data.controlLaneKinds.isEmpty)
        #expect(data.toControlEvents(for: chart).isEmpty)
    }

    @Test("guitar-channel chips on lane 22 are ignored without VIRGO_CONTROL header")
    func guitarChannelsIgnoredWithoutHeader() throws {
        let dtx = """
        #TITLE: Guitar Song
        #ARTIST: Tester
        #BPM: 120
        #DLEVEL: 50
        #00022: 0A0B0C0D
        """
        let data = try DTXFileParser.parseChartMetadata(from: dtx)
        let chart = Chart(difficulty: .medium)
        #expect(data.toControlEvents(for: chart).isEmpty)
    }

    @Test("header present parses stop chip targeting crash lane 16")
    func controlEventsParseStopChip() throws {
        let dtx = """
        #TITLE: Stop Test
        #ARTIST: Tester
        #BPM: 120
        #DLEVEL: 50
        #VIRGO_CONTROL: 1
        #00021: 16000000
        """
        let data = try DTXFileParser.parseChartMetadata(from: dtx)
        let chart = Chart(difficulty: .medium)
        let controls = data.toControlEvents(for: chart)

        #expect(controls.count == 1)
        let control = try #require(controls.first)
        #expect(control.kind == .stop)
        #expect(control.targetLaneID == "16")
        #expect(control.measureNumber == 1)
        #expect(control.originKind == .dtx)
        #expect(control.sourceLaneID == "21")
        #expect(control.sourceNoteID == "16")
        #expect(control.sourceGridPosition == 0)
        #expect(control.sourceGridSize == 4)
        #expect(control.normalizedMeasureIndex == 0)
        #expect(control.normalizedTickWithinMeasure == 0)
        #expect(control.normalizedTicksPerMeasure == 4)
        #expect(control.normalizedAbsoluteTick == 0)
        #expect(control.chart === chart)
    }

    @Test("choke and damp chips produce correct kinds")
    func controlEventsParseChokeAndDamp() throws {
        let dtx = """
        #TITLE: Choke Damp
        #ARTIST: Tester
        #BPM: 120
        #DLEVEL: 50
        #VIRGO_CONTROL: 1
        #00022: 16000000
        #00023: 12000000
        """
        let data = try DTXFileParser.parseChartMetadata(from: dtx)
        let chart = Chart(difficulty: .medium)
        let controls = data.toControlEvents(for: chart)

        #expect(controls.count == 2)
        #expect(controls.contains { $0.kind == .choke && $0.targetLaneID == "16" })
        #expect(controls.contains { $0.kind == .damp && $0.targetLaneID == "12" })
    }

    @Test("control chips are excluded from toNotes and playable chips from toControlEvents")
    func bidirectionalExclusion() throws {
        let dtx = """
        #TITLE: Mixed
        #ARTIST: Tester
        #BPM: 120
        #DLEVEL: 50
        #VIRGO_CONTROL: 1
        #00012: 01000000
        #00022: 16000000
        """
        let data = try DTXFileParser.parseChartMetadata(from: dtx)
        let chart = Chart(difficulty: .medium)

        let notes = data.toNotes(for: chart)
        let controls = data.toControlEvents(for: chart)

        #expect(notes.count == 1)
        #expect(notes.first?.noteType == .snare)
        #expect(controls.count == 1)
        #expect(controls.first?.kind == .choke)
    }

    @Test("incommensurate control chip is preserved with native grid tuple")
    func incommensurateControlPreserved() throws {
        let dtx = """
        #TITLE: Seven Grid
        #ARTIST: Tester
        #BPM: 120
        #DLEVEL: 50
        #VIRGO_CONTROL: 1
        #00021: 00010000000000
        """
        let data = try DTXFileParser.parseChartMetadata(from: dtx)
        let chart = Chart(difficulty: .medium)
        let controls = data.toControlEvents(for: chart)

        #expect(controls.count == 1)
        let control = try #require(controls.first)
        #expect(control.normalizedTicksPerMeasure == 7)
        #expect(control.normalizedTickWithinMeasure == 1)
        #expect(control.normalizedAbsoluteTick == 1)
    }

    @Test("malformed chip with zero grid size is skipped without crash")
    func malformedChipSkipped() {
        let chart = Chart(difficulty: .medium)
        let data = DTXChartData(
            title: "T", artist: "A", bpm: 120, difficultyLevel: 50,
            notes: [DTXNote(measureNumber: 0, laneID: "22", noteID: "16", notePosition: 0, totalPositions: 0)],
            controlLaneKinds: ["22": .choke]
        )
        #expect(data.toControlEvents(for: chart).isEmpty)
    }

    @Test("DTXChartData initializer without controlLaneKinds defaults to empty")
    func initializerDefaultsControlLaneKinds() {
        let data = DTXChartData(
            title: "T",
            artist: "A",
            bpm: 120,
            difficultyLevel: 50
        )
        #expect(data.controlLaneKinds.isEmpty)
    }
}
