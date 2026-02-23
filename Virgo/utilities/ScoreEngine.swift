//
//  ScoreEngine.swift
//  Virgo
//
//  Pure value-type scoring engine. Owns all combo and scoring state.
//  No I/O, no SwiftUI dependencies — fully unit-testable in isolation.
//

import Foundation

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

    // MARK: - Mutating API

    /// Process a player hit with the given accuracy tier.
    /// Non-miss hits increment combo before scoring (combo-then-score ordering).
    mutating func processHit(accuracy: TimingAccuracy) {
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
            previousHighScore: previousHighScore
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
