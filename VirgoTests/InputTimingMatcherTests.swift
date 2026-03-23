//
//  InputTimingMatcherTests.swift
//  VirgoTests
//

import Testing
@testable import Virgo

@Suite("InputTimingMatcher Tests")
@MainActor
struct InputTimingMatcherTests {
    private func makeNote(
        noteType: NoteType,
        measureNumber: Int,
        measureOffset: Double
    ) -> Note {
        Note(
            interval: .quarter,
            noteType: noteType,
            measureNumber: measureNumber,
            measureOffset: measureOffset
        )
    }

    @Test("calculateNoteMatch chooses the closest matching note inside the search window")
    func testCalculateNoteMatchChoosesClosestMatchingNote() {
        let earlierKick = makeNote(noteType: .bass, measureNumber: 1, measureOffset: 0.45)
        let targetKick = makeNote(noteType: .bass, measureNumber: 1, measureOffset: 0.50)
        let unrelatedSnare = makeNote(noteType: .snare, measureNumber: 1, measureOffset: 0.50)

        let matcher = InputTimingMatcher(
            bpm: 120.0,
            timeSignature: .fourFour,
            notes: [earlierKick, targetKick, unrelatedSnare]
        )
        let hit = InputHit(
            drumType: .kick,
            velocity: 0.8,
            timestamp: Date(timeIntervalSinceReferenceDate: 123)
        )

        let result = matcher.calculateNoteMatch(for: hit, elapsedTime: 1.01)

        #expect(result.matchedNote === targetKick)
        #expect(result.measureNumber == 1)
        #expect(abs(result.measureOffset - 0.505) < 0.0001)
        #expect(result.timingAccuracy == .perfect)
        #expect(abs((result.timingError ?? 0) - 10.0) < 0.0001)
    }

    @Test("calculateNoteMatch returns miss when no matching note falls inside the search window")
    func testCalculateNoteMatchReturnsMissWhenNoCandidateMatches() {
        let distantKick = makeNote(noteType: .bass, measureNumber: 1, measureOffset: 0.0)
        let matcher = InputTimingMatcher(
            bpm: 120.0,
            timeSignature: .fourFour,
            notes: [distantKick]
        )
        let hit = InputHit(
            drumType: .kick,
            velocity: 1.0,
            timestamp: Date(timeIntervalSinceReferenceDate: 200)
        )

        let result = matcher.calculateNoteMatch(for: hit, elapsedTime: 0.8)

        #expect(result.matchedNote == nil)
        #expect(result.timingAccuracy == .miss)
        #expect(result.timingError == nil)
        #expect(result.measureNumber == 1)
        #expect(abs(result.measureOffset - 0.4) < 0.0001)
    }

    @Test("calculateNoteMatch classifies great and good timing windows")
    func testCalculateNoteMatchClassifiesGreatAndGoodHits() {
        let targetSnare = makeNote(noteType: .snare, measureNumber: 1, measureOffset: 0.25)
        let matcher = InputTimingMatcher(
            bpm: 120.0,
            timeSignature: .fourFour,
            notes: [targetSnare]
        )
        let hit = InputHit(
            drumType: .snare,
            velocity: 0.9,
            timestamp: Date(timeIntervalSinceReferenceDate: 300)
        )

        let greatResult = matcher.calculateNoteMatch(for: hit, elapsedTime: 0.54)
        let goodResult = matcher.calculateNoteMatch(for: hit, elapsedTime: 0.58)

        #expect(greatResult.timingAccuracy == .great)
        #expect(abs((greatResult.timingError ?? 0) - 40.0) < 0.0001)
        #expect(goodResult.timingAccuracy == .good)
        #expect(abs((goodResult.timingError ?? 0) - 80.0) < 0.0001)

        // Lock in inclusive/exclusive boundary behavior around each threshold.
        // expectedTime = 0.5s (measureNumber=1, measureOffset=0.25, bpm=120, 4/4)
        // Decimal ms thresholds (25, 50, 100) cannot be represented exactly in binary
        // floating point, so we use values clearly inside and just past each boundary.
        let insidePerfect = matcher.calculateNoteMatch(for: hit, elapsedTime: 0.524) // ~24ms
        #expect(insidePerfect.timingAccuracy == .perfect)
        #expect(abs((insidePerfect.timingError ?? 0) - 24.0) < 0.2)

        let pastPerfect = matcher.calculateNoteMatch(for: hit, elapsedTime: 0.526) // ~26ms
        #expect(pastPerfect.timingAccuracy == .great)
        #expect(abs((pastPerfect.timingError ?? 0) - 26.0) < 0.2)

        let insideGreat = matcher.calculateNoteMatch(for: hit, elapsedTime: 0.549) // ~49ms
        #expect(insideGreat.timingAccuracy == .great)
        #expect(abs((insideGreat.timingError ?? 0) - 49.0) < 0.2)

        let pastGreat = matcher.calculateNoteMatch(for: hit, elapsedTime: 0.551) // ~51ms
        #expect(pastGreat.timingAccuracy == .good)
        #expect(abs((pastGreat.timingError ?? 0) - 51.0) < 0.2)

        let insideGood = matcher.calculateNoteMatch(for: hit, elapsedTime: 0.599) // ~99ms
        #expect(insideGood.timingAccuracy == .good)
        #expect(abs((insideGood.timingError ?? 0) - 99.0) < 0.2)

        let pastGood = matcher.calculateNoteMatch(for: hit, elapsedTime: 0.601) // ~101ms
        #expect(pastGood.timingAccuracy == .miss)
        #expect(abs((pastGood.timingError ?? 0) - 101.0) < 0.2)
    }

    @Test("calculateNoteMatch preserves negative timing error for early hits in later measures")
    func testCalculateNoteMatchPreservesNegativeTimingErrorForEarlyHits() {
        let laterKick = makeNote(noteType: .bass, measureNumber: 2, measureOffset: 0.25)
        let matcher = InputTimingMatcher(
            bpm: 120.0,
            timeSignature: .fourFour,
            notes: [laterKick]
        )
        let hit = InputHit(
            drumType: .kick,
            velocity: 0.7,
            timestamp: Date(timeIntervalSinceReferenceDate: 400)
        )

        let result = matcher.calculateNoteMatch(for: hit, elapsedTime: 2.42)

        #expect(result.matchedNote === laterKick)
        #expect(result.measureNumber == 2)
        #expect(abs(result.measureOffset - 0.21) < 0.0001)
        #expect(result.timingAccuracy == .good)
        #expect(abs((result.timingError ?? 0) + 80.0) < 0.0001)
    }
}
