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
import CryptoKit

/// Service that persists the best score achieved for each chart.
@MainActor
final class HighScoreService: ObservableObject {

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
        let key = persistenceKey(for: chartID)
        let scores = readPersistedScores()
        return scores[key] ?? 0
    }

    /// Saves the score if it is strictly greater than the previous record.
    /// - Returns: `true` if a new record was set, `false` otherwise.
    @discardableResult
    func saveIfHighScore(_ score: Int, for chartID: PersistentIdentifier) -> Bool {
        guard score > 0 else { return false }

        let key = persistenceKey(for: chartID)
        var scores = readPersistedScores()
        let current = scores[key] ?? 0
        guard score > current else { return false }

        scores[key] = score
        userDefaults.set(scores, forKey: settingsKey)

        Logger.debug("New high score \(score) saved for chart")
        return true
    }

    /// Removes all persisted high scores.
    func clearAllHighScores() {
        userDefaults.removeObject(forKey: settingsKey)
        Logger.debug("Cleared all high scores")
    }

    // MARK: - Private

    /// Creates a stable persistence key from a PersistentIdentifier.
    /// Uses the same JSONEncoder + SHA-256 fallback strategy as PracticeSettingsService.
    private func persistenceKey(for chartID: PersistentIdentifier) -> String {
        do {
            let data = try JSONEncoder().encode(chartID)
            if let key = String(data: data, encoding: .utf8) {
                return key
            }
            Logger.error("HighScoreService: Failed to convert PersistentIdentifier to UTF-8 string")
        } catch {
            Logger.error("HighScoreService: Failed to encode PersistentIdentifier: \(error.localizedDescription)")
        }

        // SHA-256 fallback
        let stableIdentifier = String(describing: chartID)
        let inputData = Data(stableIdentifier.utf8)
        let digest = SHA256.hash(data: inputData)
        let hashString = digest.compactMap { String(format: "%02x", $0) }.joined()
        return "chart_\(String(hashString.prefix(32)))"
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
            }
        }
        return scores
    }
}
