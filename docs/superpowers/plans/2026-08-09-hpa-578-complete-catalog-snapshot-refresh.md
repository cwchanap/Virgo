# HPA-578 Complete Catalog Snapshot Refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Virgo's additive/compatibility-heavy server catalog refresh with one validated complete snapshot replacement that preserves local songs, uses exact server IDs for derived download state, and remains safe when a refresh occurs during an in-flight download.

**Architecture:** Keep `ServerSongService` as the screen facade and `ServerSongCache` as the GraphQL-to-SwiftData cache owner. Fetch/validate all DTOs before mutation, map a complete replacement, project local download state by exact `serverSongId`, and save once. Treat `ServerSong` references as ephemeral across awaits: download completion never directly mutates the captured cache model and instead reconciles whichever current cache row owns the imported song ID.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, Swift Testing, Apollo-backed `SimfileFetching`, Xcode/xcodebuild.

## Global Constraints

- Support the current development data format only; old cache representations may be reset/reloaded.
- Catalog refresh remains manual.
- Do not add sync tokens, ETags, merge policies, retry queues, repository/use-case layers, staging databases, generation models, or transaction coordinators.
- Fetch and validate the complete DTO snapshot before any `ModelContext.insert` or `ModelContext.delete`.
- A successful replacement performs one context mutation phase and exactly one cache save; roll back on save failure.
- Catalog refresh may delete only `ServerSong` / `ServerChart` cache metadata. It must not delete/rewrite local `Song`, `Chart`, `Note`, `ScoreRecord`, or audio files.
- `Song.serverSongId` is the only current server identity contract. Do not preserve title/artist fallback matching.
- Never mutate a `ServerSong` reference after a long `await` unless it has been re-resolved; HPA-578 chooses reconciliation instead of re-fetch for download completion.
- Keep `ServerSongService` as the screen-facing facade.
- Do not move parsing/file work off-main; HPA-579/HPA-580 own that decision.
- Do not change BGM format behavior; HPA-85 remains separate.
- Do not add catalog sorting in this ticket. The existing sorted array returned by cache load is discarded and does not currently order the live `@Query`.
- macOS 14+ and iPadOS remain supported; no iPhone targeting.

---

## File Structure

**Production files modified:**

- `Virgo/utilities/ServerSongStatusManager.swift` — exact-ID status projection/deletion; remove fallback graph and stale catalog pruning.
- `Virgo/utilities/ServerSongCache.swift` — complete snapshot validation and one-save replacement; remove cache load API.
- `Virgo/utilities/ServerSongDownloader.swift` — exact-ID-only duplicate detection.
- `Virgo/utilities/ServerSongService.swift` — reference-safe download completion, result-less startup reconciliation, refresh-failure flag.
- `Virgo/models/DrumTrack.swift` — remove legacy single-file `ServerSong` initializer.
- `Virgo/views/ContentView.swift` — call result-less startup reconciliation.
- `Virgo/views/ServerSongsView.swift` — one shared loading/failed/empty placeholder.
- `CLAUDE.md` — current snapshot/cache ownership guidance.

**Focused tests modified:**

- `VirgoTests/ServerSongStatusManagerTests.swift`
- `VirgoTests/ServerSongStatusDeletionStoreTests.swift`
- `VirgoTests/ServerSongCatalogRefreshTests.swift`
- `VirgoTests/ServerSongCacheCoverageTests.swift`
- `VirgoTests/ServerSongServiceTests.swift`
- `VirgoTests/ServerSongDownloaderTests.swift`
- `VirgoTests/ServerSongModelTests.swift`
- existing `SongsTabCoverageTests` for the shared placeholder compile/render surface

No new production file/model is required.

---

## Task 1: Establish exact-ID projection and make download completion reference-safe

**Files:**
- Modify: `Virgo/utilities/ServerSongStatusManager.swift`
- Modify: `Virgo/utilities/ServerSongService.swift`
- Modify: `VirgoTests/ServerSongStatusManagerTests.swift`
- Modify: `VirgoTests/ServerSongCatalogRefreshTests.swift`
- Modify: `VirgoTests/ServerSongServiceTests.swift`

**Interfaces:**
- Produces:
  ```swift
  @MainActor
  @discardableResult
  func applyDownloadStatus(
      to serverSongs: [ServerSong],
      from localSongs: [Song]
  ) -> Bool
  ```
- Produces:
  ```swift
  private static func hasOtherImportedSong(
      serverSongId: String,
      excludingSongId: PersistentIdentifier,
      context: ModelContext
  ) throws -> Bool
  ```
- Keeps `refreshDownloadStatus(modelContext:)` as the persisted wrapper.
- Changes successful `ServerSongService.downloadAndImportSong` completion to call status reconciliation only; it no longer authors/saves `serverSong.isDownloaded` directly.

### Task 1 test migration — do this before production semantics change

- [ ] **Step 1: Make existing cross-suite server-match fixtures explicit IDs**

In `ServerSongCatalogRefreshTests.swift`:

- `testAdditiveAndPrune`: change the local matching row to include `serverSongId: "a"`.
- `testBackfillLegacyChartURLs`: change the local matching row to include `serverSongId: "a"`.

In `ServerSongStatusManagerTests.swift`:

- `setupGroupedSongs`: both server-imported rows use `serverSongId: "song-group"`.
- `testRefreshDownloadStatusUpdatesFlags`: matching local row uses the exact matching server ID.
- Any other fixture intended to represent a current server import must carry the expected `serverSongId`; a nil-ID row may remain only when the test explicitly proves nil-ID rows do **not** match.

`ServerSongCacheCoverageTests` currently has no local `Song` fixture used for download-status matching, so no ID fixture migration is needed there.

- [ ] **Step 2: Run the affected suites before behavior changes**

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

Expected: PASS. This proves the fixture migration itself did not change current behavior.

- [ ] **Step 3: Add RED exact-ID status/deletion regressions**

Add to `ServerSongStatusManagerTests.swift`:

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

Expected RED: `applyDownloadStatus` does not exist and current nil-ID title/artist fallback affects deletion/status paths.

- [ ] **Step 4: Extract `applyDownloadStatus` and make persisted refresh delegate to it**

Add:

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

Refactor `refreshDownloadStatus(modelContext:)` to fetch local/cache rows, call this method, and save only when it returns `true`. Keep existing rollback/logging around the save.

- [ ] **Step 5: Collapse user-initiated deletion to exact IDs**

Use:

```swift
let songsToDelete = allSongs.filter { song in
    song.isServerImported && song.serverSongId == serverSong.songId
}
```

In `deleteLocalSong`, stop capturing title/artist for cache identity. If `song.serverSongId` is nil, delete the local row normally but do not mutate any server cache flags.

Use one remaining-row helper:

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

When no other imported row remains for the ID, fetch current `ServerSong` rows and clear flags only on rows whose `songId == serverSongId`.

Delete now-obsolete title/artist reconciliation helpers:

- `matchedLocalSongs`
- instance/static `matchesSongIdentity`
- instance/static `matchesServerSongByServerSongId`
- instance/static `checkForOtherMatchingSongs`
- `byTitleArtist` dictionary
- title/artist parameters/captures used only for identity

**Do not delete `matchesServerSong` yet.** `pruneCachedSong -> isAlreadyDownloaded -> matchesServerSong` still uses it until Task 2 removes pruning.

- [ ] **Step 6: Add a RED download-completion reference-lifetime regression**

Extend the test `MockServerSongDownloader` with a callback and yield:

```swift
var beforeReturn: (@MainActor (ServerSong, ModelContainer) -> Void)?

@MainActor
override func downloadAndImportSong(
    _ serverSong: ServerSong,
    container: ModelContainer
) async -> (Bool, String?) {
    receivedSongIDs.append(serverSong.songId)
    await Task.yield()
    beforeReturn?(serverSong, container)
    return result
}
```

Add this service regression:

```swift
@Test("download completion reconciles the replacement cache row after suspension")
func testDownloadCompletionUsesCurrentCacheRow() async throws {
    try await TestSetup.withTestSetup {
        let context = TestContainer.shared.context
        let downloader = MockServerSongDownloader()
        downloader.result = (true, nil)
        var serviceSaveHookCalls = 0

        let statusManager = ServerSongStatusManager()
        let service = ServerSongService(
            downloader: downloader,
            statusManager: statusManager,
            saveModelContext: { context in
                serviceSaveHookCalls += 1
                try context.save()
            }
        )
        service.setModelContext(context)

        let original = ServerSong(
            songId: "race-id",
            title: "Race",
            artist: "Artist",
            bpm: 120
        )
        context.insert(original)
        try context.save()

        downloader.beforeReturn = { captured, _ in
            let local = Song(
                title: "Race",
                artist: "Artist",
                bpm: 120,
                duration: "3:00",
                genre: "DTX Import",
                isServerImported: true,
                serverSongId: "race-id"
            )
            context.insert(local)
            context.delete(captured)
            context.insert(ServerSong(
                songId: "race-id",
                title: "Race Updated",
                artist: "Artist",
                bpm: 130
            ))
            try? context.save()
        }

        #expect(await service.downloadAndImportSong(original))

        let current = try #require(
            context.fetch(FetchDescriptor<ServerSong>())
                .first { $0.songId == "race-id" }
        )
        #expect(current.title == "Race Updated")
        #expect(current.isDownloaded)
        #expect(serviceSaveHookCalls == 0)
    }
}
```

Against current code, the service save hook is invoked after the await because it still directly writes/saves the captured `serverSong`.

- [ ] **Step 7: Remove direct post-await cache authoring from `ServerSongService`**

Delete from the success path:

```swift
serverSong.isDownloaded = true
try saveModelContext(modelContext)
```

The success path becomes:

```swift
if success {
    await refreshDownloadStatus()
}
```

Remove the stored property:

```swift
private let saveModelContext: (ModelContext) throws -> Void
```

Keep the initializer parameter `saveModelContext`; it still configures the default `ServerSongStatusManager` and `ServerSongCache` dependencies.

Update service tests:

- `testDownloadAndImportSongSuccessRefreshesStatus`: stop asserting that the service directly sets the passed `serverSong.isDownloaded`; assert success, cleared tracking state, and `refreshDownloadStatusCalled`.
- Delete `testDownloadAndImportSongSuccessWhenStatusSaveThrows`; its only contract is the service-owned direct save that is being removed.
- Keep downloader failure, already-downloaded, already-downloading, and missing-context coverage.

- [ ] **Step 8: Checkpoint matcher audit**

```bash
rg -n \
  'matchedLocalSongs|matchesSongIdentity|matchesServerSongByServerSongId|checkForOtherMatchingSongs|byTitleArtist|songTitle|songArtist' \
  Virgo/utilities/ServerSongStatusManager.swift
```

Expected: no identity-fallback matches.

Do **not** include `matchesServerSong` in this Task 1 audit; Task 2 removes its final prune caller.

- [ ] **Step 9: Run the shared affected suites and verify GREEN**

Run the command from Step 2.

Expected: PASS, including the new reference-lifetime regression.

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

## Task 2: Replace the catalog from one validated complete snapshot

**Files:**
- Modify: `Virgo/utilities/ServerSongCache.swift`
- Modify: `Virgo/utilities/ServerSongStatusManager.swift`
- Modify: `VirgoTests/ServerSongCatalogRefreshTests.swift`
- Modify: `VirgoTests/ServerSongCacheCoverageTests.swift`
- Modify: `CLAUDE.md`

**Interfaces:**
- Consumes `SimfileFetching.fetchSimfiles`, `SimfileMapper.makeServerSong`, and Task 1's `applyDownloadStatus`.
- Produces:
  ```swift
  enum ServerSongCatalogRefreshError: LocalizedError, Equatable
  ```
- Produces a private throwing `fetchCompleteSnapshot(maxPages:)`.

### Task 2 existing-test migration

Apply these exact ownership changes in `ServerSongCatalogRefreshTests.swift`:

| Existing test | Action in Task 2 |
|---|---|
| `testInsertsNew` | Keep; it remains valid complete-snapshot insertion coverage. |
| `testAdditiveAndPrune` | Replace with complete replacement: changed metadata is overwritten, stale cache ID removed, matching local `Song` preserved. |
| `testNoPruneOnTruncatedWalk` | Replace with a throwing/non-destructive truncated-walk test. No partial insertion. |
| `testBackfillLegacyChartURLs` | Delete; current snapshot mapping replaces legacy backfill. |
| `testBackfillLegacyChartEncoding` | Delete. |
| `testNoBackfillWhenFileURLPresent` | Delete. |
| `testBackfillAndPruneSameRefresh` | Delete. |
| `testRefreshCatalogThrowsOnFetchError` | Strengthen by seeding old cache and asserting it remains unchanged. |
| `testRefreshCatalogRollsBackOnSaveFailure` | Strengthen by seeding old cache and asserting rollback restores it. |
| `testDuplicateDTOsDontCrash` | Replace with duplicate-ID rejection. |
| `testDuplicateDTOsBackfillSafe` | Delete. |
| `testCrossPageDuplicatesDoNotMarkCompleteEarly` | Replace with duplicate-ID rejection; duplicates are no longer tolerated. |
| `testLoadServerSongsReconcilesDownloadStatus` | Leave for Task 4, where the obsolete cache-load API is deleted. |

In `ServerSongCacheCoverageTests.swift`, keep only `testLevelScaleWarning`; delete all backfill/duplicate-recovery-only cases and the `DuplicateBackfillFetcher`.

- [ ] **Step 1: Add/replace RED complete-replacement coverage**

Use a test that seeds:

- old cache `a` with stale metadata;
- stale cache `z`;
- local `Song(serverSongId: "a")` with BGM/preview paths;
- DTO snapshot containing changed `a` and new `b`.

After refresh assert:

```swift
let cacheRows = try context.fetch(FetchDescriptor<ServerSong>())
let byID = Dictionary(uniqueKeysWithValues: cacheRows.map { ($0.songId, $0) })
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

Current additive behavior must fail the changed-metadata assertion.

- [ ] **Step 2: Add deterministic invalid-snapshot fetchers**

Keep `TruncatingFetcher`. Add:

```swift
private final class DuplicateIdFetcher: SimfileFetching, @unchecked Sendable {
    func fetchSimfiles(page: Int, pageSize: Int, search: String?) async throws -> SimfilePage {
        if page == 1 {
            return SimfilePage(simfiles: [.stub(id: "dup"), .stub(id: "dup")], totalCount: 2)
        }
        return SimfilePage(simfiles: [], totalCount: 2)
    }

    func fetchSimfile(id: String) async throws -> SimfileDTO? { nil }
}

private final class ChangingTotalCountFetcher: SimfileFetching, @unchecked Sendable {
    func fetchSimfiles(page: Int, pageSize: Int, search: String?) async throws -> SimfilePage {
        switch page {
        case 1: return SimfilePage(simfiles: [.stub(id: "a")], totalCount: 2)
        case 2: return SimfilePage(simfiles: [.stub(id: "b")], totalCount: 3)
        default: return SimfilePage(simfiles: [], totalCount: 3)
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

- [ ] **Step 3: Add RED non-destructive failure tests**

For each test, seed `ServerSong(songId: "old", title: "OLD", ...)` and save it before calling refresh:

```swift
await #expect(throws: ServerSongCatalogRefreshError.self) {
    try await cache.refreshCatalog(modelContext: context)
}
let rows = try context.fetch(FetchDescriptor<ServerSong>())
#expect(rows.map(\.songId) == ["old"])
#expect(rows.first?.title == "OLD")
```

Cover separately:

- truncated empty page before count is satisfied;
- duplicate ID;
- changing `totalCount`;
- network fetch error (expect original `URLError` rather than catalog error);
- save failure + rollback;
- valid empty snapshot clears only `ServerSong` cache while preserving local `Song`.

- [ ] **Step 4: Add RED one-save/no-post-reconcile coverage**

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

        var saveCount = 0
        let status = RecordingStatusManager()
        let cache = ServerSongCache(
            fetcher: MockSimfileFetcher(all: [.stub(id: "a")]),
            statusManager: status,
            pageSize: 10,
            saveContext: { context in
                saveCount += 1
                try context.save()
            }
        )

        try await cache.refreshCatalog(modelContext: context)

        #expect(saveCount == 1)
        #expect(status.refreshDownloadStatusCallCount == 0)
        let row = try #require(context.fetch(FetchDescriptor<ServerSong>()).first)
        #expect(row.isDownloaded)
        #expect(row.bgmDownloaded)
    }
}
```

- [ ] **Step 5: Run cache/status/service shared suites and verify RED**

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

- [ ] **Step 6: Add explicit refresh errors**

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

Duplicate IDs fail before count mismatch. Zero rows with expected count zero are valid.

- [ ] **Step 8: Replace cache rows in one mutation/save phase**

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

    for row in existingCache {
        modelContext.delete(row)
    }
    for row in replacement {
        modelContext.insert(row)
        for chart in row.charts {
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

Delete URL backfill, additive insertion, incomplete partial insertion, duplicate recovery, stale prune calls, and post-save status refresh.

- [ ] **Step 9: Delete stale-prune and now-dead status helpers**

Delete unconditionally from `ServerSongStatusManager.swift`:

- `pruneCachedSong`
- `hasBGMFile` (already dead today)
- `hasPreviewFile` (already dead today)

Then delete after their final prune caller disappears:

- `isAlreadyDownloaded`
- `matchesServerSong`

Do not replace them with another stale-catalog cleanup path.

- [ ] **Step 10: Delete compatibility-only cache tests**

Apply the Task 2 migration table above. `ServerSongCacheCoverageTests` should retain only current-data coverage such as level-scale warning.

- [ ] **Step 11: Update live guidance**

In `CLAUDE.md`, replace additive-cache guidance with:

```markdown
- `ServerSongCache`: SwiftData-backed replaceable catalog metadata. Manual refresh validates a complete GraphQL DTO snapshot, projects local download state by exact `Song.serverSongId`, then replaces `ServerSong` / `ServerChart` rows in one save. Catalog removal never deletes local imported songs or audio.
```

Also state that download completion reconciles status by stable ID rather than directly mutating a retained cache object.

- [ ] **Step 12: Run shared suites and verify GREEN**

Run the command from Step 5.

Expected: PASS.

- [ ] **Step 13: Audit the stale-prune/matcher checkpoint**

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

## Task 3: Delete remaining server-catalog compatibility surfaces

**Files:**
- Modify: `Virgo/utilities/ServerSongDownloader.swift`
- Modify: `Virgo/utilities/ServerSongService.swift`
- Modify: `Virgo/models/DrumTrack.swift`
- Modify: `VirgoTests/ServerSongDownloaderTests.swift`
- Modify: `VirgoTests/ServerSongServiceTests.swift`
- Modify: `VirgoTests/ServerSongModelTests.swift`

**Interfaces:**
- Duplicate detection becomes exact `serverSongId` only.
- Removes legacy empty-URL repair prompt and single-file model initializer.

- [ ] **Step 1: Replace legacy downloader fallback tests with current-policy RED coverage**

Delete:

- `testRejectsImportWhenLegacySongMatchesTitleArtist`
- `testRejectsImportWhenLegacySongMatchesCaseInsensitive`

Add:

```swift
@Test("downloadAndImportSong ignores same-title local rows without current server ID")
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

Current code fails because title/artist fallback reports “Song already exists in database.”

- [ ] **Step 2: Reduce `songAlreadyExists` to one targeted ID query**

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

Keep current tests proving same ID rejects and distinct IDs with identical title/artist remain allowed.

- [ ] **Step 3: Delete the service's legacy empty-URL guard and owning test**

Remove the `ServerSongService.downloadAndImportSong` block that produces:

```text
Please refresh the catalog first — this entry needs updated chart URLs
```

Delete `ServerSongServiceTests.testDownloadAndImportSongRejectsLegacyEmptyChartURL`.

Keep the downloader's existing empty-URL error coverage; invalid current URLs still fail through `ServerSongImportError`.

- [ ] **Step 4: Delete the legacy single-file model initializer/tests**

Delete `ServerSong(filename:title:artist:bpm:difficultyLevel:size:isDownloaded:)` from `DrumTrack.swift`.

Delete from `ServerSongModelTests.swift`:

- `testServerSongLegacyInitializer`
- `testServerSongIDExtraction`

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

- [ ] **Step 6: Audit all compatibility identity surfaces**

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

## Task 4: Simplify startup reconciliation and share refresh-failure presentation

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
- Changes service load to:
  ```swift
  func loadServerSongs() async
  ```
  with no return value and no throwing path.
- Adds:
  ```swift
  @Published private(set) var catalogRefreshFailed = false
  ```
- Adds one shared `serverSongsPlaceholder` view property.

### Task 4 test migration

| Existing test | Action |
|---|---|
| `ServerSongCatalogRefreshTests.testLoadServerSongsReconcilesDownloadStatus` | Delete; cache no longer owns load/reconciliation. Status-manager suites own projection behavior. |
| `ServerSongServiceTests.testLoadServerSongsWithoutModelContext` | Rewrite for void API: call method, assert loading ends and no status refresh occurs. |
| `testLoadServerSongsWithContextUsesCacheResult` | Replace with service startup reconciliation delegation using `MockServerSongStatusManager.refreshDownloadStatusCalled`. |
| `testLoadServerSongsHandlesCacheError` | Delete; startup load is intentionally non-throwing and no cache fetch probe remains. |
| `testServiceRefreshCatalog` | After refresh, assert IDs with `context.fetch(FetchDescriptor<ServerSong>())`; do not call load for an array. |
| `testRefreshCatalogCallsCache` | Keep and add `catalogRefreshFailed == false`. |
| `testRefreshCatalogFailureSetsError` | Keep and add `catalogRefreshFailed == true`. |

- [ ] **Step 1: Remove load behavior from `MockServerSongCache` and add RED service-state tests**

Delete `loadResult` and the `loadServerSongs` override from `MockServerSongCache`.

Use the existing `MockServerSongStatusManager` to test startup reconciliation:

```swift
@Test("loadServerSongs reconciles status without owning a catalog array")
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
```

Update the missing-context test:

```swift
@Test("loadServerSongs without model context is a no-op")
func testLoadServerSongsWithoutModelContext() async {
    let status = MockServerSongStatusManager()
    let service = ServerSongService(statusManager: status)

    await service.loadServerSongs()

    #expect(status.refreshDownloadStatusCalled == false)
    #expect(service.isLoading == false)
}
```

Update refresh tests to assert the new flag:

```swift
#expect(service.catalogRefreshFailed == false) // successful refresh
#expect(service.catalogRefreshFailed)          // failed refresh
```

- [ ] **Step 2: Delete `ServerSongCache.loadServerSongs`**

Remove the cache method completely. `@Query` is the catalog row source; `ServerSongStatusManager` owns reconciliation.

Delete `ServerSongCatalogRefreshTests.testLoadServerSongsReconcilesDownloadStatus` with it.

- [ ] **Step 3: Make service load void/non-throwing and refresh own failure state**

Implement:

```swift
func loadServerSongs() async {
    guard modelContext != nil else { return }
    isLoading = true
    defer { isLoading = false }
    await refreshDownloadStatus()
}
```

Add:

```swift
@Published private(set) var catalogRefreshFailed = false
```

Refactor refresh:

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

Do not add an initial-load error flag or SwiftData probe fetch.

- [ ] **Step 4: Update `ContentView` and refresh service test**

Change:

```swift
_ = await serverSongService.loadServerSongs()
```

to:

```swift
await serverSongService.loadServerSongs()
```

In `testServiceRefreshCatalog`, verify the live persisted source:

```swift
await service.refreshCatalog()
let songs = try context.fetch(FetchDescriptor<ServerSong>())
#expect(Set(songs.map(\.songId)) == ["x", "y"])
```

- [ ] **Step 5: Share one placeholder branch between list and grid**

In `ServerSongsView`, use one property:

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

List:

```swift
if !serverSongs.isEmpty {
    ForEach(serverSongs, id: \.songId) { serverSong in
        // existing row
    }
} else {
    serverSongsPlaceholder
        .listRowBackground(Color.clear)
}
```

Grid:

```swift
@ViewBuilder
private var gridPlaceholder: some View {
    serverSongsPlaceholder
}
```

Add/keep these identifiers:

```swift
.accessibilityIdentifier("serverSongsLoadingState")
.accessibilityIdentifier("serverSongsLoadErrorState")
.accessibilityIdentifier("serverSongsEmptyState")
```

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
    .accessibilityIdentifier("serverSongsLoadErrorState")
}
```

Keep non-empty cached rows visible after a failed refresh; the existing alert communicates the failure while the previous snapshot remains usable.

- [ ] **Step 6: Run service/view coverage**

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

- [ ] **Step 7: Run all server-management suites again**

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

- [ ] **Step 8: Commit**

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

- [ ] **Run all HPA-578/server-management focused suites**

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

- [ ] **Run the complete macOS unit suite**

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

Expected: BUILD SUCCEEDED. Do not use an iPhone destination.

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

Expected: no matches. Download flags are status-projected, and cache no longer owns a load API.

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
- no cache-object mutation after the download await;
- no title/artist server identity fallback;
- no sync/repository/staging infrastructure;
- no initial-load error probe/state machine;
- no unrelated catalog sorting change;
- no HPA-579/HPA-580 performance work.
