//
//  GameplayViewModelInitializationTests.swift
//  VirgoTests
//

import Testing
import Foundation
import AVFoundation
import Observation
import SwiftUI
@testable import Virgo

@Suite("Initialization & Initial State", .serialized)
@MainActor
struct GameplayViewModelInitializationTests {

    @Test func testInitialization() async throws {
        let chart = GameplayViewModelTestHarness.createTestChart()
        let metronome = GameplayViewModelTestHarness.createTestMetronome()
        let practiceSettings = GameplayViewModelTestHarness.createTestPracticeSettings()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome, practiceSettings: practiceSettings)

        #expect(viewModel.chart === chart)
        #expect(viewModel.metronome === metronome)
        #expect(viewModel.isPlaying == false)
        #expect(viewModel.playbackProgress == 0.0)
        #expect(viewModel.currentBeat == 0)
        #expect(viewModel.isDataLoaded == false)
    }

    @Test func testInitialStateIsCorrect() async throws {
        let chart = GameplayViewModelTestHarness.createTestChart()
        let metronome = GameplayViewModelTestHarness.createTestMetronome()
        let practiceSettings = GameplayViewModelTestHarness.createTestPracticeSettings()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome, practiceSettings: practiceSettings)

        // Verify all initial state values
        #expect(viewModel.cachedSong == nil)
        #expect(viewModel.cachedNotes.isEmpty)
        #expect(viewModel.track == nil)
        #expect(viewModel.cachedDrumBeats.isEmpty)
        #expect(viewModel.cachedMeasurePositions.isEmpty)
        #expect(viewModel.purpleBarPosition == nil)
        #expect(viewModel.bgmPlayer == nil)
    }
}
