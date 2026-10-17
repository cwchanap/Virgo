# HPA-583: Test Ownership and Architecture Guidance Closeout Design

**Date:** 2026-10-15\
**Linear:** HPA-583\
**Status:** Planning

## Intent

Close the HPA-575 runtime/performance/test-architecture roadmap with a deletion-first maintenance pass. Virgo already has strong behavior protection; HPA-583 should make that protection easier to understand and cheaper to run by moving meaningful regressions into clear owners, deleting campaign-era duplicates, shrinking gameplay UI coverage, and making current guidance obvious.

This is maintenance, not a new testing architecture. Production feature behavior should remain unchanged.

## Why HPA-583 is next

HPA-584 is Done through its documented GUI-environment fallback. Interactive notation mount/scroll/memory performance remains unverified, so there is no evidence-backed virtualization or eager-renderer optimization to implement here.

Current `main` also contains the package-backed `DrumNotation` renderer. HPA-583 can therefore describe and protect the system that actually shipped instead of preserving campaign-era test/document structure.

## Current evidence

The cleanup is justified by concrete repository facts rather than a coverage quota:

- `ProfileCoverageTests.swift` duplicates `ProfileView` rendering already owned by `SwiftUIRenderingSettingsAndHeaderTests.swift`.
- `LocalDTXFixtureImporterCoverageTests.swift` and `PatchCoverageAdditionsTests.swift` overlap on the bundled-import missing-`SET.def` path.
- `GameplayViewUITests.swift` repeatedly launches the app for overlapping title/header/control assertions.
- many test files are named for `Coverage`, `Patch`, or an implementation wave rather than the behavior they protect.
- `GameplayViewModelCoverageTestSupport.swift` and `SwiftUICoverageFixtures.swift` are genuinely shared support and must not be deleted merely because their names contain `Coverage`.
- `.github/README.md` is stale and still documents iPhone simulator commands even though Virgo is iPad/macOS only.
- `docs/Project_Architecture_Blueprint.md` is a generated, stale architecture snapshot and has no current runtime reference.
- `.superpowers/` is already ignored but still contains tracked generated SDD reports.
- `codecov.yml` currently has `informational: false` for both project and patch status even though HPA-583 explicitly treats Codecov as informational.

## Approaches considered

### A. Surgical deletion-first ownership sweep — selected

Move unique current regressions into existing owner suites, delete duplicates, keep genuine shared support, trim UI coverage, fix the missing app-bundle packaging smoke, and simplify documentation/configuration around one source of truth.

### B. Full test-directory taxonomy refactor — rejected

Moving every test into new folders/modules would create broad churn unrelated to the actual maintenance value.

### C. Rename-only/docs-only cleanup — rejected

Renaming campaign files without deleting duplicate execution leaves ownership ambiguous and does not reduce maintenance cost.

## Design

### 1. Behavior ownership, not coverage ownership

Every remaining test must answer: **which current behavior owns this regression?**

For each `*Coverage*`, `*Patch*`, or wave-oriented source file:

1. meaningful current behavior moves to the nearest focused owner;
2. duplicate behavior is deleted;
3. tautological/implementation-coupled coverage is deleted;
4. obsolete pre-release compatibility behavior is deleted;
5. genuine shared support stays if focused suites still depend on it.

A new owner file is created only when no coherent owner exists.

`GameplayViewModelCoverageTestSupport.swift` and `SwiftUICoverageFixtures.swift` are explicit examples of shared support that may keep their current names; HPA-583 does not spend churn on cosmetic renames.

Before any campaign source file is deleted, its test-by-test disposition (`move -> <owner>`, `duplicate -> delete`, `obsolete -> delete`, `keep support -> reason`) must be recorded in the PR body or a linked top-level PR comment. The commit that removes that source file should carry the same disposition summary in its commit body.

Commit granularity is one campaign source file per commit, or one small inseparable pair when a move/delete cannot reasonably be reviewed separately.

### 2. Preserve the expensive tests that catch distinct failures

Keep the current high-value fault detectors:

- `DrumNotation` package tests;
- real-DTX textual goldens;
- drum-tab geometric invariants;
- meaningful production mounting/raster/accessibility smoke;
- playhead alignment;
- rhythm timeline/metronome/input boundaries;
- current score persistence semantics;
- a small serialized AVFoundation integration slice where framework behavior itself is under test.

Do not keep weak tests solely to preserve a coverage percentage.

### 3. HPA-87 is an app-bundle packaging smoke

HPA-583 absorbs the useful requirement from duplicate HPA-87: prove the shipped app still contains and can import the Soukyuu fixture.

The correct failure surface is `Bundle.main`, not a second copy in `VirgoTests.xctest`:

- HPA-87's title/risk is explicitly about `Bundle.main` and app resource membership;
- `VirgoTests` is hosted by `Virgo.app` through `TEST_HOST`/`BUNDLE_LOADER`, so `Bundle.main` in the hosted unit test is the built app bundle;
- copying the fixture into the test bundle would allow the test to remain green even if app membership broke.

Add one positive test in `LocalDTXFixtureImporterTests.swift` that calls `importBundledSoukyuuIfAvailable(..., bundle: .main, deletionStore: isolatedStore)` and proves:

- a song is returned;
- `bgmFilePath` ends in `bgm.m4a`;
- charts are non-empty.

No `project.pbxproj` fixture-membership edit is planned.

Resolve importer campaign duplication in the same ownership pass:

- move the isolated missing-`SET.def` negative from `LocalDTXFixtureImporterCoverageTests.swift` into `LocalDTXFixtureImporterTests.swift`;
- delete the weaker Patch copy and `DTXFixtureTestBundleAnchor`;
- delete the synthetic fake-bundle positive once the real `Bundle.main` positive exists;
- retain/move the deletion-gate tests because they cover different behavior and need isolated fake bundles.

### 4. Reduce gameplay UI tests to a smoke portfolio

`GameplayViewUITests.swift` keeps four distinct end-to-end flows:

1. enter gameplay and navigate back;
2. open the bundled `蒼穹への翔歌` fixture;
3. verify gameplay replaces the tab shell;
4. play/pause/restart one session.

Keep `GameplayBGMFailureUITests.swift` as the critical alert flow.

Delete repeated header/control/title assertions, sheet-music-by-inference checks, duplicate playback sequences, and stress/multi-track cases that do not own a unique product contract.

### 5. Fixed-wait cleanup is folded into touched tests

HPA-583 still owns simple fixed-wait cleanup, but there is no standalone repo-wide wait inventory.

When a test is moved or retained during Tasks 1-3:

- remove a fixed wait only if an existing deterministic/local seam already makes it unnecessary;
- leave intentional speed-debounce, MIDI, metronome, AVFoundation, and other framework-timing waits alone;
- do not add clocks, schedulers, continuations, protocols, production callbacks, or a generalized waiter.

At closeout, search the changed test files for fixed waits and record any intentionally retained categories. Unrelated test files are out of scope.

### 6. Documentation cleanup favors deletion and one source of truth

`CLAUDE.md` / `AGENTS.md` remains the implementation/architecture source of truth.

Replace the stale `.github/README.md` with one concise root `README.md` covering project purpose, supported platforms, basic setup, and links to the canonical architecture/testing guidance in `CLAUDE.md`. Do not duplicate exact test-command blocks in README.

Delete `docs/Project_Architecture_Blueprint.md`; Git history is the archive and the file has no current runtime reference.

Remove the tracked `.superpowers/` subtree. It is already ignored and the tracked contents are generated SDD task/profile/verification reports.

Do not sweep `docs/superpowers/specs` or `docs/superpowers/plans`. Historical specs/plans stay unless directly touched for another concrete reason; HPA-583 will not perform documentation archaeology.

Keep `CLAUDE.md` edits narrow:

- tests are named/owned by behavior rather than coverage campaigns;
- exact commands remain canonical there, replacing the stale `.github/README.md` note;
- notation virtualization is not an established requirement because HPA-584 produced no validated interactive performance claim.

Do not add generic prose about generated reports once the tracked report tree is gone.

### 7. Codecov becomes genuinely informational

Set both `coverage.status.project.default.informational` and `coverage.status.patch.default.informational` to `true` in `codecov.yml`.

This does not remove coverage from the closeout. Because production code is expected to remain unchanged, compare base-vs-head production coverage from CI artifacts after the test sweep. Any production line covered on the base result but not on the head result must be explained before merge.

That comparison is a regression signal, not a target percentage and not a new permanent metrics framework. The assertion-level disposition map remains the primary ownership proof.

### 8. Measure with the exact base/head CI runs

Do not spend two additional local full-suite runs to create a baseline.

Base SHA `797c2e08c3794dee6d9c0e3b1848f29e1e3f236d` already has green runs using the current workflows and runner classes:

- CI run `37015199788`;
- macOS UI Tests run `37015199830`.

Their test-result/coverage artifacts are still available. Record the base job/step wall times and coverage from those runs.

After implementation and focused local verification, mark the PR ready for review so the workflows run (draft PRs skip CI/UI jobs). Use the resulting head CI/UI runs for the after measurement and coverage comparison.

Record timing and notable test/file reductions in the PR/Linear closeout only.

## Scope guardrails

- exactly one PR for HPA-583;
- no production feature behavior changes;
- no custom test framework or snapshot platform;
- no new production clock/scheduler/repository/protocol solely for tests;
- no Codecov percentage target;
- no row virtualization/performance implementation from HPA-584;
- no backward-compatibility work for pre-release data;
- no repo-wide fixed-wait inventory;
- no historical docs archaeology;
- no new image/audio assets.

If a migration exposes a real production bug, preserve the failing regression and create a separate ticket unless the repair is trivial and inseparable from keeping the current contract green.

## Acceptance

HPA-583 is complete when:

- campaign-style behavior tests are moved/deleted with a reviewable disposition map;
- genuine shared support files remain where they are still used;
- high-value notation/timing/persistence protections remain;
- gameplay UI coverage is four non-duplicative flows plus the BGM-failure alert;
- one hosted-unit-test `Bundle.main` Soukyuu packaging smoke proves `bgm.m4a` and non-empty charts;
- importer missing-resource/deletion-gate coverage survives in the focused owner without duplicate synthetic positives;
- fixed waits in touched tests are removed only where an existing/local seam makes that trivial;
- the stale `.github/README.md`, architecture blueprint, and tracked `.superpowers/` reports are gone, with one concise root README and `CLAUDE.md` as source of truth;
- Codecov project/patch statuses are informational;
- base-vs-head CI timing and production coverage are compared and notable reductions recorded;
- no new production testing architecture is introduced.
