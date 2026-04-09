//
//  GameplayRenderCoverageTests.swift
//  VirgoTests
//
//  Render-path coverage for GameplayView's two principal visual branches:
//  1. Loading state (viewModel == nil) — exercised on first layout pass.
//  2. Populated state (viewModel != nil) — exercised via the injection seam.
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
            let settings = GameplayViewModelCoverageTestSupport.makeSettings()

            // Verify the view model was fully prepared before mounting.
            #expect(vm.isDataLoaded, "makePreparedViewModel must call loadChartData()")
            #expect(!vm.cachedDrumBeats.isEmpty, "makePreparedViewModel must populate cachedDrumBeats via setupGameplay()")
            #expect(vm.staticStaffLinesView != nil, "makePreparedViewModel must build staticStaffLinesView via setupGameplay()")

            let view = GameplayView(chart: vm.chart, metronome: vm.metronome, initialViewModel: vm)
                .environmentObject(settings)

            // Mounting with a non-nil viewModel exercises the populated notation branch.
            SwiftUITestUtilities.assertViewWithEnvironment(
                view,
                size: CGSize(width: 1280, height: 900)
            )
        }
    }
}
