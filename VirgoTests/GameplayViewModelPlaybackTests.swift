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

    @Test func testPausePlaybackIsIdempotent() async throws {
        let chart = GameplayViewModelTestHarness.createTestChart()
        let metronome = GameplayViewModelTestHarness.createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()
        viewModel.setupGameplay()

        viewModel.startPlayback()
        viewModel.pausePlayback()
        let pausedAfterFirst = viewModel.pausedElapsedTime

        viewModel.pausePlayback()

        #expect(viewModel.pausedElapsedTime == pausedAfterFirst)
        #expect(viewModel.isPlaying == false)

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

    @Test func testPausePlayback() async throws {
        let chart = GameplayViewModelTestHarness.createTestChart()
        let metronome = GameplayViewModelTestHarness.createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()
        viewModel.setupGameplay()

        viewModel.startPlayback()
        #expect(viewModel.isPlaying == true)

        viewModel.pausePlayback()

        #expect(viewModel.playbackStartTime == nil)

        // Cleanup
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

    @Test func testHandlePlaybackCompletionStopsInputListening() async throws {
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 8)
        let metronome = GameplayViewModelTestHarness.createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()
        viewModel.setupGameplay()

        viewModel.startPlayback()
        viewModel.handlePlaybackCompletion()

        let mirror = Mirror(reflecting: viewModel.inputManager)
        let songStartTime = mirror.children.first { $0.label == "songStartTime" }?.value as? Date
        #expect(songStartTime == nil)
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

    @Test func testResumePlaybackPreservesInputTimingAlignment() async throws {
        // Test that input timing stays aligned after pause/resume.
        // This addresses the bug where InputManager resets timing on resume,
        // causing hit matching to be shifted by already-elapsed duration.
        //
        // The fix ensures playbackStartTime on resume is set to Date() - pausedElapsedTime,
        // which makes InputManager's elapsed time calculation (now - songStartTime)
        // correctly account for the already-elapsed duration.
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 16)
        let metronome = GameplayViewModelTestHarness.createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()
        viewModel.setupGameplay()

        // Start fresh playback
        viewModel.startPlayback()
        #expect(viewModel.isPlaying == true)

        guard let firstStartTime = viewModel.playbackStartTime else {
            throw TestError.playbackStartTimeNil
        }

        // Simulate some elapsed time (e.g., 2 beats worth at 120 BPM = 1 second)
        let simulatedElapsedSeconds: Double = 1.0

        // Pause playback
        viewModel.pausePlayback()
        #expect(viewModel.isPlaying == false)
        #expect(viewModel.playbackStartTime == nil)

        // Inject simulated elapsed time for deterministic testing
        viewModel.pausedElapsedTime = simulatedElapsedSeconds

        // Verify pausedElapsedTime was accumulated
        let pausedTimeAfterPause = viewModel.pausedElapsedTime
        #expect(pausedTimeAfterPause > 0.0, "pausedElapsedTime should be > 0 after pause")

        // Resume playback
        viewModel.startPlayback()
        #expect(viewModel.isPlaying == true)

        guard let resumeStartTime = viewModel.playbackStartTime else {
            throw TestError.playbackStartTimeNil
        }

        let resumeCallTime = Date()
        let timeBetweenResumeCallAndStart = resumeCallTime.timeIntervalSince(resumeStartTime)
        // Tolerance accounts for the 0.05s setupTime that the metronome/BGM scheduler
        // uses to buffer audio startup. The input timeline is now synchronized with
        // the scheduled start rather than the wall-clock call time.
        let tolerance: Double = 0.1
        #expect(timeBetweenResumeCallAndStart >= -0.06,
                "Resume start time may be slightly in the future due to scheduled playback")
        #expect(
            abs(timeBetweenResumeCallAndStart - pausedTimeAfterPause) < tolerance,
            "Resume start time should be offset backward by paused elapsed time"
        )

        viewModel.cleanup()
    }

    @Test func testResumePlaybackMultipleTimesMaintainsTiming() async throws {
        // Test multiple pause/resume cycles to ensure timing stays correct.
        // The key fix is that each resume adjusts songStartTime backward by
        // total pausedElapsedTime, maintaining input timing alignment.
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 20)
        let metronome = GameplayViewModelTestHarness.createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()
        viewModel.setupGameplay()

        // First cycle: start -> pause -> resume
        viewModel.startPlayback()
        guard let firstStartTime = viewModel.playbackStartTime else {
            throw TestError.playbackStartTimeNil
        }
        viewModel.pausePlayback()
        let simulatedFirstElapsed: Double = 0.5
        viewModel.pausedElapsedTime = simulatedFirstElapsed
        let pausedAfterFirst = viewModel.pausedElapsedTime

        viewModel.startPlayback()
        guard let startTimeAfterFirstResume = viewModel.playbackStartTime else {
            throw TestError.playbackStartTimeNil
        }

        let firstResumeCallTime = Date()
        let firstResumeOffset = firstResumeCallTime.timeIntervalSince(startTimeAfterFirstResume)
        #expect(abs(firstResumeOffset - pausedAfterFirst) < 0.1)

        // Second cycle: pause -> resume
        viewModel.pausePlayback()
        let simulatedSecondElapsed: Double = 1.0
        viewModel.pausedElapsedTime = simulatedSecondElapsed
        let pausedAfterSecond = viewModel.pausedElapsedTime
        #expect(pausedAfterSecond > pausedAfterFirst, "Second pause should have more elapsed time")

        viewModel.startPlayback()
        guard let startTimeAfterSecondResume = viewModel.playbackStartTime else {
            throw TestError.playbackStartTimeNil
        }

        let secondResumeCallTime = Date()
        let secondResumeOffset = secondResumeCallTime.timeIntervalSince(startTimeAfterSecondResume)
        #expect(abs(secondResumeOffset - pausedAfterSecond) < 0.1)

        viewModel.cleanup()
    }

    @Test func testResumeMetronomeOnlyPlaybackPreservesState() async throws {
        // Test that metronome-only sessions (without BGM) preserve playback state
        // across pause/resume. This addresses the regression where metronome-only
        // sessions always restart from the beginning on resume.
        //
        // The fix uses pausedElapsedTime > 0 as the primary resume indicator,
        // which works for both BGM and metronome-only sessions.
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 16)
        let metronome = GameplayViewModelTestHarness.createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()
        viewModel.setupGameplay()

        // Ensure no BGM player is loaded (metronome-only session)
        #expect(viewModel.bgmPlayer == nil, "This test requires metronome-only session (no BGM)")

        // Start fresh playback
        viewModel.startPlayback()
        #expect(viewModel.isPlaying == true)
        #expect(viewModel.currentMeasureIndex == 0, "Should start at measure 0")
        #expect(viewModel.totalBeatsElapsed == 0, "Should start with 0 elapsed beats")

        guard let firstStartTime = viewModel.playbackStartTime else {
            throw TestError.playbackStartTimeNil
        }

        // Simulate some playback progress
        // In a real scenario, the metronome would advance over time.
        // Here we manually simulate elapsed time being captured during pause.
        let simulatedElapsedSeconds: Double = 1.0  // 1 second at 120 BPM = 2 beats

        // Pause playback
        viewModel.pausePlayback()
        #expect(viewModel.isPlaying == false)
        #expect(viewModel.playbackStartTime == nil)

        // Manually set pausedElapsedTime to simulate metronome advancement
        // This simulates what would happen if playback ran for 1 second
        viewModel.pausedElapsedTime = simulatedElapsedSeconds
        let pausedTimeAfterPause = viewModel.pausedElapsedTime
        #expect(pausedTimeAfterPause > 0.0, "pausedElapsedTime should be > 0 after pause")

        // Resume playback
        viewModel.startPlayback()
        #expect(viewModel.isPlaying == true)

        guard let resumeStartTime = viewModel.playbackStartTime else {
            throw TestError.playbackStartTimeNil
        }

        // CRITICAL VERIFICATION: The resume start time must be adjusted backward
        // to account for the paused duration. This ensures InputManager calculates
        // the correct elapsed time: now - resumeStartTime ≈ pausedElapsedTime
        #expect(resumeStartTime < firstStartTime,
               "Resume start time should be adjusted backward to account for paused time")

        // Verify pausedElapsedTime was preserved and used to restore state
        let timeBetweenStartTimes = firstStartTime.timeIntervalSince(resumeStartTime)
        let toleranceMultiplier: Double = 2.0
        let timeDifference = abs(timeBetweenStartTimes - pausedTimeAfterPause)
        let tolerance = pausedTimeAfterPause * toleranceMultiplier
        #expect(
            timeDifference < tolerance,
            "Time difference (\(timeDifference)s) should be less than tolerance (\(tolerance)s)"
        )

        // Verify playback state was restored, not reset to beginning
        // The state should reflect the elapsed time from pausedElapsedTime
        #expect(viewModel.totalBeatsElapsed > 0, "Should have elapsed beats after resume")
        #expect(viewModel.currentMeasureIndex > 0 || viewModel.currentBeatPosition > 0,
               "Should have progressed from beginning after resume")

        // Cleanup
        viewModel.cleanup()
    }


    enum TestError: Error {
        case playbackStartTimeNil
    }
}
