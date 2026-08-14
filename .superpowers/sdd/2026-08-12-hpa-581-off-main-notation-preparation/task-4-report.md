# HPA-581 Task 4 Report — timeline notation value boundary

## Outcome

Task 4 is complete. The timeline/render value graph no longer carries
SwiftData object identity and the immutable worker-facing values have normal
compiler-checked `Sendable` conformances. Timeline diagnostics retain exact
`RhythmEventID` identity on the `@MainActor` runtime; legacy diagnostics now
report a count plus representative note metadata because exact model identity
is intentionally unavailable.

No async setup, detached task, worker, actor/service/scheduler/registry,
generation change, width behavior, `@unchecked Sendable`, or unsafe workaround
was added.

## TDD evidence

### RED before production edits

CodeGraph was run first for the timeline snapshot, rendered layout, note-head,
and dropped-diagnostic symbols. The tests were then added to
`RhythmLayoutSnapshotBuilderTests.swift` before touching production code.

The compile-time gate compiled on the baseline, as expected: `ObjectIdentifier`
itself can satisfy `Sendable`, so that gate cannot prove semantic identity
removal. The independent Mirror gate produced a real RED on the baseline:

```text
Expectation failed: !layoutLabels.contains("sourceObjectID")
Expectation failed: !renderedLabels.contains("sourceObjectID")
** TEST FAILED **
```

The baseline focused run exited 65. The compile-time test and the two existing
builder tests passed; the new structural test failed on both worker values.

### GREEN

Exact focused value/layout command from the brief, run serially with parallel
testing disabled:

```text
xcodebuild test -project Virgo.xcodeproj -scheme Virgo \
  -destination 'platform=macOS' -configuration Debug \
  -only-testing:VirgoTests/RhythmLayoutSnapshotBuilderTests \
  -only-testing:VirgoTests/NotationLayoutEngineTests \
  -only-testing:VirgoTests/NotationLayoutNotePositionOverrideTests \
  -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -destination-timeout 300 -derivedDataPath ./DerivedData
```

Result: **TEST SUCCEEDED**, 92 tests in 3 suites.

Exact production-layout geometry/identity command from the brief, run after
the first group and before any async wiring:

```text
xcodebuild test -project Virgo.xcodeproj -scheme Virgo \
  -destination 'platform=macOS' -configuration Debug \
  -only-testing:VirgoTests/DrumTabGoldenTests \
  -only-testing:VirgoTests/DrumTabRegressionInvariantTests \
  -only-testing:VirgoTests/DrumTabPlayheadAlignmentTests \
  -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -destination-timeout 300 -derivedDataPath ./DerivedData
```

Result: **TEST SUCCEEDED**, 19 tests in 3 suites. Goldens, beam/grid/painted
bounds invariants, simultaneous-column identity, and playhead alignment all
passed.

Narrow caller verification for the changed `GameplayViewModel` diagnostics
path:

```text
xcodebuild test -project Virgo.xcodeproj -scheme Virgo \
  -destination 'platform=macOS' -configuration Debug \
  -only-testing:VirgoTests/GameplayViewModelComputationsTests \
  -only-testing:VirgoTests/GameplayViewModelLayoutComputationsTests \
  -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -destination-timeout 300 -derivedDataPath ./DerivedData
```

Result: **TEST SUCCEEDED**, 37 tests in 2 suites.

## Implementation and invariant evidence

Production changes:

- `RhythmLayoutNote.sourceObjectID` and `RenderedNoteHead.sourceObjectID`
  were removed. `RhythmLayoutSnapshot`, `RhythmLayoutControl`,
  `RhythmLayoutRest`, and the timeline/render graph values now use normal
  `Sendable` conformances where their immutable members are compiler-proven
  safe.
- `NotationControlEventKind` and `NotationControlEvent` gained `Sendable`.
  The SwiftData `ChartControlEvent` model remains a non-Sendable `final class`.
- `RhythmLayoutSnapshotBuilder` no longer creates model object identity.
  Timeline `RenderedNoteHead.eventID` remains the source identity.
- `RenderedNoteHead.id` remains `UInt64`; the legacy renderer still assigns
  the stable array discriminator and timeline rendering still uses the stable
  event-derived rendered ID. The identity-sensitive layout test explicitly
  asserts the legacy rendered ID remains stable, and the duplicate-head test
  continues to assert distinct rendered IDs and lookup entries.
- Timeline dropped-note diagnostics compare rendered event IDs with
  `GameplayRhythmRuntime.noteByEventID` on `@MainActor` and include the exact
  event ID in representative metadata. Legacy diagnostics explicitly say
  exact model identity is unavailable and report count plus representative
  note type/measure metadata.

Structural checks after implementation:

```text
rg -n "sourceObjectID" Virgo VirgoTests
VirgoTests/RhythmLayoutSnapshotBuilderTests.swift:45: #expect(!layoutLabels.contains("sourceObjectID"))
VirgoTests/RhythmLayoutSnapshotBuilderTests.swift:46: #expect(!renderedLabels.contains("sourceObjectID"))
```

There are no production `sourceObjectID` references. `NotationLayoutInput`
remains an unannotated non-Sendable struct with its legacy `[Note]` path.
`notationLayoutGeneration` is unchanged. No `@unchecked Sendable` was added to
the touched production graph, and no new async/concurrency lifecycle was
introduced.

## Files changed

Production:

- `Virgo/layout/NotationLayout.swift`
- `Virgo/layout/NotationLayoutEngine+RhythmRendering.swift`
- `Virgo/layout/NotationLayoutEngine.swift`
- `Virgo/layout/NotationRhythmRendering.swift`
- `Virgo/layout/RhythmLayoutSnapshotBuilder.swift`
- `Virgo/models/ChartControlEvent.swift`
- `Virgo/models/RhythmMetadata.swift`
- `Virgo/viewmodels/GameplayViewModel+Computations.swift`

Tests updated for the removed initializer/API and boundary assertions:

- `VirgoTests/NotationLayoutDefensiveGuardTests.swift`
- `VirgoTests/NotationLayoutEngineTests.swift`
- `VirgoTests/NotationLayoutNotePositionOverrideTests.swift`
- `VirgoTests/NotationLayoutRhythmTests.swift`
- `VirgoTests/RhythmLayoutSnapshotBuilderTests.swift`
- `VirgoTests/RhythmRenderingTests.swift`
- `VirgoTests/SwiftUIRenderingNotationTests.swift`

## Diff, lint, and commits

- `git diff --check`: passed before the source commit; the post-commit tree
  remains clean before this report is added.
- Manual `swiftlint lint`: scanned 324 files and reported 168 existing
  warnings, 0 serious violations. The command then exited 1 because the
  sandbox denied a generated plist write. No lint auto-fix was run. The
  repository pre-commit hook separately linted all staged Swift files and
  passed, with the existing size/function warnings listed by the hook.
- Source implementation commit:
  `9e0f2f6` (`refactor(HPA-581): make timeline notation values sendable`).
- Report commit: recorded in the final handoff and in the commit history
  after this file is committed separately.

## Concerns

- The full `VirgoTests` suite was not required for this value-boundary task;
  the exact Task 4 groups and the narrow caller suites passed.
- Task 3 concluded `GATE: PROCEED` via headless Release evidence at `c3af370`.
  The compositor/visible-UI limitation remains documented; this Task 4 report
  adds no interactive GUI profiling evidence.
