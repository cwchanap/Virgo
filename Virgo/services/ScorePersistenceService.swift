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

    /// Outcome of a `recordAttempt` call, distinguishing save failures from normal results.
    enum RecordResult: Equatable {
        /// The run was saved and set a new all-time best (full-speed only).
        case newBest
        /// The run was saved but did not beat the existing best (or was not at full speed).
        case recorded
        /// The underlying save failed — nothing was persisted.
        case saveFailed
    }

    nonisolated static let maxRecentAttempts = 10
    private static let migrationFlagKey = "DidMigrateHighScoresToSwiftData"
    private static let legacyHighScoreKey = "HighScorePerChart"

    private let modelContext: ModelContext
    private let saveContext: @Sendable (ModelContext) throws -> Void
    /// Retains the container when this service owns an in-memory store, so the
    /// context cannot dangle. `ModelContext` does not keep its `ModelContainer`
    /// alive; without this, a `makeInMemory()` service would crash on first use.
    private let retainedContainer: ModelContainer?

    init(
        modelContext: ModelContext,
        saveContext: @escaping @Sendable (ModelContext) throws -> Void = { context in try context.save() }
    ) {
        self.modelContext = modelContext
        self.saveContext = saveContext
        self.retainedContainer = nil
    }

    private init(
        inMemoryContainer: ModelContainer,
        saveContext: @escaping @Sendable (ModelContext) throws -> Void = { context in try context.save() }
    ) {
        self.modelContext = inMemoryContainer.mainContext
        self.saveContext = saveContext
        self.retainedContainer = inMemoryContainer
    }

    /// Records a completed run, prunes old history, and updates the chart's
    /// all-time best when the run was full speed.
    /// - Returns: A `RecordResult` indicating whether a new best was set, the run
    ///   was merely recorded, or the save failed (nothing persisted).
    @discardableResult
    func recordAttempt(
        _ snapshot: LiveScoreSnapshot,
        for chart: Chart,
        atFullSpeed: Bool,
        speedMultiplier: Double,
        now: Date = Date()
    ) -> RecordResult {
        // The linked chart must belong to this service's context before we attach a
        // ScoreRecord to it. In production the gameplay chart is already managed by the
        // injected context; for in-memory/preview services handed a detached (context-less)
        // chart, adopt it so SwiftData does not crash faulting a context-less related object.
        if chart.modelContext == nil {
            modelContext.insert(chart)
        }

        let record = ScoreRecord(
            score: snapshot.score,
            maxCombo: snapshot.maxCombo,
            accuracy: snapshot.hitAccuracy,
            speedMultiplier: speedMultiplier,
            playedAt: now,
            chart: chart
        )
        modelContext.insert(record)

        let previousBestScore = chart.bestScore
        var isNewBest = false
        if atFullSpeed && record.score > chart.bestScore {
            chart.bestScore = record.score
            isNewBest = true
        }

        do {
            try saveContext(modelContext)
        } catch {
            Logger.error("ScorePersistenceService: failed to save score record: \(error.localizedDescription)")
            // Restore the two pending mutations — no pruning has occurred yet so only
            // the insert and bestScore need reverting.
            chart.bestScore = previousBestScore
            modelContext.delete(record)
            return .saveFailed
        }

        // Prune after a successful save so a save failure never requires "undeleting"
        // pruned records.  Pruning failure is non-critical (extra records, no data loss).
        pruneOldRecords(for: chart)
        try? saveContext(modelContext)

        return isNewBest ? .newBest : .recorded
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
            .filter { !$0.isDeleted }
            .sorted { $0.playedAt > $1.playedAt }
            .prefix(limit)
            .map { record in
                ScoreAttemptSummary(
                    id: record.persistentModelID,
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
            var updated: [(chart: Chart, previousBest: Int)] = []
            for chart in charts {
                guard let resolution = PersistentIdentifierPersistenceKey.resolve(
                    for: chart.persistentModelID,
                    in: legacy,
                    logPrefix: "ScorePersistenceService"
                ), resolution.value > chart.bestScore else {
                    continue
                }
                updated.append((chart, chart.bestScore))
                chart.bestScore = resolution.value
            }

            if !updated.isEmpty {
                do {
                    try saveContext(modelContext)
                } catch {
                    Logger.error(
                        "ScorePersistenceService: failed to save migrated high scores: \(error.localizedDescription)"
                    )
                    // Restore each chart's bestScore to its pre-migration value.
                    for entry in updated {
                        entry.chart.bestScore = entry.previousBest
                    }
                    return // leave the flag unset so migration retries next launch
                }
            }
        }

        userDefaults.removeObject(forKey: Self.legacyHighScoreKey)
        userDefaults.set(true, forKey: Self.migrationFlagKey)
    }

    // MARK: - Private

    private func pruneOldRecords(for chart: Chart) {
        let sorted = chart.scoreRecords.sorted { $0.playedAt > $1.playedAt }
        guard sorted.count > Self.maxRecentAttempts else { return }
        let toPrune = Array(sorted[Self.maxRecentAttempts...])
        for record in toPrune {
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
            } else {
                Logger.warning("ScorePersistenceService: dropping non-numeric legacy value for key \(key)")
            }
        }
        return scores
    }
}

extension ScorePersistenceService {
    /// A service backed by a throwaway in-memory store, for previews and tests
    /// that do not assert on cross-launch persistence.
    static func makeInMemory() -> ScorePersistenceService {
        let schema = Schema([
            Song.self, Chart.self, Note.self,
            ServerSong.self, ServerChart.self, ScoreRecord.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, allowsSave: true)
        do {
            let container = try ModelContainer(for: schema, configurations: [config])
            return ScorePersistenceService(inMemoryContainer: container)
        } catch {
            fatalError("ScorePersistenceService.makeInMemory failed: \(error)")
        }
    }
}
