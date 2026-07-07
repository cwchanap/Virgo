//
//  DTXFileParser.swift
//  Virgo
//
//  Created by Claude Code on 21/7/2025.
//

import Foundation
import SwiftData

struct DTXMetadata {
    var title: String?
    var artist: String?
    var bpm: Double?
    var difficultyLevel: Int?
    var preview: String?
    var previewImage: String?
    var stageFile: String?
}

enum DTXParseError: Error {
    case fileNotFound
    case invalidFormat
    case missingRequiredField(String)
    case invalidBPM
    case invalidDifficultyLevel
}

struct DTXNote {
    let measureNumber: Int
    let laneID: String
    let noteID: String
    let notePosition: Int // Position within the measure (0-based)
    let totalPositions: Int // Total number of positions in this measure

    var measureIndex: Int { measureNumber }
    var gridPosition: Int { notePosition }
    var gridSize: Int { totalPositions }

    var measureOffset: Double {
        guard totalPositions > 0 else { return 0.0 }
        return Double(notePosition) / Double(totalPositions)
    }
}

struct DTXChartData {
    let title: String
    let artist: String
    let bpm: Double
    let difficultyLevel: Int
    let preview: String?
    let previewImage: String?
    let stageFile: String?
    let notes: [DTXNote]
    let bgmStartTimePosition: Double?

    init(
        title: String,
        artist: String,
        bpm: Double,
        difficultyLevel: Int,
        preview: String? = nil,
        previewImage: String? = nil,
        stageFile: String? = nil,
        notes: [DTXNote] = [],
        bgmStartTimePosition: Double? = nil
    ) {
        self.title = title
        self.artist = artist
        self.bpm = bpm
        self.difficultyLevel = difficultyLevel
        self.preview = preview
        self.previewImage = previewImage
        self.stageFile = stageFile
        self.notes = notes
        self.bgmStartTimePosition = bgmStartTimePosition
    }

    /// `nil` when the chart has no BGM lane-01 notes (no authoritative offset).
    /// `0.0` when the chart explicitly starts BGM at time zero (e.g. `#00001: 1A…`).
    /// A positive value when BGM starts later. Returning `Double?` keeps these
    /// three cases distinct so downstream code does not have to use `> 0` as a
    /// presence sentinel (which would discard a legitimate "BGM starts now" 0.0).
    var bgmStartOffsetSeconds: Double? {
        guard let bgmStartTimePosition else { return nil }
        let secondsPerMeasure = 4.0 * 60.0 / bpm
        return bgmStartTimePosition * secondsPerMeasure
    }
}

struct NormalizedRhythmicEvent: Hashable {
    let measureIndex: Int
    let absoluteTick: Int
    let tickWithinMeasure: Int
    let ticksPerMeasure: Int
    let voiceCandidate: NormalizedNotationVoice
    let laneID: String
    let noteID: String
    let gridPosition: Int
    let gridSize: Int
    let noteType: NoteType
    let visualDurationCandidate: NoteInterval
    let articulationCandidate: NormalizedArticulation
    let measureOffset: Double

    init?(
        chip: DTXNote,
        ticksPerMeasure: Int,
        visualDurationCandidate: NoteInterval,
        articulationCandidate: NormalizedArticulation = .none
    ) {
        guard
            let noteType = chip.toNoteType(),
            chip.gridSize > 0,
            chip.gridPosition >= 0,
            chip.gridPosition < chip.gridSize,
            ticksPerMeasure > 0,
            ticksPerMeasure.isMultiple(of: chip.gridSize)
        else {
            return nil
        }

        let tickScale = ticksPerMeasure / chip.gridSize
        let tickWithinMeasure = chip.gridPosition * tickScale

        self.measureIndex = chip.measureIndex
        self.absoluteTick = chip.measureIndex * ticksPerMeasure + tickWithinMeasure
        self.tickWithinMeasure = tickWithinMeasure
        self.ticksPerMeasure = ticksPerMeasure
        self.voiceCandidate = Self.voiceCandidate(for: noteType)
        self.laneID = chip.laneID.uppercased()
        self.noteID = chip.noteID.uppercased()
        self.gridPosition = chip.gridPosition
        self.gridSize = chip.gridSize
        self.noteType = noteType
        self.visualDurationCandidate = visualDurationCandidate
        self.articulationCandidate = articulationCandidate
        self.measureOffset = chip.measureOffset
    }

    private static func voiceCandidate(for noteType: NoteType) -> NormalizedNotationVoice {
        switch DrumType.from(noteType: noteType) {
        case .some(.kick), .some(.hiHatPedal):
            return .lower
        case .some(.snare), .some(.hiHat), .some(.crash), .some(.ride),
             .some(.tom1), .some(.tom2), .some(.tom3), .some(.cowbell), .none:
            return .upper
        }
    }
}

enum DTXLane: String, CaseIterable {
    case bpm = "08"     // BPM changes (not playable)
    case lc = "1A"      // Left Crash
    case hh = "18"      // Hi-Hat Open
    case hhc = "11"     // Hi-Hat Closed
    case lp = "1B"      // Left Pedal
    case lb = "1C"      // Left Bass (foot pedal)
    case sn = "12"      // Snare
    case ht = "14"      // High Tom
    case bd = "13"      // Bass Drum
    case lt = "15"      // Low Tom
    case ft = "17"      // Floor Tom
    case cy = "16"      // Crash Cymbal
    case rd = "19"      // Ride Cymbal
    case bgm = "01"     // Background Music (not playable)

    var noteType: NoteType? {
        switch self {
        case .lc, .cy:
            return .crash
        case .hh:
            return .openHiHat
        case .hhc:
            return .hiHat
        case .sn:
            return .snare
        case .ht:
            return .highTom
        case .bd:
            return .bass
        case .lt:
            return .midTom
        case .ft:
            return .lowTom
        case .rd:
            return .ride
        case .lp:
            return .hiHatPedal
        case .lb:
            return .bass
        case .bpm, .bgm:
            return nil // Not playable drum notes
        }
    }

    var isPlayable: Bool {
        return noteType != nil
    }
}

class DTXFileParser {

    static func parseChartMetadata(from url: URL) throws -> DTXChartData {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw DTXParseError.fileNotFound
        }

        // Try Shift-JIS encoding first (common for DTX files), then fallback to UTF-8
        var content: String
        if let shiftJISContent = try? String(contentsOf: url, encoding: .shiftJIS) {
            content = shiftJISContent
        } else {
            content = try String(contentsOf: url, encoding: .utf8)
        }
        return try parseChartMetadata(from: content)
    }

    static func parseChartMetadata(from content: String) throws -> DTXChartData {
        let lines = content.components(separatedBy: .newlines)

        var metadata = DTXMetadata()
        var notes: [DTXNote] = []

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            if isNoteLine(trimmedLine) {
                let parsedNotes = try parseNoteLine(trimmedLine)
                notes.append(contentsOf: parsedNotes)
            } else {
                try processLine(trimmedLine, metadata: &metadata)
            }
        }

        try validateRequiredFields(metadata)

        return DTXChartData(
            title: metadata.title!,
            artist: metadata.artist!,
            bpm: metadata.bpm!,
            difficultyLevel: metadata.difficultyLevel!,
            preview: metadata.preview,
            previewImage: metadata.previewImage,
            stageFile: metadata.stageFile,
            notes: notes,
            bgmStartTimePosition: Self.bgmStartTimePosition(from: notes)
        )
    }

    private static func processLine(_ line: String, metadata: inout DTXMetadata) throws {
        if line.hasPrefix("#TITLE:") {
            metadata.title = extractValue(from: line, prefix: "#TITLE:")
        } else if line.hasPrefix("#ARTIST:") {
            metadata.artist = extractValue(from: line, prefix: "#ARTIST:")
        } else if line.hasPrefix("#BPM:") {
            let bpmString = extractValue(from: line, prefix: "#BPM:")
            guard let bpmValue = Double(bpmString) else {
                throw DTXParseError.invalidBPM
            }
            metadata.bpm = bpmValue
        } else if line.hasPrefix("#DLEVEL:") {
            let levelString = extractValue(from: line, prefix: "#DLEVEL:")
            guard let levelValue = Int(levelString) else {
                throw DTXParseError.invalidDifficultyLevel
            }
            metadata.difficultyLevel = levelValue
        } else if line.hasPrefix("#PREVIEW:") {
            metadata.preview = extractValue(from: line, prefix: "#PREVIEW:")
        } else if line.hasPrefix("#PREIMAGE:") {
            metadata.previewImage = extractValue(from: line, prefix: "#PREIMAGE:")
        } else if line.hasPrefix("#STAGEFILE:") {
            metadata.stageFile = extractValue(from: line, prefix: "#STAGEFILE:")
        }
    }

    private static func validateRequiredFields(_ metadata: DTXMetadata) throws {
        guard metadata.title != nil else {
            throw DTXParseError.missingRequiredField("TITLE")
        }

        guard metadata.artist != nil else {
            throw DTXParseError.missingRequiredField("ARTIST")
        }

        guard metadata.bpm != nil else {
            throw DTXParseError.missingRequiredField("BPM")
        }

        guard metadata.difficultyLevel != nil else {
            throw DTXParseError.missingRequiredField("DLEVEL")
        }
    }

    private static func extractValue(from line: String, prefix: String) -> String {
        let value = String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        return value
    }

    private static func isNoteLine(_ line: String) -> Bool {
        // Note line format: #xxxYY: where xxx is measure (000-999) and YY is lane ID (hex)
        let notePattern = "^#[0-9]{3}[0-9A-Fa-f]{2}:"
        let regex = try? NSRegularExpression(pattern: notePattern, options: [])
        let range = NSRange(location: 0, length: line.count)
        return regex?.firstMatch(in: line, options: [], range: range) != nil
    }

    static func parseNoteLine(_ line: String) throws -> [DTXNote] {
        // Parse format: #xxxYY: noteArray
        guard line.count >= 7 && line.hasPrefix("#") && line.contains(":") else {
            return []
        }

        let colonIndex = line.firstIndex(of: ":")!
        let headerPart = String(line[line.index(line.startIndex, offsetBy: 1)..<colonIndex])
        let noteArrayPart = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)

        guard headerPart.count == 5 else { return [] }

        let measureString = String(headerPart.prefix(3))
        let laneIDString = String(headerPart.suffix(2)).uppercased()

        guard let measureNumber = Int(measureString) else { return [] }

        // Parse note array - each note is represented by 2 characters
        let noteArray = noteArrayPart
        guard noteArray.count % 2 == 0 && !noteArray.isEmpty else { return [] }

        let noteCount = noteArray.count / 2
        var notes: [DTXNote] = []

        for i in 0..<noteCount {
            let startIndex = noteArray.index(noteArray.startIndex, offsetBy: i * 2)
            let endIndex = noteArray.index(startIndex, offsetBy: 2)
            let noteID = String(noteArray[startIndex..<endIndex]).uppercased()

            // Skip empty notes (00)
            if noteID != "00" {
                let note = DTXNote(
                    measureNumber: measureNumber,
                    laneID: laneIDString,
                    noteID: noteID,
                    notePosition: i,
                    totalPositions: noteCount
                )
                notes.append(note)
            }
        }

        return notes
    }

    private static func bgmStartTimePosition(from notes: [DTXNote]) -> Double? {
        notes
            .filter { $0.laneID.uppercased() == DTXLane.bgm.rawValue }
            .map { Double($0.measureNumber) + $0.measureOffset }
            .min()
    }
}

extension DTXNote {
    func toNoteType() -> NoteType? {
        guard let lane = DTXLane(rawValue: laneID.uppercased()) else { return nil }
        return lane.noteType
    }
}

extension DTXChartData {
    private static let maximumTicksPerMeasure = 4_096

    func toDifficulty() -> Difficulty {
        switch difficultyLevel {
        case 0...30:
            return .easy
        case 31...50:
            return .medium
        case 51...70:
            return .hard
        case 71...100:
            return .expert
        default:
            return .medium
        }
    }

    func toTimeSignature() -> TimeSignature {
        return .fourFour
    }

    var hasPlayableChips: Bool {
        notes.contains { $0.toNoteType() != nil }
    }

    func normalizedRhythmicEvents() -> [NormalizedRhythmicEvent] {
        let playableChips = notes.filter { $0.toNoteType() != nil }
        guard let ticksPerMeasure = Self.sharedTicksPerMeasure(for: playableChips) else {
            Logger.warning(
                "DTX normalization failed: shared ticks per measure exceeded \(Self.maximumTicksPerMeasure)"
                + " for \(playableChips.count) playable chips; chart will import with no notes."
            )
            return []
        }
        let visualDurationCandidates = Self.visualDurationCandidates(
            for: playableChips,
            ticksPerMeasure: ticksPerMeasure
        )

        return playableChips.compactMap { chip in
            NormalizedRhythmicEvent(
                chip: chip,
                ticksPerMeasure: ticksPerMeasure,
                visualDurationCandidate: visualDurationCandidates[Self.chipKey(chip)] ?? .quarter
            )
        }
    }

    private static func sharedTicksPerMeasure(for chips: [DTXNote]) -> Int? {
        let positiveGridSizes = chips
            .map(\.gridSize)
            .filter { $0 > 0 }

        guard !positiveGridSizes.isEmpty else {
            return 1
        }

        var ticksPerMeasure = 1
        for gridSize in positiveGridSizes {
            guard let nextTicksPerMeasure = leastCommonMultiple(ticksPerMeasure, gridSize) else {
                return nil
            }
            ticksPerMeasure = nextTicksPerMeasure
        }

        return ticksPerMeasure
    }

    private static func leastCommonMultiple(_ lhs: Int, _ rhs: Int) -> Int? {
        let lhs = abs(lhs)
        let rhs = abs(rhs)

        guard lhs > 0, rhs > 0 else {
            return nil
        }

        let quotient = lhs / greatestCommonDivisor(lhs, rhs)
        let product = quotient.multipliedReportingOverflow(by: rhs)
        guard !product.overflow, product.partialValue <= maximumTicksPerMeasure else {
            return nil
        }

        return product.partialValue
    }

    private static func greatestCommonDivisor(_ lhs: Int, _ rhs: Int) -> Int {
        var lhs = abs(lhs)
        var rhs = abs(rhs)

        while rhs != 0 {
            let remainder = lhs % rhs
            lhs = rhs
            rhs = remainder
        }

        return max(lhs, 1)
    }

    private static func visualDurationCandidates(
        for chips: [DTXNote],
        ticksPerMeasure: Int
    ) -> [String: NoteInterval] {
        guard ticksPerMeasure > 0 else {
            return [:]
        }

        let playableChips = chips.filter { chip in
            chip.gridSize > 0
                && chip.gridPosition >= 0
                && chip.gridPosition < chip.gridSize
        }
        let playableChipsByMeasure = Dictionary(grouping: playableChips, by: \.measureIndex)
        let fallbackTickSpanByMeasure = playableChipsByMeasure.mapValues { measureChips in
            let uniqueTicks = Set(measureChips.map {
                normalizedTick(for: $0, ticksPerMeasure: ticksPerMeasure)
            })

            return uniqueTicks.count == ticksPerMeasure ? 1 : max(ticksPerMeasure / 4, 1)
        }
        let sortedChips = playableChips.sorted { lhs, rhs in
            let lhsTick = normalizedAbsoluteTick(for: lhs, ticksPerMeasure: ticksPerMeasure)
            let rhsTick = normalizedAbsoluteTick(for: rhs, ticksPerMeasure: ticksPerMeasure)

            if lhsTick == rhsTick {
                return chipKey(lhs) < chipKey(rhs)
            }

            return lhsTick < rhsTick
        }
        let uniqueAbsoluteTicks = Array(Set(sortedChips.map {
            normalizedAbsoluteTick(for: $0, ticksPerMeasure: ticksPerMeasure)
        })).sorted()
        var nextAbsoluteTickByTick: [Int: Int] = [:]
        for index in uniqueAbsoluteTicks.indices.dropLast() {
            nextAbsoluteTickByTick[uniqueAbsoluteTicks[index]] = uniqueAbsoluteTicks[index + 1]
        }

        var candidates: [String: NoteInterval] = [:]

        for chip in sortedChips {
            let currentTick = normalizedAbsoluteTick(for: chip, ticksPerMeasure: ticksPerMeasure)
            let tickSpan = nextAbsoluteTickByTick[currentTick].map { $0 - currentTick }
                ?? fallbackTickSpanByMeasure[chip.measureIndex]
                ?? max(ticksPerMeasure / 4, 1)

            candidates[chipKey(chip)] = closestInterval(
                toTickSpan: tickSpan,
                ticksPerMeasure: ticksPerMeasure
            )
        }

        return candidates
    }

    private static func normalizedTick(for chip: DTXNote, ticksPerMeasure: Int) -> Int {
        guard chip.gridSize > 0, ticksPerMeasure > 0 else {
            return 0
        }

        return chip.gridPosition * (ticksPerMeasure / chip.gridSize)
    }

    private static func normalizedAbsoluteTick(for chip: DTXNote, ticksPerMeasure: Int) -> Int {
        chip.measureIndex * ticksPerMeasure + normalizedTick(for: chip, ticksPerMeasure: ticksPerMeasure)
    }

    private static func chipKey(_ chip: DTXNote) -> String {
        [
            String(chip.measureIndex),
            chip.laneID.uppercased(),
            chip.noteID.uppercased(),
            String(chip.gridPosition),
            String(chip.gridSize)
        ].joined(separator: "|")
    }

    private static func closestInterval(toTickSpan tickSpan: Int, ticksPerMeasure: Int) -> NoteInterval {
        guard tickSpan > 0, ticksPerMeasure > 0 else {
            return .quarter
        }

        let measureFraction = Double(tickSpan) / Double(ticksPerMeasure)
        let supportedIntervals: [(interval: NoteInterval, measureFraction: Double)] = [
            (.full, 1.0),
            (.half, 0.5),
            (.quarter, 0.25),
            (.eighth, 0.125),
            (.sixteenth, 0.0625),
            (.thirtysecond, 0.03125),
            (.sixtyfourth, 0.015625)
        ]

        return supportedIntervals.min { lhs, rhs in
            abs(measureFraction - lhs.measureFraction) < abs(measureFraction - rhs.measureFraction)
        }?.interval ?? .quarter
    }

    func toNotes(for chart: Chart) -> [Note] {
        normalizedRhythmicEvents().map { event in
            Note(
                interval: event.visualDurationCandidate,
                noteType: event.noteType,
                measureNumber: event.measureIndex + 1,
                measureOffset: event.measureOffset,
                chart: chart,
                originKind: .dtx,
                sourceLaneID: event.laneID,
                sourceNoteID: event.noteID,
                sourceGridPosition: event.gridPosition,
                sourceGridSize: event.gridSize,
                normalizedMeasureIndex: event.measureIndex,
                normalizedAbsoluteTick: event.absoluteTick,
                normalizedTickWithinMeasure: event.tickWithinMeasure,
                normalizedTicksPerMeasure: event.ticksPerMeasure,
                notationVoiceCandidate: event.voiceCandidate,
                visualDurationCandidate: event.visualDurationCandidate,
                articulationCandidate: event.articulationCandidate
            )
        }
    }
}
