# HPA-578 Complete Catalog Snapshot Refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Virgo's additive server catalog refresh with one validated complete snapshot replacement that preserves local songs, derives cache status by exact server ID, and is safe when downloads span cache refreshes.

**Architecture:** `ServerSongCache` remains the GraphQL-to-SwiftData cache owner and `ServerSongService` remains the screen facade. Fetch/validate all DTOs before mutation, map a full replacement, project local download state by `serverSongId`, replace only cache rows, and save once. `ServerSong` references are treated as ephemeral across awaits: download completion never writes the captured cache object and instead asks `ServerSongStatusManager` to reconcile whichever row currently owns the stable ID.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, Swift Testing, Apollo-backed `SimfileFetching`, Xcode/xcodebuild.

## Global Constraints

- Current development representation only; old cache rows may be reset/reloaded.
- Manual refresh only. No background sync, retry queue, ETag, sync token, merge policy, repository/use-case layer, staging database, generation model, or transaction coordinator.
- Validate the complete DTO snapshot before any context mutation.
- Successful replacement performs exactly one cache save; rollback on save failure.
- Catalog refresh may delete only `ServerSong` / `ServerChart` cache metadata. Never delete/rewrite local `Song`, `Chart`, `Note`, `ScoreRecord`, or audio because a server ID vanished.
- `Song.serverSongId` is the only current server identity contract.
- Never mutate a `ServerSong` model after a long await unless it has been re-resolved. HPA-578 uses status reconciliation rather than re-fetch for download completion.
- Do not move parsing/file work off-main; HPA-579/HPA-580 own that decision.
- Do not change server BGM format behavior; HPA-85 remains separate.
- Do not add catalog sorting in this ticket. The existing sorted cache-load array is discarded and does not order the live `@Query` today.
- macOS 14+ and iPadOS remain supported; no iPhone targeting.

---

## File Structure

**Production:**

- `Virgo/utilities/ServerSongStatusManager.swift` — exact-ID status projection/deletion; remove fallback graph and stale catalog pruning.
- `Virgo/utilities/ServerSongCache.swift` — complete snapshot validation and one-save replacement; remove obsolete load API.
- `Virgo/utilities/ServerSongDownloader.swift` — exact-ID-only duplicate detection.
- `Virgo/utilities/ServerSongService.swift` — reference-safe download completion, void startup reconciliation, refresh-failure state.
- `Virgo/models/DrumTrack.swift` — remove legacy single-file `ServerSong` initializer.
- `Virgo/views/ContentView.swift` — call result-less startup reconciliation.
- `Virgo/views/ServerSongsView.swift` — one shared loading/failed/empty placeholder.
- `CLAUDE.md` — current cache ownership guidance.

**Focused tests:**

- `VirgoTests/ServerSongStatusManagerTests.swift`
- `VirgoTests/ServerSongStatusDeletionStoreTests.swift`
- `VirgoTests/ServerSongCatalogRefreshTests.swift`
- `VirgoTests/ServerSongCacheCoverageTests.swift`
- `VirgoTests/ServerSongServiceTests.swift`
- `VirgoTests/ServerSongDownloaderTests.swift`
- `VirgoTests/ServerSongModelTests.swift`
- `VirgoTests/SongsTabCoverageTests.swift` for the view surface

No new production file/model is required.

---

## Task 1: Make status exact-ID-only and stop post-await cache authoring

**Files:**
- Modify: `Virgo/utilities/ServerSongStatusManager.swift`
- Modify: `Virgo/utilities/ServerSongService.swift`
- Modify: `VirgoTests/ServerSongStatusManagerTests.swift`
- Modify: `VirgoTests/ServerSongCatalogRefreshTests.swift`
- Modify: `VirgoTests/ServerSongServiceTests.swift`

**Produces:**

```swift
@MainActor
@discardableResult
func applyDownloadStatus(
    to serverSongs: [ServerSong],
    from localSongs: [Song]
) -> Bool
```

and:

```swift
private static func hasOtherImportedSong(
    serverSongId: String,
    excludingSongId: PersistentIdentifier,
    context: ModelContext
) throws -> Bool
```

### 1A. Migrate shared fixtures before changing identity semantics

- [ ] **Step 1: Make current server matches carry current IDs**

In `ServerSongCatalogRefreshTests.swift`:

- `testAdditiveAndPrune`: matching local row gets `serverSongId: "a"`.
- `testBackfillLegacyChartURLs`: matching local row gets `serverSongId: "a"`.

In `ServerSongStatusManagerTests.swift`:

- `setupGroupedSongs`: both imported rows get `serverSongId: "song-group"`.
- `testRefreshDownloadStatusUpdatesFlags`: matching local row gets the matching server ID.
- Any other fixture intended as a current server match gets an exact ID. Nil-ID rows remain only in tests explicitly proving they do not match.

`ServerSongCacheCoverageTests` has no local `Song` matching fixture today, so no identity fixture migration is required there.

- [ ] **Step 2: Verify fixture-only changes remain green**

```bash
xcodebuild test \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'platform=macOS' \
  -only-testing:VirgoTests/ServerSongStatusManagerTests \
  -only-testing:VirgoTests/ServerSongStatusDeletionStoreTests \
  -only-testing:VirgoTests/ServerSongCatalogRefreshTests \
  -only-testing:VirgoTests/ServerSongCacheCoverageTests \
  -only-testing:VirgoTests/ServerSongServiceTests \
  -parallel-testing-enabled NO
```

Expected: PASS.

### 1B. Pin exact-ID status/deletion behavior

- [ ] **Step 3: Add RED status/deletion regressions**

Add:

```swift
@Test("applyDownloadStatus matches only current serverSongId")
func testApplyDownloadStatusUsesOnlyServerSongId() async throws {
    try await TestSetup.withTestSetup {
        let manager = ServerSongStatusManager()
        let current = ServerSong(songId: "current", title: "Same", artist: "Artist", bpm: 120)
        let titleOnly = ServerSong(
            songId: "other",
            title: "Legacy",
            artist: "Artist",
            bpm: 120,
            isDownloaded: true,
            bgmDownloaded: true,
            previewDownloaded: true
        )
        let exact = Song(
            title: "Renamed",
            artist: "Different",
            bpm: 120,
            duration: "3:00",
            genre: "DTX Import",
            isServerImported: true,
            serverSongId: "current",
            bgmFilePath: "/tmp/current.ogg",
            previewFilePath: "/tmp/current.mp3"
        )
        let nilID = Song(
            title: "Legacy",
            artist: "Artist",
            bpm: 120,
            duration: "3:00",
            genre: "DTX Import",
            isServerImported: true,
            serverSongId: nil,
            bgmFilePath: "/tmp/legacy.ogg",
            previewFilePath: "/tmp/legacy.mp3"
        )

        let changed = manager.applyDownloadStatus(to: [current, titleOnly], from: [exact, nilID])

        #expect(changed)
        #expect(current.isDownloaded)
        #expect(current.bgmDownloaded)
        #expect(current.previewDownloaded)
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
        let cached = ServerSong(
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
        context.insert(cached)
        context.insert(titleOnly)
        try context.save()

        #expect(await manager.deleteDownloadedSong(cached, modelContext: context))
        TestAssertions.assertNotDeleted(titleOnly, in: context)
    }
}

@Test("deleteLocalSong with no serverSongId does not mutate same-title cache flags")
func testDeleteLocalSongWithoutServerIDSkipsCacheFallback() async throws {
    try await TestSetup.withTestSetup {
        let context = TestContainer.shared.context
        let container = TestContainer.shared.container
        let manager = ServerSongStatusManager()
        let cached = ServerSong(
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
        context.insert(cached)
        context.insert(local)
        try context.save()

        #expect(await manager.deleteLocalSong(local, container: container))

        let verification = ModelContext(container)
        let remaining = try #require(
            verification.fetch(FetchDescriptor<ServerSong>())
                .first { $0.songId == "server-id" }
        )
        #expect(remaining.isDownloaded)
        #expect(remaining.bgmDownloaded)
        #expect(remaining.previewDownloaded)
    }
}
```

Expected RED: the projector does not exist and nil-ID title/artist fallbacks still affect status/deletion.

- [ ] **Step 4: Extract the reusable status projector**

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

Refactor `refreshDownloadStatus(modelContext:)` to fetch local/cache rows, call this method, and save only if it returns `true`. Retain existing rollback/logging.

- [ ] **Step 5: Collapse user-initiated deletion to exact IDs**

Use:

```swift
let songsToDelete = allSongs.filter { song in
    song.isServerImported && song.serverSongId == serverSong.songId
}
```

`deleteLocalSong` stops capturing title/artist for identity. If the deleted song has no `serverSongId`, skip server-cache mutation. Otherwise use:

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

When no imported row remains, clear flags only on fetched cache rows whose `songId` equals that exact ID.

Delete now-obsolete fallback graph:

- `matchedLocalSongs`
- instance/static `matchesSongIdentity`
- instance/static `matchesServerSongByServerSongId`
- instance/static `checkForOtherMatchingSongs`
- `byTitleArtist`
- title/artist parameters/captures used only for cache identity

**Keep `matchesServerSong` temporarily.** `pruneCachedSong -> isAlreadyDownloaded -> matchesServerSong` still needs it until Task 2 deletes pruning.

### 1C. Pin the await-boundary ownership rule

- [ ] **Step 6: Replace the direct-write success test with a RED no-direct-authoring contract**

Keep `MockServerSongStatusManager.refreshDownloadStatusCalled` as a no-op observer and add/replace the service success test with:

```swift
@Test("download success delegates cache status without direct cache write")
func testDownloadSuccessDoesNotAuthorCapturedServerSong() async throws {
    try await TestSetup.withTestSetup {
        let context = TestContainer.shared.context
        let downloader = MockServerSongDownloader()
        downloader.result = (true, nil)
        let statusManager = MockServerSongStatusManager()
        var serviceSaveHookCalls = 0

        let service = ServerSongService(
            downloader: downloader,
            statusManager: statusManager,
            saveModelContext: { context in
                serviceSaveHookCalls += 1
                try context.save()
            }
        )
        service.setModelContext(context)

        let serverSong = ServerSong(
            songId: "download-ok",
            title: "OK",
            artist: "Artist",
            bpm: 120
        )
        context.insert(serverSong)
        try context.save()

        #expect(await service.downloadAndImportSong(serverSong))

        #expect(serverSong.isDownloaded == false)
        #expect(serviceSaveHookCalls == 0)
        #expect(statusManager.refreshDownloadStatusCalled)
        #expect(downloader.receivedSongIDs == ["download-ok"])
    }
}
```

This is intentionally not a destructive SwiftData race test. The mock status manager does not mutate the row, so the assertion deterministically proves the service itself no longer writes the captured cache model after the downloader await. Current code fails because it sets `serverSong.isDownloaded = true` and invokes the service save hook.

Delete `testDownloadAndImportSongSuccessWhenStatusSaveThrows`; it exists only for the direct service-owned save that is being removed.

- [ ] **Step 7: Remove post-await direct cache authoring from `ServerSongService`**

Delete from the success path:

```swift
serverSong.isDownloaded = true
try saveModelContext(modelContext)
```

Keep only:

```swift
if success {
    await refreshDownloadStatus()
}
```

Remove the stored property:

```swift
private let saveModelContext: (ModelContext) throws -> Void
```

Keep the initializer parameter `saveModelContext`; it still configures the default `ServerSongStatusManager` and `ServerSongCache`.

Because `ServerSongDownloader` snapshots `ServerSongSnapshot` before its long awaits, this leaves no `ServerSong` model access after the download await. A later Task 2 full-row replacement therefore cannot invalidate an object the completion path still writes.

`deleteDownloadedSong` is deliberately unchanged for reference lifetime: `ServerSongStatusManager.deleteDownloadedSong` is `@MainActor` and contains no suspension point, so refresh cannot interleave once that method begins. Revisit only if an `await` is added later.

- [ ] **Step 8: Audit Task 1 fallback removal**

```bash
rg -n \
  'matchedLocalSongs|matchesSongIdentity|matchesServerSongByServerSongId|checkForOtherMatchingSongs|byTitleArtist|songTitle|songArtist' \
  Virgo/utilities/ServerSongStatusManager.swift
```

Expected: no identity-fallback matches.

Do not include `matchesServerSong` yet; Task 2 removes its final prune caller.

- [ ] **Step 9: Run shared affected suites GREEN**

Run the command from Step 2.

Expected: PASS.

- [ ] **Step 10: Commit**

```bash
git add Virgo/utilities/ServerSongStatusManager.swift \
  Virgo/utilities/ServerSongService.swift \
  VirgoTests/ServerSongStatusManagerTests.swift \
  VirgoTests/ServerSongCatalogRefreshTests.swift \
  VirgoTests/ServerSongServiceTests.swift
git commit -m "refactor: make server catalog state ID-derived"
```

---

## Task 2: Validate and replace the complete cache snapshot

**Files:**
- Modify: `Virgo/utilities/ServerSongCache.swift`
- Modify: `Virgo/utilities/ServerSongStatusManager.swift`
- Modify: `VirgoTests/ServerSongCatalogRefreshTests.swift`
- Modify: `VirgoTests/ServerSongCacheCoverageTests.swift`
- Modify: `CLAUDE.md`

**Produces:**

```swift
enum ServerSongCatalogRefreshError: LocalizedError, Equatable {
    case totalCountChanged(expected: Int, actual: Int)
    case incompleteSnapshot(expected: Int, actual: Int)
    case unexpectedSnapshotCount(expected: Int, actual: Int)
    case duplicateSongID(String)
}
```

and private `fetchCompleteSnapshot(maxPages:)`.

### Task 2 old-test migration

| Existing test | Action |
|---|---|
| `testInsertsNew` | Keep. |
| `testAdditiveAndPrune` | Replace with full replacement: changed metadata overwritten, stale cache ID removed, local `Song` preserved. |
| `testNoPruneOnTruncatedWalk` | Replace with throwing/non-destructive truncated-walk test. |
| `testBackfillLegacyChartURLs` | Delete. |
| `testBackfillLegacyChartEncoding` | Delete. |
| `testNoBackfillWhenFileURLPresent` | Delete. |
| `testBackfillAndPruneSameRefresh` | Delete. |
| `testRefreshCatalogThrowsOnFetchError` | Strengthen with old-cache preservation assertion. |
| `testRefreshCatalogRollsBackOnSaveFailure` | Strengthen with old-cache restoration assertion. |
| `testDuplicateDTOsDontCrash` | Replace with duplicate rejection. |
| `testDuplicateDTOsBackfillSafe` | Delete. |
| `testCrossPageDuplicatesDoNotMarkCompleteEarly` | Replace with duplicate rejection. |
| `testLoadServerSongsReconcilesDownloadStatus` | Leave for Task 4, which removes the obsolete cache-load API. |

In `ServerSongCacheCoverageTests`, retain current-data coverage such as `testLevelScaleWarning`; delete all backfill/duplicate-recovery-only cases and `DuplicateBackfillFetcher`.

- [ ] **Step 1: Add RED complete replacement test**

Seed old cache `a`, stale cache `z`, and a local server-imported `Song(serverSongId: "a")`. Refresh with changed DTO `a` and new DTO `b`.

Assert:

```swift
let rows = try context.fetch(FetchDescriptor<ServerSong>())
let byID = Dictionary(uniqueKeysWithValues: rows.map { ($0.songId, $0) })
#expect(Set(byID.keys) == ["a", "b"])
#expect(byID["a"]?.title == "NEW")
#expect(byID["a"]?.bpm == 150)
#expect(byID["a"]?.charts.first?.fileURL == "https://r2/a/new-bas.dtx")
#expect(byID["a"]?.isDownloaded == true)
#expect(byID["a"]?.bgmDownloaded == true)
#expect(byID["a"]?.previewDownloaded == true)

let local = try #require(
    context.fetch(FetchDescriptor<Song>())
        .first { $0.serverSongId == "a" }
)
#expect(local.title == "Local A")
#expect(local.bgmFilePath == "/tmp/a.ogg")
#expect(local.previewFilePath == "/tmp/a.mp3")
```

Current additive behavior fails the metadata replacement assertion.

- [ ] **Step 2: Add deterministic invalid-snapshot fetchers**

Keep `TruncatingFetcher`. Add one duplicate-ID fetcher and one changing-`totalCount` fetcher. Their first pages must make the invalid condition deterministic; do not build generic mock infrastructure.

- [ ] **Step 3: Add RED non-destructive failure coverage**

For each failure, seed and save `ServerSong(songId: "old", title: "OLD", ...)` first, then assert the old cache is still the only persisted row after failure.

Cover:

- truncated empty page before expected count;
- duplicate ID;
- changing `totalCount`;
- network error (propagates original error);
- save failure + rollback;
- valid empty snapshot clears only server cache and preserves local `Song`.

- [ ] **Step 4: Add RED one-save/no-post-reconcile test**

Use a `RecordingStatusManager` override for `refreshDownloadStatus` and an injected cache save counter:

```swift
try await cache.refreshCatalog(modelContext: context)
#expect(cacheSaveCount == 1)
#expect(statusManager.refreshDownloadStatusCallCount == 0)
let row = try #require(context.fetch(FetchDescriptor<ServerSong>()).first)
#expect(row.isDownloaded)
```

Current code fails because it performs post-save reconciliation.

- [ ] **Step 5: Run cache/status/service suites RED**

```bash
xcodebuild test \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'platform=macOS' \
  -only-testing:VirgoTests/ServerSongStatusManagerTests \
  -only-testing:VirgoTests/ServerSongStatusDeletionStoreTests \
  -only-testing:VirgoTests/ServerSongCatalogRefreshTests \
  -only-testing:VirgoTests/ServerSongCacheCoverageTests \
  -only-testing:VirgoTests/ServerSongServiceTests \
  -parallel-testing-enabled NO
```

Expected: replacement/validation/one-save tests fail against additive refresh.

- [ ] **Step 6: Implement catalog refresh errors**

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

- [ ] **Step 7: Replace `fetchAllPages` with complete validation**

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

- [ ] **Step 8: Replace cache rows in one save**

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

    for row in existingCache { modelContext.delete(row) }
    for row in replacement {
        modelContext.insert(row)
        for chart in row.charts { modelContext.insert(chart) }
    }

    do {
        try saveContext(modelContext)
    } catch {
        modelContext.rollback()
        throw error
    }
}
```

Delete URL backfill, additive insertion, incomplete partial insertion, duplicate recovery, stale prune calls, and post-save status refresh.

- [ ] **Step 9: Delete stale-prune and dead helpers**

Delete unconditionally:

- `pruneCachedSong`
- `hasBGMFile` (already dead)
- `hasPreviewFile` (already dead)

Then delete after their final prune caller disappears:

- `isAlreadyDownloaded`
- `matchesServerSong`

Do not replace stale pruning with another local cleanup path.

- [ ] **Step 10: Apply the Task 2 test migration table**

Delete/rewrite the exact tests listed above. Do not leave old additive/backfill/duplicate-tolerance assertions for final verification to discover.

- [ ] **Step 11: Update `CLAUDE.md`**

State that manual refresh validates a complete GraphQL snapshot, projects status by exact `Song.serverSongId`, replaces cache metadata in one save, and never prunes local songs/audio because a catalog ID disappears. Also state that download completion reconciles status rather than directly mutating a retained cache object.

- [ ] **Step 12: Run shared suites GREEN**

Run the command from Step 5.

Expected: PASS.

- [ ] **Step 13: Audit prune dependencies**

```bash
rg -n \
  'pruneCachedSong|isAlreadyDownloaded|hasBGMFile|hasPreviewFile|matchesServerSong\(' \
  Virgo/utilities/ServerSongStatusManager.swift
```

Expected: no matches.

- [ ] **Step 14: Commit**

```bash
git add Virgo/utilities/ServerSongCache.swift \
  Virgo/utilities/ServerSongStatusManager.swift \
  VirgoTests/ServerSongCatalogRefreshTests.swift \
  VirgoTests/ServerSongCacheCoverageTests.swift \
  CLAUDE.md
git commit -m "refactor: replace server catalog from complete snapshot"
```

---

## Task 3: Delete remaining catalog compatibility

**Files:**
- Modify: `Virgo/utilities/ServerSongDownloader.swift`
- Modify: `Virgo/utilities/ServerSongService.swift`
- Modify: `Virgo/models/DrumTrack.swift`
- Modify: `VirgoTests/ServerSongDownloaderTests.swift`
- Modify: `VirgoTests/ServerSongServiceTests.swift`
- Modify: `VirgoTests/ServerSongModelTests.swift`

- [ ] **Step 1: Replace downloader fallback tests with RED current-policy coverage**

Delete:

- `testRejectsImportWhenLegacySongMatchesTitleArtist`
- `testRejectsImportWhenLegacySongMatchesCaseInsensitive`

Add one test proving a same-title/artist local row with nil `serverSongId` does not block import of `current-server-id`.

Expected RED: current `songAlreadyExists` returns “Song already exists in database.”

- [ ] **Step 2: Reduce `songAlreadyExists` to exact ID query**

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

Keep tests proving same ID rejects and distinct IDs with identical title/artist are allowed.

- [ ] **Step 3: Delete service empty-URL compatibility guard/test**

Remove the block producing:

```text
Please refresh the catalog first — this entry needs updated chart URLs
```

Delete `ServerSongServiceTests.testDownloadAndImportSongRejectsLegacyEmptyChartURL`.

Keep downloader empty-URL coverage; current invalid URLs still fail through `ServerSongImportError`.

- [ ] **Step 4: Delete legacy single-file model initializer/tests**

Delete `ServerSong(filename:title:artist:bpm:difficultyLevel:size:isDownloaded:)`.

Delete:

- `ServerSongModelTests.testServerSongLegacyInitializer`
- `ServerSongModelTests.testServerSongIDExtraction`

- [ ] **Step 5: Run all server-management suites**

```bash
xcodebuild test \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'platform=macOS' \
  -only-testing:VirgoTests/ServerSongStatusManagerTests \
  -only-testing:VirgoTests/ServerSongStatusDeletionStoreTests \
  -only-testing:VirgoTests/ServerSongCatalogRefreshTests \
  -only-testing:VirgoTests/ServerSongCacheCoverageTests \
  -only-testing:VirgoTests/ServerSongServiceTests \
  -only-testing:VirgoTests/ServerSongDownloaderTests \
  -only-testing:VirgoTests/ServerSongModelTests \
  -parallel-testing-enabled NO
```

Expected: PASS.

- [ ] **Step 6: Audit compatibility identity**

```bash
rg -n \
  'backfillLegacyChartURLs|matchingDtxFile|pruneCachedSong|Please refresh the catalog first|Legacy compatibility for single-file DTX' \
  Virgo VirgoTests CLAUDE.md
```

Expected: no matches.

```bash
rg -n \
  'matchedLocalSongs|matchesSongIdentity|matchesServerSongByServerSongId|byTitleArtist|titleArtistPredicate|noServerIdPredicate' \
  Virgo/utilities/ServerSongStatusManager.swift \
  Virgo/utilities/ServerSongDownloader.swift
```

Expected: no matches.

- [ ] **Step 7: Commit**

```bash
git add Virgo/utilities/ServerSongDownloader.swift \
  Virgo/utilities/ServerSongService.swift \
  Virgo/models/DrumTrack.swift \
  VirgoTests/ServerSongDownloaderTests.swift \
  VirgoTests/ServerSongServiceTests.swift \
  VirgoTests/ServerSongModelTests.swift
git commit -m "refactor: remove legacy server catalog compatibility"
```

---

## Task 4: Remove fake cache loading and share refresh-failure presentation

**Files:**
- Modify: `Virgo/utilities/ServerSongCache.swift`
- Modify: `Virgo/utilities/ServerSongService.swift`
- Modify: `Virgo/views/ContentView.swift`
- Modify: `Virgo/views/ServerSongsView.swift`
- Modify: `VirgoTests/ServerSongCatalogRefreshTests.swift`
- Modify: `VirgoTests/ServerSongServiceTests.swift`
- Verify: `VirgoTests/SongsTabCoverageTests.swift`

**Interfaces:**
- Removes `ServerSongCache.loadServerSongs`.
- Changes service load to `func loadServerSongs() async` with no result and no throwing path.
- Adds `@Published private(set) var catalogRefreshFailed = false`.
- Adds one shared `serverSongsPlaceholder` property.

### Task 4 old-test migration

| Existing test | Action |
|---|---|
| `ServerSongCatalogRefreshTests.testLoadServerSongsReconcilesDownloadStatus` | Delete; status-manager suites own reconciliation. |
| `ServerSongServiceTests.testLoadServerSongsWithoutModelContext` | Rewrite for void no-op API. |
| `testLoadServerSongsWithContextUsesCacheResult` | Replace with status-reconciliation delegation test. |
| `testLoadServerSongsHandlesCacheError` | Delete; no cache load/fetch-probe error path remains. |
| `testServiceRefreshCatalog` | Assert persisted IDs with `context.fetch`, not load return value. |
| `testRefreshCatalogCallsCache` | Keep and assert `catalogRefreshFailed == false`. |
| `testRefreshCatalogFailureSetsError` | Keep and assert `catalogRefreshFailed == true`. |

- [ ] **Step 1: Rewrite service load tests before API change**

Use the existing `MockServerSongStatusManager`:

```swift
@Test("loadServerSongs reconciles status without owning catalog rows")
func testLoadServerSongsReconcilesStatus() async throws {
    try await TestSetup.withTestSetup {
        let status = MockServerSongStatusManager()
        let service = ServerSongService(statusManager: status)
        service.setModelContext(TestContainer.shared.context)

        await service.loadServerSongs()

        #expect(status.refreshDownloadStatusCalled)
        #expect(service.isLoading == false)
    }
}

@Test("loadServerSongs without model context is a no-op")
func testLoadServerSongsWithoutModelContext() async {
    let status = MockServerSongStatusManager()
    let service = ServerSongService(statusManager: status)

    await service.loadServerSongs()

    #expect(status.refreshDownloadStatusCalled == false)
    #expect(service.isLoading == false)
}
```

Delete mock cache load result/error plumbing.

- [ ] **Step 2: Delete `ServerSongCache.loadServerSongs`**

`@Query` already owns live catalog rows. Delete the cache method and `ServerSongCatalogRefreshTests.testLoadServerSongsReconcilesDownloadStatus`.

- [ ] **Step 3: Make service startup reconciliation void/non-throwing**

```swift
func loadServerSongs() async {
    guard modelContext != nil else { return }
    isLoading = true
    defer { isLoading = false }
    await refreshDownloadStatus()
}
```

Do not add a SwiftData probe fetch or initial-load failure channel.

- [ ] **Step 4: Make manual refresh own the failure flag**

Add:

```swift
@Published private(set) var catalogRefreshFailed = false
```

Refactor:

```swift
func refreshCatalog() async {
    guard let modelContext else { return }

    isRefreshing = true
    errorMessage = nil
    defer { isRefreshing = false }

    do {
        try await cache.refreshCatalog(modelContext: modelContext)
        catalogRefreshFailed = false
    } catch {
        catalogRefreshFailed = true
        errorMessage = AlertMessage(
            "Failed to refresh server songs: \(error.localizedDescription)"
        )
        Logger.error("Failed to refresh catalog: \(error)")
    }
}
```

- [ ] **Step 5: Update `ContentView` and refresh tests**

Change:

```swift
_ = await serverSongService.loadServerSongs()
```

to:

```swift
await serverSongService.loadServerSongs()
```

`testServiceRefreshCatalog` verifies:

```swift
await service.refreshCatalog()
let songs = try context.fetch(FetchDescriptor<ServerSong>())
#expect(Set(songs.map(\.songId)) == ["x", "y"])
```

Successful refresh tests assert `catalogRefreshFailed == false`; failure tests assert `true`.

- [ ] **Step 6: Share one list/grid placeholder branch**

Add:

```swift
@ViewBuilder
private var serverSongsPlaceholder: some View {
    if serverSongService.isLoading || serverSongService.isRefreshing {
        loadingRow
    } else if serverSongService.catalogRefreshFailed {
        failedState
    } else {
        emptyState
    }
}
```

`serverList` uses it once:

```swift
if !serverSongs.isEmpty {
    ForEach(serverSongs, id: \.songId) { serverSong in
        // existing row content
    }
} else {
    serverSongsPlaceholder
        .listRowBackground(Color.clear)
}
```

`gridPlaceholder` simply returns `serverSongsPlaceholder`.

Use:

- `serverSongsLoadingState`
- `serverSongsRefreshErrorState`
- `serverSongsEmptyState`

as accessibility identifiers on the three concrete states.

`failedState` copy:

```swift
private var failedState: some View {
    VStack(spacing: 16) {
        Image(systemName: "exclamationmark.icloud")
            .font(.system(size: 50))
            .foregroundColor(theme.secondary)
        Text("Couldn’t refresh server songs")
            .font(.title2)
            .foregroundColor(theme.primary)
        Text("Tap refresh to try again")
            .font(.body)
            .foregroundColor(theme.secondary)
            .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 40)
    .accessibilityIdentifier("serverSongsRefreshErrorState")
}
```

Non-empty cached rows remain visible after a failed refresh; the existing alert communicates the error.

- [ ] **Step 7: Run service/view coverage**

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

- [ ] **Step 8: Run all server-management suites**

```bash
xcodebuild test \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'platform=macOS' \
  -only-testing:VirgoTests/ServerSongStatusManagerTests \
  -only-testing:VirgoTests/ServerSongStatusDeletionStoreTests \
  -only-testing:VirgoTests/ServerSongCatalogRefreshTests \
  -only-testing:VirgoTests/ServerSongCacheCoverageTests \
  -only-testing:VirgoTests/ServerSongServiceTests \
  -only-testing:VirgoTests/ServerSongDownloaderTests \
  -only-testing:VirgoTests/ServerSongModelTests \
  -parallel-testing-enabled NO
```

Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add Virgo/utilities/ServerSongCache.swift \
  Virgo/utilities/ServerSongService.swift \
  Virgo/views/ContentView.swift \
  Virgo/views/ServerSongsView.swift \
  VirgoTests/ServerSongCatalogRefreshTests.swift \
  VirgoTests/ServerSongServiceTests.swift
git commit -m "fix: simplify server catalog refresh state"
```

---

## Final Verification

- [ ] **Run all focused suites**

```bash
xcodebuild test \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'platform=macOS' \
  -only-testing:VirgoTests/ServerSongStatusManagerTests \
  -only-testing:VirgoTests/ServerSongStatusDeletionStoreTests \
  -only-testing:VirgoTests/ServerSongCatalogRefreshTests \
  -only-testing:VirgoTests/ServerSongCacheCoverageTests \
  -only-testing:VirgoTests/ServerSongServiceTests \
  -only-testing:VirgoTests/ServerSongDownloaderTests \
  -only-testing:VirgoTests/ServerSongModelTests \
  -only-testing:VirgoTests/SongsTabCoverageTests \
  -parallel-testing-enabled NO
```

Expected: PASS.

- [ ] **Run complete macOS unit suite**

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

- [ ] **Build iPad simulator compatibility**

```bash
xcodebuild -project Virgo.xcodeproj -scheme Virgo \
  -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M4)' build
```

Expected: BUILD SUCCEEDED.

- [ ] **Run lint/diff checks**

```bash
swiftlint lint
git diff --check main...HEAD
```

Expected: no SwiftLint errors and no whitespace errors.

- [ ] **Residual compatibility audit**

```bash
rg -n \
  'backfillLegacyChartURLs|matchingDtxFile|pruneCachedSong|Please refresh the catalog first|Legacy compatibility for single-file DTX' \
  Virgo VirgoTests CLAUDE.md
```

Expected: no matches.

```bash
rg -n \
  'matchedLocalSongs|matchesSongIdentity|matchesServerSongByServerSongId|byTitleArtist|titleArtistPredicate|noServerIdPredicate' \
  Virgo/utilities/ServerSongStatusManager.swift \
  Virgo/utilities/ServerSongDownloader.swift
```

Expected: no matches.

```bash
rg -n 'serverSong\.isDownloaded\s*=\s*true|loadServerSongs\(modelContext:' \
  Virgo/utilities/ServerSongService.swift \
  Virgo/utilities/ServerSongCache.swift
```

Expected: no matches. Download flags are projected and cache no longer owns a load API.

- [ ] **Review production diff for scope**

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

Confirm:

- no local song/audio pruning from catalog refresh;
- no `ServerSong` cache-object mutation after the download await;
- no title/artist server identity fallback;
- no sync/repository/staging infrastructure;
- no initial-load error probe/state machine;
- no unrelated catalog sorting change;
- no HPA-579/HPA-580 performance work.
