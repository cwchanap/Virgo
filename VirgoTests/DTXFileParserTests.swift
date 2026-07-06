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

    @Test("parseChartMetadata records BGM lane start position")
    func testParseChartMetadataRecordsBGMLaneStartPosition() throws {
        let dtxContent = """
        #TITLE: BGM Offset
        #ARTIST: Tester
        #BPM: 200
        #DLEVEL: 74
        #00001: 0000001A
        #00113: 0000000000010000
        """

        let chartData = try DTXFileParser.parseChartMetadata(from: dtxContent)

        #expect(chartData.bgmStartTimePosition == 0.75)
        let bgmOffset = try #require(chartData.bgmStartOffsetSeconds)
        #expect(abs(bgmOffset - 0.9) < 0.001)
    }

    @Test("parseChartMetadata: BGM lane at position zero yields a 0.0 offset, not nil")
    func testParseChartMetadataBGMLaneAtZeroYieldsZeroOffset() throws {
        // `#00001: 1A…` places the BGM chip at the very first position of measure 0,
        // i.e. "audio starts immediately". This must parse to `0.0`, which is
        // distinct from `nil` (no BGM lane at all) so downstream code can honor it.
        let dtxContent = """
        #TITLE: BGM At Zero
        #ARTIST: Tester
        #BPM: 200
        #DLEVEL: 74
        #00001: 1A
        #00113: 0001
        """

        let chartData = try DTXFileParser.parseChartMetadata(from: dtxContent)

        #expect(chartData.bgmStartTimePosition == 0.0)
        let bgmOffset = try #require(chartData.bgmStartOffsetSeconds)
        #expect(bgmOffset == 0.0)
    }

    @Test("parseChartMetadata: no BGM lane yields a nil offset")
    func testParseChartMetadataNoBGMLaneYieldsNilOffset() throws {
        // Charts without any lane-01 notes have no authoritative BGM offset;
        // the parser must surface `nil` so the caller can fall back to a heuristic.
        let dtxContent = """
        #TITLE: No BGM
        #ARTIST: Tester
        #BPM: 200
        #DLEVEL: 74
        #00113: 0001
        """

        let chartData = try DTXFileParser.parseChartMetadata(from: dtxContent)

        #expect(chartData.bgmStartTimePosition == nil)
        #expect(chartData.bgmStartOffsetSeconds == nil)
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
        #expect(dtxNote.toNoteInterval() == .quarter)
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

    @Test("lane 1C imports as bass and preserves DTX source identity")
    func testLane1CImportsAsBassWithSourceIdentity() throws {
        let dtxContent = """
        #TITLE: Left Bass
        #ARTIST: Tester
        #BPM: 120
        #DLEVEL: 50
        #0011C: 000A0000
        """

        let chartData = try DTXFileParser.parseChartMetadata(from: dtxContent)
        let rawChip = try #require(chartData.notes.first)
        #expect(rawChip.laneID == "1C")
        #expect(rawChip.noteID == "0A")
        #expect(rawChip.measureIndex == 1)
        #expect(rawChip.gridPosition == 1)
        #expect(rawChip.gridSize == 4)
        #expect(rawChip.toNoteType() == .bass)

        let chart = Chart(difficulty: .medium)
        let note = try #require(chartData.toNotes(for: chart).first)

        #expect(note.noteType == .bass)
        #expect(note.originKind == .dtx)
        #expect(note.sourceLaneID == "1C")
        #expect(note.sourceNoteID == "0A")
        #expect(note.sourceGridPosition == 1)
        #expect(note.sourceGridSize == 4)
        #expect(note.normalizedMeasureIndex == 1)
        #expect(note.normalizedAbsoluteTick == 5)
        #expect(note.normalizedTickWithinMeasure == 1)
        #expect(note.normalizedTicksPerMeasure == 4)
        #expect(note.notationVoiceCandidate == .lower)
        #expect(note.visualDurationCandidate == .quarter)
        #expect(note.articulationCandidate == .some(.none))
    }

    @Test("normalized events use a shared chart-level tick scale across lane grids")
    func testNormalizedEventsUseSharedChartTickScale() throws {
        let dtxContent = """
        #TITLE: Shared Tick Scale
        #ARTIST: Tester
        #BPM: 120
        #DLEVEL: 50
        #00113: 0101
        #00112: 00000001
        """

        let chartData = try DTXFileParser.parseChartMetadata(from: dtxContent)
        let events = chartData.normalizedRhythmicEvents()

        #expect(events.count == 3)
        #expect(Set(events.map(\.ticksPerMeasure)) == Set([4]))
        #expect(events.map(\.absoluteTick).sorted() == [4, 6, 7])
        let tickSources = events.map { event in
            (laneID: event.laneID, gridPosition: event.gridPosition, absoluteTick: event.absoluteTick)
        }.sorted { $0.absoluteTick < $1.absoluteTick }
        #expect((tickSources[0].laneID, tickSources[0].gridPosition, tickSources[0].absoluteTick) == ("13", 0, 4))
        #expect((tickSources[1].laneID, tickSources[1].gridPosition, tickSources[1].absoluteTick) == ("13", 1, 6))
        #expect((tickSources[2].laneID, tickSources[2].gridPosition, tickSources[2].absoluteTick) == ("12", 3, 7))

        let snare = try #require(events.first { $0.laneID == "12" })
        #expect(snare.gridSize == 4)
        #expect(snare.gridPosition == 3)
        #expect(snare.tickWithinMeasure == 3)
        #expect(snare.visualDurationCandidate == .quarter)
    }

    @Test("power-of-two grids normalize to readable visual duration candidates", arguments: [
        (1, NoteInterval.full),
        (2, .half),
        (4, .quarter),
        (8, .eighth),
        (16, .sixteenth),
        (32, .thirtysecond),
        (64, .sixtyfourth)
    ])
    func testPowerOfTwoGridsNormalizeToReadableVisualCandidates(
        gridSize: Int,
        expectedInterval: NoteInterval
    ) throws {
        let chips = String(repeating: "01", count: gridSize)
        let dtxContent = """
        #TITLE: Power Of Two Grid
        #ARTIST: Tester
        #BPM: 120
        #DLEVEL: 50
        #00112: \(chips)
        """

        let chartData = try DTXFileParser.parseChartMetadata(from: dtxContent)
        let events = chartData.normalizedRhythmicEvents()

        #expect(events.count == gridSize)
        #expect(Set(events.map(\.ticksPerMeasure)) == Set([gridSize]))
        #expect(events.map(\.gridPosition) == Array(0..<gridSize))
        #expect(events.map(\.tickWithinMeasure) == Array(0..<gridSize))
        #expect(events.map(\.absoluteTick) == Array(gridSize..<(gridSize * 2)))
        #expect(events.map(\.visualDurationCandidate) == Array(repeating: expectedInterval, count: gridSize))

        let chart = Chart(difficulty: .medium)
        let notes = chartData.toNotes(for: chart)
        #expect(notes.count == gridSize)
        #expect(notes.map(\.interval) == Array(repeating: expectedInterval, count: gridSize))
        #expect(notes.map(\.visualDurationCandidate) == Array(repeating: .some(expectedInterval), count: gridSize))
    }

    @Test("non-power-of-two grids preserve timing and do not collapse every note to quarter")
    func testNonPowerOfTwoGridPreservesTicksAndVisualCandidate() throws {
        let dtxContent = """
        #TITLE: Triplet Grid
        #ARTIST: Tester
        #BPM: 120
        #DLEVEL: 50
        #00112: 010101000000000000000000
        """

        let chartData = try DTXFileParser.parseChartMetadata(from: dtxContent)
        let events = chartData.normalizedRhythmicEvents()

        #expect(events.count == 3)
        #expect(Set(events.map(\.ticksPerMeasure)) == Set([12]))
        #expect(events.map(\.tickWithinMeasure) == [0, 1, 2])
        #expect(events.map(\.absoluteTick) == [12, 13, 14])
        // Adjacent non-power-of-two spacing stays visually short; the trailing note can fall back to quarter.
        #expect(events.map(\.visualDurationCandidate) == [.sixteenth, .sixteenth, .quarter])

        let chart = Chart(difficulty: .medium)
        let notes = chartData.toNotes(for: chart)
        #expect(notes.count == 3)
        #expect(notes.allSatisfy { $0.normalizedTicksPerMeasure == 12 })
        #expect(notes.map(\.visualDurationCandidate) == [.some(.sixteenth), .some(.sixteenth), .some(.quarter)])
        #expect(notes.map(\.interval) == [.sixteenth, .sixteenth, .quarter])
    }

    @Test("sparse high-resolution grid preserves timing without forcing visual 32nd notes")
    func testSparseHighResolutionGridKeepsTimingButReadableDuration() throws {
        let dtxContent = """
        #TITLE: Sparse High Resolution
        #ARTIST: Tester
        #BPM: 120
        #DLEVEL: 50
        #00113: 0000000000000000000000000000000000000000000000000000000000000001
        """

        let chartData = try DTXFileParser.parseChartMetadata(from: dtxContent)
        let events = chartData.normalizedRhythmicEvents()
        #expect(events.count == 1)
        let event = try #require(events.first)

        #expect(event.gridSize == 32)
        #expect(event.gridPosition == 31)
        #expect(event.ticksPerMeasure == 32)
        #expect(event.tickWithinMeasure == 31)
        #expect(event.absoluteTick == 63)
        #expect(event.visualDurationCandidate == .quarter)

        let chart = Chart(difficulty: .medium)
        let notes = chartData.toNotes(for: chart)
        #expect(notes.count == 1)
        let note = try #require(notes.first)
        #expect(note.normalizedTicksPerMeasure == 32)
        #expect(note.normalizedTickWithinMeasure == 31)
        #expect(note.interval == .quarter)
        #expect(note.visualDurationCandidate == .quarter)
    }

    @Test("visual duration candidates use the next chip across measure boundaries")
    func testVisualDurationCandidatesUseNextMeasureChip() throws {
        let finalEighthChip = String(repeating: "00", count: 7) + "01"
        let nextMeasureChip = "01" + String(repeating: "00", count: 7)
        let dtxContent = """
        #TITLE: Measure Boundary Spacing
        #ARTIST: Tester
        #BPM: 120
        #DLEVEL: 50
        #00113: \(finalEighthChip)
        #00212: \(nextMeasureChip)
        """

        let chartData = try DTXFileParser.parseChartMetadata(from: dtxContent)
        let events = chartData.normalizedRhythmicEvents()

        let bass = try #require(events.first { $0.laneID == "13" })
        let snare = try #require(events.first { $0.laneID == "12" })
        #expect(bass.absoluteTick == 15)
        #expect(snare.absoluteTick == 16)
        #expect(bass.visualDurationCandidate == .eighth)

        let chart = Chart(difficulty: .medium)
        let notes = chartData.toNotes(for: chart)
        let bassNote = try #require(notes.first { $0.sourceLaneID == "13" })
        #expect(bassNote.interval == .eighth)
        #expect(bassNote.visualDurationCandidate == .eighth)
    }

    @Test("normalization rejects oversized shared tick scales")
    func testNormalizedEventsRejectOversizedSharedTickScale() throws {
        let chartData = DTXChartData(
            title: "Oversized Tick Scale",
            artist: "Tester",
            bpm: 120,
            difficultyLevel: 50,
            notes: [
                DTXNote(measureNumber: 1, laneID: "13", noteID: "01", notePosition: 0, totalPositions: 4_093),
                DTXNote(measureNumber: 1, laneID: "12", noteID: "01", notePosition: 0, totalPositions: 4_091)
            ]
        )

        #expect(chartData.normalizedRhythmicEvents().isEmpty)

        let chart = Chart(difficulty: .medium)
        #expect(chartData.toNotes(for: chart).isEmpty)
    }
}
