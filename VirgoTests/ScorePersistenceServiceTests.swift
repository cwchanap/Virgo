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

    private enum SaveHookError: Error {
        case forced
    }

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

    @Test("ScoreRecord initializer clamps accuracy and preserves metadata")
    func testScoreRecordInitializerClampsAccuracy() async throws {
        try await TestSetup.withTestSetup {
            let date = Date(timeIntervalSince1970: 123)
            let lowAccuracy = ScoreRecord(
                score: 1,
                maxCombo: 2,
                accuracy: -20.0,
                speedMultiplier: 0.5,
                playedAt: date
            )
            let highAccuracy = ScoreRecord(
                score: 3,
                maxCombo: 4,
                accuracy: 140.0,
                speedMultiplier: 1.25,
                playedAt: date.addingTimeInterval(1)
            )

            #expect(lowAccuracy.accuracy == 0.0)
            #expect(highAccuracy.accuracy == 100.0)
            #expect(lowAccuracy.score == 1)
            #expect(lowAccuracy.maxCombo == 2)
            #expect(lowAccuracy.speedMultiplier == 0.5)
            #expect(lowAccuracy.playedAt == date)
            #expect(lowAccuracy.chart == nil)
        }
    }

    @Test("ScoreAttemptSummary preserves values and supports equality")
    func testScoreAttemptSummaryValueSemantics() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let chart = try makeTestChart()
            let date = Date(timeIntervalSince1970: 456)
            let record = ScoreRecord(
                score: 1234,
                maxCombo: 32,
                accuracy: 91.5,
                speedMultiplier: 0.75,
                playedAt: date,
                chart: chart
            )
            context.insert(record)
            try context.save()

            let summary = ScoreAttemptSummary(
                id: record.persistentModelID,
                score: record.score,
                maxCombo: record.maxCombo,
                accuracy: record.accuracy,
                speedMultiplier: record.speedMultiplier,
                playedAt: record.playedAt
            )
            let copy = ScoreAttemptSummary(
                id: record.persistentModelID,
                score: 1234,
                maxCombo: 32,
                accuracy: 91.5,
                speedMultiplier: 0.75,
                playedAt: date
            )

            #expect(summary == copy)
            #expect(summary.id == record.persistentModelID)
            #expect(summary.score == 1234)
            #expect(summary.maxCombo == 32)
            #expect(summary.accuracy == 91.5)
            #expect(summary.speedMultiplier == 0.75)
            #expect(summary.playedAt == date)
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

            #expect(isNewBest == .newBest)
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

            #expect(isNewBest == .recorded)
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

            #expect(isNewBest == .recorded)
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

            #expect(isNewBest == .recorded)
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
            #expect(attempts.first?.maxCombo == 3)

            let limited = service.recentAttempts(for: chart, limit: 2)
            #expect(limited.count == 2)
        }
    }

    @Test("migrateLegacyHighScores copies legacy bests into Chart.bestScore once")
    func testMigrateLegacyHighScores() async throws {
        try await TestSetup.withTestSetup {
            let chart = try makeTestChart()
            let service = ScorePersistenceService(modelContext: TestContainer.shared.context)
            let (userDefaults, _) = TestUserDefaults.makeIsolated()

            let key = PersistentIdentifierPersistenceKey.canonicalKey(
                for: chart.persistentModelID, logPrefix: "Test"
            )
            userDefaults.set([key: 3300], forKey: "HighScorePerChart")

            service.migrateLegacyHighScores(charts: [chart], from: userDefaults)

            #expect(chart.bestScore == 3300)
            #expect(userDefaults.bool(forKey: "DidMigrateHighScoresToSwiftData") == true)
            #expect(userDefaults.dictionary(forKey: "HighScorePerChart") == nil)
        }
    }

    @Test("migrateLegacyHighScores is idempotent and never lowers an existing best")
    func testMigrateLegacyHighScoresIdempotent() async throws {
        try await TestSetup.withTestSetup {
            let chart = try makeTestChart()
            let service = ScorePersistenceService(modelContext: TestContainer.shared.context)
            let (userDefaults, _) = TestUserDefaults.makeIsolated()

            let key = PersistentIdentifierPersistenceKey.canonicalKey(
                for: chart.persistentModelID, logPrefix: "Test"
            )
            userDefaults.set([key: 1000], forKey: "HighScorePerChart")
            service.migrateLegacyHighScores(charts: [chart], from: userDefaults)
            #expect(chart.bestScore == 1000)

            // A second run with a different dict must be ignored (flag already set).
            userDefaults.set([key: 9999], forKey: "HighScorePerChart")
            service.migrateLegacyHighScores(charts: [chart], from: userDefaults)
            #expect(chart.bestScore == 1000)
        }
    }

    @Test("migrateLegacyHighScores with no legacy data still sets the flag")
    func testMigrateLegacyHighScoresNoLegacyData() async throws {
        try await TestSetup.withTestSetup {
            let chart = try makeTestChart()
            let service = ScorePersistenceService(modelContext: TestContainer.shared.context)
            let (userDefaults, _) = TestUserDefaults.makeIsolated()

            // No "HighScorePerChart" key set at all.
            service.migrateLegacyHighScores(charts: [chart], from: userDefaults)

            #expect(chart.bestScore == 0)
            #expect(userDefaults.bool(forKey: "DidMigrateHighScoresToSwiftData") == true)
        }
    }

    @Test("migrateLegacyHighScores accepts NSNumber values and ignores non-numeric entries")
    func testMigrateLegacyHighScoresReadsNSNumberValues() async throws {
        try await TestSetup.withTestSetup {
            let chart = try makeTestChart()
            let otherChart = try makeTestChart(difficulty: .hard)
            let service = ScorePersistenceService(modelContext: TestContainer.shared.context)
            let (userDefaults, _) = TestUserDefaults.makeIsolated()

            let key = PersistentIdentifierPersistenceKey.canonicalKey(
                for: chart.persistentModelID, logPrefix: "Test"
            )
            let ignoredKey = PersistentIdentifierPersistenceKey.canonicalKey(
                for: otherChart.persistentModelID, logPrefix: "Test"
            )
            userDefaults.set(
                [key: NSDecimalNumber(value: 4400), ignoredKey: "not numeric"],
                forKey: "HighScorePerChart"
            )

            service.migrateLegacyHighScores(charts: [chart, otherChart], from: userDefaults)

            #expect(chart.bestScore == 4400)
            #expect(otherChart.bestScore == 0)
            #expect(userDefaults.bool(forKey: "DidMigrateHighScoresToSwiftData") == true)
        }
    }

    @Test("makeInMemory adopts detached charts before recording attempts")
    func testMakeInMemoryRecordsDetachedChart() async throws {
        try await TestSetup.withTestSetup {
            let service = ScorePersistenceService.makeInMemory()
            let chart = Chart(difficulty: .expert)
            var engine = ScoreEngine()
            engine.processHit(accuracy: .perfect, timingError: 0)
            let snapshot = LiveScoreSnapshot(scoreEngine: engine)

            let isNewBest = service.recordAttempt(
                snapshot, for: chart, atFullSpeed: true, speedMultiplier: 1.0
            )

            #expect(isNewBest == .newBest)
            #expect(chart.modelContext != nil)
            #expect(chart.bestScore == snapshot.score)
            #expect(chart.scoreRecords.count == 1)
        }
    }

    @Test("recordAttempt prunes correctly and maintains exact count after multiple calls")
    func testRecordAttemptPruneMaintainsInvariant() async throws {
        try await TestSetup.withTestSetup {
            let chart = try makeTestChart()
            let service = ScorePersistenceService(modelContext: TestContainer.shared.context)
            let base = Date(timeIntervalSince1970: 3_000_000)

            // Insert exactly maxRecentAttempts + 1 records to trigger one prune.
            for i in 0...ScorePersistenceService.maxRecentAttempts {
                var engine = ScoreEngine()
                for _ in 0...i { engine.processHit(accuracy: .good, timingError: 0) }
                let snapshot = LiveScoreSnapshot(scoreEngine: engine)
                _ = service.recordAttempt(
                    snapshot, for: chart, atFullSpeed: false, speedMultiplier: 1.0,
                    now: base.addingTimeInterval(Double(i))
                )
            }

            // Should have exactly maxRecentAttempts records.
            #expect(chart.scoreRecords.count == ScorePersistenceService.maxRecentAttempts)
            // The oldest record (i=0) should have been pruned.
            let earliest = chart.scoreRecords.map { $0.playedAt }.min()
            #expect(earliest == base.addingTimeInterval(1))
        }
    }

    @Test("migrateLegacyHighScores skips legacy scores lower than current best")
    func testMigrateLegacyHighScoresIgnoresLowerScores() async throws {
        try await TestSetup.withTestSetup {
            let chart = try makeTestChart()
            chart.bestScore = 5000
            let service = ScorePersistenceService(modelContext: TestContainer.shared.context)
            let (userDefaults, _) = TestUserDefaults.makeIsolated()

            let key = PersistentIdentifierPersistenceKey.canonicalKey(
                for: chart.persistentModelID, logPrefix: "Test"
            )
            userDefaults.set([key: 3000], forKey: "HighScorePerChart")

            service.migrateLegacyHighScores(charts: [chart], from: userDefaults)

            #expect(chart.bestScore == 5000)
            #expect(userDefaults.bool(forKey: "DidMigrateHighScoresToSwiftData") == true)
        }
    }

    @Test("migrateLegacyHighScores clears stale legacy data when nothing is updated")
    func testMigrateLegacyHighScoresClearsLegacyDataWithoutUpdates() async throws {
        try await TestSetup.withTestSetup {
            let chart = try makeTestChart()
            chart.bestScore = 5000
            let service = ScorePersistenceService(modelContext: TestContainer.shared.context)
            let (userDefaults, _) = TestUserDefaults.makeIsolated()

            let key = PersistentIdentifierPersistenceKey.canonicalKey(
                for: chart.persistentModelID,
                logPrefix: "Test"
            )
            userDefaults.set([key: 100], forKey: "HighScorePerChart")

            service.migrateLegacyHighScores(charts: [chart], from: userDefaults)

            #expect(chart.bestScore == 5000)
            #expect(userDefaults.dictionary(forKey: "HighScorePerChart") == nil)
            #expect(userDefaults.bool(forKey: "DidMigrateHighScoresToSwiftData") == true)
        }
    }

    @Test("RecordResult cases compare by value")
    func testRecordResultEquatableCases() {
        #expect(ScorePersistenceService.RecordResult.newBest == .newBest)
        #expect(ScorePersistenceService.RecordResult.recorded == .recorded)
        #expect(ScorePersistenceService.RecordResult.saveFailed == .saveFailed)
        #expect(ScorePersistenceService.RecordResult.newBest != .recorded)
        #expect(ScorePersistenceService.RecordResult.recorded != .saveFailed)
    }

    @Test("migrateLegacyHighScores returns early when migration flag is already set")
    func testMigrateLegacyHighScoresSkipsWhenFlagAlreadySet() async throws {
        try await TestSetup.withTestSetup {
            let chart = try makeTestChart()
            chart.bestScore = 1000
            let service = ScorePersistenceService(modelContext: TestContainer.shared.context)
            let (userDefaults, _) = TestUserDefaults.makeIsolated()

            let key = PersistentIdentifierPersistenceKey.canonicalKey(
                for: chart.persistentModelID, logPrefix: "Test"
            )
            userDefaults.set([key: 9999], forKey: "HighScorePerChart")
            userDefaults.set(true, forKey: "DidMigrateHighScoresToSwiftData")

            service.migrateLegacyHighScores(charts: [chart], from: userDefaults)

            #expect(chart.bestScore == 1000)
        }
    }

    // MARK: - Save-failure rollback tests

    @Test("recordAttempt rollback on save failure restores chart state")
    func testRecordAttemptRollbackOnSaveFailure() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let chart = try makeTestChart()
            chart.bestScore = 5000
            // Pre-populate with existing records so we can verify they are untouched.
            let base = Date(timeIntervalSince1970: 4_000_000)
            for i in 0..<ScorePersistenceService.maxRecentAttempts {
                let record = ScoreRecord(
                    score: 100 * (i + 1),
                    maxCombo: i,
                    accuracy: 80.0,
                    speedMultiplier: 1.0,
                    playedAt: base.addingTimeInterval(Double(i)),
                    chart: chart
                )
                context.insert(record)
            }
            try context.save()
            let originalRecordCount = chart.scoreRecords.count

            let service = ScorePersistenceService(
                modelContext: context,
                saveContext: { _ in throw SaveHookError.forced }
            )

            var engine = ScoreEngine()
            for _ in 0..<10 { engine.processHit(accuracy: .perfect, timingError: 0) }
            let snapshot = LiveScoreSnapshot(scoreEngine: engine)

            let result = service.recordAttempt(
                snapshot, for: chart, atFullSpeed: true, speedMultiplier: 1.0
            )

            #expect(result == .saveFailed)
            // bestScore must be restored to its pre-attempt value.
            #expect(chart.bestScore == 5000)
            // Pruning is deferred until after save succeeds, so existing records are untouched.
            // The new record is deleted but SwiftData doesn't remove it from the relationship
            // array until the next save — commit the pending delete to verify the final count.
            try context.save()
            #expect(chart.scoreRecords.count == originalRecordCount)
        }
    }

    @Test("recentAttempts excludes deleted records after save failure")
    func testRecentAttemptsExcludesDeletedRecords() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let chart = try makeTestChart()
            // Pre-populate one successful record.
            let base = Date(timeIntervalSince1970: 5_000_000)
            let existingRecord = ScoreRecord(
                score: 500,
                maxCombo: 10,
                accuracy: 85.0,
                speedMultiplier: 1.0,
                playedAt: base,
                chart: chart
            )
            context.insert(existingRecord)
            try context.save()

            // Service with forced save failure.
            let service = ScorePersistenceService(
                modelContext: context,
                saveContext: { _ in throw SaveHookError.forced }
            )

            var engine = ScoreEngine()
            for _ in 0..<5 { engine.processHit(accuracy: .perfect, timingError: 0) }
            let snapshot = LiveScoreSnapshot(scoreEngine: engine)

            let result = service.recordAttempt(
                snapshot, for: chart, atFullSpeed: true, speedMultiplier: 1.0,
                now: base.addingTimeInterval(1)
            )

            #expect(result == .saveFailed)

            // The deleted record must not appear in recentAttempts even though
            // SwiftData still keeps it in the relationship array.
            let attempts = service.recentAttempts(for: chart)
            #expect(attempts.count == 1)
            #expect(attempts.first?.score == 500)
        }
    }

    @Test("pruneOldRecords ignores deleted tombstones from prior failed saves")
    func testPruneIgnoresDeletedTombstones() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let chart = try makeTestChart()
            let base = Date(timeIntervalSince1970: 6_000_000)

            // Pre-populate exactly maxRecentAttempts valid records.
            for i in 0..<ScorePersistenceService.maxRecentAttempts {
                let record = ScoreRecord(
                    score: 100 * (i + 1),
                    maxCombo: i,
                    accuracy: 80.0,
                    speedMultiplier: 1.0,
                    playedAt: base.addingTimeInterval(Double(i)),
                    chart: chart
                )
                context.insert(record)
            }
            try context.save()
            // Sanity: exactly 10 records before the failed attempt.
            #expect(chart.scoreRecords.filter { !$0.isDeleted }.count == ScorePersistenceService.maxRecentAttempts)

            // Simulate a failed save: the catch block deletes the new record,
            // but SwiftData keeps the tombstone in the relationship array.
            let failService = ScorePersistenceService(
                modelContext: context,
                saveContext: { _ in throw SaveHookError.forced }
            )
            var engine = ScoreEngine()
            for _ in 0..<5 { engine.processHit(accuracy: .perfect, timingError: 0) }
            let failSnapshot = LiveScoreSnapshot(scoreEngine: engine)

            let failResult = failService.recordAttempt(
                failSnapshot, for: chart, atFullSpeed: true, speedMultiplier: 1.0,
                now: base.addingTimeInterval(100)
            )
            #expect(failResult == .saveFailed)

            // Now record a successful attempt with a working service.
            // The tombstone is still in chart.scoreRecords; pruneOldRecords
            // must filter it out so only valid records are counted for pruning.
            let goodService = ScorePersistenceService(modelContext: context)
            var engine2 = ScoreEngine()
            for _ in 0..<8 { engine2.processHit(accuracy: .perfect, timingError: 0) }
            let goodSnapshot = LiveScoreSnapshot(scoreEngine: engine2)

            _ = goodService.recordAttempt(
                goodSnapshot, for: chart, atFullSpeed: true, speedMultiplier: 1.0,
                now: base.addingTimeInterval(200)
            )

            // After the successful save + prune, there should be exactly
            // maxRecentAttempts non-deleted records. The tombstone must not
            // inflate the count and cause premature pruning of a valid record.
            let validRecords = chart.scoreRecords.filter { !$0.isDeleted }
            #expect(validRecords.count == ScorePersistenceService.maxRecentAttempts)
        }
    }

    @Test("migrateLegacyHighScores rollback on save failure preserves original bests and leaves flag unset")
    func testMigrateLegacyHighScoresRollbackOnSaveFailure() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let chart = try makeTestChart()
            chart.bestScore = 200
            try context.save()

            let service = ScorePersistenceService(
                modelContext: context,
                saveContext: { _ in throw SaveHookError.forced }
            )
            let (userDefaults, _) = TestUserDefaults.makeIsolated()

            let key = PersistentIdentifierPersistenceKey.canonicalKey(
                for: chart.persistentModelID, logPrefix: "Test"
            )
            userDefaults.set([key: 5000], forKey: "HighScorePerChart")

            service.migrateLegacyHighScores(charts: [chart], from: userDefaults)

            // bestScore must be restored — save failed, property-level rollback kicks in.
            #expect(chart.bestScore == 200)
            // Flag must NOT be set — migration should retry on next launch.
            #expect(userDefaults.bool(forKey: "DidMigrateHighScoresToSwiftData") == false)
            // Legacy data must NOT be deleted — it's the only copy until migration succeeds.
            #expect(userDefaults.dictionary(forKey: "HighScorePerChart") != nil)
        }
    }
}
