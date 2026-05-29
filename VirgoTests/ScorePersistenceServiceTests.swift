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
}
