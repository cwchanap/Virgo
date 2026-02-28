//
//  ScoreEngineTests.swift
//  VirgoTests
//
//  Unit tests for ScoreEngine - combo/scoring logic.
//  Written BEFORE implementation (TDD).
//

import Testing
@testable import Virgo

@Suite("ScoreEngine Tests")
struct ScoreEngineTests {

    // MARK: - Combo Multiplier Tiers

    @Test("Combo multiplier: 0-9 = 1.0x")
    func testComboMultiplierLow() {
        #expect(ScoreEngine.comboMultiplier(for: 0) == 1.0)
        #expect(ScoreEngine.comboMultiplier(for: 1) == 1.0)
        #expect(ScoreEngine.comboMultiplier(for: 9) == 1.0)
    }

    @Test("Combo multiplier: 10-24 = 1.5x")
    func testComboMultiplierTier2() {
        #expect(ScoreEngine.comboMultiplier(for: 10) == 1.5)
        #expect(ScoreEngine.comboMultiplier(for: 24) == 1.5)
    }

    @Test("Combo multiplier: 25-49 = 2.0x")
    func testComboMultiplierTier3() {
        #expect(ScoreEngine.comboMultiplier(for: 25) == 2.0)
        #expect(ScoreEngine.comboMultiplier(for: 49) == 2.0)
    }

    @Test("Combo multiplier: 50-99 = 2.5x")
    func testComboMultiplierTier4() {
        #expect(ScoreEngine.comboMultiplier(for: 50) == 2.5)
        #expect(ScoreEngine.comboMultiplier(for: 99) == 2.5)
    }

    @Test("Combo multiplier: 100+ = 3.0x")
    func testComboMultiplierTier5() {
        #expect(ScoreEngine.comboMultiplier(for: 100) == 3.0)
        #expect(ScoreEngine.comboMultiplier(for: 999) == 3.0)
    }

    // MARK: - processHit: Score Calculation

    @Test("Perfect hit at combo 1 earns 100 points (100 × 1.0 × 1.0)")
    func testPerfectHitScore() {
        var engine = ScoreEngine()
        engine.processHit(accuracy: .perfect)
        #expect(engine.score == 100)
        #expect(engine.combo == 1)
    }

    @Test("Great hit at combo 1 earns 80 points (100 × 0.8 × 1.0)")
    func testGreatHitScore() {
        var engine = ScoreEngine()
        engine.processHit(accuracy: .great)
        #expect(engine.score == 80)
        #expect(engine.combo == 1)
    }

    @Test("Good hit at combo 1 earns 50 points (100 × 0.5 × 1.0)")
    func testGoodHitScore() {
        var engine = ScoreEngine()
        engine.processHit(accuracy: .good)
        #expect(engine.score == 50)
        #expect(engine.combo == 1)
    }

    @Test("Miss earns 0 points and breaks combo")
    func testMissEarnsZeroAndBreaksCombo() {
        var engine = ScoreEngine()
        engine.processHit(accuracy: .perfect)
        engine.processHit(accuracy: .perfect)
        #expect(engine.combo == 2)
        engine.processHit(accuracy: .miss)
        #expect(engine.score == 200) // unchanged from the 2 perfect hits
        #expect(engine.combo == 0)
    }

    @Test("Perfect hit at combo 10 earns 150 points (100 × 1.0 × 1.5)")
    func testPerfectHitAt10Combo() {
        var engine = ScoreEngine()
        // Build to combo 9 first
        for _ in 0..<9 {
            engine.processHit(accuracy: .perfect)
        }
        let scoreAtCombo9 = engine.score
        engine.processHit(accuracy: .perfect) // combo becomes 10
        #expect(engine.combo == 10)
        #expect(engine.score == scoreAtCombo9 + 150) // 100 × 1.0 × 1.5
    }

    @Test("Great hit at combo 10 earns 120 points (100 × 0.8 × 1.5)")
    func testGreatHitAt10Combo() {
        var engine = ScoreEngine()
        for _ in 0..<9 {
            engine.processHit(accuracy: .perfect)
        }
        let scoreAtCombo9 = engine.score
        engine.processHit(accuracy: .great) // combo becomes 10
        #expect(engine.score == scoreAtCombo9 + 120) // 100 × 0.8 × 1.5
    }

    @Test("Perfect hit at combo 25 earns 200 points (100 × 1.0 × 2.0)")
    func testPerfectHitAt25Combo() {
        var engine = ScoreEngine()
        for _ in 0..<24 {
            engine.processHit(accuracy: .perfect)
        }
        let scoreAtCombo24 = engine.score
        engine.processHit(accuracy: .perfect) // combo becomes 25
        #expect(engine.score == scoreAtCombo24 + 200)
    }

    @Test("Perfect hit at combo 100 earns 300 points (100 × 1.0 × 3.0)")
    func testPerfectHitAt100Combo() {
        var engine = ScoreEngine()
        for _ in 0..<99 {
            engine.processHit(accuracy: .perfect)
        }
        let scoreAt99 = engine.score
        engine.processHit(accuracy: .perfect) // combo becomes 100
        #expect(engine.score == scoreAt99 + 300)
    }

    // MARK: - processHit: Combo Tracking

    @Test("Consecutive hits increment combo")
    func testConsecutiveHitsIncrementCombo() {
        var engine = ScoreEngine()
        engine.processHit(accuracy: .perfect)
        engine.processHit(accuracy: .great)
        engine.processHit(accuracy: .good)
        #expect(engine.combo == 3)
    }

    @Test("Miss after combo resets combo to 0")
    func testMissResetsCombo() {
        var engine = ScoreEngine()
        engine.processHit(accuracy: .perfect)
        engine.processHit(accuracy: .perfect)
        engine.processHit(accuracy: .miss)
        #expect(engine.combo == 0)
    }

    @Test("maxCombo tracks highest combo reached")
    func testMaxComboTracking() {
        var engine = ScoreEngine()
        engine.processHit(accuracy: .perfect)
        engine.processHit(accuracy: .perfect)
        engine.processHit(accuracy: .perfect)
        engine.processHit(accuracy: .miss)
        engine.processHit(accuracy: .perfect)
        #expect(engine.maxCombo == 3)
        #expect(engine.combo == 1)
    }

    // MARK: - processMissedNote

    @Test("processMissedNote breaks combo without adding score")
    func testMissedNoteBreaksCombo() {
        var engine = ScoreEngine()
        engine.processHit(accuracy: .perfect)
        engine.processHit(accuracy: .perfect)
        #expect(engine.combo == 2)
        let scoreBefore = engine.score
        engine.processMissedNote()
        #expect(engine.combo == 0)
        #expect(engine.score == scoreBefore) // score unchanged
    }

    @Test("processMissedNote at combo 0 is idempotent")
    func testMissedNoteAtZeroComboIsIdempotent() {
        var engine = ScoreEngine()
        engine.processMissedNote()
        #expect(engine.combo == 0)
        #expect(engine.score == 0)
    }

    @Test("processMissedNote increments missCount")
    func testMissedNoteIncrementsMissCount() {
        var engine = ScoreEngine()
        engine.processMissedNote()
        engine.processMissedNote()
        #expect(engine.missCount == 2)
    }

    // MARK: - Hit Count Tracking

    @Test("processHit tracks perfectCount, greatCount, goodCount, missCount")
    func testHitCountTracking() {
        var engine = ScoreEngine()
        engine.processHit(accuracy: .perfect)
        engine.processHit(accuracy: .perfect)
        engine.processHit(accuracy: .great)
        engine.processHit(accuracy: .good)
        engine.processHit(accuracy: .miss)
        #expect(engine.perfectCount == 2)
        #expect(engine.greatCount == 1)
        #expect(engine.goodCount == 1)
        #expect(engine.missCount == 1)
    }

    // MARK: - Reset

    @Test("reset clears all state to zero")
    func testReset() {
        var engine = ScoreEngine()
        engine.processHit(accuracy: .perfect)
        engine.processHit(accuracy: .perfect)
        engine.processHit(accuracy: .miss)
        engine.reset()
        #expect(engine.score == 0)
        #expect(engine.combo == 0)
        #expect(engine.maxCombo == 0)
        #expect(engine.perfectCount == 0)
        #expect(engine.greatCount == 0)
        #expect(engine.goodCount == 0)
        #expect(engine.missCount == 0)
    }

    // MARK: - Milestone Detection

    @Test("milestone returns 10 when crossing from 9 to 10")
    func testMilestone10() {
        #expect(ScoreEngine.milestone(crossedFrom: 9, to: 10) == 10)
    }

    @Test("milestone returns 25 when crossing from 24 to 25")
    func testMilestone25() {
        #expect(ScoreEngine.milestone(crossedFrom: 24, to: 25) == 25)
    }

    @Test("milestone returns 50 when crossing from 49 to 50")
    func testMilestone50() {
        #expect(ScoreEngine.milestone(crossedFrom: 49, to: 50) == 50)
    }

    @Test("milestone returns 100 when crossing from 99 to 100")
    func testMilestone100() {
        #expect(ScoreEngine.milestone(crossedFrom: 99, to: 100) == 100)
    }

    @Test("milestone returns nil for non-milestone crossings")
    func testMilestoneNil() {
        #expect(ScoreEngine.milestone(crossedFrom: 0, to: 1) == nil)
        #expect(ScoreEngine.milestone(crossedFrom: 8, to: 9) == nil)
        #expect(ScoreEngine.milestone(crossedFrom: 10, to: 11) == nil)
    }

    @Test("milestone returns nil when combo resets (prev > current)")
    func testMilestoneNilOnReset() {
        #expect(ScoreEngine.milestone(crossedFrom: 10, to: 0) == nil)
    }

    // MARK: - SessionResult

    @Test("sessionResult reports correct totals")
    func testSessionResult() {
        var engine = ScoreEngine()
        engine.processHit(accuracy: .perfect)
        engine.processHit(accuracy: .great)
        engine.processHit(accuracy: .miss)
        engine.processMissedNote()

        let result = engine.sessionResult(totalNotes: 10, previousHighScore: 0)
        #expect(result.finalScore == engine.score)
        #expect(result.maxCombo == engine.maxCombo)
        #expect(result.perfectCount == 1)
        #expect(result.greatCount == 1)
        #expect(result.goodCount == 0)
        #expect(result.missCount == 2) // 1 from processHit(.miss) + 1 from processMissedNote
        #expect(result.totalNotes == 10)
    }

    @Test("sessionResult isNewHighScore true when score beats previous")
    func testSessionResultNewHighScore() {
        var engine = ScoreEngine()
        engine.processHit(accuracy: .perfect)
        let result = engine.sessionResult(totalNotes: 1, previousHighScore: 50)
        #expect(result.isNewHighScore == true)
    }

    @Test("sessionResult isNewHighScore false when score does not beat previous")
    func testSessionResultNotNewHighScore() {
        var engine = ScoreEngine()
        engine.processHit(accuracy: .good)
        let result = engine.sessionResult(totalNotes: 1, previousHighScore: 1000)
        #expect(result.isNewHighScore == false)
    }

    // MARK: - Timing Deviation: Data Collection

    @Test("Timing deviations stored for non-miss hits")
    func testTimingDeviationTracking() {
        var engine = ScoreEngine()
        engine.processHit(accuracy: .perfect, timingError: -10.0)
        engine.processHit(accuracy: .great, timingError: 20.0)
        engine.processHit(accuracy: .good, timingError: 5.0)
        #expect(engine.timingDeviations == [-10.0, 20.0, 5.0])
    }

    @Test("Timing deviations not stored for miss hits")
    func testTimingDataNotStoredForMisses() {
        var engine = ScoreEngine()
        engine.processHit(accuracy: .miss, timingError: 30.0)
        engine.processHit(accuracy: .perfect, timingError: nil)
        #expect(engine.timingDeviations.isEmpty)
    }

    @Test("reset() clears timing deviations")
    func testResetClearsTimingData() {
        var engine = ScoreEngine()
        engine.processHit(accuracy: .perfect, timingError: -5.0)
        engine.processHit(accuracy: .great, timingError: 10.0)
        engine.reset()
        #expect(engine.timingDeviations.isEmpty)
    }

    // MARK: - Timing Deviation: Computed Stats

    @Test("averageTimingDeviation is nil when no timing data")
    func testAverageTimingDeviationNilWhenEmpty() {
        let engine = ScoreEngine()
        #expect(engine.averageTimingDeviation == nil)
    }

    @Test("averageTimingDeviation computes mean correctly")
    func testAverageTimingDeviation() {
        var engine = ScoreEngine()
        engine.processHit(accuracy: .perfect, timingError: -10.0)
        engine.processHit(accuracy: .perfect, timingError: 10.0)
        engine.processHit(accuracy: .perfect, timingError: -5.0)
        // mean = (-10 + 10 + -5) / 3 = -5/3 ≈ -1.667
        #expect(engine.averageTimingDeviation != nil)
        #expect(abs(engine.averageTimingDeviation! - (-5.0 / 3.0)) < 0.001)
    }

    @Test("earlyCount and lateCount correct with mixed timing data")
    func testEarlyLateBreakdown() {
        var engine = ScoreEngine()
        engine.processHit(accuracy: .perfect, timingError: -15.0)
        engine.processHit(accuracy: .perfect, timingError: -8.0)
        engine.processHit(accuracy: .perfect, timingError: 12.0)
        #expect(engine.earlyCount == 2)
        #expect(engine.lateCount == 1)
    }

    @Test("timingTendency returns .early when average < -5ms")
    func testTimingTendencyEarly() {
        var engine = ScoreEngine()
        engine.processHit(accuracy: .perfect, timingError: -20.0)
        engine.processHit(accuracy: .perfect, timingError: -15.0)
        #expect(engine.timingTendency == .early)
    }

    @Test("timingTendency returns .late when average > +5ms")
    func testTimingTendencyLate() {
        var engine = ScoreEngine()
        engine.processHit(accuracy: .perfect, timingError: 20.0)
        engine.processHit(accuracy: .perfect, timingError: 10.0)
        #expect(engine.timingTendency == .late)
    }

    @Test("timingTendency returns .balanced when average is within ±5ms")
    func testTimingTendencyBalanced() {
        var engine = ScoreEngine()
        engine.processHit(accuracy: .perfect, timingError: -3.0)
        engine.processHit(accuracy: .perfect, timingError: 3.0)
        #expect(engine.timingTendency == .balanced)
    }

    @Test("timingTendency returns .balanced when no timing data")
    func testTimingTendencyBalancedWhenEmpty() {
        let engine = ScoreEngine()
        #expect(engine.timingTendency == .balanced)
    }

    // MARK: - Accuracy Percentage

    @Test("accuracyPercentage is 100% when all hits are perfect")
    func testAccuracyPercentageAllPerfect() {
        var engine = ScoreEngine()
        for _ in 0..<10 { engine.processHit(accuracy: .perfect) }
        #expect(engine.accuracyPercentage == 100.0)
    }

    @Test("accuracyPercentage is 0% when no notes played")
    func testAccuracyPercentageNoNotes() {
        let engine = ScoreEngine()
        #expect(engine.accuracyPercentage == 0.0)
    }

    @Test("accuracyPercentage correct with mix of hits and misses")
    func testAccuracyPercentageWithMisses() {
        var engine = ScoreEngine()
        for _ in 0..<8 { engine.processHit(accuracy: .perfect) }
        for _ in 0..<2 { engine.processHit(accuracy: .miss) }
        #expect(engine.accuracyPercentage == 80.0)
    }

    // MARK: - SessionResult: Timing Data

    @Test("sessionResult includes timing statistics")
    func testSessionResultIncludesTimingData() {
        var engine = ScoreEngine()
        engine.processHit(accuracy: .perfect, timingError: -10.0)
        engine.processHit(accuracy: .great, timingError: 20.0)
        engine.processHit(accuracy: .miss)

        let result = engine.sessionResult(totalNotes: 3, previousHighScore: 0)
        #expect(result.accuracyPercentage == (2.0 / 3.0) * 100.0)
        #expect(result.timingDeviations == [-10.0, 20.0])
        #expect(result.earlyCount == 1)
        #expect(result.lateCount == 1)
        #expect(result.averageTimingDeviation != nil)
        #expect(abs(result.averageTimingDeviation! - 5.0) < 0.001)
        #expect(result.timingTendency == .balanced)
    }
}
