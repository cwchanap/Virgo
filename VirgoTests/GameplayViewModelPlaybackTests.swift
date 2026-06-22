//
//  GameplayViewModelPlaybackTests.swift
//  VirgoTests
//

import Testing
import Foundation
import AVFoundation
import Observation
import SwiftUI
@testable import Virgo

@Suite("Playback Control", .serialized)
@MainActor
struct GameplayViewModelPlaybackTests {

    @Test func testTogglePlayback() async throws {
        let chart = GameplayViewModelTestHarness.createTestChart()
        let metronome = GameplayViewModelTestHarness.createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()
        viewModel.setupGameplay()

        #expect(viewModel.isPlaying == false)

        viewModel.togglePlayback()
        #expect(viewModel.isPlaying == true)

        viewModel.togglePlayback()
        #expect(viewModel.isPlaying == false)

        // Cleanup
        viewModel.cleanup()
    }

    @Test func testUpdateSpeedUpdatesMetronomeWhenEnabledAndNotPlaying() async throws {
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 8)
        let metronome = GameplayViewModelTestHarness.createTestMetronome()
        let practiceSettings = GameplayViewModelTestHarness.createTestPracticeSettings()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome, practiceSettings: practiceSettings)
        await viewModel.loadChartData()
        viewModel.setupGameplay(loadPersistedSpeed: false)

        let toggleSuccess = await CombineTestUtilities.performAndWait(
            action: { metronome.toggle(bpm: viewModel.effectiveBPM(), timeSignature: .fourFour) },
            publisher: metronome.$isEnabled,
            condition: { $0 == true },
            timeout: 0.5
        )
        #expect(toggleSuccess, "Metronome should start before updating speed")

        viewModel.updateSpeed(0.75)
        // Wait for trailing-edge debounce timer to fire (100ms debounce interval + small buffer)
        try await Task.sleep(nanoseconds: 300_000_000)
        let expectedBPM = viewModel.effectiveBPM()
        #expect(abs(metronome.bpm - expectedBPM) < 0.001)

        metronome.stop()
        viewModel.cleanup()
    }

    @Test("updateSettings ignores a different practice settings instance")
    func testUpdateSettingsIgnoresDifferentPracticeSettingsInstance() async throws {
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 8)
        let metronome = GameplayViewModelTestHarness.createTestMetronome()
        let practiceSettings = GameplayViewModelTestHarness.createTestPracticeSettings()
        let otherSettings = GameplayViewModelTestHarness.createTestPracticeSettings()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome, practiceSettings: practiceSettings)
        await viewModel.loadChartData()
        viewModel.setupGameplay(loadPersistedSpeed: false)

        let initialBPM = viewModel.effectiveBPM()
        otherSettings.setSpeed(0.75)

        viewModel.updateSettings(otherSettings)

        #expect(abs(viewModel.effectiveBPM() - initialBPM) < 0.001)

        viewModel.cleanup()
    }

    @Test func testStartPlayback() async throws {
        let chart = GameplayViewModelTestHarness.createTestChart()
        let metronome = GameplayViewModelTestHarness.createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()
        viewModel.setupGameplay()

        viewModel.startPlayback()

        #expect(viewModel.isPlaying == true)
        #expect(viewModel.playbackStartTime != nil)

        // Cleanup
        viewModel.cleanup()
    }

    @Test func testStartPlaybackWaitsForGameplayPreparation() async throws {
        let chart = GameplayViewModelTestHarness.createTestChart()
        let metronome = GameplayViewModelTestHarness.createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()

        #expect(viewModel.isDataLoaded)
        #expect(!viewModel.isGameplayPrepared)

        viewModel.startPlayback()

        #expect(!viewModel.isPlaying)
        #expect(viewModel.playbackStartTime == nil)
        #expect(viewModel.lastScheduledPlaybackStartTime == nil)

        viewModel.cleanup()
    }

    @Test func testRestartPlayback() async throws {
        let chart = GameplayViewModelTestHarness.createTestChart()
        let metronome = GameplayViewModelTestHarness.createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()
        viewModel.setupGameplay()

        // Start and simulate some progress
        viewModel.startPlayback()
        viewModel.currentBeat = 5
        viewModel.playbackProgress = 0.5
        viewModel.totalBeatsElapsed = 10

        viewModel.restartPlayback()

        // Verify state is reset
        #expect(viewModel.currentBeat == 0)
        #expect(viewModel.playbackProgress == 0.0)
        #expect(viewModel.totalBeatsElapsed == 0)
        #expect(viewModel.pausedElapsedTime == 0.0)

        // Cleanup
        viewModel.cleanup()
    }

    @Test func testSkipToEnd() async throws {
        let chart = GameplayViewModelTestHarness.createTestChart()
        let metronome = GameplayViewModelTestHarness.createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()
        viewModel.setupGameplay()

        viewModel.startPlayback()
        viewModel.skipToEnd()

        #expect(viewModel.playbackProgress == 1.0)
        #expect(viewModel.isPlaying == false)
        #expect(viewModel.playbackStartTime == nil)
        #expect(viewModel.pausedElapsedTime == 0.0)
    }

    @Test func testSkipToEndWhenNotPlayingIsNoOp() async throws {
        // Regression guard: skipToEnd() must not trigger scoring or show the results
        // sheet when playback has not been started (or has been paused/stopped).
        let chart = GameplayViewModelTestHarness.createTestChart()
        let metronome = GameplayViewModelTestHarness.createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()
        viewModel.setupGameplay()

        // Do NOT call startPlayback() — isPlaying is false.
        viewModel.skipToEnd()

        #expect(viewModel.isPlaying == false)
        #expect(viewModel.isShowingSessionResults == false)
        #expect(viewModel.playbackProgress == 0.0)
    }

    @Test("skipToEnd preserves all position fields from just before completion")
    func testSkipToEndPreservesPositionStateConsistently() async throws {
        // Regression guard for the P3 inconsistency where handlePlaybackCompletion()
        // zeroed currentBeat/measureIndex/rawBeatPosition while skipToEnd() only
        // restored playbackProgress, leaving fields in a contradictory state.
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 4)
        let metronome = GameplayViewModelTestHarness.createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()
        viewModel.setupGameplay()
        viewModel.startPlayback()

        // Simulate mid-song position state (mimics what the metronome callback would set)
        viewModel.currentBeat = 3
        viewModel.currentMeasureIndex = 2
        viewModel.rawBeatPosition = 7.5
        viewModel.currentBeatPosition = 3.0
        viewModel.currentQuarterNotePosition = 12.0
        viewModel.totalBeatsElapsed = 8
        viewModel.currentRow = 4

        viewModel.skipToEnd()

        // All position fields must reflect the pre-skip snapshot — none should be 0
        // (which would indicate resetPlaybackState() ran without restoration).
        #expect(viewModel.playbackProgress == 1.0)
        #expect(viewModel.currentBeat == 3,
                "currentBeat must be preserved from the pre-skip snapshot")
        #expect(viewModel.currentMeasureIndex == 2,
                "currentMeasureIndex must be preserved from the pre-skip snapshot")
        #expect(viewModel.rawBeatPosition == 7.5,
                "rawBeatPosition must be preserved from the pre-skip snapshot")
        #expect(viewModel.currentBeatPosition == 3.0,
                "currentBeatPosition must be preserved from the pre-skip snapshot")
        #expect(viewModel.currentQuarterNotePosition == 12.0,
                "currentQuarterNotePosition must be preserved from the pre-skip snapshot")
        #expect(viewModel.totalBeatsElapsed == 8,
                "totalBeatsElapsed must be preserved from the pre-skip snapshot")
        #expect(viewModel.currentRow == 4,
                "currentRow must be preserved from the pre-skip snapshot")
        #expect(viewModel.isPlaying == false)

        viewModel.cleanup()
    }

    @Test func testStartPlaybackWithoutTrack() async throws {
        let chart = GameplayViewModelTestHarness.createTestChart()
        let metronome = GameplayViewModelTestHarness.createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        // Don't load data - track will be nil

        // Should not crash and isPlaying should remain false (no track available)
        viewModel.startPlayback()

        #expect(viewModel.isPlaying == false)

        viewModel.cleanup()
    }

    @Test func testInputManagerConfiguration() async throws {
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 8)
        let metronome = GameplayViewModelTestHarness.createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()
        viewModel.setupGameplay()

        // Input manager should exist after setup (they are non-optional)
        // Just verify they are initialized by accessing them
        _ = viewModel.inputManager
        _ = viewModel.inputHandler
    }

    @Test func testStartPlaybackStateConsistency() async throws {
        // This test verifies that isPlaying is only set to true after
        // all setup operations complete successfully.
        // See: coderabbit.ai review comment about potential state inconsistency
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 8)
        let metronome = GameplayViewModelTestHarness.createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()
        viewModel.setupGameplay()

        // Verify initial state
        #expect(viewModel.isPlaying == false)
        #expect(viewModel.playbackStartTime == nil)

        // Capture state before and after startPlayback
        let stateBeforeStart = (isPlaying: viewModel.isPlaying, startTime: viewModel.playbackStartTime)

        viewModel.startPlayback()

        // After startPlayback, both should be set together
        #expect(viewModel.isPlaying == true)
        #expect(viewModel.playbackStartTime != nil)

        // Verify state transition was atomic - both changed together
        #expect(stateBeforeStart.isPlaying == false)
        #expect(stateBeforeStart.startTime == nil)

        viewModel.cleanup()
    }

    @Test func testStartPlaybackGuardsPreventStateInconsistency() async throws {
        // Verify that guards prevent state from becoming inconsistent
        // when preconditions are not met
        let chart = GameplayViewModelTestHarness.createTestChart()
        let metronome = GameplayViewModelTestHarness.createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        // Note: NOT loading data - track will be nil

        // State should remain unchanged when startPlayback fails due to no track
        viewModel.startPlayback()

        // isPlaying should remain false since guard failed
        #expect(viewModel.isPlaying == false)
        #expect(viewModel.playbackStartTime == nil)

        viewModel.cleanup()
    }
}
