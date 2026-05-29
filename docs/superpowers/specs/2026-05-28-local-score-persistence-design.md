# Local Score Persistence — Design

**Date:** 2026-05-28
**Status:** Approved (pending written-spec review)

## Summary

Replace the single-`Int`-per-chart high score (currently in `UserDefaults` via
`HighScoreService`) with SwiftData-backed score persistence. Each completed
gameplay run is recorded as a `ScoreRecord`. Per chart we retain the **10 most
recent** attempts plus an **all-time best score** that survives pruning. Existing
high scores are migrated once, and `HighScoreService` is retired. Scores are
viewable through a reusable per-chart scores view reachable from both the Songs
tab (per chart) and the Library tab (song → chart).

## Goals

- Persist every completed run (score, max combo, accuracy, speed, date) per chart.
- Retain the recent 10 attempts per chart; prune older ones.
- Track an all-time best score per chart that survives pruning.
- Single source of truth in SwiftData (retire the `UserDefaults` store).
- Only **full-speed (1.0×)** runs may set the all-time best; slowed/faster runs are
  still recorded in history.
- Store the speed multiplier per attempt so runs can be compared across speeds.
- View scores from the Songs tab (per chart) and the Library tab (song → chart).

## Non-goals

- No top-N ranking semantics (recent-N, not best-N).
- No cloud sync / leaderboards.
- No change to scoring math (`ScoreEngine`) or accuracy windows.

## Current state (for reference)

- `HighScoreService` (`services/HighScoreService.swift`): stores `[String: Int]`
  in `UserDefaults` under `HighScorePerChart`, keyed by a serialized
  `PersistentIdentifier` via `PersistentIdentifierPersistenceKey`.
- `GameplayViewModel.handlePlaybackCompletion()` (`viewmodels/GameplayViewModel.swift:1463`)
  saves only `finalScore` and shows `SessionResultsView`.
- `SessionResultsView` displays the current run plus the all-time best score.
- High score is consumed only in the gameplay flow (`GameplayViewModel`,
  `GameplayView`, `SessionResultsView`) — not in the library list.
- Gameplay always uses concrete `Chart` (server songs download into local `Chart`
  first), so `ServerChart` does not participate in scoring.
- `LiveScoreSnapshot` already carries `score`, `maxCombo`, `hitAccuracy`, etc.

## Architecture

### 1. Data model (SwiftData)

**New `@Model ScoreRecord`** — one row per completed run:

| Field | Type | Notes |
|---|---|---|
| `score` | `Int` | Final score for the run |
| `maxCombo` | `Int` | Max combo reached |
| `accuracy` | `Double` | `LiveScoreSnapshot.hitAccuracy` (0–100) |
| `speedMultiplier` | `Double` | Effective speed at run completion (e.g. 1.0, 0.75) |
| `playedAt` | `Date` | When the run completed |
| `chart` | `Chart?` | Inverse of the relationship below |

**Additions to existing `Chart`** (`models/DrumTrack.swift`):

- `var bestScore: Int = 0` — all-time best; **survives pruning** (single source of truth).
- `@Relationship(deleteRule: .cascade, inverse: \ScoreRecord.chart) var scoreRecords: [ScoreRecord] = []`
  — cascade delete removes scores when a song/chart is deleted (no orphans).

Both additions are defaulted/optional, so this is a **lightweight automatic
migration** (no custom `SchemaMigrationPlan` needed).

**Schema registration:** add `ScoreRecord.self` to the `Schema` in
`VirgoApp.swift` (alongside `Song`, `Chart`, `Note`, `ServerSong`, `ServerChart`).

### 2. Boundary DTO

`ScoreRecord` is a SwiftData model; to keep views off live relationships we hand
the UI a value type:

```swift
struct ScoreAttemptSummary: Identifiable, Equatable {
    let id: UUID                 // stable per summary instance
    let score: Int
    let maxCombo: Int
    let accuracy: Double         // 0–100
    let speedMultiplier: Double
    let playedAt: Date
}
```

### 3. `ScorePersistenceService`

Location: `services/ScorePersistenceService.swift`. `@MainActor`, mirrors
`DatabaseMaintenanceService` (takes a `ModelContext`).

```swift
@MainActor
final class ScorePersistenceService {
    static let maxRecentAttempts = 10

    init(modelContext: ModelContext)

    /// Inserts a record, prunes to the most recent `maxRecentAttempts`, and
    /// updates the chart's all-time best when the run is full speed.
    /// - Returns: true if a new all-time best was set.
    @discardableResult
    func recordAttempt(
        _ snapshot: LiveScoreSnapshot,
        for chart: Chart,
        atFullSpeed: Bool,
        speedMultiplier: Double,
        now: Date = .now
    ) -> Bool

    func bestScore(for chart: Chart) -> Int

    func recentAttempts(
        for chart: Chart,
        limit: Int = maxRecentAttempts
    ) -> [ScoreAttemptSummary]

    /// One-time migration of legacy UserDefaults high scores. Idempotent.
    func migrateLegacyHighScores(charts: [Chart], from userDefaults: UserDefaults)
}
```

**`recordAttempt` behavior:**
1. Create a `ScoreRecord` from the snapshot (`score`, `maxCombo`,
   `accuracy = snapshot.hitAccuracy`, `speedMultiplier`, `playedAt = now`), link
   it to `chart`, and insert.
2. Prune: keep the `maxRecentAttempts` newest records (by `playedAt`); delete the
   rest via `modelContext.delete`.
3. If `atFullSpeed && record.score > chart.bestScore`, set
   `chart.bestScore = record.score` and mark `isNewBest = true`. (Score 0 never
   beats a `bestScore` that starts at 0, so zero runs never set a best.)
4. Save with verification + error logging, mirroring `HighScoreService`'s
   write-verify pattern (log on failure via `Logger`).
5. Return `isNewBest`.

Every completed run is recorded in history — including slowed/faster runs and
zero-score runs. Only the **best** is gated on full speed.

**`recentAttempts`:** returns DTOs sorted by `playedAt` descending, limited to
`limit`.

### 4. Full-speed tracking (`GameplayViewModel`)

A run qualifies for the all-time best only if it was played at 1.0× for its
entire duration.

- New flag `var sessionAtFullSpeed: Bool`.
- Set at each run start (`togglePlayback` when starting from stopped, and
  `restartPlayback`) to `abs(practiceSettings.speedMultiplier - 1.0) < epsilon`.
  Speeds are quantized to 0.25 steps, so 1.0 is exact; a small epsilon guards
  floating-point comparison.
- Cleared to `false` whenever a non-1.0× speed is applied while playing (in the
  speed-apply path: `applySpeedChangeInternal` / `applySpeedChangeWhilePlaying`).
- For the common constant-speed run this coincides with
  `speedMultiplier == 1.0`. The stored `speedMultiplier` on the record is the
  speed at completion (`lastAppliedSpeedMultiplier`); for a rare mid-run speed
  change, the run is recorded with its final speed but `sessionAtFullSpeed` is
  `false`, so it cannot set the best.

### 5. Gameplay integration

- `GameplayViewModel`: replace `let highScoreService: HighScoreService` with
  `let scorePersistence: ScorePersistenceService`. The primary `init` takes
  `scorePersistence`. Convenience/preview/`#if DEBUG` inits construct one from a
  provided or in-memory `ModelContext`.
- `handlePlaybackCompletion()`:
  ```swift
  let isNewRecord = scorePersistence.recordAttempt(
      finalSnapshot,
      for: chart,
      atFullSpeed: sessionAtFullSpeed,
      speedMultiplier: lastAppliedSpeedMultiplier
  )
  ```
  Use the returned bool for the new-record badge.
- `GameplayView`: add `@Environment(\.modelContext) private var modelContext`,
  build `ScorePersistenceService(modelContext:)`, inject into the view model. The
  results sheet reads `vm.scorePersistence.bestScore(for: chart)`.
- `SessionResultsView` is otherwise **unchanged** — same `highScore: Int` and
  `isNewRecord: Bool` inputs; only the value source changes.

### 6. Migration (one-time)

- Guarded by a `UserDefaults` bool flag `DidMigrateHighScoresToSwiftData`.
- For each existing `Chart`: compute its `canonicalKey` (reusing
  `PersistentIdentifierPersistenceKey.canonicalKey`), read the legacy
  `HighScorePerChart` dictionary; if a legacy best exists and exceeds
  `chart.bestScore`, set `chart.bestScore`.
- Set the flag and clear the legacy `HighScorePerChart` key.
- Runs in `ContentView.onAppear`, immediately after
  `databaseService?.performInitialMaintenance(songs: allSongs)`
  (`views/ContentView.swift:130`), where charts and `modelContext` are available.
- **`HighScoreService` and `HighScoreServiceTests` are deleted.** The legacy
  read logic lives only inside `migrateLegacyHighScores`.

### 7. Scores UI

A single reusable view, two entry points.

**`ChartScoresView(chart: Chart)`** (reusable):
- Builds `ScorePersistenceService` from `@Environment(\.modelContext)`.
- Header: chart difficulty + **best score**.
- List of recent attempts (`[ScoreAttemptSummary]`), each row showing
  `score · maxCombo (x) · accuracy% · speed (x) · relative date`.
- Empty state when no attempts exist.

**Entry point A — Songs tab (per chart):**
- `ChartSelectionCard` (`components/DifficultyExpansionView.swift`) shows the
  chart's best score and adds a scores affordance (e.g. a small trophy/list icon
  button) that presents `ChartScoresView(chart:)` as a sheet. The card owns the
  sheet via local `@State`, so no callbacks are threaded through
  `DifficultyExpansionView` / `ExpandableSongRow` / `SongsTabView`. The card's
  main tap still launches gameplay (`onSelect`).

**Entry point B — Library tab (song → chart):**
- `LibraryView` content is wrapped in a `NavigationStack`; each `SavedSongRow`
  becomes a `NavigationLink` → **`SongScoresView(song:)`**.
- `SongScoresView(song:)`: loads the song's charts via the async caching pattern
  (`SwiftDataRelationshipLoader`); lists each difficulty with its best score;
  selecting a difficulty navigates to `ChartScoresView(chart:)`.

Both surfaces read attempts as value-type `ScoreAttemptSummary` DTOs — no live
SwiftData models held in the view body.

## Data flow

1. Run completes → `GameplayViewModel.handlePlaybackCompletion()` snapshots the
   `ScoreEngine` into `LiveScoreSnapshot`.
2. `scorePersistence.recordAttempt(...)` inserts a `ScoreRecord`, prunes to 10,
   updates `chart.bestScore` if full-speed and higher, saves, returns `isNewBest`.
3. `SessionResultsView` shows the run + best score + new-record badge.
4. Later, the user opens `ChartScoresView` (from Songs or Library), which fetches
   recent attempts as DTOs and shows best + history.

## Error handling

- `recordAttempt` saves with verification and logs failures via `Logger`
  (mirrors `HighScoreService`). A failed save does not crash gameplay; the badge
  reflects the in-memory result.
- Migration is idempotent (flag-guarded); a partial/failed migration leaves the
  flag unset so it retries next launch. Charts absent from the legacy dict are
  skipped.
- Concurrency: `ScorePersistenceService` is `@MainActor`. Score reads happen in
  the results sheet and the scores views — never in the per-frame notation
  hierarchy. Views consume DTOs and load chart relationships via the async
  caching pattern, per the project's SwiftData concurrency rule.

## Testing

**`ScorePersistenceServiceTests`** (Swift Testing, in-memory `TestContainer`):
- `recordAttempt` inserts a record linked to the chart.
- Pruning keeps the 10 most recent by `playedAt`; older records deleted.
- Best updates only when `atFullSpeed && score > bestScore`; returns `isNewBest`.
- A slowed/faster run is recorded but does not change `bestScore`.
- Zero/negative score: recorded in history, never sets best.
- `recentAttempts` is sorted desc, limited, and maps all fields incl.
  `speedMultiplier`.
- `migrateLegacyHighScores` sets `bestScore` from a seeded legacy dict, sets the
  flag, clears the legacy key, and is idempotent on a second call.

**`GameplayViewModel` tests:**
- Update references from `highScoreService` to `scorePersistence`.
- `sessionAtFullSpeed` transitions: starts full → cleared on slow-down; starts
  slowed → not best-eligible.
- `handlePlaybackCompletion` records with the correct `speedMultiplier` and
  eligibility, and surfaces the returned `isNewRecord`.

**Removed:** `HighScoreServiceTests`.

**UI:** add previews for `ChartScoresView` and `SongScoresView` with sample
summaries; `SessionResultsView` preview is unaffected.

## Files affected

- **New:** `models/ScoreRecord.swift` (or add to `models/DrumTrack.swift`),
  `services/ScorePersistenceService.swift`, `views/ChartScoresView.swift`,
  `views/SongScoresView.swift` (names indicative).
- **Modified:** `models/DrumTrack.swift` (`Chart` additions), `VirgoApp.swift`
  (schema), `viewmodels/GameplayViewModel.swift`, `views/GameplayView.swift`,
  `views/ContentView.swift` (migration call), `views/LibraryView.swift`
  (`NavigationStack` + link), `components/DifficultyExpansionView.swift`
  (`ChartSelectionCard` scores affordance).
- **Deleted:** `services/HighScoreService.swift`,
  `VirgoTests/HighScoreServiceTests.swift`.

## Open considerations (carried, not blocking)

- The displayed `speedMultiplier` for a rare mid-run speed change is the final
  speed; such runs are non-best-eligible regardless.
- `ScoreRecord` count is bounded at 10 per chart, so storage growth is bounded by
  the number of charts played.
