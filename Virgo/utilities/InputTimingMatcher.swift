//
//  InputTimingMatcher.swift
//  Virgo
//

import Foundation

struct RhythmNoteTarget: Hashable, Sendable {
    let eventID: RhythmEventID
    let drumType: DrumType
    let position: RhythmEventPosition
    let targetSecondsAtOneX: Double
}

enum InputTimingConfiguration {
    case timeline(targets: [RhythmNoteTarget], timeline: RhythmTimeline, speed: Double)
    case legacy(bpm: Double, timeSignature: TimeSignature, notes: [Note])
}

struct InputTimingMatcher {
    // Wider than the scoring window so near-miss hits can still report timingError.
    private static let searchWindowSeconds = 0.2
    // Absorbs binary floating-point representation error in
    // `(actualTime - expectedTime) * 1000` so that an intended exact-boundary
    // hit (e.g. 1.6 - 1.5 = 0.10000000000000009) classifies as `.good` instead
    // of `.miss`. Matches the 1e-9 epsilon used by the missed-note scanner.
    private static let toleranceEpsilonMs = 1e-9

    struct LegacyState {
        let timeSignature: TimeSignature
        let notes: [Note]
        let secondsPerBeat: Double
        let secondsPerMeasure: Double
    }

    struct EffectiveTimelineTarget {
        let snapshot: RhythmNoteTarget
        let targetSeconds: Double
    }

    struct TimelineState {
        let targets: [EffectiveTimelineTarget]
        let timeline: RhythmTimeline
        let speed: Double
        let oneXSecondsPerTick: Double?
    }

    enum State {
        case legacy(LegacyState)
        case timeline(TimelineState)
    }

    private let state: State

    init(bpm: Double, timeSignature: TimeSignature, notes: [Note]) {
        self.init(configuration: .legacy(bpm: bpm, timeSignature: timeSignature, notes: notes))
    }

    init(configuration: InputTimingConfiguration) {
        switch configuration {
        case let .legacy(bpm, timeSignature, notes):
            precondition(bpm.isFinite && bpm > 0, "BPM must be finite and > 0, got: \(bpm)")
            precondition(
                timeSignature.beatsPerMeasure > 0,
                "beatsPerMeasure must be > 0, got: \(timeSignature.beatsPerMeasure)"
            )
            let secondsPerBeat = 60.0 / bpm
            state = .legacy(LegacyState(
                timeSignature: timeSignature,
                notes: notes,
                secondsPerBeat: secondsPerBeat,
                secondsPerMeasure: secondsPerBeat * Double(timeSignature.beatsPerMeasure)
            ))
        case let .timeline(targets, timeline, speed):
            precondition(speed.isFinite && speed > 0, "Speed must be finite and > 0, got: \(speed)")
            let effectiveTargets = targets.map {
                precondition(
                    $0.targetSecondsAtOneX.isFinite && $0.targetSecondsAtOneX >= 0,
                    "Timeline target seconds must be finite and nonnegative"
                )
                return EffectiveTimelineTarget(
                    snapshot: $0,
                    targetSeconds: $0.targetSecondsAtOneX / speed
                )
            }.sorted(by: Self.timelineTargetComesBefore)
            state = .timeline(TimelineState(
                targets: effectiveTargets,
                timeline: timeline,
                speed: speed,
                oneXSecondsPerTick: Self.consistentOneXSecondsPerTick(from: targets)
            ))
        }
    }

    func calculateNoteMatch(for hit: InputHit, elapsedTime: Double) -> NoteMatchResult {
        switch state {
        case let .legacy(legacy):
            return calculateLegacyNoteMatch(for: hit, elapsedTime: elapsedTime, state: legacy)
        case let .timeline(timeline):
            return calculateTimelineNoteMatch(for: hit, elapsedTime: elapsedTime, state: timeline)
        }
    }

    var effectiveBPM: Double? {
        switch state {
        case let .legacy(legacy):
            return 60 / legacy.secondsPerBeat
        case let .timeline(timeline):
            guard let secondsPerTick = timeline.oneXSecondsPerTick else { return nil }
            return 240 * timeline.speed
                / (secondsPerTick * Double(timeline.timeline.ticksPerWholeNote))
        }
    }
}

private extension InputTimingMatcher {
    func calculateLegacyNoteMatch(
        for hit: InputHit,
        elapsedTime: Double,
        state: LegacyState
    ) -> NoteMatchResult {
        let totalBeatsElapsed = elapsedTime / state.secondsPerBeat
        let beatsPerMeasure = Double(state.timeSignature.beatsPerMeasure)
        let measureNumber = Int(totalBeatsElapsed / beatsPerMeasure) + 1
        let beatWithinMeasure = totalBeatsElapsed.truncatingRemainder(dividingBy: beatsPerMeasure)
        let measureOffset = beatWithinMeasure / beatsPerMeasure
        let matchedNote = findClosestLegacyNote(
            drumType: hit.drumType,
            elapsedTime: elapsedTime,
            state: state
        )
        let expectedTime = matchedNote.map {
            legacyExpectedTime(
                measureNumber: $0.measureNumber,
                measureOffset: $0.measureOffset,
                state: state
            )
        }
        let (timingAccuracy, timingError) = timingAccuracy(
            expectedTime: expectedTime,
            actualTime: elapsedTime
        )

        return NoteMatchResult(
            hitInput: hit,
            matchedNote: matchedNote,
            timingAccuracy: timingAccuracy,
            measureNumber: measureNumber,
            measureOffset: measureOffset,
            timingError: timingError
        )
    }

    func calculateTimelineNoteMatch(
        for hit: InputHit,
        elapsedTime: Double,
        state: TimelineState
    ) -> NoteMatchResult {
        let matchedTarget = state.targets.filter {
            $0.snapshot.drumType == hit.drumType
                && abs(elapsedTime - $0.targetSeconds) <= Self.searchWindowSeconds
        }.min {
            let leftDistance = abs(elapsedTime - $0.targetSeconds)
            let rightDistance = abs(elapsedTime - $1.targetSeconds)
            if leftDistance != rightDistance {
                return leftDistance < rightDistance
            }
            return $0.snapshot.eventID.rawValue < $1.snapshot.eventID.rawValue
        }
        let (accuracy, error) = timingAccuracy(
            expectedTime: matchedTarget?.targetSeconds,
            actualTime: elapsedTime
        )

        return NoteMatchResult(
            hitInput: hit,
            timingAccuracy: accuracy,
            timingError: error,
            matchedEventID: matchedTarget?.snapshot.eventID,
            matchedTargetPosition: matchedTarget?.snapshot.position,
            matchedTargetSeconds: matchedTarget?.targetSeconds,
            hitSongSeconds: elapsedTime,
            hitPosition: timelinePosition(for: elapsedTime, state: state)
        )
    }

    func findClosestLegacyNote(
        drumType: DrumType,
        elapsedTime: Double,
        state: LegacyState
    ) -> Note? {
        let candidateNotes = state.notes.filter { note in
            guard DrumType.from(noteType: note.noteType) == drumType else { return false }
            let noteElapsedTime = legacyExpectedTime(
                measureNumber: note.measureNumber,
                measureOffset: note.measureOffset,
                state: state
            )
            return abs(elapsedTime - noteElapsedTime) <= Self.searchWindowSeconds
        }

        return candidateNotes.min { note1, note2 in
            let time1 = legacyExpectedTime(
                measureNumber: note1.measureNumber,
                measureOffset: note1.measureOffset,
                state: state
            )
            let time2 = legacyExpectedTime(
                measureNumber: note2.measureNumber,
                measureOffset: note2.measureOffset,
                state: state
            )
            return abs(elapsedTime - time1) < abs(elapsedTime - time2)
        }
    }

    func legacyExpectedTime(
        measureNumber: Int,
        measureOffset: Double,
        state: LegacyState
    ) -> Double {
        Double(measureNumber - 1) * state.secondsPerMeasure + measureOffset * state.secondsPerMeasure
    }

    func timingAccuracy(expectedTime: Double?, actualTime: Double) -> (TimingAccuracy, Double?) {
        guard let expectedTime else { return (.miss, nil) }
        let timingErrorMs = (actualTime - expectedTime) * 1000.0
        let absErrorMs = abs(timingErrorMs)
        let epsilon = Self.toleranceEpsilonMs

        if absErrorMs <= TimingAccuracy.perfect.toleranceMs + epsilon {
            return (.perfect, timingErrorMs)
        } else if absErrorMs <= TimingAccuracy.great.toleranceMs + epsilon {
            return (.great, timingErrorMs)
        } else if absErrorMs <= TimingAccuracy.good.toleranceMs + epsilon {
            return (.good, timingErrorMs)
        }
        return (.miss, timingErrorMs)
    }

    func timelinePosition(for elapsedTime: Double, state: TimelineState) -> RhythmEventPosition? {
        guard elapsedTime.isFinite,
              elapsedTime >= 0,
              let secondsPerTick = state.oneXSecondsPerTick else {
            return nil
        }
        let continuousTick = elapsedTime * state.speed / secondsPerTick
        guard continuousTick.isFinite,
              continuousTick >= 0,
              continuousTick <= Double(state.timeline.endTick) else {
            return nil
        }
        return state.timeline.position(forAbsoluteTick: Int(continuousTick.rounded()))
    }

    static func timelineTargetComesBefore(
        _ left: EffectiveTimelineTarget,
        _ right: EffectiveTimelineTarget
    ) -> Bool {
        if left.targetSeconds != right.targetSeconds {
            return left.targetSeconds < right.targetSeconds
        }
        return left.snapshot.eventID.rawValue < right.snapshot.eventID.rawValue
    }

    static func consistentOneXSecondsPerTick(from targets: [RhythmNoteTarget]) -> Double? {
        let positiveTickTargets = targets.filter { $0.position.absoluteTick > 0 }
        guard !positiveTickTargets.isEmpty else { return nil }
        var scales: [Double] = []
        scales.reserveCapacity(positiveTickTargets.count)
        for target in positiveTickTargets {
            let scale = target.targetSecondsAtOneX / Double(target.position.absoluteTick)
            guard scale.isFinite, scale > 0 else { return nil }
            scales.append(scale)
        }
        let first = scales[0]
        let tolerance = max(1e-9, first * 1e-9)
        guard scales.allSatisfy({ abs($0 - first) <= tolerance }) else { return nil }
        return first
    }
}
