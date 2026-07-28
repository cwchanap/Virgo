//
//  DrumTabPlayheadAlignmentTests.swift
//  VirgoTests
//

import Testing
import Foundation
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
        viewModel.setupGameplay(loadPersistedSpeed: false)

        // These tests bypass the harness's gate step, so re-assert validity.
        // Without this, a fixture degrading to resolveMissing would leave
        // cachedRhythmRuntime at its .legacy default and the column check
        // below would either pass vacuously or fail for the wrong reason.
        // `cachedRhythmRuntime` (GameplayViewModel.swift:88) is a stored,
        // non-optional `GameplayRhythmRuntime`, not the optional the brief
        // guessed at, so it is read directly rather than through #require.
        let runtime = viewModel.cachedRhythmRuntime
        #expect(runtime.availability == .valid)
        #expect(runtime.timeline != nil)
        #expect(!viewModel.cachedNotationLayout.noteHeads.isEmpty)

        // setupGameplay() alone leaves purpleBarPosition nil:
        // calculatePurpleBarPosition (GameplayViewModel+VisualUpdates.swift:196-197)
        // guards on `isPlaying`, which setupGameplay never sets. Mirror
        // RhythmTimelineIntegrationTests.validDTXFixtureSharesIdentityAndTime
        // (line 66), which flips isPlaying (line 128) and then drives a
        // synthetic elapsed time through updateContinuousVisualsForTesting
        // (line 152).
        //
        // Target selection matters: `TabGrid.xPosition` returns
        // `measure.contentStartX + tick * tickWidth`, and `contentStartX` is
        // `xOffset + barLineWidth + uniformSpacing` (NotationLayout.swift:343)
        // — it is `xOffset`, not the tick alone, that anchors a measure's
        // column origin, and `xOffset` differs between measures that share a
        // row. For these two fixtures specifically, every measure is 500pt
        // wide (52pt leftPadding + 16 ticks * 28pt tickWidth) against the
        // locked 900pt row width, so `buildMeasures`
        // (NotationLayoutEngine.swift:258-274) wraps every measure onto its
        // own row (100 + 500 + 12 measureSpacing = 612, then 612 + 500 =
        // 1112 > 900) and each one lands back at `xOffset == leftMargin ==
        // 100`, so `contentStartX == 152` for every measure in both charts.
        // That means x alone cannot distinguish measures here, so
        // "the middle event by index" was verified (via a throwaway
        // diagnostic run) to still land on the same x=152 column that tick 0
        // of measure 0 uses, for multiRowStableWidths, because its sparse
        // measures only ever place a note at local tick 0. Picking the event
        // with the largest local tick instead deterministically lands on a
        // late-in-measure column, so the check exercises real alignment
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

        // Because every measure in these fixtures shares the same
        // contentStartX (see above), x alone can't tell a correct playhead
        // apart from one that resolved to the wrong measure at the right
        // local tick — same column, wrong measure, and both assertions below
        // would still pass. Assert the measure independently first, matching
        // RhythmTimelineIntegrationTests.swift:153
        // (`viewModel.currentMeasureIndex == laterEvent.position.measureIndex`),
        // which sits immediately before that test's own x comparison.
        // `currentMeasureIndex` is written from `resolved.measure.measureIndex`
        // in `updateTimelineContinuousVisuals`
        // (GameplayViewModel+VisualUpdates.swift:82), derived from elapsed
        // seconds — independent of `farTarget.position.measureIndex`, which
        // comes from the resolver's event position.
        #expect(viewModel.currentMeasureIndex == farTarget.position.measureIndex)

        // The playhead must sit on a column that actually has a head. This is
        // strictly implied by the exact-match assertion below (`position.x ==
        // matchingHead.position.x`), which necessarily puts `position.x` in
        // `columnXs`. Retained anyway for the friendlier first failure message —
        // "matches no rendered note column" is more diagnosable than a `#require`
        // failure on `matchingHead` — not as independent coverage.
        let columnXs = Set(
            viewModel.cachedNotationLayout.noteHeads.map { ($0.position.x * 100).rounded() }
        )
        #expect(
            columnXs.contains((CGFloat(position.x) * 100).rounded()),
            "playhead x \(position.x) matches no rendered note column"
        )

        // Stronger check alongside the brief's set-membership assertion: not
        // merely "some column has a head," but the SPECIFIC head the driven
        // target corresponds to, matching the precedent in
        // RhythmTimelineIntegrationTests (`purpleBarPosition?.x ==
        // laterHead.position.x`, line 154).
        let matchingHead = try #require(
            viewModel.cachedNotationLayout.noteHeads.first { $0.eventID == farTarget.eventID }
        )
        #expect(position.x == Double(matchingHead.position.x))

        viewModel.cleanup()
    }
}
