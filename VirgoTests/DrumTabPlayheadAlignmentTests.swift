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
        // RhythmTimelineIntegrationTests' pattern (realDTXProjectionPersists...
        // test, line ~152) of flipping isPlaying and driving a synthetic
        // elapsed time through updateContinuousVisualsForTesting.
        //
        // Target selection matters: xPosition is computed from the tick
        // *local to its measure*, so tick 0 of any measure lands on the same
        // x as tick 0 of measure 0 — driving to "the middle event by index"
        // was verified (via a throwaway diagnostic run) to still land on
        // that trivial start-of-measure column for multiRowStableWidths,
        // because its sparse measures only ever have a note at local tick 0.
        // Picking the event with the largest local tick instead deterministically
        // lands on a late-in-measure column, so the check exercises real
        // alignment rather than only ever confirming "the playhead is at the
        // start."
        let targets = viewModel.cachedRhythmNoteTargets
        try #require(!targets.isEmpty)
        let farTarget = try #require(targets.max { $0.position.localTick < $1.position.localTick })

        viewModel.isPlaying = true
        viewModel.updateContinuousVisualsForTesting(elapsedTime: farTarget.targetSecondsAtOneX)

        let position = try #require(
            viewModel.purpleBarPosition,
            "playhead must have a position once gameplay is set up"
        )

        // The playhead must sit on a column that actually has a head.
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
    }
}
