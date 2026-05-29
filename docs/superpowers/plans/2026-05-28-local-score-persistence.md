# Local Score Persistence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the single-`Int`-per-chart `UserDefaults` high score with SwiftData-backed score persistence that keeps the recent 10 attempts per chart plus an all-time best (full-speed only), migrates legacy bests once, and shows scores from the Songs and Library tabs.

**Architecture:** A new `@Model ScoreRecord` (one row per completed run) related to `Chart` via a cascade-delete relationship, plus a `Chart.bestScore` stored attribute that survives pruning. A `@MainActor ScorePersistenceService` (takes a `ModelContext`) owns record/prune/best/migration logic and returns value-type `ScoreAttemptSummary` DTOs to views. `GameplayViewModel` records each completed run; a reusable `ChartScoresView` displays history, reached from the Songs tab (per chart) and the Library tab (song → chart). `HighScoreService` is retired.

**Tech Stack:** Swift 5.9+, SwiftUI, SwiftData, Swift Testing (`import Testing`), Xcode 16 file-system-synchronized project groups (new files auto-included).

---

## Reference: conventions used throughout

**Spec:** `docs/superpowers/specs/2026-05-28-local-score-persistence-design.md`

**Build (macOS):**
```bash
xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' build
```

**Run one test suite:**
```bash
xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' \
  -only-testing:VirgoTests/<SuiteName> \
  ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath ./DerivedData
```

**Lint:** `swiftlint lint` (line ≤120 warn/150 err; function body ≤50/100; type body ≤300/600; file ≤600/1000).

New unit-test files use Swift Testing (`import Testing`, `@Suite`, `@Test`, `#expect`, `#require`) and the `TestContainer` / `TestSetup.withTestSetup` helpers in `VirgoTests/TestHelpers.swift`.

---

## File Structure

**New files:**
- `Virgo/models/ScoreRecord.swift` — the `@Model ScoreRecord`.
- `Virgo/utilities/ScoreAttemptSummary.swift` — value-type DTO for views.
- `Virgo/services/ScorePersistenceService.swift` — record/prune/best/migration facade + `makeInMemory()`.
- `Virgo/views/ChartScoresView.swift` — reusable per-chart best + recent-attempts list.
- `Virgo/views/SongScoresView.swift` — per-song list of charts → `ChartScoresView`.
- `VirgoTests/ScorePersistenceServiceTests.swift` — service unit tests.
- `VirgoTests/GameplayViewModelFullSpeedScoringTests.swift` — VM full-speed/record tests.

**Modified files:**
- `Virgo/models/DrumTrack.swift` — `Chart.bestScore` + `Chart.scoreRecords` relationship.
- `Virgo/VirgoApp.swift` — register `ScoreRecord.self` in the schema.
- `VirgoTests/TestHelpers.swift` — register `ScoreRecord.self` in the test schema.
- `Virgo/viewmodels/GameplayViewModel.swift` — swap service, `sessionAtFullSpeed`, completion call.
- `Virgo/views/GameplayView.swift` — inject service from `@Environment(\.modelContext)`; results sheet best score.
- `Virgo/views/ContentView.swift` — one-time migration call.
- `Virgo/views/LibraryView.swift` — `NavigationStack` + per-song scores navigation.
- `Virgo/components/DifficultyExpansionView.swift` — `ChartSelectionCard` best-score label + scores sheet.
- `VirgoTests/GameplayViewModelCoverageTestSupport.swift` — build `ScorePersistenceService` instead of `HighScoreService`.
- `VirgoTests/GameplayViewModelCoverageAdditionsTests.swift` — update injection test.

**Deleted files:**
- `Virgo/services/HighScoreService.swift`
- `VirgoTests/HighScoreServiceTests.swift`

---

## Task 1: `ScoreRecord` model, `Chart` additions, schema registration

**Files:**
- Create: `Virgo/models/ScoreRecord.swift`
- Modify: `Virgo/models/DrumTrack.swift` (`Chart` class, currently lines 29–85)
- Modify: `Virgo/VirgoApp.swift:20-26` (schema array)
- Modify: `VirgoTests/TestHelpers.swift` (test schema array, ~line 75-81)
- Test: `VirgoTests/ScorePersistenceServiceTests.swift` (created here, expanded in later tasks)

- [ ] **Step 1: Write the failing test**

Create `VirgoTests/ScorePersistenceServiceTests.swift`:

```swift
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

            #expect(chart.bestScore == 0)
            #expect(chart.scoreRecords.count == 1)
            #expect(chart.scoreRecords.first?.score == 1500)
            #expect(chart.scoreRecords.first?.speedMultiplier == 1.0)
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' \
  -only-testing:VirgoTests/ScorePersistenceServiceTests \
  ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -derivedDataPath ./DerivedData
```
Expected: FAIL — compile error "cannot find 'ScoreRecord' in scope" and "value of type 'Chart' has no member 'bestScore'/'scoreRecords'".

- [ ] **Step 3: Create the `ScoreRecord` model**

Create `Virgo/models/ScoreRecord.swift`:

```swift
//
//  ScoreRecord.swift
//  Virgo
//
//  One persisted row per completed gameplay run.
//

import Foundation
import SwiftData

@Model
final class ScoreRecord {
    var score: Int
    var maxCombo: Int
    var accuracy: Double          // hit accuracy 0–100
    var speedMultiplier: Double   // effective speed at run completion
    var playedAt: Date
    var chart: Chart?

    init(
        score: Int,
        maxCombo: Int,
        accuracy: Double,
        speedMultiplier: Double,
        playedAt: Date,
        chart: Chart? = nil
    ) {
        self.score = score
        self.maxCombo = maxCombo
        self.accuracy = accuracy
        self.speedMultiplier = speedMultiplier
        self.playedAt = playedAt
        self.chart = chart
    }
}
```

- [ ] **Step 4: Add `bestScore` + `scoreRecords` to `Chart`**

In `Virgo/models/DrumTrack.swift`, inside `final class Chart` (after the existing `notes` relationship at lines 35-36), add:

```swift
    var bestScore: Int = 0
    @Relationship(deleteRule: .cascade, inverse: \ScoreRecord.chart)
    var scoreRecords: [ScoreRecord] = []
```

Both have defaults, so the existing `Chart.init` (line 76) needs no change.

- [ ] **Step 5: Register `ScoreRecord` in the app schema**

In `Virgo/VirgoApp.swift`, change the schema (lines 20-26) to include `ScoreRecord.self`:

```swift
        let schema = Schema([
            Song.self,
            Chart.self,
            Note.self,
            ServerSong.self,
            ServerChart.self,
            ScoreRecord.self
        ])
```

- [ ] **Step 6: Register `ScoreRecord` in the test schema**

In `VirgoTests/TestHelpers.swift`, find the `Schema([...])` inside `resolveContainer()` (the array ending `ServerChart.self`) and add `ScoreRecord.self`:

```swift
        let schema = Schema([
            Song.self,
            Chart.self,
            Note.self,
            ServerSong.self,
            ServerChart.self,
            ScoreRecord.self
        ])
```

Also, in the `reset()` method of `TestContainer`, after the `serverCharts` cleanup block, add a defensive cleanup for orphaned records:

```swift
            let scoreRecords = try context.fetch(FetchDescriptor<ScoreRecord>())
            scoreRecords.forEach { context.delete($0) }
```

(Place it before the final `try context.save()`.)

- [ ] **Step 7: Run test to verify it passes**

Run the Step 2 command.
Expected: PASS (1 test).

- [ ] **Step 8: Commit**

```bash
git add Virgo/models/ScoreRecord.swift Virgo/models/DrumTrack.swift \
  Virgo/VirgoApp.swift VirgoTests/TestHelpers.swift VirgoTests/ScorePersistenceServiceTests.swift
git commit -m "feat: add ScoreRecord model and Chart score relationship

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: `ScoreAttemptSummary` DTO + `ScorePersistenceService.recordAttempt` / `bestScore`

**Files:**
- Create: `Virgo/utilities/ScoreAttemptSummary.swift`
- Create: `Virgo/services/ScorePersistenceService.swift`
- Test: `VirgoTests/ScorePersistenceServiceTests.swift` (add cases)

- [ ] **Step 1: Write the failing tests**

Append these tests inside the `ScorePersistenceServiceTests` struct (before the closing brace):

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' \
  -only-testing:VirgoTests/ScorePersistenceServiceTests \
  ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -derivedDataPath ./DerivedData
```
Expected: FAIL — "cannot find 'ScorePersistenceService' in scope".

- [ ] **Step 3: Create the DTO**

Create `Virgo/utilities/ScoreAttemptSummary.swift`:

```swift
//
//  ScoreAttemptSummary.swift
//  Virgo
//
//  Value-type view boundary for a single persisted score attempt.
//

import Foundation

struct ScoreAttemptSummary: Identifiable, Equatable {
    let id: UUID
    let score: Int
    let maxCombo: Int
    let accuracy: Double          // 0–100
    let speedMultiplier: Double
    let playedAt: Date

    init(
        id: UUID = UUID(),
        score: Int,
        maxCombo: Int,
        accuracy: Double,
        speedMultiplier: Double,
        playedAt: Date
    ) {
        self.id = id
        self.score = score
        self.maxCombo = maxCombo
        self.accuracy = accuracy
        self.speedMultiplier = speedMultiplier
        self.playedAt = playedAt
    }
}
```

- [ ] **Step 4: Create the service with `recordAttempt` + `bestScore`**

Create `Virgo/services/ScorePersistenceService.swift`:

```swift
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

    static let maxRecentAttempts = 10

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Records a completed run, prunes old history, and updates the chart's
    /// all-time best when the run was full speed.
    /// - Returns: `true` if a new all-time best was set.
    @discardableResult
    func recordAttempt(
        _ snapshot: LiveScoreSnapshot,
        for chart: Chart,
        atFullSpeed: Bool,
        speedMultiplier: Double,
        now: Date = Date()
    ) -> Bool {
        let record = ScoreRecord(
            score: snapshot.score,
            maxCombo: snapshot.maxCombo,
            accuracy: snapshot.hitAccuracy,
            speedMultiplier: speedMultiplier,
            playedAt: now,
            chart: chart
        )
        modelContext.insert(record)

        pruneOldRecords(for: chart)

        var isNewBest = false
        if atFullSpeed && record.score > chart.bestScore {
            chart.bestScore = record.score
            isNewBest = true
        }

        do {
            try modelContext.save()
        } catch {
            Logger.error("ScorePersistenceService: failed to save score record: \(error.localizedDescription)")
        }
        return isNewBest
    }

    /// The all-time best score for a chart (0 if none).
    func bestScore(for chart: Chart) -> Int {
        chart.bestScore
    }

    // MARK: - Private

    private func pruneOldRecords(for chart: Chart) {
        let sorted = chart.scoreRecords.sorted { $0.playedAt > $1.playedAt }
        guard sorted.count > Self.maxRecentAttempts else { return }
        for record in sorted[Self.maxRecentAttempts...] {
            modelContext.delete(record)
        }
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run the Step 2 command.
Expected: PASS (all `ScorePersistenceServiceTests`, including Task 1's).

- [ ] **Step 6: Commit**

```bash
git add Virgo/utilities/ScoreAttemptSummary.swift Virgo/services/ScorePersistenceService.swift \
  VirgoTests/ScorePersistenceServiceTests.swift
git commit -m "feat: add ScorePersistenceService recordAttempt and bestScore

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: Pruning to recent 10 + `recentAttempts` DTO query

**Files:**
- Modify: `Virgo/services/ScorePersistenceService.swift`
- Test: `VirgoTests/ScorePersistenceServiceTests.swift` (add cases)

- [ ] **Step 1: Write the failing tests**

Append inside `ScorePersistenceServiceTests`:

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' \
  -only-testing:VirgoTests/ScorePersistenceServiceTests \
  ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -derivedDataPath ./DerivedData
```
Expected: FAIL — `testRecentAttemptsMapsAndSorts` fails with "value of type 'ScorePersistenceService' has no member 'recentAttempts'". (`testRecordAttemptPrunesToTen` already passes — pruning exists from Task 2.)

- [ ] **Step 3: Add `recentAttempts`**

In `Virgo/services/ScorePersistenceService.swift`, add this method after `bestScore(for:)`:

```swift
    /// Most recent attempts for a chart, newest first, as value-type DTOs.
    func recentAttempts(
        for chart: Chart,
        limit: Int = ScorePersistenceService.maxRecentAttempts
    ) -> [ScoreAttemptSummary] {
        chart.scoreRecords
            .sorted { $0.playedAt > $1.playedAt }
            .prefix(limit)
            .map { record in
                ScoreAttemptSummary(
                    score: record.score,
                    maxCombo: record.maxCombo,
                    accuracy: record.accuracy,
                    speedMultiplier: record.speedMultiplier,
                    playedAt: record.playedAt
                )
            }
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run the Step 2 command.
Expected: PASS (all `ScorePersistenceServiceTests`).

- [ ] **Step 5: Commit**

```bash
git add Virgo/services/ScorePersistenceService.swift VirgoTests/ScorePersistenceServiceTests.swift
git commit -m "feat: add recentAttempts DTO query and verify pruning

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: One-time legacy high-score migration

**Files:**
- Modify: `Virgo/services/ScorePersistenceService.swift`
- Test: `VirgoTests/ScorePersistenceServiceTests.swift` (add cases)

- [ ] **Step 1: Write the failing tests**

Append inside `ScorePersistenceServiceTests`. These need an isolated `UserDefaults`; reuse the project's `TestUserDefaults.makeIsolated()` helper (used by `HighScoreServiceTests` / `PracticeSettingsServiceTests`).

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' \
  -only-testing:VirgoTests/ScorePersistenceServiceTests \
  ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -derivedDataPath ./DerivedData
```
Expected: FAIL — "has no member 'migrateLegacyHighScores'".

- [ ] **Step 3: Add migration to the service**

In `Virgo/services/ScorePersistenceService.swift`, add these constants under `maxRecentAttempts`:

```swift
    private static let migrationFlagKey = "DidMigrateHighScoresToSwiftData"
    private static let legacyHighScoreKey = "HighScorePerChart"
```

Add this public method after `recentAttempts(for:limit:)`:

```swift
    /// One-time migration of legacy UserDefaults high scores into Chart.bestScore.
    /// Guarded by a flag so it runs at most once; idempotent and never lowers a best.
    func migrateLegacyHighScores(charts: [Chart], from userDefaults: UserDefaults) {
        guard !userDefaults.bool(forKey: Self.migrationFlagKey) else { return }

        let legacy = readLegacyScores(from: userDefaults)
        if !legacy.isEmpty {
            for chart in charts {
                let key = PersistentIdentifierPersistenceKey.canonicalKey(
                    for: chart.persistentModelID,
                    logPrefix: "ScorePersistenceService"
                )
                if let legacyBest = legacy[key], legacyBest > chart.bestScore {
                    chart.bestScore = legacyBest
                }
            }
            do {
                try modelContext.save()
            } catch {
                Logger.error("ScorePersistenceService: failed to save migrated high scores: \(error.localizedDescription)")
                return // leave the flag unset so migration retries next launch
            }
        }

        userDefaults.removeObject(forKey: Self.legacyHighScoreKey)
        userDefaults.set(true, forKey: Self.migrationFlagKey)
    }
```

Add this private helper after `pruneOldRecords(for:)`:

```swift
    private func readLegacyScores(from userDefaults: UserDefaults) -> [String: Int] {
        guard let raw = userDefaults.dictionary(forKey: Self.legacyHighScoreKey) else { return [:] }
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run the Step 2 command.
Expected: PASS (all `ScorePersistenceServiceTests`).

- [ ] **Step 5: Commit**

```bash
git add Virgo/services/ScorePersistenceService.swift VirgoTests/ScorePersistenceServiceTests.swift
git commit -m "feat: migrate legacy UserDefaults high scores to SwiftData

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 5: `GameplayViewModel` integration + retire `HighScoreService`

**Files:**
- Modify: `Virgo/services/ScorePersistenceService.swift` (add `makeInMemory()`)
- Modify: `Virgo/viewmodels/GameplayViewModel.swift`
- Modify: `VirgoTests/GameplayViewModelCoverageTestSupport.swift`
- Modify: `VirgoTests/GameplayViewModelCoverageAdditionsTests.swift`
- Delete: `Virgo/services/HighScoreService.swift`, `VirgoTests/HighScoreServiceTests.swift`
- Test: `VirgoTests/GameplayViewModelFullSpeedScoringTests.swift` (new)

- [ ] **Step 1: Add an in-memory factory to the service**

In `Virgo/services/ScorePersistenceService.swift`, add this extension at the end of the file:

```swift
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
            return ScorePersistenceService(modelContext: container.mainContext)
        } catch {
            fatalError("ScorePersistenceService.makeInMemory failed: \(error)")
        }
    }
}
```

- [ ] **Step 2: Write the failing tests**

Create `VirgoTests/GameplayViewModelFullSpeedScoringTests.swift`:

```swift
//
//  GameplayViewModelFullSpeedScoringTests.swift
//  VirgoTests
//
//  Verifies that completed runs are recorded and that only full-speed runs
//  set the all-time best.
//

import Testing
import SwiftData
import Foundation
@testable import Virgo

@Suite("GameplayViewModel Full-Speed Scoring", .serialized)
@MainActor
struct GameplayViewModelFullSpeedScoringTests {

    private func makeChartInContext() throws -> Chart {
        let context = TestContainer.shared.context
        let song = Song(title: "S", artist: "A", bpm: 120, duration: "1:00", genre: "Rock")
        context.insert(song)
        let chart = Chart(difficulty: .medium, song: song)
        for i in 0..<4 {
            chart.notes.append(Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: Double(i) * 0.1))
        }
        context.insert(chart)
        try context.save()
        return chart
    }

    @Test("Full-speed completion records an attempt and sets best")
    func testFullSpeedCompletionSetsBest() async throws {
        try await TestSetup.withTestSetup {
            let chart = try makeChartInContext()
            let service = ScorePersistenceService(modelContext: TestContainer.shared.context)
            let vm = GameplayViewModel(
                chart: chart,
                metronome: MetronomeEngine(audioDriver: RecordingAudioDriver()),
                practiceSettings: GameplayViewModelCoverageTestSupport.makeSettings(),
                scorePersistence: service
            )
            await vm.loadChartData()
            vm.setupGameplay(loadPersistedSpeed: false)
            vm.sessionAtFullSpeed = true
            for _ in 0..<4 { vm.scoreEngine.processHit(accuracy: .perfect, timingError: 0) }

            vm.handlePlaybackCompletion()

            #expect(vm.sessionIsNewRecord == true)
            #expect(service.bestScore(for: chart) > 0)
            #expect(chart.scoreRecords.count == 1)
        }
    }

    @Test("Slowed completion records history but does not set best")
    func testSlowedCompletionDoesNotSetBest() async throws {
        try await TestSetup.withTestSetup {
            let chart = try makeChartInContext()
            let service = ScorePersistenceService(modelContext: TestContainer.shared.context)
            let vm = GameplayViewModel(
                chart: chart,
                metronome: MetronomeEngine(audioDriver: RecordingAudioDriver()),
                practiceSettings: GameplayViewModelCoverageTestSupport.makeSettings(),
                scorePersistence: service
            )
            await vm.loadChartData()
            vm.setupGameplay(loadPersistedSpeed: false)
            vm.sessionAtFullSpeed = false
            for _ in 0..<4 { vm.scoreEngine.processHit(accuracy: .perfect, timingError: 0) }

            vm.handlePlaybackCompletion()

            #expect(vm.sessionIsNewRecord == false)
            #expect(service.bestScore(for: chart) == 0)
            #expect(chart.scoreRecords.count == 1)
        }
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run:
```bash
xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' \
  -only-testing:VirgoTests/GameplayViewModelFullSpeedScoringTests \
  ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -derivedDataPath ./DerivedData
```
Expected: FAIL — `GameplayViewModel` has no `scorePersistence:` init parameter and no `sessionAtFullSpeed` member.

- [ ] **Step 4: Swap the service + add the full-speed flag in `GameplayViewModel`**

In `Virgo/viewmodels/GameplayViewModel.swift`:

4a. Replace the high-score property (line 213-214):

```swift
    // MARK: - Score Persistence
    let scorePersistence: ScorePersistenceService

    /// True only while the current run has been at 1.0x speed for its entire
    /// duration. Gates all-time best eligibility.
    var sessionAtFullSpeed: Bool = true
```

4b. Replace the primary `init` (lines 228-240) parameter and assignment:

```swift
    @MainActor
    init(
        chart: Chart,
        metronome: MetronomeEngine,
        practiceSettings: PracticeSettingsService,
        scorePersistence: ScorePersistenceService
    ) {
        self.chart = chart
        self.metronome = metronome
        self.practiceSettings = practiceSettings
        self.scorePersistence = scorePersistence
        self.lastAppliedSpeedMultiplier = practiceSettings.speedMultiplier
    }
```

4c. Replace the two convenience inits (lines 242-253):

```swift
    @MainActor
    convenience init(chart: Chart, metronome: MetronomeEngine, practiceSettings: PracticeSettingsService) {
        self.init(
            chart: chart, metronome: metronome, practiceSettings: practiceSettings,
            scorePersistence: ScorePersistenceService.makeInMemory()
        )
    }

    #if DEBUG
    @MainActor
    convenience init(chart: Chart, metronome: MetronomeEngine) {
        let ps = PracticeSettingsService()
        self.init(
            chart: chart, metronome: metronome, practiceSettings: ps,
            scorePersistence: ScorePersistenceService.makeInMemory()
        )
    }
    #endif
```

4d. Add a static full-speed helper. Place it in the `// MARK: - Speed Control` section (after `effectiveBPM()`, ~line 265):

```swift
    /// True when a speed multiplier is effectively 1.0x.
    static func isFullSpeed(_ multiplier: Double) -> Bool {
        abs(multiplier - 1.0) < 0.0001
    }
```

4e. Set the flag at fresh run start. In `startPlayback()`, the fresh-start `else` branch (lines 723-729) currently is:

```swift
        } else {
            Logger.audioPlayback("🎮 Starting fresh playback")

            // Starting from beginning - reset all state
            resetPlaybackState()
            pausedElapsedTime = 0.0
        }
```

Change it to:

```swift
        } else {
            Logger.audioPlayback("🎮 Starting fresh playback")

            // Starting from beginning - reset all state
            resetPlaybackState()
            pausedElapsedTime = 0.0
            // A fresh run is best-eligible only if it begins at full speed.
            sessionAtFullSpeed = Self.isFullSpeed(practiceSettings.speedMultiplier)
        }
```

4f. Clear the flag when a non-full speed is applied during play. In `applySpeedChangeInternal(previousSpeed:)`, after `lastAppliedSpeedMultiplier = currentSpeed` (line 341), add:

```swift
        if isPlaying && !Self.isFullSpeed(currentSpeed) {
            sessionAtFullSpeed = false
        }
```

4g. Record the attempt on completion. In `handlePlaybackCompletion()`, replace the line (1472):

```swift
        let isNewRecord = highScoreService.saveIfHighScore(finalScore, for: chart.persistentModelID)
```

with:

```swift
        let isNewRecord = scorePersistence.recordAttempt(
            finalSnapshot,
            for: chart,
            atFullSpeed: sessionAtFullSpeed,
            speedMultiplier: lastAppliedSpeedMultiplier
        )
```

(`finalScore` is still used by the log line at 1483; leave its declaration at line 1470.)

- [ ] **Step 5: Update the test support helper**

In `VirgoTests/GameplayViewModelCoverageTestSupport.swift`:

5a. Delete the `makeHighScoreService()` method (lines 16-19).

5b. Add a `makeScorePersistence()` helper after `makeSettings()`:

```swift
    static func makeScorePersistence() -> ScorePersistenceService {
        ScorePersistenceService(modelContext: TestContainer.shared.context)
    }
```

5c. Replace `makeViewModel` (lines 39-55):

```swift
    static func makeViewModel(
        chart: Chart? = nil,
        noteCount: Int = 4,
        settings: PracticeSettingsService? = nil,
        scorePersistence: ScorePersistenceService? = nil
    ) -> GameplayViewModel {
        let resolvedChart = chart ?? makeChart(noteCount: noteCount)
        let metronome = makeMetronome()
        let resolvedSettings = settings ?? makeSettings()
        let resolvedScorePersistence = scorePersistence ?? makeScorePersistence()
        return GameplayViewModel(
            chart: resolvedChart,
            metronome: metronome,
            practiceSettings: resolvedSettings,
            scorePersistence: resolvedScorePersistence
        )
    }
```

- [ ] **Step 6: Update the injection coverage test**

In `VirgoTests/GameplayViewModelCoverageAdditionsTests.swift`, replace the first test (lines ~17-27):

```swift
    @Test("GameplayViewModelCoverageTestSupport.makeViewModel uses an injected score persistence service")
    func testMakeViewModelUsesInjectedScorePersistence() async throws {
        let service = ScorePersistenceService.makeInMemory()

        let vm = GameplayViewModelCoverageTestSupport.makeViewModel(
            scorePersistence: service
        )

        #expect(vm.scorePersistence === service)
    }
```

- [ ] **Step 7: Delete `HighScoreService` and its tests**

```bash
git rm Virgo/services/HighScoreService.swift VirgoTests/HighScoreServiceTests.swift
```

- [ ] **Step 8: Run the affected suites to verify they pass**

Run:
```bash
xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' \
  -only-testing:VirgoTests/GameplayViewModelFullSpeedScoringTests \
  -only-testing:VirgoTests/GameplayViewModelCoverageAdditionsTests \
  -only-testing:VirgoTests/ScorePersistenceServiceTests \
  ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -derivedDataPath ./DerivedData
```
Expected: PASS. If other test files still reference `HighScoreService`, fix them by switching to `ScorePersistenceService` (search: `grep -rn "HighScoreService\|highScoreService" VirgoTests`).

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "feat: record scores via ScorePersistenceService; retire HighScoreService

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 6: `GameplayView` injection + results best score + startup migration

**Files:**
- Modify: `Virgo/views/GameplayView.swift`
- Modify: `Virgo/views/ContentView.swift`

- [ ] **Step 1: Inject the service into the view model**

In `Virgo/views/GameplayView.swift`:

1a. Add the model context environment after `@Environment(\.dismiss)` (line 16):

```swift
    @Environment(\.modelContext) private var modelContext
```

1b. In the `.task` block, replace the view-model construction (lines 81-87):

```swift
            if viewModel == nil {
                viewModel = GameplayViewModel(
                    chart: chart,
                    metronome: metronome,
                    practiceSettings: practiceSettings,
                    scorePersistence: ScorePersistenceService(modelContext: modelContext)
                )
            }
```

1c. In the results sheet, replace the high score read (line 116):

```swift
                    highScore: vm.scorePersistence.bestScore(for: chart),
```

- [ ] **Step 2: Add the one-time migration at startup**

In `Virgo/views/ContentView.swift`, in `.onAppear` immediately after `databaseService?.performInitialMaintenance(songs: allSongs)` (line 130), add:

```swift
            ScorePersistenceService(modelContext: modelContext)
                .migrateLegacyHighScores(
                    charts: allSongs.flatMap { $0.charts },
                    from: .standard
                )
```

- [ ] **Step 3: Build to verify it compiles**

Run:
```bash
xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' build
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add Virgo/views/GameplayView.swift Virgo/views/ContentView.swift
git commit -m "feat: inject ScorePersistenceService into gameplay and migrate at startup

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 7: `ChartScoresView` (reusable scores view)

**Files:**
- Create: `Virgo/views/ChartScoresView.swift`

- [ ] **Step 1: Create the view**

Create `Virgo/views/ChartScoresView.swift`:

```swift
//
//  ChartScoresView.swift
//  Virgo
//
//  Reusable per-chart scores: all-time best + recent attempts.
//

import SwiftUI
import SwiftData

struct ChartScoresView: View {
    let chart: Chart

    @Environment(\.modelContext) private var modelContext
    @State private var attempts: [ScoreAttemptSummary] = []
    @State private var bestScore: Int = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 16) {
                bestScoreHeader

                if attempts.isEmpty {
                    emptyState
                } else {
                    attemptsList
                }
            }
            .padding(.top, 16)
        }
        .navigationTitle("Scores")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        #endif
        .task { load() }
    }

    private var bestScoreHeader: some View {
        VStack(spacing: 4) {
            Text("\(bestScore)")
                .font(.system(size: 40, weight: .bold, design: .monospaced))
                .foregroundColor(.purple)
            Text("BEST SCORE")
                .font(.caption)
                .foregroundColor(.gray)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 48))
                .foregroundColor(.white.opacity(0.3))
            Text("No attempts yet")
                .font(.headline)
                .foregroundColor(.white)
            Text("Play this chart to record a score")
                .font(.subheadline)
                .foregroundColor(.gray)
            Spacer()
        }
    }

    private var attemptsList: some View {
        List(attempts) { attempt in
            ScoreAttemptRow(attempt: attempt)
                .listRowBackground(Color.white.opacity(0.05))
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func load() {
        let service = ScorePersistenceService(modelContext: modelContext)
        bestScore = service.bestScore(for: chart)
        attempts = service.recentAttempts(for: chart)
    }
}

private struct ScoreAttemptRow: View {
    let attempt: ScoreAttemptSummary

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(attempt.score)")
                    .font(.system(.headline, design: .monospaced))
                    .foregroundColor(.white)
                Text(Self.relativeFormatter.localizedString(for: attempt.playedAt, relativeTo: Date()))
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(attempt.maxCombo)x · \(Int(attempt.accuracy.rounded()))%")
                    .font(.caption)
                    .foregroundColor(.cyan)
                Text("\(Int((attempt.speedMultiplier * 100).rounded()))% speed")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        ChartScoresView(chart: Chart(difficulty: .medium))
    }
    .modelContainer(for: [Song.self, Chart.self, Note.self, ServerSong.self, ServerChart.self, ScoreRecord.self], inMemory: true)
}
```

- [ ] **Step 2: Build to verify it compiles**

Run:
```bash
xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' build
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add Virgo/views/ChartScoresView.swift
git commit -m "feat: add reusable ChartScoresView for best + recent attempts

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 8: `SongScoresView` + Library navigation

**Files:**
- Create: `Virgo/views/SongScoresView.swift`
- Modify: `Virgo/views/LibraryView.swift`

- [ ] **Step 1: Create `SongScoresView`**

Create `Virgo/views/SongScoresView.swift`:

```swift
//
//  SongScoresView.swift
//  Virgo
//
//  Per-song list of charts, each linking to its scores.
//

import SwiftUI
import SwiftData

struct SongScoresView: View {
    let song: Song

    @Environment(\.modelContext) private var modelContext
    @State private var charts: [Chart] = []
    @State private var bestScores: [PersistentIdentifier: Int] = [:]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if charts.isEmpty {
                Text("No charts available")
                    .foregroundColor(.gray)
            } else {
                List(charts, id: \.persistentModelID) { chart in
                    NavigationLink {
                        ChartScoresView(chart: chart)
                    } label: {
                        HStack {
                            DifficultyBadge(difficulty: chart.difficulty, size: .normal)
                            Spacer()
                            Text("Best \(bestScores[chart.persistentModelID] ?? 0)")
                                .font(.system(.subheadline, design: .monospaced))
                                .foregroundColor(.purple)
                        }
                    }
                    .listRowBackground(Color.white.opacity(0.05))
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle(song.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        #endif
        .task { load() }
    }

    private func load() {
        let service = ScorePersistenceService(modelContext: modelContext)
        let sorted = song.charts.sorted { $0.difficulty.sortOrder < $1.difficulty.sortOrder }
        charts = sorted
        bestScores = Dictionary(
            uniqueKeysWithValues: sorted.map { ($0.persistentModelID, service.bestScore(for: $0)) }
        )
    }
}
```

- [ ] **Step 2: Wire Library navigation**

In `Virgo/views/LibraryView.swift`:

2a. Wrap the top-level `ZStack` in `LibraryView.body` in a `NavigationStack`. Change the start of `body` (line 20-21) from:

```swift
    var body: some View {
        ZStack {
```

to:

```swift
    var body: some View {
        NavigationStack {
            ZStack {
```

and add one closing brace at the end of `body` (after the existing `ZStack`'s closing brace at line 98). The structure becomes `NavigationStack { ZStack { ... } }`.

2b. Make each row navigate to its scores. Replace the `SavedSongRow(...)` usage block (lines 79-90) with a `NavigationLink` wrapper:

```swift
                        ForEach(downloadedSongs, id: \.id) { song in
                            NavigationLink {
                                SongScoresView(song: song)
                            } label: {
                                SavedSongRow(
                                    song: song,
                                    isDeleting: serverSongService.isDeleting(song),
                                    onDelete: {
                                        Task { @MainActor in
                                            await serverSongService.deleteLocalSong(song)
                                        }
                                    }
                                )
                            }
                            .buttonStyle(.plain)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }
```

Note: `SavedSongRow`'s internal "Delete" button remains tappable inside the `NavigationLink` label on macOS/iOS because it is a distinct control; the row's empty areas trigger navigation.

- [ ] **Step 3: Build to verify it compiles**

Run:
```bash
xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' build
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add Virgo/views/SongScoresView.swift Virgo/views/LibraryView.swift
git commit -m "feat: browse per-song chart scores from the Library tab

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 9: `ChartSelectionCard` scores affordance (Songs tab)

**Files:**
- Modify: `Virgo/components/DifficultyExpansionView.swift` (`ChartSelectionCard`, lines 46-92)

- [ ] **Step 1: Add best-score label + scores sheet to the card**

In `Virgo/components/DifficultyExpansionView.swift`, replace the entire `ChartSelectionCard` struct (lines 46-92) with:

```swift
// MARK: - Chart Selection Card
struct ChartSelectionCard: View {
    let chart: Chart
    let onSelect: () -> Void
    @State private var isPressed = false
    @State private var showingScores = false

    var body: some View {
        HStack(spacing: 8) {
            playButton
            scoresButton
        }
        .sheet(isPresented: $showingScores) {
            NavigationStack {
                ChartScoresView(chart: chart)
            }
        }
    }

    private var playButton: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                DifficultyBadge(difficulty: chart.difficulty, size: .normal)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(chart.notesCount) notes")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Text("Level \(chart.level)")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }

                Spacer()

                if chart.bestScore > 0 {
                    Text("\(chart.bestScore)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.purple)
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(Color.white.opacity(0.1))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(chart.difficulty.color.opacity(0.4), lineWidth: 1)
            )
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .opacity(isPressed ? 0.8 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityIdentifier("chartDifficulty\(chart.difficulty.rawValue)")
        .accessibilityLabel("\(chart.difficulty.rawValue) difficulty, \(chart.notesCount) notes, Level \(chart.level)")
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = pressing
            }
        }, perform: {})
    }

    private var scoresButton: some View {
        Button {
            showingScores = true
        } label: {
            Image(systemName: "list.bullet.rectangle")
                .font(.body)
                .foregroundColor(.cyan)
                .frame(width: 36, height: 36)
                .background(Color.white.opacity(0.1))
                .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityIdentifier("chartScores\(chart.difficulty.rawValue)")
        .accessibilityLabel("View scores for \(chart.difficulty.rawValue) difficulty")
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run:
```bash
xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' build
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add Virgo/components/DifficultyExpansionView.swift
git commit -m "feat: show best score and scores entry on chart selection cards

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 10: Full verification

**Files:** none (verification only)

- [ ] **Step 1: Confirm no lingering references to the old service**

Run:
```bash
grep -rn "HighScoreService\|saveIfHighScore" Virgo VirgoTests --include="*.swift"
```
Expected: no matches. If any appear, replace with `ScorePersistenceService` equivalents and re-commit.

- [ ] **Step 2: Lint**

Run:
```bash
swiftlint lint
```
Expected: no errors. Fix any new warnings/errors in the files you touched (watch file-length and function-body limits in `ScorePersistenceService.swift` and `ChartScoresView.swift`).

- [ ] **Step 3: Run the full unit-test suite**

Run:
```bash
xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' \
  -configuration Debug -only-testing:VirgoTests \
  ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -enableCodeCoverage YES -destination-timeout 300 -derivedDataPath ./DerivedData
```
Expected: all tests pass (including `ScorePersistenceServiceTests` and `GameplayViewModelFullSpeedScoringTests`; no `HighScoreServiceTests`).

- [ ] **Step 4: Build the app target**

Run:
```bash
xcodebuild -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' build
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Final commit (if any fixes were made)**

```bash
git add -A
git commit -m "chore: finalize local score persistence (lint + verification fixes)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Notes for the implementer

- **SwiftData inverse relationship:** setting `record.chart = chart` in `ScoreRecord.init` and then `modelContext.insert(record)` makes `chart.scoreRecords` include the new record in the same context, which is why `pruneOldRecords` and the test assertions on `chart.scoreRecords.count` work immediately after `recordAttempt`.
- **`finalScore` in `handlePlaybackCompletion`:** keep its declaration (line 1470) — it is still referenced by the completion log line. Only the save call changes.
- **UI tests:** `VirgoUITests` are not part of the unit-test command above. The Library row now wraps `SavedSongRow` in a `NavigationLink`; if a UI test taps Library rows, verify it still passes via the `ui-tests.yml` flow. The Songs-tab play target keeps its `chartDifficulty<difficulty>` accessibility identifier, so gameplay-launch UI tests are unaffected.
- **Speed semantics:** `speedMultiplier` stored on each record is the speed at completion (`lastAppliedSpeedMultiplier`); best-eligibility uses `sessionAtFullSpeed` (full speed for the entire run). For a constant-speed run these coincide.
```
