//
//  DTXNoteLineParsingTests.swift
//  VirgoTests
//
//  Note-line parsing and BGM offset extraction coverage split from DTXFileParserTests.
//

import Testing
import Foundation
@testable import Virgo

@Suite("DTX Note Line Parsing")
struct DTXNoteLineParsingTests {

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

    @Test("parseChartMetadata accepts lowercase hex lane IDs and note chips")
    func testParseChartMetadataAcceptsLowercaseHexLaneIDs() throws {
        // DTX files may use lowercase hex for lane IDs and chip values (e.g. `1c`).
        // `isNoteLine` must accept these so the chips are parsed (and uppercased)
        // rather than being silently treated as metadata and dropped.
        let dtxContent = """
        #TITLE: Lowercase Lanes
        #ARTIST: Tester
        #BPM: 200
        #DLEVEL: 74
        #0011c: 000a0000
        """

        let chartData = try DTXFileParser.parseChartMetadata(from: dtxContent)

        #expect(chartData.notes.count == 1)
        let note = try #require(chartData.notes.first)
        #expect(note.laneID == "1C")
        #expect(note.noteID == "0A")
        #expect(note.measureNumber == 1)
        #expect(note.notePosition == 1)
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
}
