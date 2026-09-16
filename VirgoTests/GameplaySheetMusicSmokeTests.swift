//
//  GameplaySheetMusicSmokeTests.swift
//  VirgoTests
//
//  HPA-166 Task 9 — production-mounted smoke evidence over real DTX
//  fixtures at controlled widths, and package↔mounted agreement for rows,
//  measure bars, controls, and the playhead.
//

import Testing
import SwiftUI
import Foundation
import DrumNotation
@testable import Virgo

#if os(macOS)
/// Counts pixels whose channels differ between two rasters — the mounting
/// differential: the production sheet paints over an opaque stage
/// background, so "ink" is "pixels the engraving changed". Shared by
/// `GameplaySheetMusicMountingTests` and the per-family smoke below.
func changedPixelCount(between lhs: RasterBitmap, and rhs: RasterBitmap) -> Int {
    guard lhs.pixelCount == rhs.pixelCount else { return .max }
    return (0..<lhs.pixelCount).count { index in
        let first = lhs.pixel(at: index)
        let second = rhs.pixel(at: index)
        return first.red != second.red || first.green != second.green
            || first.blue != second.blue || first.alpha != second.alpha
    }
}

/// One primitive family a smoke case strips from the installed engraving.
/// Each family's ink only reaches the raster through `DrumNotationView`,
/// so an identical raster proves that layer is not mounted (or the family
/// never paints). `.furniture` clears `rows` — staff lines, clef and meter
/// all hang off the row staff frame; bar descriptors have their own case.
enum MountedPrimitiveFamily: String, Sendable {
    case noteHeads, rests, stems, beams, flags, rhythmDots, controls, measureBars, furniture
}

/// One mounted smoke case: a real-DTX fixture, the primitive family to
/// strip, and the viewport width the hosted sheet engraves at.
enum MountedSmokeCase: String, CaseIterable, Sendable {
    /// Dense multi-row fixture at the 900pt-floor viewport.
    case denseHeads, denseBeams, denseStems, denseRests, denseBars, denseFurniture
    /// Same dense fixture at the wrap-changing wide width.
    case denseHeadsWideWrap, denseBeamsWideWrap
    /// Sparse high-resolution fixture: isolated flags and a rhythm dot.
    case sparseFlags, sparseRhythmDots
    /// Stop/choke/damp marks on the real control fixture.
    case controlMarks

    var fixture: DrumTabFixture {
        switch self {
        case .denseHeads, .denseBeams, .denseStems, .denseRests,
             .denseBars, .denseFurniture, .denseHeadsWideWrap, .denseBeamsWideWrap:
            return DrumTabFixtureCatalog.multiRowStableWidths
        case .sparseFlags, .sparseRhythmDots:
            return DrumTabFixtureCatalog.isolatedFlaggedNotes
        case .controlMarks:
            return DrumTabFixtureCatalog.stopChokeDamp
        }
    }

    var family: MountedPrimitiveFamily {
        switch self {
        case .denseHeads, .denseHeadsWideWrap: return .noteHeads
        case .denseBeams, .denseBeamsWideWrap: return .beams
        case .denseStems: return .stems
        case .denseRests: return .rests
        case .denseBars: return .measureBars
        case .denseFurniture: return .furniture
        case .sparseFlags: return .flags
        case .sparseRhythmDots: return .rhythmDots
        case .controlMarks: return .controls
        }
    }

    /// The hosted sheet's own `onAppear` reports the viewport width as the
    /// row width, so engraving at the wrap-changing width means hosting at
    /// that width. `GameplayLayout.maxRowWidth` (900) is the floor.
    var viewportWidth: CGFloat {
        switch self {
        case .denseHeadsWideWrap, .denseBeamsWideWrap: return 2_400
        default: return 1_024
        }
    }

    /// True when the case must verify the wide width actually repacked the
    /// dense fixture onto fewer rows before rasterizing — otherwise the
    /// "wrap-changed" evidence would be accidental.
    var expectsWrapChange: Bool {
        switch self {
        case .denseHeadsWideWrap, .denseBeamsWideWrap: return true
        default: return false
        }
    }
}

/// One controlled-width agreement scenario: a real-DTX fixture run through
/// the production preparation route at the 900pt floor and at a practical
/// wider width.
struct MountedWidthScenario: Sendable {
    let name: String
    let fixture: DrumTabFixture
    let expectControls: Bool
    /// Only the dense multi-row fixture is required to wrap onto fewer rows
    /// at the wide width; the sparse/control fixtures exercise the
    /// re-engrave path with agreement asserted either way.
    let expectFewerRowsAtWideWidth: Bool
}

/// Mounted smoke over the real production hierarchy. The rasterized view is
/// the same `GameplayView.sheetMusicView(geometry:)` branch `body` calls —
/// `ScrollView` → `GameplayStaticNotationView` → `GameplayStaticNotationLayers`
/// → `DrumNotationView` — so a family that stops reaching the raster fails
/// here even when every layout-level test stays green.
@Suite("Gameplay sheet music smoke", .serialized)
@MainActor
struct GameplaySheetMusicSmokeTests {
    /// Per-family mounted differential on real DTX fixtures: strip exactly
    /// one primitive family from the installed engraving and require the
    /// production sheet raster to change. Covers head/stem attachment,
    /// beam ink, flags, dots, rests, control marks, bars, and row furniture
    /// (staff lines + clef + meter) across dense, sparse, control-bearing,
    /// and wrap-changed examples.
    @Test("sheetMusicView paints each package primitive family", arguments: MountedSmokeCase.allCases)
    func sheetMusicViewPaintsPrimitiveFamilies(_ scenario: MountedSmokeCase) async throws {
        try await TestSetup.withTestSetup {
            let rendered = try DrumTabFixtureHarness.render(scenario.fixture)
            let viewModel = GameplayViewModel(
                chart: rendered.chart,
                metronome: GameplayViewModelTestHarness.createTestMetronome()
            )
            await viewModel.loadChartData()
            await viewModel.setupGameplay(loadPersistedSpeed: false)
            defer { viewModel.cleanup() }

            let size = CGSize(width: scenario.viewportWidth, height: 768)
            try installAtScenarioWidth(viewModel: viewModel, scenario: scenario)

            let engraving = try #require(viewModel.cachedEngravedNotation)
            try #require(
                scenario.primitiveCount(in: engraving) > 0,
                "fixture must render \(scenario.family.rawValue) for the differential to be non-vacuous"
            )
            let presentation = viewModel.notationPresentation
                ?? GameplayNotationPresentation(annotations: .empty, accessibilityLabels: [:])
            let gameplayView = GameplayView(
                chart: viewModel.chart,
                metronome: viewModel.metronome,
                initialViewModel: viewModel
            )

            @MainActor func rasterizeProductionSheet() throws -> RasterBitmap {
                try rasterizeHostedView(
                    GeometryReader { proxy in
                        gameplayView.sheetMusicView(geometry: proxy)
                    },
                    size: size
                )
            }

            let headful = try rasterizeProductionSheet()
            viewModel.installPreparedNotation(
                .ready(engraving.stripped(scenario.family), presentation)
            )
            let stripped = try rasterizeProductionSheet()

            #expect(
                changedPixelCount(between: headful, and: stripped) > 0,
                """
                \(scenario.rawValue): sheet rasterized identically without \
                \(scenario.family.rawValue) — that package layer is not mounted in production
                """
            )
        }
    }

    /// Pins the engraving to the scenario's viewport width. Wrap-change
    /// cases measure the repack (narrow first, then wide) so the
    /// differential is never vacuous; the others match the width the
    /// sheet's `onAppear` reports so the first raster cannot trigger a
    /// re-engrave mid-differential.
    private func installAtScenarioWidth(
        viewModel: GameplayViewModel,
        scenario: MountedSmokeCase
    ) throws {
        if scenario.expectsWrapChange {
            viewModel.updateRowWidth(1_024)
            let narrowRows = try #require(viewModel.cachedEngravedNotation).rows.count
            viewModel.updateRowWidth(scenario.viewportWidth)
            let wideRows = try #require(viewModel.cachedEngravedNotation).rows.count
            try #require(
                wideRows < narrowRows,
                "2400pt must repack the dense fixture onto fewer rows (\(wideRows) !< \(narrowRows))"
            )
        } else {
            viewModel.updateRowWidth(scenario.viewportWidth)
        }
    }

    /// The playhead bar mounts inside the sheet's `ScrollView` ZStack, so
    /// driving a note target must change the mounted raster — not just the
    /// view-model position the alignment tests assert.
    @Test("sheetMusicView mounts the playhead bar")
    func sheetMusicViewMountsPlayheadBar() async throws {
        try await TestSetup.withTestSetup {
            let rendered = try DrumTabFixtureHarness.render(DrumTabFixtureCatalog.multiRowStableWidths)
            let viewModel = GameplayViewModel(
                chart: rendered.chart,
                metronome: GameplayViewModelTestHarness.createTestMetronome()
            )
            await viewModel.loadChartData()
            await viewModel.setupGameplay(loadPersistedSpeed: false)
            defer { viewModel.cleanup() }

            let size = CGSize(width: 1_024, height: 768)
            viewModel.updateRowWidth(size.width)
            let engraved = try #require(viewModel.cachedEngravedNotation)

            // The bar only changes the raster when it lands inside the
            // viewport: pick the latest-tick target on row 0.
            let rowZeroMeasures = Set(
                engraved.measures.filter { $0.rowIndex == 0 }.map(\.index)
            )
            let target = try #require(
                viewModel.cachedRhythmNoteTargets
                    .filter { rowZeroMeasures.contains($0.position.measureIndex) }
                    .max { $0.position.localTick < $1.position.localTick }
            )

            let gameplayView = GameplayView(
                chart: viewModel.chart,
                metronome: viewModel.metronome,
                initialViewModel: viewModel
            )
            @MainActor func rasterizeProductionSheet() throws -> RasterBitmap {
                try rasterizeHostedView(
                    GeometryReader { proxy in
                        gameplayView.sheetMusicView(geometry: proxy)
                    },
                    size: size
                )
            }

            let idle = try rasterizeProductionSheet()
            viewModel.isPlaying = true
            viewModel.updateContinuousVisualsForTesting(elapsedTime: target.targetSecondsAtOneX)
            _ = try #require(viewModel.purpleBarPosition)
            let playing = try rasterizeProductionSheet()

            #expect(
                changedPixelCount(between: idle, and: playing) > 0,
                "playhead bar did not change the mounted sheet raster"
            )
        }
    }

    /// Controlled-width agreement: at the 900pt floor and at a width that
    /// changes the dense fixture's wrapping, the mounted surface (row
    /// anchors, measure positions, content extents, measure→row cache) and
    /// the package layout (rows, bars, controls) must agree, and the live
    /// playhead must resolve through the installed engraving's own
    /// formatter lookup.
    @Test("mounted surface agrees with the package layout across widths", arguments: [
        MountedWidthScenario(
            name: "dense multi-row",
            fixture: DrumTabFixtureCatalog.multiRowStableWidths,
            expectControls: false,
            expectFewerRowsAtWideWidth: true
        ),
        MountedWidthScenario(
            name: "sparse high-resolution",
            fixture: DrumTabFixtureCatalog.isolatedFlaggedNotes,
            expectControls: false,
            expectFewerRowsAtWideWidth: false
        ),
        MountedWidthScenario(
            name: "control-bearing",
            fixture: DrumTabFixtureCatalog.stopChokeDamp,
            expectControls: true,
            expectFewerRowsAtWideWidth: false
        )
    ])
    func mountedSurfaceAgreesWithPackageAcrossWidths(_ scenario: MountedWidthScenario) async throws {
        try await TestSetup.withTestSetup {
            let rendered = try DrumTabFixtureHarness.render(scenario.fixture)
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

            // 900pt floor: the practical narrow width.
            viewModel.updateRowWidth(GameplayLayout.maxRowWidth)
            try assertMountedInputAgreement(
                viewModel: viewModel,
                gameplayView: gameplayView,
                expectedRowWidth: GameplayLayout.maxRowWidth,
                resolvedInput: rendered.resolvedInput,
                expectControls: scenario.expectControls
            )
            try assertPlayheadAgreement(viewModel: viewModel)
            let narrowRowCount = try #require(viewModel.cachedEngravedNotation).rows.count

            // 2400pt: beyond the dense fixture's wrap boundaries.
            viewModel.updateRowWidth(2_400)
            try assertMountedInputAgreement(
                viewModel: viewModel,
                gameplayView: gameplayView,
                expectedRowWidth: 2_400,
                resolvedInput: rendered.resolvedInput,
                expectControls: scenario.expectControls
            )
            try assertPlayheadAgreement(viewModel: viewModel)
            let wideRowCount = try #require(viewModel.cachedEngravedNotation).rows.count
            if scenario.expectFewerRowsAtWideWidth {
                #expect(
                    wideRowCount < narrowRowCount,
                    "\(scenario.name): 2400pt must rewrap (\(wideRowCount) !< \(narrowRowCount))"
                )
            }
        }
    }

    /// Asserts every mounted surface derived from the installed engraving
    /// agrees with the engraving itself: row anchors, measure positions and
    /// content extents on `staticNotationInput`, the autoscroll
    /// measure→row cache, measure-bar bounds, control column anchors, and
    /// representative VoiceOver labels on the mounted presentation.
    private func assertMountedInputAgreement(
        viewModel: GameplayViewModel,
        gameplayView: GameplayView,
        expectedRowWidth: CGFloat,
        resolvedInput: ResolvedNotationInput,
        expectControls: Bool
    ) throws {
        let engraved = try #require(viewModel.cachedEngravedNotation)
        #expect(engraved.style.formatting.availableRowWidth == expectedRowWidth)

        let input = gameplayView.staticNotationInput(viewModel: viewModel)
        #expect(input.usesEngravedNotation)
        #expect(input.rowCount == engraved.rows.count)
        #expect(input.contentWidth == engraved.contentWidth)
        #expect(input.contentHeight == engraved.contentHeight)

        // Mounted scroll anchors derive from package row geometry verbatim.
        let anchors = input.rowAnchors
        let firstRow = try #require(engraved.rows.first)
        #expect(anchors.firstRowTop == max(0, firstRow.staffCenterY - engraved.style.rowHeight / 2))
        #expect(anchors.rowPitch == engraved.style.rowHeight + engraved.style.rowVerticalSpacing)

        // Mounted measure positions and the autoscroll measure→row cache
        // both agree with the engraved measure placement.
        let positions = input.measurePositions
        #expect(positions.count == engraved.measures.count)
        for (position, measure) in zip(positions, engraved.measures) {
            #expect(position.measureIndex == measure.index)
            #expect(position.row == measure.rowIndex)
            #expect(position.xOffset == measure.xOffset)
            #expect(viewModel.cachedMeasureRowMap[measure.index] == measure.rowIndex)
        }

        try assertInkAndLabelsAgreement(
            engraved: engraved,
            resolvedInput: resolvedInput,
            presentation: input.presentation,
            expectControls: expectControls
        )
    }

    /// Bars sit on their measure's row at a measure boundary; controls
    /// anchor the logical column at their resolved onset tick (checked
    /// against the installed engraving's embedded formatter); and the
    /// mounted presentation carries the app-localized VoiceOver map
    /// unchanged — representative ink must have a label.
    private func assertInkAndLabelsAgreement(
        engraved: EngravedNotation,
        resolvedInput: ResolvedNotationInput,
        presentation: GameplayNotationPresentation?,
        expectControls: Bool
    ) throws {
        for bar in engraved.measureBars {
            let measure = try #require(engraved.measures.first { $0.index == bar.measureIndex })
            #expect(bar.rowIndex == measure.rowIndex)
            #expect(
                bar.x == measure.xOffset || bar.x == measure.xOffset + measure.width,
                "bar for measure \(bar.measureIndex) x \(bar.x) sits off the measure bounds"
            )
        }
        #expect(engraved.measureBars.last?.isFinal == true)

        for control in engraved.controls {
            let resolved = try #require(
                resolvedInput.controls.first { $0.id == control.controlID }
            )
            let column = try #require(
                engraved.formatted.position(
                    measureIndex: resolved.position.measureIndex,
                    localTick: Double(resolved.position.localTick)
                )
            )
            #expect(abs(control.position.x - column.x) < 0.001)
        }
        if expectControls {
            #expect(!engraved.controls.isEmpty)
        }

        let labels = try #require(presentation).accessibilityLabels
        #expect(!labels.isEmpty)
        for head in engraved.noteHeads.prefix(3) {
            #expect(labels[.note(head.noteID)] != nil)
        }
        for control in engraved.controls {
            #expect(labels[.control(control.controlID)] != nil)
        }
    }

    /// Asserts the live playhead equals the installed engraving's own
    /// `FormattedNotation.position` lookup and the wrapped row's
    /// `staffCenterY` — the same join the alignment suite pins, re-verified
    /// at each controlled width after re-engrave.
    private func assertPlayheadAgreement(viewModel: GameplayViewModel) throws {
        let engraved = try #require(viewModel.cachedEngravedNotation)
        let target = try #require(
            viewModel.cachedRhythmNoteTargets
                .max { $0.position.localTick < $1.position.localTick }
        )
        viewModel.isPlaying = true
        viewModel.updateContinuousVisualsForTesting(elapsedTime: target.targetSecondsAtOneX)
        let playhead = try #require(viewModel.purpleBarPosition)
        let measure = try #require(
            engraved.measures.first { $0.index == target.position.measureIndex }
        )
        let position = try #require(
            engraved.formatted.position(
                measureIndex: target.position.measureIndex,
                localTick: min(Double(target.position.localTick), Double(measure.durationTicks))
            )
        )
        let row = try #require(engraved.rows.first { $0.index == position.rowIndex })
        #expect(abs(playhead.x - Double(position.x)) < 0.001)
        #expect(abs(playhead.y - Double(row.staffCenterY)) < 0.001)
    }
}

private extension MountedSmokeCase {
    /// How many primitives of this case's family the engraving carries —
    /// the differential is vacuous at zero.
    func primitiveCount(in engraving: EngravedNotation) -> Int {
        switch family {
        case .noteHeads: return engraving.noteHeads.count
        case .rests: return engraving.rests.count
        case .stems: return engraving.stems.count
        case .beams: return engraving.beams.count
        case .flags: return engraving.flags.count
        case .rhythmDots: return engraving.rhythmDots.count
        case .controls: return engraving.controls.count
        case .measureBars: return engraving.measureBars.count
        case .furniture: return engraving.rows.count
        }
    }
}

private extension EngravedNotation {
    /// A copy with one primitive family removed — the mounted-ink
    /// differential's "off" state.
    func stripped(_ family: MountedPrimitiveFamily) -> EngravedNotation {
        EngravedNotation(
            formatted: formatted,
            style: style,
            rows: family == .furniture ? [] : rows,
            measures: measures,
            noteHeads: family == .noteHeads ? [] : noteHeads,
            rests: family == .rests ? [] : rests,
            stems: family == .stems ? [] : stems,
            beams: family == .beams ? [] : beams,
            flags: family == .flags ? [] : flags,
            ledgerLines: ledgerLines,
            rhythmDots: family == .rhythmDots ? [] : rhythmDots,
            articulations: articulations,
            controls: family == .controls ? [] : controls,
            tuplets: tuplets,
            measureBars: family == .measureBars ? [] : measureBars,
            paintedBounds: paintedBounds,
            contentWidth: contentWidth,
            contentHeight: contentHeight
        )
    }
}
#endif
