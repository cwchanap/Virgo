# Task 10 Report: Cross-System Fixtures, Legacy Proof, and Final Verification

## Status

Complete on `codex/hpa-145-rhythm-timeline` from starting commit
`41f50faa817e2ab7e66ca68a12f79d4c3a94b594`.

Required commit message: `test: verify rhythm timeline end to end`

## Delivered

- Added a real 6/8 DTX parse -> persistence projection -> SwiftData reopen -> resolver fixture with explicit straight
  feel, a `0.75` pickup, a later `1.5` measure, dotted material, a recognized triplet with a printed silent slot,
  a control event, a raw lane-01 BGM anchor, and exact 32nd/64th material.
- Proved selected note/control source identity and canonical timing survive persistence and resolve to the same event
  identity and position.
- Proved one selected note keeps the same `RhythmEventID`, `RhythmEventPosition`, layout x, and one-X seconds across
  semantic analysis, rendered notehead, input target/matcher, cached gameplay beat, scoring, metronome pulse, BGM
  anchor, playhead, miss scan, track duration, and session completion.
- Added a timing-valid 7/8 fixture proving exact notehead/target positions and seconds, seven isochronous eighth-note
  pulses with only a downbeat accent, and one warning for the selected measure with no duration-bearing engraving.
- Added corrupt persisted-byte and malformed explicit-feel fixtures proving fatal diagnostics, visible disabled
  library state, nil canonical timing, and zero gameplay layout/input/metronome/BGM startup.
- Proved all three metadata-free paths: DTX stays wholly on the fixed legacy path, exactly rationalizable manual
  offsets synthesize a complete timeline, and bounded-inadmissible manual offsets stay playable through legacy with
  only `manualTimelineUnavailable` at engraving severity.
- Added scoring integration coverage for event-ID duplicate suppression and session snapshot preservation.
- Added stable canonical identity/position directly to timeline-backed `DrumBeat` values. Legacy beats retain nil
  identity, and timeline beat-position caching no longer finds the first note sharing a floating-point fraction.
- Updated one pre-existing cache test: two distinct manual offsets (`0.0` and `0.0004`) now remain two exact canonical
  beats after manual timeline synthesis instead of merging through the old legacy normalization key.

## TDD Evidence

### RED: canonical gameplay beat identity

The persisted DTX fixture passed parser, projection, reopen, resolver, layout, target, and timing assertions, then
failed at the cached gameplay beat boundary because `DrumBeat` carried only a legacy `Double` fraction. The accepted
RED run reported one issue in 12 tests: no cached beat exposed the selected event ID/position.

The minimal production correction added optional event identity/position to `DrumBeat`, grouped timeline beats by
canonical `RhythmEventPosition`, selected a deterministic minimum event ID for chords, and cached timeline x directly
from that position. A duplicate-fraction/chord regression verifies the identity is stable without a first-match scan.

### Fixture corrections

- The first 7/8 assertion expected one warning across the whole two-measure fixture. Runtime correctly emitted one
  warning per unsupported 7/8 measure, so the assertion was tightened to exactly one warning for the selected measure.
- Consecutive DTX onsets authoritatively define the preceding duration. Therefore the real DTX fixture keeps its
  recognized note-note-rest triplet; moving the second onset to force a middle silence would falsely change the first
  note to a two-slot duration and removed recognition. A separate metadata-free manual integration fixture uses
  authoritative eighth-note durations and exact slots 0 and 2 to prove literal note-rest-note analysis and rendering.
- The full suite exposed one stale legacy-normalization expectation. The chart is metadata-free manual and therefore
  explicitly opts into synthesized exact timing; its two close but distinct offsets correctly produce two beats.

## Verification

- Focused Task 10 matrix: PASS, 64 tests, 0 failures, 0 skips.
  Result bundle: `DerivedData/Logs/Test/Test-Virgo-2026.07.21_17-13-14--0700.xcresult`.
- Full `VirgoTests`, nonparallel with coverage: PASS, 1,831 tests, 0 failures, 0 skips. The device-level summary reports
  1,871 expanded invocations because parameterized tests contribute multiple runs.
  Result bundle: `DerivedData/Logs/Test/Test-Virgo-2026.07.21_17-17-48--0700.xcresult`.
- SwiftLint: exit 0, 182 warnings, 0 serious violations across 296 files. The repository retains warning-level size,
  complexity, and line-length debt; no lint error blocks this task.
- macOS Debug build: PASS (`platform=macOS`).
- iPad simulator discovery: PASS. Selected `iPad Pro 11-inch (M5)` on iOS 26.5,
  UDID `F668E44A-D7CF-4437-983B-64B7EE7ACAB8`.
- iPad simulator build: PASS for that iPad-only destination; no iPhone destination was used.
- `git diff --check`: PASS.

## Forbidden-Fallback Scan

Command:

```bash
rtk rg -n "visualDurationCandidates.*\?\? \.quarter|4\.0 \* 60\.0 / bpm|rhythmMetadataData.*nil|try\? ChartRhythmMetadataCodec|secondsPerMeasure|beatsPerMeasure|tickIndex\(forBeatWithinMeasure" Virgo
```

Review result:

- No `visualDurationCandidates ?? .quarter`, fixed `4.0 * 60.0 / bpm`, or `try? ChartRhythmMetadataCodec` match.
- The two `rhythmMetadataData ... nil` matches are the model's missing-payload initialization and the versioned DTX
  backfill eligibility predicate; neither treats invalid timing as legacy.
- Gameplay fixed-measure hits are behind an explicit timeline guard or inside named legacy helpers for layout,
  input, BGM fallback, resume, playhead, and missed-note scanning.
- Remaining `beatsPerMeasure`/`tickIndex` hits are meter display/layout primitives, the standalone legacy metronome and
  input implementations, or the documented tab-grid compatibility adapter. No timeline consumer reconstructs timing
  through a fixed four-beat formula or floating-point beat fraction.

## Scope Notes

- Production changes were limited to the integration-exposed cached-beat identity contract.
- `.superpowers/sdd/progress.md` was not modified.

## Review Correction Wave

Applied on top of `869d89e9ecb7a9c2fb5cf45ebca23b9d99673583` in response to the Task 10
review. This wave changes tests and this report only; no production source changed.

### Strengthened Proof

- The exact 7/8 integration fixture now configures `InputTimingMatcher` from the runtime timeline targets, hits the
  first event at its exact target, and proves matched event identity, canonical position, target seconds, and hit
  seconds. Recording that result twice proves event-ID deduplication leaves one scored event, combo 1, and score 100.
- The composite real-DTX fixture now resolves T1 and T2 explicitly, requires both notes and the printed silent rest
  to share one `RhythmTupletID`, and proves their ordered local ticks are exactly the first, second, and third slots.
  The rendered tuplet is also required to contain exactly the T1 and T2 event IDs.
- The metadata-free DTX legacy fixture now requires the rendered notehead to exist and proves its x-coordinate is the
  fixed-grid quarter-note position for beat 1 in 4/4; it no longer permits an absent notehead through optional access.

### Characterization Evidence

All three strengthened contracts passed on their first owning-suite run: 34 tests, 0 failures, 0 skips. They therefore
characterize behavior already present at the review baseline rather than expose a production defect. No artificial
failing expectation was introduced. SwiftLint then exposed an error-level function-length violation caused by the
additional test assertions; extracting the triplet proof into a test helper removed it without changing production.

### Verification

- Owning suites after the assertions: PASS, 34 tests, 0 failures, 0 skips.
  Result bundle: `DerivedData/Logs/Test/Test-Virgo-2026.07.21_17-35-22--0700.xcresult`.
- Final focused Task 10 matrix after the lint-only helper extraction: PASS, 64 tests, 0 failures, 0 skips.
  Result bundle: `DerivedData/Logs/Test/Test-Virgo-2026.07.21_17-41-13--0700.xcresult`.
- One full `VirgoTests` nonparallel suite after the substantive assertion additions: PASS, 1,831 tests, 0 failures,
  0 skips; 1,871 device-level expanded invocations.
  Result bundle: `DerivedData/Logs/Test/Test-Virgo-2026.07.21_17-36-39--0700.xcresult`.
- SwiftLint after the final helper compaction: exit 0, 182 warning-level violations, 0 serious violations across
  296 files.
- `git diff --check`: PASS. The diff contains only the three requested test files and this report;
  `.superpowers/sdd/progress.md` remains untouched.
- macOS and iPad builds were not rerun because no production source or project configuration changed in this wave.
