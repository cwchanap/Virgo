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
    var bpm: Int?
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

struct DTXChartData {
    let title: String
    let artist: String
    let bpm: Int
    let difficultyLevel: Int
    let preview: String?
    let previewImage: String?
    let stageFile: String?
    
    init(
        title: String,
        artist: String,
        bpm: Int,
        difficultyLevel: Int,
        preview: String? = nil,
        previewImage: String? = nil,
        stageFile: String? = nil
    ) {
        self.title = title
        self.artist = artist
        self.bpm = bpm
        self.difficultyLevel = difficultyLevel
        self.preview = preview
        self.previewImage = previewImage
        self.stageFile = stageFile
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
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            try processLine(trimmedLine, metadata: &metadata)
        }
        
        try validateRequiredFields(metadata)
        
        return DTXChartData(
            title: metadata.title!,
            artist: metadata.artist!,
            bpm: metadata.bpm!,
            difficultyLevel: metadata.difficultyLevel!,
            preview: metadata.preview,
            previewImage: metadata.previewImage,
            stageFile: metadata.stageFile
        )
    }
    
    private static func processLine(_ line: String, metadata: inout DTXMetadata) throws {
        if line.hasPrefix("#TITLE:") {
            metadata.title = extractValue(from: line, prefix: "#TITLE:")
        } else if line.hasPrefix("#ARTIST:") {
            metadata.artist = extractValue(from: line, prefix: "#ARTIST:")
        } else if line.hasPrefix("#BPM:") {
            let bpmString = extractValue(from: line, prefix: "#BPM:")
            guard let bpmValue = Int(bpmString) else {
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
}
