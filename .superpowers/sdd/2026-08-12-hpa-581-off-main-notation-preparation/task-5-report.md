# HPA-581 Task 5 Report — pure notation preparation boundary

## Outcome

Task 5 is complete. The pure `GameplayNotationPreparationRequest` /
`GameplayNotationPreparedState` boundary prepares timeline notation synchronously
through the existing `NotationLayoutInput` and `NotationLayoutEngine` path, then
returns the prepared layout and the existing TabGrid/staff-line beat coordinates.

The request and result are normal compiler-checked `Sendable` values. The legacy
`NotationLayoutInput` and `[Note]` path remain non-Sendable and are not moved
across the boundary. No async or detached task, `GameplayViewModel` setup change,
actor/service/worker/scheduler/registry, generation/width/cleanup/rendering
change, or `@unchecked Sendable` was added.

The project uses `PBXFileSystemSynchronizedRootGroup` for both `Virgo` and
`VirgoTests`, so the new source and test files are automatically target members;
the focused build compiled both files without a `project.pbxproj` edit.

## TDD evidence

CodeGraph was run first for the notation input, timeline layout engine, TabGrid,
and gameplay beat-coordinate symbols. The tests were then added before the
production boundary.

### RED before production edits

Exact focused RED command:

```text
xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=macOS' -configuration Debug \
  -only-testing:VirgoTests/GameplayNotationPreparationTests \
  -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -destination-timeout 300 -derivedDataPath ./DerivedData
```

The test target compiled far enough to discover the new suite, then exited 65
because the production boundary did not yet exist:

```text
error: cannot find 'GameplayNotationPreparationRequest' in scope
error: cannot find 'GameplayNotationPreparedState' in scope
error: cannot find 'GameplayNotationPreparer' in scope
** TEST FAILED **
```

### GREEN

Exact focused serial GREEN command from the task brief:

```text
xcodebuild test -project Virgo.xcodeproj -scheme Virgo \
  -destination 'platform=macOS' -configuration Debug \
  -only-testing:VirgoTests/GameplayNotationPreparationTests \
  -only-testing:VirgoTests/NotationLayoutEngineTests \
  -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -destination-timeout 300 -derivedDataPath ./DerivedData
```

Result: **TEST SUCCEEDED**, 88 tests in 2 suites passed. The new suite's four
tests cover the compile-time Sendable gate, pinned coordinates across wrapped
rows, printable renderable content without playable notes, and the absence of
model-identity fields. The existing Notation Layout Engine suite also passed.

## Implementation and invariant evidence

- `GameplayNotationPreparer.prepare` constructs `.timeline(request.snapshot)`
  in the existing `NotationLayoutInput` and calls `NotationLayoutEngine`.
- Beat positions use `layout.tabGrid.xPosition(in:localTick:)` and the existing
  `GameplayLayout.StaffLinePosition.line3` row coordinate; no parallel layout
  or grid math was introduced.
- `DrumType` and `GameplayLayout.NotePosition` now declare ordinary `Sendable`
  conformances in their defining files so the requested dictionary fields pass
  the compiler gate without retroactive or unchecked conformance.
- The boundary contains no SwiftData/model identity, SwiftUI, `Task`, async,
  actor, or worker lifecycle API.

## Files changed

- `Virgo/layout/GameplayNotationPreparation.swift`
- `VirgoTests/GameplayNotationPreparationTests.swift`
- `Virgo/constants/Drum.swift` (normal `DrumType: Sendable` conformance)
- `Virgo/layout/gameplay.swift` (normal `GameplayLayout.NotePosition: Sendable`
  conformance)

`Virgo.xcodeproj/project.pbxproj` was intentionally left unchanged because its
synchronized root groups provide target membership by filesystem path; the
focused build is the membership verification.

## Diff and commits

- `git diff --check`: passed before the source commit.
- Source implementation commit: `c8139b2c3b222a2ecdd165af62efc47057e26c8a`
  (`feat(HPA-581): add pure notation preparation boundary`).
- Report commit: recorded separately after this report is committed.
- After the report commit, `git status --short --branch` is expected to show a
  clean worktree.

## Limitations

This task adds only the pure request/result boundary. No caller migration or
off-main execution is included; those remain outside Task 5's assigned scope.
