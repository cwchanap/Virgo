//
//  HighScoreService.swift
//  Virgo
//
//  Per-chart high score persistence using UserDefaults.
//  Mirrors PracticeSettingsService pattern exactly:
//  @MainActor ObservableObject, injected UserDefaults, JSONEncoder + SHA-256 keying.
//

import Foundation
import SwiftData

/// Service that persists the best score achieved for each chart.
@MainActor
final class HighScoreService {

    // MARK: - Constants

    private let settingsKey = "HighScorePerChart"

    // MARK: - Dependencies

    private let userDefaults: UserDefaults

    // MARK: - Initialization

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    // MARK: - Public API

    /// Returns the saved high score for a chart, or 0 if none has been recorded.
    func highScore(for chartID: PersistentIdentifier) -> Int {
        resolvedScore(for: chartID)?.score ?? 0
    }

    /// Saves the score if it is strictly greater than the previous record.
    /// - Returns: `true` if a new record was set, `false` otherwise.
    @discardableResult
    func saveIfHighScore(_ score: Int, for chartID: PersistentIdentifier) -> Bool {
        guard score > 0 else { return false }

        let key = persistenceKey(for: chartID)
        var scores = readPersistedScores()
        if let resolved = PersistentIdentifierPersistenceKey.resolve(
            for: chartID,
            in: scores,
            logPrefix: "HighScoreService"
        ), resolved.needsMigration {
            scores.removeValue(forKey: resolved.matchedKey)
            scores[resolved.canonicalKey] = resolved.value
            userDefaults.set(scores, forKey: settingsKey)
        }

        let current = scores[key] ?? 0
        guard score > current else { return false }

        scores[key] = score
        userDefaults.set(scores, forKey: settingsKey)

        let verified = readPersistedScores()
        if verified[key] == score {
            Logger.debug("New high score \(score) saved for chart")
            return true
        } else {
            Logger.error("HighScoreService: write verification failed — high score \(score) was not persisted")
            return false
        }
    }

    /// Removes all persisted high scores.
    func clearAllHighScores() {
        userDefaults.removeObject(forKey: settingsKey)
        Logger.debug("Cleared all high scores")
    }

    // MARK: - Private

    private func resolvedScore(for chartID: PersistentIdentifier) -> (key: String, score: Int)? {
        let scores = readPersistedScores()
        guard let resolved = PersistentIdentifierPersistenceKey.resolve(
            for: chartID,
            in: scores,
            logPrefix: "HighScoreService"
        ) else {
            return nil
        }

        if resolved.needsMigration {
            var migratedScores = scores
            migratedScores.removeValue(forKey: resolved.matchedKey)
            migratedScores[resolved.canonicalKey] = resolved.value
            userDefaults.set(migratedScores, forKey: settingsKey)
        }

        return (resolved.canonicalKey, resolved.value)
    }

    /// Creates a stable persistence key from a PersistentIdentifier.
    /// Uses the same JSONEncoder + SHA-256 fallback strategy as PracticeSettingsService.
    private func persistenceKey(for chartID: PersistentIdentifier) -> String {
        PersistentIdentifierPersistenceKey.canonicalKey(
            for: chartID,
            logPrefix: "HighScoreService"
        )
    }

    /// Reads the persisted score dictionary, tolerating NSNumber bridging.
    private func readPersistedScores() -> [String: Int] {
        guard let raw = userDefaults.dictionary(forKey: settingsKey) else { return [:] }

        var scores: [String: Int] = [:]
        for (key, value) in raw {
            if let intValue = value as? Int {
                scores[key] = intValue
            } else if let numberValue = value as? NSNumber {
                scores[key] = numberValue.intValue
            } else {
                Logger.warning("HighScoreService: unexpected value type \(type(of: value)) for key \(key) — skipping")
            }
        }
        return scores
    }
}
