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

    // MARK: - Persistence (SC-06: Remember last-used speed per song/chart)

    /// Loads the saved speed for a specific chart.
    /// - Parameter chartID: The persistent identifier of the chart
    /// - Returns: The saved speed multiplier, or 1.0 if none saved
    func loadSpeed(for chartID: PersistentIdentifier) -> Double {
        let key = chartID.hashValue.description
        guard let speeds = userDefaults.dictionary(forKey: settingsKey) as? [String: Double],
              let savedSpeed = speeds[key] else {
            return 1.0
        }
        return savedSpeed
    }

    /// Saves the current speed for a specific chart.
    /// - Parameters:
    ///   - speed: The speed multiplier to save
    ///   - chartID: The persistent identifier of the chart
    func saveSpeed(_ speed: Double, for chartID: PersistentIdentifier) {
        let key = chartID.hashValue.description
        var speeds = userDefaults.dictionary(forKey: settingsKey) as? [String: Double] ?? [:]
        speeds[key] = speed
        userDefaults.set(speeds, forKey: settingsKey)
        Logger.debug("Saved speed \(Int(speed * 100))% for chart \(key)")
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
