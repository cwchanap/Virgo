# HPA-578 Complete Catalog Snapshot Refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Virgo's additive/compatibility-heavy server catalog refresh with one validated complete snapshot replacement that preserves local songs, reconciles download state by stable server ID, and surfaces load/refresh failures.

**Architecture:** Keep `ServerSongService` as the public facade and `ServerSongCache` as the GraphQL-to-SwiftData cache owner. Fetch and validate all `SimfileDTO` values before any context mutation, reuse `ServerSongStatusManager` for a non-persisting stable-ID status projection, then replace `ServerSong` / `ServerChart` rows with one `ModelContext.save()`. Delete legacy fallback/backfill paths rather than creating sync or migration infrastructure.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, Swift Testing, Apollo-backed `SimfileFetching`, Xcode/xcodebuild.

## Global Constraints

- Support the current development data format only; old local development cache representations may be reset.
- Catalog refresh remains manual. Do not add background sync, retry scheduling, ETags, sync tokens, offline queues, or merge policies.
- Do not add a repository/use-case layer, staging database, generation table, transaction coordinator, or new SwiftData model.
- Fetch and validate the complete DTO snapshot before any `ModelContext.insert` or `ModelContext.delete` call.
- A successful catalog replacement performs one context mutation phase and exactly one save; rollback on save failure.
- Catalog replacement may delete only `ServerSong` / `ServerChart` cache metadata. It must not delete or rewrite local `Song`, `Chart`, `Note`, `ScoreRecord`, or audio files.
- `Song.serverSongId` is the current server identity contract. Do not preserve title/artist fallback matching.
- Keep `ServerSongService` as the screen-facing facade; do not redesign the broader service architecture.
- Do not move parsing/file work off-main in this ticket; HPA-579/HPA-580 own performance decisions.
- Do not change server BGM format behavior; HPA-85 remains separate.
- Do not broaden test/document cleanup beyond HPA-578-specific compatibility tests; HPA-583 owns final consolidation.
- macOS 14+ and iPadOS remain supported; do not add iPhone targeting or iPhone-only assumptions.

---

## File Structure

**Production files modified:**

- `Virgo/utilities/ServerSongStatusManager.swift` — stable-ID-only download-state projection and deletion/status matching.
- `Virgo/utilities/ServerSongCache.swift` — complete page validation and one-save cache replacement.
- `Virgo/utilities/ServerSongDownloader.swift` — stable-ID-only duplicate detection.
- `Virgo/utilities/ServerSongService.swift` — remove legacy URL guard and expose catalog load/refresh failure state.
- `Virgo/models/DrumTrack.swift` — remove the legacy single-file `ServerSong` convenience initializer.
- `Virgo/views/ContentView.swift` — call the result-less catalog load API.
- `Virgo/views/ServerSongsView.swift` — distinguish loading, failed, and valid-empty states.
- `CLAUDE.md` — replace the now-false additive-cache guidance with current snapshot semantics.

**Focused tests modified:**

- `VirgoTests/ServerSongStatusManagerTests.swift`
- `VirgoTests/ServerSongCatalogRefreshTests.swift`
- `VirgoTests/ServerSongCacheCoverageTests.swift`
- `VirgoTests/ServerSongDownloaderTests.swift`
- `VirgoTests/ServerSongServiceTests.swift`
- `VirgoTests/ServerSongModelTests.swift`

No new production file is required.

---

### Task 1: Make server download state stable-ID-only and reusable before save

**Files:**
- Modify: `Virgo/utilities/ServerSongStatusManager.swift`
- Modify: `VirgoTests/ServerSongStatusManagerTests.swift`

**Interfaces:**
- Consumes: current `Song.isServerImported`, `Song.serverSongId`, `Song.bgmFilePath`, `Song.previewFilePath`, and `ServerSong` status flags.
- Produces:
  ```swift
  @MainActor
  @discardableResult
  func applyDownloadStatus(
      to serverSongs: [ServerSong],
      from localSongs: [Song]
  ) -> Bool
  ```
- Produces stable-ID-only matching semantics used by Task 2's snapshot replacement.

- [ ] **Step 1: Rewrite status tests around current stable IDs and add a RED no-fallback regression**

In `VirgoTests/ServerSongStatusManagerTests.swift`, update server-imported test fixtures that are intended to match a server row so they carry the same explicit `serverSongId` as that row.

Add this focused regression using the existing `TestSetup` / `TestContainer` pattern:

```swift
@Test("applyDownloadStatus matches only current serverSongId")
func testApplyDownloadStatusUsesOnlyServerSongId() async throws {
    try await TestSetup.withTestSetup {
        let manager = ServerSongStatusManager()

        let target = ServerSong(
            songId: "target-id",
            title: "Same Title",
            artist: "Same Artist",
            bpm: 120
        )
        let other = ServerSong(
            songId: "other-id",
            title: "Other",
            artist: "Artist",
            bpm: 120,
            isDownloaded: true,
            bgmDownloaded: true,
            previewDownloaded: true
        )

        let currentMatch = Song(
            title: "Renamed Locally",
            artist: "Different Artist",
            bpm: 120,
            duration: "3:00",
            genre: "DTX Import",
            isServerImported: true,
            serverSongId: "target-id",
            bgmFilePath: "/tmp/target.ogg",
            previewFilePath: "/tmp/target.mp3"
        )
        let legacyTitleOnly = Song(
            title: "Other",
            artist: "Artist",
            bpm: 120,
            duration: "3:00",
            genre: "DTX Import",
            isServerImported: true,
            serverSongId: nil,
            bgmFilePath: "/tmp/legacy.ogg",
            previewFilePath: "/tmp/legacy.mp3"
        )

        let changed = manager.applyDownloadStatus(
            to: [target, other],
            from: [currentMatch, legacyTitleOnly]
        )

        #expect(changed)
        #expect(target.isDownloaded)
        #expect(target.bgmDownloaded)
        #expect(target.previewDownloaded)
        #expect(other.isDownloaded == false)
        #expect(other.bgmDownloaded == false)
        #expect(other.previewDownloaded == false)
    }
}
```

Also add/adjust deletion coverage so a same-title/artist local row with `serverSongId == nil` is not deleted by `deleteDownloadedSong` for a current server row.

- [ ] **Step 2: Run the focused suite and verify RED**

Run:

```bash
xcodebuild test \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'platform=macOS' \
  -only-testing:VirgoTests/ServerSongStatusManagerTests \
  -parallel-testing-enabled NO
```

Expected: FAIL because `applyDownloadStatus(to:from:)` does not exist and current title/artist fallback tests/behavior still match nil-ID rows.

- [ ] **Step 3: Add the minimal reusable stable-ID status projection**

In `ServerSongStatusManager.swift`, add:

```swift
@MainActor
@discardableResult
func applyDownloadStatus(
    to serverSongs: [ServerSong],
    from localSongs: [Song]
) -> Bool {
    var localByServerSongID: [String: [Song]] = [:]
    for song in localSongs where song.isServerImported {
        guard let serverSongId = song.serverSongId else { continue }
        localByServerSongID[serverSongId, default: []].append(song)
    }

    var changed = false
    for serverSong in serverSongs {
        let matched = localByServerSongID[serverSong.songId] ?? []
        let isDownloaded = !matched.isEmpty
        let bgmDownloaded = matched.contains { $0.bgmFilePath != nil }
        let previewDownloaded = matched.contains { $0.previewFilePath != nil }

        if serverSong.isDownloaded != isDownloaded {
            serverSong.isDownloaded = isDownloaded
            changed = true
        }
        if serverSong.bgmDownloaded != bgmDownloaded {
            serverSong.bgmDownloaded = bgmDownloaded
            changed = true
        }
        if serverSong.previewDownloaded != previewDownloaded {
            serverSong.previewDownloaded = previewDownloaded
            changed = true
        }
    }
    return changed
}
```

Refactor `refreshDownloadStatus(modelContext:)` to fetch local/server rows, call this method, and keep its existing save/rollback behavior only when `changed == true`.

- [ ] **Step 4: Delete title/artist fallback from status/deletion helpers**

Make `deleteDownloadedSong` select only:

```swift
let songsToDelete = allSongs.filter { song in
    song.isServerImported && song.serverSongId == serverSong.songId
}
```

Simplify local-deletion cache updates to accept `songServerSongId` rather than title/artist identity. The remaining-row check is exact ID only:

```swift
private static func hasOtherImportedSong(
    serverSongId: String,
    excluding songId: PersistentIdentifier,
    context: ModelContext
) throws -> Bool {
    try context.fetch(FetchDescriptor<Song>()).contains { song in
        song.persistentModelID != songId &&
            song.isServerImported &&
            song.serverSongId == serverSongId
    }
}
```

When the deleted local row has `serverSongId == nil`, skip server-cache flag mutation; still delete that local row normally.

Remove the title/artist lookup dictionaries and fallback helpers (`matchedLocalSongs`, fallback `matchesServerSong`, title/artist forms of `matchesSongIdentity` / `matchesServerSongByServerSongId`) once no caller remains.

Keep `pruneCachedSong` compiling for this checkpoint; Task 2 removes its final caller and deletes it.

- [ ] **Step 5: Run status tests and verify GREEN**

Run the same focused command from Step 2.

Expected: PASS. Current-ID matches update flags; nil/different IDs do not match by title/artist; user-initiated deletion behavior still passes.

- [ ] **Step 6: Commit the stable-ID status checkpoint**

```bash
git add Virgo/utilities/ServerSongStatusManager.swift \
  VirgoTests/ServerSongStatusManagerTests.swift
git commit -m "refactor: use stable server IDs for catalog status"
```

---

### Task 2: Replace the catalog from one validated complete snapshot

**Files:**
- Modify: `Virgo/utilities/ServerSongCache.swift`
- Modify: `Virgo/utilities/ServerSongStatusManager.swift`
- Modify: `VirgoTests/ServerSongCatalogRefreshTests.swift`
- Modify: `VirgoTests/ServerSongCacheCoverageTests.swift`
- Modify: `CLAUDE.md`

**Interfaces:**
- Consumes: `SimfileFetching.fetchSimfiles`, `SimfileMapper.makeServerSong`, and Task 1's `applyDownloadStatus(to:from:)`.
- Produces:
  ```swift
  enum ServerSongCatalogRefreshError: LocalizedError, Equatable
  ```
- Produces a throwing private complete-snapshot fetch helper and a one-save `refreshCatalog(modelContext:)`.
- Changes cache load to:
  ```swift
  func loadServerSongs(modelContext: ModelContext) async throws
  ```

- [ ] **Step 1: Replace additive/backfill expectations with snapshot-replacement RED tests**

In `ServerSongCatalogRefreshTests.swift`, replace `testAdditiveAndPrune` with a current-contract test that seeds stale cache metadata and a local current song:

```swift
@Test("Complete refresh replaces metadata, removes stale cache IDs, and preserves local songs")
func testCompleteRefreshReplacesCacheOnly() async throws {
    try await TestSetup.withTestSetup {
        let context = TestContainer.shared.context

        let oldChart = ServerChart(
            difficulty: "easy",
            difficultyLabel: "BASIC",
            level: 10,
            filename: "old.dtx",
            size: 10,
            fileURL: "https://old/old.dtx",
            fileEncoding: "SHIFT_JIS"
        )
        let oldA = ServerSong(
            songId: "a",
            title: "OLD",
            artist: "OLD ARTIST",
            bpm: 90,
            durationSeconds: 100,
            charts: [oldChart]
        )
        let staleZ = ServerSong(songId: "z", title: "STALE", artist: "Z", bpm: 120)
        let localA = Song(
            title: "Local A",
            artist: "Local Artist",
            bpm: 111,
            duration: "9:59",
            genre: "DTX Import",
            isServerImported: true,
            serverSongId: "a",
            bgmFilePath: "/tmp/a.ogg",
            previewFilePath: "/tmp/a.mp3"
        )
        context.insert(oldA)
        context.insert(oldChart)
        context.insert(staleZ)
        context.insert(localA)
        try context.save()

        let fetcher = MockSimfileFetcher(all: [
            .stub(id: "a", title: "NEW"),
            .stub(id: "b")
        ])
        let cache = ServerSongCache(fetcher: fetcher, pageSize: 10)

        try await cache.refreshCatalog(modelContext: context)

        let cacheRows = try context.fetch(FetchDescriptor<ServerSong>())
        let byID = Dictionary(uniqueKeysWithValues: cacheRows.map { ($0.songId, $0) })
        #expect(Set(byID.keys) == ["a", "b"])
        #expect(byID["a"]?.title == "NEW")
        #expect(byID["a"]?.charts.first?.fileURL == "https://r2/a/bas.dtx")
        #expect(byID["a"]?.isDownloaded == true)
        #expect(byID["a"]?.bgmDownloaded == true)
        #expect(byID["a"]?.previewDownloaded == true)

        let localRows = try context.fetch(FetchDescriptor<Song>())
        let preserved = try #require(localRows.first { $0.serverSongId == "a" })
        #expect(preserved.title == "Local A")
        #expect(preserved.duration == "9:59")
        #expect(preserved.bgmFilePath == "/tmp/a.ogg")
        #expect(preserved.previewFilePath == "/tmp/a.mp3")
    }
}
```

Use the actual `.stub(...)` overload fields already available in `TestHelpers`; if a metadata field is not configurable by that helper, construct one `SimfileDTO` directly in the test rather than expanding production code.

- [ ] **Step 2: Add RED non-destructive validation tests**

Replace the old truncated/duplicate-success tests with these contracts:

```swift
@Test("Truncated page walk throws and leaves previous cache untouched")
func testTruncatedWalkIsNonDestructive() async throws { /* seed old -> TruncatingFetcher -> expect throw -> old only */ }

@Test("Duplicate server IDs reject the whole snapshot")
func testDuplicateIDsRejectSnapshot() async throws { /* seed old -> DuplicateIdFetcher -> expect duplicate error -> old only */ }

@Test("Changing totalCount rejects the whole snapshot")
func testChangingTotalCountRejectsSnapshot() async throws { /* page 1 total N, page 2 total N+1 */ }

@Test("Valid empty snapshot clears cache but preserves local songs")
func testEmptySnapshotClearsOnlyServerCache() async throws { /* old ServerSong + local Song -> empty backend */ }
```

For each failure test, assert both the old row still exists and no newly fetched row was partially inserted.

Update the existing network-error test to seed an old cache row first and verify that row remains unchanged after the thrown fetch error.

- [ ] **Step 3: Add a RED one-save/rollback regression**

Use the same injected save hook for both the cache and status manager so current code demonstrates its second status save:

```swift
final class SaveCounter: @unchecked Sendable {
    var count = 0
    func save(_ context: ModelContext) throws {
        count += 1
        try context.save()
    }
}
```

Construct:

```swift
let counter = SaveCounter()
let statusManager = ServerSongStatusManager(saveContext: counter.save)
let cache = ServerSongCache(
    fetcher: fetcher,
    statusManager: statusManager,
    saveContext: counter.save
)
```

Seed a matching local song so status values must change. After refresh:

```swift
#expect(counter.count == 1)
```

Strengthen the existing save-failure rollback test: seed an old persisted cache row, inject a throwing `saveContext`, run replacement, then assert rollback restores the old row rather than merely asserting that new inserts disappeared.

- [ ] **Step 4: Run catalog tests and verify RED**

Run:

```bash
xcodebuild test \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'platform=macOS' \
  -only-testing:VirgoTests/ServerSongCatalogRefreshTests \
  -parallel-testing-enabled NO
```

Expected failures in current code:

- stale metadata remains `OLD` because refresh is additive;
- truncated page walk partially inserts instead of throwing;
- duplicates are silently deduplicated instead of rejected;
- old cache can be pruned through local-song deletion behavior;
- status reconciliation can perform a second save.

- [ ] **Step 5: Implement explicit refresh validation errors**

At file scope in `ServerSongCache.swift` add:

```swift
enum ServerSongCatalogRefreshError: LocalizedError, Equatable {
    case totalCountChanged(expected: Int, actual: Int)
    case incompleteSnapshot(expected: Int, actual: Int)
    case unexpectedSnapshotCount(expected: Int, actual: Int)
    case duplicateSongID(String)

    var errorDescription: String? {
        switch self {
        case .totalCountChanged(let expected, let actual):
            return "Catalog changed during refresh (expected \(expected) items, server now reports \(actual))."
        case .incompleteSnapshot(let expected, let actual):
            return "Catalog refresh was incomplete (expected \(expected) items, received \(actual))."
        case .unexpectedSnapshotCount(let expected, let actual):
            return "Catalog refresh returned an unexpected item count (expected \(expected), received \(actual))."
        case .duplicateSongID(let id):
            return "Catalog refresh returned duplicate song ID '\(id)'."
        }
    }
}
```

- [ ] **Step 6: Replace `fetchAllPages` with a throwing complete-snapshot walk**

Implement the private helper with raw row count as the pagination signal:

```swift
private func fetchCompleteSnapshot(maxPages: Int = 100) async throws -> [SimfileDTO] {
    var results: [SimfileDTO] = []
    var expectedTotalCount: Int?

    for page in 1...maxPages {
        let pageResult = try await fetcher.fetchSimfiles(
            page: page,
            pageSize: pageSize,
            search: nil
        )

        if let expectedTotalCount {
            guard pageResult.totalCount == expectedTotalCount else {
                throw ServerSongCatalogRefreshError.totalCountChanged(
                    expected: expectedTotalCount,
                    actual: pageResult.totalCount
                )
            }
        } else {
            expectedTotalCount = pageResult.totalCount
        }

        let expected = expectedTotalCount ?? 0
        results.append(contentsOf: pageResult.simfiles)

        guard results.count <= expected else {
            throw ServerSongCatalogRefreshError.unexpectedSnapshotCount(
                expected: expected,
                actual: results.count
            )
        }
        if results.count == expected { break }
        guard !pageResult.simfiles.isEmpty else {
            throw ServerSongCatalogRefreshError.incompleteSnapshot(
                expected: expected,
                actual: results.count
            )
        }
    }

    let expected = expectedTotalCount ?? 0
    guard results.count == expected else {
        throw ServerSongCatalogRefreshError.incompleteSnapshot(
            expected: expected,
            actual: results.count
        )
    }

    var seenIDs = Set<String>()
    for dto in results {
        guard seenIDs.insert(dto.id).inserted else {
            throw ServerSongCatalogRefreshError.duplicateSongID(dto.id)
        }
    }
    return results
}
```

This intentionally treats a zero-count/zero-row first page as a valid empty snapshot.

- [ ] **Step 7: Replace cache rows in one mutation phase and one save**

Rewrite `refreshCatalog(modelContext:)` around the validated snapshot:

```swift
func refreshCatalog(modelContext: ModelContext) async throws {
    let serverDTOs = try await fetchCompleteSnapshot()

    let allLevels = serverDTOs.flatMap(\.dtxFiles).map(\.level)
    if let maxLevel = allLevels.max(), maxLevel <= 10, !allLevels.isEmpty {
        Logger.warning(
            "Chart levels max at \(maxLevel) — possible 0-10 scale (expected 0-100). " +
            "Difficulty bucketing may be incorrect."
        )
    }

    let localSongs = try modelContext.fetch(FetchDescriptor<Song>())
    let existingCache = try modelContext.fetch(FetchDescriptor<ServerSong>())
    let replacement = serverDTOs.map(SimfileMapper.makeServerSong(from:))

    statusManager.applyDownloadStatus(to: replacement, from: localSongs)

    for serverSong in existingCache {
        modelContext.delete(serverSong)
    }
    for serverSong in replacement {
        modelContext.insert(serverSong)
        for chart in serverSong.charts {
            modelContext.insert(chart)
        }
    }

    do {
        try saveContext(modelContext)
    } catch {
        modelContext.rollback()
        throw error
    }
}
```

Do not call `refreshDownloadStatus` after this save.

Delete `backfillLegacyChartURLs`, `matchingDtxFile`, `fetchAllPages`, additive insertion, duplicate recovery, and stale-prune loops/comments.

- [ ] **Step 8: Remove obsolete catalog-driven local pruning**

`ServerSongCache` no longer calls `ServerSongStatusManager.pruneCachedSong`. Delete `pruneCachedSong` and private helpers used only by that method from `ServerSongStatusManager.swift`.

Do not replace it with another stale-ID cleanup function. The whole old `ServerSong` cache is discarded as metadata; local songs/audio are out of scope for refresh.

- [ ] **Step 9: Make cache loading throw instead of manufacturing an empty result**

Change:

```swift
func loadServerSongs(modelContext: ModelContext) async throws
```

Implementation:

```swift
func loadServerSongs(modelContext: ModelContext) async throws {
    _ = try modelContext.fetch(FetchDescriptor<ServerSong>())
    await statusManager.refreshDownloadStatus(modelContext: modelContext)
}
```

The live `@Query` remains the UI's source of catalog rows. This method exists to validate/access the cache and reconcile derived status, not to create a second array source of truth.

- [ ] **Step 10: Delete compatibility-only cache tests, retain current-data coverage**

In `ServerSongCatalogRefreshTests.swift`, delete tests whose only contract is:

- legacy empty-`fileURL` backfill;
- label/filename matching for backfill;
- duplicate-ID recovery/deduplication;
- additive preservation of old metadata;
- partial insertion after an incomplete walk.

In `ServerSongCacheCoverageTests.swift`, delete the backfill-only cases. Keep the level-scale warning/current-data coverage.

Do not move unrelated tests between suites; HPA-583 owns broader consolidation.

- [ ] **Step 11: Update live catalog guidance**

In the `### Server Song Management` section of `CLAUDE.md`, replace the additive-cache description with current behavior, for example:

```markdown
- `ServerSongCache`: SwiftData-backed catalog cache. Manual refresh first validates a complete GraphQL DTO snapshot, then replaces `ServerSong` / `ServerChart` cache metadata in one save. Local downloaded `Song` rows are preserved and download flags are projected by `Song.serverSongId`.
```

Do not edit historical plan/blueprint documents in this task.

- [ ] **Step 12: Run focused cache suites and verify GREEN**

Run:

```bash
xcodebuild test \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'platform=macOS' \
  -only-testing:VirgoTests/ServerSongCatalogRefreshTests \
  -only-testing:VirgoTests/ServerSongCacheCoverageTests \
  -parallel-testing-enabled NO
```

Expected: PASS, including exact replacement, non-destructive failures, duplicate rejection, local-song preservation, valid empty snapshot, rollback, and one-save assertions.

- [ ] **Step 13: Commit the snapshot-replacement checkpoint**

```bash
git add Virgo/utilities/ServerSongCache.swift \
  Virgo/utilities/ServerSongStatusManager.swift \
  VirgoTests/ServerSongCatalogRefreshTests.swift \
  VirgoTests/ServerSongCacheCoverageTests.swift \
  CLAUDE.md
git commit -m "refactor: replace server catalog from complete snapshot"
```

---

### Task 3: Delete remaining server-catalog compatibility surfaces

**Files:**
- Modify: `Virgo/utilities/ServerSongDownloader.swift`
- Modify: `Virgo/utilities/ServerSongService.swift`
- Modify: `Virgo/models/DrumTrack.swift`
- Modify: `VirgoTests/ServerSongDownloaderTests.swift`
- Modify: `VirgoTests/ServerSongModelTests.swift`

**Interfaces:**
- Consumes: current stable `ServerSongSnapshot.songId` / `Song.serverSongId` contract.
- Produces: downloader duplicate detection based solely on exact server ID.
- Removes: legacy single-file `ServerSong` initializer and the service's old-empty-URL repair prompt.

- [ ] **Step 1: Replace legacy downloader rejection tests with a RED current-policy test**

Delete the two tests that expect a nil-ID local song to block import by exact/case-insensitive title+artist.

Add:

```swift
@Test("downloadAndImportSong ignores same-title local rows without the current server ID")
func testSameTitleWithoutServerIDDoesNotBlockImport() async throws {
    let mock = MockFileDownloader()
    let config = makeConfig(
        "ServerSongDownloaderTests.noLegacyFallback.\(UUID().uuidString)",
        withR2: false
    )
    let downloader = ServerSongDownloader(
        downloader: mock,
        fileManager: ServerSongFileManager(),
        config: config
    )

    try await TestSetup.withTestSetup {
        let context = TestContainer.shared.context
        let container = TestContainer.shared.container
        let local = Song(
            title: "Same Name",
            artist: "Same Artist",
            bpm: 100,
            duration: "2:00",
            genre: "Local",
            isServerImported: false,
            serverSongId: nil
        )
        context.insert(local)
        try context.save()

        let serverSong = ServerSong(
            songId: "current-server-id",
            title: "Same Name",
            artist: "Same Artist",
            bpm: 120,
            charts: []
        )

        let (success, message) = await downloader.downloadAndImportSong(
            serverSong,
            container: container
        )

        #expect(success)
        #expect(message == nil)
        let songs = try ModelContext(container).fetch(FetchDescriptor<Song>())
        #expect(songs.contains { $0.serverSongId == "current-server-id" })
    }
}
```

Current code should fail because title/artist fallback reports `Song already exists in database`.

- [ ] **Step 2: Run downloader tests and verify RED**

```bash
xcodebuild test \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'platform=macOS' \
  -only-testing:VirgoTests/ServerSongDownloaderTests \
  -parallel-testing-enabled NO
```

Expected: the new nil-ID/same-title test FAILS under current fallback behavior.

- [ ] **Step 3: Reduce `songAlreadyExists` to one targeted server-ID query**

Keep only:

```swift
@MainActor
private func songAlreadyExists(
    snapshot: ServerSongSnapshot,
    in context: ModelContext
) throws -> Bool {
    let songId = snapshot.songId
    let predicate = #Predicate<Song> { song in
        song.serverSongId == songId
    }
    return !(try context.fetch(FetchDescriptor<Song>(predicate: predicate))).isEmpty
}
```

Delete the exact title/artist fetch and case-insensitive nil-ID scan.

Keep existing tests proving the same server ID is rejected and distinct server IDs with the same title/artist are allowed.

- [ ] **Step 4: Delete the legacy empty-chart-URL service guard**

Remove from `ServerSongService.downloadAndImportSong` the block beginning with the comment about legacy entries created before `ServerChart.fileURL` existed and the message:

```text
Please refresh the catalog first — this entry needs updated chart URLs
```

Do not add a replacement guard. Current invalid URLs remain normal `ServerSongDownloader` import errors.

- [ ] **Step 5: Delete the legacy single-file `ServerSong` initializer and its tests**

From `DrumTrack.swift`, delete:

```swift
convenience init(
    filename: String,
    title: String,
    artist: String,
    bpm: Double,
    difficultyLevel: Int,
    size: Int,
    isDownloaded: Bool = false
)
```

From `ServerSongModelTests.swift`, delete the tests named around the legacy convenience initializer and filename-to-song-ID extraction. Retain current `songId:` initializer, media flags, BPM, genre, and duration coverage.

- [ ] **Step 6: Run downloader/model/service suites and verify GREEN**

```bash
xcodebuild test \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'platform=macOS' \
  -only-testing:VirgoTests/ServerSongDownloaderTests \
  -only-testing:VirgoTests/ServerSongModelTests \
  -only-testing:VirgoTests/ServerSongServiceTests \
  -parallel-testing-enabled NO
```

Expected: PASS after test updates; no legacy title/artist or single-file contract remains.

- [ ] **Step 7: Audit deleted compatibility symbols**

Run:

```bash
rg -n \
  'backfillLegacyChartURLs|matchingDtxFile|pruneCachedSong|Please refresh the catalog first|Legacy compatibility for single-file DTX' \
  Virgo VirgoTests CLAUDE.md
```

Expected: no matches.

Run:

```bash
rg -n 'serverSongId ==|serverSongId:' \
  Virgo/utilities/ServerSongDownloader.swift \
  Virgo/utilities/ServerSongStatusManager.swift
```

Expected: current stable-ID checks remain visible.

- [ ] **Step 8: Commit the compatibility deletion checkpoint**

```bash
git add Virgo/utilities/ServerSongDownloader.swift \
  Virgo/utilities/ServerSongService.swift \
  Virgo/models/DrumTrack.swift \
  VirgoTests/ServerSongDownloaderTests.swift \
  VirgoTests/ServerSongModelTests.swift
git commit -m "refactor: remove legacy server catalog matching"
```

---

### Task 4: Surface catalog load/refresh failure in the existing service and view

**Files:**
- Modify: `Virgo/utilities/ServerSongService.swift`
- Modify: `Virgo/views/ContentView.swift`
- Modify: `Virgo/views/ServerSongsView.swift`
- Modify: `VirgoTests/ServerSongServiceTests.swift`

**Interfaces:**
- Consumes: Task 2's throwing `ServerSongCache.loadServerSongs(modelContext:)`.
- Produces:
  ```swift
  @Published private(set) var catalogLoadFailed = false
  func loadServerSongs() async
  ```
- Keeps existing `isLoading`, `isRefreshing`, and `errorMessage` as the UI-facing state.

- [ ] **Step 1: Update the mock cache to the result-less throwing load API**

In `ServerSongServiceTests.swift`, replace the mock cache's array result with an optional error:

```swift
@MainActor
private final class MockServerSongCache: ServerSongCache {
    var loadError: Error?
    var loadCallCount = 0
    var refreshError: Error?
    var refreshCallCount = 0

    init() { super.init(fetcher: MockSimfileFetcher()) }

    override func loadServerSongs(modelContext: ModelContext) async throws {
        loadCallCount += 1
        if let loadError { throw loadError }
    }

    override func refreshCatalog(modelContext: ModelContext) async throws {
        refreshCallCount += 1
        if let refreshError { throw refreshError }
    }
}
```

Remove tests that assert `loadServerSongs()` returns a cache array; the live `@Query` owns row delivery.

- [ ] **Step 2: Add RED failure-state tests**

Add:

```swift
@Test("loadServerSongs exposes cache failure instead of an empty result")
func testLoadFailureIsVisible() async throws {
    struct LoadFailure: LocalizedError {
        var errorDescription: String? { "synthetic load failure" }
    }

    try await TestSetup.withTestSetup {
        let cache = MockServerSongCache()
        cache.loadError = LoadFailure()
        let service = ServerSongService(cache: cache)
        service.setModelContext(TestContainer.shared.context)

        await service.loadServerSongs()

        #expect(cache.loadCallCount == 1)
        #expect(service.isLoading == false)
        #expect(service.catalogLoadFailed)
        #expect(service.errorMessage?.text.contains("Failed to load server songs") == true)
        #expect(service.errorMessage?.text.contains("synthetic load failure") == true)
    }
}
```

Add a success-after-failure test:

```swift
@Test("successful catalog load clears prior failure state")
func testSuccessfulLoadClearsFailure() async throws {
    try await TestSetup.withTestSetup {
        struct LoadFailure: LocalizedError {
            var errorDescription: String? { "first failure" }
        }
        let cache = MockServerSongCache()
        let service = ServerSongService(cache: cache)
        service.setModelContext(TestContainer.shared.context)

        cache.loadError = LoadFailure()
        await service.loadServerSongs()
        #expect(service.catalogLoadFailed)

        cache.loadError = nil
        await service.loadServerSongs()
        #expect(service.catalogLoadFailed == false)
        #expect(service.isLoading == false)
    }
}
```

Update the existing refresh failure/success tests to assert failed refresh sets `catalogLoadFailed == true` and a later successful refresh clears it.

- [ ] **Step 3: Run service tests and verify RED**

```bash
xcodebuild test \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'platform=macOS' \
  -only-testing:VirgoTests/ServerSongServiceTests \
  -parallel-testing-enabled NO
```

Expected: FAIL because `catalogLoadFailed` and the result-less service load contract do not exist yet.

- [ ] **Step 4: Implement minimal service state transitions**

Add:

```swift
@Published private(set) var catalogLoadFailed = false
```

Implement load as:

```swift
func loadServerSongs() async {
    guard let modelContext else { return }

    isLoading = true
    errorMessage = nil
    defer { isLoading = false }

    do {
        try await cache.loadServerSongs(modelContext: modelContext)
        catalogLoadFailed = false
    } catch {
        catalogLoadFailed = true
        errorMessage = AlertMessage(
            "Failed to load server songs: \(error.localizedDescription)"
        )
        Logger.error("Failed to load server songs: \(error)")
    }
}
```

In `refreshCatalog()` keep the existing alert behavior, add `defer { isRefreshing = false }`, set `catalogLoadFailed = false` on success and `true` on failure.

Do not add a second catalog array or a new enum.

- [ ] **Step 5: Update `ContentView` to stop discarding a fake array result**

Change the startup call from:

```swift
_ = await serverSongService.loadServerSongs()
```

to:

```swift
await serverSongService.loadServerSongs()
```

No other startup flow changes belong here.

- [ ] **Step 6: Distinguish loading, failed, and valid-empty placeholders**

In both list and grid empty branches of `ServerSongsView`, use this order:

```swift
if serverSongService.isLoading || serverSongService.isRefreshing {
    loadingRow
} else if serverSongService.catalogLoadFailed {
    failedState
} else {
    emptyState
}
```

Add one small failed placeholder:

```swift
private var failedState: some View {
    VStack(spacing: 16) {
        Image(systemName: "exclamationmark.icloud")
            .font(.system(size: 50))
            .foregroundColor(theme.secondary)
        Text("Couldn’t load server songs")
            .font(.title2)
            .foregroundColor(theme.primary)
        Text("Tap refresh to try again")
            .font(.body)
            .foregroundColor(theme.secondary)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 40)
    .accessibilityIdentifier("serverSongsLoadErrorState")
}
```

Add `serverSongsLoadingState` / `serverSongsEmptyState` identifiers to the existing placeholders while touching this branch so UI smoke tests can target them later without a separate harness.

When cached rows are non-empty, continue rendering them even if the latest refresh failed; the alert communicates the refresh failure and the old snapshot remains usable.

- [ ] **Step 7: Run service and focused server-song UI-related unit suites**

```bash
xcodebuild test \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'platform=macOS' \
  -only-testing:VirgoTests/ServerSongServiceTests \
  -only-testing:VirgoTests/SongsTabCoverageTests \
  -parallel-testing-enabled NO
```

Expected: PASS.

- [ ] **Step 8: Commit the visible-failure checkpoint**

```bash
git add Virgo/utilities/ServerSongService.swift \
  Virgo/views/ContentView.swift \
  Virgo/views/ServerSongsView.swift \
  VirgoTests/ServerSongServiceTests.swift
git commit -m "fix: surface server catalog load failures"
```

---

## Final Verification

- [ ] **Run all HPA-578 focused suites together**

```bash
xcodebuild test \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'platform=macOS' \
  -only-testing:VirgoTests/ServerSongCatalogRefreshTests \
  -only-testing:VirgoTests/ServerSongCacheCoverageTests \
  -only-testing:VirgoTests/ServerSongStatusManagerTests \
  -only-testing:VirgoTests/ServerSongDownloaderTests \
  -only-testing:VirgoTests/ServerSongServiceTests \
  -only-testing:VirgoTests/ServerSongModelTests \
  -parallel-testing-enabled NO
```

Expected: PASS.

- [ ] **Run the complete macOS unit suite with repository-required parallel testing disabled**

```bash
xcodebuild test \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'platform=macOS' \
  -configuration Debug \
  -only-testing:VirgoTests \
  -parallel-testing-enabled NO \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  -enableCodeCoverage YES \
  -destination-timeout 300 \
  -derivedDataPath ./DerivedData
```

Expected: PASS.

- [ ] **Build the iPad simulator target to catch platform-only compile errors**

```bash
xcodebuild -project Virgo.xcodeproj -scheme Virgo \
  -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M4)' build
```

Expected: BUILD SUCCEEDED. Do not switch this to an iPhone destination.

- [ ] **Run lint and diff checks**

```bash
swiftlint lint
git diff --check main...HEAD
```

Expected: no SwiftLint errors and no whitespace errors.

- [ ] **Run a residual compatibility/scope audit**

```bash
rg -n \
  'backfillLegacyChartURLs|matchingDtxFile|pruneCachedSong|Please refresh the catalog first|Legacy compatibility for single-file DTX' \
  Virgo VirgoTests CLAUDE.md
```

Expected: no matches.

```bash
rg -n 'refreshCatalog\(|loadServerSongs\(|applyDownloadStatus\(' \
  Virgo VirgoTests
```

Expected: only the current service/cache/status paths and their focused tests.

- [ ] **Review the final diff for scope**

```bash
git diff --stat main...HEAD
git diff main...HEAD -- \
  Virgo/utilities/ServerSongCache.swift \
  Virgo/utilities/ServerSongStatusManager.swift \
  Virgo/utilities/ServerSongDownloader.swift \
  Virgo/utilities/ServerSongService.swift \
  Virgo/models/DrumTrack.swift \
  Virgo/views/ContentView.swift \
  Virgo/views/ServerSongsView.swift \
  CLAUDE.md
```

Confirm the diff contains no new sync framework, no local-song migration/pruning during catalog refresh, no off-main performance work, and no unrelated HPA-583 cleanup.
