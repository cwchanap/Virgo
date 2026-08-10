# HPA-578 Complete Catalog Snapshot Refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Virgo's additive/compatibility-heavy server catalog refresh with one validated complete snapshot replacement that preserves local songs, reconciles download state by stable server ID, and surfaces load/refresh failures.

**Architecture:** Keep `ServerSongService` as the public facade and `ServerSongCache` as the GraphQL-to-SwiftData cache owner. Fetch and validate all `SimfileDTO` values before context mutation, reuse `ServerSongStatusManager` for a non-persisting stable-ID status projection, then replace `ServerSong` / `ServerChart` rows with one `ModelContext.save()`. Delete legacy fallback/backfill paths rather than creating sync or migration infrastructure.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, Swift Testing, Apollo-backed `SimfileFetching`, Xcode/xcodebuild.

## Global Constraints

- Support the current development data format only; old development cache representations may be reset.
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

## Review Hardening

The design is unchanged. This revision tightens the implementation contract in four places:

1. **Identity cleanup is a call-graph delete, not a local edit.** Task 1 names every title/artist fallback helper that must disappear from `ServerSongStatusManager`; Task 3 names both fallback legs in `ServerSongDownloader.songAlreadyExists`.
2. **Old-contract tests are migrated at the owning checkpoint.** Each task includes a named delete/rewrite inventory so the full suite does not first turn red at final verification.
3. **Initial loading state is required in both server-song layouts.** `serverList` and `gridPlaceholder` must both branch `loading -> failed -> valid empty` when no rows exist.
4. **Residual verification searches the old identity graph, not just the obvious backfill symbols.** Final `rg` checks include the matcher helpers, title/artist lookup dictionary, nil-ID fallback, and the legacy empty-URL service message.

The four catalog validation error cases remain separate. They represent distinct bad snapshots and make focused tests/debugging clearer; no additional error framework is introduced.

---

## File Structure

**Production files modified:**

- `Virgo/utilities/ServerSongStatusManager.swift` — stable-ID-only download-state projection and deletion/status matching.
- `Virgo/utilities/ServerSongCache.swift` — complete page validation, one-save cache replacement, and throwing cache-load access.
- `Virgo/utilities/ServerSongDownloader.swift` — stable-ID-only duplicate detection.
- `Virgo/utilities/ServerSongService.swift` — remove legacy URL guard and expose catalog load/refresh failure state.
- `Virgo/models/DrumTrack.swift` — remove the legacy single-file `ServerSong` convenience initializer.
- `Virgo/views/ContentView.swift` — call the result-less catalog load API.
- `Virgo/views/ServerSongsView.swift` — distinguish loading, failed, and valid-empty states in both list/grid layouts.
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

## Task 1: Collapse status/deletion identity to exact `serverSongId`

**Files:**
- Modify: `Virgo/utilities/ServerSongStatusManager.swift`
- Modify: `VirgoTests/ServerSongStatusManagerTests.swift`

**Interfaces:**
- Consumes: `Song.isServerImported`, `Song.serverSongId`, `Song.bgmFilePath`, `Song.previewFilePath`, and the three `ServerSong` download flags.
- Produces:
  ```swift
  @MainActor
  @discardableResult
  func applyDownloadStatus(
      to serverSongs: [ServerSong],
      from localSongs: [Song]
  ) -> Bool
  ```
- Produces one remaining-row helper used by local deletion:
  ```swift
  private static func hasOtherImportedSong(
      serverSongId: String,
      excludingSongId: PersistentIdentifier,
      context: ModelContext
  ) throws -> Bool
  ```

### Exact matcher-deletion inventory

By the end of this task, delete the title/artist identity graph from `ServerSongStatusManager.swift`:

- `matchedLocalSongs(for:byServerSongId:byTitleArtist:)`
- `matchesServerSong(_:serverSong:)`
- instance `matchesSongIdentity(...)`
- static `matchesSongIdentity(...)`
- instance `matchesServerSongByServerSongId(...)`
- static `matchesServerSongByServerSongId(...)`
- instance `checkForOtherMatchingSongs(...)`
- static `checkForOtherMatchingSongs(...)`
- `songTitle` / `songArtist` parameters captured for `deleteLocalSong` cache-status reconciliation
- the `byTitleArtist` dictionary in `refreshDownloadStatus`

`isAlreadyDownloaded`, `hasBGMFile`, and `hasPreviewFile` are compatibility/prune helpers. Keep only what is needed to compile `pruneCachedSong` during this checkpoint; Task 2 deletes `pruneCachedSong` and then removes any now-unreferenced helpers.

### Test migration for Task 1

Before making production changes, update current server fixtures in `ServerSongStatusManagerTests.swift` so a row intended to match a server song carries its exact `serverSongId`. In particular:

| Existing coverage | Action |
|---|---|
| `setupGroupedSongs` imported rows | Rewrite both imported rows with `serverSongId: "song-group"`; keep the non-imported row without a server ID. |
| `testRefreshDownloadStatusUpdatesFlags` | Rewrite the matching local row with the matching server ID; title/artist should no longer be the matching contract. |
| deletion tests that intentionally model server imports | Give each current server-imported local row the expected server ID. |
| any test whose only purpose is nil-ID title/artist fallback | Delete or replace with an explicit “same title does not match without ID” regression. |

- [ ] **Step 1: Add RED stable-ID projection and deletion regressions**

Add to `ServerSongStatusManagerTests.swift`:

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
        let titleOnly = ServerSong(
            songId: "title-only-id",
            title: "Legacy Title",
            artist: "Legacy Artist",
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
            title: "Legacy Title",
            artist: "Legacy Artist",
            bpm: 120,
            duration: "3:00",
            genre: "DTX Import",
            isServerImported: true,
            serverSongId: nil,
            bgmFilePath: "/tmp/legacy.ogg",
            previewFilePath: "/tmp/legacy.mp3"
        )

        let changed = manager.applyDownloadStatus(
            to: [target, titleOnly],
            from: [currentMatch, legacyTitleOnly]
        )

        #expect(changed)
        #expect(target.isDownloaded)
        #expect(target.bgmDownloaded)
        #expect(target.previewDownloaded)
        #expect(titleOnly.isDownloaded == false)
        #expect(titleOnly.bgmDownloaded == false)
        #expect(titleOnly.previewDownloaded == false)
    }
}

@Test("deleteDownloadedSong ignores same-title rows without matching serverSongId")
func testDeleteDownloadedSongRequiresServerSongId() async throws {
    try await TestSetup.withTestSetup {
        let context = TestContainer.shared.context
        let manager = ServerSongStatusManager()
        let serverSong = ServerSong(
            songId: "current-id",
            title: "Same Title",
            artist: "Same Artist",
            bpm: 120,
            isDownloaded: true
        )
        let titleOnly = Song(
            title: "Same Title",
            artist: "Same Artist",
            bpm: 120,
            duration: "3:00",
            genre: "DTX Import",
            isServerImported: true,
            serverSongId: nil
        )
        context.insert(serverSong)
        context.insert(titleOnly)
        try context.save()

        let success = await manager.deleteDownloadedSong(
            serverSong,
            modelContext: context
        )

        #expect(success)
        TestAssertions.assertNotDeleted(titleOnly, in: context)
        #expect(serverSong.isDownloaded == false)
    }
}

@Test("deleteLocalSong with no serverSongId does not mutate same-title server cache")
func testDeleteLocalSongWithoutServerIDSkipsCacheIdentityFallback() async throws {
    try await TestSetup.withTestSetup {
        let context = TestContainer.shared.context
        let container = TestContainer.shared.container
        let manager = ServerSongStatusManager()
        let serverSong = ServerSong(
            songId: "server-id",
            title: "Same Title",
            artist: "Same Artist",
            bpm: 120,
            isDownloaded: true,
            bgmDownloaded: true,
            previewDownloaded: true
        )
        let local = Song(
            title: "Same Title",
            artist: "Same Artist",
            bpm: 120,
            duration: "3:00",
            genre: "Local",
            isServerImported: false,
            serverSongId: nil
        )
        context.insert(serverSong)
        context.insert(local)
        try context.save()

        #expect(await manager.deleteLocalSong(local, container: container))

        let verification = ModelContext(container)
        let cached = try #require(
            verification.fetch(FetchDescriptor<ServerSong>())
                .first { $0.songId == "server-id" }
        )
        #expect(cached.isDownloaded)
        #expect(cached.bgmDownloaded)
        #expect(cached.previewDownloaded)
    }
}
```

- [ ] **Step 2: Run the focused suite and verify RED**

```bash
xcodebuild test \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'platform=macOS' \
  -only-testing:VirgoTests/ServerSongStatusManagerTests \
  -parallel-testing-enabled NO
```

Expected: FAIL because `applyDownloadStatus(to:from:)` does not exist and current deletion/status paths still accept title/artist fallback matching.

- [ ] **Step 3: Add the reusable status projector**

Add to `ServerSongStatusManager.swift`:

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

Refactor `refreshDownloadStatus(modelContext:)` to fetch local/server rows, call this method, and keep the existing save/rollback behavior only when it returns `true`.

- [ ] **Step 4: Make user-initiated deletion exact-ID-only**

Change `deleteDownloadedSong` selection to:

```swift
let songsToDelete = allSongs.filter { song in
    song.isServerImported && song.serverSongId == serverSong.songId
}
```

In `deleteLocalSong`, stop capturing lowercased title/artist. Capture only:

```swift
let songServerSongId = song.serverSongId
let songId = song.persistentModelID
```

After deleting `songToDelete`, update server cache flags only when `songServerSongId` is non-nil:

```swift
if let serverSongId = songServerSongId {
    let hasOther = try Self.hasOtherImportedSong(
        serverSongId: serverSongId,
        excludingSongId: songId,
        context: backgroundContext
    )
    if !hasOther {
        let cachedSongs = try backgroundContext.fetch(FetchDescriptor<ServerSong>())
        for cached in cachedSongs where cached.songId == serverSongId {
            cached.isDownloaded = false
            cached.bgmDownloaded = false
            cached.previewDownloaded = false
        }
    }
}
```

Add exactly this helper:

```swift
private static func hasOtherImportedSong(
    serverSongId: String,
    excludingSongId: PersistentIdentifier,
    context: ModelContext
) throws -> Bool {
    try context.fetch(FetchDescriptor<Song>()).contains { song in
        song.persistentModelID != excludingSongId &&
            song.isServerImported &&
            song.serverSongId == serverSongId
    }
}
```

Delete the old `updateServerSongStatus` / `checkForOtherMatchingSongs` wrapper/static graph rather than forwarding through old title/artist parameters.

- [ ] **Step 5: Delete all migrated matcher symbols and run a checkpoint audit**

```bash
rg -n \
  'matchedLocalSongs|matchesServerSong\(|matchesSongIdentity|matchesServerSongByServerSongId|checkForOtherMatchingSongs|byTitleArtist|songTitle|songArtist' \
  Virgo/utilities/ServerSongStatusManager.swift
```

Expected: no identity-fallback matches. A logging/message use of title/artist unrelated to identity would need explicit review before keeping it; do not keep the old matcher parameters.

- [ ] **Step 6: Run status tests and verify GREEN**

Run the command from Step 2.

Expected: PASS. Exact IDs drive status/deletion; same-title/artist nil-ID rows do not.

- [ ] **Step 7: Commit the checkpoint**

```bash
git add Virgo/utilities/ServerSongStatusManager.swift \
  VirgoTests/ServerSongStatusManagerTests.swift
git commit -m "refactor: use stable server IDs for catalog status"
```

---

## Task 2: Replace the catalog from one validated complete snapshot

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
- Produces a throwing private `fetchCompleteSnapshot(maxPages:)` and a one-save `refreshCatalog(modelContext:)`.

### Named catalog-test migration

Apply these changes in `ServerSongCatalogRefreshTests.swift` as part of this task:

| Existing test | Action |
|---|---|
| `testInsertsNew` | Keep; it remains valid from an empty cache. |
| `testAdditiveAndPrune` | Replace with `testCompleteRefreshReplacesCacheOnly`. |
| `testNoPruneOnTruncatedWalk` | Replace with `testTruncatedWalkIsNonDestructive`; incomplete data must throw and insert nothing. |
| `testBackfillLegacyChartURLs` | Delete. |
| `testBackfillLegacyChartEncoding` | Delete. |
| `testNoBackfillWhenFileURLPresent` | Delete. |
| `testBackfillAndPruneSameRefresh` | Delete. |
| `testRefreshCatalogThrowsOnFetchError` | Replace/strengthen as `testFetchFailureIsNonDestructive`. |
| `testRefreshCatalogRollsBackOnSaveFailure` | Rewrite to seed an old cache row and assert rollback restores that row. |
| `testDuplicateDTOsDontCrash` | Replace with `testDuplicateIDsRejectSnapshot`. |
| `testDuplicateDTOsBackfillSafe` | Delete. |
| `testCrossPageDuplicatesDoNotMarkCompleteEarly` | Delete; duplicates are now invalid immediately, not tolerated pagination input. |
| `testLoadServerSongsReconcilesDownloadStatus` | Keep for Task 4, but rewrite there for the result-less load API. |

Apply these changes in `ServerSongCacheCoverageTests.swift`:

- keep `testLevelScaleWarning`;
- delete all `Backfill...` tests and duplicate-backfill warning coverage because the production backfill path is deleted rather than preserved.

- [ ] **Step 1: Add/replace the complete-replacement regression**

Use a test that seeds cache `a` + stale `z` and a local `Song(serverSongId: "a")`, then refreshes with changed `a` + new `b`. Assert exact cache IDs `["a", "b"]`, all changed metadata/chart URL/encoding/media fields, projected download flags, and that the local `Song` metadata/audio paths remain untouched.

The critical assertions are:

```swift
#expect(Set(byID.keys) == ["a", "b"])
#expect(byID["a"]?.title == "NEW")
#expect(byID["a"]?.artist == "NEW ARTIST")
#expect(byID["a"]?.bpm == 150)
#expect(byID["a"]?.durationSeconds == 222)
#expect(byID["a"]?.charts.first?.fileURL == "https://r2/a/new-bas.dtx")
#expect(byID["a"]?.charts.first?.fileEncoding == "UTF_8")
#expect(byID["a"]?.isDownloaded == true)
#expect(byID["a"]?.bgmDownloaded == true)
#expect(byID["a"]?.previewDownloaded == true)

let localRows = try context.fetch(FetchDescriptor<Song>())
let preserved = try #require(localRows.first { $0.serverSongId == "a" })
#expect(preserved.title == "Local A")
#expect(preserved.duration == "9:59")
#expect(preserved.bgmFilePath == "/tmp/a.ogg")
#expect(preserved.previewFilePath == "/tmp/a.mp3")
```

- [ ] **Step 2: Add exact invalid-snapshot fetchers**

Keep the existing `TruncatingFetcher`. Add suite-local duplicate and changing-count fetchers:

```swift
private final class DuplicateIdFetcher: SimfileFetching, @unchecked Sendable {
    func fetchSimfiles(page: Int, pageSize: Int, search: String?) async throws -> SimfilePage {
        if page == 1 {
            return SimfilePage(
                simfiles: [.stub(id: "dup"), .stub(id: "dup")],
                totalCount: 2
            )
        }
        return SimfilePage(simfiles: [], totalCount: 2)
    }

    func fetchSimfile(id: String) async throws -> SimfileDTO? { nil }
}

private final class ChangingTotalCountFetcher: SimfileFetching, @unchecked Sendable {
    func fetchSimfiles(page: Int, pageSize: Int, search: String?) async throws -> SimfilePage {
        switch page {
        case 1:
            return SimfilePage(simfiles: [.stub(id: "a")], totalCount: 2)
        case 2:
            return SimfilePage(simfiles: [.stub(id: "b")], totalCount: 3)
        default:
            return SimfilePage(simfiles: [], totalCount: 3)
        }
    }

    func fetchSimfile(id: String) async throws -> SimfileDTO? { nil }
}

@MainActor
private final class RecordingStatusManager: ServerSongStatusManager {
    private(set) var refreshDownloadStatusCallCount = 0

    override func refreshDownloadStatus(modelContext: ModelContext) async {
        refreshDownloadStatusCallCount += 1
        await super.refreshDownloadStatus(modelContext: modelContext)
    }
}
```

- [ ] **Step 3: Add non-destructive RED tests**

For truncated pagination, duplicate IDs, changing `totalCount`, and request failure:

1. persist `ServerSong(songId: "old", title: "OLD", ...)`;
2. call `refreshCatalog` with the invalid fetcher;
3. expect the corresponding error;
4. fetch cache rows and assert the only row remains `old` with unchanged metadata.

For a valid empty snapshot, seed one cache row plus one local `Song`, refresh from `MockSimfileFetcher(all: [])`, and assert the server cache is empty while the local `Song` remains present with its audio path.

For save failure, seed `old`, inject a throwing `saveContext`, call refresh with a valid non-empty DTO snapshot, and assert rollback leaves only `old`.

- [ ] **Step 4: Add a RED one-save/no-post-reconcile test**

```swift
@Test("Complete refresh saves once and does not run post-save status refresh")
func testCompleteRefreshUsesOneSave() async throws {
    try await TestSetup.withTestSetup {
        let context = TestContainer.shared.context
        context.insert(Song(
            title: "Local A",
            artist: "Artist",
            bpm: 120,
            duration: "3:00",
            genre: "DTX Import",
            isServerImported: true,
            serverSongId: "a",
            bgmFilePath: "/tmp/a.ogg"
        ))
        try context.save()

        var cacheSaveCount = 0
        let statusManager = RecordingStatusManager()
        let cache = ServerSongCache(
            fetcher: MockSimfileFetcher(all: [.stub(id: "a")]),
            statusManager: statusManager,
            pageSize: 10,
            saveContext: { context in
                cacheSaveCount += 1
                try context.save()
            }
        )

        try await cache.refreshCatalog(modelContext: context)

        #expect(cacheSaveCount == 1)
        #expect(statusManager.refreshDownloadStatusCallCount == 0)
        let row = try #require(context.fetch(FetchDescriptor<ServerSong>()).first)
        #expect(row.isDownloaded)
        #expect(row.bgmDownloaded)
    }
}
```

- [ ] **Step 5: Run catalog tests and verify RED**

```bash
xcodebuild test \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'platform=macOS' \
  -only-testing:VirgoTests/ServerSongCatalogRefreshTests \
  -parallel-testing-enabled NO
```

Expected: stale metadata remains stale in current code, invalid snapshots are tolerated/partially applied, and post-save status reconciliation is still invoked.

- [ ] **Step 6: Add explicit refresh validation errors**

At file scope in `ServerSongCache.swift`:

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

- [ ] **Step 7: Replace page walking with complete-snapshot validation**

Replace `fetchAllPages` with:

```swift
private func fetchCompleteSnapshot(maxPages: Int = 100) async throws -> [SimfileDTO] {
    var results: [SimfileDTO] = []
    var seenIDs = Set<String>()
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

        for dto in pageResult.simfiles {
            guard seenIDs.insert(dto.id).inserted else {
                throw ServerSongCatalogRefreshError.duplicateSongID(dto.id)
            }
            results.append(dto)
        }

        let expected = expectedTotalCount ?? 0
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
    return results
}
```

A first page with zero rows and `totalCount == 0` is valid. Duplicate IDs fail before count mismatch; unique-ID count is never used as the completion condition.

- [ ] **Step 8: Replace cache rows in one mutation phase and one save**

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
    let replacement = serverDTOs.map { SimfileMapper.makeServerSong(from: $0) }

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

Delete `backfillLegacyChartURLs`, `matchingDtxFile`, old `fetchAllPages`, additive insertion, duplicate recovery, stale-prune loops/comments, and the post-save `refreshDownloadStatus` call.

- [ ] **Step 9: Delete obsolete catalog-driven local pruning and its helper tail**

Delete `ServerSongStatusManager.pruneCachedSong` after `ServerSongCache` no longer calls it. Then run:

```bash
rg -n 'isAlreadyDownloaded|hasBGMFile|hasPreviewFile|pruneCachedSong' \
  Virgo/utilities/ServerSongStatusManager.swift Virgo/utilities/ServerSongCache.swift
```

Delete `isAlreadyDownloaded`, `hasBGMFile`, or `hasPreviewFile` if they have no remaining current caller. Do not replace catalog-driven local deletion with another cleanup path.

- [ ] **Step 10: Delete compatibility-only cache tests and keep current-data coverage**

Apply the named migration table above. Do not retain disabled/skipped backfill tests.

- [ ] **Step 11: Update live repository guidance**

In `CLAUDE.md` under `### Server Song Management`, replace the additive-cache bullet with:

```markdown
- `ServerSongCache`: SwiftData-backed catalog cache. Manual refresh first validates a complete GraphQL DTO snapshot, then replaces `ServerSong` / `ServerChart` cache metadata in one save. Local downloaded `Song` rows are preserved and download flags are projected by `Song.serverSongId`.
```

Do not edit historical planning documents in this implementation ticket.

- [ ] **Step 12: Run focused cache suites and verify GREEN**

```bash
xcodebuild test \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'platform=macOS' \
  -only-testing:VirgoTests/ServerSongCatalogRefreshTests \
  -only-testing:VirgoTests/ServerSongCacheCoverageTests \
  -parallel-testing-enabled NO
```

Expected: PASS, including exact replacement, non-destructive failures, duplicate rejection, local-song preservation, valid empty snapshot, rollback, and one-save/no-post-reconcile assertions.

- [ ] **Step 13: Commit the checkpoint**

```bash
git add Virgo/utilities/ServerSongCache.swift \
  Virgo/utilities/ServerSongStatusManager.swift \
  VirgoTests/ServerSongCatalogRefreshTests.swift \
  VirgoTests/ServerSongCacheCoverageTests.swift \
  CLAUDE.md
git commit -m "refactor: replace server catalog from complete snapshot"
```

---

## Task 3: Delete remaining server-catalog compatibility surfaces

**Files:**
- Modify: `Virgo/utilities/ServerSongDownloader.swift`
- Modify: `Virgo/utilities/ServerSongService.swift`
- Modify: `Virgo/models/DrumTrack.swift`
- Modify: `VirgoTests/ServerSongDownloaderTests.swift`
- Modify: `VirgoTests/ServerSongServiceTests.swift`
- Modify: `VirgoTests/ServerSongModelTests.swift`

**Interfaces:**
- Consumes: current `ServerSongSnapshot.songId` / `Song.serverSongId` identity.
- Produces: duplicate detection based solely on exact server ID.
- Removes: the two nil-ID title/artist legs of `songAlreadyExists`, the old-empty-URL service repair prompt, and legacy single-file `ServerSong` construction.

### Named compatibility-test migration

| Existing test | Action |
|---|---|
| `ServerSongDownloaderTests.testDuplicateDetectionByServerSongId` | Keep. |
| `ServerSongDownloaderTests.testAllowsDistinctServerSongsWithSameTitleArtist` | Keep. |
| `ServerSongDownloaderTests.testRejectsImportWhenLegacySongMatchesTitleArtist` | Delete/replace with the same-title nil-ID row **does not block** current import regression below. |
| `ServerSongDownloaderTests.testRejectsImportWhenLegacySongMatchesCaseInsensitive` | Delete; case-insensitive fallback is deleted, not supported. |
| `ServerSongServiceTests.testDownloadAndImportSongRejectsLegacyEmptyChartURL` | Delete with the service guard. Downloader invalid-URL coverage remains the owner of malformed current chart URLs. |
| `ServerSongModelTests.testServerSongLegacyInitializer` | Delete with convenience initializer. |
| `ServerSongModelTests.testServerSongIDExtraction` | Delete with convenience initializer. |

- [ ] **Step 1: Add the RED current-policy downloader test**

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
        context.insert(Song(
            title: "Same Name",
            artist: "Same Artist",
            bpm: 100,
            duration: "2:00",
            genre: "Local",
            isServerImported: false,
            serverSongId: nil
        ))
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

Current code should fail with `Song already exists in database` because the exact/case-insensitive title/artist fallback still runs for nil-ID local rows.

- [ ] **Step 2: Run downloader tests and verify RED**

```bash
xcodebuild test \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'platform=macOS' \
  -only-testing:VirgoTests/ServerSongDownloaderTests \
  -parallel-testing-enabled NO
```

- [ ] **Step 3: Reduce `songAlreadyExists` to one stable-ID query**

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

Delete both old legs:

1. exact `title == snapshot.title && artist == snapshot.artist && serverSongId == nil` fetch;
2. case-insensitive scan across nil-ID rows.

- [ ] **Step 4: Delete the old-empty-URL service guard and its owning test**

Remove the `ServerSongService.downloadAndImportSong` block whose message is:

```text
Please refresh the catalog first — this entry needs updated chart URLs
```

Delete `ServerSongServiceTests.testDownloadAndImportSongRejectsLegacyEmptyChartURL` in the same checkpoint.

Do not add a replacement guard. `ServerSongDownloader.processChart` / `ServerSongImportError.invalidChartURL` remains the current-data failure path and already has downloader-level empty-URL coverage.

- [ ] **Step 5: Delete the legacy single-file `ServerSong` initializer and tests**

Delete:

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

Delete `testServerSongLegacyInitializer` and `testServerSongIDExtraction`. Retain current `songId:` initializer, media, BPM, genre, and duration coverage.

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

Expected: PASS.

- [ ] **Step 7: Run the compatibility call-graph audit**

```bash
rg -n \
  'backfillLegacyChartURLs|matchingDtxFile|pruneCachedSong|Please refresh the catalog first|Legacy compatibility for single-file DTX' \
  Virgo VirgoTests CLAUDE.md
```

Expected: no matches.

```bash
rg -n \
  'matchesSongIdentity|matchesServerSongByServerSongId|matchedLocalSongs|byTitleArtist|serverSongId == nil|titleArtistPredicate|noServerIdPredicate' \
  Virgo/utilities/ServerSongStatusManager.swift \
  Virgo/utilities/ServerSongDownloader.swift
```

Expected: no matches. If a new nil-ID check is introduced for non-identity behavior, review it explicitly rather than accepting it as an audit exception.

- [ ] **Step 8: Commit the checkpoint**

```bash
git add Virgo/utilities/ServerSongDownloader.swift \
  Virgo/utilities/ServerSongService.swift \
  Virgo/models/DrumTrack.swift \
  VirgoTests/ServerSongDownloaderTests.swift \
  VirgoTests/ServerSongServiceTests.swift \
  VirgoTests/ServerSongModelTests.swift
git commit -m "refactor: remove legacy server catalog matching"
```

---

## Task 4: Surface catalog load/refresh failure in the existing service and view

**Files:**
- Modify: `Virgo/utilities/ServerSongCache.swift`
- Modify: `Virgo/utilities/ServerSongService.swift`
- Modify: `Virgo/views/ContentView.swift`
- Modify: `Virgo/views/ServerSongsView.swift`
- Modify: `VirgoTests/ServerSongServiceTests.swift`
- Modify: `VirgoTests/ServerSongCatalogRefreshTests.swift`

**Interfaces:**
- Changes cache load to:
  ```swift
  func loadServerSongs(modelContext: ModelContext) async throws
  ```
- Produces service state/API:
  ```swift
  @Published private(set) var catalogLoadFailed = false
  func loadServerSongs() async
  ```
- Keeps existing `isLoading`, `isRefreshing`, and `errorMessage`.

### Named load/failure test migration

| Existing test | Action |
|---|---|
| `ServerSongServiceTests.testLoadServerSongsWithoutModelContext` | Rewrite for void API: call `await service.loadServerSongs()` and assert no loading/error/failure state is introduced. |
| `ServerSongServiceTests.testLoadServerSongsWithContextUsesCacheResult` | Delete; live catalog rows come from `@Query`, not a service-returned array. |
| `ServerSongServiceTests.testLoadServerSongsHandlesCacheError` | Replace with `testLoadFailureIsVisible`. |
| `ServerSongServiceTests.testServiceRefreshCatalog` | Rewrite to `context.fetch(FetchDescriptor<ServerSong>())` after `await service.refreshCatalog()`, not a returned `loadServerSongs` array. |
| `ServerSongCatalogRefreshTests.testLoadServerSongsReconcilesDownloadStatus` | Rewrite to call result-less cache load, then fetch the persisted `ServerSong` and assert its stale flag was corrected. |

- [ ] **Step 1: Change the mock cache to a result-less throwing load API**

In `ServerSongServiceTests.swift`:

```swift
@MainActor
private final class MockServerSongCache: ServerSongCache {
    var loadError: Error?
    private(set) var loadCallCount = 0
    var refreshError: Error?
    private(set) var refreshCallCount = 0

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

- [ ] **Step 2: Add RED load/failure-state tests**

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

@Test("successful catalog load clears prior failure state")
func testSuccessfulLoadClearsFailure() async throws {
    struct LoadFailure: LocalizedError {
        var errorDescription: String? { "first failure" }
    }

    try await TestSetup.withTestSetup {
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
        #expect(cache.loadCallCount == 2)
    }
}
```

Update the existing refresh failure test to assert `catalogLoadFailed == true`; update successful refresh coverage to assert it is `false`.

- [ ] **Step 3: Rewrite the existing load/reconcile and service-refresh tests before changing signatures**

`ServerSongCatalogRefreshTests.testLoadServerSongsReconcilesDownloadStatus` becomes:

```swift
try await cache.loadServerSongs(modelContext: context)
let loaded = try #require(
    context.fetch(FetchDescriptor<ServerSong>())
        .first { $0.songId == "orphan" }
)
#expect(loaded.isDownloaded == false)
```

`ServerSongServiceTests.testServiceRefreshCatalog` should fetch directly from the context after refresh:

```swift
await service.refreshCatalog()
let songs = try context.fetch(FetchDescriptor<ServerSong>())
#expect(Set(songs.map(\.songId)) == ["x", "y"])
```

Rewrite `testLoadServerSongsWithoutModelContext` as:

```swift
let service = ServerSongService()
await service.loadServerSongs()
#expect(service.isLoading == false)
#expect(service.catalogLoadFailed == false)
#expect(service.errorMessage == nil)
```

Delete `testLoadServerSongsWithContextUsesCacheResult`; the new mock call-count/success tests cover delegation without reintroducing an array contract.

- [ ] **Step 4: Run service/catalog load tests and verify RED**

```bash
xcodebuild test \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'platform=macOS' \
  -only-testing:VirgoTests/ServerSongServiceTests \
  -only-testing:VirgoTests/ServerSongCatalogRefreshTests \
  -parallel-testing-enabled NO
```

Expected: FAIL until the result-less load API and `catalogLoadFailed` state exist.

- [ ] **Step 5: Make cache load propagate SwiftData fetch failure**

```swift
func loadServerSongs(modelContext: ModelContext) async throws {
    _ = try modelContext.fetch(FetchDescriptor<ServerSong>())
    await statusManager.refreshDownloadStatus(modelContext: modelContext)
}
```

Do not create a second in-memory catalog array.

- [ ] **Step 6: Implement minimal service state transitions**

Add:

```swift
@Published private(set) var catalogLoadFailed = false
```

Implement:

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

In `refreshCatalog()`, use `defer { isRefreshing = false }`, set `catalogLoadFailed = false` after a successful cache refresh, and set it to `true` in the existing catch block.

- [ ] **Step 7: Update `ContentView` to the result-less load**

Change:

```swift
_ = await serverSongService.loadServerSongs()
```

to:

```swift
await serverSongService.loadServerSongs()
```

No other startup changes belong to HPA-578.

- [ ] **Step 8: Require loading/failed/empty branching in both layouts**

In `ServerSongsView.serverList`, when `serverSongs.isEmpty`, the branch must be:

```swift
if serverSongService.isLoading || serverSongService.isRefreshing {
    loadingRow.listRowBackground(Color.clear)
} else if serverSongService.catalogLoadFailed {
    failedState.listRowBackground(Color.clear)
} else {
    emptyState.listRowBackground(Color.clear)
}
```

In `gridPlaceholder`, independently require the same state order:

```swift
if serverSongService.isLoading || serverSongService.isRefreshing {
    loadingRow
} else if serverSongService.catalogLoadFailed {
    failedState
} else {
    emptyState
}
```

Add:

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
            .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 40)
    .accessibilityIdentifier("serverSongsLoadErrorState")
}
```

Add `.accessibilityIdentifier("serverSongsLoadingState")` to `loadingRow` and `.accessibilityIdentifier("serverSongsEmptyState")` to `emptyState`.

Keep non-empty cached rows visible after failed refresh; the existing alert communicates the refresh failure while the previous valid snapshot remains usable.

- [ ] **Step 9: Run service and server-tab unit coverage and verify GREEN**

```bash
xcodebuild test \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'platform=macOS' \
  -only-testing:VirgoTests/ServerSongServiceTests \
  -only-testing:VirgoTests/ServerSongCatalogRefreshTests \
  -only-testing:VirgoTests/SongsTabCoverageTests \
  -parallel-testing-enabled NO
```

Expected: PASS.

- [ ] **Step 10: Commit the checkpoint**

```bash
git add Virgo/utilities/ServerSongCache.swift \
  Virgo/utilities/ServerSongService.swift \
  Virgo/views/ContentView.swift \
  Virgo/views/ServerSongsView.swift \
  VirgoTests/ServerSongServiceTests.swift \
  VirgoTests/ServerSongCatalogRefreshTests.swift
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

- [ ] **Build the iPad simulator target**

```bash
xcodebuild -project Virgo.xcodeproj -scheme Virgo \
  -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M4)' build
```

Expected: BUILD SUCCEEDED. Do not use an iPhone destination.

- [ ] **Run lint and diff checks**

```bash
swiftlint lint
git diff --check main...HEAD
```

Expected: no SwiftLint errors and no whitespace errors.

- [ ] **Run the broad residual compatibility audit**

```bash
rg -n \
  'backfillLegacyChartURLs|matchingDtxFile|pruneCachedSong|Please refresh the catalog first|Legacy compatibility for single-file DTX' \
  Virgo VirgoTests CLAUDE.md
```

Expected: no matches.

```bash
rg -n \
  'matchesSongIdentity|matchesServerSongByServerSongId|matchedLocalSongs|byTitleArtist|serverSongId == nil|titleArtistPredicate|noServerIdPredicate' \
  Virgo/utilities/ServerSongStatusManager.swift \
  Virgo/utilities/ServerSongDownloader.swift
```

Expected: no matches.

```bash
rg -n 'testDownloadAndImportSongRejectsLegacyEmptyChartURL|testRejectsImportWhenLegacySongMatches|testNoPruneOnTruncatedWalk|testDuplicateDTOsDontCrash|testCrossPageDuplicatesDoNotMarkCompleteEarly' \
  VirgoTests
```

Expected: no matches; the old-contract tests were deleted/replaced at their owning checkpoints.

```bash
rg -n 'refreshCatalog\(|loadServerSongs\(|applyDownloadStatus\(' Virgo VirgoTests
```

Expected: only current service/cache/status paths and focused tests.

- [ ] **Review the final production diff for scope**

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

Confirm the diff contains no sync framework, no local-song migration/pruning during catalog refresh, no title/artist server identity fallback, no off-main performance work, and no unrelated HPA-583 cleanup.
