//
//  InputTimingMatcher.swift
//  Virgo
//

import Foundation

struct InputTimingMatcher {
    private let timeSignature: TimeSignature
    private let notes: [Note]
    private let secondsPerBeat: Double
    private let secondsPerMeasure: Double

    init(bpm: Double, timeSignature: TimeSignature, notes: [Note]) {
        precondition(bpm.isFinite && bpm > 0, "BPM must be finite and > 0, got: \(bpm)")
        precondition(timeSignature.beatsPerMeasure > 0, "beatsPerMeasure must be > 0, got: \(timeSignature.beatsPerMeasure)")
        self.timeSignature = timeSignature
        self.notes = notes
        self.secondsPerBeat = 60.0 / bpm
        self.secondsPerMeasure = self.secondsPerBeat * Double(timeSignature.beatsPerMeasure)
    }

    func calculateNoteMatch(for hit: InputHit, elapsedTime: Double) -> NoteMatchResult {
        let totalBeatsElapsed = elapsedTime / secondsPerBeat
        let measureNumber = Int(totalBeatsElapsed / Double(timeSignature.beatsPerMeasure)) + 1
        let beatWithinMeasure = totalBeatsElapsed.truncatingRemainder(dividingBy: Double(timeSignature.beatsPerMeasure))
        let measureOffset = beatWithinMeasure / Double(timeSignature.beatsPerMeasure)

        let matchedNote = findClosestNote(drumType: hit.drumType, elapsedTime: elapsedTime)
        let (timingAccuracy, timingError) = calculateTimingAccuracy(matchedNote: matchedNote, actualTime: elapsedTime)

        return NoteMatchResult(
            hitInput: hit,
            matchedNote: matchedNote,
            timingAccuracy: timingAccuracy,
            measureNumber: measureNumber,
            measureOffset: measureOffset,
            timingError: timingError
        )
    }

    private func findClosestNote(drumType: DrumType, elapsedTime: Double) -> Note? {
        let searchWindowSeconds = 0.2
        let candidateNotes = notes.filter { note in
            guard DrumType.from(noteType: note.noteType) == drumType else { return false }
            let noteElapsedTime = calculateExpectedTime(measureNumber: note.measureNumber, measureOffset: note.measureOffset)
            return abs(elapsedTime - noteElapsedTime) <= searchWindowSeconds
        }

        return candidateNotes.min { note1, note2 in
            let time1 = calculateExpectedTime(measureNumber: note1.measureNumber, measureOffset: note1.measureOffset)
            let time2 = calculateExpectedTime(measureNumber: note2.measureNumber, measureOffset: note2.measureOffset)
            return abs(elapsedTime - time1) < abs(elapsedTime - time2)
        }
    }

    private func calculateExpectedTime(measureNumber: Int, measureOffset: Double) -> Double {
        let measureIndex = measureNumber - 1
        return Double(measureIndex) * secondsPerMeasure + (measureOffset * secondsPerMeasure)
    }

    private func calculateTimingAccuracy(matchedNote: Note?, actualTime: Double) -> (TimingAccuracy, Double?) {
        guard let note = matchedNote else {
            return (.miss, nil)
        }

        let expectedTime = calculateExpectedTime(measureNumber: note.measureNumber, measureOffset: note.measureOffset)
        let timingErrorMs = (actualTime - expectedTime) * 1000.0
        let absErrorMs = abs(timingErrorMs)

        if absErrorMs <= TimingAccuracy.perfect.toleranceMs {
            return (.perfect, timingErrorMs)
        } else if absErrorMs <= TimingAccuracy.great.toleranceMs {
            return (.great, timingErrorMs)
        } else if absErrorMs <= TimingAccuracy.good.toleranceMs {
            return (.good, timingErrorMs)
        } else {
            return (.miss, timingErrorMs)
        }
    }
}
