//
//  ScorePersistenceServiceTests.swift
//  VirgoTests
//
//  Unit tests for SwiftData-backed score persistence.
//

import Testing
import SwiftData
import Foundation
@testable import Virgo

@Suite("ScorePersistenceService Tests", .serialized)
@MainActor
struct ScorePersistenceServiceTests {

    /// Inserts a Song + Chart into the shared test context and saves.
    private func makeTestChart(difficulty: Difficulty = .medium) throws -> Chart {
        let context = TestContainer.shared.context
        let song = Song(title: "Test", artist: "Test", bpm: 120.0, duration: "3:00", genre: "Rock")
        context.insert(song)
        let chart = Chart(difficulty: difficulty, song: song)
        context.insert(chart)
        try context.save()
        return chart
    }

    @Test("ScoreRecord persists and links to its chart")
    func testScoreRecordPersists() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let chart = try makeTestChart()

            let record = ScoreRecord(
                score: 1500,
                maxCombo: 12,
                accuracy: 92.5,
                speedMultiplier: 1.0,
                playedAt: Date(),
                chart: chart
            )
            context.insert(record)
            try context.save()

            // Inserting a raw ScoreRecord must not change bestScore; the all-time
            // best is updated only by the service layer (added in a later task).
            #expect(chart.bestScore == 0)
            #expect(chart.scoreRecords.count == 1)
            #expect(chart.scoreRecords.first?.score == 1500)
            #expect(chart.scoreRecords.first?.speedMultiplier == 1.0)
        }
    }

    @Test("Deleting a chart cascade-deletes its score records")
    func testCascadeDeleteRemovesScoreRecords() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let chart = try makeTestChart()
            let record = ScoreRecord(
                score: 100,
                maxCombo: 5,
                accuracy: 80.0,
                speedMultiplier: 1.0,
                playedAt: Date(),
                chart: chart
            )
            context.insert(record)
            try context.save()

            context.delete(chart)
            try context.save()

            let remaining = try context.fetch(FetchDescriptor<ScoreRecord>())
            #expect(remaining.isEmpty)
        }
    }

    @Test("recordAttempt at full speed sets a new best and returns true")
    func testRecordAttemptFullSpeedSetsBest() async throws {
        try await TestSetup.withTestSetup {
            let chart = try makeTestChart()
            let service = ScorePersistenceService(modelContext: TestContainer.shared.context)
            var engine = ScoreEngine()
            for _ in 0..<10 { engine.processHit(accuracy: .perfect, timingError: 0) }
            let snapshot = LiveScoreSnapshot(scoreEngine: engine)

            let isNewBest = service.recordAttempt(
                snapshot, for: chart, atFullSpeed: true, speedMultiplier: 1.0
            )

            #expect(isNewBest == true)
            #expect(service.bestScore(for: chart) == snapshot.score)
            #expect(chart.scoreRecords.count == 1)
        }
    }

    @Test("recordAttempt below current best returns false and keeps best")
    func testRecordAttemptLowerScoreKeepsBest() async throws {
        try await TestSetup.withTestSetup {
            let chart = try makeTestChart()
            let service = ScorePersistenceService(modelContext: TestContainer.shared.context)
            chart.bestScore = 5000

            var engine = ScoreEngine()
            for _ in 0..<3 { engine.processHit(accuracy: .good, timingError: 0) }
            let snapshot = LiveScoreSnapshot(scoreEngine: engine)

            let isNewBest = service.recordAttempt(
                snapshot, for: chart, atFullSpeed: true, speedMultiplier: 1.0
            )

            #expect(isNewBest == false)
            #expect(service.bestScore(for: chart) == 5000)
            #expect(chart.scoreRecords.count == 1) // still recorded in history
        }
    }

    @Test("recordAttempt not at full speed records history but never sets best")
    func testRecordAttemptSlowedDoesNotSetBest() async throws {
        try await TestSetup.withTestSetup {
            let chart = try makeTestChart()
            let service = ScorePersistenceService(modelContext: TestContainer.shared.context)
            var engine = ScoreEngine()
            for _ in 0..<20 { engine.processHit(accuracy: .perfect, timingError: 0) }
            let snapshot = LiveScoreSnapshot(scoreEngine: engine)

            let isNewBest = service.recordAttempt(
                snapshot, for: chart, atFullSpeed: false, speedMultiplier: 0.5
            )

            #expect(isNewBest == false)
            #expect(service.bestScore(for: chart) == 0)
            #expect(chart.scoreRecords.count == 1)
            #expect(chart.scoreRecords.first?.speedMultiplier == 0.5)
        }
    }

    @Test("recordAttempt with zero score never sets best")
    func testRecordAttemptZeroScore() async throws {
        try await TestSetup.withTestSetup {
            let chart = try makeTestChart()
            let service = ScorePersistenceService(modelContext: TestContainer.shared.context)
            let snapshot = LiveScoreSnapshot(scoreEngine: ScoreEngine())

            let isNewBest = service.recordAttempt(
                snapshot, for: chart, atFullSpeed: true, speedMultiplier: 1.0
            )

            #expect(isNewBest == false)
            #expect(service.bestScore(for: chart) == 0)
            #expect(chart.scoreRecords.count == 1)
        }
    }

    @Test("recordAttempt prunes to the 10 most recent by playedAt")
    func testRecordAttemptPrunesToTen() async throws {
        try await TestSetup.withTestSetup {
            let chart = try makeTestChart()
            let service = ScorePersistenceService(modelContext: TestContainer.shared.context)
            let base = Date(timeIntervalSince1970: 1_000_000)

            // Insert 12 attempts with increasing timestamps and scores.
            for i in 0..<12 {
                var engine = ScoreEngine()
                for _ in 0...(i) { engine.processHit(accuracy: .good, timingError: 0) }
                let snapshot = LiveScoreSnapshot(scoreEngine: engine)
                _ = service.recordAttempt(
                    snapshot, for: chart, atFullSpeed: false, speedMultiplier: 1.0,
                    now: base.addingTimeInterval(Double(i))
                )
            }

            #expect(chart.scoreRecords.count == 10)
            // Oldest two (i = 0, 1) should have been pruned.
            let earliest = chart.scoreRecords.map { $0.playedAt }.min()
            #expect(earliest == base.addingTimeInterval(2))
        }
    }

    @Test("recentAttempts returns DTOs newest-first, limited, with all fields")
    func testRecentAttemptsMapsAndSorts() async throws {
        try await TestSetup.withTestSetup {
            let chart = try makeTestChart()
            let service = ScorePersistenceService(modelContext: TestContainer.shared.context)
            let base = Date(timeIntervalSince1970: 2_000_000)

            for i in 0..<3 {
                var engine = ScoreEngine()
                for _ in 0...(i) { engine.processHit(accuracy: .perfect, timingError: 0) }
                let snapshot = LiveScoreSnapshot(scoreEngine: engine)
                _ = service.recordAttempt(
                    snapshot, for: chart, atFullSpeed: true,
                    speedMultiplier: 0.75, now: base.addingTimeInterval(Double(i))
                )
            }

            let attempts = service.recentAttempts(for: chart)
            #expect(attempts.count == 3)
            #expect(attempts.first?.playedAt == base.addingTimeInterval(2)) // newest first
            #expect(attempts.last?.playedAt == base)
            #expect(attempts.first?.speedMultiplier == 0.75)
            #expect(attempts.first?.maxCombo ?? 0 > 0)

            let limited = service.recentAttempts(for: chart, limit: 2)
            #expect(limited.count == 2)
        }
    }
}
