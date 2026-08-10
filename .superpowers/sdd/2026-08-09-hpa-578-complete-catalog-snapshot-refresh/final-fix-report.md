# HPA-578 final review fix report

## Status

Complete. The deletion/refresh interleaving fix and deterministic regression are
implemented and committed in `d33c132` (`fix: reconcile local delete after
catalog refresh`).

## Root cause and scheduling analysis

`ServerSongCache.refreshCatalog` is `@MainActor`. After its fetch await returns,
it fetches local `Song` rows, projects the three download flags onto replacement
`ServerSong` rows, deletes the old cache rows, inserts the replacement rows, and
invokes its single save closure without another suspension point.

`ServerSongStatusManager.deleteLocalSong` is also entered on the main actor, but
its actual deletion runs in `Task.detached`. That detached context can delete
the local `Song` and save after refresh has already projected the local row but
before refresh saves the replacement cache. The replacement therefore retains
`isDownloaded`, `bgmDownloaded`, and `previewDownloaded` as `true`. The service
previously returned from successful deletion without reconciling the current
cache row.

The minimal ownership-preserving fix is in `ServerSongService.deleteLocalSong`:
after the detached deletion succeeds, it awaits the existing
`refreshDownloadStatus()` path. Because both service operations resume on the
main actor, this reconciliation runs after any in-progress replacement save
has completed and derives all three flags from the now-current local store. No
cache serialization, coordinator, repository, or snapshot-save change was
needed.

## RED evidence

I added `testDeleteLocalSongReconcilesReplacementAfterRefreshOverlap` before the
production fix. The test uses actual `ServerSongCache`,
`ServerSongStatusManager`, `ServerSongService`, `ModelContainer`, and detached
deletion behavior. Injected save closures use semaphores only to force this
ordering:

1. Detached deletion reaches its save and waits.
2. Refresh snapshots the still-present local song, projects `true` flags, and
   reaches its replacement save, which waits.
3. The arbiter releases deletion save, then releases replacement save.
4. The service completes deletion and the test reads the persisted replacement
   row from a fresh `ModelContext`.

Against `f2662c927e05dca820705222c779d2c0654e4c8f`, the focused command failed
with:

```text
Failing tests:
    ServerSongServiceTests.testDeleteLocalSongReconcilesReplacementAfterRefreshOverlap()
    ServerSongServiceTests.testDeleteLocalSongReconcilesReplacementAfterRefreshOverlap()
    ServerSongServiceTests.testDeleteLocalSongReconcilesReplacementAfterRefreshOverlap()

** TEST FAILED **
```

The repeated entries are the Swift Testing/Xcode failure summary; the failure
was the three persisted-flag expectations in the overlap regression.

## GREEN evidence

Covering service suite, serial:

```bash
xcodebuild test -project Virgo.xcodeproj -scheme Virgo \
  -destination 'platform=macOS' \
  -only-testing:VirgoTests/ServerSongServiceTests \
  -parallel-testing-enabled NO \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath /private/tmp/virgo-hpa578-final-green2
```

Result: `Test run with 25 tests in 1 suite passed`; `** TEST SUCCEEDED **`.

All eight focused HPA-578 suites, serial:

```bash
xcodebuild test -project Virgo.xcodeproj -scheme Virgo \
  -destination 'platform=macOS' \
  -only-testing:VirgoTests/ServerSongStatusManagerTests \
  -only-testing:VirgoTests/ServerSongStatusDeletionStoreTests \
  -only-testing:VirgoTests/ServerSongCatalogRefreshTests \
  -only-testing:VirgoTests/ServerSongCacheCoverageTests \
  -only-testing:VirgoTests/ServerSongServiceTests \
  -only-testing:VirgoTests/ServerSongDownloaderTests \
  -only-testing:VirgoTests/ServerSongModelTests \
  -only-testing:VirgoTests/SongsTabCoverageTests \
  -parallel-testing-enabled NO \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath /private/tmp/virgo-hpa578-final-green2
```

Result: `Test run with 85 tests in 8 suites passed`; `** TEST SUCCEEDED **`.

## Files changed

- `Virgo/utilities/ServerSongService.swift` — reconcile download status after successful local deletion.
- `VirgoTests/ServerSongServiceTests.swift` — deterministic real SwiftData overlap regression and save-boundary coordinator.

## Verification and self-review

- `git diff --check` passed.
- The regression observes a fresh persisted replacement row and asserts all
  three flags are cleared plus the local `Song` is gone; it is not a mock-call
  assertion.
- The fix runs only on successful deletion; failure behavior and existing error
  reporting are unchanged.
- No retained `ServerSong` reference is mutated across an await, and the
  complete-snapshot/one-cache-save contract is unchanged.
- The commit hook SwiftLint check passed. The touched test file still reports
  warning-level file/function size findings (including pre-existing size debt);
  no lint error was introduced.

## Concerns

No functional concerns. A direct changed-file `swiftlint lint --quiet` invocation
also reported the sandbox's inability to write its cache plist; the commit hook
ran successfully. No full macOS or iPad build was repeated in this narrow final
fix wave; the required eight focused suites passed serially.

## Commit

`d33c132` — `fix: reconcile local delete after catalog refresh`
