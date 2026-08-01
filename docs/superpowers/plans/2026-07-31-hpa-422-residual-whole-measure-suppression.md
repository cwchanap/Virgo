# HPA-422 Residual Whole-Measure Suppression Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Preserve a visible warning for an unresolvable terminal DTX duration without suppressing resolved engraving in the same measure or another voice.

**Architecture:** Add a warning-capable measure support state that explicitly separates a displayed diagnostic from a measure-wide fallback. Route support projection through one pure helper used by the analyzer and snapshot builder; renderer and topology consumers permit warning-only measures while continuing to reject genuinely unsupported measures. The individual terminal event remains indeterminate, so no duration is invented.

**Tech Stack:** Swift 5.9+, SwiftUI, SwiftData, Swift Testing (`import Testing`), Xcode/`xcodebuild`, SwiftLint, committed drum-tab golden fixtures.

## Global Constraints

- Work only in `/Users/chanwaichan/workspace/Virgo/.worktrees/hpa-422-residual-whole-measure-suppression` on branch `codex/hpa-422-residual-whole-measure-suppression`.
- Preserve HPA-419's exact clean-remainder behavior. Do not add a terminal-duration heuristic or synthesize a binary, dotted, or tuplet duration for an unresolvable onset.
- `indeterminateTerminalDuration` is the only new warning-only runtime diagnostic. Every existing structural engraving diagnostic remains measure-blocking unless an explicit later ticket changes that contract.
- A pre-existing timeline `.unsupported` state remains unsupported even when its codes are otherwise warning-only.
- Keep `RhythmLayoutSnapshotBuilder` as the single shared path for gameplay and `DrumTabFixtureHarness`; do not duplicate snapshot support projection in tests.
- Use Swift Testing, not XCTest. Run all `xcodebuild test` invocations sequentially with `-parallel-testing-enabled NO` and the macOS destination.
- Prefix every shell command with `rtk`. Do not run concurrent Xcode commands against the same derived-data directory.
- The app remains iPad-only for iOS-family builds; this work uses macOS tests and must not alter iPhone targeting or `TARGETED_DEVICE_FAMILY = 2`.
- The golden-update command intentionally fails after rewriting files. Inspect its diff, then run the normal golden suite as the pass signal.

---

## File Structure

### Production files

- `Virgo/models/RhythmMetadata.swift` — owns the additive `.warning` support state, stable code union, exhaustive blocking classification, and `permitsEngraving` predicate.
- `Virgo/layout/NotationRhythmAnalyzer.swift` — narrows conservative fallback to measures whose projected support is truly unsupported, including after rest-topology diagnostics.
- `Virgo/layout/RhythmLayoutSnapshotBuilder.swift` — applies the same shared support projection on the production/fixture snapshot boundary.
- `Virgo/layout/NotationBeamTopology.swift` — lets warning-only measures produce beam topology.
- `Virgo/layout/NotationRestTopology.swift` — lets warning-only measures solve printable resolved gaps while keeping complements adjacent to indeterminate spans as hidden spacing.
- `Virgo/layout/NotationLayoutEngine+RhythmRendering.swift` — draws measure warnings for both warning-only and unsupported support states.

### Test and golden files

- `VirgoTests/RhythmMetadataTests.swift` — verifies code classification, stable state projection, and preservation of pre-existing unsupported state.
- `VirgoTests/NotationRestTopologyTests.swift` — proves a warning-only measure yields exact printed resolved rests while terminal-adjacent gaps remain hidden and non-escalating.
- `VirgoTests/NotationBeamTopologyMeterTests.swift` — proves a warning-only measure still groups beamable notes.
- `VirgoTests/RhythmRenderingTests.swift` — proves warning-only layout retains engraving and renders the warning glyph; true unsupported layout remains suppressed.
- `VirgoTests/NotationRhythmAnalyzerTests.swift` — direct HPA-422 tests for non-clean remainders and cross-voice terminal uncertainty.
- `VirgoTests/RhythmLayoutSnapshotBuilderTests.swift` — proves the shared builder projects a terminal-only runtime warning to `.warning`, not `.unsupported`.
- `VirgoTests/RhythmImportBackfillTests.swift` — verifies the real importer → resolver → snapshot → layout path preserves upper full-note support and the warning without imposing an invalid stem expectation.
- `VirgoTests/NotationLayoutDigest.swift` — serializes the additive support state as `warning[...]` for deterministic golden review.
- `VirgoTests/DrumTabGoldenTests.swift` — handles the new state exhaustively and rejects it for the still-structural triplet fixture.
- `VirgoTests/Goldens/sparse-hi-res-lane.txt` — regenerated expected output for the known terminal-only warning fixture.

## Task 1: Add Warning-Capable Support Semantics and Renderer Boundaries

**Files:**

- Modify: `Virgo/models/RhythmMetadata.swift:298-332, 394-397`
- Modify: `Virgo/layout/NotationBeamTopology.swift:156-165`
- Modify: `Virgo/layout/NotationRestTopology.swift:541-691`
- Modify: `Virgo/layout/NotationLayoutEngine+RhythmRendering.swift:185-211`
- Modify: `VirgoTests/RhythmMetadataTests.swift`
- Modify: `VirgoTests/NotationRestTopologyTests.swift`
- Modify: `VirgoTests/NotationBeamTopologyMeterTests.swift`
- Modify: `VirgoTests/RhythmRenderingTests.swift`
- Modify: `VirgoTests/NotationLayoutDigest.swift:40-46`
- Modify: `VirgoTests/DrumTabGoldenTests.swift:326-383`

**Interfaces:**

- Produces: `RhythmEngravingSupport.warning([RhythmDiagnosticCode])`.
- Produces: an exhaustive `RhythmDiagnosticCode.blocksWholeMeasureEngraving: Bool` switch with no `default` (`false` only for `.indeterminateTerminalDuration`).
- Produces: `RhythmEngravingSupport.permitsEngraving: Bool` and `applyingRuntimeWarnings(_:) -> RhythmEngravingSupport`.
- Consumes: existing stable raw-value ordering for diagnostic codes; no persisted representation changes.

- [ ] **Step 1: Write the failing warning-state tests**

Add a `RhythmMetadataTests` case that makes the intended state projection explicit:

```swift
@Test("terminal-duration warnings permit engraving while structural warnings block it")
func warningSupportProjection() {
    let warning = RhythmEngravingSupport.supported.applyingRuntimeWarnings([
        .indeterminateTerminalDuration
    ])
    #expect(warning == .warning([.indeterminateTerminalDuration]))
    #expect(warning.permitsEngraving)

    let blocking = warning.applyingRuntimeWarnings([.incompleteTuplet])
    #expect(blocking == .unsupported([.incompleteTuplet, .indeterminateTerminalDuration]))
    #expect(!blocking.permitsEngraving)

    let original = RhythmEngravingSupport.unsupported([.ambiguousBeatGrouping])
    #expect(original.applyingRuntimeWarnings([.indeterminateTerminalDuration]) == .unsupported([
        .ambiguousBeatGrouping, .indeterminateTerminalDuration
    ]))
}
```

Extend `NotationRestTopologyTests` so `resolvedMeasure` accepts an optional support argument and add a `.warning([.indeterminateTerminalDuration])` measure with an exact 120-tick gap. Assert that `buildExact` returns a printed upper-voice eighth rest and no `.ambiguousBeatGrouping` warning.

Add a terminal-boundary rest case with a resolved half span `0...32` and an indeterminate terminal span beginning at `33` in a 64-tick warning measure. Assert the complement at `32...33` is hidden spacing, never a printed sixty-fourth rest, and adds no `.ambiguousBeatGrouping`; this is the explicit non-escalation contract for terminal uncertainty.

Extend `NotationBeamTopologyMeterTests` with two contiguous eighth-note events in a `.warning([.indeterminateTerminalDuration])` 4/4 measure. Assert the topology has one primary group containing both event indices.

Add a `RhythmRenderingTests` layout test using a warning-only measure, two beamable supported notes, and a printable lower rest. Assert the layout has a beam, stems, the supplied rest, and exactly one `RenderedRhythmWarning.measure(0)` whose codes are `[.indeterminateTerminalDuration]`.

- [ ] **Step 2: Run the focused tests and confirm they fail**

Run:

```bash
rtk xcodebuild test -project Virgo.xcodeproj -scheme Virgo \
  -destination 'platform=macOS' -configuration Debug \
  -only-testing:VirgoTests/RhythmMetadataTests \
  -only-testing:VirgoTests/NotationRestTopologyTests \
  -only-testing:VirgoTests/NotationBeamTopologyMeterTests \
  -only-testing:VirgoTests/RhythmRenderingTests \
  -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath ./DerivedData-hpa422
```

Expected: compile failure because `.warning`, `permitsEngraving`, and `applyingRuntimeWarnings(_:)` do not exist.

- [ ] **Step 3: Implement the support model and stable projection helper**

In `RhythmMetadata.swift`, extend the enum and add pure helpers. Keep the array returned by every state projection sorted by `rawValue` so equality, warning IDs, and digest output remain deterministic.

```swift
enum RhythmEngravingSupport: Hashable, Sendable {
    case supported
    case warning([RhythmDiagnosticCode])
    case unsupported([RhythmDiagnosticCode])
}

extension RhythmDiagnosticCode {
    var blocksWholeMeasureEngraving: Bool {
        switch self {
        case .indeterminateTerminalDuration:
            return false
        case .malformedTimeSignature,
                .unsupportedTimeSignature,
                .malformedFeel,
                .unsupportedFeel,
                .malformedMeasureLength,
                .nonpositiveMeasureLength,
                .conflictingTimeSignature,
                .conflictingFeel,
                .conflictingMeasureLength,
                .unsupportedMetadataVersion,
                .arithmeticOverflow,
                .resolutionLimitExceeded,
                .measureLimitExceeded,
                .rhythmMaterializationLimitExceeded,
                .inexactGridProjection,
                .inconsistentPersistedTiming,
                .unsupportedTupletRatio,
                .unsupportedDotCount,
                .incompleteTuplet,
                .ambiguousBeatGrouping,
                .manualTimelineUnavailable:
            return true
        }
    }
}

extension RhythmEngravingSupport {
    var permitsEngraving: Bool {
        switch self {
        case .supported, .warning: true
        case .unsupported: false
        }
    }

    func applyingRuntimeWarnings(_ runtimeCodes: Set<RhythmDiagnosticCode>) -> Self {
        let existingCodes: Set<RhythmDiagnosticCode>
        let wasUnsupported: Bool
        switch self {
        case .supported:
            existingCodes = []
            wasUnsupported = false
        case let .warning(codes):
            existingCodes = Set(codes)
            wasUnsupported = false
        case let .unsupported(codes):
            existingCodes = Set(codes)
            wasUnsupported = true
        }

        let allCodes = existingCodes.union(runtimeCodes)
        let stableCodes = allCodes.sorted { $0.rawValue < $1.rawValue }
        if wasUnsupported { return .unsupported(stableCodes) }
        guard !stableCodes.isEmpty else { return .supported }
        return allCodes.contains { $0.blocksWholeMeasureEngraving }
            ? .unsupported(stableCodes)
            : .warning(stableCodes)
    }
}
```

Do not classify a code by `requiredSeverity`: other `.engravingOnly` diagnostics remain blocking under HPA-422. Do not add a `default` branch to `blocksWholeMeasureEngraving`; a new diagnostic must force an explicit policy choice at compile time.

- [ ] **Step 4: Make topology and warning rendering consume `permitsEngraving`**

Replace the exact `.supported` guard in `NotationBeamTopology.groupEventsByResolvedGroup` with `measure.engravingSupport.permitsEngraving`.

In `NotationRestTopology`, let ordinary gaps in a permitting measure use `permitsEngraving` and the existing exact solver. Thread terminal-span adjacency from `appendExactVoice` into the gap handling: a gap that directly touches an indeterminate span becomes an `.indeterminate(.indeterminateTerminalDuration)` `.hiddenSpacing` event without calling `solveRestPath` or adding `.ambiguousBeatGrouping`. A non-adjacent gap that the solver cannot represent still emits the structural diagnostic and follows normal fallback policy.

Update `buildRhythmWarnings` to extract codes from `.warning` and `.unsupported`, while returning no warning for `.supported`:

```swift
let codes: [RhythmDiagnosticCode]
switch measure.engravingSupport {
case .supported:
    return nil
case let .warning(value), let .unsupported(value):
    codes = value
}
```

Add the `.warning` case to `NotationLayoutDigest` as `warning[codeA,codeB]`. Add a `.warning` branch to the `tripletGrid` switch in `DrumTabGoldenTests` that records an issue because that fixture must remain structural fallback, then leaves its existing unsupported assertions untouched.

- [ ] **Step 5: Run the focused tests and inspect the diff**

Run the Step 2 command again. Expected: all selected suites pass; the existing true-unsupported rendering assertions still pass unchanged.

Then run:

```bash
rtk git diff --check
rtk git diff -- Virgo/models/RhythmMetadata.swift Virgo/layout/NotationBeamTopology.swift Virgo/layout/NotationRestTopology.swift Virgo/layout/NotationLayoutEngine+RhythmRendering.swift VirgoTests
```

Expected: only the additive support state and its direct rendering/topology coverage change.

- [ ] **Step 6: Commit the warning-state boundary**

```bash
rtk git add Virgo/models/RhythmMetadata.swift Virgo/layout/NotationBeamTopology.swift \
  Virgo/layout/NotationRestTopology.swift Virgo/layout/NotationLayoutEngine+RhythmRendering.swift \
  VirgoTests/RhythmMetadataTests.swift VirgoTests/NotationRestTopologyTests.swift \
  VirgoTests/NotationBeamTopologyMeterTests.swift VirgoTests/RhythmRenderingTests.swift \
  VirgoTests/NotationLayoutDigest.swift VirgoTests/DrumTabGoldenTests.swift
rtk git commit -m "feat: separate rhythm warnings from fallback support"
```

## Task 2: Localize Analyzer Fallback and Preserve the Shared Snapshot Contract

**Files:**

- Modify: `Virgo/layout/NotationRhythmAnalyzer.swift:97-162, 650-710`
- Modify: `Virgo/layout/RhythmLayoutSnapshotBuilder.swift:119-145`
- Modify: `VirgoTests/NotationRhythmAnalyzerTests.swift:288-313`
- Modify: `VirgoTests/RhythmLayoutSnapshotBuilderTests.swift`
- Modify: `VirgoTests/RhythmImportBackfillTests.swift:130-225`

**Interfaces:**

- Consumes: `RhythmEngravingSupport.applyingRuntimeWarnings(_:)` and `permitsEngraving` from Task 1.
- Produces: `applyConservativeFallback` targeted only through a pre-filtered `fallbackDiagnosticCodesByMeasure` map for projected `.unsupported` measures.
- Produces: warning-only snapshots for a measure whose only runtime code is `.indeterminateTerminalDuration`.
- Preserves: the terminal note's `.indeterminate(.indeterminateTerminalDuration)` rhythm and all existing whole-measure behavior for blocking diagnostics.

- [ ] **Step 1: Replace the old suppression expectation with the two direct HPA-422 tests**

Rename `terminalDTXUncleanRemainderSuppressesMeasure` to describe the desired behavior. Retain its two DTX events, but assert that the clean first event remains supported:

```swift
#expect(terminal.rhythm.support == .indeterminate(.indeterminateTerminalDuration))
#expect(resolved.rhythm.support == .supported)
#expect(analysis.warnings.contains {
    $0.codes == [.indeterminateTerminalDuration]
})
```

Add a direct multi-voice analyzer test without an importer fixture:

```swift
let analysis = analyze([
    event(1, tick: 0, voice: .upper, origin: .dtx, interval: .sixtyfourth),
    event(2, tick: 300, voice: .lower, origin: .dtx, interval: .sixtyfourth)
])
let upper = try #require(analysis.notes.first { $0.eventID.rawValue == 1 })
let lower = try #require(analysis.notes.first { $0.eventID.rawValue == 2 })

#expect(upper.durationTicks == 960)
#expect(upper.rhythm == NotationRhythm(baseInterval: .full))
#expect(lower.rhythm.support == .indeterminate(.indeterminateTerminalDuration))
```

Also assert the retained warning code and that no upper note is rewritten to `.unsupported`.

Extend `RhythmLayoutSnapshotBuilderTests` with a direct DTX → projection → resolver → `RhythmLayoutSnapshotBuilder.build` case using the existing voice-scoped pattern:

```dtx
#00012: 0100000000000000
#00011: 0200000000000000
#00013: 0003000000000000
```

Assert measure `0` is `.warning([.indeterminateTerminalDuration])`, its two upper notes are supported full notes, and its lower note remains indeterminate.

Update `RhythmImportBackfillTests.crossVoiceOnsetDoesNotShortenTerminalUpperVoiceDuration` to assert the same warning support state, one measure warning glyph, two upper noteheads with supported rhythm, and no upper full note rewritten to unsupported. Retain its assertions that upper full notes have no stem, flag, or beam: full notes are intentionally stemless, so those absences do not diagnose suppression.

- [ ] **Step 2: Run the focused tests and confirm they fail under whole-measure fallback**

Run:

```bash
rtk xcodebuild test -project Virgo.xcodeproj -scheme Virgo \
  -destination 'platform=macOS' -configuration Debug \
  -only-testing:VirgoTests/NotationRhythmAnalyzerTests \
  -only-testing:VirgoTests/RhythmLayoutSnapshotBuilderTests \
  -only-testing:VirgoTests/RhythmImportBackfillTests \
  -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath ./DerivedData-hpa422
```

Expected: the direct analyzer assertions fail because `applyConservativeFallback` rewrites resolved siblings; the builder and importer assertions fail because warning codes become `.unsupported`.

- [ ] **Step 3: Project support before fallback and only fall back for non-permitting measures**

Refactor `NotationRhythmAnalyzer` so it obtains effective measures with the Task 1 helper before each fallback decision. Rename the all-diagnostic aggregation from `warningCodes` to `diagnosticCodes`, making it clear that it can contain blocking codes as well as codes which project to `.warning`. Compute fallback targets from `!measure.engravingSupport.permitsEngraving`, not from every diagnostic key.

```swift
func measuresWithFallback(
    _ measures: [RhythmMeasure],
    diagnosticCodes: [Int: Set<RhythmDiagnosticCode>]
) -> [RhythmMeasure] {
    measures.map { measure in
        let codes = diagnosticCodes[measure.measureIndex, default: []]
        let support = measure.engravingSupport.applyingRuntimeWarnings(codes)
        return RhythmMeasure(
            measureIndex: measure.measureIndex,
            startTick: measure.startTick,
            durationTicks: measure.durationTicks,
            timeSignature: measure.timeSignature,
            beatGroups: measure.beatGroups,
            engravingSupport: support
        )
    }
}
```

Derive `fallbackDiagnosticCodesByMeasure` by filtering `diagnosticCodes` to the projected non-permitting measures. Change `applyConservativeFallback` to accept that map, use its keys as its only targets, and obtain `primaryCode(in:)` from the selected measure's mapped codes. It may rewrite resolutions, remove tuplets, and remove reserved rests only for those indexes. Leave `.indeterminate` resolutions intact. Rename `metadataWarningCodes` to `metadataDiagnosticCodes` and seed the reporting set from either `.warning` or `.unsupported` input support; the current timeline only originates the latter, but this keeps the three-state boundary complete.

After the first `analyzedRests` call appends diagnostics, recompute the projected measures. Re-run fallback only if a measure newly changes from `permitsEngraving == true` to `false`; warning-only additions do not trigger a second fallback. Only in that case, run `analyzedRests` once more. This deliberate at-most-two-pass bound is safe because rest synthesis is deterministic and measure-scoped: unchanged permitting measures receive the same inputs, and measures whose inputs changed are already non-permitting. The final diagnostic output unions both passes and contains every code used for fallback; no third fallback is required. Keep tuplet recognition guarded by `measure.engravingSupport.permitsEngraving` rather than the old binary case.

- [ ] **Step 4: Make the snapshot builder use the same support projection**

Replace the builder's local conversion-to-unsupported logic with the shared helper:

```swift
let support = measure.engravingSupport.applyingRuntimeWarnings(codes)
return RhythmMeasure(
    measureIndex: measure.measureIndex,
    startTick: measure.startTick,
    durationTicks: measure.durationTicks,
    timeSignature: measure.timeSignature,
    beatGroups: measure.beatGroups,
    engravingSupport: support
)
```

Do not reimplement blocking classification in `RhythmLayoutSnapshotBuilder`; the helper is the contract shared with `NotationRhythmAnalyzer` and the fixture harness.

- [ ] **Step 5: Run focused tests to green and preserve structural fallback coverage**

Run the Step 2 command again. Expected: all selected suites pass.

Also run the existing structural control:

```bash
rtk xcodebuild test -project Virgo.xcodeproj -scheme Virgo \
  -destination 'platform=macOS' -configuration Debug \
  -only-testing:VirgoTests/DTXControlImportIntegrationTests \
  -only-testing:VirgoTests/DrumTabGoldenTests \
  -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath ./DerivedData-hpa422
```

Expected: the 7/8 structural diagnostic remains `.unsupported([.ambiguousBeatGrouping])`; the pre-update golden comparison may fail only for the known warning-only fixture and is handled in Task 3.

- [ ] **Step 6: Inspect and commit the localized fallback**

```bash
rtk git diff --check
rtk git diff -- Virgo/layout/NotationRhythmAnalyzer.swift Virgo/layout/RhythmLayoutSnapshotBuilder.swift VirgoTests/NotationRhythmAnalyzerTests.swift VirgoTests/RhythmLayoutSnapshotBuilderTests.swift VirgoTests/RhythmImportBackfillTests.swift
rtk git add Virgo/layout/NotationRhythmAnalyzer.swift Virgo/layout/RhythmLayoutSnapshotBuilder.swift \
  VirgoTests/NotationRhythmAnalyzerTests.swift VirgoTests/RhythmLayoutSnapshotBuilderTests.swift \
  VirgoTests/RhythmImportBackfillTests.swift
rtk git commit -m "fix: localize terminal rhythm fallback"
```

Expected: no unrelated rhythm or importer files are staged.

## Task 3: Re-Record the Warning-Only Golden and Verify the Full Regression Boundary

**Files:**

- Modify: `VirgoTests/Goldens/sparse-hi-res-lane.txt` (generated by the golden update run)
- Review only: all other `VirgoTests/Goldens/*.txt` files
- Verify: `VirgoTests/DrumTabRegressionInvariantTests.swift` (its fixture matrix includes `sparse-hi-res-lane`)
- Modify if required by the actual reviewed output: existing golden assertion comments in `VirgoTests/DrumTabGoldenTests.swift`

**Interfaces:**

- Consumes: warning-state digest output from Task 1 and localized analyzer/snapshot behavior from Task 2.
- Produces: a reviewed golden showing `warning[indeterminateTerminalDuration]`, a visible warning, restored engraving for resolved material, and hidden terminal-adjacent spacing in `sparse-hi-res-lane`.
- Preserves: `triplet-grid` and other structural fallback goldens as `.unsupported` unless a separately demonstrated pre-existing inconsistency requires a deliberate change.

- [ ] **Step 1: Confirm the expected golden scope before rewriting**

Run:

```bash
rtk rg -n 'engraving=unsupported\\[indeterminateTerminalDuration\\]' VirgoTests/Goldens
rtk rg -n 'engraving=unsupported\\[.*incompleteTuplet' VirgoTests/Goldens
```

Expected before regeneration: `sparse-hi-res-lane.txt` is the terminal-only fixture; `triplet-grid.txt` remains a mixed structural control.

- [ ] **Step 2: Regenerate the golden suite and accept its intentional failure**

Run exactly once:

```bash
rtk env TEST_RUNNER_VIRGO_UPDATE_GOLDENS=1 xcodebuild test -project Virgo.xcodeproj -scheme Virgo \
  -destination 'platform=macOS' -configuration Debug \
  -only-testing:VirgoTests/DrumTabGoldenTests \
  -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -enableCodeCoverage YES -destination-timeout 300 \
  -derivedDataPath ./DerivedData-hpa422
```

Expected: the test command exits nonzero after writing revised golden files. That failure is the update guard, not a product regression.

- [ ] **Step 3: Inspect every generated diff and retain only intentional output**

Run:

```bash
rtk git diff -- VirgoTests/Goldens
rtk git diff --check
```

Verify `sparse-hi-res-lane.txt` changes its measure state to `warning[indeterminateTerminalDuration]`, retains a measure warning line, restores the resolved half note's supported rhythm, adds the expected `m0` lower full-measure rest, and keeps the unresolved terminal note indeterminate. Its `m0 t32...33` complement must be hidden spacing rather than a printed sixty-fourth rest; the resolved half remains intentionally stemless and flagless. Verify `triplet-grid.txt` still names `incompleteTuplet` and remains unsupported. Revert no user changes; only amend generated golden output if the implementation created a nondeterministic or semantically incorrect line.

- [ ] **Step 4: Run normal golden, focused, and full-suite verification**

Run sequentially:

```bash
rtk xcodebuild test -project Virgo.xcodeproj -scheme Virgo \
  -destination 'platform=macOS' -configuration Debug \
  -only-testing:VirgoTests/DrumTabGoldenTests \
  -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -enableCodeCoverage YES -destination-timeout 300 \
  -derivedDataPath ./DerivedData-hpa422

rtk xcodebuild test -project Virgo.xcodeproj -scheme Virgo \
  -destination 'platform=macOS' -configuration Debug \
  -only-testing:VirgoTests/DrumTabRegressionInvariantTests \
  -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -enableCodeCoverage YES -destination-timeout 300 \
  -derivedDataPath ./DerivedData-hpa422

rtk xcodebuild test -project Virgo.xcodeproj -scheme Virgo \
  -destination 'platform=macOS' -configuration Debug \
  -only-testing:VirgoTests/NotationRhythmAnalyzerTests \
  -only-testing:VirgoTests/RhythmLayoutSnapshotBuilderTests \
  -only-testing:VirgoTests/RhythmImportBackfillTests \
  -only-testing:VirgoTests/RhythmRenderingTests \
  -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -enableCodeCoverage YES -destination-timeout 300 \
  -derivedDataPath ./DerivedData-hpa422

rtk xcodebuild test -project Virgo.xcodeproj -scheme Virgo \
  -destination 'platform=macOS' -configuration Debug \
  -only-testing:VirgoTests \
  -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -enableCodeCoverage YES -destination-timeout 300 \
  -derivedDataPath ./DerivedData-hpa422

rtk git diff --check
rtk git status --short
```

Expected: every normal test command exits zero; the worktree contains only reviewed HPA-422 changes before the final commit.

`DrumTabRegressionInvariantTests` parameterizes across `DrumTabFixtureCatalog.all`, which includes `sparse-hi-res-lane`, so it is a focused regression boundary for this change. `DrumTabRenderProbeTests` and `DrumTabPlayheadAlignmentTests` do not currently use this fixture; the final full `VirgoTests` run retains their coverage without claiming a fixture-specific expected diff.

- [ ] **Step 5: Commit the approved golden regression coverage**

```bash
rtk git add VirgoTests/Goldens/sparse-hi-res-lane.txt VirgoTests/DrumTabGoldenTests.swift
rtk git commit -m "test: cover warning-only terminal rhythm fallback"
```

If the reviewed update changes another golden, add only that explicit filename after confirming why it changed. Do not stage `DerivedData-hpa422` or any generated build product.

## Plan Self-Review

- **Spec coverage:** Task 1 implements visible, non-suppressing warning state plus non-escalating terminal-boundary spacing; Task 2 covers both direct analyzer acceptance cases and the shared production path; Task 3 proves the changed real fixture output and that structural fallback remains intact.
- **No invented duration:** Task 2 retains the terminal event's existing indeterminate support and changes fallback scope only.
- **Type consistency:** Every consumer uses `RhythmEngravingSupport.permitsEngraving` and `applyingRuntimeWarnings(_:)`; no second blocking-code classifier is introduced outside `RhythmMetadata.swift`.
- **Compatibility:** The plan leaves persisted models, import payloads, timing resolution, iPad targeting, and existing `.unsupported` behavior unchanged.
