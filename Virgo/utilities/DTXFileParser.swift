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
    var virgoControlEnabled: Bool = false
    var rhythmState = DTXRhythmParser.State()
    var earliestBGMAnchor: RhythmSourceAnchor?
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
    let controlLaneKinds: [String: NotationControlEventKind]
    let rhythmMetadata: ChartRhythmMetadata
    let rhythmDiagnostics: [DTXRhythmDiagnostic]

    init(
        title: String,
        artist: String,
        bpm: Double,
        difficultyLevel: Int,
        preview: String? = nil,
        previewImage: String? = nil,
        stageFile: String? = nil,
        notes: [DTXNote] = [],
        controlLaneKinds: [String: NotationControlEventKind] = [:],
        rhythmMetadata: ChartRhythmMetadata? = nil,
        rhythmDiagnostics: [DTXRhythmDiagnostic] = []
    ) {
        self.title = title
        self.artist = artist
        self.bpm = bpm
        self.difficultyLevel = difficultyLevel
        self.preview = preview
        self.previewImage = previewImage
        self.stageFile = stageFile
        self.notes = notes
        self.controlLaneKinds = controlLaneKinds
        self.rhythmMetadata = rhythmMetadata ?? Self.defaultRhythmMetadata
        self.rhythmDiagnostics = rhythmDiagnostics
    }

    private static let defaultRhythmMetadata: ChartRhythmMetadata = {
        do {
            return try ChartRhythmMetadata(
                timeSignature: .fourFour,
                feel: .straight,
                measureLengthOverrides: [],
                bgmStartAnchor: nil,
                timingStatus: .valid,
                diagnostics: []
            )
        } catch {
            preconditionFailure("Static rhythm metadata defaults must satisfy validation: \(error)")
        }
    }()
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
    let visualDurationCandidate: NoteInterval?
    let articulationCandidate: NormalizedArticulation

    init?(
        chip: DTXNote,
        ticksPerMeasure: Int,
        visualDurationCandidate: NoteInterval?,
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
    }

    private static func voiceCandidate(for noteType: NoteType) -> NormalizedNotationVoice {
        guard let voice = DrumNotationCatalog.definition(for: noteType)?.voice else {
            assertionFailure("Missing notation voice for \(noteType)")
            return .upper
        }
        return voice == .lower ? .lower : .upper
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
    case lt = "15"      // Mid Tom (DTX "lt"; maps to .midTom in DrumNotationCatalog)
    case ft = "17"      // Floor Tom
    case cy = "16"      // Crash Cymbal
    case rd = "19"      // Ride Cymbal
    case bgm = "01"     // Background Music (not playable)

    var noteType: NoteType? {
        DrumNotationCatalog.noteType(forLaneID: rawValue)
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

        for (lineIndex, line) in lines.enumerated() {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            if metadata.rhythmState.consume(
                trimmedLine,
                sourceLineNumber: lineIndex + 1,
                sourceLine: line
            ) {
                continue
            } else if isNoteLine(trimmedLine) {
                let parsedNotes = try parseNoteLine(trimmedLine)
                notes.append(contentsOf: parsedNotes)
                if metadata.earliestBGMAnchor == nil,
                   let bgmChip = parsedNotes.first(where: { $0.laneID == DTXLane.bgm.rawValue }) {
                    metadata.earliestBGMAnchor = try RhythmSourceAnchor(
                        measureIndex: bgmChip.measureIndex,
                        gridPosition: bgmChip.gridPosition,
                        gridSize: bgmChip.gridSize
                    )
                }
            } else {
                try processLine(trimmedLine, metadata: &metadata)
            }
        }

        try validateRequiredFields(metadata)

        let controlLaneKinds: [String: NotationControlEventKind] = metadata.virgoControlEnabled
            ? ["21": .stop, "22": .choke, "23": .damp]
            : [:]
        let rhythmMetadata = try metadata.rhythmState.makeMetadata(
            bgmStartAnchor: metadata.earliestBGMAnchor
        )

        return DTXChartData(
            title: metadata.title!,
            artist: metadata.artist!,
            bpm: metadata.bpm!,
            difficultyLevel: metadata.difficultyLevel!,
            preview: metadata.preview,
            previewImage: metadata.previewImage,
            stageFile: metadata.stageFile,
            notes: notes,
            controlLaneKinds: controlLaneKinds,
            rhythmMetadata: rhythmMetadata,
            rhythmDiagnostics: metadata.rhythmState.diagnostics
        )
    }

    private static func processLine(_ line: String, metadata: inout DTXMetadata) throws {
        if line.hasPrefix("#TITLE:") {
            metadata.title = extractValue(from: line, prefix: "#TITLE:")
        } else if line.hasPrefix("#ARTIST:") {
            metadata.artist = extractValue(from: line, prefix: "#ARTIST:")
        } else if line.hasPrefix("#BPM:") {
            metadata.bpm = try parseBPM(from: line)
        } else if line.hasPrefix("#DLEVEL:") {
            metadata.difficultyLevel = try parseDifficultyLevel(from: line)
        } else if line.hasPrefix("#PREVIEW:") {
            metadata.preview = extractValue(from: line, prefix: "#PREVIEW:")
        } else if line.hasPrefix("#PREIMAGE:") {
            metadata.previewImage = extractValue(from: line, prefix: "#PREIMAGE:")
        } else if line.hasPrefix("#STAGEFILE:") {
            metadata.stageFile = extractValue(from: line, prefix: "#STAGEFILE:")
        } else if line.hasPrefix("#VIRGO_CONTROL:") {
            let value = extractValue(from: line, prefix: "#VIRGO_CONTROL:")
            if value == "1" {
                metadata.virgoControlEnabled = true
            } else if !value.isEmpty {
                Logger.info("Ignoring #VIRGO_CONTROL: \(value), expected \"1\"")
            }
        }
    }

    private static func parseBPM(from line: String) throws -> Double {
        let bpmString = extractValue(from: line, prefix: "#BPM:")
        guard let bpmValue = Double(bpmString), bpmValue.isFinite, bpmValue > 0 else {
            throw DTXParseError.invalidBPM
        }
        return bpmValue
    }

    private static func parseDifficultyLevel(from line: String) throws -> Int {
        let levelString = extractValue(from: line, prefix: "#DLEVEL:")
        guard let levelValue = Int(levelString) else {
            throw DTXParseError.invalidDifficultyLevel
        }
        return levelValue
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
        // Lane IDs are case-insensitive (DTX files may use lowercase hex such as `1c`).
        let notePattern = "^#[0-9]{3}[0-9A-F]{2}:"
        let regex = try? NSRegularExpression(pattern: notePattern, options: .caseInsensitive)
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

    func toTimeSignature() -> TimeSignature? {
        rhythmMetadata.timeSignature
    }

    var hasPlayableChips: Bool {
        notes.contains { $0.toNoteType() != nil }
    }

    func normalizedRhythmicEvents() -> [NormalizedRhythmicEvent] {
        guard rhythmMetadata.timingStatus == .valid else { return [] }
        let playableChips = notes.filter { $0.toNoteType() != nil }
        guard let ticksPerMeasure = Self.sharedTicksPerMeasure(for: playableChips) else {
            Logger.warning(
                "DTX normalization failed: shared ticks per measure exceeded \(Self.maximumTicksPerMeasure)"
                + " for \(playableChips.count) playable chips; chart will import with no notes."
            )
            return []
        }
        let visualDurationCandidates = VisualDurationLookup.candidates(
            for: playableChips,
            ticksPerMeasure: ticksPerMeasure
        )

        return playableChips.compactMap { chip in
            NormalizedRhythmicEvent(
                chip: chip,
                ticksPerMeasure: ticksPerMeasure,
                visualDurationCandidate: visualDurationCandidates[VisualDurationLookup.chipKey(chip)]
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

    func toNotes(for chart: Chart) -> [Note] {
        if rhythmMetadata.timingStatus == .fatal {
            return notes.compactMap { chip in
                guard let noteType = chip.toNoteType(), chip.gridSize > 0 else { return nil }
                return Note(
                    interval: .quarter,
                    noteType: noteType,
                    measureNumber: chip.measureIndex + 1,
                    measureOffset: Double(chip.gridPosition) / Double(chip.gridSize),
                    chart: chart,
                    originKind: .dtx,
                    sourceLaneID: chip.laneID.uppercased(),
                    sourceNoteID: chip.noteID.uppercased(),
                    sourceGridPosition: chip.gridPosition,
                    sourceGridSize: chip.gridSize
                )
            }
        }
        return normalizedRhythmicEvents().map { event in
            Note(
                interval: event.visualDurationCandidate ?? .quarter,
                noteType: event.noteType,
                measureNumber: event.measureIndex + 1,
                measureOffset: Double(event.gridPosition) / Double(event.gridSize),
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

    func toControlEvents(for chart: Chart) -> [ChartControlEvent] {
        guard !controlLaneKinds.isEmpty else { return [] }
        let hasValidTiming = rhythmMetadata.timingStatus == .valid
        return notes.compactMap { chip -> ChartControlEvent? in
            guard let kind = controlLaneKinds[chip.laneID.uppercased()] else { return nil }
            guard chip.gridSize > 0,
                  chip.gridPosition >= 0,
                  chip.gridPosition < chip.gridSize else {
                Logger.warning(
                    "DTX control chip skipped — malformed grid: lane \(chip.laneID), "
                    + "measure \(chip.measureNumber), position \(chip.gridPosition)/\(chip.gridSize)"
                )
                return nil
            }
            return ChartControlEvent(
                kind: kind,
                measureNumber: chip.measureIndex + 1,
                measureOffset: Double(chip.gridPosition) / Double(chip.gridSize),
                chart: chart,
                originKind: .dtx,
                sourceLaneID: chip.laneID.uppercased(),
                sourceNoteID: chip.noteID.uppercased(),
                sourceGridPosition: chip.gridPosition,
                sourceGridSize: chip.gridSize,
                normalizedMeasureIndex: hasValidTiming ? chip.measureIndex : nil,
                // For timing-valid parser output, unlike Note.normalizedAbsoluteTick (which uses the
                // shared LCM ticks-per-measure across all playable chips), this
                // value uses the chip's NATIVE gridSize as its resolution. It is
                // self-consistent with normalizedTicksPerMeasure (also gridSize)
                // but is NOT comparable across control chips with different grid
                // sizes. The layout engine rescales per-control via
                // exactRescaledTick before any cross-control ordering.
                normalizedAbsoluteTick: hasValidTiming
                    ? chip.measureIndex * chip.gridSize + chip.gridPosition
                    : nil,
                normalizedTickWithinMeasure: hasValidTiming ? chip.gridPosition : nil,
                normalizedTicksPerMeasure: hasValidTiming ? chip.gridSize : nil,
                targetLaneID: chip.noteID.uppercased()
            )
        }
    }
}

enum DTXImportWarning: Hashable {
    case fatalRhythm([PersistedRhythmDiagnostic])

    var message: String {
        guard case let .fatalRhythm(diagnostics) = self,
              let diagnostic = diagnostics.first else {
            return String(localized: "Unsupported chart timing")
        }
        let presentation = RhythmDiagnosticPresentation(code: diagnostic.code)
        if let measureIndex = diagnostic.sourceMeasureIndex {
            return String(localized: "\(presentation.title): measure \(measureIndex + 1) \(presentation.description)")
        }
        return String(localized: "\(presentation.title): \(presentation.description)")
    }
}

struct ImportedNoteValues {
    let interval: NoteInterval
    let noteType: NoteType
    let measureNumber: Int
    let measureOffset: Double
    let sourceLaneID: String
    let sourceNoteID: String
    let sourceGridPosition: Int
    let sourceGridSize: Int
    let normalizedMeasureIndex: Int?
    let normalizedAbsoluteTick: Int?
    let normalizedTickWithinMeasure: Int?
    let normalizedTicksPerMeasure: Int?
    let notationVoiceCandidate: NormalizedNotationVoice?
    let visualDurationCandidate: NoteInterval?
    let articulationCandidate: NormalizedArticulation?

    func makeNote(for chart: Chart) -> Note {
        Note(
            interval: interval,
            noteType: noteType,
            measureNumber: measureNumber,
            measureOffset: measureOffset,
            chart: chart,
            originKind: .dtx,
            sourceLaneID: sourceLaneID,
            sourceNoteID: sourceNoteID,
            sourceGridPosition: sourceGridPosition,
            sourceGridSize: sourceGridSize,
            normalizedMeasureIndex: normalizedMeasureIndex,
            normalizedAbsoluteTick: normalizedAbsoluteTick,
            normalizedTickWithinMeasure: normalizedTickWithinMeasure,
            normalizedTicksPerMeasure: normalizedTicksPerMeasure,
            notationVoiceCandidate: notationVoiceCandidate,
            visualDurationCandidate: visualDurationCandidate,
            articulationCandidate: articulationCandidate
        )
    }
}

struct ImportedControlValues {
    let kind: NotationControlEventKind
    let measureNumber: Int
    let measureOffset: Double
    let sourceLaneID: String
    let sourceNoteID: String
    let sourceGridPosition: Int
    let sourceGridSize: Int
    let normalizedMeasureIndex: Int?
    let normalizedAbsoluteTick: Int?
    let normalizedTickWithinMeasure: Int?
    let normalizedTicksPerMeasure: Int?
    let targetLaneID: String

    func makeControl(for chart: Chart) -> ChartControlEvent {
        ChartControlEvent(
            kind: kind,
            measureNumber: measureNumber,
            measureOffset: measureOffset,
            chart: chart,
            originKind: .dtx,
            sourceLaneID: sourceLaneID,
            sourceNoteID: sourceNoteID,
            sourceGridPosition: sourceGridPosition,
            sourceGridSize: sourceGridSize,
            normalizedMeasureIndex: normalizedMeasureIndex,
            normalizedAbsoluteTick: normalizedAbsoluteTick,
            normalizedTickWithinMeasure: normalizedTickWithinMeasure,
            normalizedTicksPerMeasure: normalizedTicksPerMeasure,
            targetLaneID: targetLaneID
        )
    }
}

struct DTXChartPersistenceProjection {
    let chartMetadata: ChartRhythmMetadata
    let timeSignature: TimeSignature
    let notes: [ImportedNoteValues]
    let controls: [ImportedControlValues]
    let warning: DTXImportWarning?
    let timeline: RhythmTimeline?
}

extension DTXChartData {
    func persistenceProjection() throws -> DTXChartPersistenceProjection {
        let noteSources = notes.enumerated().compactMap { index, chip -> ProjectionNoteSource? in
            guard let noteType = chip.toNoteType() else { return nil }
            let id = RhythmSourceEventID(kind: .note, stableOrdinal: index)
            return ProjectionNoteSource(id: id, chip: chip, noteType: noteType)
        }
        let controlSources = notes.enumerated().compactMap { index, chip -> ProjectionControlSource? in
            guard let kind = controlLaneKinds[chip.laneID.uppercased()] else { return nil }
            let id = RhythmSourceEventID(kind: .control, stableOrdinal: index)
            return ProjectionControlSource(id: id, chip: chip, kind: kind)
        }

        guard rhythmMetadata.timingStatus == .valid else {
            return fatalProjection(
                metadata: rhythmMetadata,
                noteSources: noteSources,
                controlSources: controlSources
            )
        }

        do {
            let events = noteSources.map(\.sourceEvent) + controlSources.map(\.sourceEvent)
            let timeline = try RhythmTimelineBuilder().build(metadata: rhythmMetadata, events: events)
            let projection = CanonicalRhythmProjection(timeline: timeline)
            let durationCandidates = visualDurationCandidates(noteSources: noteSources, timeline: timeline)
            return DTXChartPersistenceProjection(
                chartMetadata: rhythmMetadata,
                timeSignature: rhythmMetadata.timeSignature ?? .fourFour,
                notes: noteSources.compactMap {
                    importedNote(
                        from: $0,
                        timing: projection.normalizedTiming(for: $0.id),
                        visualDurationCandidate: durationCandidates[$0.id]
                    )
                },
                controls: controlSources.compactMap {
                    importedControl(from: $0, timing: projection.normalizedTiming(for: $0.id))
                },
                warning: nil,
                timeline: timeline
            )
        } catch let error as RhythmTimelineBuildError {
            let diagnostic = try PersistedRhythmDiagnostic(
                code: error.diagnosticCode,
                severity: .timingFatal
            )
            let fatalMetadata = try ChartRhythmMetadata(
                timeSignature: rhythmMetadata.timeSignature,
                feel: rhythmMetadata.feel,
                measureLengthOverrides: rhythmMetadata.measureLengthOverrides,
                bgmStartAnchor: rhythmMetadata.bgmStartAnchor,
                timingStatus: .fatal,
                diagnostics: orderedDiagnostics(rhythmMetadata.diagnostics + [diagnostic])
            )
            return fatalProjection(
                metadata: fatalMetadata,
                noteSources: noteSources,
                controlSources: controlSources
            )
        }
    }
}

private extension DTXChartData {
    struct ProjectionNoteSource {
        let id: RhythmSourceEventID
        let chip: DTXNote
        let noteType: NoteType

        var sourceEvent: RhythmSourceEvent {
            RhythmSourceEvent(
                id: id,
                coordinate: .dtx(
                    measureIndex: chip.measureIndex,
                    gridPosition: chip.gridPosition,
                    gridSize: chip.gridSize
                ),
                sourceLaneID: chip.laneID.uppercased(),
                sourceNoteID: chip.noteID.uppercased(),
                drumLaneID: noteType.rawValue
            )
        }
    }

    struct ProjectionControlSource {
        let id: RhythmSourceEventID
        let chip: DTXNote
        let kind: NotationControlEventKind

        var sourceEvent: RhythmSourceEvent {
            RhythmSourceEvent(
                id: id,
                coordinate: .dtx(
                    measureIndex: chip.measureIndex,
                    gridPosition: chip.gridPosition,
                    gridSize: chip.gridSize
                ),
                sourceLaneID: chip.laneID.uppercased(),
                sourceNoteID: chip.noteID.uppercased(),
                drumLaneID: chip.noteID.uppercased()
            )
        }
    }

    func fatalProjection(
        metadata: ChartRhythmMetadata,
        noteSources: [ProjectionNoteSource],
        controlSources: [ProjectionControlSource]
    ) -> DTXChartPersistenceProjection {
        DTXChartPersistenceProjection(
            chartMetadata: metadata,
            timeSignature: metadata.timeSignature ?? .fourFour,
            notes: noteSources.map { importedNote(from: $0, timing: nil, visualDurationCandidate: nil) },
            controls: controlSources.map { importedControl(from: $0, timing: nil) },
            warning: .fatalRhythm(metadata.diagnostics),
            timeline: nil
        )
    }

    func importedNote(
        from source: ProjectionNoteSource,
        timing: CanonicalNormalizedTiming?,
        visualDurationCandidate: NoteInterval?
    ) -> ImportedNoteValues {
        ImportedNoteValues(
            interval: visualDurationCandidate ?? .quarter,
            noteType: source.noteType,
            measureNumber: source.chip.measureIndex + 1,
            measureOffset: source.chip.measureOffset,
            sourceLaneID: source.chip.laneID.uppercased(),
            sourceNoteID: source.chip.noteID.uppercased(),
            sourceGridPosition: source.chip.gridPosition,
            sourceGridSize: source.chip.gridSize,
            normalizedMeasureIndex: timing?.measureIndex,
            normalizedAbsoluteTick: timing?.absoluteTick,
            normalizedTickWithinMeasure: timing?.tickWithinMeasure,
            normalizedTicksPerMeasure: timing?.ticksPerMeasure,
            notationVoiceCandidate: timing == nil ? nil : voiceCandidate(for: source.noteType),
            visualDurationCandidate: visualDurationCandidate,
            articulationCandidate: timing == nil ? nil : NormalizedArticulation.none
        )
    }

    func importedControl(
        from source: ProjectionControlSource,
        timing: CanonicalNormalizedTiming?
    ) -> ImportedControlValues {
        ImportedControlValues(
            kind: source.kind,
            measureNumber: source.chip.measureIndex + 1,
            measureOffset: source.chip.measureOffset,
            sourceLaneID: source.chip.laneID.uppercased(),
            sourceNoteID: source.chip.noteID.uppercased(),
            sourceGridPosition: source.chip.gridPosition,
            sourceGridSize: source.chip.gridSize,
            normalizedMeasureIndex: timing?.measureIndex,
            normalizedAbsoluteTick: timing?.absoluteTick,
            normalizedTickWithinMeasure: timing?.tickWithinMeasure,
            normalizedTicksPerMeasure: timing?.ticksPerMeasure,
            targetLaneID: source.chip.noteID.uppercased()
        )
    }

    func visualDurationCandidates(
        noteSources: [ProjectionNoteSource],
        timeline: RhythmTimeline
    ) -> [RhythmSourceEventID: NoteInterval] {
        let positions = noteSources.compactMap { source -> (RhythmSourceEventID, Int)? in
            guard let position = timeline.position(for: source.id) else { return nil }
            return (source.id, position.absoluteTick)
        }
        let orderedTicks = Array(Set(positions.map(\.1))).sorted()
        let nextTickByTick = Dictionary(uniqueKeysWithValues: zip(orderedTicks, orderedTicks.dropFirst()))
        return Dictionary(uniqueKeysWithValues: positions.compactMap { id, tick in
            guard let nextTick = nextTickByTick[tick] else { return nil }
            return (
                id,
                VisualDurationLookup.closestInterval(
                    toTickSpan: nextTick - tick,
                    ticksPerMeasure: timeline.ticksPerWholeNote
                )
            )
        })
    }

    func voiceCandidate(for noteType: NoteType) -> NormalizedNotationVoice {
        DrumNotationCatalog.definition(for: noteType)?.voice == .lower ? .lower : .upper
    }

    func orderedDiagnostics(_ diagnostics: [PersistedRhythmDiagnostic]) -> [PersistedRhythmDiagnostic] {
        Array(Set(diagnostics)).sorted {
            let left = ($0.sourceMeasureIndex ?? -1, $0.sourceLineNumber ?? -1, $0.code.rawValue)
            let right = ($1.sourceMeasureIndex ?? -1, $1.sourceLineNumber ?? -1, $1.code.rawValue)
            return left < right
        }
    }
}
