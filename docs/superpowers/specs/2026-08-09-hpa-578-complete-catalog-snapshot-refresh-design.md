# HPA-578: Complete Catalog Snapshot Refresh

**Date:** 2026-08-09
**Status:** Draft design for review — planning only, implementation not started

## Context

HPA-578 is the remaining Phase A work in the Virgo runtime/performance roadmap after HPA-576 and HPA-577. It is unblocked and independent of the HPA-579 profiling gate, while HPA-580 and HPA-581 must not start until that profiling decision exists.

Virgo currently treats `ServerSong` / `ServerChart` as a partly persistent catalog and partly mutable sync state:

- `ServerSongCache.refreshCatalog` page-walks the backend, inserts only unseen IDs, backfills legacy chart URLs, prunes stale IDs, silently tolerates duplicate IDs, saves, then runs a second download-status reconciliation pass.
- Existing cache rows are deliberately preserved, so current server edits to title, artist, BPM, duration, chart level, URL, encoding, and media availability can remain stale indefinitely.
- An incomplete page walk can still partially insert fetched rows.
- `ServerSongStatusManager.pruneCachedSong` may delete a locally imported `Song` and its audio merely because the current server catalog no longer contains that ID.
- `ServerSongDownloader` and `ServerSongStatusManager` still fall back to title/artist matching for historical rows without `serverSongId`.
- `ServerSongCache.loadServerSongs` converts a SwiftData fetch failure into an empty list, and `ServerSongService.loadServerSongs` converts cache failure into another empty list, making failure indistinguishable from a valid empty cache.

HPA-577 established Virgo's current-format-only policy: old development representations may be reset rather than migrated. HPA-578 applies the same policy to the server catalog. The cache should represent one complete current server snapshot, and local imported songs should use `Song.serverSongId` as the only server identity.

## Decision summary

Treat the server catalog as replaceable metadata, not as a synchronized user-data store.

1. Fetch and validate one complete DTO snapshot before touching SwiftData.
2. Reject incomplete pagination, changing `totalCount`, count mismatches, or duplicate server IDs.
3. Build new `ServerSong` / `ServerChart` models from the validated DTOs using `SimfileMapper`.
4. Project current download/BGM/preview flags from local server-imported `Song` rows by `serverSongId` before insertion.
5. Delete the old catalog rows and insert the new snapshot in one `ModelContext` mutation phase, call `save()` exactly once, and roll back on save failure.
6. Never delete or rewrite local `Song`, `Chart`, `Note`, `ScoreRecord`, or audio files as part of catalog replacement.
7. Delete legacy catalog backfill, additive-upsert, title/artist fallback, and single-file compatibility paths instead of preserving them.
8. Use the existing `ServerSongService.isLoading`, plus one small failure flag, to distinguish empty/loading/failed catalog presentation. Do not introduce a catalog state framework.

## Approaches considered

### A. Keep additive refresh and patch more metadata fields

Update every field on matching IDs, preserve stale pruning, keep the legacy URL backfill, and add more duplicate/incomplete-page guards.

**Rejected.** This continues to make cache replacement behave like a synchronization engine. It also keeps two code paths for creating current metadata: fresh insertion and mutation/backfill of an old row. The cache contains no user-authored state worth preserving, so replacement is simpler and more correct.

### B. Validate a full snapshot, then replace the cache in one save

Fetch all plain DTOs first, validate them, map them to new models, restore only derived download flags by stable ID, and replace the old cache rows in one mutation/save phase.

**Selected.** This matches the data ownership model: server metadata is replaceable, local `Song` data is durable application data. It eliminates most compatibility code and gives failure a clear non-destructive boundary.

### C. Add a repository/sync coordinator, staging store, generation table, or two-phase swap

Introduce a new catalog repository and persistent generations so the app can stage a snapshot and atomically flip between versions.

**Rejected.** Virgo is pre-release and the catalog is a manual cache. A validated in-memory DTO snapshot plus one SwiftData save provides the required behavior without permanent synchronization infrastructure.

## Goals

1. Current server metadata fully replaces stale cached metadata after a successful manual refresh.
2. Any fetch, pagination, validation, or save failure leaves the previously persisted catalog intact.
3. Duplicate server IDs are treated as invalid input rather than deduplicated.
4. Download flags survive cache replacement by deriving them from current local songs with matching stable server IDs.
5. Local downloaded/imported songs and audio remain untouched when catalog entries disappear.
6. Initial cache-load failure is visibly different from a valid empty catalog.
7. Historical catalog compatibility code and tests are deleted rather than carried forward.

## Non-goals and ownership boundaries

- No automatic/background catalog refresh.
- No incremental sync token, ETag, merge policy, offline queue, or retry scheduler.
- No new repository/use-case layer around `ServerSongService`.
- No separate SwiftData container, staging table, generation model, or transaction coordinator.
- No change to Apollo/GraphQL schema or generated code.
- No change to locally imported song/chart/note/score persistence beyond identity matching in server-management code.
- No audio-format fix; HPA-85 owns server BGM playback format behavior.
- No off-main parsing or file-work change; HPA-579/HPA-580 own that decision.
- No broad test-suite/documentation consolidation; HPA-583 owns the final cleanup pass.
- No attempt to preserve old development cache rows that lack current IDs/URLs. Reset/reload is the supported path.

## Design

### 1. Fetch a complete plain-DTO snapshot before mutation

Keep network orchestration inside `ServerSongCache`; `SimfileFetching` remains the backend seam. Do not move this work to a new repository.

Replace the current `(simfiles, isComplete)` result with a throwing complete-snapshot helper:

```swift
enum ServerSongCatalogRefreshError: LocalizedError, Equatable {
    case totalCountChanged(expected: Int, actual: Int)
    case incompleteSnapshot(expected: Int, actual: Int)
    case unexpectedSnapshotCount(expected: Int, actual: Int)
    case duplicateSongID(String)
}
```

The exact error text should be user-readable because `ServerSongService` already surfaces refresh errors through `errorMessage`.

`fetchCompleteSnapshot(maxPages:)` follows these rules:

1. Fetch page 1 and capture its `totalCount` as the expected snapshot count.
2. Require every subsequent page to report the same `totalCount`. If it changes during the walk, fail and let the user refresh again.
3. A first page with `totalCount == 0` and zero rows is a valid empty snapshot.
4. Validate each received DTO ID as pages arrive. On the first repeated `dto.id`, throw `duplicateSongID` immediately; do not wait for count validation or silently deduplicate it.
5. Append only validated DTOs and use the accumulated raw DTO count as the pagination completion signal. Do not use unique-ID count to decide whether the walk is complete.
6. An empty page before the expected count is reached is `incompleteSnapshot`.
7. Hitting the existing defensive `maxPages` bound before reaching the expected count is `incompleteSnapshot`.
8. Require the accumulated DTO count never to exceed `totalCount`; an overfilled response is `unexpectedSnapshotCount`.
9. After the walk, require the accumulated DTO count to equal `totalCount` exactly.

Network errors from `SimfileFetching` propagate unchanged. All of this happens before any `ModelContext.insert` / `delete` call.

### 2. Reuse one small status projection, keyed only by `serverSongId`

`ServerSongStatusManager` already owns the meaning of the three cache status flags. Keep that ownership, but make the reusable core non-persisting:

```swift
@MainActor
@discardableResult
func applyDownloadStatus(
    to serverSongs: [ServerSong],
    from localSongs: [Song]
) -> Bool
```

The method:

- considers only local rows with `isServerImported == true` and non-nil `serverSongId`;
- groups them by exact `serverSongId`;
- sets `isDownloaded` when at least one local row exists for the ID;
- sets `bgmDownloaded` when any matching row has `bgmFilePath != nil`;
- sets `previewDownloaded` when any matching row has `previewFilePath != nil`;
- returns whether it changed any supplied `ServerSong` flag.

There is deliberately no title/artist dictionary and no normalization fallback.

`refreshDownloadStatus(modelContext:)` remains available for existing non-catalog callers. It fetches current local/cache rows, delegates to `applyDownloadStatus`, and saves only if values changed.

`ServerSongCache.refreshCatalog` uses `applyDownloadStatus` on the newly mapped, not-yet-saved cache models. This is the important part: status reconciliation becomes part of the catalog replacement's one save instead of a second post-save transaction.

### 3. Replace only cache rows in one mutation/save phase

After the DTO snapshot has been fetched and validated:

1. Fetch local `Song` rows needed for status projection.
2. Fetch the existing `ServerSong` cache rows.
3. Convert every DTO through `SimfileMapper.makeServerSong(from:)`.
4. Apply stable-ID download state to those new models.
5. Delete every existing `ServerSong`. Its cascade relationship owns `ServerChart` deletion.
6. Insert every new `ServerSong` and its mapped `ServerChart` rows.
7. Call the injected `saveContext` exactly once.
8. If save throws, call `modelContext.rollback()` and rethrow.

No local `Song` is deleted or modified in this path. No audio file is removed. A server ID disappearing from the catalog only means there is no current `ServerSong` cache row for it. If the ID appears in a later valid snapshot, status projection will mark it downloaded again from the still-present local `Song`.

Delete `ServerSongStatusManager.pruneCachedSong`; complete cache replacement no longer has a reason to call it.

The level-scale warning may remain because it validates current server data and does not preserve an old representation.

### 4. Delete catalog compatibility and fallback identity

#### `ServerSongCache`

Delete:

- `backfillLegacyChartURLs`;
- `matchingDtxFile`;
- additive existing-ID preservation;
- incomplete-walk partial insertion;
- duplicate-ID recovery/deduplication comments and behavior;
- post-save `refreshDownloadStatus` call.

A valid current snapshot always rebuilds charts from DTO `fileURL` / encoding through `SimfileMapper`.

#### `ServerSongDownloader`

`ServerSongDownloader.songAlreadyExists` keeps only the targeted `Song.serverSongId == snapshot.songId` check.

Delete both legacy fallbacks:

- exact title/artist match when `serverSongId == nil`;
- case-insensitive in-memory title/artist match.

A local/manual/historical row with the same title and artist but no matching current server ID does not block a server import.

#### `ServerSongStatusManager`

All server-status matching becomes exact stable-ID matching. Simplify:

- `deleteDownloadedSong` selects `isServerImported` rows whose `serverSongId == serverSong.songId`;
- `deleteLocalSong` updates cache flags only when the deleted local song has a `serverSongId`;
- remaining-row checks compare that exact ID only;
- remove title/artist fallback helpers and parameters.

Local deletion still deletes the selected local row and its owned audio using the existing file manager rules; this is user-initiated deletion, not catalog refresh.

#### `ServerSongService`

Delete the pre-download guard that rejects cached charts with an empty `fileURL` and tells the user to refresh. That guard exists only to support an old cache representation. Current invalid/missing URLs continue to fail through the normal downloader error path.

#### `ServerSong` model

Delete the `ServerSong(filename:title:artist:bpm:difficultyLevel:size:isDownloaded:)` single-file convenience initializer and its compatibility-only model tests. Current catalog construction uses the `songId` initializer through `SimfileMapper`; the repository survey found no current production caller for the legacy initializer.

### 5. Make initial load failure observable without a state framework

The live UI already reads `@Query var serverSongs`; the array returned from `ServerSongService.loadServerSongs()` is ignored by `ContentView`. Remove the misleading result contract instead of inventing another in-memory source of truth.

Change the cache load boundary to:

```swift
func loadServerSongs(modelContext: ModelContext) async throws
```

It performs a real SwiftData fetch (so fetch failure propagates) and retains the current status reconciliation call. It does not convert fetch failure to `[]`.

Change the service boundary to:

```swift
func loadServerSongs() async
```

Use existing `isLoading` and add only:

```swift
@Published private(set) var catalogLoadFailed = false
```

Behavior:

- start load: `isLoading = true`, clear `errorMessage`;
- load success: `catalogLoadFailed = false`;
- load failure: `catalogLoadFailed = true`, set `errorMessage` to `Failed to load server songs: ...`, log the error;
- always finish with `isLoading = false`;
- successful manual refresh also clears `catalogLoadFailed`;
- failed manual refresh sets it, while leaving any previously cached rows visible.

`ContentView` calls `await serverSongService.loadServerSongs()` without assigning a result.

`ServerSongsView` keeps the existing cache rows as the first priority. Only when `serverSongs.isEmpty` does it distinguish:

1. `isLoading || isRefreshing` → loading placeholder;
2. `catalogLoadFailed` → failed placeholder (`Couldn’t load server songs` / `Tap refresh to try again`);
3. otherwise → valid empty-catalog placeholder.

The existing header refresh button and alert are sufficient retry/error affordances. Do not add a second retry controller or state enum.

### 6. Focused regression coverage

#### Complete replacement

Seed cache rows `a` and stale `z`, plus a local server-imported `Song(serverSongId: "a")`. Refresh with DTOs containing changed `a` and new `b`.

Assert:

- cache IDs become exactly `a` and `b`;
- `a` receives the DTO's new title/artist/BPM/duration/chart URL/encoding/media availability;
- `z` disappears only from `ServerSong` / `ServerChart` cache rows;
- the local `Song(serverSongId: "a")` still exists unchanged;
- matching `a` has download/BGM/preview flags projected from the local row;
- the injected cache `saveContext` is called once and no post-save status refresh is invoked.

#### Non-destructive failures

For each of these, seed an old persisted cache row first and assert it remains unchanged with no partial new rows:

- backend request throws;
- an empty page arrives before `totalCount` is satisfied;
- later page reports a different `totalCount`;
- response contains duplicate IDs;
- mapped mutation reaches save but the injected save hook throws (rollback restores the old cache).

Also cover a valid empty snapshot: it clears only the server cache and preserves local songs.

#### Stable identity

Update `ServerSongStatusManagerTests` fixtures to carry explicit current `serverSongId` values. Add assertions that same-title/artist rows with a different or nil ID do not affect download status or deletion.

Keep the existing downloader stable-ID duplicate test and distinct-server-ID/same-title test. Replace the two legacy fallback tests with one current-policy test proving that a nil-ID local song with the same title/artist does not block a server import.

Delete backfill-only cache coverage and legacy single-file model tests.

#### Failure presentation

`ServerSongServiceTests` should prove:

- cache load error ends loading, sets `catalogLoadFailed`, and exposes an error message;
- successful load clears a previous failure;
- refresh failure is visible and does not claim success;
- successful refresh clears the failure flag.

Do not build a new SwiftUI test harness solely for the placeholder. Keep the view branch small and exercise it through existing compile/UI smoke coverage.

### 7. Keep live repository guidance accurate

`CLAUDE.md` is operational guidance (`AGENTS.md` points to it) and currently says `ServerSongCache` refresh is additive. Update only that live section when implementation lands:

- catalog refresh is manual, validated, and full-snapshot replacement;
- `ServerSong` / `ServerChart` are replaceable cache metadata;
- local `Song.serverSongId` is the stable server identity and local rows are not pruned by catalog replacement.

Do not clean old historical plan documents in this ticket; HPA-583 owns that cleanup.

## Expected file impact

Production:

- `Virgo/utilities/ServerSongCache.swift`
- `Virgo/utilities/ServerSongStatusManager.swift`
- `Virgo/utilities/ServerSongDownloader.swift`
- `Virgo/utilities/ServerSongService.swift`
- `Virgo/models/DrumTrack.swift`
- `Virgo/views/ContentView.swift`
- `Virgo/views/ServerSongsView.swift`
- `CLAUDE.md`

Focused tests:

- `VirgoTests/ServerSongCatalogRefreshTests.swift`
- `VirgoTests/ServerSongCacheCoverageTests.swift`
- `VirgoTests/ServerSongStatusManagerTests.swift`
- `VirgoTests/ServerSongDownloaderTests.swift`
- `VirgoTests/ServerSongServiceTests.swift`
- `VirgoTests/ServerSongModelTests.swift`

No new production file or SwiftData model is required.

## Acceptance mapping

- **Complete valid DTO snapshot replaces cache metadata through one context mutation/save phase:** Sections 1–3 and replacement/save-count tests.
- **Failed, incomplete, or duplicate-ID responses are non-destructive and visible:** Sections 1, 5, and non-destructive failure tests.
- **Current server metadata replaces stale cached metadata:** Section 3 replacement behavior.
- **Download state is reconciled from current local songs by stable server ID:** Section 2.
- **Legacy catalog backfill and fallback matching code is deleted:** Section 4.
- **Focused cache/service tests cover replacement and failure without sync infrastructure:** Section 6.

## Self-review against Virgo guardrails

- No backward-compatibility mechanism is introduced; compatibility code is deleted.
- No repository, coordinator, migration framework, or synchronization protocol is added.
- No background work, retry system, or server API change is added.
- Local user/application data is outside the cache replacement transaction.
- Status projection reuses the existing status manager rather than creating a parallel abstraction.
- Failure UI uses existing service/view structure plus one Boolean, not a new state machine framework.
- HPA-579/HPA-580 performance scope and HPA-85 audio scope remain untouched.
