//
//  ScoreEngineEdgeCaseTests.swift
//  VirgoTests
//
//  Edge-case and extended tests for ScoreEngine not covered by ScoreEngineTests.swift.
//

import Testing
@testable import Virgo

@Suite("ScoreEngine Edge Case Tests")
struct ScoreEngineEdgeCaseTests {

    // MARK: - Large Combo Sequences

    @Test("Score is correct after 100 consecutive perfect hits (max multiplier)")
    func testScoreAfter100PerfectHits() {
        var engine = ScoreEngine()
        // Hits 1-9: 100 pts each (1.0x) = 900
        // Hits 10-24: 150 pts each (1.5x) = 2250
        // Hits 25-49: 200 pts each (2.0x) = 5000
        // Hits 50-99: 250 pts each (2.5x) = 12500
        // Hit 100: 300 pts (3.0x)
        for _ in 1...100 {
            engine.processHit(accuracy: .perfect)
        }
        let expectedScore = 9 * 100 + 15 * 150 + 25 * 200 + 50 * 250 + 1 * 300
        #expect(engine.score == expectedScore)
        #expect(engine.combo == 100)
        #expect(engine.maxCombo == 100)
        #expect(engine.perfectCount == 100)
    }

    @Test("Score continues accumulating past combo 100 at 3.0x multiplier")
    func testScoreAccumulatesPastCombo100() {
        var engine = ScoreEngine()
        for _ in 0..<100 {
            engine.processHit(accuracy: .perfect)
        }
        let scoreAt100 = engine.score
        engine.processHit(accuracy: .perfect) // combo 101
        #expect(engine.score == scoreAt100 + 300) // still 3.0x
        engine.processHit(accuracy: .perfect) // combo 102
        #expect(engine.score == scoreAt100 + 600)
    }

    // MARK: - Multiple Miss / Combo Reset Cycles

    @Test("maxCombo persists across multiple combo build-reset cycles")
    func testMaxComboPersistsAcrossResetCycles() {
        var engine = ScoreEngine()
        // First cycle: combo 5
        for _ in 0..<5 { engine.processHit(accuracy: .perfect) }
        engine.processHit(accuracy: .miss)
        // Second cycle: combo 3
        for _ in 0..<3 { engine.processHit(accuracy: .perfect) }
        engine.processHit(accuracy: .miss)
        // Third cycle: combo 7 — new record
        for _ in 0..<7 { engine.processHit(accuracy: .perfect) }

        #expect(engine.maxCombo == 7)
        #expect(engine.combo == 7)
    }

    @Test("Multiple misses in a row keep combo at 0")
    func testMultipleMissesKeepComboAtZero() {
        var engine = ScoreEngine()
        for _ in 0..<5 { engine.processHit(accuracy: .miss) }
        #expect(engine.combo == 0)
        #expect(engine.missCount == 5)
        #expect(engine.score == 0)
    }

    // MARK: - Mixed Accuracy Sequences

    @Test("Score accumulates correctly through mixed accuracy sequence")
    func testMixedAccuracySequence() {
        var engine = ScoreEngine()
        engine.processHit(accuracy: .perfect) // combo 1, 100pts
        engine.processHit(accuracy: .great)   // combo 2, 80pts
        engine.processHit(accuracy: .good)    // combo 3, 50pts
        engine.processHit(accuracy: .miss)    // combo resets
        engine.processHit(accuracy: .perfect) // combo 1, 100pts

        #expect(engine.score == 100 + 80 + 50 + 100)
        #expect(engine.combo == 1)
        #expect(engine.perfectCount == 2)
        #expect(engine.greatCount == 1)
        #expect(engine.goodCount == 1)
        #expect(engine.missCount == 1)
    }

    // MARK: - reset() Idempotency

    @Test("Calling reset() on a fresh engine leaves state at zero")
    func testResetOnFreshEngineIsIdempotent() {
        var engine = ScoreEngine()
        engine.reset()
        #expect(engine.score == 0)
        #expect(engine.combo == 0)
        #expect(engine.maxCombo == 0)
        #expect(engine.perfectCount == 0)
        #expect(engine.greatCount == 0)
        #expect(engine.goodCount == 0)
        #expect(engine.missCount == 0)
        #expect(engine.timingDeviations.isEmpty)
    }

    @Test("Calling reset() twice clears state both times")
    func testDoubleReset() {
        var engine = ScoreEngine()
        for _ in 0..<10 { engine.processHit(accuracy: .perfect) }
        engine.reset()
        engine.processHit(accuracy: .great)
        engine.reset()
        #expect(engine.score == 0)
        #expect(engine.perfectCount == 0)
        #expect(engine.greatCount == 0)
    }

    // MARK: - comboMultiplier Tier Boundaries

    @Test("comboMultiplier at boundary values matches expected tiers")
    func testComboMultiplierBoundaries() {
        // Tier transitions at 10, 25, 50, 100
        #expect(ScoreEngine.comboMultiplier(for: 9) == 1.0)
        #expect(ScoreEngine.comboMultiplier(for: 10) == 1.5)
        #expect(ScoreEngine.comboMultiplier(for: 24) == 1.5)
        #expect(ScoreEngine.comboMultiplier(for: 25) == 2.0)
        #expect(ScoreEngine.comboMultiplier(for: 49) == 2.0)
        #expect(ScoreEngine.comboMultiplier(for: 50) == 2.5)
        #expect(ScoreEngine.comboMultiplier(for: 99) == 2.5)
        #expect(ScoreEngine.comboMultiplier(for: 100) == 3.0)
        #expect(ScoreEngine.comboMultiplier(for: 10000) == 3.0)
    }

    // MARK: - milestone() Edge Cases

    @Test("milestone returns nil when both values are the same")
    func testMilestoneNilWhenSameValues() {
        #expect(ScoreEngine.milestone(crossedFrom: 10, to: 10) == nil)
        #expect(ScoreEngine.milestone(crossedFrom: 25, to: 25) == nil)
        #expect(ScoreEngine.milestone(crossedFrom: 50, to: 50) == nil)
    }

    @Test("milestone returns nil when jumping past a milestone without crossing")
    func testMilestoneNilForJumpPastMilestone() {
        // If prev is already 10, crossing to 11 doesn't hit a new milestone
        #expect(ScoreEngine.milestone(crossedFrom: 10, to: 11) == nil)
        #expect(ScoreEngine.milestone(crossedFrom: 25, to: 26) == nil)
    }

    @Test("milestone correctly detects crossing exactly to milestone")
    func testMilestoneDetectsExactCrossing() {
        // Use crossedFrom = milestone - 1 so the combo was just below
        #expect(ScoreEngine.milestone(crossedFrom: 9, to: 10) == 10)
        #expect(ScoreEngine.milestone(crossedFrom: 24, to: 25) == 25)
        #expect(ScoreEngine.milestone(crossedFrom: 49, to: 50) == 50)
        #expect(ScoreEngine.milestone(crossedFrom: 99, to: 100) == 100)
    }

    @Test("milestone returns first (lowest) milestone when prev=0 and to spans multiple milestones")
    func testMilestoneReturnsFirstInRange() {
        // Jumping from 0 to 100 crosses 10, 25, 50, and 100;
        // milestone returns the first (lowest) one found — 10.
        let result = ScoreEngine.milestone(crossedFrom: 0, to: 100)
        #expect(result == 10)
    }

    // MARK: - totalHits / totalNotes

    @Test("totalHits is 0 on fresh engine")
    func testTotalHitsInitiallyZero() {
        let engine = ScoreEngine()
        #expect(engine.totalHits == 0)
        #expect(engine.totalNotes == 0)
    }

    @Test("totalNotes counts both hits and misses")
    func testTotalNotesCounts() {
        var engine = ScoreEngine()
        engine.processHit(accuracy: .perfect)
        engine.processHit(accuracy: .great)
        engine.processHit(accuracy: .miss)
        engine.processMissedNote()
        // totalHits = 2 (perfect + great), missCount = 2 (miss + missedNote)
        #expect(engine.totalHits == 2)
        #expect(engine.totalNotes == 4)
    }

    // MARK: - accuracyPercentage

    @Test("accuracyPercentage is 0 with only misses")
    func testAccuracyPercentageAllMisses() {
        var engine = ScoreEngine()
        for _ in 0..<5 { engine.processHit(accuracy: .miss) }
        #expect(engine.accuracyPercentage == 0.0)
    }

    @Test("accuracyPercentage rounds correctly for mixed counts")
    func testAccuracyPercentageMixed() {
        var engine = ScoreEngine()
        for _ in 0..<3 { engine.processHit(accuracy: .perfect) }
        engine.processHit(accuracy: .miss)
        // 3 hits, 1 miss, 4 total → 75%
        #expect(abs(engine.accuracyPercentage - 75.0) < 0.001)
    }

    // MARK: - sessionResult()

    @Test("sessionResult uses provided totalNotes parameter, not internal counter")
    func testSessionResultUsesProvidedTotalNotes() {
        var engine = ScoreEngine()
        engine.processHit(accuracy: .perfect)
        // Internal totalNotes = 1, but we pass 10 (for notes not yet processed)
        let result = engine.sessionResult(totalNotes: 10, previousHighScore: 0)
        #expect(result.totalNotes == 10)
    }

    @Test("sessionResult isNewHighScore false when tied with previous")
    func testSessionResultTiedHighScoreIsNotNew() {
        var engine = ScoreEngine()
        engine.processHit(accuracy: .perfect) // score = 100
        let result = engine.sessionResult(totalNotes: 1, previousHighScore: 100)
        // score (100) is NOT > previous (100), so isNewHighScore = false
        #expect(result.isNewHighScore == false)
    }

    @Test("sessionResult timingTendency computed from deviations at session end")
    func testSessionResultTimingTendency() {
        var engine = ScoreEngine()
        engine.processHit(accuracy: .perfect, timingError: -20.0)
        engine.processHit(accuracy: .perfect, timingError: -10.0)
        // avg = -15ms → early
        let result = engine.sessionResult(totalNotes: 2, previousHighScore: 0)
        #expect(result.timingTendency == .early)
    }

    // MARK: - Timing Deviation Running Sum Accuracy

    @Test("averageTimingDeviation is O(1) and matches manual mean calculation")
    func testAverageTimingDeviationIsAccurate() {
        var engine = ScoreEngine()
        let deviations = [-20.0, 15.0, -5.0, 30.0, -10.0]
        for dev in deviations {
            engine.processHit(accuracy: .perfect, timingError: dev)
        }
        let manualMean = deviations.reduce(0, +) / Double(deviations.count)
        #expect(abs(engine.averageTimingDeviation! - manualMean) < 0.001)
    }

    @Test("earlyCount and lateCount are consistent with timingDeviations array")
    func testEarlyLateCountConsistency() {
        var engine = ScoreEngine()
        let deviations = [-15.0, 0.0, 20.0, -5.0, 8.0]
        for dev in deviations {
            engine.processHit(accuracy: .perfect, timingError: dev)
        }
        let manualEarly = deviations.filter { $0 < 0 }.count
        let manualLate = deviations.filter { $0 > 0 }.count
        #expect(engine.earlyCount == manualEarly)
        #expect(engine.lateCount == manualLate)
    }
}

@Suite("ScoreEngine TimingTendency Boundary Tests")
struct ScoreEngineTimingTendencyBoundaryTests {

    @Test("timingTendency .balanced when deviations average to exactly 0")
    func testTimingTendencyZeroAverage() {
        var engine = ScoreEngine()
        engine.processHit(accuracy: .perfect, timingError: -10.0)
        engine.processHit(accuracy: .perfect, timingError: 10.0)
        // avg = 0 → balanced
        #expect(engine.timingTendency == .balanced)
    }

    @Test("timingTendency .early for large negative deviation")
    func testTimingTendencyLargeNegative() {
        var engine = ScoreEngine()
        engine.processHit(accuracy: .perfect, timingError: -100.0)
        #expect(engine.timingTendency == .early)
    }

    @Test("timingTendency .late for large positive deviation")
    func testTimingTendencyLargePositive() {
        var engine = ScoreEngine()
        engine.processHit(accuracy: .perfect, timingError: 100.0)
        #expect(engine.timingTendency == .late)
    }

    @Test("timingTendency .balanced for single zero deviation")
    func testTimingTendencyBalancedForZeroDeviation() {
        var engine = ScoreEngine()
        engine.processHit(accuracy: .perfect, timingError: 0.0)
        #expect(engine.timingTendency == .balanced)
    }
}
