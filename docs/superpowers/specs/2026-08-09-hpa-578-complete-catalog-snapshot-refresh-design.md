# HPA-578: Complete Catalog Snapshot Refresh

**Date:** 2026-08-09
**Status:** Implemented — revised after reference-lifetime review; implementation landed in HPA-578 (see plan `2026-08-09-hpa-578-complete-catalog-snapshot-refresh.md`). Subsequent race fix `eb3e758` removed detached-context cache mutation from `deleteLocalSong`; the plan's Step 5 has been updated to match.

## Context

HPA-578 is the remaining Phase A work in the Virgo runtime/performance roadmap after HPA-576 and HPA-577. It is unblocked and independent of the HPA-579 profiling gate.

Today `ServerSong` / `ServerChart` behave partly like replaceable catalog metadata and partly like durable mutable state:

- `ServerSongCache.refreshCatalog` inserts unseen IDs, preserves existing rows, backfills legacy chart URLs, prunes IDs missing from the server, tolerates duplicate responses, saves, then performs a second status reconciliation.
- Existing cache rows therefore keep stale server metadata indefinitely.
- An incomplete page walk can partially insert new rows.
- `ServerSongStatusManager.pruneCachedSong` can delete a locally imported `Song` and its audio because a catalog ID disappeared.
- `ServerSongDownloader` and `ServerSongStatusManager` still use title/artist fallback identity for rows without `serverSongId`.
- `ServerSongService.downloadAndImportSong` holds a `ServerSong` model across a long `await`, then writes `serverSong.isDownloaded = true`. Full cache replacement would make that captured model disposable while the download is still in flight.
- `ServerSongService.loadServerSongs()` returns an array that `ContentView` discards; the live catalog is already owned by SwiftUI `@Query`.

HPA-577 established the current-format-only policy: old development representations may be reset rather than migrated. HPA-578 applies the same policy to server catalog metadata.

## Decision summary

Treat `ServerSong` / `ServerChart` as replaceable cache metadata and `Song` as durable local application data.

1. Fetch and validate one complete DTO snapshot before any SwiftData mutation.
2. Reject incomplete pagination, changing `totalCount`, over/under-counts, and duplicate server IDs.
3. Map the validated DTOs through `SimfileMapper`.
4. Project download/BGM/preview flags from local server-imported `Song` rows by exact `serverSongId`.
5. Delete old `ServerSong` rows, insert the mapped snapshot, and save exactly once. Roll back on save failure.
6. Never delete or rewrite local `Song`, `Chart`, `Note`, `ScoreRecord`, or audio because a catalog ID disappeared.
7. Never author cache download flags through a `ServerSong` reference that survived an `await`; download completion triggers stable-ID status reconciliation instead.
8. Delete catalog compatibility: URL backfill, additive upsert, title/artist identity fallback, stale pruning, and the single-file `ServerSong` convenience initializer.
9. Keep startup catalog loading non-throwing. `@Query` owns the rows; startup work only reconciles download flags.
10. Surface **manual refresh** failure with the existing alert plus one `catalogRefreshFailed` Boolean. Do not add a catalog state machine.
11. Share one empty/loading/failed placeholder branch between list and grid layouts.

## Approaches considered

### A. Keep additive refresh and patch more fields

Update matching rows in place and keep compatibility/prune behavior.

**Rejected.** It preserves two ways to create current cache metadata and retains the ownership bug where server catalog changes can affect local durable data.

### B. Validate one complete snapshot, then replace cache metadata

Fetch plain DTOs, validate them, map new cache models, project local status, then replace only cache rows in one save.

**Selected.** This is the smallest design that matches the actual ownership model.

### C. Add a repository, staging store, generations, or two-phase swap

**Rejected.** The catalog is a manual pre-release cache. A validated in-memory snapshot plus one SwiftData save is sufficient.

## Goals

- Successful refresh exactly reflects current server metadata.
- Failed/incomplete/duplicate snapshots leave the previous persisted cache untouched.
- Local imported songs and audio survive catalog removals.
- Download state is derived from current local rows using stable IDs.
- In-flight downloads remain safe if the cache is refreshed while they are awaiting network/file work.
- Manual refresh failure is visibly distinguishable from a valid empty catalog.
- Compatibility code is deleted rather than deprecated.

## Non-goals

- Background/automatic refresh.
- Incremental sync tokens, ETags, merge policies, retry queues, repository/use-case layers, staging databases, or generation models.
- Off-main parsing/file changes; HPA-579/HPA-580 own that decision.
- Server BGM format changes; HPA-85 owns that work.
- Broad test/document cleanup; HPA-583 owns the final consolidation.
- New catalog sorting behavior. The current sorted array returned by `ServerSongCache.loadServerSongs` is discarded by `ContentView`; it does not control the live `@Query` order today.

## Design

### 1. Validate a complete plain-DTO snapshot before mutation

Keep orchestration in `ServerSongCache` and keep `SimfileFetching` as the backend seam.

Add one catalog-specific error type:

```swift
enum ServerSongCatalogRefreshError: LocalizedError, Equatable {
    case totalCountChanged(expected: Int, actual: Int)
    case incompleteSnapshot(expected: Int, actual: Int)
    case unexpectedSnapshotCount(expected: Int, actual: Int)
    case duplicateSongID(String)
}
```

`fetchCompleteSnapshot(maxPages:)` rules:

1. First page establishes `expectedTotalCount`.
2. Every later page must report that same count.
3. `totalCount == 0` with zero rows is a valid empty snapshot.
4. Validate each DTO ID as it arrives; the first duplicate throws immediately.
5. Append only validated DTOs.
6. Empty page before expected count throws `incompleteSnapshot`.
7. Exceeding expected count throws `unexpectedSnapshotCount`.
8. Reaching `maxPages` before expected count throws `incompleteSnapshot`.
9. Final row count must equal `expectedTotalCount` exactly.
10. Network errors propagate unchanged.

No `ModelContext.insert` or `delete` occurs before this helper returns successfully.

### 2. Make status projection exact-ID-only

Extract the non-persisting core already inside `ServerSongStatusManager.refreshDownloadStatus`:

```swift
@MainActor
@discardableResult
func applyDownloadStatus(
    to serverSongs: [ServerSong],
    from localSongs: [Song]
) -> Bool
```

It considers only `isServerImported` local rows with non-nil `serverSongId`, groups by exact ID, and sets:

- `isDownloaded` if any local row matches;
- `bgmDownloaded` if any matching row has `bgmFilePath`;
- `previewDownloaded` if any matching row has `previewFilePath`.

`refreshDownloadStatus(modelContext:)` remains the persisted wrapper for non-catalog callers: fetch current rows, call `applyDownloadStatus`, save only if values changed, roll back/log on failure.

Delete title/artist identity from status/deletion flows. During Task 1, `matchesServerSong` may remain only as a temporary dependency of `pruneCachedSong`; Task 2 deletes both together.

### 3. Replace only cache metadata in one save

After validation:

1. Fetch local `Song` rows for status projection.
2. Fetch existing `ServerSong` cache rows.
3. Map DTOs with `SimfileMapper.makeServerSong(from:)`.
4. Apply download flags to those new models.
5. Delete every existing `ServerSong`; cascade owns `ServerChart` cleanup.
6. Insert every replacement `ServerSong` and `ServerChart`.
7. Call injected `saveContext` exactly once.
8. On save failure, `rollback()` and rethrow.

Do not call `pruneCachedSong`. Do not delete local songs or audio. Do not run a second post-save status reconciliation.

A catalog ID disappearing means only that its cache metadata is absent. If the ID returns later, the still-present local `Song(serverSongId:)` will project downloaded state back onto the new cache row.

### 4. Treat cache model references as ephemeral across awaits

Full replacement means a `ServerSong` reference is valid only until an operation suspends unless the caller explicitly re-resolves it.

`ServerSongDownloader.downloadAndImportSong` already does the correct thing: it creates `ServerSongSnapshot` before its first long await and uses that value snapshot for chart/audio work.

`ServerSongService.downloadAndImportSong` must stop doing this after the downloader returns:

```swift
serverSong.isDownloaded = true
try saveModelContext(modelContext)
```

Those writes author derived cache state through a model object that may have been deleted/replaced during the download.

On successful import, the service should only:

```swift
await refreshDownloadStatus()
```

The imported local `Song` carries `serverSongId`, so status reconciliation finds whichever current cache row owns that ID.

Consequences:

- remove the stored `saveModelContext` property from `ServerSongService`; keep the initializer parameter only because it is injected into the cache/status manager constructors;
- delete the service test whose only contract is the direct post-download status save;
- add a regression that replaces the cache row while a mocked download is in flight and proves completion updates the replacement row through status reconciliation without invoking the service save hook.

`deleteDownloadedSong` does **not** need a re-fetch in this ticket. Its `ServerSongStatusManager.deleteDownloadedSong` body has no suspension point and is `@MainActor`; once entered, a refresh cannot interleave until it returns. If that method later gains an `await`, its reference lifetime should be re-reviewed then.

### 5. Delete remaining compatibility surfaces

#### `ServerSongCache`

Delete:

- `backfillLegacyChartURLs`;
- `matchingDtxFile`;
- additive existing-row preservation;
- partial insertion on incomplete walks;
- duplicate recovery/deduplication;
- stale prune loop;
- post-save status refresh.

#### `ServerSongStatusManager`

Delete title/artist matching helpers and parameters. Task 2 also deletes:

- `pruneCachedSong`;
- `isAlreadyDownloaded` if it has no remaining caller after prune removal;
- already-dead `hasBGMFile`;
- already-dead `hasPreviewFile`;
- `matchesServerSong` after its final prune caller disappears.

#### `ServerSongDownloader`

`Song.serverSongId == snapshot.songId` becomes the only duplicate check. Delete exact and case-insensitive title/artist fallback legs.

#### `ServerSongService`

Delete the pre-download empty-`fileURL` “refresh first” compatibility guard. Current invalid URLs fail through `ServerSongDownloader.processChart` / `ServerSongImportError`.

#### `ServerSong`

Delete the legacy single-file convenience initializer and compatibility-only model tests.

### 6. Simplify startup load; make refresh failure visible

The catalog row source is `ContentView`'s `@Query`, not the value returned by the service.

Delete `ServerSongCache.loadServerSongs`. It is not needed to load the live catalog.

Change the service method to a result-less, non-throwing startup reconciliation:

```swift
func loadServerSongs() async {
    guard modelContext != nil else { return }
    isLoading = true
    defer { isLoading = false }
    await refreshDownloadStatus()
}
```

This keeps the existing startup call and existing `isLoading` surface without inventing a second catalog source or a SwiftData “probe fetch.”

Add:

```swift
@Published private(set) var catalogRefreshFailed = false
```

Only manual refresh owns this flag:

- refresh start: clear prior `errorMessage`;
- refresh success: `catalogRefreshFailed = false`;
- refresh failure: `catalogRefreshFailed = true`, set existing refresh error alert;
- always end with `isRefreshing = false`.

Initial reconciliation failure inside `ServerSongStatusManager` remains logged by that existing component; HPA-578 does not add a second error channel for `@Query`/SwiftData failure.

### 7. Use one shared empty/loading/failed placeholder

Keep non-empty cached rows as first priority. When there are no rows, both list and grid render one shared property:

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

`serverList` applies `.listRowBackground(Color.clear)` to this property. `gridPlaceholder` simply returns the same property. This structurally prevents list/grid state-order drift.

Keep accessibility identifiers on loading, failed, and valid-empty states.

### 8. Test migration must precede behavior changes

Task 1 changes shared identity semantics, so old fixtures that depend on title/artist fallback must be made current-ID fixtures **before** the production change.

At minimum migrate:

- `ServerSongCatalogRefreshTests.testAdditiveAndPrune`: matching local row gets `serverSongId: "a"`;
- `ServerSongCatalogRefreshTests.testBackfillLegacyChartURLs`: matching local row gets `serverSongId: "a"`;
- current-match fixtures in `ServerSongStatusManagerTests`, including `setupGroupedSongs` and `testRefreshDownloadStatusUpdatesFlags`.

`ServerSongCacheCoverageTests` contains no local `Song` fixture used for download-status matching today, so there is no identity fixture to migrate there; it is still included in the shared checkpoint regression command because it exercises the cache/status integration.

Task 1 GREEN verification runs the shared affected suites, not only `ServerSongStatusManagerTests`:

- `ServerSongStatusManagerTests`
- `ServerSongStatusDeletionStoreTests`
- `ServerSongCatalogRefreshTests`
- `ServerSongCacheCoverageTests`
- `ServerSongServiceTests`

Downloader/model suites join once their code changes in Task 3; final verification runs all server-management suites together.

### 9. Live guidance

Update only the active `CLAUDE.md` server-song section when implementation lands:

- refresh is validated full-snapshot replacement;
- server cache rows are disposable metadata;
- local songs are never pruned because a catalog ID disappears;
- `Song.serverSongId` is the stable server identity;
- download completion derives cache flags through status reconciliation rather than directly authoring a retained `ServerSong` object.

Do not edit historical plans; HPA-583 owns that cleanup.

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
- `VirgoTests/ServerSongStatusDeletionStoreTests.swift`
- `VirgoTests/ServerSongDownloaderTests.swift`
- `VirgoTests/ServerSongServiceTests.swift`
- `VirgoTests/ServerSongModelTests.swift`
- existing song-tab coverage for the shared placeholder compile/render surface

No new production file or model is required.

## Acceptance criteria

- [ ] A complete valid DTO snapshot replaces all `ServerSong` / `ServerChart` cache metadata through one mutation phase and one save.
- [ ] Fetch, pagination, duplicate-ID, count, and save failures leave the previous cache intact.
- [ ] Current server metadata replaces stale cached metadata.
- [ ] Local downloaded/imported songs and audio are never removed by catalog replacement.
- [ ] Download/BGM/preview flags are projected from local rows using exact `serverSongId` only.
- [ ] Download completion does not mutate a `ServerSong` reference after its long await; a mid-download refresh remains safe.
- [ ] Legacy catalog backfill, stale prune, title/artist fallback, empty-URL refresh prompt, and single-file compatibility initializer are deleted.
- [ ] `loadServerSongs()` is result-less and non-throwing; `@Query` remains the catalog row source.
- [ ] Failed manual refresh is visible through the existing alert and `catalogRefreshFailed`; successful refresh clears the flag.
- [ ] List and grid share one loading/failed/empty placeholder branch.
- [ ] Focused and full server-management tests pass without adding sync/repository infrastructure.
