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
