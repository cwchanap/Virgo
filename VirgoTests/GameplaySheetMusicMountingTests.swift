//
//  GameplaySheetMusicMountingTests.swift
//  VirgoTests
//

import Testing
import SwiftUI
import Foundation
import DrumNotation
@testable import Virgo

#if os(macOS)
/// Counts pixels with any meaningful coverage, regardless of colour, so the probe
/// survives a theme or palette change. Rasterization is `rasterizeView`
/// (`RenderRasterProbe.swift`), shared with the other pixel-level suites.
@MainActor
private func countInkPixels<V: View>(in view: V, size: CGSize) throws -> Int {
    try rasterizeView(view, size: size).count { $0.alpha > 20 }
}

/// Gates that `GameplaySheetMusicView.drumNotationView` actually *mounts* the
/// package `DrumNotationView` over the installed engraving — as opposed to the
/// package renderer merely being able to draw, which is what
/// `DrumTabRenderProbeTests` covers.
///
/// The distinction is the whole point. `DrumTabRenderProbeTests` rasterizes
/// `DrumNotationView` and proves the primitives paint, but it mounts the view
/// itself, so a production branch that never mounts `DrumNotationView` leaves
/// it green. Every other drum-tab test asserts on layout *data*, which is
/// equally unchanged by a view that is never mounted. Before this suite
/// existed, that deletion passed the entire test target.
@Suite("Gameplay sheet music mounting", .serialized)
@MainActor
struct GameplaySheetMusicMountingTests {
    /// Renders the production view twice — once with the installed engraving's
    /// `noteHeads` intact and once with them stripped — and requires the first
    /// to paint more ink.
    ///
    /// Chart-wide ink, not a per-head rect: this drives a real `GameplayViewModel`
    /// whose engraving it does not control, so the falsifiable claim available
    /// here is "removing the heads removes ink". Per-head bounds checking
    /// belongs to `DrumTabRenderProbeTests`, which runs against fixtures with
    /// locked geometry.
    @Test("drumNotationView mounts the package note head layer")
    func drumNotationViewMountsNoteHeadLayer() async throws {
        try await TestSetup.withTestSetup {
            let viewModel = GameplayViewModelCoverageTestSupport.makeViewModel(noteCount: 8)
            await viewModel.loadChartData()
            await viewModel.setupGameplay(loadPersistedSpeed: false)

            let engraving = try #require(
                viewModel.cachedEngravedNotation,
                "fixture must install an engraving for this probe to be non-vacuous"
            )
            try #require(
                !engraving.noteHeads.isEmpty,
                "fixture must render note heads for this probe to be non-vacuous"
            )
            let presentation = viewModel.notationPresentation
                ?? GameplayNotationPresentation(annotations: .empty, accessibilityLabels: [:])

            let gameplayView = GameplayView(chart: viewModel.chart, metronome: viewModel.metronome)
            let size = CGSize(width: 1_024, height: 768)

            let inkWithHeads = try countInkPixels(
                in: gameplayView.drumNotationView(viewModel: viewModel),
                size: size
            )
            viewModel.installPreparedNotation(
                .ready(engraving.replacing(noteHeads: []), presentation)
            )
            let inkWithoutHeads = try countInkPixels(
                in: gameplayView.drumNotationView(viewModel: viewModel),
                size: size
            )

            #expect(
                inkWithHeads > inkWithoutHeads,
                """
                drumNotationView painted no additional ink for \(engraving.noteHeads.count) note head(s) \
                (\(inkWithHeads) vs \(inkWithoutHeads)) — the package note-head layer is not mounted
                """
            )
        }
    }
}

private extension EngravedNotation {
    /// A copy of this immutable engraving with selected primitive arrays
    /// swapped — mirrors `DrumTabRenderProbeTests`'s one-layer differential.
    func replacing(noteHeads: [EngravedNoteHead]) -> EngravedNotation {
        EngravedNotation(
            formatted: formatted,
            style: style,
            rows: rows,
            measures: measures,
            noteHeads: noteHeads,
            rests: rests,
            stems: stems,
            beams: beams,
            flags: flags,
            ledgerLines: ledgerLines,
            rhythmDots: rhythmDots,
            articulations: articulations,
            controls: controls,
            tuplets: tuplets,
            measureBars: measureBars,
            paintedBounds: paintedBounds,
            contentWidth: contentWidth,
            contentHeight: contentHeight
        )
    }
}
#endif
