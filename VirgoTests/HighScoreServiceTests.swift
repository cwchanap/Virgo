//
//  HighScoreServiceTests.swift
//  VirgoTests
//
//  Unit tests for HighScoreService - per-chart high score persistence.
//  Written BEFORE implementation (TDD).
//  All SwiftData model access occurs inside TestSetup.withTestSetup {},
//  matching the pattern established in PracticeSettingsServiceTests.
//

import Testing
import SwiftData
@testable import Virgo

@Suite("HighScoreService Tests", .serialized)
@MainActor
struct HighScoreServiceTests {

    // MARK: - Helper

    /// Creates and inserts a Song and Chart, saves the context, and returns the Chart.
    private func makeTestChart(difficulty: Difficulty = .medium) throws -> Chart {
        let context = TestContainer.shared.context
        let song = Song(title: "Test", artist: "Test", bpm: 120.0, duration: "3:00", genre: "Rock")
        context.insert(song)
        let chart = Chart(difficulty: difficulty, song: song)
        context.insert(chart)
        try context.save()
        return chart
    }

    // MARK: - Default State

    @Test("Default high score is 0 for an unseen chart")
    func testDefaultHighScore() async throws {
        try await TestSetup.withTestSetup {
            let (ud, _) = TestUserDefaults.makeIsolated()
            let service = HighScoreService(userDefaults: ud)
            let chart = try makeTestChart()

            #expect(service.highScore(for: chart.persistentModelID) == 0)
        }
    }

    // MARK: - Save and Load

    @Test("saveIfHighScore saves and returns true for first score")
    func testSavesFirstScore() async throws {
        try await TestSetup.withTestSetup {
            let (ud, _) = TestUserDefaults.makeIsolated()
            let service = HighScoreService(userDefaults: ud)
            let chart = try makeTestChart()

            let isNew = service.saveIfHighScore(1500, for: chart.persistentModelID)
            #expect(isNew == true)
            #expect(service.highScore(for: chart.persistentModelID) == 1500)
        }
    }

    @Test("saveIfHighScore saves higher score and returns true")
    func testSavesHigherScore() async throws {
        try await TestSetup.withTestSetup {
            let (ud, _) = TestUserDefaults.makeIsolated()
            let service = HighScoreService(userDefaults: ud)
            let chart = try makeTestChart()

            _ = service.saveIfHighScore(1000, for: chart.persistentModelID)
            let isNew = service.saveIfHighScore(1500, for: chart.persistentModelID)
            #expect(isNew == true)
            #expect(service.highScore(for: chart.persistentModelID) == 1500)
        }
    }

    @Test("saveIfHighScore rejects lower score and returns false")
    func testRejectsLowerScore() async throws {
        try await TestSetup.withTestSetup {
            let (ud, _) = TestUserDefaults.makeIsolated()
            let service = HighScoreService(userDefaults: ud)
            let chart = try makeTestChart()

            _ = service.saveIfHighScore(1500, for: chart.persistentModelID)
            let isNew = service.saveIfHighScore(500, for: chart.persistentModelID)
            #expect(isNew == false)
            #expect(service.highScore(for: chart.persistentModelID) == 1500)
        }
    }

    @Test("saveIfHighScore rejects equal score and returns false")
    func testRejectsEqualScore() async throws {
        try await TestSetup.withTestSetup {
            let (ud, _) = TestUserDefaults.makeIsolated()
            let service = HighScoreService(userDefaults: ud)
            let chart = try makeTestChart()

            _ = service.saveIfHighScore(1000, for: chart.persistentModelID)
            let isNew = service.saveIfHighScore(1000, for: chart.persistentModelID)
            #expect(isNew == false)
            #expect(service.highScore(for: chart.persistentModelID) == 1000)
        }
    }

    // MARK: - Persistence Across Instances

    @Test("High score persists across service instances using same UserDefaults")
    func testPersistsAcrossInstances() async throws {
        try await TestSetup.withTestSetup {
            let (ud, _) = TestUserDefaults.makeIsolated()
            let chart = try makeTestChart()

            let service1 = HighScoreService(userDefaults: ud)
            _ = service1.saveIfHighScore(2000, for: chart.persistentModelID)

            let service2 = HighScoreService(userDefaults: ud)
            #expect(service2.highScore(for: chart.persistentModelID) == 2000)
        }
    }

    // MARK: - Multiple Charts

    @Test("High scores are isolated per chart")
    func testScoresIsolatedPerChart() async throws {
        try await TestSetup.withTestSetup {
            let (ud, _) = TestUserDefaults.makeIsolated()
            let service = HighScoreService(userDefaults: ud)
            let chartA = try makeTestChart(difficulty: .easy)
            let chartB = try makeTestChart(difficulty: .hard)

            _ = service.saveIfHighScore(100, for: chartA.persistentModelID)
            _ = service.saveIfHighScore(500, for: chartB.persistentModelID)

            #expect(service.highScore(for: chartA.persistentModelID) == 100)
            #expect(service.highScore(for: chartB.persistentModelID) == 500)
        }
    }

    // MARK: - Clear All

    @Test("clearAllHighScores resets all charts to 0")
    func testClearAll() async throws {
        try await TestSetup.withTestSetup {
            let (ud, _) = TestUserDefaults.makeIsolated()
            let service = HighScoreService(userDefaults: ud)
            let chart = try makeTestChart()

            _ = service.saveIfHighScore(1000, for: chart.persistentModelID)
            service.clearAllHighScores()
            #expect(service.highScore(for: chart.persistentModelID) == 0)
        }
    }

    // MARK: - Invalid Input Guards

    @Test("Negative score is rejected")
    func testRejectsNegativeScore() async throws {
        try await TestSetup.withTestSetup {
            let (ud, _) = TestUserDefaults.makeIsolated()
            let service = HighScoreService(userDefaults: ud)
            let chart = try makeTestChart()

            let isNew = service.saveIfHighScore(-1, for: chart.persistentModelID)
            #expect(isNew == false)
            #expect(service.highScore(for: chart.persistentModelID) == 0)
        }
    }

    @Test("Zero score does not beat default of 0")
    func testZeroScoreNotSaved() async throws {
        try await TestSetup.withTestSetup {
            let (ud, _) = TestUserDefaults.makeIsolated()
            let service = HighScoreService(userDefaults: ud)
            let chart = try makeTestChart()

            let isNew = service.saveIfHighScore(0, for: chart.persistentModelID)
            #expect(isNew == false)
            #expect(service.highScore(for: chart.persistentModelID) == 0)
        }
    }
}
