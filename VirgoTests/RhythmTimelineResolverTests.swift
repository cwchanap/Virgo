//
//  RhythmTimelineResolverTests.swift
//  VirgoTests
//

import Foundation
import Testing
@testable import Virgo

@Suite("Rhythm timeline resolver", .serialized)
@MainActor
struct RhythmTimelineResolverTests {
    @Test("missing metadata synthesizes an exact timeline for manual-only charts")
    func missingManualChartSynthesizesTimeline() throws {
        let first = Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: 0.5)
        let second = Note(interval: .quarter, noteType: .bass, measureNumber: 2, measureOffset: 0)
        let chart = Chart(difficulty: .medium, timeSignature: .fourFour, notes: [first, second])

        let resolved = RhythmTimelineResolver().resolve(chart: chart)

        #expect(resolved.availability == .valid)
        #expect(resolved.timeline?.measures.count == 2)
        #expect(resolved.orderedEvents.map(\.position.absoluteTick) == [2, 4])
        #expect(resolved.noteByEventID.count == 2)
        #expect(resolved.runtimeDiagnostics.isEmpty)
        #expect(first.normalizedMeasureIndex == nil)
        #expect(first.normalizedAbsoluteTick == nil)
        #expect(first.normalizedTickWithinMeasure == nil)
        #expect(first.normalizedTicksPerMeasure == nil)
    }

    @Test("missing metadata plus any DTX note or control remains wholly legacy")
    func missingMixedOriginRemainsLegacy() {
        let manual = Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0)
        let dtxControl = ChartControlEvent(
            kind: .stop,
            measureNumber: 1,
            measureOffset: 0.5,
            originKind: .dtx,
            sourceLaneID: "08",
            sourceNoteID: "01",
            sourceGridPosition: 1,
            sourceGridSize: 2,
            targetLaneID: "11"
        )
        let chart = Chart(
            difficulty: .medium,
            notes: [manual],
            controlEvents: [dtxControl]
        )

        let resolved = RhythmTimelineResolver().resolve(chart: chart)

        #expect(resolved.availability == .legacy)
        #expect(resolved.timeline == nil)
        #expect(resolved.orderedEvents.isEmpty)
        #expect(resolved.noteByEventID.isEmpty)
        #expect(resolved.runtimeDiagnostics.isEmpty)
    }

    @Test("corrupt nonempty payload is fatal before origin inspection")
    func corruptPayloadIsAlwaysFatal() {
        let chart = Chart(
            difficulty: .medium,
            notes: [Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0)]
        )
        chart.rhythmMetadataData = Data("corrupt".utf8)

        let resolved = RhythmTimelineResolver().resolve(chart: chart)

        #expect(resolved.availability == .fatal)
        #expect(resolved.timeline == nil)
        #expect(resolved.runtimeDiagnostics.map(\.code) == [.inconsistentPersistedTiming])
    }

    @Test("decoded fatal metadata preserves its diagnostics")
    func decodedFatalMetadataIsFatal() throws {
        let diagnostic = try PersistedRhythmDiagnostic(
            code: .malformedTimeSignature,
            severity: .timingFatal,
            sourceLineNumber: 8
        )
        let metadata = try ChartRhythmMetadata(
            timeSignature: nil,
            feel: .straight,
            measureLengthOverrides: [],
            bgmStartAnchor: nil,
            timingStatus: .fatal,
            diagnostics: [diagnostic]
        )
        let chart = Chart(difficulty: .hard)
        try chart.setRhythmMetadata(metadata)

        let resolved = RhythmTimelineResolver().resolve(chart: chart)

        #expect(resolved.availability == .fatal)
        #expect(resolved.runtimeDiagnostics == [diagnostic])
    }

    @Test("valid source events receive deterministic IDs after canonical sorting")
    func deterministicEventIDs() throws {
        let later = dtxNote(
            noteType: .crash,
            lane: "16",
            chip: "03",
            gridPosition: 1,
            gridSize: 4
        )
        let sameTimeSecond = dtxNote(
            noteType: .bass,
            lane: "13",
            chip: "02",
            gridPosition: 0,
            gridSize: 4
        )
        let sameTimeFirst = dtxNote(
            noteType: .snare,
            lane: "12",
            chip: "01",
            gridPosition: 0,
            gridSize: 4
        )
        let chart = Chart(
            difficulty: .expert,
            notes: [later, sameTimeSecond, sameTimeFirst]
        )
        try chart.setRhythmMetadata(validMetadata())

        let firstResolution = RhythmTimelineResolver().resolve(chart: chart)
        let secondResolution = RhythmTimelineResolver().resolve(chart: chart)

        #expect(firstResolution.availability == .valid)
        #expect(firstResolution.orderedEvents.map(\.eventID.rawValue) == [0, 1, 2])
        #expect(firstResolution.orderedEvents.map(\.sourceLaneID) == ["12", "13", "16"])
        #expect(firstResolution.orderedEvents.map(\.position.absoluteTick) == [0, 0, 1])
        #expect(firstResolution.orderedEvents == secondResolution.orderedEvents)
        #expect(firstResolution.noteByEventID[.init(rawValue: 0)] === sameTimeFirst)
        #expect(firstResolution.noteByEventID[.init(rawValue: 1)] === sameTimeSecond)
        #expect(firstResolution.noteByEventID[.init(rawValue: 2)] === later)
    }

    @Test("notes and controls share one event identity sequence")
    func notesAndControlsShareIdentitySequence() throws {
        let note = dtxNote(
            noteType: .snare,
            lane: "12",
            chip: "01",
            gridPosition: 0,
            gridSize: 4
        )
        let control = ChartControlEvent(
            kind: .stop,
            measureNumber: 1,
            measureOffset: 0,
            originKind: .dtx,
            sourceLaneID: "08",
            sourceNoteID: "01",
            sourceGridPosition: 0,
            sourceGridSize: 4,
            targetLaneID: "12"
        )
        let chart = Chart(difficulty: .medium, notes: [note], controlEvents: [control])
        try chart.setRhythmMetadata(validMetadata())

        let resolved = RhythmTimelineResolver().resolve(chart: chart)

        #expect(resolved.orderedEvents.count == 2)
        #expect(Set(resolved.orderedEvents.map(\.eventID)).count == 2)
        #expect(resolved.orderedEvents.map(\.sourceKind) == [.control, .note])
        #expect(resolved.noteByEventID.count == 1)
    }

    @Test("valid metadata plus one inadmissible manual event is fatal")
    func invalidManualAdditionIsFatal() throws {
        let manual = Note(
            interval: .quarter,
            noteType: .snare,
            measureNumber: 1,
            measureOffset: 0.4142135623730951
        )
        let chart = Chart(difficulty: .medium, notes: [manual])
        try chart.setRhythmMetadata(validMetadata())

        let resolved = RhythmTimelineResolver().resolve(chart: chart)

        #expect(resolved.availability == .fatal)
        #expect(resolved.timeline == nil)
        #expect(resolved.runtimeDiagnostics.map(\.code) == [.inexactGridProjection])
        #expect(resolved.runtimeDiagnostics.allSatisfy { $0.severity == .timingFatal })
    }

    @Test("manual-only synthesis failure falls back wholly to legacy")
    func manualSynthesisFailureFallsBackToLegacy() {
        let valid = Note(interval: .quarter, noteType: .bass, measureNumber: 1, measureOffset: 0)
        let invalid = Note(
            interval: .quarter,
            noteType: .snare,
            measureNumber: 1,
            measureOffset: 0.4142135623730951
        )
        let chart = Chart(difficulty: .medium, notes: [valid, invalid])

        let resolved = RhythmTimelineResolver().resolve(chart: chart)

        #expect(resolved.availability == .legacy)
        #expect(resolved.timeline == nil)
        #expect(resolved.orderedEvents.isEmpty)
        #expect(resolved.noteByEventID.isEmpty)
        #expect(resolved.runtimeDiagnostics.map(\.code) == [.manualTimelineUnavailable])
        #expect(resolved.runtimeDiagnostics.allSatisfy { $0.severity == .engravingOnly })
    }

    @Test("final-measure manual rollover is legacy without payload and fatal with payload")
    func finalMeasureRolloverPrecedence() throws {
        let rollover = Note(
            interval: .quarter,
            noteType: .snare,
            measureNumber: 4_096,
            measureOffset: 1
        )
        let legacyChart = Chart(difficulty: .medium, notes: [rollover])
        let timelineChart = Chart(
            difficulty: .medium,
            notes: [Note(
                interval: .quarter,
                noteType: .snare,
                measureNumber: 4_096,
                measureOffset: 1
            )]
        )
        try timelineChart.setRhythmMetadata(validMetadata())

        let legacy = RhythmTimelineResolver().resolve(chart: legacyChart)
        let fatal = RhythmTimelineResolver().resolve(chart: timelineChart)

        #expect(legacy.availability == .legacy)
        #expect(legacy.runtimeDiagnostics.map(\.code) == [.manualTimelineUnavailable])
        #expect(fatal.availability == .fatal)
        #expect(fatal.runtimeDiagnostics.map(\.code) == [.measureLimitExceeded])
    }

    @Test("valid metadata requires complete raw DTX coordinates")
    func incompleteDTXCoordinatesAreFatal() throws {
        let note = Note(
            interval: .quarter,
            noteType: .snare,
            measureNumber: 1,
            measureOffset: 0,
            originKind: .dtx,
            sourceLaneID: "12",
            sourceNoteID: "01",
            sourceGridPosition: 0
        )
        let chart = Chart(difficulty: .medium, notes: [note])
        try chart.setRhythmMetadata(validMetadata())

        let resolved = RhythmTimelineResolver().resolve(chart: chart)

        #expect(resolved.availability == .fatal)
        #expect(resolved.runtimeDiagnostics.map(\.code) == [.inexactGridProjection])
    }

    @Test("partial or mismatched canonical persisted timing is fatal")
    func inconsistentPersistedTimingIsFatal() throws {
        let note = dtxNote(
            noteType: .snare,
            lane: "12",
            chip: "01",
            gridPosition: 1,
            gridSize: 4
        )
        note.normalizedMeasureIndex = 0
        note.normalizedAbsoluteTick = 999
        let chart = Chart(difficulty: .medium, notes: [note])
        try chart.setRhythmMetadata(validMetadata())

        let resolved = RhythmTimelineResolver().resolve(chart: chart)

        #expect(resolved.availability == .fatal)
        #expect(resolved.runtimeDiagnostics.map(\.code) == [.inconsistentPersistedTiming])
    }

    @Test("canonical projection exposes import values without mutating models")
    func canonicalProjectionIsPure() throws {
        let note = dtxNote(
            noteType: .snare,
            lane: "12",
            chip: "01",
            measureNumber: 2,
            gridPosition: 1,
            gridSize: 4
        )
        let chart = Chart(difficulty: .medium, notes: [note])
        try chart.setRhythmMetadata(validMetadata())

        let resolved = RhythmTimelineResolver().resolve(chart: chart)
        let sourceID = try #require(resolved.orderedEvents.first?.sourceEventID)
        let timing = try #require(resolved.canonicalProjection?.normalizedTiming(for: sourceID))

        #expect(timing.measureIndex == 1)
        #expect(timing.tickWithinMeasure == 1)
        #expect(timing.ticksPerMeasure == 4)
        #expect(timing.absoluteTick == 5)
        #expect(note.normalizedMeasureIndex == nil)
        #expect(note.normalizedAbsoluteTick == nil)
        #expect(note.normalizedTickWithinMeasure == nil)
        #expect(note.normalizedTicksPerMeasure == nil)
    }

    private func validMetadata() throws -> ChartRhythmMetadata {
        try ChartRhythmMetadata(
            timeSignature: .fourFour,
            feel: .straight,
            measureLengthOverrides: [],
            bgmStartAnchor: nil,
            timingStatus: .valid,
            diagnostics: []
        )
    }

    private func dtxNote(
        noteType: NoteType,
        lane: String,
        chip: String,
        measureNumber: Int = 1,
        gridPosition: Int,
        gridSize: Int
    ) -> Note {
        Note(
            interval: .quarter,
            noteType: noteType,
            measureNumber: measureNumber,
            measureOffset: Double(gridPosition) / Double(gridSize),
            originKind: .dtx,
            sourceLaneID: lane,
            sourceNoteID: chip,
            sourceGridPosition: gridPosition,
            sourceGridSize: gridSize
        )
    }
}
