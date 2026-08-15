# HPA-581 Task 6 Report — dispatch timeline notation preparation off-main

## Scope and baseline

- Worktree: `.worktrees/hpa-581-off-main-notation` (relative to the repository root)
- Accepted baseline: `b8ed0a4`
- Task 3's headless Release profiling gate was already `GATE: PROCEED`; this task report records no new profile claim.
- CodeGraph was used before source exploration.

## Implementation

- `GameplayViewModel.setupGameplay(loadPersistedSpeed:)` is now the single async setup API. The production lifecycle caller and every compiler-found test caller await it; no synchronous wrapper was added.
- Valid timeline snapshots build `GameplayNotationPreparationRequest` on the main actor, then run only `GameplayNotationPreparer.prepare(request)` inside `Task.detached(priority: .userInitiated)`. SwiftData/model references, resolver maps, diagnostics, UserDefaults lookup, BGM, metronome, and input setup remain on the main actor. The legacy `[Note]` `NotationLayoutInput` path remains synchronous/on-main.
- The existing `notationLayoutGeneration` is the only freshness identity. Setup allocates the generation before dispatch, current results install through the existing funnel without a second increment, and stale results update no layout/cache/readiness state. Cleanup advances the same generation and cancels the retained task only as resource control.
- Prepared timeline state installs its layout, row/measure maps, note-head coordinates, and beat coordinates coherently before `isGameplayPrepared` becomes true.
- Existing row-width flooring, `> 0.5` tolerance, and prepared-sheet 100 ms trailing-edge debounce remain unchanged. Width changes during initial preparation are handled by the existing post-mount width path; no width retry loop or second width generation was added.
- Freshness tests are direct deterministic apply/lifecycle tests; they do not sleep or race real detached tasks.

## Files changed

Production:

- `Virgo/viewmodels/GameplayViewModel.swift`
- `Virgo/viewmodels/GameplayViewModel+Computations.swift`
- `Virgo/viewmodels/GameplayViewModel+Playback.swift`
- `Virgo/views/GameplayView.swift`

Tests and callers:

- `VirgoTests/GameplayViewModelLayoutComputationsTests.swift`
- `VirgoTests/GameplayViewModelCleanupTests.swift`
- Every other `VirgoTests` file reported by `rg -n 'setupGameplay\\(' Virgo VirgoTests` that contained a call was mechanically updated to await the async API.

## TDD evidence

### RED

After adding the direct stale/current-generation and cleanup tests, before production edits, the required focused command was run serially:

```text
xcodebuild test -project Virgo.xcodeproj -scheme Virgo \
  -destination 'platform=macOS' -configuration Debug \
  -only-testing:VirgoTests/GameplayViewModelLayoutComputationsTests \
  -only-testing:VirgoTests/GameplayViewModelCleanupTests \
  -only-testing:VirgoTests/GameplayViewTests \
  -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -destination-timeout 300 -derivedDataPath ./DerivedData
```

Observed result: exit `65`; compilation failed because the production apply/lifecycle seams did not yet exist (`GameplayViewModel` had no `beginNotationPreparation` / `applyPreparedNotation`). No tests ran. The pre-migration `await setupGameplay` call sites also produced the expected async-migration warning.

### GREEN — required focused command

The same exact serial command completed successfully after implementation:

```text
✔ Test run with 55 tests in 3 suites passed after 2.492 seconds.
** TEST SUCCEEDED **
```

Covered suites:

- `GameplayViewModelLayoutComputationsTests`
- `GameplayViewModelCleanupTests`
- `GameplayViewTests`

The focused run includes direct stale-result rejection, current-generation single-increment apply, pinned row/coordinate-map setup, and cleanup invalidation coverage.

### Supplemental verification

The existing fatal/nil/reset owner passed after the async migration and fatal-reset generation preservation:

```text
xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' \
  -configuration Debug -only-testing:VirgoTests/GameplayViewModelDataLoadingTests \
  -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO -destination-timeout 300 -derivedDataPath ./DerivedData

✔ Test run with 19 tests in 1 suite passed.
** TEST SUCCEEDED **
```

All mechanically changed caller suites were covered by this serial full unit run:

```text
xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' \
  -configuration Debug -only-testing:VirgoTests -parallel-testing-enabled NO \
  ONLY_ACTIVE_ARCH=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -enableCodeCoverage YES -destination-timeout 300 -derivedDataPath ./DerivedData

━ Test run with 1857 tests in 177 suites passed after 172.391 seconds with 1 known issue.
** TEST SUCCEEDED **
```

The harness reported one known issue while still completing the run successfully; no test failure occurred.

Additional checks:

- `git diff --check`: passed.
- `swiftlint lint --no-cache`: exit `0`, 168 repository warnings, 0 serious violations. The staged hook also passed; warnings are existing size/line-limit warnings in touched and untouched files.
- A final `rg` scan found no unawaited `setupGameplay(` call sites.

## Commit

- Implementation: `49ffb72 feat(HPA-581): prepare timeline notation off main actor`
- Report commit: recorded separately after this report is staged.
