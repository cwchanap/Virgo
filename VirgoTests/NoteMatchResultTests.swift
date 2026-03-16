//
//  NoteMatchResultTests.swift
//  VirgoTests
//
//  Unit tests for NoteMatchResult and InputHit value types.
//

import Testing
import Foundation
@testable import Virgo

@Suite("InputHit Tests")
struct InputHitTests {

    @Test("InputHit stores drumType, velocity, and timestamp")
    func testInputHitInitialization() {
        let timestamp = Date()
        let hit = InputHit(drumType: .snare, velocity: 0.8, timestamp: timestamp)
        #expect(hit.drumType == .snare)
        #expect(hit.velocity == 0.8)
        #expect(hit.timestamp == timestamp)
    }

    @Test("InputHit accepts minimum velocity 0.0")
    func testInputHitMinVelocity() {
        let hit = InputHit(drumType: .kick, velocity: 0.0, timestamp: Date())
        #expect(hit.velocity == 0.0)
    }

    @Test("InputHit accepts maximum velocity 1.0")
    func testInputHitMaxVelocity() {
        let hit = InputHit(drumType: .kick, velocity: 1.0, timestamp: Date())
        #expect(hit.velocity == 1.0)
    }

    @Test("InputHit stores all DrumType values without error")
    func testInputHitAllDrumTypes() {
        for drumType in DrumType.allCases {
            let hit = InputHit(drumType: drumType, velocity: 1.0, timestamp: Date())
            #expect(hit.drumType == drumType)
        }
    }

    @Test("InputHit timestamps are distinct when created at different times")
    func testInputHitTimestampDistinctness() async throws {
        let hit1 = InputHit(drumType: .snare, velocity: 1.0, timestamp: Date())
        try await Task.sleep(nanoseconds: 1_000_000) // 1ms
        let hit2 = InputHit(drumType: .snare, velocity: 1.0, timestamp: Date())
        #expect(hit2.timestamp > hit1.timestamp)
    }

    @Test("InputHit is Sendable - can be used across concurrency boundaries")
    func testInputHitSendable() async {
        let hit = InputHit(drumType: .hiHat, velocity: 0.5, timestamp: Date())
        let result = await Task.detached {
            // Access hit from a different task to verify Sendable conformance works
            return hit.drumType
        }.value
        #expect(result == .hiHat)
    }
}

@Suite("NoteMatchResult Tests")
struct NoteMatchResultTests {

    private func makeNote(measure: Int = 1, offset: Double = 0.0) -> Note {
        Note(interval: .quarter, noteType: .snare, measureNumber: measure, measureOffset: offset)
    }

    private func makeHit(drumType: DrumType = .snare) -> InputHit {
        InputHit(drumType: drumType, velocity: 1.0, timestamp: Date())
    }

    // MARK: - Initialization

    @Test("NoteMatchResult stores all properties correctly for a perfect hit")
    func testPerfectHitInitialization() {
        let hit = makeHit()
        let note = makeNote()
        let result = NoteMatchResult(
            hitInput: hit,
            matchedNote: note,
            timingAccuracy: .perfect,
            measureNumber: 1,
            measureOffset: 0.0,
            timingError: -5.0
        )
        #expect(result.timingAccuracy == .perfect)
        #expect(result.matchedNote != nil)
        #expect(result.measureNumber == 1)
        #expect(result.measureOffset == 0.0)
        #expect(result.timingError == -5.0)
    }

    @Test("NoteMatchResult allows nil matchedNote for a miss")
    func testMissHasNilMatchedNote() {
        let hit = makeHit()
        let result = NoteMatchResult(
            hitInput: hit,
            matchedNote: nil,
            timingAccuracy: .miss,
            measureNumber: 1,
            measureOffset: 0.0,
            timingError: nil
        )
        #expect(result.matchedNote == nil)
        #expect(result.timingAccuracy == .miss)
        #expect(result.timingError == nil)
    }

    @Test("NoteMatchResult allows nil timingError for miss")
    func testMissTimingErrorIsNil() {
        let result = NoteMatchResult(
            hitInput: makeHit(),
            matchedNote: nil,
            timingAccuracy: .miss,
            measureNumber: 2,
            measureOffset: 0.5,
            timingError: nil
        )
        #expect(result.timingError == nil)
    }

    @Test("NoteMatchResult stores positive timingError (late hit)")
    func testLateHitTimingError() {
        let result = NoteMatchResult(
            hitInput: makeHit(),
            matchedNote: makeNote(),
            timingAccuracy: .great,
            measureNumber: 1,
            measureOffset: 0.25,
            timingError: 35.0 // 35ms late
        )
        #expect(result.timingError == 35.0)
        if let error = result.timingError {
            #expect(error > 0) // late = positive
        }
    }

    @Test("NoteMatchResult stores negative timingError (early hit)")
    func testEarlyHitTimingError() {
        let result = NoteMatchResult(
            hitInput: makeHit(),
            matchedNote: makeNote(),
            timingAccuracy: .great,
            measureNumber: 1,
            measureOffset: 0.0,
            timingError: -30.0 // 30ms early
        )
        #expect(result.timingError == -30.0)
        if let error = result.timingError {
            #expect(error < 0) // early = negative
        }
    }

    @Test("NoteMatchResult preserves measure number and offset for multi-measure songs")
    func testMultiMeasurePosition() {
        let result = NoteMatchResult(
            hitInput: makeHit(),
            matchedNote: makeNote(measure: 5, offset: 0.75),
            timingAccuracy: .good,
            measureNumber: 5,
            measureOffset: 0.75,
            timingError: 80.0
        )
        #expect(result.measureNumber == 5)
        #expect(result.measureOffset == 0.75)
    }

    @Test("NoteMatchResult hitInput stores the original drum hit")
    func testHitInputPreserved() {
        let hit = InputHit(drumType: .crash, velocity: 0.7, timestamp: Date())
        let result = NoteMatchResult(
            hitInput: hit,
            matchedNote: nil,
            timingAccuracy: .miss,
            measureNumber: 1,
            measureOffset: 0.0,
            timingError: nil
        )
        #expect(result.hitInput.drumType == .crash)
        #expect(result.hitInput.velocity == 0.7)
    }

    // MARK: - Accuracy-timingError Consistency

    @Test("Perfect result has timingError within ±25ms")
    func testPerfectResultTimingErrorRange() {
        let errors: [Double] = [-25.0, -10.0, 0.0, 10.0, 25.0]
        for error in errors {
            let result = NoteMatchResult(
                hitInput: makeHit(),
                matchedNote: makeNote(),
                timingAccuracy: .perfect,
                measureNumber: 1,
                measureOffset: 0.0,
                timingError: error
            )
            // Verify the stored error is within perfect tolerance
            if let e = result.timingError {
                #expect(abs(e) <= TimingAccuracy.perfect.toleranceMs,
                        "Error \(e)ms exceeds perfect tolerance for perfect result")
            }
        }
    }

    @Test("Miss result with nil timingError does not pollute timing statistics")
    func testMissNilTimingErrorDoesNotAddToDeviations() {
        var engine = ScoreEngine()
        let missResult = NoteMatchResult(
            hitInput: makeHit(),
            matchedNote: nil,
            timingAccuracy: .miss,
            measureNumber: 1,
            measureOffset: 0.0,
            timingError: nil
        )
        // Simulate what GameplayViewModel.recordHit does
        engine.processHit(accuracy: missResult.timingAccuracy, timingError: missResult.timingError)
        #expect(engine.timingDeviations.isEmpty)
        #expect(engine.earlyCount == 0)
        #expect(engine.lateCount == 0)
    }

    @Test("Perfect result with timingError adds deviation to ScoreEngine")
    func testPerfectTimingErrorAddsDeviation() {
        var engine = ScoreEngine()
        let result = NoteMatchResult(
            hitInput: makeHit(),
            matchedNote: makeNote(),
            timingAccuracy: .perfect,
            measureNumber: 1,
            measureOffset: 0.0,
            timingError: -8.0
        )
        engine.processHit(accuracy: result.timingAccuracy, timingError: result.timingError)
        #expect(engine.timingDeviations == [-8.0])
        #expect(engine.earlyCount == 1)
        #expect(engine.lateCount == 0)
    }
}
