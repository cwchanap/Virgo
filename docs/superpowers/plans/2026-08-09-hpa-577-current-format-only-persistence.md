# HPA-577 Current-Format-Only Persistence Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to execute this plan task-by-task with review checkpoints.

**Goal:** Delete Virgo's pre-release startup/persistence compatibility paths so the app supports only data written by the current build, while preserving fresh fixture import, current score/history persistence, practice settings, bundled-fixture deletion, and UI-test reset/seeding.

**Architecture:** Keep the existing owners (`ContentView`, `LocalDTXFixtureImporter`, `ScorePersistenceService`, `PracticeSettingsService`) and remove upgrade behavior from them. Stable IDs provide narrow idempotence; a matching existing fixture row is returned unchanged. No replacement migration/version/dedup layer is introduced.

**Tech Stack:** Swift, SwiftUI, SwiftData, Swift Testing, Xcode 26.1.1 / `xcodebuild`.

**Design:** `docs/superpowers/specs/2026-08-09-hpa-577-current-format-only-persistence-design.md`

## Global constraints

- Breaking local SwiftData/UserDefaults changes are accepted. Old development data may be reset.
- Do not add schema/version registries, migration coordinators, compatibility adapters, generic deduplication, or automatic destructive production reset.
- Keep `ContentView` as the startup composition point; do not create a startup coordinator/use-case layer.
- Keep `LocalDTXFixtureImporter` as the local fixture owner; do not create a fixture repository/reconciliation engine.
- Keep current save-failure handling for fresh imports and current scores. Failure recovery for current writes is not backward compatibility.
- Keep `BundledFixtureDeletionStore`; user deletion of the bundled demo is current product behavior.
- Do not change server-catalog refresh behavior (HPA-578), performance/actor placement (HPA-579/HPA-580), or broad architecture/test documentation (HPA-583).
- Run macOS tests with `-parallel-testing-enabled NO`, matching CI.
- The Xcode project uses file-system-synchronized groups. Do not hand-edit `Virgo.xcodeproj/project.pbxproj` for file deletions/renames unless a build proves it is required.

---

## Task 1: Collapse local fixture re-import to stable-ID idempotence

**Files:**

- Modify: `Virgo/utilities/LocalDTXFixtureImporter.swift`
- Modify: `VirgoTests/LocalDTXFixtureImporterTests.swift`
- Modify: `VirgoTests/LocalDTXFixtureImporterCoverageTests.swift`

**Behavioral boundary:** A fresh import creates the complete current representation. A repeated import for the same `serverSongId` returns the existing row without mutating it.

### Step 1: Add the no-repair regression first

In `VirgoTests/LocalDTXFixtureImporterTests.swift`, replace the old “refresh stale Soukyuu” expectations with one explicit policy test. Use a real fixture so the test proves that a source capable of repairing the row is present, yet the importer deliberately does not do so.

Add a test shaped like:

```swift
@Test("re-import by stable ID returns the existing row without repair")
func reImportByStableIDDoesNotRepairExistingSong() throws {
    let context = TestContainer.isolatedContainer().context
    let fixtureURL = try soukyuuFixtureURL()
    let staleBGM = fixtureURL.appendingPathComponent("bgm.ogg").path

    let existing = Song(
        title: "蒼穹への翔歌",
        artist: "legacy local state",
        bpm: 165.55,
        duration: "5:14",
        genre: "DTX Import",
        timeSignature: .fourFour,
        isServerImported: false,
        serverSongId: LocalDTXFixtureImporter.soukyuuSongId,
        bgmFilePath: staleBGM,
        previewFilePath: nil
    )
    context.insert(existing)
    try context.save()

    let returned = try LocalDTXFixtureImporter.importSong(
        from: fixtureURL,
        into: context
    )

    #expect(returned === existing)
    #expect(returned.duration == "5:14")
    #expect(returned.bgmFilePath == staleBGM)
    #expect(returned.previewFilePath == nil)
    #expect(returned.isServerImported == false)
    #expect(try context.fetch(FetchDescriptor<Song>()).count == 1)
}
```

This test should fail against the current implementation because re-import repairs duration/audio fields.

Remove/replace existing tests whose desired result is specifically a repair:

- `refreshesStaleSoukyuuAudioPathsWhenAlreadyImported`
- `refreshClearsStaleAudioPathsWhenAssetsRemoved`
- `reImportRefreshesStaleDuration`

Keep tests that merely prove stable-ID reuse or fresh-import correctness. `reImportLeavesMissingLegacyBGMStartOffsetUntouched` / `reImportDoesNotClobberExistingBGMStartOffset` can be folded into the new single no-repair regression rather than retaining multiple historical-state variants.

In `LocalDTXFixtureImporterCoverageTests.swift`, change the “existing record marked deleted is refreshed” test wording to “existing record marked deleted is returned” and assert identity only. Delete the unreadable-SET refresh-path test because an existing stable-ID row will no longer decode `SET.def` at all.

### Step 2: Run the focused test and verify RED

```bash
xcodebuild test \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'platform=macOS' \
  -configuration Debug \
  -only-testing:VirgoTests/LocalDTXFixtureImporterTests \
  -only-testing:VirgoTests/LocalDTXFixtureImporterCoverageTests \
  -parallel-testing-enabled NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  -destination-timeout 300 \
  -derivedDataPath ./DerivedData
```

Expected: the new no-repair test fails because the existing branch still calls refresh helpers.

### Step 3: Make the existing-ID branch return immediately

In `LocalDTXFixtureImporter.swift`, simplify the private import entry point so it has no `performLegacySourceRefreshes` parameter.

The existing-ID path becomes exactly:

```swift
if let existingSong = try existingSong(with: songId, in: context) {
    return LocalDTXFixtureImportResult(song: existingSong, warnings: [])
}
```

Delete:

```swift
refreshAudioPaths(...)
refreshDurationIfStale(...)
refreshControlEventsIfMissing(...)
performLegacySourceRefreshes
```

Do not replace them with a general `refreshExistingSong`, diff, or “validate then repair” function.

Both normal and bundled imports should call the same current-format import path.

### Step 4: Remove the now-unused custom-ID convenience overload if it has no current caller

First update retained tests that pass `songId: tempDir.lastPathComponent` only to recreate the default behavior. They should call:

```swift
LocalDTXFixtureImporter.importSong(from: tempDir, into: context)
```

Then verify:

```bash
rg -n 'importSong\(\s*from:.*songId:' Virgo VirgoTests
```

If no retained current caller remains, delete:

```swift
static func importSong(from folderURL: URL, songId: String, into context: ModelContext) throws -> Song
```

Do not keep an unused public-ish overload solely because old tests once used it.

### Step 5: Run the focused fixture suites and verify GREEN

Run the Task 1 command again. Also include the fresh import suites if they are separate after edits:

```bash
xcodebuild test \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'platform=macOS' \
  -configuration Debug \
  -only-testing:VirgoTests/LocalDTXFixtureImporterTests \
  -only-testing:VirgoTests/LocalDTXFixtureImporterCoverageTests \
  -parallel-testing-enabled NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  -destination-timeout 300 \
  -derivedDataPath ./DerivedData
```

Expected: fresh imports still create current timing/audio/control data; repeated stable-ID import returns unchanged state.

### Step 6: Commit the checkpoint

```bash
git add Virgo/utilities/LocalDTXFixtureImporter.swift \
  VirgoTests/LocalDTXFixtureImporterTests.swift \
  VirgoTests/LocalDTXFixtureImporterCoverageTests.swift
git commit -m "refactor: make local fixture import current-format only"
```

---

## Task 2: Delete control/rhythm backfill and its version state

**Files:**

- Modify: `Virgo/utilities/LocalDTXFixtureImporter.swift`
- Delete: `Virgo/utilities/RhythmBackfillVersionStore.swift`
- Modify/rename: `VirgoTests/LocalDTXControlBackfillTests.swift`
- Modify/rename: `VirgoTests/RhythmImportBackfillTests.swift`
- Modify: `VirgoTests/LocalDTXFixtureImporterTests.swift` if comments reference backfill suites

### Step 1: Inventory every backfill-only symbol before deleting it

```bash
rg -n \
  'backfillBundledRhythmTimingIfNeeded|backfillRhythmTiming|RhythmBackfillVersion|RhythmBackfillPlan|RhythmBackfillCandidate|refreshControlEventsIfMissing|unmatchedRhythmBackfillChart|ambiguousRhythmBackfillChart' \
  Virgo VirgoTests
```

Classify each hit as either:

- production backfill/version code to delete;
- a compatibility test to delete;
- a current behavior test that happens to use backfill as setup and must be rewritten to start from a fresh current projection.

Do not keep a production backfill API just to avoid rewriting a test.

### Step 2: Preserve current fresh-control coverage and delete control-upgrade coverage

`LocalDTXControlBackfillTests.swift` currently mixes fresh import with legacy repair.

Retain current tests such as:

- fresh import populates `controlEvents`;
- multi-difficulty fresh import routes controls to the correct charts.

Delete tests whose contract is re-import repair, including missing-control backfill, first-wins upgrade semantics, mixed-grid backfill, and multi-difficulty/MASTER+REAL backfill routing.

If the remaining file contains only fresh-import behavior, rename it narrowly:

```bash
git mv VirgoTests/LocalDTXControlBackfillTests.swift \
  VirgoTests/LocalDTXControlImportTests.swift
```

Update the suite/header comments only. Do not move these tests into unrelated files; HPA-583 owns broad test consolidation.

### Step 3: Preserve current projection behavior without a backfill setup

`RhythmImportBackfillTests.swift` includes valuable projection/fresh-import assertions alongside upgrade tests.

Keep pure current-format tests such as:

- failed fresh import rolls back the inserted graph;
- valid DTX projection carries canonical timing;
- timing-fatal projection keeps source identity while canonical timing is absent.

For a test that currently deletes normalized fields and then invokes `backfillRhythmTiming` merely to reach a downstream layout assertion, rewrite its fixture/setup to use the fresh `DTXChartPersistenceProjection` directly. The product behavior being tested should be the current projection/layout, not recovery of an old row.

Delete tests whose subject is timing backfill selection, version idempotence, unmatched/ambiguous legacy candidates, or duplicate legacy source charts.

If “Backfill” is no longer accurate, rename narrowly:

```bash
git mv VirgoTests/RhythmImportBackfillTests.swift \
  VirgoTests/RhythmImportTests.swift
```

### Step 4: Delete the production backfill implementation

From `LocalDTXFixtureImporter.swift`, delete:

- `backfillBundledRhythmTimingIfNeeded`;
- `backfillRhythmTiming`;
- backfill-only error cases/descriptions;
- `RhythmBackfillPlan`;
- `RhythmBackfillCandidate`;
- `RhythmBackfillProjectionKey`;
- source-matching/sort/apply helpers used only by backfill.

Delete the entire file:

```text
Virgo/utilities/RhythmBackfillVersionStore.swift
```

There is no replacement version key.

### Step 5: Clean the caller in `ContentView`

In `ContentView.seedLocalDTXFixtures()`, reduce:

```swift
if let song {
    try LocalDTXFixtureImporter.backfillBundledRhythmTimingIfNeeded(...)
    Logger.database(...)
}
```

to current seeding only:

```swift
if let song {
    Logger.database("Seeded local DTX fixture: \(song.title)")
}
```

Do not add a different “ensure current timing” pass; fresh current imports already persist canonical timing.

### Step 6: Update adjacent startup wording

In `ContentStartupPolicy.shouldImportBundledLocalDTXFixtures`, replace comments that say the fixture is “refreshed on subsequent launches” with current semantics: startup ensures the current stable-ID fixture is present when allowed; an existing row is returned unchanged.

Also update any immediately adjacent importer/test comments that promise self-healing refresh behavior.

Do not clean historical docs/specs in this ticket; HPA-583 owns broad documentation consolidation.

### Step 7: Verify backfill symbols are gone and current import tests pass

```bash
rg -n \
  'backfillBundledRhythmTimingIfNeeded|backfillRhythmTiming|RhythmBackfillVersion|RhythmBackfillPlan|RhythmBackfillCandidate|refreshControlEventsIfMissing|unmatchedRhythmBackfillChart|ambiguousRhythmBackfillChart' \
  Virgo VirgoTests
```

Expected: no hits.

Then run the retained fixture/rhythm suites:

```bash
xcodebuild test \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'platform=macOS' \
  -configuration Debug \
  -only-testing:VirgoTests/LocalDTXFixtureImporterTests \
  -only-testing:VirgoTests/LocalDTXFixtureImporterCoverageTests \
  -only-testing:VirgoTests/LocalDTXControlImportTests \
  -only-testing:VirgoTests/RhythmImportTests \
  -parallel-testing-enabled NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  -destination-timeout 300 \
  -derivedDataPath ./DerivedData
```

If a file was not renamed, use its actual retained suite name in `-only-testing` rather than renaming solely to match this command.

### Step 8: Commit the checkpoint

```bash
git add -A Virgo/utilities Virgo/views/ContentView.swift VirgoTests
git commit -m "refactor: delete local fixture backfill paths"
```

---

## Task 3: Remove startup database maintenance and legacy score migration

**Files:**

- Modify: `Virgo/views/ContentView.swift`
- Delete: `Virgo/services/DatabaseMaintenanceService.swift`
- Delete: `VirgoTests/DatabaseMaintenanceServiceTests.swift`
- Modify: `Virgo/services/ScorePersistenceService.swift`
- Modify: `VirgoTests/ScorePersistenceServiceTests.swift`

### Step 1: Delete the database-maintenance startup path

In `ContentView` remove:

```swift
@State private var databaseService: DatabaseMaintenanceService?
```

and the entire block that creates/calls it.

Also remove the comments and chart re-fetch that exist solely because maintenance may delete songs.

Do not simplify `startupSongsOverride` away in the same change. It still bridges synchronous UI-test/bundled seeding to a live `@Query` and is not a compatibility mechanism.

Delete:

```text
Virgo/services/DatabaseMaintenanceService.swift
VirgoTests/DatabaseMaintenanceServiceTests.swift
```

Do not move any of its repair methods elsewhere.

### Step 2: Delete the startup score migration call

Remove from `ContentView` the `FetchDescriptor<Chart>` + `migrateLegacyHighScores` block. Normal startup should not scan all charts for historical score data.

Keep `ScorePersistenceService` creation in gameplay/current owners only; do not instantiate it just for startup.

### Step 3: Delete migration-only score code

From `ScorePersistenceService.swift`, delete:

```swift
private static let migrationFlagKey = "DidMigrateHighScoresToSwiftData"
private static let legacyHighScoreKey = "HighScorePerChart"
func migrateLegacyHighScores(...)
private func readLegacyScores(...)
```

Keep unchanged:

- `RecordResult`;
- `recordAttempt`;
- save-failure rollback for the current attempt;
- `bestScore`;
- `recentAttempts`;
- pruning;
- `makeInMemory`.

### Step 4: Delete only migration-specific score tests

In `ScorePersistenceServiceTests.swift`, remove every `migrateLegacyHighScores` test, including:

- normal migration;
- idempotence/flag behavior;
- no-data behavior;
- NSNumber/non-numeric legacy parsing;
- lower-score behavior;
- stale-key clearing;
- pre-set flag behavior;
- migration rollback on save failure.

Keep current save-failure rollback tests for `recordAttempt`.

`SaveHookError` remains if current score-save tests still use it.

### Step 5: Verify no maintenance/score-migration production references remain

```bash
rg -n \
  'DatabaseMaintenanceService|performInitialMaintenance|migrateLegacyHighScores|HighScorePerChart|DidMigrateHighScoresToSwiftData' \
  Virgo VirgoTests
```

Expected: no hits.

### Step 6: Run current score and app-shell unit coverage

```bash
xcodebuild test \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'platform=macOS' \
  -configuration Debug \
  -only-testing:VirgoTests/ScorePersistenceServiceTests \
  -only-testing:VirgoTests/AppShellCoverageTests \
  -parallel-testing-enabled NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  -destination-timeout 300 \
  -derivedDataPath ./DerivedData
```

Expected: current score/history behavior and startup policy coverage remain green without maintenance/migration code.

### Step 7: Commit the checkpoint

```bash
git add -A Virgo/views/ContentView.swift Virgo/services VirgoTests
git commit -m "refactor: delete startup and score compatibility"
```

---

## Task 4: Make practice-settings keys current-format-only

**Files:**

- Modify: `Virgo/services/PracticeSettingsService.swift`
- Modify: `Virgo/utilities/PersistentIdentifierPersistenceKey.swift`
- Modify: `VirgoTests/PracticeSettingsServiceTests.swift`
- Modify: `VirgoTests/CollectionAndLayoutExtensionTests.swift`
- Modify: `VirgoTests/SwiftDataRelationshipLoaderTests.swift`

### Step 1: Replace the migration test with a breaking-policy regression

In `PracticeSettingsServiceTests.swift`, delete the generic legacy-key helper methods:

```swift
makeLegacyPersistenceKey(...)
addWhitespaceOutsideStrings(...)
```

Replace `testLoadSpeedMigratesLegacyPersistenceKeys` with a smaller policy test that constructs one non-canonical-but-previously-resolvable key inline:

```swift
@Test("loadSpeed ignores non-canonical historical keys")
func loadSpeedIgnoresNonCanonicalHistoricalKeys() async throws {
    try await TestSetup.withTestSetup {
        let (userDefaults, _) = TestUserDefaults.makeIsolated()
        let chartID = try makeTestChartID()
        let canonicalKey = PersistentIdentifierPersistenceKey.canonicalKey(
            for: chartID,
            logPrefix: "Test"
        )
        let nonCanonicalKey = " \(canonicalKey) "

        userDefaults.set(
            [nonCanonicalKey: 0.8],
            forKey: "PracticeSettingsSpeedMultipliers"
        )

        let service = PracticeSettingsService(userDefaults: userDefaults)
        #expect(service.loadSpeed(for: chartID) == 1.0)
        #expect(
            userDefaults.dictionary(forKey: "PracticeSettingsSpeedMultipliers")?[nonCanonicalKey] != nil
        )
    }
}
```

Against the current resolver this should fail because whitespace-normalized JSON is recognized and migrated.

### Step 2: Verify RED

```bash
xcodebuild test \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'platform=macOS' \
  -configuration Debug \
  -only-testing:VirgoTests/PracticeSettingsServiceTests \
  -parallel-testing-enabled NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  -destination-timeout 300 \
  -derivedDataPath ./DerivedData
```

Expected: the new non-canonical-key test fails under the legacy resolver.

### Step 3: Simplify `PracticeSettingsService.loadSpeed`

Replace resolver/migration logic with an exact canonical lookup:

```swift
let key = persistenceKey(for: chartID)
guard let savedSpeed = readPersistedSpeeds()[key] else {
    return 1.0
}
```

Keep the existing finite/range validation and session cache.

In `readPersistedSpeeds()`, keep numeric bridging for the current UserDefaults representation (`Double` / `NSNumber`). Remove the `String -> Double` fallback because the current writer never stores string values.

Update `testLoadSpeedDecodesNSNumberAndStringValues` to test current numeric bridging only.

### Step 4: Reduce `PersistentIdentifierPersistenceKey` to current key generation

Keep:

```swift
static func canonicalKey(for identifier: PersistentIdentifier, logPrefix: String) -> String
```

and its current error fallback.

Delete:

```swift
Resolution<Value>
resolve(...)
normalizeJSONKey(...)
```

Do not add a replacement resolver.

### Step 5: Delete compatibility-only resolver test suites

Remove the `PersistentIdentifierPersistenceKey.Resolution` suites from:

- `CollectionAndLayoutExtensionTests.swift`;
- `SwiftDataRelationshipLoaderTests.swift`.

Update those files' header comments accordingly. Leave their unrelated array/layout/relationship tests untouched.

### Step 6: Verify resolver/migration symbols are gone and current settings pass

```bash
rg -n \
  'PersistentIdentifierPersistenceKey\.resolve|needsMigration|matchedKey|normalizeJSONKey|loadSpeedMigratesLegacy|makeLegacyPersistenceKey' \
  Virgo VirgoTests
```

Expected: no hits.

Then rerun:

```bash
xcodebuild test \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'platform=macOS' \
  -configuration Debug \
  -only-testing:VirgoTests/PracticeSettingsServiceTests \
  -only-testing:VirgoTests/CollectionAndLayoutExtensionTests \
  -only-testing:VirgoTests/SwiftDataRelationshipLoaderTests \
  -parallel-testing-enabled NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  -destination-timeout 300 \
  -derivedDataPath ./DerivedData
```

Expected: canonical current settings still round-trip; the historical key is ignored.

### Step 7: Commit the checkpoint

```bash
git add Virgo/services/PracticeSettingsService.swift \
  Virgo/utilities/PersistentIdentifierPersistenceKey.swift \
  VirgoTests/PracticeSettingsServiceTests.swift \
  VirgoTests/CollectionAndLayoutExtensionTests.swift \
  VirgoTests/SwiftDataRelationshipLoaderTests.swift
git commit -m "refactor: remove persistence key compatibility"
```

---

## Task 5: Final current-format audit and platform verification

**Files:**

- Modify only if the audit finds stale compatibility comments/references adjacent to touched production/tests.
- Do not expand into HPA-583 documentation consolidation.

### Step 1: Search for every removed compatibility concept

```bash
rg -n \
  'DatabaseMaintenanceService|performInitialMaintenance|migrateLegacyHighScores|HighScorePerChart|DidMigrateHighScoresToSwiftData|performLegacySourceRefreshes|refreshAudioPaths|refreshDurationIfStale|refreshControlEventsIfMissing|backfillBundledRhythmTimingIfNeeded|backfillRhythmTiming|RhythmBackfillVersion(Store|Storing)|PersistentIdentifierPersistenceKey\.resolve|needsMigration' \
  Virgo VirgoTests
```

Expected: no hits.

Also search for stale promises that re-import repairs older data:

```bash
rg -n 'refresh(es|ed|ing)? .*fixture|legacy .*backfill|self-healing refresh|upgrade path' \
  Virgo VirgoTests
```

Review each hit manually. Delete/reword only comments/tests adjacent to HPA-577 behavior. Do not sweep historical design documents.

### Step 2: Check the diff is deletion-first

```bash
git diff --stat main...HEAD
git diff --check main...HEAD
```

Review the stat. A correct HPA-577 implementation should remove substantially more compatibility code/tests than it adds. If the implementation grows a new framework or comparable amount of replacement code, stop and simplify it before proceeding.

### Step 3: Run the complete macOS unit-test command used by CI

Generate local endpoint config if needed using the existing repository script/environment, then run:

```bash
set -o pipefail
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

Expected: all `VirgoTests` pass.

### Step 4: Build the iPad Simulator target used by CI

```bash
xcodebuild build \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO
```

Expected: build succeeds with iPad-only target settings unchanged.

### Step 5: Manual fresh/reset-store smoke

Use a clean development store/UserDefaults (or the existing `-UITesting -ResetState` path) and verify the supported current behavior:

1. launch from a clean/reset state;
2. bundled Soukyuu fixture seeds once when allowed;
3. relaunch does not duplicate it;
4. delete the bundled fixture and relaunch; it remains deleted;
5. clear/reset test state; the bundled fixture can seed again;
6. play a chart and record a score; current `ScoreRecord`/`bestScore` behavior works;
7. save/reload a practice speed using the current canonical key.

Do **not** test preservation of data from an old build; HPA-577 explicitly drops that contract.

### Step 6: Update the implementation PR description

State explicitly:

- old local development stores/UserDefaults may require reset;
- no migration/recovery framework was added;
- HPA-578/HPA-579/HPA-580/HPA-583 and HPA-85 remain out of scope;
- macOS tests and iPad build results.

### Step 7: Commit any final narrow cleanup

```bash
git add -A
git commit -m "test: verify current-format-only persistence cleanup"
```

Skip this commit if Task 5 required no file changes.

---

## Definition of done

- [ ] `ContentView` has no normal-startup historical repair/migration pass.
- [ ] `DatabaseMaintenanceService` is deleted, not relocated.
- [ ] Legacy score migration and legacy practice-key resolution are deleted.
- [ ] Local fixture re-import is stable-ID identity only.
- [ ] Fresh local import remains transactional and writes the full current representation.
- [ ] Rhythm/control backfill and its UserDefaults version marker are deleted.
- [ ] Bundled-fixture deletion/reset behavior remains intact.
- [ ] Compatibility-only tests are deleted; retained tests describe current behavior.
- [ ] No replacement migration/dedup/version abstraction appears in the diff.
- [ ] Full macOS unit tests pass with parallel testing disabled.
- [ ] iPad Simulator build passes.
- [ ] PR notes the intentional breaking local-data policy.