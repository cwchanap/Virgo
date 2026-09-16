//
//  DrumTabPlayheadAlignmentTests.swift
//  VirgoTests
//

import Testing
import Foundation
import DrumNotation
@testable import Virgo

/// Verifies the gameplay playhead lands on a column a note head is actually
/// rendered at, for charts the golden/geometric fixture tests already cover.
///
/// `RhythmTimelineIntegrationTests.swift` is already close to SwiftLint's
/// 600-line file warning, so this lives in its own file rather than being
/// appended there.
@Suite("Drum tab playhead alignment", .serialized)
@MainActor
struct DrumTabPlayheadAlignmentTests {
    @Test("playhead x lands on a rendered note column", arguments: [
        DrumTabFixtureCatalog.sixteenthRun,
        DrumTabFixtureCatalog.multiRowStableWidths
    ])
    func playheadMatchesNoteColumn(_ fixture: DrumTabFixture) async throws {
        // The chart comes from the fixture harness — attached, persisted, and
        // built through persistenceProjection. Never createTestChart: that
        // leaves rhythmMetadataState == .missing, routes resolve() through
        // resolveMissing, and lands on the legacy layout path.
        let rendered = try DrumTabFixtureHarness.render(fixture)

        let viewModel = GameplayViewModel(
            chart: rendered.chart,
            metronome: GameplayViewModelTestHarness.createTestMetronome()
        )
        await viewModel.loadChartData()
        await viewModel.setupGameplay(loadPersistedSpeed: false)
        // Guard teardown immediately after setup so cleanup runs on both the
        // success path and any throwing `#require` below — the explicit call
        // that used to live at the end of the test was skipped whenever an
        // earlier `#require` threw.
        defer { viewModel.cleanup() }

        // These tests bypass the harness's gate step, so re-assert validity.
        // Without this, a fixture degrading to resolveMissing would leave
        // cachedRhythmRuntime at its .legacy default and the column check
        // below would either pass vacuously or fail for the wrong reason.
        // `cachedRhythmRuntime` on `GameplayViewModel` is a stored,
        // non-optional `GameplayRhythmRuntime`, not the optional the brief
        // guessed at, so it is read directly rather than through #require.
        let runtime = viewModel.cachedRhythmRuntime
        #expect(runtime.availability == .valid)
        #expect(runtime.timeline != nil)
        let engraved = try #require(viewModel.cachedEngravedNotation)
        #expect(!engraved.noteHeads.isEmpty)

        // setupGameplay() alone leaves purpleBarPosition nil:
        // `calculatePurpleBarPosition` on `GameplayViewModel+VisualUpdates`
        // guards on `isPlaying`, which setupGameplay never sets. Mirror
        // `RhythmTimelineIntegrationTests.validDTXFixtureSharesIdentityAndTime`,
        // which flips `isPlaying` and then drives a synthetic elapsed time
        // through `updateContinuousVisualsForTesting`.
        //
        // Target selection matters: on the measured route (HPA-164) the
        // playhead resolves X through the formatter's column lookup, so each
        // event tick has its own logical column X. Sparse measures in these
        // fixtures place notes only at local tick 0, so "the middle event by
        // index" can coincide with measure 0's tick-0 column; picking the
        // event with the largest local tick instead deterministically lands
        // on a late-in-measure column, so the check exercises real alignment
        // rather than only ever confirming "the playhead is at the start."
        let targets = viewModel.cachedRhythmNoteTargets
        try #require(!targets.isEmpty)
        let farTarget = try #require(targets.max { $0.position.localTick < $1.position.localTick })

        viewModel.isPlaying = true
        viewModel.updateContinuousVisualsForTesting(elapsedTime: farTarget.targetSecondsAtOneX)

        let position = try #require(
            viewModel.purpleBarPosition,
            "playhead must have a position once gameplay is set up"
        )

        // Because sparse measures in these fixtures only place notes at
        // local tick 0 (see above), x alone can't tell a correct playhead
        // apart from one that resolved to the wrong measure at the right
        // local tick — same column, wrong measure, and both assertions below
        // would still pass. Assert the measure independently first, matching
        // `RhythmTimelineIntegrationTests.validDTXFixtureSharesIdentityAndTime`
        // (`viewModel.currentMeasureIndex == laterEvent.position.measureIndex`),
        // which sits immediately before that test's own x comparison.
        // `currentMeasureIndex` is written from `resolved.measure.measureIndex`
        // in `updateTimelineContinuousVisuals` on
        // `GameplayViewModel+VisualUpdates`, derived from elapsed seconds —
        // independent of `farTarget.position.measureIndex`, which comes from
        // the resolver's event position.
        #expect(viewModel.currentMeasureIndex == farTarget.position.measureIndex)

        // The playhead must sit on a column that actually has a head. This is
        // strictly implied by the exact-match assertion below (`position.x ==
        // matchingHead.position.x`), which necessarily puts `position.x` in
        // `columnXs`. Retained anyway for the friendlier first failure message —
        // "matches no rendered note column" is more diagnosable than a `#require`
        // failure on `matchingHead` — not as independent coverage.
        let columnXs = Set(
            engraved.noteHeads.map { ($0.position.x * 100).rounded() }
        )
        #expect(
            columnXs.contains((CGFloat(position.x) * 100).rounded()),
            "playhead x \(position.x) matches no rendered note column"
        )

        // Stronger check alongside the brief's set-membership assertion: not
        // merely "some column has a head," but the SPECIFIC head the driven
        // target corresponds to, matching the precedent in
        // `RhythmTimelineIntegrationTests.validDTXFixtureSharesIdentityAndTime`
        // (`purpleBarPosition?.x == laterHead.position.x`).
        let matchingHead = try #require(
            engraved.noteHeads.first { $0.noteID == farTarget.eventID.rawValue }
        )
        #expect(position.x == Double(matchingHead.position.x))
    }

    /// The playhead must follow the *wrapped* package rows, not a
    /// single-row reconstruction: drive one note target on each of two
    /// distinct `EngravedRow`s and assert the live X is the formatter's own
    /// `FormattedNotation.position` lookup and the live Y is that row's
    /// `staffCenterY`.
    @Test("playhead tracks formatter X and row staffCenterY across wrapped rows")
    func playheadTracksFormatterXAndRowCenterYAcrossWrappedRows() async throws {
        // Eight measures of 16ths at the default row width wrap onto
        // multiple package rows — the fixture is built for stable wrapped
        // widths, so every row carries note targets.
        let rendered = try DrumTabFixtureHarness.render(DrumTabFixtureCatalog.multiRowStableWidths)

        let viewModel = GameplayViewModel(
            chart: rendered.chart,
            metronome: GameplayViewModelTestHarness.createTestMetronome()
        )
        await viewModel.loadChartData()
        await viewModel.setupGameplay(loadPersistedSpeed: false)
        defer { viewModel.cleanup() }

        #expect(viewModel.cachedRhythmRuntime.availability == .valid)
        let engraved = try #require(viewModel.cachedEngravedNotation)
        try #require(
            engraved.rows.count >= 2,
            "fixture must wrap onto at least two package rows for this probe"
        )

        let rowIndexByMeasure = Dictionary(
            uniqueKeysWithValues: engraved.measures.map { ($0.index, $0.rowIndex) }
        )
        let targets = viewModel.cachedRhythmNoteTargets
        // One representative target per row, covering at least two rows.
        var targetsByRow: [Int: RhythmNoteTarget] = [:]
        for target in targets.sorted(by: { $0.position.absoluteTick < $1.position.absoluteTick }) {
            guard let rowIndex = rowIndexByMeasure[target.position.measureIndex],
                  targetsByRow[rowIndex] == nil else { continue }
            targetsByRow[rowIndex] = target
        }
        try #require(
            targetsByRow.count >= 2,
            "fixture must place note targets on at least two wrapped rows"
        )

        viewModel.isPlaying = true
        for (rowIndex, target) in targetsByRow.sorted(by: { $0.key < $1.key }).prefix(2) {
            try expectPlayhead(
                viewModel: viewModel,
                target: target,
                rowIndex: rowIndex,
                engraved: engraved
            )
        }
    }

    /// Asserts the live playhead at `target` matches the formatter's own
    /// tick→X lookup (not a head-center or stale `measurePositionMap`
    /// reconstruction) and the wrapped `EngravedRow.staffCenterY` — so the
    /// bar rides the row the package painted.
    private func expectPlayhead(
        viewModel: GameplayViewModel,
        target: RhythmNoteTarget,
        rowIndex: Int,
        engraved: EngravedNotation
    ) throws {
        viewModel.updateContinuousVisualsForTesting(elapsedTime: target.targetSecondsAtOneX)
        let position = try #require(
            viewModel.purpleBarPosition,
            "playhead must resolve on row \(rowIndex)"
        )
        let measureIndex = target.position.measureIndex
        let measure = try #require(
            engraved.measures.first { $0.index == measureIndex }
        )
        let formatterPosition = try #require(
            engraved.formatted.position(
                measureIndex: measureIndex,
                localTick: min(Double(target.position.localTick), Double(measure.durationTicks))
            )
        )
        #expect(
            abs(position.x - Double(formatterPosition.x)) < 0.001,
            "row \(rowIndex): playhead x \(position.x) != formatter x \(formatterPosition.x)"
        )
        let row = try #require(engraved.rows.first { $0.index == rowIndex })
        #expect(
            abs(position.y - Double(row.staffCenterY)) < 0.001,
            "row \(rowIndex): playhead y \(position.y) != staffCenterY \(row.staffCenterY)"
        )
    }
}
