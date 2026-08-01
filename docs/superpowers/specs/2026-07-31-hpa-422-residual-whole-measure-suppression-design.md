# HPA-422 Residual Whole-Measure Suppression Design

- **Date:** 2026-07-31
- **Status:** Design approved after committed-spec review
- **Scope:** Keep a visible rhythm warning for an unresolvable terminal DTX duration while preserving the engraving of resolved notes and voices in the same measure.
- **Linear:** [HPA-422](https://linear.app/cwchanap/issue/HPA-422/residual-whole-measure-suppression-for-non-clean-terminal-remainders)
- **Related:** [HPA-419](https://linear.app/cwchanap/issue/HPA-419/final-measure-of-every-chart-renders-without-stems-beams-flags-or-rests), [HPA-145](https://linear.app/cwchanap/issue/HPA-145/handle-tuplets-dotted-rhythms-compound-meter-and-dtx-measure-length)

## 1. Context

HPA-419 improved terminal DTX duration resolution. A terminal onset now receives an exact duration when the remaining measure span is a supported binary or single-dotted notation value. It deliberately leaves an onset indeterminate when no defensible duration exists.

The remaining defect is scope, not duration inference. `NotationRhythmAnalyzer.finalizeIndeterminateDurations` records `indeterminateTerminalDuration` in a measure-keyed warning collection. `applyConservativeFallback` and `measuresWithFallback` currently treat every warning as a whole-measure engraving failure. `RhythmLayoutSnapshotBuilder` independently repeats that projection when it creates the production snapshot. Consequently, one indeterminate onset strips stems, beams, flags, dots, tuplets, and rests from otherwise resolved material in its measure.

This affects both a non-clean terminal remainder in one voice and a multi-voice measure in which one voice resolves exactly while another cannot. The existing `sparse-hi-res-lane` golden demonstrates the former terminal-only warning path. `RhythmImportBackfillTests.crossVoiceOnsetDoesNotShortenTerminalUpperVoiceDuration` demonstrates the latter through the shared gameplay layout path.

## 2. Goals

- Preserve an unresolved terminal onset as `.indeterminate(.indeterminateTerminalDuration)` rather than inventing a duration.
- Continue to display a measure-level rhythm warning for that diagnostic.
- Permit resolved notes and voices in the same measure to retain normal stems, beams, flags, dots, tuplets, and printable rests.
- Preserve the current conservative whole-measure fallback for structural engraving failures.
- Keep the analyzer, gameplay snapshot builder, fixture harness, and notation renderer on one consistent support contract.
- Add direct analyzer-level coverage for both HPA-422 acceptance cases.

## 3. Non-Goals

- No new terminal-duration heuristic or duration backfill.
- No changes to normalized timing, persisted rhythm metadata, import format, or SwiftData schema.
- No relaxation of fallback behavior for `incompleteTuplet`, `ambiguousBeatGrouping`, or other existing structural diagnostics.
- No broad notation redesign or changes to the warning visual treatment.

## 4. Approved Product Decisions

1. A terminal duration that cannot be resolved remains unknown. The system must not substitute a guessed binary, dotted, or tuplet duration merely to remove a warning.
2. `indeterminateTerminalDuration` is a warning-only diagnostic when it is the only runtime engraving diagnostic for a measure.
3. A warning-only measure still receives the existing measure warning glyph.
4. A warning-only measure remains engravable. The unresolved note is excluded by its own non-supported rhythm state; resolved notes and voices continue through ordinary layout.
5. If a measure has any blocking diagnostic in addition to an indeterminate terminal duration, blocking fallback wins. The warning glyph retains the full stable code set.
6. Existing timeline-originated unsupported measures remain unsupported.

## 5. Support-State Model

Extend `RhythmEngravingSupport` with an additive warning state:

```swift
enum RhythmEngravingSupport: Hashable, Sendable {
    case supported
    case warning([RhythmDiagnosticCode])
    case unsupported([RhythmDiagnosticCode])
}
```

The model has two independent questions that should not be conflated:

- **May this measure engrave?** `.supported` and `.warning` may engrave; `.unsupported` may not.
- **Should a warning glyph be displayed?** `.warning` and `.unsupported` display one when they carry codes.

A shared, pure classification helper owns these decisions. It receives the original support state and the accumulated analyzer codes, unions codes deterministically, and returns one of the three states. It exposes a semantic predicate such as `permitsEngraving` so callers do not repeat `switch` logic.

`indeterminateTerminalDuration` is the sole warning-only runtime code in this change. Every other existing code that currently reaches whole-measure fallback remains blocking by default. This is intentionally narrow: future warning-only diagnostics must opt in explicitly rather than silently weakening established fallback behavior.

## 6. Analyzer and Snapshot Flow

### 6.1 `NotationRhythmAnalyzer`

`warningCodes` continues to aggregate diagnostics by measure for reporting. It no longer means that every affected measure must be suppressed.

`applyConservativeFallback` derives its target measures from blocking diagnostics only. For a terminal-only warning, it leaves all `EventResolution` values untouched:

- the unresolvable terminal event remains `.indeterminate(.indeterminateTerminalDuration)`;
- a previously resolved sibling remains `.supported` and retains any recognized tuplet association;
- a resolved event in another voice remains `.supported`;
- reserved tuplet rests are removed only for genuinely unsupported measures.

`measuresWithFallback` uses the shared support-state helper. A measure with only `indeterminateTerminalDuration` becomes `.warning`; a measure with a blocking code becomes `.unsupported`. The existing second rest-topology pass remains in place, but only newly blocking diagnostics trigger another conservative fallback.

### 6.2 `RhythmLayoutSnapshotBuilder`

`RhythmLayoutSnapshotBuilder.rhythmMeasuresApplyingWarnings` delegates to the same helper. It must not independently convert every analyzer warning into `.unsupported`.

This preserves the contract that `RhythmLayoutSnapshotBuilder` is shared by gameplay and `DrumTabFixtureHarness`: a fixture golden cannot pass while production restores whole-measure suppression, or vice versa.

## 7. Layout and Rendering

All measure-level consumers use the semantic support predicates rather than assuming a binary enum:

- `NotationRestTopologyBuilder` accepts `.warning` as engravable. Its existing per-note logic still converts an indeterminate note to uncertain spacing rather than a printed duration, while it may construct printed rests for resolved material.
- `NotationBeamTopologyBuilder` accepts `.warning` as engravable, allowing resolved notes to participate in normal beam topology.
- `NotationLayoutEngine` builds `unsupportedMeasureIndexes` from `.unsupported` only. It therefore retains current filtering for true fallback measures without excluding a warning-only measure's rests, flags, dots, and tuplets.
- `buildRhythmWarnings` renders the existing measure warning glyph for both `.warning` and `.unsupported` states.
- `NotationLayoutDigest` gains a stable `warning[...]` measure representation so golden diffs make the new semantic state visible.

The note-level `rhythm.support == .supported` gate remains unchanged. It naturally prevents an indeterminate terminal note from gaining a stem, flag, dot, or beam while allowing its resolved siblings to engrave.

## 8. Test Plan

### 8.1 Direct analyzer coverage

`NotationRhythmAnalyzerTests` will contain both HPA-422 acceptance cases directly:

1. **Non-clean terminal remainder:** revise the current baseline test so the terminal onset stays indeterminate and warned, while the cleanly resolved sibling remains `.supported` rather than being rewritten as unsupported.
2. **Unresolvable lower voice:** add a one-measure, multi-voice test where an upper voice resolves to a valid full-measure duration and the lower terminal DTX onset is indeterminate. Assert the upper voice remains supported and the warning code is retained.

These tests use the pure analyzer helper and do not rely on fixture goldens for the core contract.

### 8.2 Shared-pipeline and renderer coverage

- Update `RhythmImportBackfillTests.crossVoiceOnsetDoesNotShortenTerminalUpperVoiceDuration` to expect `.warning([.indeterminateTerminalDuration])`, a warning glyph, and at least one upper-voice stem. Its upper full notes should still have no flag or beam because that is valid full-note notation, not suppression.
- Add or extend `RhythmLayoutSnapshotBuilderTests` to assert that a terminal-only analyzer warning becomes the warning state rather than unsupported in the shared production builder.
- Update switch-based rendering and digest tests for the new state. Confirm a structural warning such as `incompleteTuplet` still yields `.unsupported` and remains conservatively suppressed.

### 8.3 Golden verification

Run the drum-tab golden suite with `TEST_RUNNER_VIRGO_UPDATE_GOLDENS=1`, review every diff, and manually retain only intentional output. The known terminal-only `sparse-hi-res-lane` golden is expected to change from `unsupported[indeterminateTerminalDuration]` to the warning state with restored engraving for its resolved note. Mixed structural fixtures such as `triplet-grid` must remain unsupported because `incompleteTuplet` is still blocking.

The golden update run intentionally fails after rewriting files. A subsequent normal golden run is the verification signal.

### 8.4 Commands

Use the macOS destination, disabled parallel testing, and a dedicated derived-data directory. Run sequentially:

```bash
xcodebuild test -project Virgo.xcodeproj -scheme Virgo \
  -destination 'platform=macOS' -only-testing:VirgoTests/NotationRhythmAnalyzerTests \
  -parallel-testing-enabled NO -derivedDataPath ./DerivedData-hpa422

xcodebuild test -project Virgo.xcodeproj -scheme Virgo \
  -destination 'platform=macOS' -only-testing:VirgoTests/RhythmImportBackfillTests \
  -parallel-testing-enabled NO -derivedDataPath ./DerivedData-hpa422

TEST_RUNNER_VIRGO_UPDATE_GOLDENS=1 xcodebuild test -project Virgo.xcodeproj -scheme Virgo \
  -destination 'platform=macOS' -only-testing:VirgoTests/DrumTabGoldenTests \
  -parallel-testing-enabled NO -derivedDataPath ./DerivedData-hpa422

xcodebuild test -project Virgo.xcodeproj -scheme Virgo \
  -destination 'platform=macOS' -only-testing:VirgoTests/DrumTabGoldenTests \
  -parallel-testing-enabled NO -derivedDataPath ./DerivedData-hpa422

xcodebuild test -project Virgo.xcodeproj -scheme Virgo \
  -destination 'platform=macOS' -only-testing:VirgoTests \
  -parallel-testing-enabled NO -derivedDataPath ./DerivedData-hpa422
```

The normal repository test configuration additionally supplies `ONLY_ACTIVE_ARCH=NO`, code-signing disables, code coverage, and destination timeout; use those settings for the final full-suite run.

## 9. Compatibility and Rollout

The enum is an in-memory layout value, not a persisted SwiftData or network payload. No migration is required.

Existing `.supported` and `.unsupported` semantics remain unchanged. Only an analyzer-produced terminal-duration warning with no blocking companion code gains the new non-suppressing state. Old imported charts retain their existing normalized rhythm inputs and are analyzed through the same corrected runtime path.

## 10. Completion Criteria

HPA-422 is complete when:

1. a non-clean terminal remainder leaves resolved notes in its measure engraved;
2. an unresolvable voice leaves resolved voices in its measure engraved;
3. the unresolved event stays indeterminate and a measure warning remains visible;
4. structural diagnostics still suppress the entire measure;
5. the direct analyzer tests, shared pipeline tests, reviewed goldens, and full macOS unit suite pass.
