//
//  GameplaySheetMusicMountingTests.swift
//  VirgoTests
//

import Testing
import SwiftUI
import Foundation
@testable import Virgo

#if os(macOS)
/// Counts pixels with any meaningful coverage, regardless of colour, so the probe
/// survives a theme or palette change. Rasterization is `rasterizeView`
/// (`RenderRasterProbe.swift`), shared with the other pixel-level suites.
@MainActor
private func countInkPixels<V: View>(in view: V, size: CGSize) throws -> Int {
    try rasterizeView(view, size: size).count { $0.alpha > 20 }
}

/// Gates that `GameplaySheetMusicView.drumNotationView` actually *mounts* the layers it
/// is given — as opposed to the layers themselves being able to draw, which is what the
/// primitive-level suites cover.
///
/// The distinction is the whole point. `DrumTabRenderProbeTests` rasterizes
/// `NotationNoteHeadView` and proves the primitive paints, but it re-declares the
/// z-order in its own `ZStack`, so deleting the `noteHeads` `ForEach` from
/// `drumNotationView` leaves it green. Every other drum-tab test asserts on layout
/// *data*, which is equally unchanged by a view that is never mounted. Before this
/// suite existed, that deletion passed the entire test target.
@Suite("Gameplay sheet music mounting", .serialized)
@MainActor
struct GameplaySheetMusicMountingTests {
    /// Renders the production view twice — once with `cachedNotationLayout.noteHeads`
    /// intact and once with it emptied — and requires the first to paint more ink.
    ///
    /// Chart-wide ink, not a per-head rect: this drives a real `GameplayViewModel` whose
    /// layout it does not control, so the falsifiable claim available here is "removing
    /// the heads removes ink". Per-head bounds checking belongs to
    /// `DrumTabRenderProbeTests`, which runs against fixtures with locked geometry.
    @Test("drumNotationView mounts the note head layer")
    func drumNotationViewMountsNoteHeadLayer() async throws {
        try await TestSetup.withTestSetup {
            let viewModel = GameplayViewModelCoverageTestSupport.makeViewModel(noteCount: 8)
            await viewModel.loadChartData()
            viewModel.setupGameplay(loadPersistedSpeed: false)

            let heads = viewModel.cachedNotationLayout.noteHeads
            try #require(!heads.isEmpty, "fixture must render note heads for this probe to be non-vacuous")

            let gameplayView = GameplayView(chart: viewModel.chart, metronome: viewModel.metronome)
            let size = CGSize(width: 1_024, height: 768)

            let inkWithHeads = try countInkPixels(
                in: gameplayView.drumNotationView(viewModel: viewModel),
                size: size
            )
            viewModel.cachedNotationLayout.noteHeads = []
            let inkWithoutHeads = try countInkPixels(
                in: gameplayView.drumNotationView(viewModel: viewModel),
                size: size
            )

            #expect(
                inkWithHeads > inkWithoutHeads,
                """
                drumNotationView painted no additional ink for \(heads.count) note head(s) \
                (\(inkWithHeads) vs \(inkWithoutHeads)) — the head layer is not mounted
                """
            )
        }
    }
}
#endif
