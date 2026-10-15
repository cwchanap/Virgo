# HPA-583 Test Ownership and Architecture Guidance Closeout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Consolidate Virgo's campaign-era tests into behavior-owned suites, trim gameplay UI coverage, add one real app-bundle Soukyuu packaging regression, and simplify documentation/configuration without introducing production test architecture.

**Architecture:** Deletion-first maintenance. Existing focused owner suites and current production seams stay authoritative; campaign tests move or disappear, shared support remains, and documentation points to `CLAUDE.md`. Full before/after timing and production-coverage comparison use the exact base/head CI runs rather than duplicated local full-suite baselines.

**Tech Stack:** Swift 6 / Swift Testing / XCTest UI tests / SwiftUI / SwiftData / Xcode / GitHub Actions / Codecov / Markdown

**Spec:** `docs/superpowers/specs/2026-10-15-hpa-583-test-architecture-closeout-design.md`

## Global Constraints

- One Linear ticket -> one PR. Continue implementation on this HPA-583 PR.
- No production feature behavior changes unless a trivial correctness repair is inseparable from an existing contract.
- Prefer deletion/reuse over new helpers, clocks, schedulers, protocols, snapshot systems, or directory taxonomies.
- Do not retain weak tests to protect a Codecov percentage.
- Preserve real-DTX goldens, geometry invariants, production mounting/raster/accessibility smoke, playhead alignment, rhythm/metronome/input boundaries, and current score persistence semantics.
- Do not implement notation row virtualization or make an eager-renderer performance claim; HPA-584 ended without validated interactive performance evidence.
- Remove fixed waits only while touching a test and only when an existing local deterministic seam already replaces the wait.
- No pre-release backward compatibility work.
- No new image/audio assets.

## Review Focus

1. **App fixture packaging silently breaks.** The positive regression must use hosted-test `Bundle.main`, not a copied test-bundle fixture, and must assert `bgm.m4a` plus non-empty charts.
2. **Campaign deletion loses a unique assertion.** Every source campaign file gets a test-by-test disposition recorded in the PR before deletion and in the deleting commit body.
3. **Importer dedupe removes a distinct branch.** Preserve one isolated missing-`SET.def` negative and the deletion-gate behaviors while deleting the weaker Patch duplicate and synthetic positive.
4. **UI cleanup removes the tab-shell replacement proof.** Keep explicit gameplay-mounted / `appTabShell`-absent coverage plus bundled Soukyuu open and play/pause/restart.
5. **Coverage/config cleanup turns into a new quota.** Codecov becomes informational; base-vs-head line coverage is only a regression diff because production code is unchanged.

---

### Task 1: Record the base evidence and consolidate bundled-import ownership

**Files:**
- Modify: `VirgoTests/LocalDTXFixtureImporterTests.swift`
- Modify/delete relevant importer cases from: `VirgoTests/LocalDTXFixtureImporterCoverageTests.swift`
- Modify/delete relevant importer case/anchor from: `VirgoTests/PatchCoverageAdditionsTests.swift`
- Read: `Virgo/utilities/LocalDTXFixtureImporter.swift`
- Read: `Virgo.xcodeproj/project.pbxproj`
- Read: `.github/workflows/ci.yml`
- Read: `.github/workflows/ui-tests.yml`

**Interfaces:**
- Consumes: `LocalDTXFixtureImporter.importBundledSoukyuuIfAvailable(into:bundle:deletionStore:)`
- Produces: focused importer ownership containing the real app-bundle positive, one isolated missing-resource negative, and distinct deletion-gate regressions

- [ ] **Step 1: Record the exact base CI evidence**

Use base SHA `797c2e08c3794dee6d9c0e3b1848f29e1e3f236d`:

- CI run `37015199788`;
- macOS UI run `37015199830`.

Record in temporary working notes for PR/Linear closeout:

- CI `Run Tests on macOS` job wall time and `Run unit tests` step wall time;
- UI `Run UI Tests on macOS` job wall time and `Run UI tests` step wall time;
- base test-results / coverage artifact IDs needed for Task 5.

Do not run a second local full unit/UI baseline and do not add a metrics file.

- [ ] **Step 2: Add the real app-bundle positive regression**

Add `bundledSoukyuuImportsFromBuiltAppBundle()` to `LocalDTXFixtureImporterTests.swift`.

Use an isolated model container and isolated deletion store, but pass `Bundle.main` explicitly:

```swift
let song = try #require(
    try LocalDTXFixtureImporter.importBundledSoukyuuIfAvailable(
        into: context,
        bundle: .main,
        deletionStore: isolatedDeletionStore
    )
)
#expect(song.bgmFilePath?.hasSuffix("bgm.m4a") == true)
#expect(!song.charts.isEmpty)
```

Do not add test-target fixture membership and do not edit `project.pbxproj` for this regression.

- [ ] **Step 3: Move the stronger missing-`SET.def` negative into the owner suite**

Use the isolated fake-empty-bundle case from `LocalDTXFixtureImporterCoverageTests.importBundledSoukyuuReturnsNilWhenBundleLacksSETDef` as the owned negative. Preserve its isolated deletion store so a real `.standard` tombstone cannot make it pass for the wrong reason.

Delete the weaker `PatchCoverageAdditionsTests.testReturnsNilWhenBundleLacksSETDef` copy and delete `DTXFixtureTestBundleAnchor` when no other test uses it.

- [ ] **Step 4: Delete the synthetic positive and retain distinct deletion-gate cases**

Delete `LocalDTXFixtureImporterCoverageTests.importBundledSoukyuuImportsWhenBundleContainsFixture` after the real `Bundle.main` positive exists.

Move the deletion durability / existing-stable-ID / tombstone-clear cases into `LocalDTXFixtureImporterTests.swift` if they are not already owned elsewhere. They intentionally continue using isolated fake fixture bundles.

- [ ] **Step 5: Inspect waits only in the importer tests being touched**

Remove a fixed wait only if an existing awaited/local seam already makes it unnecessary. Do not inspect unrelated test files and do not add a generalized waiter.

- [ ] **Step 6: Run the focused importer suite**

Run the serial macOS `LocalDTXFixtureImporterTests` suite.

Expected: real `Bundle.main` positive, missing-resource negative, and deletion-gate regressions pass.

- [ ] **Step 7: Commit the importer ownership cut**

Commit the app-bundle smoke plus importer-case dedupe together because the old negative/synthetic-positive decisions are directly coupled to the new owned regression. Include the exact moved/deleted cases in the commit body.

---

### Task 2: Consolidate campaign-style unit files one source file at a time

**Files:**
- Inventory with: `git ls-files 'VirgoTests/*Coverage*.swift' 'VirgoTests/*Patch*.swift' 'VirgoTests/*Wave*.swift'`
- Keep shared support when still referenced, including:
  - `VirgoTests/GameplayViewModelCoverageTestSupport.swift`
  - `VirgoTests/SwiftUICoverageFixtures.swift`
- Prefer focused owners already present beside the campaign files, including importer, rendering, song/library/cache/input, gameplay computation/speed/BGM/playback/cleanup, notation, and metronome suites.

**Interfaces:**
- Consumes: existing focused owner suites and current test helpers
- Produces: reviewable behavior ownership with campaign source files deleted or explicitly justified as shared support

- [ ] **Step 1: Publish the disposition map before deleting campaign files**

For every inventory source file, record every test as one of:

- `move -> <owner>`;
- `duplicate -> delete`;
- `obsolete -> delete`;
- `keep support -> <current focused users>`.

Put the map directly in the PR body, or in one top-level PR comment linked from the body if it is too large. Do not keep the only copy in temporary notes.

- [ ] **Step 2: Migrate one campaign source file (or one inseparable pair)**

For each source file:

1. copy meaningful cases into existing focused owners;
2. run the focused owner suite serially;
3. delete duplicate/obsolete cases and the emptied campaign source;
4. inspect only the waits in cases touched by this migration; remove one only when an existing local seam makes it trivial;
5. update the PR disposition map if implementation facts differ from the planned disposition.

Do not create `*Coverage2Tests`, a new umbrella suite, or a folder taxonomy.

- [ ] **Step 3: Commit that source-file cut**

Use one commit per campaign source file, or one small inseparable pair. The commit body must include that source file's disposition lines so review/bisect evidence travels with the deletion.

Repeat Steps 2-3 until the inventory is exhausted.

- [ ] **Step 4: Verify shared support survives intentionally**

Search references to `GameplayViewModelCoverageTestSupport` and `SwiftUICoverageFixtures`. Keep them if focused suites still use them; do not rename them for naming purity.

- [ ] **Step 5: Verify the final campaign inventory**

Run:

```bash
git ls-files 'VirgoTests/*Coverage*.swift' 'VirgoTests/*Patch*.swift' 'VirgoTests/*Wave*.swift'
```

Expected: remaining matches are genuine shared support only, with rationale already present in the PR disposition map.

---

### Task 3: Reduce gameplay UI coverage to four flows plus the alert path

**Files:**
- Modify: `VirgoUITests/GameplayViewUITests.swift`
- Keep: `VirgoUITests/GameplayBGMFailureUITests.swift`
- Modify helpers only when dead after deletion: `VirgoUITests/UITestHelpers.swift`, `VirgoUITests/UITestHelpers+SongRow.swift`

**Interfaces:**
- Consumes: existing gameplay navigation/playback/song-row helpers
- Produces: four distinct gameplay smoke flows plus the existing BGM-failure alert

- [ ] **Step 1: Keep exactly the distinct gameplay contracts**

Retain/reshape one test for each:

1. enter gameplay and navigate back to Songs;
2. open bundled `蒼穹への翔歌`;
3. assert gameplay is mounted while `appTabShell` / tab shell is absent;
4. play/pause/restart one session and confirm controls remain usable.

Keep `GameplayBGMFailureUITests` unchanged unless helper deletion requires a mechanical update.

- [ ] **Step 2: Delete redundant gameplay UI cases**

Remove separate header, sheet-area-by-inference, controls-area, duplicate playback-sequence, generic accessibility-by-hittability, multi-track, and rapid-interaction cases unless implementation review identifies a unique product contract.

- [ ] **Step 3: Remove only newly dead UI helpers**

Do not refactor the helper layer. Delete only functions no retained UI test uses.

- [ ] **Step 4: Inspect waits only in the UI tests being touched**

Leave framework/UI synchronization waits alone unless an existing bounded helper already represents the state transition.

- [ ] **Step 5: Commit the UI portfolio reduction**

Commit the UI source/helper deletion as one reviewable UI cut. Full behavioral verification occurs in head CI in Task 5; no separate local 30-minute full UI baseline is required.

---

### Task 4: Simplify docs and make Codecov actually informational

**Files:**
- Move/rewrite: `.github/README.md` -> `README.md`
- Modify: `CLAUDE.md`
- Delete: `docs/Project_Architecture_Blueprint.md`
- Remove tracked generated tree: `.superpowers/`
- Modify: `codecov.yml`
- Do not sweep: `docs/superpowers/specs/`, `docs/superpowers/plans/`

**Interfaces:**
- Consumes: current guidance already in `CLAUDE.md`
- Produces: one concise repository entry point, one architecture source of truth, no tracked generated report tree, informational Codecov status

- [ ] **Step 1: Replace the stale `.github/README.md` with a root README**

Move/rewrite the README so the root file contains only:

- Virgo purpose;
- supported macOS/iPad platforms;
- basic setup entry point;
- a link to `CLAUDE.md` for exact test commands, CI policy, and architecture/contributor guidance.

Do not copy test command blocks into README.

- [ ] **Step 2: Make narrow durable `CLAUDE.md` edits**

- remove the stale `.github/README.md` warning after that file is gone;
- add one rule that behavior owns tests and campaign `Coverage`/`Patch` buckets are not owners;
- retain the current-format/package-backed/CI guidance already there;
- add one current guardrail: notation virtualization is not established as necessary because HPA-584 produced no validated interactive performance claim.

Do not add generic history about generated reports.

- [ ] **Step 3: Delete the stale architecture blueprint**

Delete `docs/Project_Architecture_Blueprint.md`; do not replace it with a pointer stub. Git history is the archive and `CLAUDE.md` is current guidance.

- [ ] **Step 4: Remove the tracked `.superpowers/` report tree**

The path is already ignored and its tracked contents are generated task/profile/verification reports. Remove the tracked subtree as a unit rather than performing per-report archaeology.

- [ ] **Step 5: Do not sweep historical specs/plans**

Leave `docs/superpowers/specs` and `docs/superpowers/plans` alone except for the two HPA-583 planning documents already in this PR.

- [ ] **Step 6: Make Codecov informational**

In `codecov.yml`, set both:

```yaml
coverage.status.project.default.informational: true
coverage.status.patch.default.informational: true
```

Leave targets/thresholds otherwise unchanged; they remain reporting context, not merge gates.

- [ ] **Step 7: Verify doc/config consistency**

Confirm:

- only root `README.md` remains;
- README links resolve to `CLAUDE.md`;
- no current guidance references the deleted blueprint or `.github/README.md`;
- `.superpowers/` has no tracked files;
- `codecov.yml` has no `informational: false` status.

- [ ] **Step 8: Commit docs/config cleanup**

One commit is sufficient because these files together establish the repository guidance/quality-policy surface.

---

### Task 5: Focused verification, head CI, coverage diff, and closeout

**Files:**
- No new source file required
- Update the PR body/comment and Linear HPA-583 with measured results

**Interfaces:**
- Consumes: Tasks 1-4
- Produces: evidence that deletion preserved current behavior and reduced maintenance cost

- [ ] **Step 1: Run package tests locally**

```bash
swift test --package-path Packages/DrumNotation
```

Expected: PASS.

- [ ] **Step 2: Run focused owner suites touched by Task 2**

Use serial macOS testing (`-parallel-testing-enabled NO`). Do not rerun an unrelated repo-wide fixed-wait inventory.

Expected: every migrated owner suite passes.

- [ ] **Step 3: Run SwiftLint and ownership/diff checks**

```bash
swiftlint lint
git ls-files 'VirgoTests/*Coverage*.swift' 'VirgoTests/*Patch*.swift' 'VirgoTests/*Wave*.swift'
git diff --check main...HEAD
```

Expected: no new lint errors; remaining campaign-named files are documented shared support only; clean diff check.

- [ ] **Step 4: Review the final diff before CI**

Expected production Swift delta: none. Expected implementation changes: tests, UI tests/helpers, `README.md`/`CLAUDE.md`, blueprint/report deletions, and `codecov.yml`.

If production Swift changed, either justify a trivial inseparable correctness repair or move it to another ticket and revert it here.

- [ ] **Step 5: Mark the draft PR ready for review**

Both `ci.yml` and `ui-tests.yml` skip draft PRs. Mark ready only after the focused local checks above are green so head CI becomes the authoritative full-suite verification.

- [ ] **Step 6: Require green head CI/UI/iPad jobs**

Wait for the PR-triggered workflows to complete and require:

- full serial macOS unit tests: PASS;
- macOS UI tests: PASS;
- iPad simulator build: PASS;
- package coverage upload/config steps: no configuration failure.

No iPhone destination is permitted.

- [ ] **Step 7: Compare base and head timing**

Compare the same base/head workflow jobs and test steps. Record both wall-time pairs in the PR/Linear closeout; do not turn the delta into a performance gate.

- [ ] **Step 8: Compare base and head production coverage**

Use the base CI `TestResults.xcresult` / coverage artifact and the corresponding head artifact. Export/report production coverage with `xcrun xccov view --report --json` (or equivalent data from the retained artifact).

Because production code is unchanged, flag any production line covered on base but not head. For each loss, either restore the uniquely valuable regression or explain why the deleted execution was intentionally redundant/obsolete.

Do not compare only the headline percentage and do not introduce a new permanent coverage-diff script unless existing commands are insufficient.

- [ ] **Step 9: Post closeout evidence**

Update PR/Linear with:

- final disposition map / links to campaign-file commits;
- unit/UI base vs head wall times;
- notable deleted/moved test files;
- intentionally retained fixed-wait categories encountered in touched tests;
- base-vs-head production coverage losses and their resolutions (expected: none unexplained);
- confirmation that Codecov is informational;
- confirmation that HPA-584 performance remains unverified and no virtualization work was introduced.

**Checkpoint:** HPA-583 ends as one PR with clearer behavior ownership, less duplicate test/UI/doc execution, a packaging regression that protects the shipped app bundle, and no new production testing architecture.
