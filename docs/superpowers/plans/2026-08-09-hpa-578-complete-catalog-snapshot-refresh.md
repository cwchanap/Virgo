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

---

## File Structure

**Production files modified:**

- `Virgo/utilities/ServerSongStatusManager.swift` — stable-ID-only download-state projection and deletion/status matching.
- `Virgo/utilities/ServerSongCache.swift` — complete page validation, one-save cache replacement, and throwing cache-load access.
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
- Produces stable-ID-only matching semantics used by Task 2.

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

Expected: FAIL because `applyDownloadStatus(to:from:)` does not exist and current deletion still accepts a title/artist fallback for nil-ID rows.

- [ ] **Step 3: Add the minimal reusable status projection**

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

- [ ] **Step 4: Remove title/artist identity from status/deletion paths**

Change `deleteDownloadedSong` selection to:

```swift
let songsToDelete = allSongs.filter { song in
    song.isServerImported && song.serverSongId == serverSong.songId
}
```

Change the detached local-delete flow to pass only `songServerSongId` and the deleted `PersistentIdentifier` into its cache-status update helper. Use this exact remaining-row predicate:

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

When `songServerSongId == nil`, skip server-cache flag mutation and continue deleting the local row normally.

Remove the title/artist lookup dictionary from `refreshDownloadStatus` and delete fallback helpers once their callers are gone. Keep `pruneCachedSong` compiling at this checkpoint; Task 2 removes its final caller and then deletes it.

Update every `isServerImported: true` fixture in `ServerSongStatusManagerTests.swift` that represents a current server match so it carries the expected stable ID. In particular, update `setupGroupedSongs` so both imported rows use `serverSongId: "song-group"`; keep the non-imported row without a server ID.

- [ ] **Step 5: Run status tests and verify GREEN**

Run the command from Step 2.

Expected: PASS. Exact IDs drive status/deletion; title/artist-only rows do not.

- [ ] **Step 6: Commit the checkpoint**

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
- Produces a throwing private `fetchCompleteSnapshot(maxPages:)` and a one-save `refreshCatalog(modelContext:)`.

- [ ] **Step 1: Replace additive behavior with a RED complete-replacement regression**

Replace the current additive/prune expectation in `ServerSongCatalogRefreshTests.swift` with:

```swift
@Test("Complete refresh replaces cache metadata and preserves local songs")
func testCompleteRefreshReplacesCacheOnly() async throws {
    try await TestSetup.withTestSetup {
        let context = TestContainer.shared.context
        let oldChart = ServerChart(
            difficulty: "easy",
            difficultyLabel: "BASIC",
            level: 10,
            filename: "old.dtx",
            size: 10,
            fileURL: "https://old.example/old.dtx",
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

        let dtoA = SimfileDTO(
            id: "a",
            title: "NEW",
            artist: "NEW ARTIST",
            bpm: 150,
            genre: "Rock",
            tags: [],
            durationSeconds: 222,
            updatedAt: "2026-08-09T12:00:00Z",
            dtxFiles: [
                DtxFileDTO(
                    label: "BASIC",
                    level: 44,
                    fileURL: "https://r2/a/new-bas.dtx",
                    fileSizeBytes: 444,
                    encoding: .utf8
                )
            ],
            fileKeys: ["a/bgm.ogg", "a/preview.mp3"]
        )
        let cache = ServerSongCache(
            fetcher: MockSimfileFetcher(all: [dtoA, .stub(id: "b")]),
            pageSize: 10
        )

        try await cache.refreshCatalog(modelContext: context)

        let cacheRows = try context.fetch(FetchDescriptor<ServerSong>())
        let byID = Dictionary(uniqueKeysWithValues: cacheRows.map { ($0.songId, $0) })
        #expect(Set(byID.keys) == ["a", "b"])
        #expect(byID["a"]?.title == "NEW")
        #expect(byID["a"]?.artist == "NEW ARTIST")
        #expect(byID["a"]?.bpm == 150)
        #expect(byID["a"]?.durationSeconds == 222)
        #expect(byID["a"]?.hasBGM == true)
        #expect(byID["a"]?.hasPreview == true)
        #expect(byID["a"]?.charts.count == 1)
        #expect(byID["a"]?.charts.first?.level == 44)
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
    }
}
```

- [ ] **Step 2: Add exact invalid-snapshot fetchers for the test suite**

Keep the existing `TruncatingFetcher`, and add these suite-local fetchers:

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

- [ ] **Step 3: Add RED non-destructive validation tests**

Add these complete tests:

```swift
@Test("Truncated page walk throws and leaves previous cache untouched")
func testTruncatedWalkIsNonDestructive() async throws {
    try await TestSetup.withTestSetup {
        let context = TestContainer.shared.context
        context.insert(ServerSong(songId: "old", title: "OLD", artist: "A", bpm: 120))
        try context.save()

        let fetcher = TruncatingFetcher(
            all: [.stub(id: "a"), .stub(id: "b")],
            pageSize: 1
        )
        let cache = ServerSongCache(fetcher: fetcher, pageSize: 1)

        await #expect(throws: ServerSongCatalogRefreshError.self) {
            try await cache.refreshCatalog(modelContext: context)
        }

        let rows = try context.fetch(FetchDescriptor<ServerSong>())
        #expect(rows.map(\.songId) == ["old"])
        #expect(rows.first?.title == "OLD")
    }
}

@Test("Duplicate server IDs reject the whole snapshot")
func testDuplicateIDsRejectSnapshot() async throws {
    try await TestSetup.withTestSetup {
        let context = TestContainer.shared.context
        context.insert(ServerSong(songId: "old", title: "OLD", artist: "A", bpm: 120))
        try context.save()

        let cache = ServerSongCache(fetcher: DuplicateIdFetcher(), pageSize: 10)

        await #expect(throws: ServerSongCatalogRefreshError.self) {
            try await cache.refreshCatalog(modelContext: context)
        }

        let rows = try context.fetch(FetchDescriptor<ServerSong>())
        #expect(rows.map(\.songId) == ["old"])
    }
}

@Test("Changing totalCount rejects the whole snapshot")
func testChangingTotalCountRejectsSnapshot() async throws {
    try await TestSetup.withTestSetup {
        let context = TestContainer.shared.context
        context.insert(ServerSong(songId: "old", title: "OLD", artist: "A", bpm: 120))
        try context.save()

        let cache = ServerSongCache(fetcher: ChangingTotalCountFetcher(), pageSize: 1)

        await #expect(throws: ServerSongCatalogRefreshError.self) {
            try await cache.refreshCatalog(modelContext: context)
        }

        let rows = try context.fetch(FetchDescriptor<ServerSong>())
        #expect(rows.map(\.songId) == ["old"])
    }
}

@Test("Fetch failure leaves previous cache untouched")
func testFetchFailureIsNonDestructive() async throws {
    try await TestSetup.withTestSetup {
        let context = TestContainer.shared.context
        context.insert(ServerSong(songId: "old", title: "OLD", artist: "A", bpm: 120))
        try context.save()

        let fetcher = MockSimfileFetcher(all: [.stub(id: "new")])
        fetcher.error = URLError(.notConnectedToInternet)
        let cache = ServerSongCache(fetcher: fetcher, pageSize: 10)

        await #expect(throws: URLError.self) {
            try await cache.refreshCatalog(modelContext: context)
        }

        let rows = try context.fetch(FetchDescriptor<ServerSong>())
        #expect(rows.map(\.songId) == ["old"])
        #expect(rows.first?.title == "OLD")
    }
}

@Test("Valid empty snapshot clears only server cache")
func testEmptySnapshotClearsOnlyServerCache() async throws {
    try await TestSetup.withTestSetup {
        let context = TestContainer.shared.context
        let old = ServerSong(songId: "old", title: "OLD", artist: "A", bpm: 120)
        let local = Song(
            title: "Local",
            artist: "Artist",
            bpm: 120,
            duration: "3:00",
            genre: "DTX Import",
            isServerImported: true,
            serverSongId: "old",
            bgmFilePath: "/tmp/local.ogg"
        )
        context.insert(old)
        context.insert(local)
        try context.save()

        let cache = ServerSongCache(fetcher: MockSimfileFetcher(all: []), pageSize: 10)
        try await cache.refreshCatalog(modelContext: context)

        #expect(try context.fetch(FetchDescriptor<ServerSong>()).isEmpty)
        let localRows = try context.fetch(FetchDescriptor<Song>())
        #expect(localRows.count == 1)
        #expect(localRows.first?.serverSongId == "old")
        #expect(localRows.first?.bgmFilePath == "/tmp/local.ogg")
    }
}
```

Strengthen the existing save-failure test by seeding `ServerSong(songId: "old", ...)` first, injecting a throwing cache save hook, and asserting after rollback that the only cache row is still `old`.

- [ ] **Step 4: Add a RED one-save/no-post-reconcile test**

Add:

```swift
@Test("Complete refresh saves once and does not run post-save status refresh")
func testCompleteRefreshUsesOneSave() async throws {
    try await TestSetup.withTestSetup {
        let context = TestContainer.shared.context
        let local = Song(
            title: "Local A",
            artist: "Artist",
            bpm: 120,
            duration: "3:00",
            genre: "DTX Import",
            isServerImported: true,
            serverSongId: "a",
            bgmFilePath: "/tmp/a.ogg"
        )
        context.insert(local)
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

Current code should fail because it calls `refreshDownloadStatus` after its cache save.

- [ ] **Step 5: Run catalog tests and verify RED**

```bash
xcodebuild test \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'platform=macOS' \
  -only-testing:VirgoTests/ServerSongCatalogRefreshTests \
  -parallel-testing-enabled NO
```

Expected: stale metadata remains stale, invalid snapshots are accepted/partially applied, and post-save reconciliation is still invoked.

- [ ] **Step 6: Add explicit refresh validation errors**

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

- [ ] **Step 7: Replace page walking with throwing complete-snapshot validation**

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

- [ ] **Step 9: Delete obsolete catalog-driven local pruning**

Now that `ServerSongCache` has no prune caller, delete `ServerSongStatusManager.pruneCachedSong` and helpers used only by that method. Do not replace it with another stale-ID cleanup path.

- [ ] **Step 10: Delete compatibility-only cache tests and keep current-data coverage**

Delete the tests that assert legacy empty-`fileURL` backfill, label/filename backfill matching, duplicate recovery, additive preservation of old metadata, or partial insertion from an incomplete page walk.

In `ServerSongCacheCoverageTests.swift`, keep `testLevelScaleWarning` and delete the backfill-only cases. Do not move unrelated suites.

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

### Task 3: Delete remaining server-catalog compatibility surfaces

**Files:**
- Modify: `Virgo/utilities/ServerSongDownloader.swift`
- Modify: `Virgo/utilities/ServerSongService.swift`
- Modify: `Virgo/models/DrumTrack.swift`
- Modify: `VirgoTests/ServerSongDownloaderTests.swift`
- Modify: `VirgoTests/ServerSongModelTests.swift`

**Interfaces:**
- Consumes: current `ServerSongSnapshot.songId` / `Song.serverSongId` identity.
- Produces: duplicate detection based solely on exact server ID.
- Removes: legacy single-file `ServerSong` initializer and the service's old-empty-URL repair prompt.

- [ ] **Step 1: Replace legacy downloader rejection tests with a RED current-policy test**

Delete `testRejectsImportWhenLegacySongMatchesTitleArtist` and `testRejectsImportWhenLegacySongMatchesCaseInsensitive` from `ServerSongDownloaderTests.swift`.

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

Current code should fail with `Song already exists in database`.

- [ ] **Step 2: Run downloader tests and verify RED**

```bash
xcodebuild test \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'platform=macOS' \
  -only-testing:VirgoTests/ServerSongDownloaderTests \
  -parallel-testing-enabled NO
```

Expected: the new same-title/nil-ID test FAILS.

- [ ] **Step 3: Reduce `songAlreadyExists` to one targeted stable-ID query**

Use:

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

Delete the exact title/artist fetch and case-insensitive nil-ID scan. Keep tests proving the same server ID is rejected and distinct server IDs with the same title/artist are allowed.

- [ ] **Step 4: Delete the old-empty-URL service guard**

Remove from `ServerSongService.downloadAndImportSong` the legacy block whose user-facing message is:

```text
Please refresh the catalog first — this entry needs updated chart URLs
```

Do not add a replacement guard. Current invalid URLs continue to fail through `ServerSongDownloader.processChart` / `ServerSongImportError`.

- [ ] **Step 5: Delete the legacy single-file `ServerSong` initializer and tests**

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

From `ServerSongModelTests.swift`, delete `testServerSongLegacyInitializer` and `testServerSongIDExtraction`. Retain current `songId:` initializer, media, BPM, genre, and duration coverage.

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

- [ ] **Step 7: Audit deleted compatibility symbols**

```bash
rg -n \
  'backfillLegacyChartURLs|matchingDtxFile|pruneCachedSong|Please refresh the catalog first|Legacy compatibility for single-file DTX' \
  Virgo VirgoTests CLAUDE.md
```

Expected: no matches.

```bash
rg -n 'serverSongId ==|serverSongId:' \
  Virgo/utilities/ServerSongDownloader.swift \
  Virgo/utilities/ServerSongStatusManager.swift
```

Expected: current stable-ID checks remain visible.

- [ ] **Step 8: Commit the checkpoint**

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
- Modify: `Virgo/utilities/ServerSongCache.swift`
- Modify: `Virgo/utilities/ServerSongService.swift`
- Modify: `Virgo/views/ContentView.swift`
- Modify: `Virgo/views/ServerSongsView.swift`
- Modify: `VirgoTests/ServerSongServiceTests.swift`

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

- [ ] **Step 1: Change the mock cache to a result-less throwing load API**

In `ServerSongServiceTests.swift`, replace the mock's array `loadResult` with:

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

Delete the test that asserts a cache-returned array is passed through. The live `@Query` is the catalog row source.

- [ ] **Step 2: Add RED load/failure-state tests**

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

Update the existing refresh failure test to assert `catalogLoadFailed == true`. Add the same assertion with `false` after the existing successful refresh test.

- [ ] **Step 3: Run service tests and verify RED**

```bash
xcodebuild test \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'platform=macOS' \
  -only-testing:VirgoTests/ServerSongServiceTests \
  -parallel-testing-enabled NO
```

Expected: FAIL because the result-less load API and `catalogLoadFailed` do not exist.

- [ ] **Step 4: Make cache load propagate SwiftData fetch failure**

Change `ServerSongCache.loadServerSongs` from returning `[ServerSong]` with `try?` fallback to:

```swift
func loadServerSongs(modelContext: ModelContext) async throws {
    _ = try modelContext.fetch(FetchDescriptor<ServerSong>())
    await statusManager.refreshDownloadStatus(modelContext: modelContext)
}
```

Do not create a second in-memory catalog array.

- [ ] **Step 5: Implement minimal service state transitions**

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

- [ ] **Step 6: Update `ContentView` to the result-less service load**

Change:

```swift
_ = await serverSongService.loadServerSongs()
```

to:

```swift
await serverSongService.loadServerSongs()
```

No other startup changes belong to HPA-578.

- [ ] **Step 7: Distinguish loading, failed, and valid-empty placeholders**

In both the list and grid empty paths in `ServerSongsView`, use:

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

Keep rendering non-empty cached rows after a failed refresh; the existing alert communicates that refresh failure while the previous valid snapshot remains usable.

- [ ] **Step 8: Run service and server-tab unit coverage and verify GREEN**

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

- [ ] **Step 9: Commit the checkpoint**

```bash
git add Virgo/utilities/ServerSongCache.swift \
  Virgo/utilities/ServerSongService.swift \
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

- [ ] **Run a residual compatibility audit**

```bash
rg -n \
  'backfillLegacyChartURLs|matchingDtxFile|pruneCachedSong|Please refresh the catalog first|Legacy compatibility for single-file DTX' \
  Virgo VirgoTests CLAUDE.md
```

Expected: no matches.

```bash
rg -n 'refreshCatalog\(|loadServerSongs\(|applyDownloadStatus\(' Virgo VirgoTests
```

Expected: only the current service/cache/status paths and focused tests.

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

Confirm the diff contains no sync framework, no local-song migration/pruning during catalog refresh, no off-main performance work, and no unrelated HPA-583 cleanup.
