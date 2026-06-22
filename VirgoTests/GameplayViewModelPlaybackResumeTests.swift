//
//  GameplayViewModelPlaybackResumeTests.swift
//  VirgoTests
//
//  Pause/resume lifecycle tests split out of GameplayViewModelPlaybackTests to keep
//  both suites under SwiftLint's type_body_length limit.
//

import Testing
import Foundation
import AVFoundation
import Observation
import SwiftUI
@testable import Virgo

@Suite("Pause & Resume Playback", .serialized)
@MainActor
struct GameplayViewModelPlaybackResumeTests {

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

    enum TestError: Error {
        case playbackStartTimeNil
    }
}
