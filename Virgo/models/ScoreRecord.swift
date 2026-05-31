//
//  ScoreRecord.swift
//  Virgo
//
//  One persisted row per completed gameplay run.
//

import Foundation
import SwiftData

@Model
final class ScoreRecord {
    var score: Int
    var maxCombo: Int
    var accuracy: Double          // hit accuracy 0–100
    var speedMultiplier: Double   // effective speed at run completion
    var playedAt: Date
    var chart: Chart?

    init(
        score: Int,
        maxCombo: Int,
        accuracy: Double,
        speedMultiplier: Double,
        playedAt: Date,
        chart: Chart? = nil
    ) {
        precondition(score >= 0, "ScoreRecord.score must be non-negative")
        self.score = score
        self.maxCombo = maxCombo
        self.accuracy = min(max(accuracy, 0), 100)
        self.speedMultiplier = speedMultiplier
        self.playedAt = playedAt
        self.chart = chart
    }
}
