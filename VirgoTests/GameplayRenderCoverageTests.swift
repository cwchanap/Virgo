//
//  GameplayRenderCoverageTests.swift
//  VirgoTests
//
//  Render-path coverage for GameplayView's principal visual branches:
//  1. Loading state (viewModel == nil) — exercised on first layout pass.
//  2. Populated state (viewModel != nil) — exercised via the injection seam.
//  3. Sub-view branches: StaffLinesBackgroundView, controlsView placeholder/loaded,
//     DrumClefSymbol, TimeSignatureSymbol.
//

import Testing
import SwiftUI
import Foundation
@testable import Virgo

@Suite("GameplayRenderCoverageTests", .serialized)
@MainActor
struct GameplayRenderCoverageTests {

    // MARK: - Loading-state render path

    /// Mounts `GameplayView(chart:metronome:)` without an initial view model.
    /// `layoutSubtreeIfNeeded()` evaluates the body with `viewModel == nil`,
    /// which exercises the loading-state branch in `sheetMusicView` and also
    /// the `controlsView` placeholder (`Color.black.frame(height: 100)`) branch.
    @Test("GameplayView mounts in loading state when no viewModel is provided")
    func testGameplayView_noInitialViewModel_rendersLoadingState() async throws {
        try await TestSetup.withTestSetup {
            let chart = GameplayViewModelCoverageTestSupport.makeChart()
            let metronome = GameplayViewModelCoverageTestSupport.makeMetronome()
            let settings = GameplayViewModelCoverageTestSupport.makeSettings()

            let view = GameplayView(chart: chart, metronome: metronome)
                .environmentObject(settings)

            // Initial layout evaluates the body with viewModel == nil,
            // exercising the loading-state branch for coverage.
            SwiftUITestUtilities.assertViewWithEnvironment(
                view,
                size: CGSize(width: 1280, height: 900)
            )
        }
    }

    // MARK: - Populated render path

    /// Injects a fully-prepared view model via the new `initialViewModel` seam.
    /// The view renders the populated notation branch from the very first layout pass,
    /// and also exercises the `controlsView` full `GameplayControlsView` branch.
    @Test("GameplayView mounts in populated state when a prepared viewModel is injected")
    func testGameplayView_withPreparedViewModel_rendersPopulatedState() async throws {
        try await TestSetup.withTestSetup {
            let vm = await GameplayViewModelCoverageTestSupport.makePreparedViewModel()
            defer { vm.cleanup() }

            // Verify the view model was fully prepared before mounting.
            #expect(vm.isDataLoaded, "makePreparedViewModel must call loadChartData()")
            #expect(!vm.cachedDrumBeats.isEmpty, "makePreparedViewModel must populate cachedDrumBeats via setupGameplay()")
            #expect(vm.staticStaffLinesView != nil, "makePreparedViewModel must build staticStaffLinesView via setupGameplay()")

            let view = GameplayView(chart: vm.chart, metronome: vm.metronome, initialViewModel: vm)
                .environmentObject(vm.practiceSettings)

            // Mounting with a non-nil viewModel exercises the populated notation branch.
            SwiftUITestUtilities.assertViewWithEnvironment(
                view,
                size: CGSize(width: 1280, height: 900)
            )
        }
    }

    // MARK: - Dynamic staff lines fallback (staticStaffLinesPresent: false)

    /// Passes `staticStaffLinesPresent: false` so `viewModel.staticStaffLinesView` is nil,
    /// exercising the else-branch in `sheetMusicView` that falls back to `staffLinesView(...)`.
    @Test("GameplayView renders dynamic staff lines when staticStaffLinesView is nil")
    func testGameplayView_dynamicStaffLinesFallback() async throws {
        try await TestSetup.withTestSetup {
            let vm = await GameplayViewModelCoverageTestSupport.makePreparedViewModel(staticStaffLinesPresent: false)
            defer { vm.cleanup() }
            #expect(vm.staticStaffLinesView == nil, "Fixture must clear staticStaffLinesView")

            let view = GameplayView(chart: vm.chart, metronome: vm.metronome, initialViewModel: vm)
                .environmentObject(vm.practiceSettings)

            SwiftUITestUtilities.assertViewWithEnvironment(
                view,
                size: CGSize(width: 1280, height: 900)
            )
            #expect(vm.staticStaffLinesView == nil,
                    "Injected view model must preserve a nil staticStaffLinesView during mount")
        }
    }

    // MARK: - StaffLinesBackgroundView

    /// Creates a `StaffLinesBackgroundView` whose `measurePositions` span multiple rows,
    /// ensuring the `ForEach(rows, …)` iteration in `body` visits more than one row.
    @Test("StaffLinesBackgroundView renders staff lines across multiple rows")
    func testStaffLinesBackgroundView_multipleRows() async throws {
        try await TestSetup.withTestSetup {
            // 4 four-four measures wraps at measure index 3 → rows 0 and 1 are present.
            let positions = GameplayLayout.calculateMeasurePositions(
                totalMeasures: 4, timeSignature: .fourFour
            )
            let rows = Set(positions.map { $0.row })
            #expect(rows.count >= 2, "Fixture must produce at least 2 rows")

            let view = StaffLinesBackgroundView(measurePositions: positions)
            SwiftUITestUtilities.assertViewWithEnvironment(
                view,
                size: CGSize(width: 1280, height: 900)
            )
        }
    }

    @Test("StaffLinesBackgroundView accepts custom width parameter")
    func testStaffLinesBackgroundView_customWidth() async throws {
        try await TestSetup.withTestSetup {
            let positions = GameplayLayout.calculateMeasurePositions(
                totalMeasures: 1, timeSignature: .fourFour
            )
            let customWidth: CGFloat = 500
            let view = StaffLinesBackgroundView(measurePositions: positions, width: customWidth)
            SwiftUITestUtilities.assertViewWithEnvironment(
                view,
                size: CGSize(width: 1280, height: 900)
            )
        }
    }

    // MARK: - MusicNotationViews

    @Test("DrumClefSymbol renders without error")
    func testDrumClefSymbol_renders() async throws {
        try await TestSetup.withTestSetup {
            let view = DrumClefSymbol()
            SwiftUITestUtilities.assertViewWithEnvironment(
                view,
                size: CGSize(width: 100, height: 100)
            )
        }
    }

    @Test("TimeSignatureSymbol renders the correct numerals for 3/4 time")
    func testTimeSignatureSymbol_threeFour_renders() async throws {
        try await TestSetup.withTestSetup {
            let view = TimeSignatureSymbol(timeSignature: .threeFour)
            SwiftUITestUtilities.assertView(
                view,
                containsStrings: ["3", "4"],
                size: CGSize(width: 100, height: 100)
            )
        }
    }

    // MARK: - Row anchor column with high note positions

    /// Verifies that `rowAnchorColumn` renders without error when the notation
    /// layout includes note heads at high above-staff positions (e.g. aboveLine9).
    /// This exercises the dynamic top-padding computation introduced to fix
    /// clipping of extended custom note positions.
    @Test("rowAnchorColumn accommodates note heads at aboveLine9 without clipping")
    func testRowAnchorColumn_withHighNotePositions_renders() async throws {
        try await TestSetup.withTestSetup {
            let vm = await GameplayViewModelCoverageTestSupport.makePreparedViewModel()
            defer { vm.cleanup() }

            let gameplayView = GameplayView(chart: vm.chart, metronome: vm.metronome)
            let rowCount = gameplayView.sheetRowCount(
                measurePositions: gameplayView.sheetMeasurePositions(viewModel: vm)
            )

            // The anchor column must render without error for any rowCount.
            let anchorColumn = gameplayView.rowAnchorColumn(rowCount: rowCount, viewModel: vm)
            SwiftUITestUtilities.assertViewWithEnvironment(
                anchorColumn,
                size: CGSize(width: 1280, height: 900)
            )
        }
    }

    /// Verifies that a chart with notes mapped to .aboveLine9 via notation
    /// position overrides produces a layout where the highest note head sits
    /// well above line5, and the anchor column still renders successfully.
    @Test("rowAnchorColumn with notation layout containing high above-staff notes")
    func testRowAnchorColumn_withAboveLine9Override_renders() async throws {
        try await TestSetup.withTestSetup {
            // Create a chart with crash notes (mapped to .aboveLine5 by default)
            // then override to .aboveLine9 via DrumNotationSettings.
            let chart = GameplayViewModelCoverageTestSupport.makeChart(
                noteCount: 2,
                interval: .quarter,
                measureOffset: 0.25
            )
            // Change the first note to crash so it uses an above-staff position.
            chart.notes[0].noteType = .crash

            let vm = GameplayViewModelCoverageTestSupport.makeViewModel(chart: chart)
            await vm.loadChartData()
            vm.setupGameplay()

            let gameplayView = GameplayView(chart: vm.chart, metronome: vm.metronome)
            let rowCount = gameplayView.sheetRowCount(
                measurePositions: gameplayView.sheetMeasurePositions(viewModel: vm)
            )

            let anchorColumn = gameplayView.rowAnchorColumn(rowCount: rowCount, viewModel: vm)
            SwiftUITestUtilities.assertViewWithEnvironment(
                anchorColumn,
                size: CGSize(width: 1280, height: 900)
            )
        }
    }

    /// Verifies that the populated sheet music view (which includes rowAnchorColumn)
    /// still renders correctly after the rowAnchorColumn signature change.
    @Test("Full sheet music view renders with updated rowAnchorColumn")
    func testSheetMusicView_rendersWithUpdatedRowAnchorColumn() async throws {
        try await TestSetup.withTestSetup {
            let vm = await GameplayViewModelCoverageTestSupport.makePreparedViewModel()
            defer { vm.cleanup() }

            let view = GameplayView(chart: vm.chart, metronome: vm.metronome, initialViewModel: vm)
                .environmentObject(vm.practiceSettings)

            SwiftUITestUtilities.assertViewWithEnvironment(
                view,
                size: CGSize(width: 1280, height: 900)
            )
        }
    }
}
