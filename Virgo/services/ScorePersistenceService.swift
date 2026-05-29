//
//  ScorePersistenceService.swift
//  Virgo
//
//  SwiftData-backed per-chart score persistence: records each completed run,
//  retains the most recent attempts, and tracks an all-time best (full-speed only).
//

import Foundation
import SwiftData

@MainActor
final class ScorePersistenceService {

    static let maxRecentAttempts = 10

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Records a completed run, prunes old history, and updates the chart's
    /// all-time best when the run was full speed.
    /// - Returns: `true` if a new all-time best was set.
    /// Returns `false` if the underlying save fails (no best-score change is reported).
    @discardableResult
    func recordAttempt(
        _ snapshot: LiveScoreSnapshot,
        for chart: Chart,
        atFullSpeed: Bool,
        speedMultiplier: Double,
        now: Date = Date()
    ) -> Bool {
        let record = ScoreRecord(
            score: snapshot.score,
            maxCombo: snapshot.maxCombo,
            accuracy: snapshot.hitAccuracy,
            speedMultiplier: speedMultiplier,
            playedAt: now,
            chart: chart
        )
        modelContext.insert(record)

        pruneOldRecords(for: chart)

        let previousBestScore = chart.bestScore
        var isNewBest = false
        if atFullSpeed && record.score > chart.bestScore {
            chart.bestScore = record.score
            isNewBest = true
        }

        do {
            try modelContext.save()
        } catch {
            Logger.error("ScorePersistenceService: failed to save score record: \(error.localizedDescription)")
            chart.bestScore = previousBestScore
            return false
        }
        return isNewBest
    }

    /// The all-time best score for a chart (0 if none).
    func bestScore(for chart: Chart) -> Int {
        chart.bestScore
    }

    /// Most recent attempts for a chart, newest first, as value-type DTOs.
    func recentAttempts(
        for chart: Chart,
        limit: Int = ScorePersistenceService.maxRecentAttempts
    ) -> [ScoreAttemptSummary] {
        chart.scoreRecords
            .sorted { $0.playedAt > $1.playedAt }
            .prefix(limit)
            .map { record in
                ScoreAttemptSummary(
                    score: record.score,
                    maxCombo: record.maxCombo,
                    accuracy: record.accuracy,
                    speedMultiplier: record.speedMultiplier,
                    playedAt: record.playedAt
                )
            }
    }

    // MARK: - Private

    private func pruneOldRecords(for chart: Chart) {
        let sorted = chart.scoreRecords.sorted { $0.playedAt > $1.playedAt }
        guard sorted.count > Self.maxRecentAttempts else { return }
        for record in sorted[Self.maxRecentAttempts...] {
            modelContext.delete(record)
        }
    }
}
