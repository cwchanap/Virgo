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
            let viewModel = GameplayViewModelTestSupport.makeViewModel(noteCount: 8)
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

    // MARK: - Consolidated from GameplayNotationCoverageAdditionsTests

    /// The sheet's own fatal guard (distinct from `body`'s interception):
    /// calling `sheetMusicView` directly on a view model whose installed
    /// preparation failed must render the fatal sheet.
    @Test("sheetMusicView renders the fatal sheet when installed preparation failed")
    func sheetMusicViewRendersFatalSheetOnPreparationFailure() async throws {
        try await TestSetup.withTestSetup {
            let viewModel = GameplayViewModelTestSupport.makeViewModel(noteCount: 4)
            viewModel.installPreparedNotation(.failed(GameplayNotationPreparationFailure(
                detail: "synthetic failure",
                userMessage: "Notation exploded"
            )))
            #expect(viewModel.practiceUnavailableMessage == "Notation exploded")

            let gameplayView = GameplayView(
                chart: viewModel.chart,
                metronome: viewModel.metronome,
                initialViewModel: viewModel
            )
            let mounted = SwiftUITestUtilities.assertViewWithEnvironment(
                GeometryReader { proxy in
                    gameplayView.sheetMusicView(geometry: proxy)
                },
                size: CGSize(width: 800, height: 600)
            )
            let texts = SwiftUITestUtilities.renderedTexts(from: mounted.root)
            #expect(texts.contains("Practice unavailable"))
            #expect(texts.contains("Notation exploded"))
        }
    }

    /// The mounted sheet's live wiring: `currentRow` and `isPlaying`
    /// changes run their auto-scroll `onChange` arms against the mounted
    /// render without destabilizing it (the scroll offsets themselves are
    /// observable only in the UI suite's playback flow), and a container
    /// resize feeds `updateRowWidth` through the width `onChange`.
    @Test("mounted sheet drives auto-scroll and row-width onChange handlers")
    func mountedSheetDrivesAutoScrollAndRowWidth() async throws {
        try await TestSetup.withTestSetup {
            let rendered = try DrumTabFixtureHarness.render(DrumTabFixtureCatalog.multiRowStableWidths)
            let viewModel = GameplayViewModel(
                chart: rendered.chart,
                metronome: GameplayViewModelTestHarness.createTestMetronome()
            )
            await viewModel.loadChartData()
            await viewModel.setupGameplay(loadPersistedSpeed: false)
            defer { viewModel.cleanup() }

            let gameplayView = GameplayView(
                chart: viewModel.chart,
                metronome: viewModel.metronome,
                initialViewModel: viewModel
            )
            let mounted = SwiftUITestUtilities.assertViewWithEnvironment(
                GeometryReader { proxy in
                    gameplayView.sheetMusicView(geometry: proxy)
                },
                size: CGSize(width: 1_024, height: 768)
            )
            await SwiftUITestUtilities.waitForRenderStabilization(in: mounted)

            // Playing + a row change: both scroll `onChange` arms fire
            // against real playable content while the mounted render
            // stabilizes.
            let maxRow = try #require(viewModel.cachedEngravedNotation?.rows.map(\.index).max())
            viewModel.isPlaying = true
            viewModel.currentRow = maxRow
            await SwiftUITestUtilities.waitForRenderStabilization(in: mounted)

            #if os(macOS)
            // A container resize re-engraves at the new width through the
            // geometry `onChange`.
            mounted.hostingView.frame = CGRect(origin: .zero, size: CGSize(width: 1_400, height: 768))
            await SwiftUITestUtilities.waitForRenderStabilization(in: mounted)
            #expect(viewModel.cachedLayoutRowWidth == 1_400)
            #endif
        }
    }

    /// End-to-end auto-scroll regression: playing and advancing
    /// `currentRow` must drive the real `ScrollViewReader.scrollTo`
    /// (`.top` anchor) so the hosted `NSScrollView`'s clip view actually
    /// comes to rest at the target row's anchor top. A target that only
    /// *draws* at its top (`.offset`) still lays out at y=0 and lands every
    /// row at the sheet top — that failure mode reads back here as a
    /// zero offset.
    @Test("playing and changing currentRow scrolls the real clip view to the row anchor top")
    func mountedSheetScrollToLandsAtRowAnchorTop() async throws {
        try await TestSetup.withTestSetup {
            let rendered = try DrumTabFixtureHarness.render(DrumTabFixtureCatalog.multiRowStableWidths)
            let viewModel = GameplayViewModel(
                chart: rendered.chart,
                metronome: GameplayViewModelTestHarness.createTestMetronome()
            )
            await viewModel.loadChartData()
            await viewModel.setupGameplay(loadPersistedSpeed: false)
            defer { viewModel.cleanup() }

            let gameplayView = GameplayView(
                chart: viewModel.chart,
                metronome: viewModel.metronome,
                initialViewModel: viewModel
            )
            viewModel.updateRowWidth(1_024)

            #if os(macOS)
            let host = try hostWindowedSheet(gameplayView)
            defer { host.window.orderOut(nil) }
            let input = gameplayView.staticNotationInput(viewModel: viewModel)
            let tops = input.rowAnchorTops
            try #require(tops.count > 1, "fixture must mount multiple rows")
            let targetRow = try #require(
                tops.indices.max { tops[$0] < tops[$1] }, "anchor tops must not be empty"
            )
            try #require(tops[targetRow] > 0, "target anchor must sit below the sheet top")

            // Drive the production auto-scroll path: play, then advance.
            viewModel.isPlaying = true
            viewModel.currentRow = targetRow
            // The production scroll runs in a 0.25s ease animation — pump
            // the run loop until the clip view stops moving.
            var offset = host.scrollView.contentView.bounds.origin.y
            var stableReads = 0
            while stableReads < 3 {
                Self.pumpRunLoop(0.1)
                host.hostingView.layoutSubtreeIfNeeded()
                let next = host.scrollView.contentView.bounds.origin.y
                stableReads = abs(next - offset) < 0.1 ? stableReads + 1 : 0
                offset = next
            }
            #expect(
                abs(offset - tops[targetRow]) < 1.0,
                "scrollTo(\"row_\(targetRow)\") rested at \(offset); anchor top is \(tops[targetRow])"
            )
            #else
            let mounted = SwiftUITestUtilities.assertViewWithEnvironment(
                GeometryReader { proxy in
                    gameplayView.sheetMusicView(geometry: proxy)
                },
                size: CGSize(width: 1_024, height: 768)
            )
            await SwiftUITestUtilities.waitForRenderStabilization(in: mounted)
            #endif
        }
    }

    /// Services the main run loop synchronously — CA-driven scroll
    /// animations never tick from an `await` suspension, and
    /// `RunLoop.current` is unavailable in async contexts.
    private static func pumpRunLoop(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    #if os(macOS)
    /// A sheet mounted in a real window for observing real `scrollTo`
    /// landings.
    private struct WindowedSheetHost {
        let window: NSWindow
        let hostingView: NSHostingView<AnyView>
        let scrollView: NSScrollView
    }

    /// Hosts the sheet in a real window and returns the production
    /// `NSScrollView` it mounted. `scrollTo` animates through Core
    /// Animation, which never ticks for an unparented `NSHostingView`, so
    /// the unwindowed mount the other mounting tests use cannot observe
    /// where a scroll actually lands.
    private func hostWindowedSheet(_ gameplayView: GameplayView) throws -> WindowedSheetHost {
        let hostingView = NSHostingView(rootView: AnyView(
            GeometryReader { proxy in
                gameplayView.sheetMusicView(geometry: proxy)
            }
        ))
        hostingView.frame = CGRect(origin: .zero, size: CGSize(width: 1_024, height: 768))
        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.orderFrontRegardless()
        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()
        Self.pumpRunLoop(0.1)
        do {
            return WindowedSheetHost(
                window: window,
                hostingView: hostingView,
                scrollView: try #require(firstHostedScrollView(in: hostingView))
            )
        } catch {
            // The window was already ordered front — close it on the
            // failure path instead of leaking it into the test host.
            window.orderOut(nil)
            throw error
        }
    }
    #endif

    @Test("Gameplay sheet auto-scroll preserves legacy empty layout without scrolling notation-only content")
    func testGameplaySheetAutoScrollPolicy() async throws {
        try await TestSetup.withTestSetup {
            let restOnlyViewModel = GameplayViewModelTestSupport.makeViewModel(
                chart: Chart(difficulty: .medium),
                noteCount: 0
            )
            defer { restOnlyViewModel.cleanup() }
            await restOnlyViewModel.loadChartData()
            await restOnlyViewModel.setupGameplay(loadPersistedSpeed: false)

            let controlOnlyChart = Chart(difficulty: .medium)
            controlOnlyChart.controlEvents.append(ChartControlEvent(
                kind: .choke,
                measureNumber: 1,
                measureOffset: 0,
                targetLaneID: "1A"
            ))
            let controlOnlyViewModel = GameplayViewModelTestSupport.makeViewModel(chart: controlOnlyChart)
            defer { controlOnlyViewModel.cleanup() }
            await controlOnlyViewModel.loadChartData()
            await controlOnlyViewModel.setupGameplay(loadPersistedSpeed: false)

            let playableViewModel = GameplayViewModelTestSupport.makeViewModel(noteCount: 1)
            defer { playableViewModel.cleanup() }
            await playableViewModel.loadChartData()
            await playableViewModel.setupGameplay(loadPersistedSpeed: false)

            let legacyEmptyViewModel = GameplayViewModelTestSupport.makeViewModel(noteCount: 0)
            defer { legacyEmptyViewModel.cleanup() }
            await legacyEmptyViewModel.loadChartData()
            await legacyEmptyViewModel.setupGameplay(loadPersistedSpeed: false)
            legacyEmptyViewModel.clearNotationInstallation()

            let gameplayView = GameplayView(chart: playableViewModel.chart, metronome: playableViewModel.metronome)
            #expect(!gameplayView.shouldAutoScrollSheet(viewModel: restOnlyViewModel, isPlaying: true))
            #expect(!gameplayView.shouldAutoScrollSheet(viewModel: controlOnlyViewModel, isPlaying: true))
            #expect(gameplayView.shouldAutoScrollSheet(viewModel: playableViewModel, isPlaying: true))
            #expect(gameplayView.shouldAutoScrollSheet(viewModel: legacyEmptyViewModel, isPlaying: true))
            #expect(!gameplayView.shouldAutoScrollSheet(viewModel: playableViewModel, isPlaying: false))
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
