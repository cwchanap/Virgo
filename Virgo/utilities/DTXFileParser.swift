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

    init(
        title: String,
        artist: String,
        bpm: Double,
        difficultyLevel: Int,
        preview: String? = nil,
        previewImage: String? = nil,
        stageFile: String? = nil,
        notes: [DTXNote] = []
    ) {
        self.title = title
        self.artist = artist
        self.bpm = bpm
        self.difficultyLevel = difficultyLevel
        self.preview = preview
        self.previewImage = previewImage
        self.stageFile = stageFile
        self.notes = notes
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
        case .bpm, .bgm, .lb:
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
            notes: notes
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
        let notePattern = "^#[0-9]{3}[0-9A-F]{2}:"
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
        let laneIDString = String(headerPart.suffix(2))

        guard let measureNumber = Int(measureString) else { return [] }

        // Parse note array - each note is represented by 2 characters
        let noteArray = noteArrayPart
        guard noteArray.count % 2 == 0 && !noteArray.isEmpty else { return [] }

        let noteCount = noteArray.count / 2
        var notes: [DTXNote] = []

        for i in 0..<noteCount {
            let startIndex = noteArray.index(noteArray.startIndex, offsetBy: i * 2)
            let endIndex = noteArray.index(startIndex, offsetBy: 2)
            let noteID = String(noteArray[startIndex..<endIndex])

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
}

extension DTXNote {
    func toNoteType() -> NoteType? {
        guard let lane = DTXLane(rawValue: laneID.uppercased()) else { return nil }
        return lane.noteType
    }

    func toNoteInterval() -> NoteInterval {
        // Calculate note interval based on total positions in measure
        switch totalPositions {
        case 1:
            return .full
        case 2:
            return .half
        case 4:
            return .quarter
        case 8:
            return .eighth
        case 16:
            return .sixteenth
        case 32:
            return .thirtysecond
        case 64:
            return .sixtyfourth
        default:
            // For non-standard divisions, use quarter note as fallback
            return .quarter
        }
    }
}

extension DTXChartData {
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

    func toNotes(for chart: Chart) -> [Note] {
        return notes.compactMap { dtxNote in
            guard let noteType = dtxNote.toNoteType() else { return nil }

            return Note(
                interval: dtxNote.toNoteInterval(),
                noteType: noteType,
                measureNumber: dtxNote.measureNumber + 1, // Convert to 1-based indexing
                measureOffset: dtxNote.measureOffset,
                chart: chart
            )
        }
    }
}
