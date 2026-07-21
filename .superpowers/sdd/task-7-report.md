# Task 7 Report: Model-Free Input Targets, Scoring Identity, and Speed Reconfiguration

## Status

Complete. Gameplay input now matches immutable rhythm-timeline targets, returns stable event/tick/seconds identity,
deduplicates scoring by event ID, scans misses in effective target seconds, and atomically reinstalls the same targets
when practice speed changes. The legacy matcher remains available through the source-compatible configuration wrapper.

Required commit message: `feat: match input against rhythm timeline`

## TDD Evidence

### RED 1: immutable target and timeline configuration contracts

The initial `RhythmInputTimingTests` run failed before production changes with exit 65 and the expected missing API
diagnostics:

```text
Cannot find 'RhythmNoteTarget' in scope
Missing argument label 'configuration:' in call
Type 'InputTimingConfiguration' has no member 'timeline'
```

The minimum implementation added immutable timeline targets, the explicit timeline/legacy configuration boundary,
timeline result fields, and stable seconds/event-ID matching while preserving the legacy initializer.

### RED 2: timeline scoring identity and miss scanning

The first scoring tests failed to compile on the wished-for timeline caches and seconds-based scan:

```text
GameplayViewModel has no member 'cachedRhythmNoteTargets'
GameplayViewModel has no member 'cachedNoteByRhythmEventID'
GameplayViewModel has no member 'scoredRhythmEventIDs'
Incorrect argument label in call (have 'upToSeconds:', expected 'upToTimePosition:')
```

The GREEN implementation caches the resolved timeline, immutable one-X targets, and a MainActor-only event-ID-to-note
lookup during chart loading. Timeline hits and misses use stable event IDs and effective seconds; the legacy object-ID
and fractional-position path remains isolated to legacy results.

### RED 3: speed reconfiguration

Paused and playing speed-change tests initially returned `nil` event identity and target position because the old
fixed-measure matcher was reinstalled. The corrected path preserves the one-X target array, installs the new speed
atomically with its elapsed offset, and never transitions through legacy matching.

### RED 4: inverse-position safety

An inconsistent target-scale counterexample initially produced a synthetic hit position. Timeline inverse mapping now
requires at least one positive-tick target and a finite, positive, consistent one-X seconds-per-tick scale. Matching
identity remains available when inverse position is intentionally `nil`.

## GREEN Results

Final requested focused matrix, parallel testing disabled:

```text
Result: Passed
Total tests: 93
Failed: 0
Skipped: 0
xcresult: DerivedData/Logs/Test/Test-Virgo-2026.07.21_12-58-40--0700.xcresult
```

Full nonparallel unit suite with code coverage:

```text
Result: Passed
Total tests: 1781
Failed: 0
Skipped: 0
Device-expanded runs: 1821 (dynamic parameters)
xcresult: DerivedData/Logs/Test/Test-Virgo-2026.07.21_12-59-17--0700.xcresult
```

Additional checks:

- `rtk swiftlint lint --no-cache`: completed across 291 files with 156 warnings and 0 serious violations.
- `rtk git diff --check`: passed.

## Implemented Semantics

- `RhythmNoteTarget` snapshots carry stable event ID, drum type, exact timeline position, and one-X target seconds.
- `InputTimingMatcher` sorts timeline targets by effective seconds then event ID and retains no SwiftData `Note` in
  timeline state or results.
- `NoteMatchResult` exposes optional event, target position/seconds, hit seconds, and inverse hit position fields while
  preserving optional legacy note and measure fields without sentinel values.
- `InputManager.configure(_:, elapsedOffset:)` constructs a matcher outside the runtime queue and atomically replaces
  matcher, timing mirrors, legacy-note retention, and elapsed origin in one queue mutation.
- Gameplay chart loading resolves targets and the UI note lookup once on the MainActor. Duplicate hits use event IDs;
  same-time events remain independently scoreable.
- Timeline missed-note scanning advances a target-seconds-sorted cursor with the existing 100 ms late boundary.
- Paused and playing speed changes retain target identity and atomically reinstall the timeline matcher with effective
  target seconds derived from the new multiplier.
- The input delegate recognizes event-ID matches and logs exact timeline measure/tick positions when available.
- Completion and skip-to-end paths choose timeline seconds scanning only for timeline-backed gameplay; legacy behavior
  remains unchanged.

## Files

- `Virgo/utilities/InputTimingMatcher.swift`
- `Virgo/utilities/InputManager.swift`
- `Virgo/views/GameplayView+InputManagerDelegate.swift`
- `Virgo/viewmodels/GameplayViewModel.swift`
- `Virgo/viewmodels/GameplayViewModel+Computations.swift`
- `Virgo/viewmodels/GameplayViewModel+Playback.swift`
- `Virgo/viewmodels/GameplayViewModel+SpeedControl.swift`
- `Virgo/viewmodels/GameplayViewModel+VisualUpdates.swift`
- `VirgoTests/RhythmInputTimingTests.swift` (new)
- `VirgoTests/InputTimingMatcherTests.swift`
- `VirgoTests/GameplayViewModelScoringTests.swift`
- `VirgoTests/GameplayViewModelSpeedTests.swift`

## Self-review and Concerns

- Audited callback state for SwiftData retention, event-ID tie breaking, hit/error sign, exact late-window behavior,
  speed transitions, paused resume offsets, completion scanning, and legacy compatibility.
- No Task 8 metronome schedule, BGM anchor, playhead ownership, layout snapshot, or fatal-state UI work was added.
- `GameplayViewModel+Computations.swift` now crosses SwiftLint's warning-level 600-line threshold, and the repository
  retains other warning-level size/line findings. SwiftLint reports no serious violations.
- Progress ledger unchanged as required.
