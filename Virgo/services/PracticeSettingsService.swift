//
//  PracticeSettingsService.swift
//  Virgo
//
//  Service for managing practice-related settings including speed control.
//  Designed for extensibility to support future practice features like
//  loop points, count-in, A-B repeat, etc.
//

import Foundation
import SwiftData
import CryptoKit

/// Service that manages practice settings for gameplay sessions.
/// Handles speed control state, validation, and per-chart persistence.
@MainActor
class PracticeSettingsService: ObservableObject {
    // MARK: - Constants

    /// Minimum allowed speed multiplier (25%)
    static let minSpeed: Double = 0.25

    /// Maximum allowed speed multiplier (150%)
    static let maxSpeed: Double = 1.5

    /// Speed adjustment increment for slider (5%)
    static let speedIncrement: Double = 0.05

    /// Preset speed options for quick selection
    static let speedPresets: [Double] = [0.50, 0.75, 1.00, 1.25]

    // MARK: - Published State

    /// Current speed multiplier (0.25 to 1.5, where 1.0 = 100%)
    @Published private(set) var speedMultiplier: Double = 1.0

    // MARK: - Dependencies

    private let userDefaults: UserDefaults
    private let settingsKey = "PracticeSettingsSpeedMultipliers"

    // MARK: - Initialization

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    // MARK: - Speed Control API

    /// Sets the speed multiplier with validation and clamping.
    /// - Parameter speed: The desired speed multiplier (will be clamped to valid range)
    func setSpeed(_ speed: Double) {
        guard speed.isFinite else {
            Logger.warning("PracticeSettingsService: Invalid speed value (non-finite), ignoring")
            return
        }

        let clampedSpeed = max(Self.minSpeed, min(Self.maxSpeed, speed))

        // Skip redundant updates to prevent unnecessary @Published notifications
        // (avoids double notifications when view calls setSpeed before updateSpeed)
        guard abs(clampedSpeed - speedMultiplier) > 0.001 else { return }

        speedMultiplier = clampedSpeed

        Logger.userAction("Speed set to \(Int(clampedSpeed * 100))%")
    }

    /// Resets speed to 100% (1.0x multiplier)
    func resetSpeed() {
        setSpeed(1.0)
    }

    /// Calculates effective BPM based on base BPM and current speed multiplier.
    /// - Parameter baseBPM: The original BPM from the chart/song
    /// - Returns: The effective BPM after applying speed multiplier
    func effectiveBPM(baseBPM: Double) -> Double {
        return baseBPM * speedMultiplier
    }

    /// Formats the speed for display (e.g., "75%")
    var formattedSpeed: String {
        return "\(Int(speedMultiplier * 100))%"
    }

    /// Formats effective BPM for display
    /// - Parameter baseBPM: The original BPM from the chart/song
    /// - Returns: Formatted string (e.g., "90 BPM")
    func formattedEffectiveBPM(baseBPM: Double) -> String {
        return "\(Int(effectiveBPM(baseBPM: baseBPM))) BPM"
    }

    // MARK: - Persistence (SC-06: Remember last-used speed per chart)

    /// Creates a stable persistence key from a PersistentIdentifier.
    /// Uses JSON encoding for a stable, deterministic representation across app launches.
    /// - Parameter chartID: The persistent identifier of the chart
    /// - Returns: A stable string key for UserDefaults storage
    private func persistenceKey(for chartID: PersistentIdentifier) -> String {
        // Encode using JSONEncoder for stable, deterministic representation
        do {
            let data = try JSONEncoder().encode(chartID)
            if let key = String(data: data, encoding: .utf8) {
                return key
            }
            Logger.error("Failed to convert PersistentIdentifier JSON data to UTF-8 string")
        } catch {
            Logger.error("Failed to JSON-encode PersistentIdentifier: \(error.localizedDescription)")
        }

        // Fallback: SHA-256 digest of description string.
        // Note: PersistentIdentifier.description stability is not guaranteed by Apple API;
        // this fallback may produce different keys across OS/framework updates.
        // The primary JSONEncoder path should handle most cases reliably.
        let stableIdentifier = String(describing: chartID)
        let inputData = Data(stableIdentifier.utf8)
        let digest = SHA256.hash(data: inputData)
        let hashString = digest.compactMap { String(format: "%02x", $0) }.joined()
        // Use first 32 hex characters (128 bits) of SHA-256 digest
        return "chart_\(String(hashString.prefix(32)))"
    }

    /// Loads the saved speed for a specific chart.
    /// - Parameter chartID: The persistent identifier of the chart
    /// - Returns: The saved speed multiplier, or 1.0 if none saved
    func loadSpeed(for chartID: PersistentIdentifier) -> Double {
        let key = persistenceKey(for: chartID)
        guard let speeds = userDefaults.dictionary(forKey: settingsKey) as? [String: Double],
              let savedSpeed = speeds[key] else {
            return 1.0
        }

        // Validate loaded value is within bounds and finite
        guard savedSpeed.isFinite else {
            Logger.warning("Loaded non-finite speed value for chart \(key), using default 1.0")
            return 1.0
        }

        let clampedSpeed = max(Self.minSpeed, min(Self.maxSpeed, savedSpeed))
        if clampedSpeed != savedSpeed {
            Logger.warning("Loaded out-of-range speed \(savedSpeed) for chart, clamped to \(clampedSpeed)")
        }

        return clampedSpeed
    }

    /// Saves the current speed for a specific chart.
    /// - Parameters:
    ///   - speed: The speed multiplier to save
    ///   - chartID: The persistent identifier of the chart
    func saveSpeed(_ speed: Double, for chartID: PersistentIdentifier) {
        // Validate speed value is finite
        guard speed.isFinite else {
            Logger.warning("Attempted to save non-finite speed value, ignoring")
            return
        }

        // Clamp speed to valid range
        let clampedSpeed = max(Self.minSpeed, min(Self.maxSpeed, speed))
        if clampedSpeed != speed {
            Logger.warning(
                "Speed \(speed) out of valid range [\(Self.minSpeed), \(Self.maxSpeed)], " +
                    "clamping to \(clampedSpeed)"
            )
        }

        let key = persistenceKey(for: chartID)
        var speeds = userDefaults.dictionary(forKey: settingsKey) as? [String: Double] ?? [:]
        speeds[key] = clampedSpeed
        userDefaults.set(speeds, forKey: settingsKey)

        // Verify persistence succeeded
        if let verified = userDefaults.dictionary(forKey: settingsKey) as? [String: Double],
           verified[key] == clampedSpeed {
            Logger.debug("Saved speed \(Int(clampedSpeed * 100))% for chart")
        } else {
            Logger.error("Failed to persist speed setting - value may not be saved")
        }
    }

    /// Loads saved speed for a chart and applies it to current state.
    /// - Parameter chartID: The persistent identifier of the chart
    func loadAndApplySpeed(for chartID: PersistentIdentifier) {
        let savedSpeed = loadSpeed(for: chartID)
        setSpeed(savedSpeed)
    }

    /// Clears all saved speed settings.
    func clearAllSavedSpeeds() {
        userDefaults.removeObject(forKey: settingsKey)
        Logger.debug("Cleared all saved speed settings")
    }
}
