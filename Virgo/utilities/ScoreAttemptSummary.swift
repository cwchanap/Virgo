//
//  ScoreAttemptSummary.swift
//  Virgo
//
//  Value-type view boundary for a single persisted score attempt.
//

import Foundation

struct ScoreAttemptSummary: Identifiable, Equatable {
    let id: UUID
    let score: Int
    let maxCombo: Int
    let accuracy: Double          // 0–100
    let speedMultiplier: Double
    let playedAt: Date

    init(
        id: UUID = UUID(),
        score: Int,
        maxCombo: Int,
        accuracy: Double,
        speedMultiplier: Double,
        playedAt: Date
    ) {
        self.id = id
        self.score = score
        self.maxCombo = maxCombo
        self.accuracy = accuracy
        self.speedMultiplier = speedMultiplier
        self.playedAt = playedAt
    }
}
