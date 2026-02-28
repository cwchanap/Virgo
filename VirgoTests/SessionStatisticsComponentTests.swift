//
//  SessionStatisticsComponentTests.swift
//  VirgoTests
//
//  Unit tests for AccuracyCircleView, AccuracyBreakdownChart, and TimingDeviationView.
//  Verifies instantiation, logic-bearing properties, and edge case handling.
//

import Testing
import SwiftUI
@testable import Virgo

// MARK: - AccuracyCircleView Tests

@Suite("AccuracyCircleView Tests")
struct AccuracyCircleViewTests {

    @Test("Can be instantiated with 0% accuracy")
    func testInstantiationZeroPercent() {
        let view = AccuracyCircleView(percentage: 0.0)
        _ = view
    }

    @Test("Can be instantiated with 100% accuracy")
    func testInstantiationFullPercent() {
        let view = AccuracyCircleView(percentage: 100.0)
        _ = view
    }

    @Test("Can be instantiated with fractional accuracy")
    func testInstantiationFractionalPercent() {
        let view = AccuracyCircleView(percentage: 66.7)
        _ = view
    }

    @Test("ScoreEngine accuracyPercentage is 100 with all perfects")
    func testScoreEngineAllPerfects() {
        var engine = ScoreEngine()
        for _ in 0..<20 { engine.processHit(accuracy: .perfect) }
        #expect(engine.accuracyPercentage == 100.0)
        let view = AccuracyCircleView(percentage: engine.accuracyPercentage)
        _ = view
    }

    @Test("ScoreEngine accuracyPercentage is 0 on empty engine")
    func testScoreEngineEmpty() {
        let engine = ScoreEngine()
        #expect(engine.accuracyPercentage == 0.0)
        let view = AccuracyCircleView(percentage: engine.accuracyPercentage)
        _ = view
    }

    @Test("ScoreEngine accuracyPercentage clamps correctly with mixed hits")
    func testScoreEnginePartialAccuracy() {
        var engine = ScoreEngine()
        for _ in 0..<3 { engine.processHit(accuracy: .perfect) }
        for _ in 0..<1 { engine.processHit(accuracy: .miss) }
        #expect(engine.accuracyPercentage == 75.0)
        let view = AccuracyCircleView(percentage: engine.accuracyPercentage)
        _ = view
    }
}

// MARK: - AccuracyBreakdownChart Tests

@Suite("AccuracyBreakdownChart Tests")
struct AccuracyBreakdownChartTests {

    @Test("Can be instantiated with all-zero counts")
    func testAllZeroCounts() {
        let view = AccuracyBreakdownChart(perfectCount: 0, greatCount: 0, goodCount: 0, missCount: 0)
        _ = view
    }

    @Test("Can be instantiated with realistic hit distribution")
    func testRealisticDistribution() {
        let view = AccuracyBreakdownChart(perfectCount: 30, greatCount: 10, goodCount: 5, missCount: 2)
        _ = view
    }

    @Test("Can be instantiated with all misses")
    func testAllMisses() {
        let view = AccuracyBreakdownChart(perfectCount: 0, greatCount: 0, goodCount: 0, missCount: 50)
        _ = view
    }

    @Test("Can be instantiated with all perfects")
    func testAllPerfects() {
        let view = AccuracyBreakdownChart(perfectCount: 100, greatCount: 0, goodCount: 0, missCount: 0)
        _ = view
    }

    @Test("ScoreEngine hit counts pass through correctly")
    func testScoreEngineHitCountsPassThrough() {
        var engine = ScoreEngine()
        for _ in 0..<4 { engine.processHit(accuracy: .perfect) }
        for _ in 0..<2 { engine.processHit(accuracy: .great) }
        for _ in 0..<1 { engine.processHit(accuracy: .good) }
        for _ in 0..<3 { engine.processHit(accuracy: .miss) }

        #expect(engine.perfectCount == 4)
        #expect(engine.greatCount == 2)
        #expect(engine.goodCount == 1)
        #expect(engine.missCount == 3)

        let view = AccuracyBreakdownChart(
            perfectCount: engine.perfectCount,
            greatCount: engine.greatCount,
            goodCount: engine.goodCount,
            missCount: engine.missCount
        )
        _ = view
    }
}

// MARK: - TimingDeviationView Tests

@Suite("TimingDeviationView Tests")
struct TimingDeviationViewTests {

    @Test("Can be instantiated with nil averageDeviation")
    func testNilDeviation() {
        let view = TimingDeviationView(
            averageDeviation: nil,
            earlyPercentage: 0,
            latePercentage: 0,
            tendency: .balanced
        )
        _ = view
    }

    @Test("Can be instantiated with early tendency")
    func testEarlyTendency() {
        let view = TimingDeviationView(
            averageDeviation: -18.5,
            earlyPercentage: 70,
            latePercentage: 30,
            tendency: .early
        )
        _ = view
    }

    @Test("Can be instantiated with late tendency")
    func testLateTendency() {
        let view = TimingDeviationView(
            averageDeviation: 12.0,
            earlyPercentage: 25,
            latePercentage: 75,
            tendency: .late
        )
        _ = view
    }

    @Test("Can be instantiated with balanced tendency")
    func testBalancedTendency() {
        let view = TimingDeviationView(
            averageDeviation: 1.2,
            earlyPercentage: 48,
            latePercentage: 52,
            tendency: .balanced
        )
        _ = view
    }

    @Test("ScoreEngine properties feed correctly into TimingDeviationView")
    func testScoreEngineFeedsView() {
        var engine = ScoreEngine()
        engine.processHit(accuracy: .perfect, timingError: -20.0)
        engine.processHit(accuracy: .perfect, timingError: -10.0)
        engine.processHit(accuracy: .great, timingError: 5.0)

        // Verify computed values before passing to view
        #expect(engine.earlyCount == 2)
        #expect(engine.lateCount == 1)
        #expect(engine.timingTendency == .early)
        #expect(engine.averageTimingDeviation != nil)
        // average = (-20 + -10 + 5) / 3 = -8.33... → early
        #expect(engine.averageTimingDeviation! < -5.0)

        let view = TimingDeviationView(
            averageDeviation: engine.averageTimingDeviation,
            earlyPercentage: engine.earlyPercentage,
            latePercentage: engine.latePercentage,
            tendency: engine.timingTendency
        )
        _ = view
    }

    @Test("ScoreEngine with only misses feeds nil deviation to view")
    func testScoreEngineAllMissesNoDeviation() {
        var engine = ScoreEngine()
        for _ in 0..<5 { engine.processHit(accuracy: .miss) }

        #expect(engine.averageTimingDeviation == nil)
        #expect(engine.earlyPercentage == 0.0)
        #expect(engine.latePercentage == 0.0)

        let view = TimingDeviationView(
            averageDeviation: engine.averageTimingDeviation,
            earlyPercentage: engine.earlyPercentage,
            latePercentage: engine.latePercentage,
            tendency: engine.timingTendency
        )
        _ = view
    }
}

// MARK: - TimingTendency Tests

@Suite("TimingTendency Equatable Tests")
struct TimingTendencyTests {

    @Test("TimingTendency values are equatable")
    func testEquatable() {
        #expect(TimingTendency.early == .early)
        #expect(TimingTendency.late == .late)
        #expect(TimingTendency.balanced == .balanced)
        #expect(TimingTendency.early != .late)
        #expect(TimingTendency.early != .balanced)
        #expect(TimingTendency.late != .balanced)
    }

    @Test("All three tendency values can be produced from ScoreEngine")
    func testAllTendenciesReachable() {
        var earlyEngine = ScoreEngine()
        earlyEngine.processHit(accuracy: .perfect, timingError: -50.0)
        #expect(earlyEngine.timingTendency == .early)

        var lateEngine = ScoreEngine()
        lateEngine.processHit(accuracy: .perfect, timingError: 50.0)
        #expect(lateEngine.timingTendency == .late)

        let emptyEngine = ScoreEngine()
        #expect(emptyEngine.timingTendency == .balanced)

        var balancedEngine = ScoreEngine()
        balancedEngine.processHit(accuracy: .perfect, timingError: 0.0)
        #expect(balancedEngine.timingTendency == .balanced)
    }
}
