//
//  GameplayViewModelPlaybackTimingTests.swift
//  VirgoTests
//
//  Split from GameplayViewModelPlaybackTests to keep each file under the
//  SwiftLint file-length warn limit (600). Holds the timing-sync, audio-
//  interruption, effective-BPM, and speed-change tests.
//

import Testing
import Foundation
import AVFoundation
import Observation
import SwiftUI
@testable import Virgo

@Suite("Playback Timing & Speed", .serialized)
@MainActor
struct GameplayViewModelPlaybackTimingTests {

    @Test func testInputTimingSynchronizedWithScheduledPlayback() async throws {
        // Verify that input timeline (playbackStartTime) is derived from the
        // scheduled metronome start time, not from the wall-clock moment
        // startPlayback() was called. This prevents a ~50ms timing gap where
        // hits would be scored against a timeline that started before the
        // player hears any audio.
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 16)
        let metronome = ScheduledMetronomeSpy()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()
        viewModel.setupGameplay()

        // Fresh start (no BGM, metronome-only)
        let startCallTime = CFAbsoluteTimeGetCurrent()
        viewModel.startPlayback()
        #expect(viewModel.isPlaying == true)

        // lastScheduledPlaybackStartTime should be set to the metronome's actual start
        let scheduledTime = try #require(viewModel.lastScheduledPlaybackStartTime,
                                          "lastScheduledPlaybackStartTime should be set after startPlayback")
        // For a fresh metronome-only start, the scheduled time should be ~0.05s after startPlayback begins
        // (consistent with BGM cases, allowing inputManager.startListening to be called before audio starts)
        let scheduledDelay = scheduledTime - startCallTime
        #expect(scheduledDelay > 0.03,
                "Fresh metronome-only scheduled time should be after the start call (delay: \(scheduledDelay)s)")
        #expect(scheduledDelay <= 0.25,
                "Fresh metronome-only scheduled time should be ~0.05s after the start call (delay: \(scheduledDelay)s)")

        // playbackStartTime should be derived from the scheduled time, not wall-clock Date()
        let playbackStart = try #require(viewModel.playbackStartTime)
        let expectedDate = Date(timeIntervalSinceReferenceDate: scheduledTime)
        let dateDrift = abs(playbackStart.timeIntervalSince(expectedDate))
        #expect(dateDrift < 0.01,
                "playbackStartTime should be derived from scheduled CFAbsoluteTime (drift: \(dateDrift)s)")

        // Now test resume path: pause, inject elapsed time, resume
        viewModel.pausePlayback()
        let simulatedElapsed: Double = 2.0
        viewModel.pausedElapsedTime = simulatedElapsed

        let resumeCallTime = CFAbsoluteTimeGetCurrent()
        viewModel.startPlayback()
        let resumeScheduled = try #require(viewModel.lastScheduledPlaybackStartTime)
        // On resume, the metronome is scheduled 0.05s in the future
        let resumeScheduledDelay = resumeScheduled - resumeCallTime
        #expect(resumeScheduledDelay > 0.03,
                "Resume should schedule metronome after the resume call (delay: \(resumeScheduledDelay)s)")
        #expect(resumeScheduledDelay <= 0.25,
                "Resume scheduled time should be ~0.05s after the resume call (delay: \(resumeScheduledDelay)s)")

        // playbackStartTime should account for both the scheduled time and the elapsed offset
        let resumePlaybackStart = try #require(viewModel.playbackStartTime)
        let expectedResumeDate = Date(timeIntervalSinceReferenceDate: resumeScheduled - simulatedElapsed)
        let resumeDateDrift = abs(resumePlaybackStart.timeIntervalSince(expectedResumeDate))
        #expect(resumeDateDrift < 0.01,
                "Resume playbackStartTime should be derived from scheduled time minus elapsed offset (drift: \(resumeDateDrift)s)")

        viewModel.cleanup()
    }

    @Test("resume schedules metronome from fractional beat progress")
    func testResumeSchedulesMetronomeFromFractionalBeatProgress() async throws {
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 16)
        let metronome = ScheduledMetronomeSpy()
        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()
        viewModel.setupGameplay(loadPersistedSpeed: false)

        let pausedElapsedTime = 2.25
        viewModel.pausedElapsedTime = pausedElapsedTime

        viewModel.startPlayback()

        let call = try #require(
            metronome.startAtTimeCalls.last,
            "Resuming playback should schedule the metronome"
        )
        let secondsPerBeat = 60.0 / viewModel.effectiveBPM()
        let expectedBeatsElapsed = pausedElapsedTime / secondsPerBeat

        #expect(
            abs(call.totalBeatsElapsed - expectedBeatsElapsed) < 0.0001,
            "Metronome scheduling should preserve fractional beat progress instead of flooring to an integer"
        )
        #expect(viewModel.totalBeatsElapsed == Int(expectedBeatsElapsed))
        #expect(viewModel.isPlaying == true)

        viewModel.cleanup()
    }

    @Test func testAudioInterruptionPausesPlayback() async {
        // Test that audio interruptions (phone calls, Siri, etc.) pause playback.
        // This verifies the interruption handling chain:
        // MetronomeAudioEngine.onInterruption -> MetronomeEngine.onInterruption -> GameplayViewModel.pausePlayback
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 8)
        let metronome = GameplayViewModelTestHarness.createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()
        viewModel.setupGameplay()

        // Start playback
        viewModel.startPlayback()
        #expect(viewModel.isPlaying == true, "Playback should be active")

        // Simulate audio interruption by invoking the metronome's callback
        // This mimics what happens when iOS sends an interruption notification
        metronome.onInterruption?(true)

        // Verify playback was paused
        #expect(viewModel.isPlaying == false, "Playback should be paused after interruption")
        #expect(viewModel.playbackStartTime == nil, "playbackStartTime should be nil after pause")

        // Verify state is preserved (not reset)
        // pausedElapsedTime should have captured the elapsed time
        // (in this test it may be 0 or small since we just started)

        // Cleanup
        viewModel.cleanup()
    }

    @Test func testAudioInterruptionEndDoesNotAutoResume() async {
        // Test that when audio interruption ends, playback does NOT automatically resume.
        // Users should manually resume to avoid unexpected audio playback.
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 8)
        let metronome = GameplayViewModelTestHarness.createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()
        viewModel.setupGameplay()

        // Start playback
        viewModel.startPlayback()
        #expect(viewModel.isPlaying == true)

        // Simulate interruption begin
        metronome.onInterruption?(true)
        #expect(viewModel.isPlaying == false, "Should be paused after interruption")

        // Simulate interruption end
        metronome.onInterruption?(false)

        // Verify playback is still paused (not auto-resumed)
        #expect(viewModel.isPlaying == false, "Should remain paused after interruption ends - no auto-resume")

        // Cleanup
        viewModel.cleanup()
    }

    @Test func testEffectiveBPMCalculation() async throws {
        let chart = GameplayViewModelTestHarness.createTestChart()
        let metronome = GameplayViewModelTestHarness.createTestMetronome()

        let (userDefaults, _) = TestUserDefaults.makeIsolated()
        let practiceSettings = PracticeSettingsService(userDefaults: userDefaults)
        let viewModel = GameplayViewModel(chart: chart, metronome: metronome, practiceSettings: practiceSettings)
        await viewModel.loadChartData()
        viewModel.setupGameplay()

        // Get base BPM (should be 120.0 for test charts without songs)
        guard let track = viewModel.track else {
            throw TestError.trackMissing
        }
        let baseBPM = track.bpm
        let tolerance = 0.01

        // Default speed is 1.0, so effective BPM should equal track BPM
        #expect(
            abs(viewModel.effectiveBPM() - baseBPM) < tolerance,
            "At 100% speed, effective BPM should equal base BPM"
        )
        #expect(
            abs(viewModel.inputManager.configuredBPM - baseBPM) < tolerance,
            "InputManager should be configured with effective BPM at 100% speed"
        )

        // Set speed to 50%
        viewModel.practiceSettings.setSpeed(0.5)
        viewModel.setupGameplay(loadPersistedSpeed: false)
        #expect(
            abs(viewModel.effectiveBPM() - (baseBPM * 0.5)) < tolerance,
            "At 50% speed, effective BPM should be half of base BPM"
        )
        #expect(
            abs(viewModel.inputManager.configuredBPM - (baseBPM * 0.5)) < tolerance,
            "InputManager should be configured with effective BPM at 50% speed"
        )

        // Set speed to 150%
        viewModel.practiceSettings.setSpeed(1.5)
        viewModel.setupGameplay(loadPersistedSpeed: false)
        #expect(
            abs(viewModel.effectiveBPM() - (baseBPM * 1.5)) < tolerance,
            "At 150% speed, effective BPM should be 1.5x base BPM"
        )
        #expect(
            abs(viewModel.inputManager.configuredBPM - (baseBPM * 1.5)) < tolerance,
            "InputManager should be configured with effective BPM at 150% speed"
        )

        viewModel.cleanup()
    }

    @Test func testUpdateSpeedDuringPlayback() async throws {
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 8)
        let metronome = GameplayViewModelTestHarness.createTestMetronome()

        let (userDefaults, _) = TestUserDefaults.makeIsolated()
        let practiceSettings = PracticeSettingsService(userDefaults: userDefaults)
        let viewModel = GameplayViewModel(chart: chart, metronome: metronome, practiceSettings: practiceSettings)
        await viewModel.loadChartData()
        viewModel.setupGameplay()

        // Start playback at default speed
        viewModel.startPlayback()
        #expect(viewModel.isPlaying == true)

        guard let track = viewModel.track else {
            throw TestError.trackMissing
        }
        let baseBPM = track.bpm
        let tolerance = 0.01

        // Change speed during playback
        viewModel.updateSpeed(0.75)

        // Wait for trailing-edge debounce timer to fire (100ms debounce interval + small buffer)
        try await Task.sleep(nanoseconds: 300_000_000)

        // Verify speed was applied
        #expect(
            viewModel.practiceSettings.speedMultiplier == 0.75,
            "Speed should be updated to 75%"
        )
        #expect(
            abs(viewModel.effectiveBPM() - (baseBPM * 0.75)) < tolerance,
            "Effective BPM should reflect new speed"
        )
        #expect(
            abs(viewModel.inputManager.configuredBPM - (baseBPM * 0.75)) < tolerance,
            "InputManager should be configured with effective BPM after speed change"
        )

        // Verify metronome was updated (it should still be playing)
        // Note: We can't directly verify metronome.bpm was updated, but we can check playback continues
        #expect(viewModel.isPlaying == true, "Playback should continue after speed change")

        viewModel.cleanup()
    }

    @Test func testUpdateSpeedBeforePlaybackReconfiguresInputManager() async throws {
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 8)
        let metronome = GameplayViewModelTestHarness.createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()
        viewModel.setupGameplay()

        guard let track = viewModel.track else {
            throw TestError.trackMissing
        }

        #expect(viewModel.isPlaying == false)

        let baseBPM = track.bpm
        let tolerance = 0.01

        viewModel.updateSpeed(0.75)

        // Wait for trailing-edge debounce timer to fire (100ms debounce interval + small buffer)
        try await Task.sleep(nanoseconds: 300_000_000)

        #expect(
            abs(viewModel.inputManager.configuredBPM - (baseBPM * 0.75)) < tolerance,
            "InputManager should be configured with effective BPM after pre-playback speed change"
        )

        viewModel.cleanup()
    }

    @Test func testInputManagerConfiguredWithEffectiveBPM() async throws {
        // This test verifies that InputManager is configured with effective BPM so scoring matches playback speed.

        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 8)
        let metronome = GameplayViewModelTestHarness.createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()

        // Verify track was loaded
        guard let track = viewModel.track else {
            throw TestError.trackMissing
        }

        // Set speed to 50%
        viewModel.practiceSettings.setSpeed(0.5)

        // Use loadPersistedSpeed: false to preserve the preconfigured speed
        viewModel.setupGameplay(loadPersistedSpeed: false)

        let baseBPM = track.bpm
        let effectiveBPM = viewModel.effectiveBPM()

        // Use small tolerance for floating point comparison
        let tolerance = 0.01
        #expect(abs(effectiveBPM - (baseBPM * 0.5)) < tolerance, "Effective BPM should be 50% of base at this speed")
        #expect(abs(effectiveBPM - baseBPM) > tolerance, "At 50% speed, effective BPM should differ from base BPM")
        #expect(
            abs(viewModel.inputManager.configuredBPM - (baseBPM * 0.5)) < tolerance,
            "InputManager should be configured with effective BPM when speed changes"
        )

        viewModel.cleanup()
    }

    @Test func testMetronomeBPMMatchesEffectiveBPMOnSpeedChange() async throws {
        // This test verifies that the metronome BPM matches effectiveBPM after speed changes.
        // This ensures synchronization between metronome audio, visual timing, and BGM.
        // Previously, updateBPM clamped to 40-200 which caused desync at extreme speeds.

        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 8)
        let metronome = GameplayViewModelTestHarness.createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()
        viewModel.setupGameplay()

        // Verify track was loaded
        guard let track = viewModel.track else {
            throw TestError.trackMissing
        }

        // Test 1: Normal speed (100%)
        viewModel.startPlayback()
        let normalEffectiveBPM = viewModel.effectiveBPM()
        #expect(metronome.bpm == normalEffectiveBPM, "Metronome BPM should match effective BPM at 100% speed")
        viewModel.pausePlayback()

        // Test 2: Slow speed (50%) - common for practice
        viewModel.practiceSettings.setSpeed(0.5)
        viewModel.startPlayback()
        let slowEffectiveBPM = viewModel.effectiveBPM()
        #expect(metronome.bpm == slowEffectiveBPM, "Metronome BPM should match effective BPM at 50% speed")
        #expect(abs(metronome.bpm - (track.bpm * 0.5)) < 0.01, "Metronome BPM should be 50% of base BPM")
        viewModel.pausePlayback()

        // Test 3: Very slow speed (25%) - for learning complex patterns
        // If base BPM is 120, effective BPM would be 30 (previously clamped to 40)
        viewModel.practiceSettings.setSpeed(0.25)
        viewModel.startPlayback()
        let verySlowEffectiveBPM = viewModel.effectiveBPM()
        #expect(
            metronome.bpm == verySlowEffectiveBPM,
            "Metronome BPM should match effective BPM at 25% speed"
        )
        #expect(abs(metronome.bpm - (track.bpm * 0.25)) < 0.01, "Metronome BPM should be 25% of base BPM")
        viewModel.pausePlayback()

        // Test 4: Fast speed (150%) - for endurance training
        viewModel.practiceSettings.setSpeed(1.5)
        viewModel.startPlayback()
        let fastEffectiveBPM = viewModel.effectiveBPM()
        #expect(metronome.bpm == fastEffectiveBPM, "Metronome BPM should match effective BPM at 150% speed")
        #expect(abs(metronome.bpm - (track.bpm * 1.5)) < 0.01, "Metronome BPM should be 150% of base BPM")
        viewModel.pausePlayback()

        // Test 5: Live speed change during playback
        // Start at 75% speed
        viewModel.practiceSettings.setSpeed(0.75)
        viewModel.startPlayback()
        #expect(metronome.bpm == track.bpm * 0.75, "Initial metronome BPM should be correct")

        // Change speed to 125% while playing
        viewModel.updateSpeed(1.25)
        // Wait for trailing-edge debounce timer to fire (100ms debounce interval + small buffer)
        try await Task.sleep(nanoseconds: 300_000_000)
        let updatedEffectiveBPM = viewModel.effectiveBPM()
        #expect(
            metronome.bpm == updatedEffectiveBPM,
            "Metronome BPM should update to match new effective BPM during live speed change"
        )
        #expect(
            abs(metronome.bpm - (track.bpm * 1.25)) < 0.01,
            "Metronome BPM should be 125% of base BPM after live change"
        )

        viewModel.cleanup()
    }

    enum TestError: Error {
        case trackMissing
    }
}
