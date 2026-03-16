//
//  TimingAccuracyTests.swift
//  VirgoTests
//
//  Unit tests for TimingAccuracy enum — tolerance windows and score multipliers.
//

import Testing
@testable import Virgo

@Suite("TimingAccuracy Tests")
struct TimingAccuracyTests {

    // MARK: - toleranceMs Values

    @Test("Perfect tolerance is 25ms")
    func testPerfectTolerance() {
        #expect(TimingAccuracy.perfect.toleranceMs == 25.0)
    }

    @Test("Great tolerance is 50ms")
    func testGreatTolerance() {
        #expect(TimingAccuracy.great.toleranceMs == 50.0)
    }

    @Test("Good tolerance is 100ms")
    func testGoodTolerance() {
        #expect(TimingAccuracy.good.toleranceMs == 100.0)
    }

    @Test("Miss tolerance is infinite")
    func testMissTolerance() {
        #expect(TimingAccuracy.miss.toleranceMs == Double.infinity)
    }

    // MARK: - toleranceMs Ordering

    @Test("Tolerances increase: perfect < great < good < miss")
    func testToleranceOrdering() {
        #expect(TimingAccuracy.perfect.toleranceMs < TimingAccuracy.great.toleranceMs)
        #expect(TimingAccuracy.great.toleranceMs < TimingAccuracy.good.toleranceMs)
        #expect(TimingAccuracy.good.toleranceMs < TimingAccuracy.miss.toleranceMs)
    }

    // MARK: - scoreMultiplier Values

    @Test("Perfect score multiplier is 1.0")
    func testPerfectScoreMultiplier() {
        #expect(TimingAccuracy.perfect.scoreMultiplier == 1.0)
    }

    @Test("Great score multiplier is 0.8")
    func testGreatScoreMultiplier() {
        #expect(TimingAccuracy.great.scoreMultiplier == 0.8)
    }

    @Test("Good score multiplier is 0.5")
    func testGoodScoreMultiplier() {
        #expect(TimingAccuracy.good.scoreMultiplier == 0.5)
    }

    @Test("Miss score multiplier is 0.0")
    func testMissScoreMultiplier() {
        #expect(TimingAccuracy.miss.scoreMultiplier == 0.0)
    }

    // MARK: - scoreMultiplier Ordering

    @Test("Score multipliers decrease: perfect > great > good > miss")
    func testScoreMultiplierOrdering() {
        #expect(TimingAccuracy.perfect.scoreMultiplier > TimingAccuracy.great.scoreMultiplier)
        #expect(TimingAccuracy.great.scoreMultiplier > TimingAccuracy.good.scoreMultiplier)
        #expect(TimingAccuracy.good.scoreMultiplier > TimingAccuracy.miss.scoreMultiplier)
    }

    // MARK: - scoreMultiplier Bounds

    @Test("All score multipliers are in [0.0, 1.0]")
    func testScoreMultiplierBounds() {
        for tier in [TimingAccuracy.perfect, .great, .good, .miss] {
            #expect(tier.scoreMultiplier >= 0.0)
            #expect(tier.scoreMultiplier <= 1.0)
        }
    }

    // MARK: - Tier Classification Logic

    @Test("Error within perfect window classifies as perfect")
    func testPerfectWindowClassification() {
        // Errors within ±25ms should be perfect
        let errors: [Double] = [0.0, 10.0, -10.0, 24.9, -24.9, 25.0]
        for error in errors {
            let abs = Swift.abs(error)
            let tier: TimingAccuracy
            if abs <= TimingAccuracy.perfect.toleranceMs {
                tier = .perfect
            } else if abs <= TimingAccuracy.great.toleranceMs {
                tier = .great
            } else if abs <= TimingAccuracy.good.toleranceMs {
                tier = .good
            } else {
                tier = .miss
            }
            #expect(tier == .perfect, "Expected perfect for error \(error)ms, got \(tier)")
        }
    }

    @Test("Error within great window but outside perfect classifies as great")
    func testGreatWindowClassification() {
        // Errors in (25ms, 50ms] should be great
        let errors: [Double] = [25.1, 30.0, -30.0, 49.9, 50.0]
        for error in errors {
            let abs = Swift.abs(error)
            let tier: TimingAccuracy
            if abs <= TimingAccuracy.perfect.toleranceMs {
                tier = .perfect
            } else if abs <= TimingAccuracy.great.toleranceMs {
                tier = .great
            } else if abs <= TimingAccuracy.good.toleranceMs {
                tier = .good
            } else {
                tier = .miss
            }
            #expect(tier == .great, "Expected great for error \(error)ms, got \(tier)")
        }
    }

    @Test("Error within good window but outside great classifies as good")
    func testGoodWindowClassification() {
        // Errors in (50ms, 100ms] should be good
        let errors: [Double] = [50.1, 75.0, -75.0, 99.9, 100.0]
        for error in errors {
            let abs = Swift.abs(error)
            let tier: TimingAccuracy
            if abs <= TimingAccuracy.perfect.toleranceMs {
                tier = .perfect
            } else if abs <= TimingAccuracy.great.toleranceMs {
                tier = .great
            } else if abs <= TimingAccuracy.good.toleranceMs {
                tier = .good
            } else {
                tier = .miss
            }
            #expect(tier == .good, "Expected good for error \(error)ms, got \(tier)")
        }
    }

    @Test("Error outside good window classifies as miss")
    func testMissClassification() {
        // Errors > 100ms should be miss
        let errors: [Double] = [100.1, 150.0, -150.0, 200.0, 1000.0]
        for error in errors {
            let abs = Swift.abs(error)
            let tier: TimingAccuracy
            if abs <= TimingAccuracy.perfect.toleranceMs {
                tier = .perfect
            } else if abs <= TimingAccuracy.great.toleranceMs {
                tier = .great
            } else if abs <= TimingAccuracy.good.toleranceMs {
                tier = .good
            } else {
                tier = .miss
            }
            #expect(tier == .miss, "Expected miss for error \(error)ms, got \(tier)")
        }
    }

    // MARK: - Score Points Derived from Multiplier

    @Test("Perfect hit at base (100 × 1.0 × 1.0) yields 100 points")
    func testPerfectPointsAtBaseCombo() {
        let basePoints = 100.0
        let comboMultiplier = 1.0
        let points = Int(basePoints * TimingAccuracy.perfect.scoreMultiplier * comboMultiplier)
        #expect(points == 100)
    }

    @Test("Great hit at base (100 × 0.8 × 1.0) yields 80 points")
    func testGreatPointsAtBaseCombo() {
        let basePoints = 100.0
        let comboMultiplier = 1.0
        let points = Int(basePoints * TimingAccuracy.great.scoreMultiplier * comboMultiplier)
        #expect(points == 80)
    }

    @Test("Good hit at base (100 × 0.5 × 1.0) yields 50 points")
    func testGoodPointsAtBaseCombo() {
        let basePoints = 100.0
        let comboMultiplier = 1.0
        let points = Int(basePoints * TimingAccuracy.good.scoreMultiplier * comboMultiplier)
        #expect(points == 50)
    }

    @Test("Miss hit at base (100 × 0.0 × 1.0) yields 0 points")
    func testMissPointsAtBaseCombo() {
        let basePoints = 100.0
        let comboMultiplier = 1.0
        let points = Int(basePoints * TimingAccuracy.miss.scoreMultiplier * comboMultiplier)
        #expect(points == 0)
    }

    // MARK: - Boundary Precision

    @Test("Exact perfect boundary (25.0ms) is classified as perfect, not great")
    func testExactPerfectBoundary() {
        let errorMs = 25.0
        // At exactly 25ms, the check is <= perfect.toleranceMs, so it's perfect
        #expect(errorMs <= TimingAccuracy.perfect.toleranceMs)
    }

    @Test("Just past perfect boundary (25.001ms) falls in great window")
    func testJustPastPerfectBoundary() {
        let errorMs = 25.001
        #expect(errorMs > TimingAccuracy.perfect.toleranceMs)
        #expect(errorMs <= TimingAccuracy.great.toleranceMs)
    }

    @Test("Exact good boundary (100.0ms) is classified as good, not miss")
    func testExactGoodBoundary() {
        let errorMs = 100.0
        #expect(errorMs <= TimingAccuracy.good.toleranceMs)
        #expect(errorMs > TimingAccuracy.perfect.toleranceMs)
        #expect(errorMs > TimingAccuracy.great.toleranceMs)
    }

    @Test("Just past good boundary (100.001ms) is classified as miss")
    func testJustPastGoodBoundary() {
        let errorMs = 100.001
        #expect(errorMs > TimingAccuracy.good.toleranceMs)
    }
}
