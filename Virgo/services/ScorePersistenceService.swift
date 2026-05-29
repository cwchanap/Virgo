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

    nonisolated static let maxRecentAttempts = 10
    private static let migrationFlagKey = "DidMigrateHighScoresToSwiftData"
    private static let legacyHighScoreKey = "HighScorePerChart"

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

    /// One-time migration of legacy UserDefaults high scores into Chart.bestScore.
    /// Guarded by a flag so it runs at most once; idempotent and never lowers a best.
    func migrateLegacyHighScores(charts: [Chart], from userDefaults: UserDefaults) {
        guard !userDefaults.bool(forKey: Self.migrationFlagKey) else { return }

        let legacy = readLegacyScores(from: userDefaults)
        if !legacy.isEmpty {
            for chart in charts {
                let key = PersistentIdentifierPersistenceKey.canonicalKey(
                    for: chart.persistentModelID,
                    logPrefix: "ScorePersistenceService"
                )
                if let legacyBest = legacy[key], legacyBest > chart.bestScore {
                    chart.bestScore = legacyBest
                }
            }
            do {
                try modelContext.save()
            } catch {
                Logger.error(
                    "ScorePersistenceService: failed to save migrated high scores: \(error.localizedDescription)"
                )
                return // leave the flag unset so migration retries next launch
            }
        }

        userDefaults.removeObject(forKey: Self.legacyHighScoreKey)
        userDefaults.set(true, forKey: Self.migrationFlagKey)
    }

    // MARK: - Private

    private func pruneOldRecords(for chart: Chart) {
        let sorted = chart.scoreRecords.sorted { $0.playedAt > $1.playedAt }
        guard sorted.count > Self.maxRecentAttempts else { return }
        for record in sorted[Self.maxRecentAttempts...] {
            modelContext.delete(record)
        }
    }

    private func readLegacyScores(from userDefaults: UserDefaults) -> [String: Int] {
        guard let raw = userDefaults.dictionary(forKey: Self.legacyHighScoreKey) else { return [:] }
        var scores: [String: Int] = [:]
        for (key, value) in raw {
            if let intValue = value as? Int {
                scores[key] = intValue
            } else if let numberValue = value as? NSNumber {
                scores[key] = numberValue.intValue
            }
        }
        return scores
    }
}
