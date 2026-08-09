# HPA-577: Current-Format-Only Startup and Persistence

**Date:** 2026-08-09  
**Status:** Draft design for review — implementation not started

## Context

Virgo is still pre-release and has no production user data that must survive breaking local-format changes. HPA-577 therefore adopts the roadmap's current-format-only policy: SwiftData stores and UserDefaults created by older development builds may be deleted/reset instead of migrated or repaired.

The current code still carries several upgrade paths from earlier development iterations:

- `ContentView` creates `DatabaseMaintenanceService` on normal startup and runs historical `Song`/`Chart` repair passes.
- `ContentView` fetches every `Chart` at startup to migrate `HighScorePerChart` UserDefaults into SwiftData.
- `LocalDTXFixtureImporter` treats re-import as a repair opportunity for stale audio paths, stale duration, missing control events, and missing rhythm metadata.
- `RhythmBackfillVersionStore` persists a one-time timing-backfill version in UserDefaults.
- `PersistentIdentifierPersistenceKey.resolve` recognizes non-canonical historical key encodings and rewrites them; `PracticeSettingsService` still uses that compatibility path.

Those paths are useful only if old local state must be preserved. Keeping them makes startup and importer behavior harder to reason about, expands the test surface, and encourages new compatibility code whenever the current representation changes.

HPA-577 should remove that policy, not replace it with a different migration framework.

## Decision summary

Support exactly one representation: the representation written by the current build.

- Normal startup does not inspect or repair old data.
- Current bundled/local fixture import remains idempotent by stable `serverSongId`.
- Re-import of an already-present stable ID returns the existing row unchanged; it does not repair it.
- A fresh fixture import writes the complete current `Song`/`Chart`/`Note`/`ChartControlEvent` graph in one transaction.
- Scores use only current SwiftData `ScoreRecord` + `Chart.bestScore` persistence.
- Per-chart practice settings read/write only the current canonical persistence key.
- Old development stores/settings that do not match the current representation are reset manually or by the existing test reset path.

This is intentionally deletion-first. Do not add schema versions, compatibility adapters, generalized deduplication, or automatic store reset detection.

## Approaches considered

### A. Disable compatibility at startup but leave the old code in place

Remove the calls from `ContentView`, but keep `DatabaseMaintenanceService`, fixture refresh/backfill helpers, migration resolvers, and their tests.

**Pros**

- Smallest immediate production diff.
- Easy to restore an old migration temporarily.

**Cons**

- Leaves dead behavior and dead tests that still cost maintenance time.
- Future contributors can accidentally call the compatibility code again.
- Does not satisfy HPA-577's deletion-first goal.

**Decision:** Reject.

### B. Delete compatibility paths and keep only current-format idempotence

Remove old repair/migration behavior while preserving current-format creation, stable-ID lookup, test reset/seeding, and current persistence APIs.

**Pros**

- Smallest long-term architecture.
- Makes startup and importer behavior deterministic.
- Matches the roadmap guardrail that breaking development data is acceptable.
- Reduces tests by deleting behavior the product no longer supports.

**Cons**

- A developer with an old local store may need to delete/reset it.
- Re-import no longer self-heals a stale persisted fixture row.

**Decision:** Recommended and selected.

### C. Detect stale data and automatically reset/reseed it

Introduce a store/version marker and automatically clear/recreate incompatible state.

**Pros**

- Smoother transition between development builds.

**Cons**

- Reintroduces the exact version/migration coordination HPA-577 is intended to remove.
- Adds state and failure modes for a pre-release application with disposable local data.
- Creates pressure to preserve the mechanism indefinitely.

**Decision:** Reject.

## Goals

1. Remove historical maintenance from the normal startup path.
2. Make local fixture import current-format-only and stable-ID idempotent.
3. Remove legacy score migration and persistence-key migration behavior.
4. Delete tests/helpers whose only purpose is preserving old local representations.
5. Keep fresh/reset-store behavior and current user-facing persistence behavior intact.

## Non-goals

- No SwiftData schema/migration framework.
- No automatic incompatible-store detection or destructive production reset.
- No generic song deduplication or title/artist normalization.
- No redesign of `ScorePersistenceService`, `PracticeSettingsService`, `ContentView`, or SwiftData ownership.
- No server catalog refresh redesign; HPA-578 owns that work.
- No off-main parsing/performance work; HPA-579/HPA-580 own that decision.
- No broad test-suite/documentation consolidation; HPA-583 owns the final cleanup pass.
- No server BGM format work; HPA-85 remains separate.

## Design

### 1. Remove the startup upgrade pipeline

`ContentView.onAppear` should retain only startup work that serves the current build:

- UI-test reset/seed policy.
- bundled current-format fixture seed.
- `ServerSongService` model-context setup and catalog load.
- the existing short-lived `startupSongsOverride` used to bridge synchronous seed/reset work to the live `@Query`.

Delete:

- `@State private var databaseService: DatabaseMaintenanceService?`;
- creation/invocation of `DatabaseMaintenanceService`;
- the post-maintenance chart re-fetch;
- `ScorePersistenceService.migrateLegacyHighScores(...)` startup invocation and its error branch;
- comments that describe startup maintenance/migration.

Do **not** extract a startup coordinator merely to make this deletion look architectural. The existing `ContentStartupPolicy` is sufficient.

`DatabaseMaintenanceService.swift` is then unused and should be deleted together with `DatabaseMaintenanceServiceTests.swift`.

The removed service behavior is not replaced:

- `genre == "DTX Import"` is no longer backfilled into `isServerImported`;
- `Chart.level == 50` is no longer rewritten by difficulty;
- duplicate songs are not repaired by normalized title/artist matching;
- the sample cleanup no-op disappears.

Current creators are responsible for writing valid current data.

### 2. Make fixture re-import identity-only

`LocalDTXFixtureImporter` already has the correct narrow identity boundary: `serverSongId`.

Keep the lookup:

```swift
private static func existingSong(with songId: String, in context: ModelContext) throws -> Song?
```

When it finds an existing row, return that row immediately:

```swift
if let existingSong = try existingSong(with: songId, in: context) {
    return LocalDTXFixtureImportResult(song: existingSong, warnings: [])
}
```

The existing row is **not** a source for upgrade work. Do not re-resolve audio paths, recompute duration, backfill control events, or reconstruct rhythm metadata.

Fresh import remains the source of truth for the current representation:

1. decode `SET.def`;
2. parse playable current DTX charts;
3. create the `Song` with current audio paths and duration;
4. create current `Chart` objects;
5. persist canonical rhythm metadata, notes, and control events from `DTXChartPersistenceProjection`;
6. save once;
7. roll the context back if the save/build path throws.

This preserves current correctness while deleting upgrade behavior.

#### Bundled fixture deletion behavior remains current functionality

`BundledFixtureDeletionStore` is not a compatibility mechanism. It represents the current product rule that a user-deleted bundled demo should not be recreated on every launch.

Keep these semantics:

- tombstone + missing row -> skip seed;
- tombstone cleared + missing row -> seed current fixture;
- existing stable-ID row -> return it without mutation.

Update comments/tests that currently call the last case a “refresh”; after HPA-577 it is simply stable-ID idempotence.

#### Compatibility code to delete

Remove from `LocalDTXFixtureImporter`:

- `performLegacySourceRefreshes`;
- `refreshAudioPaths`;
- `refreshDurationIfStale`;
- `refreshControlEventsIfMissing`;
- `backfillBundledRhythmTimingIfNeeded`;
- `backfillRhythmTiming`;
- rhythm-backfill-only error cases;
- rhythm-backfill plan/candidate/equivalence/source-matching/apply helpers.

Delete `RhythmBackfillVersionStore.swift` and its protocol. No version marker replaces it.

The custom `importSong(from:songId:into:)` convenience overload should also be deleted if, after compatibility tests are removed, it has no remaining current caller. Tests that simply need the folder's stable ID should use `importSong(from:into:)`.

`ContentView.seedLocalDTXFixtures()` should import the bundled fixture and log success; it should no longer invoke a timing backfill afterward.

`ContentStartupPolicy.shouldImportBundledLocalDTXFixtures` documentation should describe idempotent seeding, not “refreshing” older rows.

### 3. Keep current score persistence; delete score migration

`ScorePersistenceService` remains the owner of current score behavior:

- record a `ScoreRecord`;
- update `Chart.bestScore` for eligible full-speed runs;
- return recent attempt DTOs;
- prune old attempt history;
- restore in-memory mutations when the current save fails.

Delete only the historical migration surface:

- `migrationFlagKey` (`DidMigrateHighScoresToSwiftData`);
- `legacyHighScoreKey` (`HighScorePerChart`);
- `migrateLegacyHighScores`;
- `readLegacyScores`;
- migration-specific rollback tests and fixtures.

Do not alter current `recordAttempt` rollback semantics. A failure while saving current data is a current correctness concern, not backward compatibility.

### 4. Remove legacy persistence-key resolution

The current persistence-key representation is `PersistentIdentifierPersistenceKey.canonicalKey(...)`. Keep that function because current call sites use it.

Delete historical key resolution:

- `PersistentIdentifierPersistenceKey.Resolution`;
- `resolve(...)`;
- `normalizeJSONKey(...)`;
- tests that exist only to exercise `needsMigration`/legacy key matching.

`PracticeSettingsService.loadSpeed(for:)` should perform one exact lookup using the canonical key:

```swift
let key = persistenceKey(for: chartID)
guard let savedSpeed = readPersistedSpeeds()[key] else {
    return 1.0
}
```

Keep validation/clamping and numeric UserDefaults bridging needed by the current representation. Remove the string-value fallback if no current writer produces strings; current writes store numeric values.

A non-canonical historical key is ignored rather than rewritten. This is the intended breaking behavior.

### 5. Tests describe supported behavior, not historical upgrades

Delete tests whose contract is “old state is repaired.” Do not preserve them as disabled tests.

#### Delete entirely

- `VirgoTests/DatabaseMaintenanceServiceTests.swift`.
- timing-backfill/version-store-specific tests once the production API is gone.
- duplicated `PersistentIdentifierPersistenceKey.Resolution` suites.
- legacy score-migration tests.
- legacy practice-key migration helpers/tests.

#### Retain or adapt

Keep current-format tests for:

- fresh local fixture import;
- canonical timing/control-event persistence on fresh import;
- fresh-import rollback on save failure;
- error handling for missing/unreadable/malformed current fixture input;
- bundled fixture deletion tombstone behavior;
- current `ScoreRecord`/best-score/recent-attempt behavior;
- current practice-speed save/load/clamp behavior.

Tests that currently mix a useful current behavior with a backfill setup should be rewritten to start from a fresh current-format import rather than preserving the backfill API just for the test.

Where a test file becomes misleading after compatibility tests are deleted, a narrow rename such as `LocalDTXControlBackfillTests.swift` -> `LocalDTXControlImportTests.swift` or `RhythmImportBackfillTests.swift` -> `RhythmImportTests.swift` is acceptable. Do not perform broader suite consolidation; leave that for HPA-583.

#### Add one explicit no-repair regression

Pin the new policy with a small test:

1. insert a `Song` using the same stable ID as a fixture;
2. deliberately give it stale values such as an old duration/audio path;
3. call `importSong(from:into:)`;
4. assert the same persisted row is returned;
5. assert no duplicate row is created;
6. assert the stale fields are unchanged.

This prevents a future “helpful” refresh path from silently reintroducing migration behavior.

For practice settings, replace the legacy-key migration test with one current-policy regression: a non-canonical key is ignored and the default speed is returned.

## Breaking local-data policy

HPA-577 intentionally changes upgrade behavior.

After this change, a local store/settings domain created by an older development build may contain:

- `Song` rows missing newly required/current metadata;
- historical duplicate rows;
- old chart levels;
- old fixture duration/audio/control/timing values;
- `HighScorePerChart` UserDefaults;
- non-canonical practice-setting keys.

Virgo does not attempt to repair those states. Delete/reset the development store/UserDefaults and let the current build create fresh data.

The application should not add a production “migration failed, reset now” flow in this ticket. That would turn a pre-release development convenience into permanent infrastructure.

## Failure behavior

Current-format failures remain visible and local:

- missing/unreadable `SET.def` continues to fail/return as today;
- fresh fixture graph creation rolls back on a thrown save/build error;
- current score save failures continue to return `.saveFailed` and restore pending mutations;
- unsupported/corrupt current practice-setting values fall back through existing validation rules.

What disappears is only the attempt to turn an old representation into a new one.

## Expected file impact

### Production

- Modify: `Virgo/views/ContentView.swift`
- Delete: `Virgo/services/DatabaseMaintenanceService.swift`
- Modify: `Virgo/services/ScorePersistenceService.swift`
- Modify: `Virgo/services/PracticeSettingsService.swift`
- Modify: `Virgo/utilities/PersistentIdentifierPersistenceKey.swift`
- Modify: `Virgo/utilities/LocalDTXFixtureImporter.swift`
- Delete: `Virgo/utilities/RhythmBackfillVersionStore.swift`
- Modify: `Virgo/utilities/ContentStartupPolicy.swift` (comment only)

### Tests

- Delete: `VirgoTests/DatabaseMaintenanceServiceTests.swift`
- Modify: `VirgoTests/ScorePersistenceServiceTests.swift`
- Modify: `VirgoTests/PracticeSettingsServiceTests.swift`
- Modify: `VirgoTests/CollectionAndLayoutExtensionTests.swift`
- Modify: `VirgoTests/SwiftDataRelationshipLoaderTests.swift`
- Modify: `VirgoTests/LocalDTXFixtureImporterTests.swift`
- Modify: `VirgoTests/LocalDTXFixtureImporterCoverageTests.swift`
- Modify/rename: `VirgoTests/LocalDTXControlBackfillTests.swift`
- Modify/rename: `VirgoTests/RhythmImportBackfillTests.swift`

The project uses file-system-synchronized groups, so implementation should not hand-edit `project.pbxproj` for these file additions/deletions unless Xcode proves it is necessary.

## Acceptance criteria

- [ ] `ContentView` performs no historical database maintenance or score migration on normal startup.
- [ ] `DatabaseMaintenanceService` and its tests no longer exist.
- [ ] `ScorePersistenceService` contains only current SwiftData score persistence behavior.
- [ ] `HighScorePerChart` / `DidMigrateHighScoresToSwiftData` migration code is gone.
- [ ] Existing local fixture rows are matched only by stable ID and returned without repair.
- [ ] Fresh fixture import still writes canonical current charts, notes, controls, rhythm metadata, duration, and audio paths.
- [ ] Rhythm backfill/version-store production code is gone.
- [ ] `PersistentIdentifierPersistenceKey` no longer resolves/migrates historical key encodings.
- [ ] Current per-chart practice settings still round-trip through the canonical key; historical key variants are ignored.
- [ ] Bundled fixture deletion remains durable and reset/reseed behavior still works.
- [ ] Compatibility-only tests/comments are deleted or rewritten around current behavior.
- [ ] Full macOS unit tests pass with parallel testing disabled.
- [ ] iPad Simulator build passes.
- [ ] The implementation/PR explicitly states that old local development data may require reset.

## Review guardrails

During implementation/review, reject changes that add any of the following merely to compensate for the deleted paths:

- schema/version registries;
- migration coordinators;
- automatic duplicate repair;
- generalized fixture reconciliation/diffing;
- startup repositories/use-case layers;
- compatibility adapters for old UserDefaults keys;
- new cross-cutting test infrastructure.

If a current-format creator is found to write invalid state, fix that creator directly in the smallest owning scope instead of adding a repair pass.