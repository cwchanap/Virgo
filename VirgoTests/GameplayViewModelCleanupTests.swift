//
//  GameplayViewModelCleanupTests.swift
//  VirgoTests
//

import Testing
import Foundation
import AVFoundation
import Combine
import Observation
import SwiftUI
@testable import Virgo

@Suite("Cleanup & Reset", .serialized)
@MainActor
struct GameplayViewModelCleanupTests {

    @Test func testCleanup() async throws {
        let chart = GameplayViewModelTestHarness.createTestChart()
        let metronome = GameplayViewModelTestHarness.createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()
        viewModel.setupGameplay()
        viewModel.setupMetronomeSubscription()
        viewModel.startPlayback()

        #expect(viewModel.isGameplayPrepared)
        viewModel.cleanup()

        #expect(!viewModel.isGameplayPrepared)
        #expect(viewModel.playbackTimer == nil)
        #expect(viewModel.bgmPlayer == nil)
        #expect(viewModel.metronomeSubscription == nil)
    }

    @Test func testCleanupIdempotent() async throws {
        let chart = GameplayViewModelTestHarness.createTestChart()
        let metronome = GameplayViewModelTestHarness.createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)

        // Multiple cleanup calls should not crash
        viewModel.cleanup()
        viewModel.cleanup()
        viewModel.cleanup()

        #expect(viewModel.playbackTimer == nil)
    }

    @Test("cleanup() cancels and clears any pending completion task")
    func testCleanupCancelsCompletionTask() async throws {
        // Regression guard for P2: if the user dismisses gameplay during the
        // grace period, cleanup() must cancel the in-flight completionTask so
        // it cannot persist score/high-score state after the screen is gone.
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 4)
        let metronome = GameplayViewModelTestHarness.createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()
        viewModel.setupGameplay()
        viewModel.startPlayback()

        // Inject a sentinel cancellable to simulate the grace-period completion
        // handle being in-flight, and record whether cleanup() cancels it.
        var sentinelCancelled = false
        let sentinel = AnyCancellable { sentinelCancelled = true }
        viewModel.completionTask = sentinel

        viewModel.cleanup()

        #expect(viewModel.completionTask == nil,
                "cleanup() must nil completionTask so the stale task cannot fire")
        #expect(sentinelCancelled,
                "cleanup() must cancel the in-flight completionTask")
    }

    @Test func testPlaybackStateReset() async throws {
        let chart = GameplayViewModelTestHarness.createTestChart()
        let metronome = GameplayViewModelTestHarness.createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()
        viewModel.setupGameplay()

        // Set various state values
        viewModel.currentBeat = 10
        viewModel.playbackProgress = 0.75
        viewModel.totalBeatsElapsed = 20
        viewModel.currentBeatPosition = 0.5
        viewModel.rawBeatPosition = 2.5
        viewModel.currentMeasureIndex = 3

        // Restart should reset all state
        viewModel.restartPlayback()

        #expect(viewModel.currentBeat == 0)
        #expect(viewModel.playbackProgress == 0.0)
        #expect(viewModel.totalBeatsElapsed == 0)
        #expect(viewModel.currentBeatPosition == 0.0)
        #expect(viewModel.rawBeatPosition == 0.0)
        #expect(viewModel.currentMeasureIndex == 0)

        viewModel.cleanup()
    }

    @Test func testCleanupSavesCurrentSpeed() async throws {
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 8)
        let metronome = GameplayViewModelTestHarness.createTestMetronome()

        // Create isolated UserDefaults for this test
        let (userDefaults, _) = TestUserDefaults.makeIsolated()
        let practiceSettings = PracticeSettingsService(userDefaults: userDefaults)

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome, practiceSettings: practiceSettings)
        await viewModel.loadChartData()
        viewModel.setupGameplay()

        // Set speed
        viewModel.updateSpeed(0.75)

        // Wait for trailing-edge debounce timer to fire before cleanup
        try await Task.sleep(nanoseconds: 300_000_000)

        // Cleanup (should save speed)
        viewModel.cleanup()

        // Verify speed was saved by loading it directly
        let loadedSpeed = practiceSettings.loadSpeed(for: chart.persistentModelID)
        #expect(loadedSpeed == 0.75, "Speed should be saved on cleanup")
    }

    @Test func testCleanupDoesNotSaveSpeedWhenDataNotLoaded() async throws {
        // Regression test for race condition where quickly dismissing GameplayView
        // could save the previous chart's shared speed under the current chart's ID
        // before its own persisted speed was loaded.
        //
        // Scenario:
        // 1. User plays Chart A at 1.5x speed
        // 2. User backs out (saves 1.5x for Chart A)
        // 3. User quickly opens Chart B (ViewModel created with sharedSettings at 1.5x)
        // 4. User immediately backs out BEFORE loadChartData/setupGameplay completes
        // 5. Without the fix, cleanup() would save 1.5x for Chart B, corrupting its setting

        let chartA = GameplayViewModelTestHarness.createTestChart(noteCount: 4)
        let chartB = GameplayViewModelTestHarness.createTestChart(noteCount: 4)
        let metronome = GameplayViewModelTestHarness.createTestMetronome()

        // Shared practice settings (simulates the injected environment object)
        let (userDefaults, _) = TestUserDefaults.makeIsolated()
        let sharedSettings = PracticeSettingsService(userDefaults: userDefaults)

        // --- Simulate playing Chart A at 1.5x speed ---
        let vmA = GameplayViewModel(chart: chartA, metronome: metronome, practiceSettings: sharedSettings)
        await vmA.loadChartData()
        vmA.setupGameplay()
        vmA.updateSpeed(1.5)
        // Wait for trailing-edge debounce timer to fire
        try await Task.sleep(nanoseconds: 300_000_000)
        vmA.cleanup()  // Saves 1.5x for Chart A

        #expect(sharedSettings.speedMultiplier == 1.5, "Shared settings should retain last used speed")
        #expect(sharedSettings.loadSpeed(for: chartA.persistentModelID) == 1.5, "Chart A should have 1.5x saved")

        // --- Simulate quickly opening and closing Chart B before setup completes ---
        // Create ViewModel for Chart B (inherits 1.5x from shared settings)
        let vmB = GameplayViewModel(chart: chartB, metronome: metronome, practiceSettings: sharedSettings)

        // NOTE: We intentionally do NOT call loadChartData/setupGameplay
        // This simulates the user dismissing the view before async setup completes
        #expect(vmB.isDataLoaded == false, "Data should not be loaded in this scenario")

        // Pre-set Chart B's saved speed to 0.75x (its intended default)
        sharedSettings.saveSpeed(0.75, for: chartB.persistentModelID)
        // Reset shared speed to simulate fresh state
        sharedSettings.setSpeed(1.0)
        // But vmB still has the stale 1.5x from when it was created
        #expect(vmB.practiceSettings.speedMultiplier == 1.0, "Practice settings speed should be reset")

        // Cleanup without data loaded - should NOT save anything
        vmB.cleanup()

        // Verify Chart B's saved speed was NOT corrupted
        let chartBSpeed = sharedSettings.loadSpeed(for: chartB.persistentModelID)
        #expect(chartBSpeed == 0.75, "Chart B's saved speed should not be corrupted by early cleanup")
    }

    @Test func testCleanupDoesNotSaveSpeedWhenPersistedSpeedNotLoaded() async throws {
        // Regression test for race condition where quickly dismissing GameplayView
        // after loadChartData() but before setupGameplay() could save the default
        // speed (1.0) under the current chart's ID, overwriting its persisted speed.
        //
        // Scenario (Bug P1):
        // 1. Chart B has persisted speed of 0.75x saved
        // 2. User opens Chart B
        // 3. GameplayView.task calls resetSpeed() → speed becomes 1.0 (default)
        // 4. GameplayView.task calls loadChartData() → isDataLoaded = true
        // 5. User quickly dismisses view BEFORE setupGameplay() loads persisted speed
        // 6. cleanup() is called with isDataLoaded=true but speed still at 1.0
        // 7. Without the fix, cleanup() would save 1.0 for Chart B, corrupting 0.75x

        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 4)
        let metronome = GameplayViewModelTestHarness.createTestMetronome()

        // Isolated UserDefaults for this test
        let (userDefaults, _) = TestUserDefaults.makeIsolated()
        let practiceSettings = PracticeSettingsService(userDefaults: userDefaults)

        // Pre-set chart's saved speed to 0.75x
        practiceSettings.saveSpeed(0.75, for: chart.persistentModelID)
        #expect(practiceSettings.loadSpeed(for: chart.persistentModelID) == 0.75, "Chart should have 0.75x pre-saved")

        // Simulate GameplayView.task flow up to loadChartData:
        // 1. Reset speed to default (as GameplayView.task does)
        practiceSettings.resetSpeed()
        #expect(practiceSettings.speedMultiplier == 1.0, "Speed should be reset to default 1.0")

        // 2. Create ViewModel and load chart data (but NOT setupGameplay)
        let viewModel = GameplayViewModel(chart: chart, metronome: metronome, practiceSettings: practiceSettings)
        await viewModel.loadChartData()
        #expect(viewModel.isDataLoaded == true, "Data should be loaded")
        // NOTE: We intentionally do NOT call setupGameplay() - this simulates
        // the user dismissing the view right after loadChartData() but before
        // setupGameplay() had a chance to load the persisted speed

        // At this point, speed is still 1.0 (default), not the chart's 0.75x
        #expect(practiceSettings.speedMultiplier == 1.0, "Speed should still be default 1.0")

        // Cleanup - should NOT save the default speed since persisted speed was never loaded
        viewModel.cleanup()

        // Verify chart's saved speed was NOT corrupted with the default 1.0
        let savedSpeed = practiceSettings.loadSpeed(for: chart.persistentModelID)
        #expect(savedSpeed == 0.75, "Chart's saved speed should NOT be overwritten with default 1.0")
    }

    @Test func testResetPlaybackStateClearsScheduledStartTime() async {
        // Verify that resetPlaybackState clears the scheduled playback start time
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 8)
        let metronome = GameplayViewModelTestHarness.createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()
        viewModel.setupGameplay()

        viewModel.startPlayback()
        #expect(viewModel.lastScheduledPlaybackStartTime != nil,
                "Scheduled time should be set after startPlayback")

        viewModel.pausePlayback()
        // After pause and reset (via restartPlayback), scheduled time should be nil
        viewModel.restartPlayback()
        #expect(
            viewModel.lastScheduledPlaybackStartTime == nil,
            "restartPlayback should clear lastScheduledPlaybackStartTime via resetPlaybackState"
        )
        // restartPlayback calls resetPlaybackState which clears lastScheduledPlaybackStartTime,
        // but then startPlayback sets it again if isPlaying. Since restartPlayback only calls
        // startPlayback when isPlaying==true, verify the reset happened.
        // Let's test via resetPlaybackState directly via a full cycle:
        viewModel.pausePlayback()
        viewModel.restartPlayback() // This resets state and starts fresh if isPlaying

        viewModel.cleanup()
    }
}
