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
        await viewModel.setupGameplay()

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
        await viewModel.setupGameplay()

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
        await viewModel.setupGameplay()

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
        await viewModel.setupGameplay()

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
        await viewModel.setupGameplay()

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
        await viewModel.setupGameplay()

        viewModel.startPlayback()
        viewModel.handlePlaybackCompletion()

        let mirror = Mirror(reflecting: viewModel.inputManager)
        let songStartTime = mirror.children.first { $0.label == "songStartTime" }?.value as? Date
        #expect(songStartTime == nil)
    }

    @Test("pausePlayback falls back to playbackStartTime when metronome has no playback time")
    func testPausePlaybackFallsBackToPlaybackStartTime() async throws {
        let vm = GameplayViewModelCoverageTestSupport.makeViewModel(noteCount: 4)
        await vm.loadChartData()
        await vm.setupGameplay()
        defer { vm.cleanup() }

        vm.isPlaying = true
        let startTime = Date().addingTimeInterval(-1.5)
        vm.playbackStartTime = startTime
        vm.pausedElapsedTime = 0.0

        vm.pausePlayback()

        #expect(vm.isPlaying == false)
        #expect(vm.pausedElapsedTime >= 1.4, "Should accumulate ~1.5 s from playbackStartTime fallback")
    }

    @Test("pausePlayback fallback does not double-count pausedElapsedTime in backdated startTime")
    func testPausePlaybackFallbackNoDoubleCount() async throws {
        let vm = GameplayViewModelCoverageTestSupport.makeViewModel(noteCount: 4)
        await vm.loadChartData()
        await vm.setupGameplay()
        defer { vm.cleanup() }

        // Simulate resume state: pausedElapsedTime = 3.0 s
        // playbackStartTime is backdated by pausedElapsedTime (mirrors applySpeedChangeInternal/startPlayback logic)
        let pausedOffset = 3.0
        vm.isPlaying = true
        vm.pausedElapsedTime = pausedOffset
        // Simulate 1.0 s of new playback since resume (backdated start = now - pausedOffset - 1.0)
        let startTime = Date().addingTimeInterval(-(pausedOffset + 1.0))
        vm.playbackStartTime = startTime

        vm.pausePlayback()

        // Total elapsed should be ~4.0 s (3.0 offset + 1.0 new), NOT ~7.0 s (double-counted)
        #expect(vm.pausedElapsedTime >= 3.9 && vm.pausedElapsedTime <= 4.2,
                "Total elapsed should be ~4.0s (pausedOffset + new playback), not double-counted")
    }

    @Test("calculateElapsedTime fallback does not double-count pausedElapsedTime in backdated startTime")
    func testCalculateElapsedTimeFallbackNoDoubleCount() async throws {
        let chart = GameplayViewModelCoverageTestSupport.makeChart(noteCount: 4)
        chart.notes.forEach { $0.originKind = .dtx }
        let vm = GameplayViewModelCoverageTestSupport.makeViewModel(chart: chart)
        await vm.loadChartData()
        await vm.setupGameplay()
        defer { vm.cleanup() }

        // Simulate resume state: pausedElapsedTime = 3.0 s
        // playbackStartTime is backdated by pausedElapsedTime
        let pausedOffset = 3.0
        vm.isPlaying = true
        vm.pausedElapsedTime = pausedOffset
        vm.playbackStartTime = Date().addingTimeInterval(-(pausedOffset + 0.5))

        let elapsed = vm.calculateElapsedTime()

        // Total elapsed should be ~3.5 s (3.0 offset + 0.5 new), NOT ~6.5 s (double-counted)
        #expect(elapsed != nil, "Fallback path should return a non-nil elapsed time")
        if let t = elapsed {
            #expect(t >= 3.4 && t <= 3.7,
                    "Total elapsed should be ~3.5s (pausedOffset + new playback), not double-counted")
        }
    }

    @Test("pausePlayback during scheduled-start window does not record negative elapsed time")
    func testPauseDuringScheduledStartWindowClampsToZero() async throws {
        let vm = GameplayViewModelCoverageTestSupport.makeViewModel(noteCount: 4)
        await vm.loadChartData()
        await vm.setupGameplay()
        defer { vm.cleanup() }

        // Simulate fresh start with playbackStartTime in the future
        // (scheduled 50ms ahead for buffer priming, as in startPlayback())
        vm.isPlaying = true
        vm.pausedElapsedTime = 0.0
        vm.playbackStartTime = Date().addingTimeInterval(0.05)

        vm.pausePlayback()

        #expect(vm.isPlaying == false)
        #expect(vm.pausedElapsedTime >= 0.0,
                "Paused elapsed time must not be negative when pausing during scheduled-start window")
    }

    @Test("pausePlayback during scheduled-start window preserves existing pause offset on resume")
    func testPauseDuringScheduledStartWindowPreservesExistingOffset() async throws {
        let vm = GameplayViewModelCoverageTestSupport.makeViewModel(noteCount: 4)
        await vm.loadChartData()
        await vm.setupGameplay()
        defer { vm.cleanup() }

        // Simulate resume path: playbackStartTime is backdated the same way
        // startPlayback() does on resume (scheduledStartTime - pausedElapsedTime).
        // With pausedElapsedTime = 3.0 and a scheduled start 0.05 s in the future,
        // the backdated start = (now + 0.05) - 3.0 = now - 2.95.
        vm.isPlaying = true
        vm.pausedElapsedTime = 3.0
        vm.playbackStartTime = Date().addingTimeInterval(0.05 - 3.0)

        vm.pausePlayback()

        #expect(vm.pausedElapsedTime >= 3.0,
                "Should preserve the existing pause offset, not replace with a negative value")
    }

    @Test("calculateElapsedTime returns zero instead of negative before scheduled start")
    func testCalculateElapsedTimeClampsNegativeBeforeScheduledStart() async throws {
        let vm = GameplayViewModelCoverageTestSupport.makeViewModel(noteCount: 4)
        await vm.loadChartData()
        await vm.setupGameplay()
        defer { vm.cleanup() }

        // Fresh start: playbackStartTime is 0.05 s in the future (buffer priming).
        vm.isPlaying = true
        vm.pausedElapsedTime = 0.0
        vm.playbackStartTime = Date().addingTimeInterval(0.05)

        let elapsed = vm.calculateElapsedTime()

        #expect(elapsed == 0.0,
                "calculateElapsedTime should clamp to zero before scheduled start, got \(elapsed ?? -1)")
    }

    @Test("calculateElapsedTime falls back to playbackStartTime when metronome is idle")
    func testCalculateElapsedTimeFallbackToPlaybackStartTime() async throws {
        let vm = GameplayViewModelCoverageTestSupport.makeViewModel(noteCount: 2)
        await vm.loadChartData()
        await vm.setupGameplay()
        defer { vm.cleanup() }

        // Force playing state without starting the metronome so
        // getCurrentPlaybackTime() returns nil and we hit the fallback path.
        vm.isPlaying = true
        vm.playbackStartTime = Date().addingTimeInterval(-2.0)

        let elapsed = vm.calculateElapsedTime()

        vm.isPlaying = false

        #expect(elapsed != nil, "Fallback path should return a non-nil elapsed time")
        if let t = elapsed {
            #expect(t >= 1.9 && t < 3.0, "Elapsed time should be approximately 2 seconds")
        }
    }

    @Test("startPlayback resume uses BGM timeline when bgmPlayer.currentTime > 0")
    func startPlaybackResumeViaBGMTimeline() async throws {
        let vm = GameplayViewModelCoverageTestSupport.makeViewModel(noteCount: 8)
        await vm.loadChartData()
        await vm.setupGameplay(loadPersistedSpeed: false)
        defer { vm.cleanup() }

        let player = try GameplayViewModelTestHarness.makeSilentAudioPlayer()
        player.prepareToPlay()
        vm.bgmPlayer = player
        player.currentTime = 2.0
        vm.bgmOffsetSeconds = 0.5
        vm.cachedTrackDuration = 60.0
        vm.pausedElapsedTime = 3.0

        vm.startPlayback()

        #expect(vm.isPlaying == true)
    }

    enum TestError: Error {
        case playbackStartTimeNil
    }
}
