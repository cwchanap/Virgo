//
//  RhythmLayoutSnapshotBuilder.swift
//  Virgo
//

import Foundation

/// Assembles the `RhythmLayoutSnapshot` that timeline-native layout consumes.
///
/// Extracted from `GameplayViewModel+Computations` so the gameplay view model and
/// the drum-tab fixture harness share one code path. A parallel copy in tests
/// would let goldens pass while production rendering broke.
@MainActor
struct RhythmLayoutSnapshotBuilder {
    func build(
        resolvedRhythm: ResolvedChartRhythm,
        timeline: RhythmTimeline,
        feel: RhythmicFeel
    ) throws -> RhythmLayoutSnapshot {
        let analysisEvents = resolvedRhythm.orderedEvents.compactMap { event -> RhythmAnalysisEvent? in
            guard let note = resolvedRhythm.noteByEventID[event.eventID] else { return nil }
            let drumType = DrumType.from(noteType: note.noteType)
            return RhythmAnalysisEvent(
                eventID: event.eventID,
                origin: event.origin,
                position: event.position,
                voice: drumType.map(NotationVoice.voice(for:)) ?? .upper,
                storedInterval: note.interval,
                visualDurationCandidate: note.visualDurationCandidate
            )
        }
        let analysis = NotationRhythmAnalyzer().analyze(
            events: analysisEvents,
            measures: timeline.measures,
            ticksPerWholeNote: timeline.ticksPerWholeNote,
            feel: feel
        )
        let measures = rhythmMeasuresApplyingWarnings(timeline.measures, warnings: analysis.warnings)
        let notes = analysis.notes.compactMap { analyzed -> RhythmLayoutNote? in
            guard let note = resolvedRhythm.noteByEventID[analyzed.eventID] else { return nil }
            return RhythmLayoutNote(
                eventID: analyzed.eventID,
                sourceObjectID: ObjectIdentifier(note),
                sourceLaneID: note.sourceLaneID,
                sourceChipID: note.sourceNoteID,
                noteType: note.noteType,
                position: analyzed.position,
                durationTicks: analyzed.durationTicks,
                rhythm: analyzed.rhythm,
                tupletID: analyzed.tupletID
            )
        }
        let controls = resolvedRhythm.orderedEvents.compactMap { event -> RhythmLayoutControl? in
            guard let control = resolvedRhythm.controlByEventID[event.eventID] else { return nil }
            return RhythmLayoutControl(
                eventID: event.eventID,
                event: control,
                position: event.position
            )
        }
        let rests = analysis.rests.compactMap { rest -> RhythmLayoutRest? in
            guard let position = timeline.position(
                measureIndex: rest.measureIndex,
                localTick: rest.startTick
            ) else { return nil }
            return RhythmLayoutRest(
                position: position,
                durationTicks: rest.durationTicks,
                voice: rest.voice,
                rhythm: rest.rhythm,
                visibility: rest.visibility,
                tupletID: rest.tupletID
            )
        }
        let snapshot = try RhythmLayoutSnapshot(
            ticksPerWholeNote: timeline.ticksPerWholeNote,
            measures: measures,
            notes: notes,
            controls: controls,
            rests: rests,
            feel: feel,
            diagnostics: resolvedRhythm.runtimeDiagnostics
        )
        snapshot.logDiagnostics()
        return snapshot
    }

    private func rhythmMeasuresApplyingWarnings(
        _ measures: [RhythmMeasure],
        warnings: [RhythmMeasureWarning]
    ) -> [RhythmMeasure] {
        let warningsByMeasure = Dictionary(uniqueKeysWithValues: warnings.map { ($0.measureIndex, $0.codes) })
        return measures.map { measure in
            guard let codes = warningsByMeasure[measure.measureIndex], !codes.isEmpty else { return measure }
            let existingCodes: Set<RhythmDiagnosticCode>
            if case let .unsupported(existing) = measure.engravingSupport {
                existingCodes = Set(existing)
            } else {
                existingCodes = []
            }
            return RhythmMeasure(
                measureIndex: measure.measureIndex,
                startTick: measure.startTick,
                durationTicks: measure.durationTicks,
                timeSignature: measure.timeSignature,
                beatGroups: measure.beatGroups,
                engravingSupport: .unsupported(Array(existingCodes.union(codes)).sorted { $0.rawValue < $1.rawValue })
            )
        }
    }
}
