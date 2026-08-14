# HPA-581 Task 2 report: isolate static gameplay notation

## Outcome

Task 2 is complete on the isolated worktree at
`/Users/chanwaichan/workspace/Virgo/.worktrees/hpa-581-off-main-notation`.
The live gameplay sheet now observes only O(1) frame/playback values and an
immutable static notation projection. The static projection is an Equatable
child whose identity is the existing authoritative `notationLayoutGeneration`.

## Implementation

- Removed the view-model's `staticStaffLinesView` and `notationStaffLinesView`
  `AnyView` caches and deleted their creator.
- Added `GameplayStaticNotationInput`, a value projection containing the
  installed layout, legacy positions/height, time signature, renderability, and
  generation. Equality is generation-only.
- Added the private `GameplayStaticNotationView` and applied `.equatable()`.
  Its immutable subtree owns staff lines, measure bars, clefs/time signatures,
  all notation primitives, and the row-anchor column. It receives no
  `GameplayViewModel`.
- Changed `GameplayPlayheadBarView` to accept only an optional position tuple.
  Playback and auto-scroll observation remain in the surrounding
  `ScrollViewReader` container.
- Kept renderability as an install-time predicate and the playable-note query
  as an O(1) layout query, so visual-update paths do not scan notation arrays.
- Preserved value-based wrappers used by mounting/layout probes; they are not
  evaluated by the mounted playback-observed sheet.
- Reset the legacy content-height scalar along the existing fatal/no-track
  layout-reset paths.

## Files changed

- `Virgo/viewmodels/GameplayViewModel.swift`
- `Virgo/viewmodels/GameplayViewModel+Computations.swift`
- `Virgo/viewmodels/GameplayViewModel+VisualUpdates.swift`
- `Virgo/views/subviews/GameplaySheetMusicView.swift`
- `VirgoTests/GameplayViewModelLayoutComputationsTests.swift`
- `VirgoTests/GameplayViewModelDataLoadingTests.swift`
- `VirgoTests/GameplayViewModelCoverageTestSupport.swift`
- `VirgoTests/GameplayRenderCoverageTests.swift`

`GameplaySheetMusicMountingTests` and `DrumTabPlayheadAlignmentTests` were
preserved and verified without source edits.

## TDD evidence

### RED

The regression was added before the production static-input API. Exact command:

```bash
xcodebuild test -project Virgo.xcodeproj -scheme Virgo \
  -destination 'platform=macOS' -configuration Debug \
  -only-testing:VirgoTests/GameplaySheetMusicMountingTests \
  -only-testing:VirgoTests/GameplayViewModelLayoutComputationsTests \
  -only-testing:VirgoTests/DrumTabPlayheadAlignmentTests \
  -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -destination-timeout 300 -derivedDataPath ./DerivedData
```

Result: exited 65 (`** TEST FAILED **`) during test-target compilation. The
first decisive diagnostic was `value of type 'GameplayView' has no member
'staticNotationInput'` at the new regression call sites (with follow-on
key-path inference diagnostics), proving the test exercised the missing
boundary rather than passing against the old implementation.

### GREEN

The same exact command, after the implementation, finished with:

```text
Test run with 25 tests in 3 suites passed after 1.603 seconds.
** TEST SUCCEEDED **
```

The focused command was rerun once more after the final O(1) playable-query
adjustment and produced the same `25 tests in 3 suites` / `** TEST SUCCEEDED **`
result.

## Additional verification

All commands were serialized with `-parallel-testing-enabled NO`:

- `GameplayRenderCoverageTests`: 13 tests passed.
- `GameplayViewModelDataLoadingTests`: 19 tests passed.
- `GameplayViewModelComputationsTests`: 14 tests passed.
- `SwiftUIRenderingCoverageTests` + `SwiftUIRenderingNotationTests`: 24 tests
  passed.
- `DrumTabRenderProbeTests`: 2 tests passed.
- `git diff --check`: clean.
- `swiftlint lint --no-cache`: completed with 168 existing warnings and 0
  serious violations; the staged-file pre-commit lint also passed. Warnings
  are existing size/line-length and Swift-concurrency diagnostics in touched
  or unrelated files.

## Self-review

- `rg` finds no production `AnyView`, `staticStaffLinesView`,
  `notationStaffLinesView`, or `cacheNotationStaffLinesView` references.
- The static child has no view-model property and uses generation-only
  equality with `.equatable()`; no `.id(generation)` was introduced.
- Static derivations (measure mapping, row scan, note-head spacing, printed
  rest filtering, layer construction, and row anchors) occur under the static
  child. The parent sheet body computes only scalar frame values, immutable
  input, playhead position, and playback/auto-scroll hooks.
- The existing layout generation remains the sole authority; no async
  preparation, request token, worker, actor, service, scheduler, registry,
  Sendable, unsafe annotation, resize workaround, or Phase B code was added.

## Commits

- Implementation: `c461778` — `refactor(HPA-581): isolate static gameplay notation`
- This report: committed separately after implementation (see the follow-up
  report commit in the handoff).

## Risks and deferrals

- This task did not include a new Instruments/profile run; Phase B profiling is
  intentionally deferred until after static isolation.
- The compatibility wrappers retained for existing raster/layout probes can
  still perform their own scans when called directly by tests. They are not in
  the live playback-observed container path.
- Existing SwiftLint and macOS AppIntents/service warnings remain unchanged.
