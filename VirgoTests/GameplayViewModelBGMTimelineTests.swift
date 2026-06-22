//
//  GameplayViewModelBGMTimelineTests.swift
//  VirgoTests
//

import Testing
import Foundation
import AVFoundation
import Observation
import SwiftUI
@testable import Virgo

@Suite("BGM Timeline & Speed Rescale", .serialized)
@MainActor
struct GameplayViewModelBGMTimelineTests {

    @Test func testRemainingBGMOffsetAccountsForPausedElapsedTime() async throws {
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 8)
        let metronome = GameplayViewModelTestHarness.createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()
        viewModel.setupGameplay()

        viewModel.bgmOffsetSeconds = 1.2
        viewModel.pausedElapsedTime = 0.4

        #expect(
            abs(viewModel.remainingBGMOffset() - 0.8) < 0.001,
            "Remaining BGM offset should subtract paused elapsed time"
        )

        viewModel.cleanup()
    }

    @Test func testRescheduleBGMForSpeedChangeNoBGM() async throws {
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 8)
        let metronome = GameplayViewModelTestHarness.createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()
        viewModel.setupGameplay()

        let didReschedule = viewModel.rescheduleBGMForSpeedChange(commonStartTime: CFAbsoluteTimeGetCurrent())
        #expect(didReschedule == false, "Reschedule should be a no-op without an active BGM player")

        viewModel.cleanup()
    }

    @Test func testUpdateSpeedWhilePausedRescalesElapsedTime() async throws {
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 8)
        let metronome = GameplayViewModelTestHarness.createTestMetronome()

        let practiceSettings = GameplayViewModelTestHarness.createTestPracticeSettings()
        let viewModel = GameplayViewModel(chart: chart, metronome: metronome, practiceSettings: practiceSettings)
        await viewModel.loadChartData()
        viewModel.setupGameplay(loadPersistedSpeed: false)

        viewModel.practiceSettings.setSpeed(1.0)
        viewModel.pausedElapsedTime = 2.0
        viewModel.updateSpeed(0.5)

        // Wait for trailing-edge debounce timer to fire (100ms debounce interval + small buffer)
        try await Task.sleep(nanoseconds: 300_000_000)

        let expectedProgress = viewModel.cachedTrackDuration > 0
            ? viewModel.pausedElapsedTime / viewModel.cachedTrackDuration
            : 0.0
        #expect(
            abs(viewModel.pausedElapsedTime - 4.0) < 0.001,
            "Paused elapsed time should scale to the new speed timeline"
        )
        #expect(
            abs(viewModel.playbackProgress - expectedProgress) < 0.001,
            "Playback progress should update to match rescaled elapsed time"
        )

        viewModel.cleanup()
    }

    @Test func testUpdateSpeedWhilePlayingRescalesElapsedTimeWhenMetronomeTimeUnavailable() async throws {
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 8)
        let metronome = GameplayViewModelTestHarness.createTestMetronome()
        let practiceSettings = GameplayViewModelTestHarness.createTestPracticeSettings()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome, practiceSettings: practiceSettings)
        await viewModel.loadChartData()
        viewModel.setupGameplay(loadPersistedSpeed: false)

        // Simulate active playback state while metronome time is unavailable.
        // This forces the fallback speed-change path (metronome.getCurrentPlaybackTime() == nil).
        viewModel.practiceSettings.setSpeed(1.0)
        viewModel.isPlaying = true
        viewModel.pausedElapsedTime = 2.0

        viewModel.updateSpeed(0.5)
        // Wait for trailing-edge debounce timer to fire (100ms debounce interval + buffer)
        try await Task.sleep(nanoseconds: 300_000_000)

        #expect(
            abs(viewModel.pausedElapsedTime - 4.0) < 0.001,
            "Elapsed timeline should rescale in fallback path when metronome playback time is unavailable"
        )
        #expect(
            abs(metronome.bpm - viewModel.effectiveBPM()) < 0.001,
            "Metronome BPM should still be updated in fallback path"
        )
        #expect(
            metronome.isEnabled == true,
            "Fallback speed change should reschedule the metronome instead of only updating BPM"
        )

        viewModel.cleanup()
    }

    @Test func testBGMTimelineElapsedTimeScalesWithSpeed() async throws {
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 8)
        let metronome = GameplayViewModelTestHarness.createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()
        viewModel.setupGameplay()

        viewModel.bgmOffsetSeconds = 0.5
        viewModel.practiceSettings.setSpeed(0.5)

        let timelineElapsed = viewModel.bgmTimelineElapsedTime(for: 2.0)
        #expect(abs(timelineElapsed - 4.5) < 0.001, "BGM timeline should scale by speed and include offset")

        viewModel.cleanup()
    }

    @Test func testCalculateElapsedTimeUsesBGMClockAfterBGMStarts() async throws {
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 8)
        let metronome = GameplayViewModelTestHarness.createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()
        viewModel.setupGameplay(loadPersistedSpeed: false)

        let player = try GameplayViewModelTestHarness.makeSilentAudioPlayer(durationSeconds: 5.0)
        player.currentTime = 2.0
        viewModel.bgmPlayer = player
        viewModel.bgmOffsetSeconds = 0.75
        viewModel.isPlaying = true

        metronome.startAtTime(
            bpm: viewModel.effectiveBPM(),
            timeSignature: .fourFour,
            startTime: CFAbsoluteTimeGetCurrent() - 10.0
        )

        let elapsedTime = try #require(viewModel.calculateElapsedTime())

        #expect(
            abs(elapsedTime - 2.75) < 0.001,
            "Elapsed gameplay time should follow BGM currentTime plus BGM offset once BGM has started"
        )

        metronome.stop()
        viewModel.cleanup()
    }

    @Test func testVisualUpdateUsesBGMClockAfterBGMStarts() async throws {
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 32)
        let metronome = GameplayViewModelTestHarness.createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()
        viewModel.setupGameplay(loadPersistedSpeed: false)

        let player = try GameplayViewModelTestHarness.makeSilentAudioPlayer(durationSeconds: 5.0)
        player.currentTime = 2.0
        viewModel.bgmPlayer = player
        viewModel.bgmOffsetSeconds = 0.75
        viewModel.isPlaying = true

        metronome.startAtTime(
            bpm: viewModel.effectiveBPM(),
            timeSignature: .fourFour,
            startTime: CFAbsoluteTimeGetCurrent() - 10.0
        )

        viewModel.updateVisualElementsFromMetronome()

        let expectedProgress = 2.75 / viewModel.cachedTrackDuration
        #expect(
            abs(viewModel.playbackProgress - expectedProgress) < 0.001,
            "Visual progress should use BGM currentTime, not the independent metronome elapsed time"
        )

        metronome.stop()
        viewModel.cleanup()
    }

    @Test("visual timeline stays aligned to speed-adjusted BGM clock over a long run")
    func testLongRunVisualTimelineUsesSpeedAdjustedBGMClock() async throws {
        let song = Song(
            title: "Long BGM Sync",
            artist: "Tester",
            bpm: 120,
            duration: "2:00",
            genre: "DTX",
            bgmStartOffsetSeconds: 0.9
        )
        let chart = Chart(difficulty: .medium, timeSignature: .fourFour, song: song)
        for measureNumber in 1...40 {
            chart.notes.append(
                Note(interval: .quarter, noteType: .snare, measureNumber: measureNumber, measureOffset: 0.0)
            )
        }
        let practiceSettings = GameplayViewModelTestHarness.createTestPracticeSettings()
        practiceSettings.setSpeed(0.75)
        let metronome = GameplayViewModelTestHarness.createTestMetronome()
        let viewModel = GameplayViewModel(chart: chart, metronome: metronome, practiceSettings: practiceSettings)

        await viewModel.loadChartData()
        viewModel.setupGameplay(loadPersistedSpeed: false)
        let bgmPlayer = try GameplayViewModelTestHarness.makeSilentAudioPlayer(durationSeconds: 90.0)
        bgmPlayer.currentTime = 45.0
        viewModel.bgmPlayer = bgmPlayer
        viewModel.isPlaying = true

        viewModel.updateVisualElementsFromMetronome()

        let expectedElapsedTime = 45.0 / 0.75 + (0.9 / 0.75)
        let expectedTotalBeats = Int(expectedElapsedTime / (60.0 / viewModel.effectiveBPM()))
        let expectedMeasureIndex = expectedTotalBeats / chart.timeSignature.beatsPerMeasure
        let expectedBeatPosition = Double(expectedTotalBeats % chart.timeSignature.beatsPerMeasure)
            / Double(chart.timeSignature.beatsPerMeasure)

        #expect(viewModel.totalBeatsElapsed == expectedTotalBeats)
        #expect(viewModel.currentMeasureIndex == expectedMeasureIndex)
        #expect(abs(viewModel.currentBeatPosition - expectedBeatPosition) < 0.0001)
        #expect(viewModel.purpleBarPosition != nil)

        viewModel.cleanup()
    }

    @Test func testPausePlaybackUsesBGMClockAfterBGMStarts() async throws {
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 32)
        let metronome = GameplayViewModelTestHarness.createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()
        viewModel.setupGameplay(loadPersistedSpeed: false)

        let player = try GameplayViewModelTestHarness.makeSilentAudioPlayer(durationSeconds: 5.0)
        player.currentTime = 2.0
        viewModel.bgmPlayer = player
        viewModel.bgmOffsetSeconds = 0.75
        viewModel.isPlaying = true

        metronome.startAtTime(
            bpm: viewModel.effectiveBPM(),
            timeSignature: .fourFour,
            startTime: CFAbsoluteTimeGetCurrent() - 10.0
        )

        viewModel.pausePlayback()

        #expect(
            abs(viewModel.pausedElapsedTime - 2.75) < 0.001,
            "Pause should preserve the BGM-derived timeline position once BGM has started"
        )

        viewModel.cleanup()
    }

    @Test func testCalculateBGMOffsetWithFirstMeasureNote() async throws {
        let chart = Chart(difficulty: .medium)
        let note = Note(
            interval: .quarter,
            noteType: .bass,
            measureNumber: 1,
            measureOffset: 0.0
        )
        chart.notes.append(note)

        let metronome = GameplayViewModelTestHarness.createTestMetronome()
        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)

        await viewModel.loadChartData()
        viewModel.setupGameplay()

        // Note at start of measure 1 should have 0 offset
        #expect(viewModel.bgmOffsetSeconds == 0.0)

        viewModel.cleanup()
    }

    @Test func testCalculateBGMOffsetWithLaterNote() async throws {
        let chart = Chart(difficulty: .medium)
        // Note in measure 2 at beat 2
        let note = Note(
            interval: .quarter,
            noteType: .bass,
            measureNumber: 2,
            measureOffset: 0.5
        )
        chart.notes.append(note)

        let metronome = GameplayViewModelTestHarness.createTestMetronome()
        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)

        await viewModel.loadChartData()
        viewModel.setupGameplay()

        // Should have non-zero offset since first note is not at start
        #expect(viewModel.bgmOffsetSeconds > 0.0)

        viewModel.cleanup()
    }

    @Test("calculateBGMOffset uses persisted DTX BGM lane start when available")
    func testCalculateBGMOffsetUsesPersistedBGMLaneStart() async throws {
        let song = Song(
            title: "BGM Offset",
            artist: "Tester",
            bpm: 200,
            duration: "3:30",
            genre: "DTX",
            bgmStartOffsetSeconds: 0.9
        )
        let chart = Chart(difficulty: .medium, song: song)
        chart.notes.append(Note(interval: .quarter, noteType: .bass, measureNumber: 2, measureOffset: 0.625))

        let viewModel = GameplayViewModel(chart: chart, metronome: GameplayViewModelTestHarness.createTestMetronome())
        await viewModel.loadChartData()
        viewModel.setupGameplay()

        #expect(abs(viewModel.bgmOffsetSeconds - 0.9) < 0.001)

        viewModel.cleanup()
    }

    @Test("calculateBGMOffset honors an explicit zero BGM offset even when the first note is later")
    func testCalculateBGMOffsetHonorsExplicitZero() async throws {
        // DTX charts where lane 01 starts at measure 000 (e.g. `#00001: 1A…`)
        // parse to a legitimate 0.0 BGM offset meaning "audio starts immediately".
        // The first playable drum note may come later; the BGM must NOT be delayed
        // to that note's time. Previously the `> 0` presence check discarded the
        // 0.0 and fell back to the first-note heuristic, delaying the BGM.
        let song = Song(
            title: "BGM At Zero",
            artist: "Tester",
            bpm: 200,
            duration: "3:30",
            genre: "DTX",
            bgmStartOffsetSeconds: 0.0
        )
        let chart = Chart(difficulty: .medium, song: song)
        // First drum note in measure 3 — well after the BGM start.
        chart.notes.append(Note(interval: .quarter, noteType: .bass, measureNumber: 3, measureOffset: 0.0))

        let viewModel = GameplayViewModel(
            chart: chart,
            metronome: GameplayViewModelTestHarness.createTestMetronome()
        )
        await viewModel.loadChartData()
        viewModel.setupGameplay()

        #expect(abs(viewModel.bgmOffsetSeconds) < 0.001,
               "An explicit 0.0 BGM offset must be honored, not replaced by the first-note heuristic")

        viewModel.cleanup()
    }

    @Test("calculateBGMOffset scales by speed multiplier for notes after measure 1")
    func testCalculateBGMOffsetScalesWithSpeedMultiplier() async throws {
        // A note in measure 3 should produce a non-zero BGM offset.
        // At 50% speed the offset should be double the 100% speed offset,
        // since BGM starts playing later to align with the slower tempo.
        let chart = Chart(difficulty: .medium)
        let note = Note(
            interval: .quarter,
            noteType: .bass,
            measureNumber: 3,
            measureOffset: 0.0
        )
        chart.notes.append(note)

        // Use isolated metronome and practice settings instances per view model
        let metronomeFull = GameplayViewModelTestHarness.createTestMetronome()
        let practiceSettingsFull = GameplayViewModelTestHarness.createTestPracticeSettings()
        practiceSettingsFull.setSpeed(1.0)
        let viewModelFull = GameplayViewModel(chart: chart, metronome: metronomeFull, practiceSettings: practiceSettingsFull)
        await viewModelFull.loadChartData()
        viewModelFull.setupGameplay(loadPersistedSpeed: false)
        let offsetAt100 = viewModelFull.bgmOffsetSeconds

        let metronomeHalf = GameplayViewModelTestHarness.createTestMetronome()
        let practiceSettingsHalf = GameplayViewModelTestHarness.createTestPracticeSettings()
        practiceSettingsHalf.setSpeed(0.5)
        let viewModelHalf = GameplayViewModel(chart: chart, metronome: metronomeHalf, practiceSettings: practiceSettingsHalf)
        await viewModelHalf.loadChartData()
        viewModelHalf.setupGameplay(loadPersistedSpeed: false)
        let offsetAt50 = viewModelHalf.bgmOffsetSeconds

        #expect(offsetAt100 > 0.0, "BGM offset should be positive when first note is not at beginning")
        #expect(offsetAt50 > 0.0, "BGM offset at 50% speed should also be positive")
        // At 50% speed, BGM offset must be 2× the 100% speed offset (within floating-point tolerance)
        let ratio = offsetAt50 / offsetAt100
        #expect(abs(ratio - 2.0) < 0.001,
                "BGM offset at 50% speed should be exactly 2× the offset at 100% speed, got ratio \(ratio)")

        viewModelFull.cleanup()
        viewModelHalf.cleanup()
    }

    @Test func testCalculateElapsedTimeWhenNotPlaying() async throws {
        let chart = GameplayViewModelTestHarness.createTestChart()
        let metronome = GameplayViewModelTestHarness.createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)

        // When not playing and no start time, should return nil
        let elapsed = viewModel.calculateElapsedTime()
        #expect(elapsed == nil)
    }

    @Test func testBGMRateClampedAtMinimumSpeed() async throws {
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 8)
        let metronome = GameplayViewModelTestHarness.createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()
        viewModel.setupGameplay()

        // Inject an in-memory BGM player so the clamp path is exercised
        // deterministically regardless of whether BGM test assets exist on disk.
        let bgmPlayer = try GameplayViewModelTestHarness.makeSilentAudioPlayer(durationSeconds: 10.0)
        viewModel.bgmPlayer = bgmPlayer
        #expect(viewModel.bgmPlayer != nil, "BGM player must be present to validate the clamp path")

        viewModel.startPlayback()
        #expect(viewModel.isPlaying == true)

        // Set speed to 25% (below AVAudioPlayer's minimum of 50%)
        viewModel.updateSpeed(0.25)

        // Wait for trailing-edge debounce timer to fire (100ms debounce interval + small buffer)
        try await Task.sleep(nanoseconds: 300_000_000)

        // Verify practiceSettings clamped to 50% to keep BGM in sync
        #expect(viewModel.practiceSettings.speedMultiplier == 0.5, "Speed should be clamped to 50% with BGM")

        // Verify BGM rate is clamped to 0.5 (not 0.25)
        #expect(bgmPlayer.rate == 0.5, "BGM rate should be clamped to 0.5 (50%) when speed is below 50%")

        viewModel.cleanup()
    }

    @Test func testBGMRateAllowsFullSpeedRange() async throws {
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 8)
        let metronome = GameplayViewModelTestHarness.createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()
        viewModel.setupGameplay()

        // Inject an in-memory BGM player so the rate assertions are deterministic.
        let bgmPlayer = try GameplayViewModelTestHarness.makeSilentAudioPlayer(durationSeconds: 10.0)
        viewModel.bgmPlayer = bgmPlayer
        #expect(viewModel.bgmPlayer != nil, "BGM player must be present to validate the rate path")

        viewModel.startPlayback()
        #expect(viewModel.isPlaying == true)

        // Set speed to 150% (within AVAudioPlayer's range)
        viewModel.updateSpeed(1.5)

        // Wait for trailing-edge debounce timer to fire (100ms debounce interval + small buffer)
        try await Task.sleep(nanoseconds: 300_000_000)

        // Verify BGM rate is NOT clamped
        #expect(bgmPlayer.rate == 1.5, "BGM rate should be 1.5 when speed is 150% (within supported range)")

        // Set speed to 75%
        viewModel.updateSpeed(0.75)

        // Wait for trailing-edge debounce timer to fire
        try await Task.sleep(nanoseconds: 300_000_000)

        #expect(bgmPlayer.rate == 0.75, "BGM rate should be 0.75 when speed is 75% (within supported range)")

        viewModel.cleanup()
    }

    @Test func testBGMRateClampsAtAVAudioPlayerBounds() async throws {
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 8)
        let metronome = GameplayViewModelTestHarness.createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()
        viewModel.setupGameplay()

        let highClampedRate = viewModel.clampedBGMRate(for: 2.5)
        #expect(highClampedRate == 2.0, "BGM rate should clamp to 2.0 when speed exceeds 200%")

        let lowClampedRate = viewModel.clampedBGMRate(for: 0.25)
        #expect(lowClampedRate == 0.5, "BGM rate should clamp to 0.5 when speed is below 50%")

        viewModel.cleanup()
    }

    @Test func testSetupGameplayUpdatesBaselineAfterBGMClamp() async throws {
        // Regression test for: Speed baseline must stay in sync after setup-time BGM clamp.
        // When a persisted speed below 50% is loaded (e.g., 0.25), it gets clamped to 0.5
        // for BGM charts. The lastAppliedSpeedMultiplier must be updated to reflect the
        // clamped value, not the original persisted value, to ensure subsequent live speed
        // changes calculate correct ratios and don't cause timing jumps.
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 8)
        let metronome = GameplayViewModelTestHarness.createTestMetronome()

        // Create isolated UserDefaults for this test
        let (userDefaults, _) = TestUserDefaults.makeIsolated()
        let practiceSettings = PracticeSettingsService(userDefaults: userDefaults)

        // Save a speed below BGM minimum (0.25 < 0.50)
        practiceSettings.saveSpeed(0.25, for: chart.persistentModelID)

        // Create ViewModel with BGM present (needs a song with BGM path)
        let viewModel = GameplayViewModel(chart: chart, metronome: metronome, practiceSettings: practiceSettings)
        await viewModel.loadChartData()

        // Inject a mock BGM player so the clamp behavior is deterministically
        // exercised. Without this, bgmPlayer is nil and no clamp ever runs.
        viewModel.bgmPlayer = try GameplayViewModelTestHarness.makeSilentAudioPlayer(durationSeconds: 10.0)
        viewModel.setupGameplay()

        // Wait for async setup
        try await Task.sleep(nanoseconds: 50_000_000)

        // BGM is present, so persisted 0.25 speed must have been clamped to >= 0.5.
        #expect(
            practiceSettings.speedMultiplier >= 0.5,
            "Speed should be clamped to at least 50% when BGM is present"
        )

        // The critical fix: lastAppliedSpeedMultiplier must reflect the effective speed
        // This is verified indirectly by checking that speed changes work correctly
        let initialEffectiveBPM = viewModel.effectiveBPM()

        // Simulate a speed update during playback (this would use the ratio)
        viewModel.updateSpeed(1.0)
        try await Task.sleep(nanoseconds: 300_000_000)

        // After speed change, effective BPM should reflect the new speed.
        // With BGM clamping, speed went from 0.5 to 1.0 (2x).
        let newEffectiveBPM = viewModel.effectiveBPM()
        #expect(
            abs(newEffectiveBPM - initialEffectiveBPM * 2.0) < 0.01,
            "BPM should approximately double when going from 0.5 to 1.0 with BGM clamping"
        )

        viewModel.cleanup()
    }
}
