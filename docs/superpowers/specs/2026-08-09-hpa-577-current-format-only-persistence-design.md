# HPA-577: Current-Format-Only Startup and Persistence

**Date:** 2026-08-09  
**Status:** Draft design for review — revised after review, implementation not started

## Context

Virgo is still pre-release and has no production user data that must survive breaking local-format changes. HPA-577 therefore adopts the roadmap's current-format-only policy: SwiftData stores and UserDefaults created by older development builds may be deleted/reset instead of migrated or repaired.

The current code still carries several upgrade paths from earlier development iterations:

- `ContentView` creates `DatabaseMaintenanceService` on normal startup and runs historical `Song`/`Chart` repair passes.
- `ContentView` fetches every `Chart` at startup to migrate `HighScorePerChart` UserDefaults into SwiftData.
- `LocalDTXFixtureImporter` treats re-import as a repair opportunity for stale audio paths, stale duration, missing control events, and missing rhythm metadata.
- `RhythmBackfillVersionStore` persists a one-time timing-backfill version in UserDefaults.
- `PersistentIdentifierPersistenceKey.resolve` recognizes non-canonical historical key encodings and rewrites them; `PracticeSettingsService` still uses that compatibility path.

Those paths are useful only if old local state must be preserved. Keeping them makes startup and importer behavior harder to reason about, expands the test surface, and encourages new compatibility code whenever the current representation changes.

HPA-577 removes that policy rather than replacing it with another migration framework.

## Decision summary

Support exactly one local representation: the representation written by the current build.

- Normal startup does not inspect or repair old local data.
- Current bundled/local fixture import remains idempotent by stable `serverSongId`.
- Re-import of an already-present stable ID returns the existing row and graph unchanged; it does not repair song fields, controls, or rhythm data.
- A fresh fixture import writes the complete current `Song`/`Chart`/`Note`/`ChartControlEvent` graph transactionally.
- Scores use only current SwiftData `ScoreRecord` + `Chart.bestScore` persistence.
- Per-chart practice settings read/write only the current canonical persistence key.
- Old development stores/settings that do not match the current representation are reset rather than upgraded.
- Operational repository guidance (`CLAUDE.md`, also exposed through the `AGENTS.md` symlink) must stop naming production APIs removed by this ticket when implementation lands.

This is intentionally deletion-first. Do not add schema versions, compatibility adapters, generalized deduplication, or automatic store-reset detection.

## Approaches considered

### A. Disable compatibility calls but leave the old implementation

Remove the startup calls but keep `DatabaseMaintenanceService`, fixture refresh/backfill helpers, migration resolvers, and their tests.

**Rejected.** This minimizes the immediate diff but leaves dead behavior, dead tests, and an attractive path for accidentally restoring compatibility later.

### B. Delete compatibility paths and keep narrow current-format identity

Remove upgrade behavior while preserving current creators, stable-ID lookup, test reset/seeding, score persistence, and current settings persistence.

**Selected.** This is the smallest long-term design and matches the project's accepted breaking-data policy.

### C. Add store/version detection and automatic reset/reseed

Detect an old representation and automatically clear or migrate it.

**Rejected.** This recreates permanent version/migration coordination for disposable pre-release data.

## Goals

1. Remove historical maintenance from normal startup.
2. Make local fixture import current-format-only and stable-ID idempotent.
3. Remove legacy score migration and persistence-key migration behavior.
4. Delete tests/helpers whose only purpose is preserving old local representations.
5. Keep fresh/reset-store behavior and current user-facing persistence behavior intact.
6. Keep the always-on agent guidance accurate when deleted symbols disappear.

## Non-goals and ownership boundaries

- No SwiftData schema/migration framework.
- No automatic incompatible-store detection or destructive production reset.
- No generic song deduplication or title/artist normalization.
- No redesign of `ScorePersistenceService`, `PracticeSettingsService`, `ContentView`, or SwiftData ownership.
- No server catalog snapshot redesign; HPA-578 owns that work.
- **No `ServerSongDownloader.songAlreadyExists` cleanup in HPA-577.** Its exact title/artist and case-insensitive fallbacks for rows lacking `serverSongId` are a known residual compatibility path, and HPA-578 already explicitly owns deleting those fallbacks and making `serverSongId` the current server-import identity contract.
- No off-main parsing/performance work; HPA-579/HPA-580 own that decision.
- No broad test-suite or historical documentation consolidation; HPA-583 owns that final cleanup.
- No server BGM format work; HPA-85 remains separate.

The HPA-578 residual is named here so HPA-577 implementers do not silently expand scope or leave the ownership ambiguous.

## Design

### 1. Remove the startup upgrade pipeline

`ContentView.onAppear` keeps only startup work needed by the current build:

- UI-test reset/seed policy;
- bundled current-format fixture seed;
- `ServerSongService` model-context setup and catalog load;
- the short-lived `startupSongsOverride` bridge used after synchronous seed/reset work.

Delete:

- `@State private var databaseService: DatabaseMaintenanceService?`;
- construction/invocation of `DatabaseMaintenanceService`;
- the post-maintenance chart re-fetch;
- `ScorePersistenceService.migrateLegacyHighScores(...)` and its startup error branch;
- comments that describe startup maintenance/migration.

Do **not** extract a startup coordinator. `ContentStartupPolicy` already owns the relevant decision logic.

`DatabaseMaintenanceService.swift` and `DatabaseMaintenanceServiceTests.swift` are deleted. None of their behavior moves elsewhere:

- `genre == "DTX Import"` is no longer backfilled into `isServerImported`;
- `Chart.level == 50` is no longer rewritten by difficulty;
- duplicate songs are not repaired by normalized title/artist matching;
- the sample cleanup no-op disappears.

Current creators are responsible for writing valid current data.

### 2. Make fixture re-import identity-only

`LocalDTXFixtureImporter` already has the correct narrow identity boundary: `serverSongId`.

Keep:

```swift
private static func existingSong(with songId: String, in context: ModelContext) throws -> Song?
```

When it finds an existing row, return it immediately:

```swift
if let existingSong = try existingSong(with: songId, in: context) {
    return LocalDTXFixtureImportResult(song: existingSong, warnings: [])
}
```

The existing row and its relationships are not sources for upgrade work. Re-import must not:

- re-resolve audio paths;
- recompute duration;
- add or replace charts;
- add missing control events;
- rewrite rhythm metadata or normalized tick fields.

Fresh import remains the source of truth for the current representation:

1. decode `SET.def`;
2. parse playable current DTX charts;
3. create the `Song` with current audio paths and duration;
4. create current `Chart` objects;
5. persist canonical rhythm metadata, notes, and control events from `DTXChartPersistenceProjection`;
6. save once;
7. roll back the context if graph creation/save throws.

#### Bundled fixture deletion remains current behavior

`BundledFixtureDeletionStore` is a product rule, not compatibility infrastructure.

Keep:

- tombstone + missing row -> skip seed;
- tombstone cleared + missing row -> seed current fixture;
- existing stable-ID row -> return it unchanged.

Comments/tests that currently describe the final case as a “refresh” should be rewritten as stable-ID idempotence.

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

Delete `RhythmBackfillVersionStore.swift` and its protocol. No version marker replaces them.

The custom `importSong(from:songId:into:)` overload is compatibility-test plumbing once backfill callers are gone. **Do not delete it in the first fixture checkpoint while `LocalDTXControlBackfillTests` still calls it.** Rewrite/delete those callers in the control/rhythm cleanup checkpoint, then delete the overload when `rg` confirms it has no current caller.

`ContentView.seedLocalDTXFixtures()` imports the bundled fixture and logs success; it no longer invokes timing backfill.

`ContentStartupPolicy.shouldImportBundledLocalDTXFixtures` should describe idempotent seeding, not refreshing old rows.

### 3. Pin no-repair behavior across song and graph state

A song-field-only regression is insufficient because the current compatibility path also repairs control/rhythm-related graph state.

Use one richer stable-ID policy test through the real DTX import path. Build a deterministic temporary fixture containing a playable chart and a control event, then pre-insert a row with the same stable ID but intentionally stale/incomplete graph state:

- stale `Song.duration` and audio paths;
- one existing `Chart` with the matching difficulty/level;
- existing note(s) left exactly as inserted;
- empty `controlEvents` even though the source fixture contains a control;
- `rhythmMetadataData == nil`.

Call `importSong(from:into:)` and assert:

- the exact same `Song` instance is returned;
- one `Song` row remains;
- the same existing chart remains and no new chart is inserted;
- stale song fields remain unchanged;
- the existing note collection remains unchanged;
- `controlEvents` remains empty;
- `rhythmMetadataData` remains `nil`.

This is the explicit policy pin that prevents a future “helpful” importer repair from returning. The separate removal of `ContentView`'s timing-backfill call plus an `rg` gate proves startup cannot repair the missing rhythm payload either.

### 4. Keep current score persistence; delete legacy score migration

`ScorePersistenceService` keeps current behavior:

- record a `ScoreRecord`;
- update `Chart.bestScore` for eligible full-speed runs;
- return recent attempt DTOs;
- prune old attempt history;
- restore pending mutations when the current save fails.

Delete only the historical migration surface:

- `migrationFlagKey` (`DidMigrateHighScoresToSwiftData`);
- `legacyHighScoreKey` (`HighScorePerChart`);
- `migrateLegacyHighScores`;
- `readLegacyScores`;
- migration-specific rollback/tests/fixtures.

Current `recordAttempt` rollback remains. Failed current writes are a correctness concern, not backward compatibility.

### 5. Remove legacy persistence-key resolution

Keep `PersistentIdentifierPersistenceKey.canonicalKey(...)`, because current persistence uses it.

Delete:

- `PersistentIdentifierPersistenceKey.Resolution`;
- `resolve(...)`;
- `normalizeJSONKey(...)`;
- compatibility-only resolver tests.

`PracticeSettingsService.loadSpeed(for:)` performs one exact canonical lookup:

```swift
let key = persistenceKey(for: chartID)
guard let savedSpeed = readPersistedSpeeds()[key] else {
    return 1.0
}
```

Keep finite/range validation and numeric (`Double`/`NSNumber`) UserDefaults bridging needed by the current representation. Remove the string-value fallback because the current writer stores numeric values.

A non-canonical historical key is ignored rather than rewritten.

### 6. Tests describe supported behavior, not upgrades

Delete tests whose contract is “old state is repaired.” Do not keep them disabled.

Delete entirely:

- `VirgoTests/DatabaseMaintenanceServiceTests.swift`;
- timing-backfill/version-store-specific tests;
- duplicate `PersistentIdentifierPersistenceKey.Resolution` suites;
- legacy score-migration tests;
- legacy practice-key migration helpers/tests.

Retain/adapt current-format coverage for:

- fresh local fixture import;
- canonical timing/control persistence on fresh import;
- fresh-import rollback on save failure;
- missing/unreadable/malformed current fixture input;
- bundled fixture deletion tombstone behavior;
- current score/best/recent-attempt behavior;
- current practice-speed save/load/clamp behavior;
- the richer stable-ID no-repair policy above.

Tests that use a backfill API merely as setup should be rewritten around a fresh current projection. Do not keep production compatibility APIs for test convenience.

Narrow file renames such as `LocalDTXControlBackfillTests.swift` -> `LocalDTXControlImportTests.swift` and `RhythmImportBackfillTests.swift` -> `RhythmImportTests.swift` are acceptable if the retained file no longer tests backfill. Broader suite consolidation belongs to HPA-583.

### 7. Keep the live agent brief accurate

`CLAUDE.md` is operational repository guidance and `AGENTS.md` is a symlink to it. It is not merely historical architecture documentation.

When implementation deletes the production APIs, update only the live statements that would become false:

- remove the `RhythmBackfillVersionStore` paragraph/instruction from the rhythm pipeline section and state that current imports persist normalized data directly; old imported development rows are reset rather than renormalized;
- remove `DatabaseMaintenanceService` from the services list;
- remove the claim that `ScorePersistenceService` performs the `HighScorePerChart` migration.

Do not sweep old files under `docs/superpowers/specs`, `docs/superpowers/plans`, or `docs/Project_Architecture_Blueprint.md`; HPA-583 still owns broad/historical documentation consolidation.

This narrow update prevents later agents from recreating deleted compatibility APIs from stale always-on guidance.

## Breaking local-data policy

After HPA-577, an older development store/settings domain may contain stale song metadata, historical duplicates, old chart levels, old fixture controls/timing, legacy high scores, or non-canonical settings keys.

Virgo does not repair those states. Reset the development store/UserDefaults and let the current build create fresh data.

Do not add a production “migration failed, reset now” flow.

## Failure behavior

Current-format failures remain visible and local:

- missing/unreadable `SET.def` continues to fail/return as current code specifies;
- fresh fixture graph creation rolls back on thrown build/save errors;
- current score save failures return `.saveFailed` and restore pending mutations;
- unsupported/corrupt current practice-setting values use current validation/fallback rules.

What disappears is only conversion of an old representation into a new one.

## Verification policy

For the startup deletion, the primary proof is deliberately simple:

1. source search shows `DatabaseMaintenanceService`, `performInitialMaintenance`, `migrateLegacyHighScores`, and legacy score keys no longer exist in production/tests;
2. the app and focused current tests compile/pass;
3. the full macOS test suite passes;
4. the iPad Simulator build passes.

`AppShellCoverageTests` may still run to guard current startup policy, but it is **not** claimed to prove that `ContentView.onAppear` no longer performs maintenance. Do not add a new runtime seam or source-parser test solely to prove absence of deleted code.

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
- Modify: `CLAUDE.md` (narrow live-guidance cleanup only)

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

The Xcode project uses file-system-synchronized groups, so implementation should not hand-edit `project.pbxproj` for these deletions/renames unless a build proves it is necessary.

## Acceptance criteria

- [ ] `ContentView` performs no historical database maintenance or score migration on normal startup.
- [ ] `DatabaseMaintenanceService` and its tests no longer exist.
- [ ] `ScorePersistenceService` contains only current SwiftData score persistence behavior.
- [ ] `HighScorePerChart` / `DidMigrateHighScoresToSwiftData` migration code is gone.
- [ ] Existing local fixture rows are matched only by stable ID and returned without song or graph repair.
- [ ] The no-repair regression proves stale song fields, existing charts/notes, empty controls, and missing rhythm metadata remain unchanged on repeated import.
- [ ] Fresh fixture import still writes canonical current charts, notes, controls, rhythm metadata, duration, and audio paths.
- [ ] Rhythm backfill/version-store production code is gone.
- [ ] `PersistentIdentifierPersistenceKey` no longer resolves/migrates historical key encodings.
- [ ] Current practice settings round-trip through the canonical key; historical key variants are ignored.
- [ ] Bundled fixture deletion remains durable and reset/reseed behavior still works.
- [ ] The custom `importSong(from:songId:into:)` overload is removed only after Task 2 eliminates its remaining backfill-test callers.
- [ ] `ServerSongDownloader` title/artist fallback cleanup remains explicitly owned by HPA-578 and is not implemented here.
- [ ] `CLAUDE.md` contains no live guidance instructing agents to use APIs deleted by HPA-577.
- [ ] Compatibility-only tests/comments are deleted or rewritten around current behavior.
- [ ] Full macOS unit tests pass with parallel testing disabled.
- [ ] iPad Simulator build passes.
- [ ] The implementation PR states that old local development data may require reset.

## Review guardrails

Reject changes that add any of the following merely to compensate for deleted compatibility paths:

- schema/version registries;
- migration coordinators;
- automatic duplicate repair;
- generalized fixture reconciliation/diffing;
- startup repositories/use-case layers;
- compatibility adapters for old UserDefaults keys;
- new cross-cutting test infrastructure.

Also reject scope creep that deletes the server-download title/artist fallbacks in this ticket; HPA-578 already owns that exact cleanup.

If a current-format creator writes invalid state, fix that creator directly in its smallest owning scope instead of adding a repair pass.