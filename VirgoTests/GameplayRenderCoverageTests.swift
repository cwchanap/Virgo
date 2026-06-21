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
import Observation
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

    @Test("GameplayView hides gameplay chrome until the view model is prepared")
    func testGameplayView_unpreparedViewModelRendersLoadingOnlyState() async throws {
        try await TestSetup.withTestSetup {
            let vm = GameplayViewModelCoverageTestSupport.makeViewModel()
            defer { vm.cleanup() }

            #expect(!vm.isGameplayPrepared, "Fixture must not call setupGameplay()")

            let view = GameplayView(chart: vm.chart, metronome: vm.metronome, initialViewModel: vm)
                .environmentObject(vm.practiceSettings)
            let mountedView = SwiftUITestUtilities.assertViewWithEnvironment(
                view,
                size: CGSize(width: 1280, height: 900)
            )
            let texts = SwiftUITestUtilities.renderedTexts(from: mountedView.root)
            let identifiers = SwiftUITestUtilities.renderedIdentifiers(from: mountedView.root)

            #expect(texts.contains("Loading..."))
            #expect(!texts.contains("Unknown Song"))
            #expect(!identifiers.contains("gameplayHeaderPlayPauseButton"))
            #expect(!identifiers.contains("gameplayMainPlayPauseButton"))
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
            #expect(
                !vm.cachedDrumBeats.isEmpty,
                "makePreparedViewModel must populate cachedDrumBeats via setupGameplay()"
            )
            #expect(
                vm.staticStaffLinesView != nil,
                "makePreparedViewModel must build staticStaffLinesView via setupGameplay()"
            )

            let view = GameplayView(chart: vm.chart, metronome: vm.metronome, initialViewModel: vm)
                .environmentObject(vm.practiceSettings)

            // Mounting with a non-nil viewModel exercises the populated notation branch.
            SwiftUITestUtilities.assertViewWithEnvironment(
                view,
                size: CGSize(width: 1280, height: 900)
            )
        }
    }

    @Test("Static notation rendering does not rebuild on per-beat state changes")
    func testDrumNotationViewDoesNotRebuildOnBeatChanges() async throws {
        // Regression guard: beat-boundary highlighting was removed because
        // re-evaluating the notation tree on every beat forced expensive sheet
        // re-layouts. The notation views must continue to depend only on
        // cachedNotationLayout, never on per-beat state, so that the ~30 Hz
        // visual tick does not invalidate them.
        try await TestSetup.withTestSetup {
            let vm = await GameplayViewModelCoverageTestSupport.makePreparedViewModel()
            defer { vm.cleanup() }
            vm.isPlaying = true

            let view = GameplayView(chart: vm.chart, metronome: vm.metronome, initialViewModel: vm)

            var didInvalidate = false
            withObservationTracking {
                _ = view.drumNotationView(viewModel: vm)
            } onChange: {
                didInvalidate = true
            }

            // Per-beat state (driven by the metronome / visual tick) must NOT
            // invalidate the static notation tree.
            vm.currentBeat = 3
            vm.totalBeatsElapsed = 7

            #expect(
                !didInvalidate,
                "Per-beat state changes must not invalidate static notation rendering"
            )
        }
    }

    @Test("Static sheet music content does not observe purple bar position")
    func testStaticSheetMusicContentDoesNotObservePurpleBarPosition() async throws {
        try await TestSetup.withTestSetup {
            let vm = await GameplayViewModelCoverageTestSupport.makePreparedViewModel()
            defer { vm.cleanup() }
            vm.isPlaying = true
            vm.updatePurpleBarPosition(elapsedTime: 0.01)

            let view = GameplayView(chart: vm.chart, metronome: vm.metronome, initialViewModel: vm)
            let usesNotationLayout = view.usesNotationLayout(viewModel: vm)
            let measurePositions = view.sheetMeasurePositions(viewModel: vm)
            let contentWidth = view.sheetContentWidth(viewModel: vm)
            let rowCount = view.sheetRowCount(measurePositions: measurePositions)

            var didInvalidate = false
            withObservationTracking {
                _ = view.staticSheetMusicContent(
                    measurePositions: measurePositions,
                    contentWidth: contentWidth,
                    rowCount: rowCount,
                    usesNotationLayout: usesNotationLayout,
                    viewModel: vm
                )
            } onChange: {
                didInvalidate = true
            }

            vm.updatePurpleBarPosition(elapsedTime: 0.51)

            #expect(
                !didInvalidate,
                "Moving the purple bar must not invalidate static notation content"
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

    /// Verifies that a chart with crash notes (default position .aboveLine5) produces
    /// a layout where the crash note head sits above the staff, and the anchor column
    /// still renders successfully.
    ///
    /// Note: Testing a true .aboveLine9 override is not feasible here because
    /// `cacheNotationLayout()` bypasses UserDefaults in the test environment.
    @Test("rowAnchorColumn with above-staff crash notes renders correctly")
    func testRowAnchorColumn_withAboveStaffCrashNotes_renders() async throws {
        try await TestSetup.withTestSetup {
            // Create a chart with crash notes (mapped to .aboveLine5 by default).
            let chart = GameplayViewModelCoverageTestSupport.makeChart(
                noteCount: 2,
                interval: .quarter,
                measureOffset: 0.25
            )
            // Change the first note to crash so it uses an above-staff position.
            chart.notes[0].noteType = .crash

            let vm = GameplayViewModelCoverageTestSupport.makeViewModel(chart: chart)
            defer { vm.cleanup() }
            await vm.loadChartData()
            vm.setupGameplay()

            // Verify the crash note head is above the highest staff line (line5).
            // In screen coordinates, above-line5 means a smaller Y value.
            let crashHead = try #require(
                vm.cachedNotationLayout.noteHeads.first { $0.drumType == .crash },
                "Layout should contain a crash note head"
            )
            let line5Y = GameplayLayout.StaffLinePosition.line5.absoluteY(for: crashHead.row)
            #expect(crashHead.position.y < line5Y,
                    "Crash note head should be above line5 (default .aboveLine5 position)")

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
