//
//  RhythmTimelineResolver.swift
//  Virgo
//

import Foundation

struct RhythmEventID: Hashable, Sendable {
    let rawValue: Int
}

enum ResolvedRhythmEventOrigin: String, Hashable, Sendable {
    case manual
    case dtx
}

struct ResolvedRhythmEvent: Hashable, Sendable {
    let eventID: RhythmEventID
    let sourceEventID: RhythmSourceEventID
    let sourceKind: RhythmSourceEventKind
    let origin: ResolvedRhythmEventOrigin
    let sourceLaneID: String?
    let sourceNoteID: String?
    let drumLaneID: String?
    let stableOrdinal: Int
    let position: RhythmEventPosition
}

@MainActor
struct ResolvedChartRhythm {
    let availability: RhythmTimelineAvailability
    let timeline: RhythmTimeline?
    let orderedEvents: [ResolvedRhythmEvent]
    let noteByEventID: [RhythmEventID: Note]
    let runtimeDiagnostics: [PersistedRhythmDiagnostic]
    let canonicalProjection: CanonicalRhythmProjection?
}

@MainActor
struct RhythmTimelineResolver {
    func resolve(chart: Chart) -> ResolvedChartRhythm {
        switch chart.rhythmMetadataState {
        case let .invalid(code):
            return unavailable(
                availability: .fatal,
                diagnostics: [timingDiagnostic(code)]
            )
        case let .valid(metadata) where metadata.timingStatus == .fatal:
            return unavailable(availability: .fatal, diagnostics: metadata.diagnostics)
        case let .valid(metadata):
            return resolveValid(
                metadata: metadata,
                notes: chart.safeNotes,
                controls: chart.safeControlEvents
            )
        case .missing:
            return resolveMissing(chart: chart)
        }
    }
}

@MainActor
private extension RhythmTimelineResolver {
    struct SourceEnvelope {
        let sourceEvent: RhythmSourceEvent
        let origin: ResolvedRhythmEventOrigin
        let sourceIdentityKey: String
        let stableOrdinal: Int
        let note: Note?
    }

    func resolveMissing(chart: Chart) -> ResolvedChartRhythm {
        let notes = chart.safeNotes
        let controls = chart.safeControlEvents
        let containsDTXEvent = notes.contains { $0.originKind == .dtx }
            || controls.contains { $0.originKind == .dtx }
        guard !containsDTXEvent else {
            return unavailable(availability: .legacy, diagnostics: [])
        }

        let metadata: ChartRhythmMetadata
        do {
            metadata = try ChartRhythmMetadata(
                timeSignature: chart.timeSignature,
                feel: .straight,
                measureLengthOverrides: [],
                bgmStartAnchor: nil,
                timingStatus: .valid,
                diagnostics: []
            )
        } catch {
            return manualLegacyResult()
        }

        let resolved = resolveValid(metadata: metadata, notes: notes, controls: controls)
        guard resolved.availability == .valid else { return manualLegacyResult() }
        return resolved
    }

    func resolveValid(
        metadata: ChartRhythmMetadata,
        notes: [Note],
        controls: [ChartControlEvent]
    ) -> ResolvedChartRhythm {
        let envelopes = sourceEnvelopes(notes: notes, controls: controls)
        do {
            let timeline = try RhythmTimelineBuilder().build(
                metadata: metadata,
                events: envelopes.map(\.sourceEvent)
            )
            return validResult(
                timeline: timeline,
                envelopes: envelopes,
                diagnostics: metadata.diagnostics
            )
        } catch let error as RhythmTimelineBuildError {
            return unavailable(
                availability: .fatal,
                diagnostics: metadata.diagnostics + [timingDiagnostic(error.diagnosticCode)]
            )
        } catch {
            return unavailable(
                availability: .fatal,
                diagnostics: metadata.diagnostics + [timingDiagnostic(.inconsistentPersistedTiming)]
            )
        }
    }

    func validResult(
        timeline: RhythmTimeline,
        envelopes: [SourceEnvelope],
        diagnostics: [PersistedRhythmDiagnostic]
    ) -> ResolvedChartRhythm {
        let sortedEnvelopes = envelopes.sorted {
            sourceEnvelopeComesBefore($0, $1, timeline: timeline)
        }
        var orderedEvents: [ResolvedRhythmEvent] = []
        var noteByEventID: [RhythmEventID: Note] = [:]
        orderedEvents.reserveCapacity(sortedEnvelopes.count)

        for (rawID, envelope) in sortedEnvelopes.enumerated() {
            guard let position = timeline.position(for: envelope.sourceEvent.id) else { continue }
            let eventID = RhythmEventID(rawValue: rawID)
            orderedEvents.append(ResolvedRhythmEvent(
                eventID: eventID,
                sourceEventID: envelope.sourceEvent.id,
                sourceKind: envelope.sourceEvent.id.kind,
                origin: envelope.origin,
                sourceLaneID: envelope.sourceEvent.sourceLaneID,
                sourceNoteID: envelope.sourceEvent.sourceNoteID,
                drumLaneID: envelope.sourceEvent.drumLaneID,
                stableOrdinal: envelope.stableOrdinal,
                position: position
            ))
            if let note = envelope.note {
                noteByEventID[eventID] = note
            }
        }

        return ResolvedChartRhythm(
            availability: .valid,
            timeline: timeline,
            orderedEvents: orderedEvents,
            noteByEventID: noteByEventID,
            runtimeDiagnostics: diagnostics,
            canonicalProjection: CanonicalRhythmProjection(timeline: timeline)
        )
    }

    func sourceEnvelopeComesBefore(
        _ left: SourceEnvelope,
        _ right: SourceEnvelope,
        timeline: RhythmTimeline
    ) -> Bool {
        let leftTick = timeline.position(for: left.sourceEvent.id)?.absoluteTick ?? Int.max
        let rightTick = timeline.position(for: right.sourceEvent.id)?.absoluteTick ?? Int.max
        if leftTick != rightTick { return leftTick < rightTick }
        if left.sourceIdentityKey != right.sourceIdentityKey {
            return left.sourceIdentityKey < right.sourceIdentityKey
        }
        let leftLane = left.sourceEvent.drumLaneID ?? ""
        let rightLane = right.sourceEvent.drumLaneID ?? ""
        if leftLane != rightLane { return leftLane < rightLane }
        return left.stableOrdinal < right.stableOrdinal
    }

    func sourceEnvelopes(notes: [Note], controls: [ChartControlEvent]) -> [SourceEnvelope] {
        var result = notes.enumerated().map { index, note in
            noteEnvelope(note, stableOrdinal: index)
        }
        result += controls.enumerated().map { index, control in
            controlEnvelope(control, stableOrdinal: notes.count + index)
        }
        return result
    }

    func noteEnvelope(_ note: Note, stableOrdinal: Int) -> SourceEnvelope {
        let kind = RhythmSourceEventKind.note
        let event = RhythmSourceEvent(
            id: RhythmSourceEventID(kind: kind, stableOrdinal: stableOrdinal),
            coordinate: coordinate(
                originKind: note.originKind,
                measureNumber: note.measureNumber,
                measureOffset: note.measureOffset,
                sourceGridPosition: note.sourceGridPosition,
                sourceGridSize: note.sourceGridSize
            ),
            sourceLaneID: note.sourceLaneID,
            sourceNoteID: note.sourceNoteID,
            drumLaneID: note.noteType.rawValue,
            persistedTiming: persistedTiming(
                measureIndex: note.normalizedMeasureIndex,
                absoluteTick: note.normalizedAbsoluteTick,
                tickWithinMeasure: note.normalizedTickWithinMeasure,
                ticksPerMeasure: note.normalizedTicksPerMeasure
            )
        )
        return SourceEnvelope(
            sourceEvent: event,
            origin: resolvedOrigin(note.originKind),
            sourceIdentityKey: sourceIdentityKey(event: event),
            stableOrdinal: stableOrdinal,
            note: note
        )
    }

    func controlEnvelope(_ control: ChartControlEvent, stableOrdinal: Int) -> SourceEnvelope {
        let kind = RhythmSourceEventKind.control
        let event = RhythmSourceEvent(
            id: RhythmSourceEventID(kind: kind, stableOrdinal: stableOrdinal),
            coordinate: coordinate(
                originKind: control.originKind,
                measureNumber: control.measureNumber,
                measureOffset: control.measureOffset,
                sourceGridPosition: control.sourceGridPosition,
                sourceGridSize: control.sourceGridSize
            ),
            sourceLaneID: control.sourceLaneID,
            sourceNoteID: control.sourceNoteID,
            drumLaneID: control.targetLaneID ?? control.kind.rawValue,
            persistedTiming: persistedTiming(
                measureIndex: control.normalizedMeasureIndex,
                absoluteTick: control.normalizedAbsoluteTick,
                tickWithinMeasure: control.normalizedTickWithinMeasure,
                ticksPerMeasure: control.normalizedTicksPerMeasure
            )
        )
        return SourceEnvelope(
            sourceEvent: event,
            origin: resolvedOrigin(control.originKind),
            sourceIdentityKey: sourceIdentityKey(event: event),
            stableOrdinal: stableOrdinal,
            note: nil
        )
    }
}

@MainActor
private extension RhythmTimelineResolver {
    func coordinate(
        originKind: NoteOriginKind,
        measureNumber: Int,
        measureOffset: Double,
        sourceGridPosition: Int?,
        sourceGridSize: Int?
    ) -> RhythmSourceCoordinate {
        switch originKind {
        case .manual:
            return .manual(measureNumber: measureNumber, measureOffset: measureOffset)
        case .dtx:
            let measureIndex = measureNumber > 0 ? measureNumber - 1 : -1
            return .dtx(
                measureIndex: measureIndex,
                gridPosition: sourceGridPosition ?? -1,
                gridSize: sourceGridSize ?? 0
            )
        }
    }

    func persistedTiming(
        measureIndex: Int?,
        absoluteTick: Int?,
        tickWithinMeasure: Int?,
        ticksPerMeasure: Int?
    ) -> RhythmPersistedTimingFields {
        RhythmPersistedTimingFields(
            measureIndex: measureIndex,
            absoluteTick: absoluteTick,
            tickWithinMeasure: tickWithinMeasure,
            ticksPerMeasure: ticksPerMeasure
        )
    }

    func resolvedOrigin(_ origin: NoteOriginKind) -> ResolvedRhythmEventOrigin {
        switch origin {
        case .manual: return .manual
        case .dtx: return .dtx
        }
    }

    func sourceIdentityKey(event: RhythmSourceEvent) -> String {
        let coordinateKey: String
        switch event.coordinate {
        case let .dtx(measureIndex, gridPosition, gridSize):
            coordinateKey = "dtx|\(measureIndex)|\(gridPosition)|\(gridSize)"
        case let .manual(measureNumber, measureOffset):
            coordinateKey = "manual|\(measureNumber)|\(measureOffset.bitPattern)"
        }
        return [
            coordinateKey,
            event.sourceLaneID ?? "",
            event.sourceNoteID ?? "",
            event.id.kind.rawValue
        ].joined(separator: "|")
    }

    func unavailable(
        availability: RhythmTimelineAvailability,
        diagnostics: [PersistedRhythmDiagnostic]
    ) -> ResolvedChartRhythm {
        ResolvedChartRhythm(
            availability: availability,
            timeline: nil,
            orderedEvents: [],
            noteByEventID: [:],
            runtimeDiagnostics: diagnostics,
            canonicalProjection: nil
        )
    }

    func manualLegacyResult() -> ResolvedChartRhythm {
        unavailable(
            availability: .legacy,
            diagnostics: [try! PersistedRhythmDiagnostic(
                code: .manualTimelineUnavailable,
                severity: .engravingOnly
            )]
        )
    }

    func timingDiagnostic(_ code: RhythmDiagnosticCode) -> PersistedRhythmDiagnostic {
        try! PersistedRhythmDiagnostic(code: code, severity: .timingFatal)
    }
}
