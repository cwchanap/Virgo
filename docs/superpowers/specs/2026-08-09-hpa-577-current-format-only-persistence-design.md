# HPA-577: Current-Format-Only Startup and Persistence

**Date:** 2026-08-09  
**Status:** Draft design for review — revised after second review, implementation not started

## Context

Virgo is still pre-release and has no production user data that must survive breaking local-format changes. HPA-577 therefore adopts the roadmap's current-format-only policy: SwiftData stores and UserDefaults created by older development builds may be deleted/reset instead of migrated or repaired.

The current code still carries several upgrade paths from earlier development iterations:

- `ContentView` creates `DatabaseMaintenanceService` on normal startup and runs historical `Song`/`Chart` repair passes.
- `ContentView` fetches every `Chart` at startup to migrate `HighScorePerChart` UserDefaults into SwiftData.
- `LocalDTXFixtureImporter` can recompute stale duration, populate missing control events, and backfill missing rhythm metadata/ticks on older imported rows.
- `RhythmBackfillVersionStore` persists a one-time timing-backfill version in UserDefaults.
- `PersistentIdentifierPersistenceKey.resolve` recognizes non-canonical historical key encodings and rewrites them; `PracticeSettingsService` still uses that compatibility path.

One existing repeated-import behavior is **not** compatibility and must remain: local/bundled audio paths are stored as absolute filesystem paths and are consumed directly by `AudioPlaybackService` and `GameplayViewModel`. `refreshAudioPaths` re-resolves those ephemeral paths from the current fixture folder and clears paths when current assets disappear. It runs unconditionally today, outside the `performLegacySourceRefreshes` gate. HPA-577 keeps that small current-format repair while deleting historical model/data migration.

HPA-577 removes upgrade policy rather than replacing it with another migration framework.

## Decision summary

Support exactly one persistent data representation: the representation written by the current build.

- Normal startup does not inspect or repair historical local model data.
- Current bundled/local fixture import remains idempotent by stable `serverSongId`.
- Re-import of an already-present stable ID re-resolves only ephemeral BGM/preview filesystem paths, then returns the same persisted song/graph without repairing duration, charts, notes, controls, rhythm metadata, or normalized ticks.
- A fresh fixture import writes the complete current `Song`/`Chart`/`Note`/`ChartControlEvent` graph transactionally.
- Scores use only current SwiftData `ScoreRecord` + `Chart.bestScore` persistence.
- Per-chart practice settings read/write only the current canonical persistence key.
- Old development stores/settings that do not match the current representation are reset rather than upgraded.
- Operational repository guidance (`CLAUDE.md`, also exposed through the `AGENTS.md` symlink) must stop naming production APIs removed by this ticket when implementation lands.

This is intentionally deletion-first. Do not add schema versions, compatibility adapters, generalized deduplication, or automatic store-reset detection.

## Approaches considered

### A. Disable compatibility calls but leave the old implementation

Remove the startup calls but keep `DatabaseMaintenanceService`, fixture duration/control/rhythm backfills, migration resolvers, and their tests.

**Rejected.** This minimizes the immediate diff but leaves dead behavior, dead tests, and an attractive path for accidentally restoring compatibility later.

### B. Delete compatibility paths, keep narrow current identity and path resolution

Remove historical upgrade behavior while preserving current creators, stable-ID lookup, current audio-path resolution, test reset/seeding, score persistence, and current settings persistence.

**Selected.** This is the smallest long-term design while preserving a current runtime requirement caused by persisted absolute audio paths.

### C. Add store/version detection and automatic reset/reseed

Detect an old representation and automatically clear or migrate it.

**Rejected.** This recreates permanent version/migration coordination for disposable pre-release data.

A future move from persisted absolute audio paths to bundle-relative/resource identifiers could remove the need for `refreshAudioPaths`, but that would change the path contract and all consumers. HPA-577 does not need that broader change: retaining the existing small resolver is cheaper and clearer.

## Goals

1. Remove historical maintenance from normal startup.
2. Make local fixture re-import current-format-only while preserving current audio path resolution.
3. Remove legacy score migration and persistence-key migration behavior.
4. Delete tests/helpers whose only purpose is preserving old local representations.
5. Keep fresh/reset-store behavior and current user-facing persistence behavior intact.
6. Keep the always-on agent guidance accurate when deleted symbols disappear.

## Non-goals and ownership boundaries

- No SwiftData schema/migration framework.
- No automatic incompatible-store detection or destructive production reset.
- No generic song deduplication or title/artist normalization.
- No bundle-relative audio-path redesign in this ticket.
- No redesign of `ScorePersistenceService`, `PracticeSettingsService`, `ContentView`, or SwiftData ownership.
- No server catalog snapshot redesign; HPA-578 owns that work.
- **No `ServerSongDownloader.songAlreadyExists` cleanup in HPA-577.** Its exact title/artist and case-insensitive fallbacks for rows lacking `serverSongId` are a known residual compatibility path, and HPA-578 already explicitly owns deleting those fallbacks and making `serverSongId` the current server-import identity contract.
- No off-main parsing/performance work; HPA-579/HPA-580 own that decision.
- No broad test-suite or historical documentation consolidation; HPA-583 owns that final cleanup.
- No server BGM format work; HPA-85 remains separate.
- Do not delete `RhythmTimelineResolver.resolveMissing` or the `.legacy` runtime fallback. HPA-577 deletes import/startup backfill machinery, not runtime fallback behavior used by current/manual/sample paths and older local rows that have not been reset.

The HPA-578 residual is named here so HPA-577 implementers do not silently expand scope or leave ownership ambiguous.

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

### 2. Keep audio paths current; make everything else identity-only

`LocalDTXFixtureImporter` already has the correct narrow persistent identity boundary: `serverSongId`.

Keep:

```swift
private static func existingSong(with songId: String, in context: ModelContext) throws -> Song?
```

For an existing row, the repeated-import path becomes:

```swift
if let existingSong = try existingSong(with: songId, in: context) {
    try refreshAudioPaths(for: existingSong, from: folderURL, in: context)
    return LocalDTXFixtureImportResult(song: existingSong, warnings: [])
}
```

`refreshAudioPaths` is current-format filesystem resolution, not migration. Fresh imports persist absolute `bgm.m4a` / `preview.mp3` paths, and playback later calls `URL(fileURLWithPath:)` on those stored strings. A rebuilt/moved app bundle or removed asset can invalidate an otherwise current row, so repeated import must re-resolve these two paths.

The existing row and relationships are otherwise not sources for upgrade work. Re-import must not:

- recompute duration;
- rewrite `isServerImported`, title, artist, BPM, genre, or time signature;
- add or replace charts;
- add or replace notes;
- add missing control events;
- rewrite rhythm metadata or normalized tick fields;
- create or modify `bgmStartOffsetSeconds`.

Fresh import remains the source of truth for the persistent current representation:

1. decode `SET.def`;
2. parse playable current DTX charts;
3. create the `Song` with current audio paths and duration;
4. create current `Chart` objects;
5. persist canonical rhythm metadata, notes, and control events from `DTXChartPersistenceProjection`;
6. save once;
7. roll the context back if graph creation/save throws.

#### Bundled fixture deletion remains current behavior

`BundledFixtureDeletionStore` is a product rule, not compatibility infrastructure.

Keep:

- tombstone + missing row -> skip seed;
- tombstone cleared + missing row -> seed current fixture;
- existing stable-ID row -> re-resolve audio paths and return the same graph.

Comments/tests that currently call duration/control/rhythm work “self-healing refresh” should be narrowed to the actual retained behavior: current audio-path resolution only.

#### Current path-resolution code/tests to keep

Keep `refreshAudioPaths` and `existingAudioPath`.

Keep the asset-removal regression that verifies a repeated import clears BGM/preview paths when current assets disappear. Rewrite the old `bgm.ogg`-framed stale-path test, or cover path relocation in the graph policy test, so the retained contract is about current absolute-path re-resolution rather than preservation of an obsolete audio format.

#### Compatibility code to delete

Remove from `LocalDTXFixtureImporter`:

- `performLegacySourceRefreshes`;
- `refreshDurationIfStale`;
- `refreshControlEventsIfMissing`;
- `backfillBundledRhythmTimingIfNeeded`;
- `backfillRhythmTiming`;
- rhythm-backfill-only error cases;
- rhythm-backfill plan/candidate/equivalence/source-matching/apply helpers.

Delete `RhythmBackfillVersionStore.swift` and its protocol. No version marker replaces them.

The custom `importSong(from:songId:into:)` overload is compatibility-test plumbing once backfill callers are gone. **Do not delete it in the first fixture checkpoint while `LocalDTXControlBackfillTests` still calls it.** Rewrite/delete those callers in the control/rhythm cleanup checkpoint, then delete the overload when `rg` confirms it has no current caller.

`ContentView.seedLocalDTXFixtures()` imports the bundled fixture and logs success; it no longer invokes timing backfill.

`ContentStartupPolicy.shouldImportBundledLocalDTXFixtures` should describe idempotent seeding/path resolution, not historical model repair.

### 3. Pin the boundary: paths may change; persisted graph data may not

Use one richer stable-ID policy test through the real DTX import path. Build a deterministic temporary fixture containing:

- `SET.def`;
- a playable BASIC chart;
- `#VIRGO_CONTROL: 1` plus a control event;
- current `bgm.m4a` and `preview.mp3` files.

Pre-insert a row with the same stable ID but intentionally stale/incomplete persistent state:

- stale absolute BGM/preview paths pointing somewhere else;
- stale `Song.duration`;
- `isServerImported == false`;
- a non-nil `bgmStartOffsetSeconds` sentinel such as `0.42`;
- one existing `Chart` with matching difficulty/level;
- one existing note;
- empty `controlEvents` even though the source fixture contains a control;
- `rhythmMetadataData == nil`.

Call `importSong(from:into:)` and assert:

- the exact same `Song` instance is returned;
- BGM/preview paths now resolve to the current temp fixture files;
- stale duration and `isServerImported` remain unchanged;
- `bgmStartOffsetSeconds` remains `0.42`;
- one `Song` row and one `Chart` row remain;
- the same existing chart and note remain;
- `controlEvents` remains empty;
- `rhythmMetadataData` remains `nil`.

Against current code, the **RED signal must come from historical repair that is actually being removed**:

- the duration assertion fails because `refreshDurationIfStale` recomputes it;
- the empty-controls assertion fails because `refreshControlEventsIfMissing` populates controls.

The audio-path assertions are expected to pass both before and after HPA-577, because that behavior is retained. The rhythm-metadata assertion also passes in the direct re-import test before HPA-577; it pins the direct-import boundary but is not itself a RED signal. Removal of `ContentView`'s separate `backfillBundledRhythmTimingIfNeeded` call plus a symbol/caller audit is what proves startup can no longer fill missing rhythm metadata.

Existing BGM-offset tests already encode part of the target no-repair policy. Retain/rename them as current-policy coverage or fold their nil/non-nil assertions into the richer regression; do not drop the field from coverage merely because the old comments call it legacy.

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

### 6. Runtime rhythm fallback is not migration infrastructure

`RhythmTimelineResolver.resolveMissing` remains untouched.

Today a DTX-origin chart with missing rhythm metadata resolves with `.legacy` availability and no canonical timeline; non-DTX/manual/sample charts also use missing-metadata fallback logic. This runtime behavior is separate from the import/startup backfills HPA-577 deletes.

`ChartPracticeState` currently treats `.legacy` availability as non-fatal rather than surfacing a timing-unavailable badge. Therefore HPA-577 must **not** claim that stale DTX rows already fail visibly or are automatically blocked. Old development data is simply unsupported/resettable, and the existing runtime fallback remains as-is.

That is still not a reason to add a store version detector, and it is not a reason to delete `resolveMissing` in this ticket.

### 7. Tests describe supported behavior, not upgrades

Delete tests whose contract is “historical model state is upgraded.” Do not keep them disabled.

Delete entirely:

- `VirgoTests/DatabaseMaintenanceServiceTests.swift`;
- timing-backfill/version-store-specific tests;
- duplicate `PersistentIdentifierPersistenceKey.Resolution` suites;
- legacy score-migration tests;
- legacy practice-key migration helpers/tests.

Retain/adapt current-format coverage for:

- fresh local fixture import;
- current audio-path re-resolution and asset removal;
- canonical timing/control persistence on fresh import;
- fresh-import rollback on save failure;
- missing/unreadable/malformed current fixture input;
- bundled fixture deletion tombstone behavior;
- current score/best/recent-attempt behavior;
- current practice-speed save/load/clamp behavior;
- the richer stable-ID boundary above, including BGM offset non-clobbering.

Tests that use a backfill API merely as setup should be rewritten around a fresh current projection. Do not keep production compatibility APIs for test convenience.

Narrow file renames such as `LocalDTXControlBackfillTests.swift` -> `LocalDTXControlImportTests.swift` and `RhythmImportBackfillTests.swift` -> `RhythmImportTests.swift` are acceptable if the retained file no longer tests backfill. Broader suite consolidation belongs to HPA-583.

### 8. Keep the live agent brief accurate

`CLAUDE.md` is operational repository guidance and `AGENTS.md` is a symlink to it. It is not merely historical architecture documentation.

When implementation deletes the production APIs, update only the live statements that would become false:

- remove the `RhythmBackfillVersionStore` paragraph/instruction from the rhythm pipeline section and state that current imports persist normalized data directly; old imported development rows are reset rather than renormalized;
- remove `DatabaseMaintenanceService` from the services list;
- remove the claim that `ScorePersistenceService` performs the `HighScorePerChart` migration;
- keep any current guidance that local fixture audio paths are re-resolved when needed, but remove obsolete `bgm.ogg` migration framing if it names a historical format transition as current architecture.

Do not sweep old files under `docs/superpowers/specs`, `docs/superpowers/plans`, or `docs/Project_Architecture_Blueprint.md`; HPA-583 still owns broad/historical documentation consolidation.

## Breaking local-data policy

After HPA-577, an older development store/settings domain may contain stale song metadata, historical duplicates, old chart levels, old fixture controls/timing, legacy high scores, or non-canonical settings keys.

Virgo does not upgrade those states. Reset the development store/UserDefaults and let the current build create fresh data.

The narrow exception is **filesystem location**, not representation: when a stable-ID fixture is already present, Virgo may update only its persisted BGM/preview paths to point at the current fixture assets (or clear them when those assets no longer exist).

Do not add a production “migration failed, reset now” flow.

## Failure behavior

Current-format failures remain visible and local:

- missing/unreadable `SET.def` continues to fail/return as current code specifies on a fresh import;
- fresh fixture graph creation rolls back on thrown build/save errors;
- current score save failures return `.saveFailed` and restore pending mutations;
- unsupported/corrupt current practice-setting values use current validation/fallback rules;
- repeated current fixture import keeps audio references synchronized with the files that actually exist.

Historical DTX rows with missing rhythm metadata may still enter the existing `.legacy` runtime fallback. HPA-577 neither upgrades that state nor removes the fallback; old development data remains resettable/unsupported.

## Verification policy

For startup deletion, the primary proof remains deliberately simple:

1. source search shows `DatabaseMaintenanceService`, `performInitialMaintenance`, `migrateLegacyHighScores`, and legacy score keys no longer exist in production/tests;
2. focused current tests compile/pass;
3. the full macOS unit suite passes;
4. the macOS `VirgoUITests` suite passes, matching the separate UI-test workflow that drives `-UITesting` / `-ResetState` startup behavior;
5. the iPad Simulator build passes.

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
- Verify: `VirgoUITests/*` (no expected production-test rewrite; run the existing suite after startup changes)

The Xcode project uses file-system-synchronized groups, so implementation should not hand-edit `project.pbxproj` for these deletions/renames unless a build proves it is necessary.

## Acceptance criteria

- [ ] `ContentView` performs no historical database maintenance or score migration on normal startup.
- [ ] `DatabaseMaintenanceService` and its tests no longer exist.
- [ ] `ScorePersistenceService` contains only current SwiftData score persistence behavior.
- [ ] `HighScorePerChart` / `DidMigrateHighScoresToSwiftData` migration code is gone.
- [ ] Existing local fixture rows are matched by stable ID; only BGM/preview filesystem paths may be re-resolved on repeated import.
- [ ] The stable-ID regression proves duration, identity fields, BGM offset, existing charts/notes, empty controls, and missing rhythm metadata are not repaired by direct re-import, while audio paths do resolve to current assets.
- [ ] The Task 1 RED check explicitly fails on duration repair and control-event backfill before production changes.
- [ ] Fresh fixture import still writes canonical current charts, notes, controls, rhythm metadata, duration, and audio paths.
- [ ] Current audio-path re-resolution and asset-removal coverage remains.
- [ ] Rhythm backfill/version-store production code is gone.
- [ ] `RhythmTimelineResolver.resolveMissing` / `.legacy` runtime fallback is not removed by this ticket.
- [ ] `PersistentIdentifierPersistenceKey` no longer resolves/migrates historical key encodings.
- [ ] Current practice settings round-trip through the canonical key; historical key variants are ignored.
- [ ] Bundled fixture deletion remains durable and reset/reseed behavior still works.
- [ ] The custom `importSong(from:songId:into:)` overload is removed only after Task 2 eliminates its remaining backfill-test callers.
- [ ] `ServerSongDownloader` title/artist fallback cleanup remains explicitly owned by HPA-578 and is not implemented here.
- [ ] `CLAUDE.md` contains no live guidance instructing agents to use APIs deleted by HPA-577.
- [ ] Compatibility-only tests/comments are deleted or rewritten around current behavior.
- [ ] Full macOS unit tests pass with parallel testing disabled.
- [ ] Existing macOS `VirgoUITests` pass after the startup rewrite.
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

Also reject:

- scope creep that deletes the server-download title/artist fallbacks in this ticket; HPA-578 already owns that exact cleanup;
- deletion of `refreshAudioPaths` without first replacing the persisted absolute-path contract end-to-end;
- deletion of `RhythmTimelineResolver.resolveMissing` / `.legacy` fallback as if it were the same thing as import-time migration.

If a current-format creator writes invalid persistent state, fix that creator directly in its smallest owning scope instead of adding a repair pass.
