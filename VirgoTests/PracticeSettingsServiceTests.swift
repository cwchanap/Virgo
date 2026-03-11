//
//  PracticeSettingsServiceTests.swift
//  VirgoTests
//
//  Unit tests for PracticeSettingsService speed control functionality.
//

import Testing
import SwiftData
@testable import Virgo

@Suite("PracticeSettingsService Tests", .serialized)
@MainActor
struct PracticeSettingsServiceTests {
    private func makeTestChartID(difficulty: Difficulty = .medium) throws -> PersistentIdentifier {
        let context = TestContainer.shared.context
        let song = Song(title: "Test", artist: "Test", bpm: 120.0, duration: "3:00", genre: "Test")
        context.insert(song)

        let chart = Chart(difficulty: difficulty, song: song)
        context.insert(chart)
        try context.save()

        return chart.persistentModelID
    }

    private func makeLegacyPersistenceKey(for chartID: PersistentIdentifier) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let canonicalData = try encoder.encode(chartID)
        guard let canonicalKey = String(data: canonicalData, encoding: .utf8) else {
            throw NSError(domain: "PracticeSettingsServiceTests", code: 1)
        }

        return addWhitespaceOutsideStrings(to: canonicalKey)
    }

    private func addWhitespaceOutsideStrings(to json: String) -> String {
        var result = ""
        var inString = false
        var isEscaping = false

        for character in json {
            if isEscaping {
                result.append(character)
                isEscaping = false
                continue
            }

            if character == "\\" {
                result.append(character)
                isEscaping = true
                continue
            }

            if character == "\"" {
                result.append(character)
                inString.toggle()
                continue
            }

            result.append(character)
            if !inString && (character == ":" || character == ",") {
                result.append(" ")
            }
        }

        return result
    }

    // MARK: - Initialization Tests

    @Test("Service initializes with default speed of 1.0")
    func testDefaultInitialization() {
        let service = PracticeSettingsService()
        #expect(service.speedMultiplier == 1.0)
    }

    @Test("Service accepts custom UserDefaults")
    func testCustomUserDefaults() {
        let (userDefaults, _) = TestUserDefaults.makeIsolated()
        let service = PracticeSettingsService(userDefaults: userDefaults)
        #expect(service.speedMultiplier == 1.0)
    }

    // MARK: - Speed Setting Tests

    @Test("setSpeed sets valid speed values")
    func testSetSpeedValidValues() {
        let service = PracticeSettingsService()

        service.setSpeed(0.5)
        #expect(service.speedMultiplier == 0.5)

        service.setSpeed(0.75)
        #expect(service.speedMultiplier == 0.75)

        service.setSpeed(1.0)
        #expect(service.speedMultiplier == 1.0)

        service.setSpeed(1.25)
        #expect(service.speedMultiplier == 1.25)

        service.setSpeed(1.5)
        #expect(service.speedMultiplier == 1.5)
    }

    @Test("setSpeed clamps values below minimum to 0.25")
    func testSetSpeedClampsBelowMinimum() {
        let service = PracticeSettingsService()

        service.setSpeed(0.1)
        #expect(service.speedMultiplier == 0.25)

        service.setSpeed(0.0)
        #expect(service.speedMultiplier == 0.25)

        service.setSpeed(-1.0)
        #expect(service.speedMultiplier == 0.25)
    }

    @Test("setSpeed clamps values above maximum to 1.5")
    func testSetSpeedClampsAboveMaximum() {
        let service = PracticeSettingsService()

        service.setSpeed(1.6)
        #expect(service.speedMultiplier == 1.5)

        service.setSpeed(2.0)
        #expect(service.speedMultiplier == 1.5)

        service.setSpeed(100.0)
        #expect(service.speedMultiplier == 1.5)
    }

    @Test("setSpeed handles boundary values exactly")
    func testSetSpeedBoundaryValues() {
        let service = PracticeSettingsService()

        service.setSpeed(PracticeSettingsService.minSpeed)
        #expect(service.speedMultiplier == 0.25)

        service.setSpeed(PracticeSettingsService.maxSpeed)
        #expect(service.speedMultiplier == 1.5)
    }

    @Test("setSpeed ignores non-finite values")
    func testSetSpeedIgnoresNonFiniteValues() {
        let service = PracticeSettingsService()

        // Set a known value first
        service.setSpeed(0.75)
        #expect(service.speedMultiplier == 0.75)

        // NaN should be ignored
        service.setSpeed(Double.nan)
        #expect(service.speedMultiplier == 0.75)

        // Infinity should be ignored
        service.setSpeed(Double.infinity)
        #expect(service.speedMultiplier == 0.75)

        // Negative infinity should be ignored
        service.setSpeed(-Double.infinity)
        #expect(service.speedMultiplier == 0.75)
    }

    @Test("resetSpeed sets speed back to 1.0")
    func testResetSpeed() {
        let service = PracticeSettingsService()

        service.setSpeed(0.5)
        #expect(service.speedMultiplier == 0.5)

        service.resetSpeed()
        #expect(service.speedMultiplier == 1.0)
    }

    // MARK: - Effective BPM Tests

    @Test("effectiveBPM calculates correctly at various speeds")
    func testEffectiveBPMCalculation() {
        let service = PracticeSettingsService()

        // At 100% speed
        service.setSpeed(1.0)
        #expect(service.effectiveBPM(baseBPM: 120.0) == 120.0)
        #expect(service.effectiveBPM(baseBPM: 90.0) == 90.0)

        // At 50% speed
        service.setSpeed(0.5)
        #expect(service.effectiveBPM(baseBPM: 120.0) == 60.0)
        #expect(service.effectiveBPM(baseBPM: 100.0) == 50.0)

        // At 75% speed
        service.setSpeed(0.75)
        #expect(service.effectiveBPM(baseBPM: 120.0) == 90.0)
        #expect(service.effectiveBPM(baseBPM: 80.0) == 60.0)

        // At 150% speed
        service.setSpeed(1.5)
        #expect(service.effectiveBPM(baseBPM: 100.0) == 150.0)
        #expect(service.effectiveBPM(baseBPM: 120.0) == 180.0)
    }

    @Test("effectiveBPM handles edge case BPM values")
    func testEffectiveBPMEdgeCases() {
        let service = PracticeSettingsService()

        service.setSpeed(1.0)
        #expect(service.effectiveBPM(baseBPM: 0.0) == 0.0)

        service.setSpeed(0.5)
        #expect(service.effectiveBPM(baseBPM: 1.0) == 0.5)
    }

    // MARK: - Formatting Tests

    @Test("formattedSpeed returns correct percentage string")
    func testFormattedSpeed() {
        let service = PracticeSettingsService()

        service.setSpeed(1.0)
        #expect(service.formattedSpeed == "100%")

        service.setSpeed(0.5)
        #expect(service.formattedSpeed == "50%")

        service.setSpeed(0.75)
        #expect(service.formattedSpeed == "75%")

        service.setSpeed(1.25)
        #expect(service.formattedSpeed == "125%")

        service.setSpeed(1.5)
        #expect(service.formattedSpeed == "150%")

        service.setSpeed(0.25)
        #expect(service.formattedSpeed == "25%")
    }

    @Test("formattedEffectiveBPM returns correct BPM string")
    func testFormattedEffectiveBPM() {
        let service = PracticeSettingsService()

        service.setSpeed(1.0)
        #expect(service.formattedEffectiveBPM(baseBPM: 120.0) == "120 BPM")

        service.setSpeed(0.5)
        #expect(service.formattedEffectiveBPM(baseBPM: 120.0) == "60 BPM")

        service.setSpeed(0.75)
        #expect(service.formattedEffectiveBPM(baseBPM: 120.0) == "90 BPM")

        service.setSpeed(1.5)
        #expect(service.formattedEffectiveBPM(baseBPM: 100.0) == "150 BPM")
    }

    // MARK: - Constants Tests

    @Test("Speed constants have expected values")
    func testSpeedConstants() {
        #expect(PracticeSettingsService.minSpeed == 0.25)
        #expect(PracticeSettingsService.maxSpeed == 1.5)
        #expect(PracticeSettingsService.speedIncrement == 0.05)
    }

    @Test("Speed presets contain expected values")
    func testSpeedPresets() {
        let presets = PracticeSettingsService.speedPresets
        #expect(presets.count == 4)
        #expect(presets.contains(0.50))
        #expect(presets.contains(0.75))
        #expect(presets.contains(1.00))
        #expect(presets.contains(1.25))
    }

    // MARK: - Persistence Tests

    @Test("saveSpeed and loadSpeed work correctly")
    func testSpeedPersistence() async throws {
        try await TestSetup.withTestSetup {
            let (userDefaults, _) = TestUserDefaults.makeIsolated()
            let service = PracticeSettingsService(userDefaults: userDefaults)
            let context = TestContainer.shared.context

            // Create a test chart
            let song = Song(title: "Test", artist: "Test", bpm: 120.0, duration: "3:00", genre: "Test")
            context.insert(song)
            let chart = Chart(difficulty: .medium, song: song)
            context.insert(chart)
            try context.save()

            let chartID = chart.persistentModelID

            // Default load should return 1.0
            let defaultSpeed = service.loadSpeed(for: chartID)
            #expect(defaultSpeed == 1.0)

            // Save a speed
            service.saveSpeed(0.75, for: chartID)

            // Load should return saved speed
            let loadedSpeed = service.loadSpeed(for: chartID)
            #expect(loadedSpeed == 0.75)

            // Save a different speed
            service.saveSpeed(1.25, for: chartID)
            let updatedSpeed = service.loadSpeed(for: chartID)
            #expect(updatedSpeed == 1.25)
        }
    }

    @Test("loadAndApplySpeed loads and applies saved speed")
    func testLoadAndApplySpeed() async throws {
        try await TestSetup.withTestSetup {
            let (userDefaults, _) = TestUserDefaults.makeIsolated()
            let service = PracticeSettingsService(userDefaults: userDefaults)
            let context = TestContainer.shared.context

            // Create a test chart
            let song = Song(title: "Test", artist: "Test", bpm: 120.0, duration: "3:00", genre: "Test")
            context.insert(song)
            let chart = Chart(difficulty: .medium, song: song)
            context.insert(chart)
            try context.save()

            let chartID = chart.persistentModelID

            // Save a speed for this chart
            service.saveSpeed(0.5, for: chartID)

            // Reset to default
            service.setSpeed(1.0)
            #expect(service.speedMultiplier == 1.0)

            // Load and apply
            service.loadAndApplySpeed(for: chartID)
            #expect(service.speedMultiplier == 0.5)
        }
    }

    @Test("clearAllSavedSpeeds removes all persisted speeds")
    func testClearAllSavedSpeeds() async throws {
        try await TestSetup.withTestSetup {
            let (userDefaults, _) = TestUserDefaults.makeIsolated()
            let service = PracticeSettingsService(userDefaults: userDefaults)
            let context = TestContainer.shared.context

            // Create test charts
            let song = Song(title: "Test", artist: "Test", bpm: 120.0, duration: "3:00", genre: "Test")
            context.insert(song)
            let chart1 = Chart(difficulty: .easy, song: song)
            let chart2 = Chart(difficulty: .hard, song: song)
            context.insert(chart1)
            context.insert(chart2)
            try context.save()

            // Save speeds for both charts
            service.saveSpeed(0.5, for: chart1.persistentModelID)
            service.saveSpeed(1.25, for: chart2.persistentModelID)

            // Verify speeds were saved
            #expect(service.loadSpeed(for: chart1.persistentModelID) == 0.5)
            #expect(service.loadSpeed(for: chart2.persistentModelID) == 1.25)

            // Clear all
            service.clearAllSavedSpeeds()

            // Should return default (1.0) for both
            #expect(service.loadSpeed(for: chart1.persistentModelID) == 1.0)
            #expect(service.loadSpeed(for: chart2.persistentModelID) == 1.0)
        }
    }

    @Test("Different charts maintain separate speed settings")
    func testSeparateSpeedPerChart() async throws {
        try await TestSetup.withTestSetup {
            let (userDefaults, _) = TestUserDefaults.makeIsolated()
            let service = PracticeSettingsService(userDefaults: userDefaults)
            let context = TestContainer.shared.context

            // Create multiple charts
            let song = Song(title: "Test", artist: "Test", bpm: 120.0, duration: "3:00", genre: "Test")
            context.insert(song)

            let difficulties: [Difficulty] = [.easy, .medium, .hard]
            let charts = difficulties.map { difficulty in
                Chart(difficulty: difficulty, song: song)
            }
            charts.forEach { context.insert($0) }
            try context.save()

            // Save different speeds for each chart
            service.saveSpeed(0.5, for: charts[0].persistentModelID)
            service.saveSpeed(0.75, for: charts[1].persistentModelID)
            service.saveSpeed(1.25, for: charts[2].persistentModelID)

            // Verify each chart has its own speed
            #expect(service.loadSpeed(for: charts[0].persistentModelID) == 0.5)
            #expect(service.loadSpeed(for: charts[1].persistentModelID) == 0.75)
            #expect(service.loadSpeed(for: charts[2].persistentModelID) == 1.25)
        }
    }

    @Test("loadSpeed decodes NSNumber and String payloads from UserDefaults")
    func testLoadSpeedDecodesNSNumberAndStringValues() async throws {
        try await TestSetup.withTestSetup {
            let (userDefaults, _) = TestUserDefaults.makeIsolated()
            let chartID = try makeTestChartID()
            let seedingService = PracticeSettingsService(userDefaults: userDefaults)
            seedingService.saveSpeed(1.0, for: chartID)

            guard let key = userDefaults.dictionary(forKey: "PracticeSettingsSpeedMultipliers")?.keys.first else {
                Issue.record("Expected a persisted speed key to be created")
                return
            }

            userDefaults.set([key: NSNumber(value: 0.75)], forKey: "PracticeSettingsSpeedMultipliers")
            let numberLoaded = PracticeSettingsService(userDefaults: userDefaults).loadSpeed(for: chartID)
            #expect(numberLoaded == 0.75)

            userDefaults.set([key: "1.25"], forKey: "PracticeSettingsSpeedMultipliers")
            let stringLoaded = PracticeSettingsService(userDefaults: userDefaults).loadSpeed(for: chartID)
            #expect(stringLoaded == 1.25)
        }
    }

    @Test("loadSpeed reads legacy persistence keys and migrates them to canonical format")
    func testLoadSpeedMigratesLegacyPersistenceKeys() async throws {
        try await TestSetup.withTestSetup {
            let (userDefaults, _) = TestUserDefaults.makeIsolated()
            let chartID = try makeTestChartID()
            let legacyKey = try makeLegacyPersistenceKey(for: chartID)

            userDefaults.set([legacyKey: 0.8], forKey: "PracticeSettingsSpeedMultipliers")

            let loadedSpeed = PracticeSettingsService(userDefaults: userDefaults).loadSpeed(for: chartID)
            #expect(loadedSpeed == 0.8)

            let persistedKeys = userDefaults.dictionary(forKey: "PracticeSettingsSpeedMultipliers").map {
                Array($0.keys)
            } ?? []
            #expect(persistedKeys.contains(legacyKey) == false)
            #expect(persistedKeys.count == 1)
        }
    }

    @Test("loadSpeed clamps out-of-range values and ignores unsupported payload types")
    func testLoadSpeedClampsAndIgnoresUnsupportedPersistedValues() async throws {
        try await TestSetup.withTestSetup {
            let (userDefaults, _) = TestUserDefaults.makeIsolated()
            let chartID = try makeTestChartID()
            let seedingService = PracticeSettingsService(userDefaults: userDefaults)
            seedingService.saveSpeed(1.0, for: chartID)

            guard let key = userDefaults.dictionary(forKey: "PracticeSettingsSpeedMultipliers")?.keys.first else {
                Issue.record("Expected a persisted speed key to be created")
                return
            }

            userDefaults.set([key: -2.0], forKey: "PracticeSettingsSpeedMultipliers")
            let clampedLow = PracticeSettingsService(userDefaults: userDefaults).loadSpeed(for: chartID)
            #expect(clampedLow == PracticeSettingsService.minSpeed)

            userDefaults.set([key: 3.0], forKey: "PracticeSettingsSpeedMultipliers")
            let clampedHigh = PracticeSettingsService(userDefaults: userDefaults).loadSpeed(for: chartID)
            #expect(clampedHigh == PracticeSettingsService.maxSpeed)

            userDefaults.set([key: ["unsupported"]], forKey: "PracticeSettingsSpeedMultipliers")
            let fallbackValue = PracticeSettingsService(userDefaults: userDefaults).loadSpeed(for: chartID)
            #expect(fallbackValue == 1.0)
        }
    }

    @Test("saveSpeed clamps persisted values and ignores non-finite input")
    func testSaveSpeedClampsAndIgnoresNonFiniteValues() async throws {
        try await TestSetup.withTestSetup {
            let (userDefaults, _) = TestUserDefaults.makeIsolated()
            let service = PracticeSettingsService(userDefaults: userDefaults)
            let chartID = try makeTestChartID()

            service.saveSpeed(0.1, for: chartID)
            let clampedLow = PracticeSettingsService(userDefaults: userDefaults).loadSpeed(for: chartID)
            #expect(clampedLow == PracticeSettingsService.minSpeed)

            service.saveSpeed(3.0, for: chartID)
            let clampedHigh = PracticeSettingsService(userDefaults: userDefaults).loadSpeed(for: chartID)
            #expect(clampedHigh == PracticeSettingsService.maxSpeed)

            service.saveSpeed(0.75, for: chartID)
            service.saveSpeed(Double.nan, for: chartID)
            let preservedValue = PracticeSettingsService(userDefaults: userDefaults).loadSpeed(for: chartID)
            #expect(preservedValue == 0.75)
        }
    }

    @Test("clearAllSavedSpeeds clears persisted values and session cache")
    func testClearAllSavedSpeedsClearsSessionCache() async throws {
        try await TestSetup.withTestSetup {
            let (userDefaults, _) = TestUserDefaults.makeIsolated()
            let service = PracticeSettingsService(userDefaults: userDefaults)
            let chartID = try makeTestChartID()

            service.saveSpeed(0.75, for: chartID)
            #expect(service.loadSpeed(for: chartID) == 0.75)

            service.clearAllSavedSpeeds()

            #expect(service.loadSpeed(for: chartID) == 1.0)
            #expect(userDefaults.dictionary(forKey: "PracticeSettingsSpeedMultipliers") == nil)
        }
    }
}
