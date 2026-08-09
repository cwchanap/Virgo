# HPA-577 Current-Format-Only Persistence Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Delete Virgo's pre-release startup/persistence compatibility paths so the app supports only data written by the current build while preserving fresh fixture import, current score/history persistence, current practice settings, bundled-fixture deletion, and UI-test reset/seeding.

**Architecture:** Keep the existing owners (`ContentView`, `LocalDTXFixtureImporter`, `ScorePersistenceService`, `PracticeSettingsService`) and remove upgrade behavior from them. Stable IDs provide narrow idempotence: a matching existing local fixture row and graph are returned unchanged. Do not replace removed compatibility with migration/version/dedup infrastructure.

**Tech Stack:** Swift, SwiftUI, SwiftData, Swift Testing, Xcode 26.1.1, `xcodebuild`.

**Design:** `docs/superpowers/specs/2026-08-09-hpa-577-current-format-only-persistence-design.md`

## Global Constraints

- Breaking local SwiftData/UserDefaults changes are accepted. Old development data may be reset.
- Do not add schema/version registries, migration coordinators, compatibility adapters, generic deduplication, or automatic destructive production reset.
- Keep `ContentView` as the startup composition point; do not create a startup coordinator/use-case layer.
- Keep `LocalDTXFixtureImporter` as the local fixture owner; do not create a fixture repository/reconciliation engine.
- Keep current save-failure handling for fresh imports and current scores. Failure recovery for current writes is not backward compatibility.
- Keep `BundledFixtureDeletionStore`; durable user deletion of the bundled demo is current product behavior.
- `ServerSongDownloader.songAlreadyExists` title/artist fallbacks are **not HPA-577 work**. HPA-578 explicitly owns deleting them and making `serverSongId` the current server-import identity contract.
- Do not change server catalog refresh behavior (HPA-578), performance/actor placement (HPA-579/HPA-580), server BGM format work (HPA-85), or broad historical documentation/test consolidation (HPA-583).
- Update only live `CLAUDE.md` guidance that becomes false because this ticket deletes production APIs. `AGENTS.md` is a symlink to `CLAUDE.md`; do not edit both.
- Run macOS tests with `-parallel-testing-enabled NO`, matching CI.
- The Xcode project uses file-system-synchronized groups. Do not hand-edit `Virgo.xcodeproj/project.pbxproj` for file deletions/renames unless a build proves it is required.

---

## Task 1: Collapse local fixture re-import to stable-ID identity

**Files:**
- Modify: `Virgo/utilities/LocalDTXFixtureImporter.swift`
- Modify: `VirgoTests/LocalDTXFixtureImporterTests.swift`
- Modify: `VirgoTests/LocalDTXFixtureImporterCoverageTests.swift`

**Interfaces:**
- Consumes: existing `LocalDTXFixtureImporter.importSong(from:into:)`, `existingSong(with:in:)`, current DTX parser/projection.
- Produces: repeated import for the same `serverSongId` returns the existing `Song` and existing graph unchanged; fresh import behavior is unchanged.
- Deferred to Task 2: deleting `importSong(from:songId:into:)`. Keep it temporarily because `LocalDTXControlBackfillTests.swift` still has callers.

- [ ] **Step 1: Replace song-only repair tests with one graph-level no-repair regression.**

In `VirgoTests/LocalDTXFixtureImporterTests.swift`, add a deterministic temporary fixture whose source is capable of creating rhythm/control data:

```swift
@Test("re-import by stable ID returns the existing graph without repair")
func reImportByStableIDDoesNotRepairExistingGraph() throws {
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

    let staleBGM = "/legacy/bgm.ogg"
    let existing = Song(
        title: "Legacy Local State",
        artist: "Legacy Artist",
        bpm: 90,
        duration: "9:59",
        genre: "DTX Import",
        timeSignature: .fourFour,
        isServerImported: false,
        serverSongId: tempDir.lastPathComponent,
        bgmFilePath: staleBGM,
        previewFilePath: "/legacy/preview.mp3"
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
    #expect(returned.duration == "9:59")
    #expect(returned.bgmFilePath == staleBGM)
    #expect(returned.previewFilePath == "/legacy/preview.mp3")
    #expect(returned.isServerImported == false)
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

This source contains a control event and valid current DTX data. The test therefore proves that re-import deliberately does **not** fill missing graph data.

Remove/fold tests whose desired result is specifically historical repair:

- `refreshesStaleSoukyuuAudioPathsWhenAlreadyImported`
- `refreshClearsStaleAudioPathsWhenAssetsRemoved`
- `reImportRefreshesStaleDuration`
- `reImportLeavesMissingLegacyBGMStartOffsetUntouched`
- `reImportDoesNotClobberExistingBGMStartOffset`

Keep fresh-import correctness tests and simple stable-ID duplicate prevention.

In `LocalDTXFixtureImporterCoverageTests.swift`:

- rename the “existing record marked deleted is refreshed” test to describe returning the existing stable-ID record;
- assert identity/current tombstone semantics only;
- delete the unreadable-SET refresh-path test because an existing stable-ID row should no longer decode `SET.def`.

- [ ] **Step 2: Run the focused suites and verify RED.**

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

Expected: the graph-level policy test fails because current re-import refreshes stale song fields and can populate missing controls.

- [ ] **Step 3: Make the existing-ID branch return immediately.**

Simplify the private `importSongResult` path so the existing-ID branch is exactly:

```swift
if let existingSong = try existingSong(with: songId, in: context) {
    return LocalDTXFixtureImportResult(song: existingSong, warnings: [])
}
```

Remove `performLegacySourceRefreshes` from the private function signature/callers.

Stop calling:

```swift
refreshAudioPaths(...)
refreshDurationIfStale(...)
refreshControlEventsIfMissing(...)
```

Delete `refreshAudioPaths` and `refreshDurationIfStale` now if they have no caller. `refreshControlEventsIfMissing` may remain temporarily as dead compatibility code until Task 2 deletes the whole control/rhythm backfill surface.

Do not add a replacement `refreshExistingSong`, diff, validation, or repair helper.

- [ ] **Step 4: Keep the custom `songId:` overload until Task 2.**

Do **not** delete:

```swift
static func importSong(from folderURL: URL, songId: String, into context: ModelContext) throws -> Song
```

in this checkpoint. `LocalDTXControlBackfillTests.swift` still uses it; deleting it here would make Task 1 fail to compile before Task 2 rewrites/removes those callers.

- [ ] **Step 5: Rerun focused tests and verify GREEN.**

Run the Step 2 command again.

Expected:

- fresh import still persists current data;
- repeated stable-ID import returns unchanged song/chart/note state;
- source controls are not injected into the existing chart;
- no duplicate graph is created.

- [ ] **Step 6: Commit the checkpoint.**

```bash
git add Virgo/utilities/LocalDTXFixtureImporter.swift \
  VirgoTests/LocalDTXFixtureImporterTests.swift \
  VirgoTests/LocalDTXFixtureImporterCoverageTests.swift
git commit -m "refactor: make local fixture re-import identity only"
```

---

## Task 2: Delete control/rhythm backfill and version state

**Files:**
- Modify: `Virgo/utilities/LocalDTXFixtureImporter.swift`
- Delete: `Virgo/utilities/RhythmBackfillVersionStore.swift`
- Modify/rename: `VirgoTests/LocalDTXControlBackfillTests.swift`
- Modify/rename: `VirgoTests/RhythmImportBackfillTests.swift`
- Modify: `VirgoTests/LocalDTXFixtureImporterTests.swift` if its comments name the old suites
- Modify: `Virgo/views/ContentView.swift`
- Modify: `Virgo/utilities/ContentStartupPolicy.swift`

**Interfaces:**
- Consumes: Task 1's identity-only importer and current `DTXChartPersistenceProjection` fresh-import path.
- Produces: no local control/rhythm upgrade API or UserDefaults version marker; current fresh projections remain the only persisted rhythm source.

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

- [ ] **Step 2: Reduce control tests to current fresh-import behavior.**

In `LocalDTXControlBackfillTests.swift`, retain current behavior such as:

- fresh import populates `controlEvents`;
- multi-difficulty fresh import routes controls to the correct chart;
- any other test whose setup begins from a current DTX source and does not require an existing legacy row.

Delete compatibility contracts such as:

- missing-control re-import backfill;
- mixed-grid backfill;
- first-wins edited-control refresh;
- multi-difficulty backfill routing;
- MASTER/REAL backfill routing.

Rewrite any retained `songId: tempDir.lastPathComponent` call that merely duplicates default identity to:

```swift
try LocalDTXFixtureImporter.importSong(from: tempDir, into: context)
```

If the remaining file only covers current import, rename it:

```bash
git mv VirgoTests/LocalDTXControlBackfillTests.swift \
  VirgoTests/LocalDTXControlImportTests.swift
```

- [ ] **Step 3: Reduce rhythm tests to current projection/import behavior.**

In `RhythmImportBackfillTests.swift`, keep tests that directly protect current behavior, including:

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

- [ ] **Step 4: Delete production backfill code.**

From `LocalDTXFixtureImporter.swift`, delete:

- `refreshControlEventsIfMissing`;
- `backfillBundledRhythmTimingIfNeeded`;
- `backfillRhythmTiming`;
- `unmatchedRhythmBackfillChart` / `ambiguousRhythmBackfillChart` and descriptions;
- `RhythmBackfillPlan`;
- `RhythmBackfillCandidate`;
- `RhythmBackfillProjectionKey`;
- source-matching/sorting/apply helpers used only by backfill.

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

In `ContentStartupPolicy.shouldImportBundledLocalDTXFixtures`, replace wording that promises refresh of old rows with the current contract: startup seeds when allowed; an existing stable-ID row is returned unchanged.

- [ ] **Step 6: Delete the custom `songId:` overload only now.**

After Steps 2–5, run:

```bash
rg -n 'importSong\(.*songId:' Virgo VirgoTests
```

Expected: no current caller remains except the overload declaration itself.

Then delete:

```swift
static func importSong(from folderURL: URL, songId: String, into context: ModelContext) throws -> Song
```

Do not keep an unused overload solely for removed compatibility tests.

- [ ] **Step 7: Verify backfill/version symbols are gone.**

```bash
rg -n \
  'backfillBundledRhythmTimingIfNeeded|backfillRhythmTiming|RhythmBackfillVersion|RhythmBackfillPlan|RhythmBackfillCandidate|refreshControlEventsIfMissing|unmatchedRhythmBackfillChart|ambiguousRhythmBackfillChart' \
  Virgo VirgoTests
```

Expected: no hits.

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

If a test file was not renamed because its retained scope still justifies the old name, use its actual suite name instead of renaming solely for this command.

Expected: fresh import/projection behavior passes without any backfill API.

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
- Produces: startup performs no historical local repair/score migration; current score writes and rollback semantics remain unchanged.

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

This source-symbol gate plus compilation is the proof that the old startup path is gone. Do not add a production startup seam or source-parser test merely to prove absence of deleted code.

- [ ] **Step 6: Run current score and startup-policy coverage.**

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

`AppShellCoverageTests` is a regression check for retained startup decisions, **not** the proof of maintenance deletion; Step 5 plus successful compilation provides that proof.

- [ ] **Step 7: Commit the checkpoint.**

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

Update `testLoadSpeedDecodesNSNumberAndStringValues` into an NSNumber/numeric-current-representation test; remove the string payload assertion.

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

## Task 5: Update live guidance and verify current-format-only behavior

**Files:**
- Modify: `CLAUDE.md`
- Modify only if needed: comments adjacent to touched production/tests
- Do not modify: `AGENTS.md` separately (symlink to `CLAUDE.md`)
- Do not sweep: historical files under `docs/superpowers/specs`, `docs/superpowers/plans`, or `docs/Project_Architecture_Blueprint.md`

**Interfaces:**
- Consumes: Tasks 1–4 final production surface.
- Produces: always-on agent guidance matches the live code; full macOS/iPad verification passes; HPA-578 server-download fallback remains untouched.

- [ ] **Step 1: Remove stale live API guidance from `CLAUDE.md`.**

In **Rhythm & Notation Pipeline**, replace the paragraph that says `RhythmBackfillVersionStore` gates one-time normalization with current policy, e.g.:

```markdown
Normalized tick fields are persisted on `Note` and `ChartControlEvent` during current DTX import.
Virgo does not backfill older imported development rows after representation changes; reset/reseed
local development data instead. `RhythmMetronomeSchedule` derives the metronome schedule from the
same timeline, so timing changes affect audio and notation together.
```

In **Services Layer**:

- delete the `DatabaseMaintenanceService` bullet;
- change the `ScorePersistenceService` bullet so it describes current `ScoreRecord`, recent attempts, and full-speed best-score behavior only;
- remove the claim that it migrates `HighScorePerChart`.

Do not edit `AGENTS.md` separately; repository guidance states it is a symlink to `CLAUDE.md`.

- [ ] **Step 2: Audit removed concepts in live code/tests/guidance.**

```bash
rg -n \
  'DatabaseMaintenanceService|performInitialMaintenance|migrateLegacyHighScores|HighScorePerChart|DidMigrateHighScoresToSwiftData|performLegacySourceRefreshes|refreshAudioPaths|refreshDurationIfStale|refreshControlEventsIfMissing|backfillBundledRhythmTimingIfNeeded|backfillRhythmTiming|RhythmBackfillVersion(Store|Storing)|PersistentIdentifierPersistenceKey\.resolve|needsMigration' \
  Virgo VirgoTests CLAUDE.md
```

Expected: no hits.

Then search for stale live promises:

```bash
rg -n 'self-healing refresh|legacy .*backfill|refresh(es|ed|ing)? .*fixture|upgrade path' \
  Virgo VirgoTests CLAUDE.md
```

Review each hit manually and reword/delete only if it describes HPA-577 behavior that no longer exists.

Do **not** run this as a historical-doc cleanup over `docs/`; HPA-583 owns that work.

- [ ] **Step 3: Confirm the HPA-578 residual was not accidentally pulled into this diff.**

```bash
git diff --exit-code main...HEAD -- Virgo/utilities/ServerSongDownloader.swift
```

Expected: no diff for `ServerSongDownloader.swift`.

The current title/artist fallback is intentionally left for HPA-578, whose scope explicitly deletes it.

- [ ] **Step 4: Check the implementation remains deletion-first.**

```bash
git diff --stat main...HEAD
git diff --check main...HEAD
```

Expected:

- substantially more compatibility code/tests removed than replacement code added;
- no whitespace errors;
- no new migration/version/dedup abstraction.

If the implementation adds a framework comparable in size to what it deletes, simplify before continuing.

- [ ] **Step 5: Run the complete macOS unit suite used by CI.**

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

- [ ] **Step 6: Build the iPad Simulator target used by CI.**

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

- [ ] **Step 7: Run a clean/reset-store smoke.**

Using a clean development store/UserDefaults or the existing UI-test reset path, verify:

1. launch from clean/reset state;
2. bundled Soukyuu fixture seeds once when allowed;
3. relaunch does not duplicate it;
4. delete the bundled fixture and relaunch; it remains deleted;
5. clear/reset test state; the bundled fixture can seed again;
6. play a chart and record a score; current `ScoreRecord`/`bestScore` behavior works;
7. save/reload a practice speed using the current canonical key.

Do not test preservation of data from an old build; HPA-577 explicitly drops that contract.

- [ ] **Step 8: Update the implementation PR description.**

State explicitly:

- old local development SwiftData/UserDefaults may require reset;
- no migration/recovery framework was added;
- stable-ID local re-import returns existing song **and graph** unchanged;
- HPA-578 still owns `ServerSongDownloader` title/artist fallback removal;
- `CLAUDE.md` live guidance was updated for deleted APIs;
- macOS tests and iPad build results.

- [ ] **Step 9: Commit any final narrow cleanup.**

```bash
git add CLAUDE.md Virgo VirgoTests
git commit -m "docs: align guidance with current persistence model"
```

Skip this commit only if `CLAUDE.md` and adjacent live comments required no changes; based on current main, `CLAUDE.md` does require changes.

---

## Definition of Done

- [ ] `ContentView` has no normal-startup historical repair/migration pass.
- [ ] `DatabaseMaintenanceService` is deleted, not relocated.
- [ ] Legacy score migration and legacy practice-key resolution are deleted.
- [ ] Local fixture re-import is stable-ID identity only for both song fields and the existing graph.
- [ ] The graph-level regression proves controls/rhythm/chart/note state are not repaired on re-import.
- [ ] Fresh local import remains transactional and writes the full current representation.
- [ ] Rhythm/control backfill and its UserDefaults version marker are deleted.
- [ ] The custom `importSong(from:songId:into:)` overload is deleted only after Task 2 removes/reworks its remaining callers.
- [ ] Bundled-fixture deletion/reset behavior remains intact.
- [ ] Current score save-failure rollback remains intact.
- [ ] Current practice settings persist through the canonical key; historical key variants are ignored.
- [ ] `CLAUDE.md` no longer teaches `DatabaseMaintenanceService`, `RhythmBackfillVersionStore`, or `HighScorePerChart` migration as live architecture.
- [ ] `ServerSongDownloader.swift` is unchanged; HPA-578 remains the owner of server-import title/artist fallback removal.
- [ ] Compatibility-only tests are deleted; retained tests describe current behavior.
- [ ] No replacement migration/dedup/version abstraction appears in the diff.
- [ ] Full macOS unit tests pass with parallel testing disabled.
- [ ] iPad Simulator build passes.
- [ ] PR notes the intentional breaking local-data policy.