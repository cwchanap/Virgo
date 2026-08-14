# HPA-581 Task 1 Report

## Implementation

- Confirmed the pre-edit production assignment sites with `rg -n 'cachedNotationLayout\\s*=' Virgo`: the normal install and no-track reset in `GameplayViewModel+Computations.swift`, the fatal-timing reset in `GameplayViewModel.swift`, and the stored-property declaration.
- Added private `notationLayoutStorage`, read-only `cachedNotationLayout`, and `private(set)` `notationLayoutGeneration` to `GameplayViewModel`.
- Added the single synchronous MainActor `installNotationLayout(_:)` funnel. It advances the one generation with `&+= 1` and stores the layout.
- Routed normal layout installation, no-track/empty reset, and fatal-rhythm-timing reset through the funnel.
- Migrated test-only direct layout mutations to install the replacement layout through the same seam; no production writer remains outside the funnel.
- Added deterministic coverage for normal installation, no-track reset, fatal reset, repeated-install generation uniqueness, and read-only generation exposure.
- No manager/service/worker/request counter, async preparation, static-view extraction, identity removal, or profiling was added; existing synchronous MainActor behavior remains unchanged.

## Files changed

- `Virgo/viewmodels/GameplayViewModel.swift`
- `Virgo/viewmodels/GameplayViewModel+Computations.swift`
- `VirgoTests/GameplayViewModelLayoutComputationsTests.swift`
- `VirgoTests/GameplayViewModelDataLoadingTests.swift`
- `VirgoTests/GameplayViewModelComputationsTests.swift`
- `VirgoTests/GameplaySheetMusicMountingTests.swift`
- `VirgoTests/SwiftUIRenderingCoverageTests.swift`
- `VirgoTests/SwiftUIRenderingNotationTests.swift`

## TDD evidence

### RED

After adding the generation tests and before production edits:

```text
xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' -configuration Debug \
  -only-testing:VirgoTests/GameplayViewModelLayoutComputationsTests \
  -only-testing:VirgoTests/GameplayViewModelDataLoadingTests \
  -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -destination-timeout 300 -derivedDataPath ./DerivedData
```

Exit 65. Compilation failed with four instances of:

```text
error: value of type 'GameplayViewModel' has no member 'notationLayoutGeneration'
Testing cancelled because the build failed.
```

### GREEN

After the funnel implementation and test migration, the same focused command completed with:

```text
✔ Test run with 41 tests in 2 suites passed after 1.497 seconds.
** TEST SUCCEEDED **
```

Supplemental migrated-call-site coverage also passed:

- `GameplayViewModelComputationsTests`, `SwiftUIRenderingCoverageTests`, and `SwiftUIRenderingNotationTests`: 38 tests in 3 suites passed.
- `GameplaySheetMusicMountingTests`: 1 test in 1 suite passed.

## Self-review

- `rg -n 'cachedNotationLayout\\s*=' Virgo` now reports no production layout assignment; the only backing-storage assignment is inside `installNotationLayout(_:)`.
- `notationLayoutStorage` is private and `notationLayoutGeneration` uses `private(set)`, so callers/extensions can read state but cannot bypass the install seam or assign the generation.
- `git diff --check` passed.
- `swiftlint lint --no-cache` exited 0: 169 repository warnings, 0 serious violations. The staged pre-commit lint also passed; warnings are existing size/line-limit violations.

## Commits

- `fe8f620 refactor(HPA-581): centralize notation layout installation`

## Concerns / follow-up

The async worker phase is intentionally out of scope for Task 1. Its request allocation and `cleanup()` stale-result invalidation must continue to advance this same `notationLayoutGeneration` counter rather than introducing another token or counter.

## Review-fix round 1

### Findings addressed

1. Reset coverage now loads and installs a renderable layout before each reset. The no-track case clears `track` before `computeCachedLayoutData()`; the fatal case calls `cacheNotationLayout()` before `setupGameplay()`. Both assert the renderable precondition, a single generation advance, and an empty/non-renderable result. The uniqueness test now installs two differing layouts (`.empty` then the saved renderable layout) and asserts consecutive generations and resulting content.
2. The read-only test now uses generic overload classification: `notationLayoutGeneration` must resolve to the `KeyPath`/read-only overload, while the known writable `nextBeatId` must resolve to the `ReferenceWritableKeyPath`/writable overload. If the generation setter becomes externally writable, the first assertion changes to `.writable` and fails.

### TDD evidence

The correction was test-only on top of the already-implemented Task 1 production code. The predecessor baseline `b31bd41` provides the RED characterization for this exact focused command: exit 65 with `error: value of type 'GameplayViewModel' has no member 'notationLayoutGeneration'` and `Testing cancelled because the build failed.` The corrected tests therefore remain unbuildable on the pre-Task1 implementation while now exercising distinct reset/install semantics.

RED command:

```text
xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' -configuration Debug \
  -only-testing:VirgoTests/GameplayViewModelLayoutComputationsTests \
  -only-testing:VirgoTests/GameplayViewModelDataLoadingTests \
  -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -destination-timeout 300 -derivedDataPath ./DerivedData
```

Observed RED output: exit 65; four `error: value of type 'GameplayViewModel' has no member 'notationLayoutGeneration'` diagnostics; `Testing cancelled because the build failed.`

Final focused command (parallel testing disabled):

```text
xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' -configuration Debug \
  -only-testing:VirgoTests/GameplayViewModelLayoutComputationsTests \
  -only-testing:VirgoTests/GameplayViewModelDataLoadingTests \
  -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -destination-timeout 300 -derivedDataPath ./DerivedData
```

```text
✔ Test run with 41 tests in 2 suites passed after 1.577 seconds.
** TEST SUCCEEDED **
```

### Changed files

- `VirgoTests/GameplayViewModelLayoutComputationsTests.swift`
- `VirgoTests/GameplayViewModelDataLoadingTests.swift`

### Review-fix self-review

- `git diff --check` passed.
- Targeted SwiftLint exited 0 with 3 pre-existing warnings and 0 serious violations.
- No production files changed; the one-generation install funnel and synchronous MainActor behavior are unchanged.

### Commit

- `4ead51e test(HPA-581): strengthen notation generation coverage`
