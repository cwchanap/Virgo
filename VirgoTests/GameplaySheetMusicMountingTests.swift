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
/// Counts pixels whose channels differ between two rasters — the mounting
/// differential: the production sheet paints over an opaque stage
/// background, so "ink" is "pixels the engraving changed".
private func changedPixelCount(between lhs: RasterBitmap, and rhs: RasterBitmap) -> Int {
    guard lhs.pixelCount == rhs.pixelCount else { return .max }
    return (0..<lhs.pixelCount).count { index in
        let first = lhs.pixel(at: index)
        let second = rhs.pixel(at: index)
        return first.red != second.red || first.green != second.green
            || first.blue != second.blue || first.alpha != second.alpha
    }
}

/// Gates that the production `GameplayView.sheetMusicView(geometry:)` branch
/// actually *mounts* the package `DrumNotationView` over the installed
/// engraving — as opposed to the package renderer merely being able to draw,
/// which is what `DrumTabRenderProbeTests` covers.
///
/// The distinction is the whole point. `DrumTabRenderProbeTests` rasterizes
/// `DrumNotationView` and proves the primitives paint, but it mounts the view
/// itself, so a production branch that never mounts `DrumNotationView` leaves
/// it green. Every other drum-tab test asserts on layout *data*, which is
/// equally unchanged by a view that is never mounted. Rasterizing the same
/// `sheetMusicView` the production body calls means deleting the
/// `DrumNotationView` mount inside `GameplayStaticNotationLayers` fails here.
@Suite("Gameplay sheet music mounting", .serialized)
@MainActor
struct GameplaySheetMusicMountingTests {
    /// Renders the production sheet branch twice — once with the installed
    /// engraving's `noteHeads` intact and once with them stripped — and
    /// requires the rasters to differ.
    ///
    /// The test view mounts the injected `GameplayView` through the same
    /// `sheetMusicView(geometry:)` entry point `GameplayView.body` calls, so
    /// the rasterized hierarchy is the production one: `ScrollView` →
    /// `GameplayStaticNotationView` → `GameplayStaticNotationLayers` →
    /// `DrumNotationView`. The sheet paints over an opaque stage background,
    /// so the gate is a pixel-level differential, not an ink count: the only
    /// state change between the two rasters is the engraving's `noteHeads`,
    /// which only the mounted package head layer consumes.
    @Test("sheetMusicView mounts the package note head layer")
    func sheetMusicViewMountsNoteHeadLayer() async throws {
        try await TestSetup.withTestSetup {
            let viewModel = GameplayViewModelCoverageTestSupport.makeViewModel(noteCount: 8)
            await viewModel.loadChartData()
            await viewModel.setupGameplay(loadPersistedSpeed: false)
            defer { viewModel.cleanup() }

            let size = CGSize(width: 1_024, height: 768)
            // Pin the row width the sheet's onAppear reports so the first
            // raster cannot trigger a wider re-engrave mid-differential.
            viewModel.updateRowWidth(size.width)

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

            let gameplayView = GameplayView(
                chart: viewModel.chart,
                metronome: viewModel.metronome,
                initialViewModel: viewModel
            )
            // The production mounting branch, exactly as `GameplayView.body`
            // invokes it — inside a GeometryReader for the proxy argument.
            // The rasters are captured before the install mutation because
            // `sheetMusicView` reads the view model at render time, and through
            // the hosted rasterizer because `ImageRenderer` does not paint the
            // branch's `ScrollView` document content in this host.
            @MainActor func rasterizeProductionSheet() throws -> RasterBitmap {
                try rasterizeHostedView(
                    GeometryReader { proxy in
                        gameplayView.sheetMusicView(geometry: proxy)
                    },
                    size: size
                )
            }

            let headfulRaster = try rasterizeProductionSheet()

            // Baseline sanity: identical state must produce identical
            // rasters — guards the differential against renderer jitter.
            #expect(
                changedPixelCount(between: headfulRaster, and: try rasterizeProductionSheet()) == 0,
                "identical sheet state rasterized differently"
            )

            viewModel.installPreparedNotation(
                .ready(engraving.replacing(noteHeads: []), presentation)
            )
            let headlessRaster = try rasterizeProductionSheet()

            #expect(
                changedPixelCount(between: headfulRaster, and: headlessRaster) > 0,
                """
                sheetMusicView rasterized identically without \(engraving.noteHeads.count) \
                note head(s) — the package note-head layer is not mounted in production
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
