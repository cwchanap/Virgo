//
//  GameplayRenderCoverageTests.swift
//  VirgoTests
//
//  Render-path coverage for GameplayView's principal visual branches:
//  1. Loading state (viewModel == nil) — exercised on first layout pass.
//  2. Populated state (viewModel != nil) — exercised via the injection seam.
//  3. Sub-view branches: StaffLinesBackgroundView, BeamView/BeamGroupView,
//     controlsView placeholder/loaded, DrumClefSymbol, TimeSignatureSymbol.
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
    /// which exercises the loading-state branch in `sheetMusicView`.
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
    /// The view renders the populated notation branch from the very first layout pass.
    @Test("GameplayView mounts in populated state when a prepared viewModel is injected")
    func testGameplayView_withPreparedViewModel_rendersPopulatedState() async throws {
        try await TestSetup.withTestSetup {
            let vm = await GameplayViewModelCoverageTestSupport.makePreparedViewModel()

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
            #expect(vm.staticStaffLinesView == nil, "Fixture must clear staticStaffLinesView")

            let view = GameplayView(chart: vm.chart, metronome: vm.metronome, initialViewModel: vm)
                .environmentObject(vm.practiceSettings)

            SwiftUITestUtilities.assertViewWithEnvironment(
                view,
                size: CGSize(width: 1280, height: 900)
            )
        }
    }

    // MARK: - controlsView branches

    /// Mounts `GameplayView` without a viewModel, causing `controlsView` to show the
    /// placeholder `Color.black.frame(height: 100)` branch.
    @Test("GameplayView controlsView shows placeholder when viewModel is nil")
    func testGameplayView_controlsPlaceholder_rendersWhenNoViewModel() async throws {
        try await TestSetup.withTestSetup {
            let chart = GameplayViewModelCoverageTestSupport.makeChart()
            let metronome = GameplayViewModelCoverageTestSupport.makeMetronome()
            let settings = GameplayViewModelCoverageTestSupport.makeSettings()

            let view = GameplayView(chart: chart, metronome: metronome)
                .environmentObject(settings)

            SwiftUITestUtilities.assertViewWithEnvironment(
                view,
                size: CGSize(width: 1280, height: 900)
            )
        }
    }

    /// Mounts `GameplayView` with a populated viewModel, causing `controlsView` to render
    /// the full `GameplayControlsView` branch.
    @Test("GameplayView controlsView shows loaded controls when viewModel is populated")
    func testGameplayView_controlsLoaded_rendersWhenViewModelPresent() async throws {
        try await TestSetup.withTestSetup {
            let vm = await GameplayViewModelCoverageTestSupport.makePreparedViewModel()

            let view = GameplayView(chart: vm.chart, metronome: vm.metronome, initialViewModel: vm)
                .environmentObject(vm.practiceSettings)

            SwiftUITestUtilities.assertViewWithEnvironment(
                view,
                size: CGSize(width: 1280, height: 900)
            )
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

    // MARK: - BeamGroupView

    /// Renders a `BeamGroupView` whose `beats` are eighth notes in the same measure.
    /// The `body` iterates `beamCount` times and builds a child `BeamView` for each.
    @Test("BeamGroupView renders its BeamView children for an eighth-note group")
    func testBeamGroupView_renders() async throws {
        try await TestSetup.withTestSetup {
            let beats = [
                DrumBeat(id: 0, drums: [.kick],  timePosition: 0.0,  interval: .eighth),
                DrumBeat(id: 1, drums: [.snare], timePosition: 0.25, interval: .eighth)
            ]
            let beamGroup = BeamGroup(id: "bg1", beats: beats)
            let positions = GameplayLayout.calculateMeasurePositions(
                totalMeasures: 1, timeSignature: .fourFour
            )

            let view = BeamGroupView(
                beamGroup: beamGroup,
                measurePositions: positions,
                timeSignature: .fourFour,
                isActive: false
            )
            SwiftUITestUtilities.assertViewWithEnvironment(
                view,
                size: CGSize(width: 1280, height: 900)
            )
        }
    }

    // MARK: - BeamView branches

    /// Two eighth-note beats in measure 0 (same row) → `beamedBeats.count >= 2` and
    /// `firstMeasurePos.row == lastMeasurePos.row` → the `Path` rendering branch executes.
    @Test("BeamView renders a beam line when two beats share the same row")
    func testBeamView_sameRow_renders() async throws {
        try await TestSetup.withTestSetup {
            let beats = [
                DrumBeat(id: 0, drums: [.kick],  timePosition: 0.0,  interval: .eighth),
                DrumBeat(id: 1, drums: [.snare], timePosition: 0.25, interval: .eighth)
            ]
            let positions = GameplayLayout.calculateMeasurePositions(
                totalMeasures: 1, timeSignature: .fourFour
            )
            #expect(positions[0].row == 0, "Single-measure fixture must be in row 0")

            let view = BeamView(
                beats: beats,
                beamLevel: 0,
                measurePositions: positions,
                timeSignature: .fourFour,
                isActive: false
            )
            SwiftUITestUtilities.assertViewWithEnvironment(
                view,
                size: CGSize(width: 1280, height: 900)
            )
        }
    }

    /// `beamLevel = 1` with eighth notes (flagCount = 1): `1 > 1` is false for every beat,
    /// so `beamedBeats` is empty → the `count < 2` guard fires → `EmptyView()` branch.
    @Test("BeamView renders EmptyView when fewer than two beats pass the beamLevel filter")
    func testBeamView_fewerThanTwoBeats_doesNotRender() async throws {
        try await TestSetup.withTestSetup {
            let beats = [
                DrumBeat(id: 0, drums: [.kick],  timePosition: 0.0,  interval: .eighth),
                DrumBeat(id: 1, drums: [.snare], timePosition: 0.25, interval: .eighth)
            ]
            let positions = GameplayLayout.calculateMeasurePositions(
                totalMeasures: 1, timeSignature: .fourFour
            )
            // beamLevel 1 requires flagCount > 1; eighth notes have flagCount == 1, so none pass.
            let view = BeamView(
                beats: beats,
                beamLevel: 1,
                measurePositions: positions,
                timeSignature: .fourFour,
                isActive: false
            )
            SwiftUITestUtilities.assertViewWithEnvironment(
                view,
                size: CGSize(width: 1280, height: 900)
            )
        }
    }

    /// Measures 2 and 3 are in different rows when `totalMeasures == 4`.
    /// `firstMeasurePos.row != lastMeasurePos.row` → the row-mismatch `EmptyView()` branch.
    @Test("BeamView renders EmptyView when beats span different rows")
    func testBeamView_rowMismatch_doesNotRender() async throws {
        try await TestSetup.withTestSetup {
            // 4 four-four measures: measures 0-2 row 0, measure 3 row 1.
            let positions = GameplayLayout.calculateMeasurePositions(
                totalMeasures: 4, timeSignature: .fourFour
            )
            let rowsPresent = Set(positions.map { $0.row })
            #expect(rowsPresent.contains(0) && rowsPresent.contains(1),
                    "Fixture must span two rows for the row-mismatch branch")

            // timePosition 2.0 → measureIndex 2 (row 0); 3.0 → measureIndex 3 (row 1).
            let beatRow0 = DrumBeat(id: 0, drums: [.kick],  timePosition: 2.0, interval: .eighth)
            let beatRow1 = DrumBeat(id: 1, drums: [.snare], timePosition: 3.0, interval: .eighth)

            let view = BeamView(
                beats: [beatRow0, beatRow1],
                beamLevel: 0,
                measurePositions: positions,
                timeSignature: .fourFour,
                isActive: false
            )
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
}
