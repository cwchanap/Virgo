# Task 8 Report: Timeline Gameplay, Metronome Schedule, BGM Anchor, and Duration Precedence

## Status

Complete. Valid rhythm charts now cache one immutable gameplay runtime and use it for notation layout, input targets,
metronome pulses, duration, BGM anchoring, continuous playhead position, row changes, miss scanning, pause/resume, and
speed reseating. Legacy DTX-origin charts without a persisted timing payload retain the fixed-measure path. Timing-fatal
charts cannot prepare or start practice and render a fatal sheet-music message.

Required commit message: `feat: drive gameplay from rhythm timeline`

## TDD Evidence

### RED 1: pulse policy, allocation bound, and cursor invalidation

The first focused schedule run failed to compile on the wished-for `RhythmMetronomeSchedule`, pulse, accent-level, and
cursor APIs. The GREEN implementation added:

- quarter-note pulses for X/4;
- eighth-note pulses for 6/8, 7/8, 9/8, and 12/8;
- downbeat/group accents for unambiguous meters and downbeat-only accent for 7/8;
- residual pulses that stay strictly inside shortened and extended bars;
- checked chart-wide pulse preflight before allocation, accepting exactly 49,152 and rejecting 49,153 with
  `rhythmMaterializationLimitExceeded`; and
- lock-guarded cursor consume/reseat/cancel generation so a stale lookup cannot advance a replacement.

### RED 2: timeline timing-engine overload

Timing tests first failed on missing schedule/speed/elapsed overloads in `MetronomeTimingEngine` and `MetronomeEngine`.
The GREEN path binary-seats a new cursor for every start/reseat, schedules immutable one-X pulse offsets against the
shared `CFAbsoluteTime` origin, captures audio/visual callbacks at timer construction, and gates callbacks with both
the playback token and cursor generation. The legacy `MetronomeBeatSchedule` path remains selected by its original
overload.

### RED 3: atomic gameplay runtime and fatal gating

Integration tests initially failed to compile on the wished-for cached runtime, timeline start spy, and fatal message.
Chart loading now resolves and atomically stores availability, timeline, rhythm layout snapshot, note targets,
metronome schedule, event-ID note lookup, note-position lookup, and diagnostics before setup consumes any of them.
Fatal setup clears render/audio state and every gameplay starter returns without starting scoring, metronome, or BGM.

### RED 4: continuous playhead and shortened-bar resume

The first runtime migration left the playhead and resume state in measure 0 after 1.51 seconds on a chart whose first
bar ended at 1.5 seconds. Valid runtime now converts elapsed seconds to a continuous absolute tick, resolves the
containing measure, derives local x through `TabGrid`, changes row from the resolved measure, scans misses in seconds,
and restores pause/resume state from the same position. Beat/pulse indexes wrap from the timeline schedule at the
shortened barline.

### RED 5: canonical 7/8 schedule quantum

A builder-produced valid 7/8 timeline with a 1/3-whole-note override initially threw `inexactProjection` while creating
the schedule. The builder quantum now includes the meter denominator required for pulse/notational projection before
materialization. Focused coverage proves standard, shortened 1/3, and extended 4/3 valid 7/8 bars all have integral
pulse ticks. The cumulative exact-Double boundary remains enforced at the largest quantum-aligned tick, and the
49,152 schedule cap remains independently enforced.

### RED 6: short-audio clock ownership

After a one-second audio file ended, resume incorrectly restored 3.5 seconds from media plus anchor instead of the
shared 2.0-second timeline clock; a live 1.0x to 0.5x speed change similarly reseated at 7.0 instead of 4.0 seconds.
Valid runtime now yields ownership to the shared clock after early media completion and clamps musical elapsed time
only to timeline duration. Legacy BGM behavior is unchanged.

### RED 7: availability-explicit compatibility fixtures

The first full suite exposed tests whose old intent was implicit: manual-only charts now correctly synthesize valid
timelines, so fixed-measure, `Song.duration`, `Song.bgmStartOffsetSeconds`, legacy callback, and beat-quantized assertions
were no longer testing legacy behavior. Corrections were evidence-based:

- explicit legacy tests now use DTX-origin events without a timing payload;
- valid manual-chart tests assert the timeline schedule overload and speed rather than mutable legacy BPM;
- valid playhead tests assert continuous exact tick movement rather than beat-boundary quantization;
- valid duration/speed tests assert authoritative timeline clamping; and
- legacy media-offset tests retain their original one-X offset expectations.

No assertion was weakened to accept both contracts.

## Implemented Semantics

- `RhythmMetronomeSchedule` is immutable, exact, bounded, and constructed only after checked preflight.
- `RhythmScheduleCursor` prevents cancellation/reseat races through a lock and generation-stamped candidates.
- Timeline metronome playback schedules pulse offsets from the same future start used by BGM and input timing.
- `GameplayRhythmRuntime` is the sole availability boundary for timeline, layout, target, schedule, lookup, and
  diagnostic caches.
- The layout snapshot is produced from the cached timeline and rhythm analysis, including rests, controls, tuplets,
  and engraving warnings.
- `RhythmTimeline.endSeconds` owns valid session duration, progress, completion, layout measure count, and speed
  scaling. `Song.duration` remains library/legacy data; `AVAudioPlayer.duration` only bounds media operations.
- BGM uses the chart-owned projected anchor, then earliest playable event, then zero. `Song.bgmStartOffsetSeconds` is
  consulted only in legacy mode.
- Valid elapsed state resolves continuous absolute/local ticks for playhead x, row, measure fraction, quarter position,
  pulse index, current target, miss scanning, completion, and resume.
- Long audio stops with timeline completion; short audio may end while the metronome/shared clock continues.
- Fatal runtime displays `rhythmFatalPracticeMessage` and cannot prepare or start gameplay.

## Fixed-Measure Reader Audit

Ran the exact Task 8 `rtk rg` audit over gameplay, input, and metronome readers.

- `InputTimingMatcher`: fixed `secondsPerMeasure` and `beatsPerMeasure` math exists only in `LegacyState` and
  `calculateLegacyNoteMatch`; timeline matching uses immutable seconds/tick targets.
- `InputManager`: the timing configuration switch explicitly separates `.legacy` and `.timeline`; two write-only
  `secondsPerBeat`/`secondsPerMeasure` compatibility caches were removed.
- `MetronomeTimingEngine` / `MetronomeEngine`: `beatInterval` and fixed beat wrapping remain on the legacy overload;
  timeline scheduling uses immutable pulse offsets and cursor seating.
- `GameplayViewModel+Computations`: valid duration, measure count, beat positions, and BGM anchor branch through the
  cached timeline; fixed formulas remain in legacy helpers/fallbacks.
- `GameplayViewModel+VisualUpdates` / `+Playback`: valid elapsed and resume state use continuous ticks; fixed measure
  fractions are confined to named legacy functions.
- `.duration` hits in valid audio logic are only the AVAudioPlayer end bound used to relinquish media-clock ownership.

## Verification

Final requested Task 8 matrix, parallel testing disabled:

```text
Result: Passed
Total tests: 117
Failed: 0
Skipped: 0
xcresult: DerivedData/Logs/Test/Test-Virgo-2026.07.21_14-36-50--0700.xcresult
```

Final full nonparallel VirgoTests suite with code coverage:

```text
Result: Passed
Total tests: 1804
Failed: 0
Skipped: 0
Device-expanded passed runs: 1844 (dynamic parameters)
xcresult: DerivedData/Logs/Test/Test-Virgo-2026.07.21_14-37-32--0700.xcresult
```

Post-review timing/runtime suites after the callback-capture and lint-only refactors:

```text
Result: Passed
Total tests: 30
Failed: 0
Skipped: 0
xcresult: DerivedData/Logs/Test/Test-Virgo-2026.07.21_14-43-36--0700.xcresult
```

Additional checks:

- macOS Debug build: `BUILD SUCCEEDED`.
- `rtk swiftlint lint --no-cache`: completed across 294 files with 169 warnings and 0 serious violations.
- `rtk git diff --check`: passed.
- Production scope audit found no Task 9 import, persistence, library, or backfill changes.
- Progress ledger unchanged as required.

## Files

Production:

- `Virgo/utilities/RhythmMetronomeSchedule.swift` (new)
- `Virgo/utilities/MetronomeTimingEngine.swift`
- `Virgo/utilities/MetronomeEngine.swift`
- `Virgo/utilities/RhythmTimelineBuilder.swift`
- `Virgo/utilities/InputManager.swift`
- `Virgo/viewmodels/GameplayViewModel.swift`
- `Virgo/viewmodels/GameplayViewModel+Computations.swift`
- `Virgo/viewmodels/GameplayViewModel+VisualUpdates.swift`
- `Virgo/viewmodels/GameplayViewModel+Playback.swift`
- `Virgo/viewmodels/GameplayViewModel+SpeedControl.swift`
- `Virgo/viewmodels/GameplayViewModel+BGM.swift`
- `Virgo/views/subviews/GameplaySheetMusicView.swift`

Tests:

- `VirgoTests/RhythmMetronomeScheduleTests.swift` (new)
- `VirgoTests/RhythmTimelineIntegrationTests.swift` (new)
- `VirgoTests/MetronomeTimingEngineTests.swift`
- `VirgoTests/MetronomeEngineTests.swift`
- `VirgoTests/GameplayViewModelComputationsTests.swift`
- `VirgoTests/GameplayViewModelVisualUpdatesTests.swift`
- `VirgoTests/GameplayViewModelPlaybackTimingTests.swift`
- `VirgoTests/GameplayViewModelPlaybackResumeTests.swift`
- `VirgoTests/GameplayViewModelBGMTimelineTests.swift`
- `VirgoTests/GameplayViewModelPlaybackBGMCoverageTests.swift`
- `VirgoTests/GameplayViewModelSpeedTests.swift`
- `VirgoTests/GameplayViewModelCoverageAdditionsTests.swift`
- `VirgoTests/GameplayViewModelCoveragePlaybackAdditionsTests.swift`
- `VirgoTests/PatchCoverageAdditionsTests.swift`
- `VirgoTests/RhythmTimelineBuilderTests.swift`
- `VirgoTests/GameplayViewModelTestHarness.swift`

## Self-review and Concerns

- Audited schedule arithmetic, cursor races, callback cancellation, variable-bar boundaries, timeline/BGM clock
  ownership, speed scaling, fatal gating, SwiftData retention, and explicit valid/legacy fixture classification.
- The schedule and gameplay runtime store immutable value snapshots; MainActor note lookups remain outside timer/input
  callbacks.
- SwiftLint reports no serious violations. Warning-level file/type/function size debt remains in the expanded timing
  engine and gameplay computation files, alongside existing repository warning-level debt.
- No Task 9 ownership was entered, and the progress ledger was not edited.

## Review Correction Wave: Runtime Identity and Cancellation

The first Task 8 review rejected two Important findings. Both were corrected through focused RED/GREEN cycles on
`e468772` without entering Task 9 ownership.

### RED: audible cancellation race

The timer handlers checked `token.isActive` and then invoked `audioBeatHandler` outside that lock. Cancellation could
therefore stop the audio driver between the check and callback, allowing the stale callback to enqueue a tick after
the stop. The new deterministic semaphore regression first failed to compile because the token exposed no atomic
operation (`cannot find 'MetronomePlaybackToken' in scope`).

`MetronomePlaybackToken.performIfActive` now holds the same lock used by `cancel()` across the complete audio callback.
Both legacy and timeline timer handlers use that operation. A cancellation following an in-flight callback waits for
the callback to leave the gate, after which `MetronomeEngine` still calls `audioDriver.stop()` during reseat. Existing
visual callbacks retain their `token.isActive` generation checks. The regressions use semaphore handshakes and no
sleep calls.

### RED: relationship-array control reconstruction

After the atomic gate was minimally green, the focused run failed only the two new control regressions:

- reordered immutable relationship snapshots attached the wrong payload to timeline positions;
- a one-element lingering/deleted-note count mismatch dropped or shifted control payloads.

The resolver previously discarded the control payload and gameplay reconstructed it with
`event.stableOrdinal - cachedNotes.count` into `cachedControlEvents`. Relationship order and the filtered resolver note
count are not a valid identity boundary. `ResolvedChartRhythm` now owns an immutable
`controlByEventID: [RhythmEventID: NotationControlEvent]` populated directly from each source envelope.
`GameplayRhythmRuntime` carries that lookup, and timeline layout joins controls only through `eventID`.

### Correction verification

Focused timing, engine, and runtime integration suites:

```text
Result: Passed
Failed: 0
Skipped: 0
xcresult: DerivedData/Logs/Test/Test-Virgo-2026.07.21_15-04-04--0700.xcresult
```

Exact Task 8 matrix, including the original 117 tests plus four correction regressions:

```text
Result: Passed
Total tests: 121
Failed: 0
Skipped: 0
xcresult: DerivedData/Logs/Test/Test-Virgo-2026.07.21_15-05-12--0700.xcresult
```

Full nonparallel VirgoTests suite with code coverage:

```text
Result: Passed
Total tests: 1808
Failed: 0
Skipped: 0
Device-expanded passed runs: 1848 (dynamic parameters)
xcresult: DerivedData/Logs/Test/Test-Virgo-2026.07.21_15-06-01--0700.xcresult
```

Additional correction checks:

- macOS Debug build: `BUILD SUCCEEDED`.
- `rtk swiftlint lint --no-cache`: completed across 294 files with 167 warnings and 0 serious violations.
- `rtk git diff --check`: passed.
- Production changes remain confined to Task 8 timing/runtime ownership; no Task 9 files or behavior were added.
- Progress ledger remains unchanged.
