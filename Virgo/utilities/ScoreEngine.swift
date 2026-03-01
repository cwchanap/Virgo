//
//  ScoreEngine.swift
//  Virgo
//
//  Pure value-type scoring engine. Owns all combo and scoring state.
//  No I/O, no SwiftUI dependencies — fully unit-testable in isolation.
//

import Foundation

// MARK: - TimingTendency

/// Player's overall timing direction across a session.
enum TimingTendency: Equatable {
    case early     // average deviation < -5ms
    case late      // average deviation > +5ms
    case balanced  // -5ms to +5ms
}

// MARK: - SessionResult

/// Immutable snapshot of a completed gameplay session's results.
struct SessionResult: Equatable {
    let finalScore: Int
    let maxCombo: Int
    let perfectCount: Int
    let greatCount: Int
    let goodCount: Int
    let missCount: Int
    let totalNotes: Int
    let isNewHighScore: Bool
    let previousHighScore: Int
    // Timing statistics
    let accuracyPercentage: Double
    let averageTimingDeviation: Double?
    let earlyCount: Int
    let lateCount: Int
    let timingTendency: TimingTendency
    let timingDeviations: [Double]
}

// MARK: - ScoreEngine

/// Stateful scoring engine tracking combo, score, and accuracy counts.
/// All mutations are explicit via `mutating` methods. Thread-safe by value semantics.
struct ScoreEngine {

    // MARK: - State

    private(set) var score: Int = 0
    private(set) var combo: Int = 0
    private(set) var maxCombo: Int = 0
    private(set) var perfectCount: Int = 0
    private(set) var greatCount: Int = 0
    private(set) var goodCount: Int = 0
    private(set) var missCount: Int = 0
    private(set) var timingDeviations: [Double] = []
    private(set) var earlyCount: Int = 0
    private(set) var lateCount: Int = 0
    private var timingDeviationSum: Double = 0.0

    // MARK: - Computed Stats

    var totalHits: Int { perfectCount + greatCount + goodCount }
    var totalNotes: Int { totalHits + missCount }

    /// Hit accuracy as a percentage (0–100). Returns 0 when no notes played.
    var accuracyPercentage: Double {
        guard totalNotes > 0 else { return 0.0 }
        return Double(totalHits) / Double(totalNotes) * 100.0
    }

    /// Mean timing deviation across all scored (non-miss) hits. Nil when no data.
    /// O(1) — uses a running sum maintained in `processHit`.
    var averageTimingDeviation: Double? {
        guard !timingDeviations.isEmpty else { return nil }
        return timingDeviationSum / Double(timingDeviations.count)
    }

    /// Early hit share as a percentage (0–100). Returns 0 when no timing data.
    /// O(1) — uses a running counter maintained in `processHit`.
    var earlyPercentage: Double {
        guard !timingDeviations.isEmpty else { return 0.0 }
        return Double(earlyCount) / Double(timingDeviations.count) * 100.0
    }

    /// Late hit share as a percentage (0–100). Returns 0 when no timing data.
    /// O(1) — uses a running counter maintained in `processHit`.
    var latePercentage: Double {
        guard !timingDeviations.isEmpty else { return 0.0 }
        return Double(lateCount) / Double(timingDeviations.count) * 100.0
    }

    /// Player's overall timing tendency for this session.
    var timingTendency: TimingTendency {
        guard let avg = averageTimingDeviation else { return .balanced }
        if avg < -5.0 { return .early }
        if avg > 5.0 { return .late }
        return .balanced
    }

    // MARK: - Mutating API

    /// Process a player hit with the given accuracy tier.
    /// Non-miss hits increment combo before scoring (combo-then-score ordering).
    /// Pass `timingError` (ms, negative = early, positive = late) to collect timing data.
    mutating func processHit(accuracy: TimingAccuracy, timingError: Double? = nil) {
        switch accuracy {
        case .perfect:
            perfectCount += 1
        case .great:
            greatCount += 1
        case .good:
            goodCount += 1
        case .miss:
            missCount += 1
            combo = 0
            return
        }
        combo += 1
        maxCombo = max(maxCombo, combo)
        score += pointsForCurrentCombo(accuracy: accuracy)
        if let error = timingError {
            timingDeviations.append(error)
            timingDeviationSum += error
            if error < 0 { earlyCount += 1 }
            else if error > 0 { lateCount += 1 }
        }
    }

    /// Process a note that scrolled past without a hit attempt.
    /// Breaks combo and increments missCount but does not add to score.
    mutating func processMissedNote() {
        missCount += 1
        combo = 0
    }

    /// Reset all state to initial values.
    mutating func reset() {
        score = 0
        combo = 0
        maxCombo = 0
        perfectCount = 0
        greatCount = 0
        goodCount = 0
        missCount = 0
        timingDeviations = []
        earlyCount = 0
        lateCount = 0
        timingDeviationSum = 0.0
    }

    // MARK: - Session Result

    /// Snapshot results at the end of a session.
    func sessionResult(totalNotes: Int, previousHighScore: Int) -> SessionResult {
        SessionResult(
            finalScore: score,
            maxCombo: maxCombo,
            perfectCount: perfectCount,
            greatCount: greatCount,
            goodCount: goodCount,
            missCount: missCount,
            totalNotes: totalNotes,
            isNewHighScore: score > previousHighScore,
            previousHighScore: previousHighScore,
            accuracyPercentage: accuracyPercentage,
            averageTimingDeviation: averageTimingDeviation,
            earlyCount: earlyCount,
            lateCount: lateCount,
            timingTendency: timingTendency,
            timingDeviations: timingDeviations
        )
    }

    // MARK: - Pure Static Helpers

    /// Combo multiplier tier based on current combo count.
    static func comboMultiplier(for combo: Int) -> Double {
        switch combo {
        case 100...: return 3.0
        case 50...:  return 2.5
        case 25...:  return 2.0
        case 10...:  return 1.5
        default:     return 1.0
        }
    }

    /// Returns the milestone value if the combo just crossed one (10 / 25 / 50 / 100), else nil.
    static func milestone(crossedFrom prev: Int, to current: Int) -> Int? {
        let milestones = [10, 25, 50, 100]
        return milestones.first { $0 > prev && $0 <= current }
    }

    // MARK: - Private

    private func pointsForCurrentCombo(accuracy: TimingAccuracy) -> Int {
        Int(100.0 * accuracy.scoreMultiplier * Self.comboMultiplier(for: combo))
    }
}
