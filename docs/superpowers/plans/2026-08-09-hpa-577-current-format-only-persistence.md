# HPA-577 Current-Format-Only Persistence Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Delete Virgo's pre-release startup/persistence compatibility paths while preserving current fixture audio-path resolution, fresh fixture import, current score/history persistence, current practice settings, bundled-fixture deletion, and UI-test reset/seeding.

**Architecture:** Keep the existing owners (`ContentView`, `LocalDTXFixtureImporter`, `ScorePersistenceService`, `PracticeSettingsService`) and delete only historical upgrade behavior. Stable IDs keep fixture import idempotent. Existing fixture rows may update BGM/preview filesystem paths because those paths are absolute and consumed directly; other persisted fields/relationships are not repaired. Do not replace removed compatibility with migration/version/dedup infrastructure.

**Tech Stack:** Swift, SwiftUI, SwiftData, Swift Testing, XCTest UI testing, Xcode 26.1.1, `xcodebuild`.

**Design:** `docs/superpowers/specs/2026-08-09-hpa-577-current-format-only-persistence-design.md`

## Global Constraints

- Breaking local SwiftData/UserDefaults representation changes are accepted. Old development data may be reset.
- Do not add schema/version registries, migration coordinators, compatibility adapters, generic deduplication, or automatic destructive production reset.
- Keep `ContentView` as the startup composition point; do not create a startup coordinator/use-case layer.
- Keep `LocalDTXFixtureImporter` as the local fixture owner; do not create a fixture repository/reconciliation engine.
- Keep `refreshAudioPaths`; it is current filesystem-path resolution, not migration. Do not replace it with a bundle-relative path redesign in this ticket.
- Keep current save-failure handling for fresh imports and current scores. Failure recovery for current writes is not backward compatibility.
- Keep `BundledFixtureDeletionStore`; durable user deletion of the bundled demo is current product behavior.
- Keep `RhythmTimelineResolver.resolveMissing` and `.legacy` runtime fallback behavior; HPA-577 deletes import/startup backfill, not runtime fallback. Do not claim `.legacy` is automatically blocked by `ChartPracticeState`; current code treats it as non-fatal.
- `ServerSongDownloader.songAlreadyExists` title/artist fallbacks are **not HPA-577 work**. HPA-578 explicitly owns deleting them and making `serverSongId` the current server-import identity contract.
- Do not change server catalog refresh behavior (HPA-578), performance/actor placement (HPA-579/HPA-580), server BGM format work (HPA-85), or broad historical documentation/test consolidation (HPA-583).
- Update only live `CLAUDE.md` guidance that becomes false because this ticket deletes production APIs. `AGENTS.md` is a symlink to `CLAUDE.md`; do not edit both.
- Run macOS unit/UI tests with parallel testing disabled, matching CI.
- The Xcode project uses file-system-synchronized groups. Do not hand-edit `Virgo.xcodeproj/project.pbxproj` for file deletions/renames unless a build proves it is required.

---

## Task 1: Make repeated fixture import path-current but model-repair-free

**Files:**
- Modify: `Virgo/utilities/LocalDTXFixtureImporter.swift`
- Modify: `VirgoTests/LocalDTXFixtureImporterTests.swift`
- Modify: `VirgoTests/LocalDTXFixtureImporterCoverageTests.swift`

**Interfaces:**
- Consumes: `LocalDTXFixtureImporter.importSong(from:into:)`, `existingSong(with:in:)`, `refreshAudioPaths`, current DTX parser/projection.
- Produces: repeated import for the same `serverSongId` re-resolves only BGM/preview paths, returns the same persisted `Song`/graph, and performs no duration/control/rhythm repair.
- Deferred to Task 2: deleting `importSong(from:songId:into:)`. Keep it temporarily because control-backfill tests still have callers.

- [ ] **Step 1: Keep current audio-path removal coverage and replace legacy path framing.**

Retain `refreshClearsStaleAudioPathsWhenAssetsRemoved`; it protects current behavior because persisted absolute paths must be cleared when the current fixture no longer contains those assets.

Delete the old `refreshesStaleSoukyuuAudioPathsWhenAlreadyImported` test if it remains framed specifically as an `bgm.ogg -> bgm.m4a` upgrade. The richer policy test in Step 2 will cover current absolute-path relocation instead.

Update stale comments that say BOM-less UTF-8 would be lossily decoded as UTF-16. The current importer gates UTF-16 on a BOM, so those comments are no longer accurate. Do not change the tested encoding solely because of comment cleanup.

- [ ] **Step 2: Add one graph-level boundary regression with current audio files.**

Add this test to `LocalDTXFixtureImporterTests.swift` using the existing `makeTempDirectory()` helper:

```swift
@Test("re-import refreshes audio paths without repairing persisted graph data")
func reImportRefreshesOnlyAudioPaths() throws {
    let context = TestContainer.isolatedContainer().context
    let tempDir = try makeTempDirectory()

    try """
    #TITLE: Current Source
    #L1LABEL: BASIC
    #L1FILE: chart.dtx
    """.write(
        to: tempDir.appendingPathComponent("SET.def"),
        atomically: true,
        encoding: .utf8
    )

    try """
    #TITLE: Current Source
    #ARTIST: Tester
    #BPM: 120
    #DLEVEL: 50
    #VIRGO_CONTROL: 1
    #00012: 01000000
    #00022: 16000000
    """.write(
        to: tempDir.appendingPathComponent("chart.dtx"),
        atomically: true,
        encoding: .utf8
    )

    let currentBGM = tempDir.appendingPathComponent("bgm.m4a")
    let currentPreview = tempDir.appendingPathComponent("preview.mp3")
    try Data().write(to: currentBGM)
    try Data().write(to: currentPreview)

    let existing = Song(
        title: "Legacy Local State",
        artist: "Legacy Artist",
        bpm: 90,
        duration: "9:59",
        genre: "DTX Import",
        timeSignature: .fourFour,
        isServerImported: false,
        serverSongId: tempDir.lastPathComponent,
        bgmFilePath: "/old-container/bgm.m4a",
        previewFilePath: "/old-container/preview.mp3",
        bgmStartOffsetSeconds: 0.42
    )
    let chart = Chart(difficulty: .easy, level: 50, song: existing)
    let note = Note(
        interval: .quarter,
        noteType: .snare,
        measureNumber: 1,
        measureOffset: 0,
        chart: chart
    )
    chart.notes = [note]
    existing.charts = [chart]
    context.insert(existing)
    context.insert(chart)
    context.insert(note)
    try context.save()

    #expect(chart.rhythmMetadataData == nil)
    #expect(chart.safeControlEvents.isEmpty)

    let returned = try LocalDTXFixtureImporter.importSong(from: tempDir, into: context)

    #expect(returned === existing)
    #expect(returned.bgmFilePath == currentBGM.path)
    #expect(returned.previewFilePath == currentPreview.path)
    #expect(returned.duration == "9:59")
    #expect(returned.isServerImported == false)
    #expect(returned.bgmStartOffsetSeconds == 0.42)
    #expect(returned.charts.count == 1)
    #expect(returned.charts.first === chart)
    #expect(chart.safeNotes.count == 1)
    #expect(chart.safeNotes.first === note)
    #expect(chart.safeControlEvents.isEmpty)
    #expect(chart.rhythmMetadataData == nil)
    #expect(try context.fetch(FetchDescriptor<Song>()).count == 1)
    #expect(try context.fetch(FetchDescriptor<Chart>()).count == 1)
}
```

This fixture intentionally contains a control event the old repair path can populate, while also providing real current audio files that `refreshAudioPaths` should find.

Rename the existing nil-offset policy test and remove its legacy-upgrade framing:

```swift
@Test("re-import leaves an unset BGM start offset unset")
func reImportLeavesUnsetBGMStartOffsetUnset() throws {
    let context = TestContainer.isolatedContainer().context
    let fixtureURL = try soukyuuFixtureURL()
    let existing = Song(
        title: "蒼穹への翔歌",
        artist: "existing",
        bpm: 165.55,
        duration: "3:50",
        genre: "DTX Import",
        timeSignature: .fourFour,
        isServerImported: true,
        serverSongId: LocalDTXFixtureImporter.soukyuuSongId,
        bgmFilePath: fixtureURL.appendingPathComponent("bgm.m4a").path,
        previewFilePath: fixtureURL.appendingPathComponent("preview.mp3").path,
        bgmStartOffsetSeconds: nil
    )
    context.insert(existing)
    try context.save()

    let returned = try LocalDTXFixtureImporter.importSong(from: fixtureURL, into: context)

    #expect(returned === existing)
    #expect(returned.bgmStartOffsetSeconds == nil)
}
```

The non-nil offset case is folded into `reImportRefreshesOnlyAudioPaths`; delete the old separate non-clobber test after the new test is green.

- [ ] **Step 3: Run the focused suites and verify the intended RED signal.**

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

Expected before production changes:

- **FAIL:** `returned.duration == "9:59"`, because `refreshDurationIfStale` recomputes it.
- **FAIL:** `chart.safeControlEvents.isEmpty`, because `refreshControlEventsIfMissing` populates controls.
- **PASS already:** BGM/preview paths resolve to `currentBGM.path` / `currentPreview.path`; this behavior is retained.
- **PASS already:** `rhythmMetadataData == nil` in the direct importer path. This assertion pins the direct-import boundary but is not a RED signal; Task 2 removes the separate startup rhythm backfill.

Do not accept a RED run caused only by an unrelated fixture/setup failure. The two named historical-repair assertions are the expected failures.

- [ ] **Step 4: Simplify the existing-ID branch while keeping audio path resolution.**

In `LocalDTXFixtureImporter.swift`, remove `performLegacySourceRefreshes` from the private import function and all callers.

The existing-ID path becomes exactly:

```swift
if let existingSong = try existingSong(with: songId, in: context) {
    try refreshAudioPaths(for: existingSong, from: folderURL, in: context)
    return LocalDTXFixtureImportResult(song: existingSong, warnings: [])
}
```

Stop calling and delete `refreshDurationIfStale`.

Stop calling `refreshControlEventsIfMissing`, but leave its private body until Task 2, where the control/rhythm compatibility surface and its tests are deleted together.

This creates an **intentional one-checkpoint dead-code window** for `refreshControlEventsIfMissing`: it is private, uncalled, and scheduled for deletion in the immediately following task. Do not rewire it merely because it still exists after Task 1.

Keep `refreshAudioPaths` unchanged apart from removing obsolete `bgm.ogg` migration wording in its comments. Its contract is current path resolution/asset disappearance.

Do not add a replacement `refreshExistingSong`, graph diff, validation, or repair helper.

- [ ] **Step 5: Keep the custom `songId:` overload until Task 2.**

Do **not** delete:

```swift
static func importSong(from folderURL: URL, songId: String, into context: ModelContext) throws -> Song
```

in this checkpoint. Remaining control-backfill tests still use it; deleting it here would make Task 1 fail to compile before Task 2 rewrites/removes those callers.

- [ ] **Step 6: Rerun focused tests and verify GREEN.**

Run the Step 3 command again.

Expected:

- current audio paths re-resolve;
- removed current assets clear persisted paths;
- stale duration is unchanged;
- BGM start offset is not mutated for nil or non-nil states;
- repeated import does not add/replace charts or notes;
- source controls are not injected into the existing chart;
- no duplicate graph is created.

- [ ] **Step 7: Commit the checkpoint.**

```bash
git add Virgo/utilities/LocalDTXFixtureImporter.swift \
  VirgoTests/LocalDTXFixtureImporterTests.swift \
  VirgoTests/LocalDTXFixtureImporterCoverageTests.swift
git commit -m "refactor: limit fixture re-import to current audio paths"
```

---

## Task 2: Delete control/rhythm backfill and version state

**Files:**
- Modify: `Virgo/utilities/LocalDTXFixtureImporter.swift`
- Delete: `Virgo/utilities/RhythmBackfillVersionStore.swift`
- Modify/rename: `VirgoTests/LocalDTXControlBackfillTests.swift`
- Modify/rename: `VirgoTests/RhythmImportBackfillTests.swift`
- Modify: `VirgoTests/LocalDTXFixtureImporterTests.swift` if its comments name old suites
- Modify: `Virgo/views/ContentView.swift`
- Modify: `Virgo/utilities/ContentStartupPolicy.swift`

**Interfaces:**
- Consumes: Task 1's path-current/model-repair-free importer and current `DTXChartPersistenceProjection` fresh-import path.
- Produces: no import/startup control/rhythm upgrade API or UserDefaults version marker; current fresh projections remain the only persisted canonical rhythm source.

- [ ] **Step 1: Inventory backfill-only symbols and custom-ID callers.**

```bash
rg -n \
  'backfillBundledRhythmTimingIfNeeded|backfillRhythmTiming|RhythmBackfillVersion|RhythmBackfillPlan|RhythmBackfillCandidate|refreshControlEventsIfMissing|unmatchedRhythmBackfillChart|ambiguousRhythmBackfillChart|importSong\(.*songId:' \
  Virgo VirgoTests
```

Classify every hit as:

- production compatibility code to delete;
- compatibility test to delete;
- current behavior test to rewrite around fresh import/projection;
- remaining `songId:` convenience-overload caller to rewrite before deleting the overload.

Do **not** classify `RhythmTimelineResolver.resolveMissing` or `.legacy` runtime fallback as part of this deletion.

- [ ] **Step 2: Reduce control tests to fresh current import.**

In `LocalDTXControlBackfillTests.swift`, retain current behavior such as:

- fresh import populates `controlEvents`;
- multi-difficulty fresh import routes controls to the correct charts.

Delete compatibility contracts such as:

- missing-control re-import backfill;
- mixed-grid backfill;
- first-wins edited-control refresh;
- multi-difficulty backfill routing;
- MASTER/REAL backfill routing.

Rewrite retained calls that pass `songId: tempDir.lastPathComponent` merely to reproduce default identity:

```swift
try LocalDTXFixtureImporter.importSong(from: tempDir, into: context)
```

If the remaining file only covers current import, rename it narrowly:

```bash
git mv VirgoTests/LocalDTXControlBackfillTests.swift \
  VirgoTests/LocalDTXControlImportTests.swift
```

- [ ] **Step 3: Reduce rhythm tests to current projection/import behavior.**

In `RhythmImportBackfillTests.swift`, keep tests that directly protect current behavior:

- fresh-import rollback after save failure;
- canonical DTX projection timing;
- timing-fatal projection retaining source identity;
- downstream layout behavior that can be constructed from a fresh current projection.

Delete tests whose subject is:

- timing backfill selection;
- backfill version idempotence;
- unmatched/ambiguous legacy candidates;
- duplicate legacy source-backed chart upgrades.

If a useful layout test currently erases normalized fields and calls `backfillRhythmTiming` only as setup, stop erasing the current projection and assert downstream behavior from the fresh projection instead.

If “Backfill” is no longer accurate, rename:

```bash
git mv VirgoTests/RhythmImportBackfillTests.swift \
  VirgoTests/RhythmImportTests.swift
```

- [ ] **Step 4: Delete production backfill code and version state.**

From `LocalDTXFixtureImporter.swift`, delete:

- `refreshControlEventsIfMissing`;
- `backfillBundledRhythmTimingIfNeeded`;
- `backfillRhythmTiming`;
- `unmatchedRhythmBackfillChart` / `ambiguousRhythmBackfillChart` and descriptions;
- `RhythmBackfillPlan`;
- `RhythmBackfillCandidate`;
- `RhythmBackfillProjectionKey`;
- source-matching/sorting/apply helpers used only by backfill.

Keep `refreshAudioPaths` / `existingAudioPath`.

Delete:

```text
Virgo/utilities/RhythmBackfillVersionStore.swift
```

There is no replacement version marker.

- [ ] **Step 5: Remove startup timing backfill.**

In `ContentView.seedLocalDTXFixtures()`, reduce the success branch to current seed logging:

```swift
if let song {
    Logger.database("Seeded local DTX fixture: \(song.title)")
}
```

Delete the call to `backfillBundledRhythmTimingIfNeeded`.

In `ContentStartupPolicy.shouldImportBundledLocalDTXFixtures`, replace wording that promises historical refresh with the current contract: startup seeds when allowed; an existing stable-ID row may only re-resolve current audio paths.

- [ ] **Step 6: Delete the custom `songId:` overload only after its callers are gone.**

Run:

```bash
rg -n 'importSong\(.*songId:' Virgo VirgoTests
```

Expected: no current caller remains except the overload declaration itself.

Then delete:

```swift
static func importSong(from folderURL: URL, songId: String, into context: ModelContext) throws -> Song
```

- [ ] **Step 7: Verify backfill/version symbols are gone but runtime fallback remains.**

```bash
rg -n \
  'backfillBundledRhythmTimingIfNeeded|backfillRhythmTiming|RhythmBackfillVersion|RhythmBackfillPlan|RhythmBackfillCandidate|refreshControlEventsIfMissing|unmatchedRhythmBackfillChart|ambiguousRhythmBackfillChart' \
  Virgo VirgoTests
```

Expected: no hits.

Then:

```bash
rg -n 'func resolveMissing|availability: \.legacy' Virgo/utilities/RhythmTimelineResolver.swift
```

Expected: the current runtime fallback still exists. Do not remove it in HPA-577.

Do not add an assertion that `.legacy` is unavailable in `ChartPracticeState`; current code treats `.legacy` as non-fatal.

- [ ] **Step 8: Run retained fixture/rhythm suites.**

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

If a test file was not renamed, use its actual suite name instead of renaming solely for this command.

Expected: fresh import/projection behavior passes with audio path resolution intact and no backfill API.

- [ ] **Step 9: Commit the checkpoint.**

```bash
git add -A Virgo/utilities Virgo/views/ContentView.swift VirgoTests
git commit -m "refactor: delete local rhythm compatibility paths"
```

---

## Task 3: Remove startup database maintenance and legacy score migration

**Files:**
- Modify: `Virgo/views/ContentView.swift`
- Delete: `Virgo/services/DatabaseMaintenanceService.swift`
- Delete: `VirgoTests/DatabaseMaintenanceServiceTests.swift`
- Modify: `Virgo/services/ScorePersistenceService.swift`
- Modify: `VirgoTests/ScorePersistenceServiceTests.swift`

**Interfaces:**
- Consumes: current `ContentStartupPolicy`, current SwiftData score model and `recordAttempt` behavior.
- Produces: startup performs no historical local repair/score migration; current seed/reset bridge and current score writes/rollback remain unchanged.

- [ ] **Step 1: Delete the database-maintenance startup path.**

From `ContentView`, remove:

```swift
@State private var databaseService: DatabaseMaintenanceService?
```

and the block that constructs/calls `DatabaseMaintenanceService`.

Remove the post-maintenance chart re-fetch/comments that exist only because maintenance can delete rows.

Do not simplify `startupSongsOverride`; it still bridges synchronous UI-test/bundled seeding to the live `@Query`.

Delete:

```text
Virgo/services/DatabaseMaintenanceService.swift
VirgoTests/DatabaseMaintenanceServiceTests.swift
```

Do not move any repair method elsewhere.

- [ ] **Step 2: Delete the startup legacy-score scan.**

Remove the `FetchDescriptor<Chart>` + `migrateLegacyHighScores` block from `ContentView.onAppear`.

Normal startup must not scan charts for historical score data.

- [ ] **Step 3: Delete migration-only score code.**

From `ScorePersistenceService.swift`, delete:

```swift
private static let migrationFlagKey = "DidMigrateHighScoresToSwiftData"
private static let legacyHighScoreKey = "HighScorePerChart"
func migrateLegacyHighScores(...)
private func readLegacyScores(...)
```

Keep:

- `RecordResult`;
- `recordAttempt`;
- rollback of pending current score mutations on save failure;
- `bestScore`;
- `recentAttempts`;
- pruning;
- `makeInMemory`.

- [ ] **Step 4: Delete only legacy-score migration tests.**

In `ScorePersistenceServiceTests.swift`, remove tests for:

- normal legacy migration;
- migration flag/idempotence;
- no-data migration;
- NSNumber/non-numeric legacy parsing;
- lower/stale legacy score behavior;
- migration save-failure rollback.

Keep current `recordAttempt` save-failure rollback tests.

- [ ] **Step 5: Prove the deleted startup APIs are absent.**

```bash
rg -n \
  'DatabaseMaintenanceService|performInitialMaintenance|migrateLegacyHighScores|HighScorePerChart|DidMigrateHighScoresToSwiftData' \
  Virgo VirgoTests
```

Expected: no hits.

This source-symbol gate plus compilation proves the historical startup path is gone. Do not add a production startup seam or source-parser test solely to prove absence of deleted code.

- [ ] **Step 6: Run current score and startup-policy unit coverage.**

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

Expected: current score/history and startup policy remain green.

`AppShellCoverageTests` guards retained startup decisions; Step 5 plus successful compilation is the proof that maintenance/migration code is absent.

- [ ] **Step 7: Run the existing macOS UI-test target against the startup rewrite.**

The repository has a separate PR workflow for `VirgoUITests`, and those tests launch with `-UITesting` / `-ResetState`. Match that workflow instead of relying only on unit coverage.

Build for testing:

```bash
xcodebuild build-for-testing \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'platform=macOS' \
  -configuration Debug \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO
```

Then run:

```bash
xcodebuild test-without-building \
  -project Virgo.xcodeproj \
  -scheme Virgo \
  -destination 'platform=macOS' \
  -configuration Debug \
  -parallel-testing-enabled NO \
  -only-testing:VirgoUITests \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  -enableCodeCoverage YES \
  -destination-timeout 600
```

Expected: all existing `VirgoUITests` pass, including reset/seed navigation and gameplay BGM-failure flows.

- [ ] **Step 8: Commit the checkpoint.**

```bash
git add -A Virgo/views/ContentView.swift Virgo/services VirgoTests
git commit -m "refactor: delete startup and score compatibility"
```

---

## Task 4: Make practice-setting keys current-format-only

**Files:**
- Modify: `Virgo/services/PracticeSettingsService.swift`
- Modify: `Virgo/utilities/PersistentIdentifierPersistenceKey.swift`
- Modify: `VirgoTests/PracticeSettingsServiceTests.swift`
- Modify: `VirgoTests/CollectionAndLayoutExtensionTests.swift`
- Modify: `VirgoTests/SwiftDataRelationshipLoaderTests.swift`

**Interfaces:**
- Consumes: `PersistentIdentifierPersistenceKey.canonicalKey(for:logPrefix:)`, current numeric UserDefaults writer.
- Produces: exact current canonical-key lookup only; historical key encodings are ignored rather than migrated.

- [ ] **Step 1: Replace the legacy-key migration test with a breaking-policy test.**

Delete `makeLegacyPersistenceKey(...)` and `addWhitespaceOutsideStrings(...)` from `PracticeSettingsServiceTests.swift`.

Add:

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

Expected against current code: RED because `resolve(...)` normalizes/migrates the historical key.

- [ ] **Step 2: Verify RED.**

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

- [ ] **Step 3: Simplify `PracticeSettingsService.loadSpeed`.**

Replace resolver/migration logic with exact lookup:

```swift
let key = persistenceKey(for: chartID)
guard let savedSpeed = readPersistedSpeeds()[key] else {
    return 1.0
}
```

Keep finite/range validation and `sessionSpeedCache`.

In `readPersistedSpeeds()`, keep current numeric decoding:

```swift
if let doubleValue = value as? Double {
    speeds[key] = doubleValue
} else if let numberValue = value as? NSNumber {
    speeds[key] = numberValue.doubleValue
}
```

Delete the `String -> Double` branch because the current writer stores numeric values.

Update `testLoadSpeedDecodesNSNumberAndStringValues` into an NSNumber/current-numeric-representation test; remove the string payload assertion.

- [ ] **Step 4: Reduce `PersistentIdentifierPersistenceKey` to current key generation.**

Keep:

```swift
static func canonicalKey(for identifier: PersistentIdentifier, logPrefix: String) -> String
```

Delete:

```swift
Resolution<Value>
resolve(...)
normalizeJSONKey(...)
```

Do not add another resolver.

- [ ] **Step 5: Delete resolver-only tests.**

Remove `PersistentIdentifierPersistenceKey.Resolution` test suites from:

- `VirgoTests/CollectionAndLayoutExtensionTests.swift`;
- `VirgoTests/SwiftDataRelationshipLoaderTests.swift`.

Update only those files' header comments as needed; leave unrelated tests untouched.

- [ ] **Step 6: Verify compatibility symbols are gone.**

```bash
rg -n \
  'PersistentIdentifierPersistenceKey\.resolve|needsMigration|matchedKey|normalizeJSONKey|loadSpeedMigratesLegacy|makeLegacyPersistenceKey' \
  Virgo VirgoTests
```

Expected: no hits.

- [ ] **Step 7: Run current practice/utility suites.**

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

Expected: current canonical settings round-trip; historical variants are ignored.

- [ ] **Step 8: Commit the checkpoint.**

```bash
git add Virgo/services/PracticeSettingsService.swift \
  Virgo/utilities/PersistentIdentifierPersistenceKey.swift \
  VirgoTests/PracticeSettingsServiceTests.swift \
  VirgoTests/CollectionAndLayoutExtensionTests.swift \
  VirgoTests/SwiftDataRelationshipLoaderTests.swift
git commit -m "refactor: remove persistence key compatibility"
```

---

## Task 5: Update live guidance and perform final current-format audit

**Files:**
- Modify: `CLAUDE.md`
- Modify only if needed: comments adjacent to touched production/tests
- Do not modify: `AGENTS.md` separately (symlink to `CLAUDE.md`)
- Do not sweep: historical files under `docs/superpowers/specs`, `docs/superpowers/plans`, or `docs/Project_Architecture_Blueprint.md`

**Interfaces:**
- Consumes: Tasks 1–4 final production surface and Task 3's UI-test evidence.
- Produces: live agent guidance matches the code; removed compatibility is absent; retained audio-path/runtime-fallback behavior remains; full macOS unit/iPad verification passes.

- [ ] **Step 1: Remove stale live API guidance from `CLAUDE.md`.**

In **Rhythm & Notation Pipeline**, replace the paragraph that says `RhythmBackfillVersionStore` gates one-time normalization with current policy, e.g.:

```markdown
Normalized tick fields are persisted on `Note` and `ChartControlEvent` during current DTX import.
Virgo does not backfill older imported development rows after representation changes; reset/reseed
local development data instead. Runtime missing-metadata fallback remains separate from import-time
backfill. `RhythmMetronomeSchedule` derives the metronome schedule from the same timeline.
```

In **Services Layer**:

- delete the `DatabaseMaintenanceService` bullet;
- change the `ScorePersistenceService` bullet so it describes current `ScoreRecord`, recent attempts, and full-speed best-score behavior only;
- remove the claim that it migrates `HighScorePerChart`.

For local fixture guidance, keep the current rule that BGM/preview paths may be re-resolved from current assets, but remove historical `bgm.ogg -> bgm.m4a` migration framing where it is presented as live architecture.

Do not edit `AGENTS.md` separately.

- [ ] **Step 2: Audit removed compatibility concepts.**

```bash
rg -n \
  'DatabaseMaintenanceService|performInitialMaintenance|migrateLegacyHighScores|HighScorePerChart|DidMigrateHighScoresToSwiftData|performLegacySourceRefreshes|refreshDurationIfStale|refreshControlEventsIfMissing|backfillBundledRhythmTimingIfNeeded|backfillRhythmTiming|RhythmBackfillVersion(Store|Storing)|PersistentIdentifierPersistenceKey\.resolve|needsMigration' \
  Virgo VirgoTests CLAUDE.md
```

Expected: no hits.

`refreshAudioPaths` is intentionally **not** in this removal search.

Verify it remains:

```bash
rg -n 'refreshAudioPaths|existingAudioPath' \
  Virgo/utilities/LocalDTXFixtureImporter.swift VirgoTests/LocalDTXFixtureImporterTests.swift
```

Expected: production path resolution and current tests still reference the retained behavior.

Verify runtime fallback remains:

```bash
rg -n 'func resolveMissing|availability: \.legacy' Virgo/utilities/RhythmTimelineResolver.swift
```

Expected: hits remain.

- [ ] **Step 3: Search for stale live promises and review manually.**

```bash
rg -n 'self-healing refresh|legacy .*backfill|upgrade path|bgm\.ogg.*bgm\.m4a' \
  Virgo VirgoTests CLAUDE.md
```

Reword/delete only statements that describe removed HPA-577 upgrade behavior. Do not sweep historical docs.

- [ ] **Step 4: Confirm HPA-578 server-download fallback was not pulled into this diff.**

```bash
git diff --exit-code main...HEAD -- Virgo/utilities/ServerSongDownloader.swift
```

Expected: no diff for `ServerSongDownloader.swift`.

- [ ] **Step 5: Check the implementation remains deletion-first.**

```bash
git diff --stat main...HEAD
git diff --check main...HEAD
```

Expected:

- substantially more historical compatibility code/tests removed than replacement code added;
- `refreshAudioPaths` remains small and local;
- no whitespace errors;
- no new migration/version/dedup abstraction.

- [ ] **Step 6: Run the complete macOS unit suite used by CI.**

Generate local endpoint config if needed using the repository's existing script/environment, then run:

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

Task 3 already ran the complete `VirgoUITests` target after the startup rewrite. If Tasks 4–5 unexpectedly modify `ContentView`, launch arguments, seed/reset behavior, or UI-facing gameplay startup, rerun the Task 3 UI-test command before completion. Otherwise do not pay for a duplicate full UI run.

- [ ] **Step 7: Build the iPad Simulator target used by CI.**

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

- [ ] **Step 8: Run a clean/reset-store smoke.**

Using a clean development store/UserDefaults or the existing UI-test reset path, verify:

1. launch from clean/reset state;
2. bundled Soukyuu fixture seeds once when allowed;
3. relaunch does not duplicate it;
4. delete the bundled fixture and relaunch; it remains deleted;
5. clear/reset test state; the bundled fixture can seed again;
6. play a chart and record a score; current `ScoreRecord`/`bestScore` behavior works;
7. save/reload a practice speed using the current canonical key.

Do not test preservation of historical model data. Audio filesystem paths are the explicit exception: repeated fixture import may update them to current assets.

- [ ] **Step 9: Update the implementation PR description.**

State explicitly:

- old local development SwiftData/UserDefaults representation may require reset;
- no migration/recovery framework was added;
- stable-ID local re-import re-resolves only BGM/preview filesystem paths and otherwise does not repair the persisted graph;
- `refreshAudioPaths` was intentionally retained because absolute paths are consumed directly;
- HPA-578 still owns `ServerSongDownloader` title/artist fallback removal;
- `RhythmTimelineResolver.resolveMissing` / `.legacy` runtime fallback remains out of scope;
- `CLAUDE.md` live guidance was updated for deleted APIs;
- focused RED assertions, macOS unit/UI test results, and iPad build results.

- [ ] **Step 10: Commit final narrow guidance cleanup.**

```bash
git add CLAUDE.md Virgo VirgoTests
git commit -m "docs: align guidance with current persistence model"
```

Skip this commit only if no file changed in Task 5; based on current main, `CLAUDE.md` does require changes.

---

## Definition of Done

- [ ] `ContentView` has no normal-startup historical repair/migration pass.
- [ ] `DatabaseMaintenanceService` is deleted, not relocated.
- [ ] Legacy score migration and legacy practice-key resolution are deleted.
- [ ] Local fixture re-import retains `refreshAudioPaths` and does not repair duration/identity/graph/rhythm data.
- [ ] Current audio-path relocation and asset-removal behavior remains tested.
- [ ] The Task 1 RED run fails specifically on duration repair and control-event backfill before production changes, then passes after removal.
- [ ] BGM start offset non-clobbering remains covered for nil and non-nil states.
- [ ] Fresh local import remains transactional and writes the full current representation.
- [ ] Rhythm/control backfill and its UserDefaults version marker are deleted.
- [ ] `RhythmTimelineResolver.resolveMissing` / `.legacy` runtime fallback remains untouched.
- [ ] The custom `importSong(from:songId:into:)` overload is deleted only after Task 2 removes/reworks its remaining callers.
- [ ] Bundled-fixture deletion/reset behavior remains intact.
- [ ] Current score save-failure rollback remains intact.
- [ ] Current practice settings persist through the canonical key; historical key variants are ignored.
- [ ] `CLAUDE.md` no longer teaches `DatabaseMaintenanceService`, `RhythmBackfillVersionStore`, or `HighScorePerChart` migration as live architecture.
- [ ] `ServerSongDownloader.swift` is unchanged; HPA-578 remains the owner of server-import title/artist fallback removal.
- [ ] Compatibility-only tests are deleted; retained tests describe current behavior.
- [ ] No replacement migration/dedup/version abstraction appears in the diff.
- [ ] Full macOS unit tests pass with parallel testing disabled.
- [ ] Existing macOS `VirgoUITests` pass after the startup rewrite.
- [ ] iPad Simulator build passes.
- [ ] PR notes the intentional breaking local-data policy and the retained current audio-path exception.
