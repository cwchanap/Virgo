//
//  DTXNormalizationTests.swift
//  VirgoTests
//
//  Normalization-specific DTX parser coverage split from DTXFileParserTests.
//

import Testing
import Foundation
@testable import Virgo

@Suite("DTX Normalization")
struct DTXNormalizationTests {

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
        // `.some(.none)` = non-nil Optional wrapping `NormalizedArticulation.none` (no articulation),
        // distinct from `Optional.none` (nil). Written explicitly to document the enum-case/Optional
        // name collision rather than relying on implicit conversion.
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
        let sparseBassChip = String(repeating: "00", count: 31) + "01"
        let dtxContent = """
        #TITLE: Sparse High Resolution
        #ARTIST: Tester
        #BPM: 120
        #DLEVEL: 50
        #00113: \(sparseBassChip)
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

    @Test("NormalizedRhythmicEvent rejects tick scales that are not multiples of the chip grid")
    func testNormalizedRhythmicEventRejectsNonMultipleTickScale() throws {
        let chip = DTXNote(measureNumber: 1, laneID: "11", noteID: "01", notePosition: 1, totalPositions: 4)

        // 6 is not a multiple of 4 -> would silently truncate tickScale to 1, corrupting ticks.
        #expect(NormalizedRhythmicEvent(
            chip: chip,
            ticksPerMeasure: 6,
            visualDurationCandidate: .quarter
        ) == nil)

        // 8 is a valid multiple of 4 -> tickScale = 2, ticks preserved exactly.
        let valid = try #require(NormalizedRhythmicEvent(
            chip: chip,
            ticksPerMeasure: 8,
            visualDurationCandidate: .quarter
        ))
        #expect(valid.tickWithinMeasure == 2)
        #expect(valid.ticksPerMeasure == 8)
    }
}
