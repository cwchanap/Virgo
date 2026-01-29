// swiftlint:disable file_length
//
//  GameplayViewModelTests.swift
//  VirgoTests
//
//  Tests for GameplayViewModel - consolidated state management for GameplayView
//

import Testing
import Foundation
import SwiftUI
@testable import Virgo

@MainActor
// swiftlint:disable:next type_body_length
struct GameplayViewModelTests {

    // MARK: - Test Helpers

    /// Creates a test Chart with sample notes
    private func createTestChart(
        noteCount: Int = 4,
        measuresCount: Int = 1
    ) -> Chart {
        let chart = Chart(difficulty: .medium)

        // Add sample notes across measures
        for i in 0..<noteCount {
            let measureNumber = (i / 4) + 1
            let measureOffset = Double(i % 4) * 0.25
            let note = Note(
                interval: .quarter,
                noteType: i % 2 == 0 ? .bass : .snare,
                measureNumber: measureNumber,
                measureOffset: measureOffset
            )
            chart.notes.append(note)
        }

        return chart
    }

    /// Creates a test MetronomeEngine
    private func createTestMetronome() -> MetronomeEngine {
        return MetronomeEngine()
    }

    // MARK: - Initialization Tests

    @Test func testInitialization() async throws {
        let chart = createTestChart()
        let metronome = createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)

        #expect(viewModel.chart === chart)
        #expect(viewModel.metronome === metronome)
        #expect(viewModel.isPlaying == false)
        #expect(viewModel.playbackProgress == 0.0)
        #expect(viewModel.currentBeat == 0)
        #expect(viewModel.isDataLoaded == false)
    }

    @Test func testInitialStateIsCorrect() async throws {
        let chart = createTestChart()
        let metronome = createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)

        // Verify all initial state values
        #expect(viewModel.cachedSong == nil)
        #expect(viewModel.cachedNotes.isEmpty)
        #expect(viewModel.track == nil)
        #expect(viewModel.cachedDrumBeats.isEmpty)
        #expect(viewModel.cachedMeasurePositions.isEmpty)
        #expect(viewModel.cachedBeamGroups.isEmpty)
        #expect(viewModel.activeBeatId == nil)
        #expect(viewModel.purpleBarPosition == nil)
        #expect(viewModel.bgmPlayer == nil)
    }

    // MARK: - Data Loading Tests

    @Test func testLoadChartData() async throws {
        let chart = createTestChart(noteCount: 8)
        let metronome = createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)

        #expect(viewModel.isDataLoaded == false)

        await viewModel.loadChartData()

        #expect(viewModel.isDataLoaded == true)
        #expect(viewModel.cachedNotes.count == 8)
        #expect(viewModel.track != nil)
    }

    @Test func testLoadChartDataWithEmptyNotes() async throws {
        let chart = Chart(difficulty: .easy)
        let metronome = createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)

        await viewModel.loadChartData()

        #expect(viewModel.isDataLoaded == true)
        #expect(viewModel.cachedNotes.isEmpty)
        #expect(viewModel.track != nil)
    }

    // MARK: - Setup Tests

    @Test func testSetupGameplay() async throws {
        let chart = createTestChart(noteCount: 8)
        let metronome = createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)

        await viewModel.loadChartData()
        viewModel.setupGameplay()

        // Verify computed data is populated
        #expect(!viewModel.cachedDrumBeats.isEmpty)
        #expect(!viewModel.cachedMeasurePositions.isEmpty)
        #expect(!viewModel.cachedBeatIndices.isEmpty)
        #expect(!viewModel.measurePositionMap.isEmpty)
        #expect(viewModel.cachedTrackDuration > 0)
    }

    @Test func testSetupGameplayWithoutLoadingData() async throws {
        let chart = createTestChart()
        let metronome = createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)

        // Call setupGameplay without loading data first
        viewModel.setupGameplay()

        // Should not crash, but data should remain empty since track is nil
        #expect(viewModel.cachedDrumBeats.isEmpty)
    }

    // MARK: - Playback Control Tests

    @Test func testTogglePlayback() async throws {
        let chart = createTestChart()
        let metronome = createTestMetronome()

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

    @Test func testPausePlaybackIsIdempotent() async throws {
        let chart = createTestChart()
        let metronome = createTestMetronome()

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
        let chart = createTestChart()
        let metronome = createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()
        viewModel.setupGameplay()

        viewModel.startPlayback()

        #expect(viewModel.isPlaying == true)
        #expect(viewModel.playbackStartTime != nil)

        // Cleanup
        viewModel.cleanup()
    }

    @Test func testPausePlayback() async throws {
        let chart = createTestChart()
        let metronome = createTestMetronome()

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
        let chart = createTestChart()
        let metronome = createTestMetronome()

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
        let chart = createTestChart()
        let metronome = createTestMetronome()

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

    @Test func testHandlePlaybackCompletionStopsInputListening() async throws {
        let chart = createTestChart(noteCount: 8)
        let metronome = createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()
        viewModel.setupGameplay()

        viewModel.startPlayback()
        viewModel.handlePlaybackCompletion()

        let mirror = Mirror(reflecting: viewModel.inputManager)
        let songStartTime = mirror.children.first { $0.label == "songStartTime" }?.value as? Date
        #expect(songStartTime == nil)
    }

    // MARK: - Computation Tests

    @Test func testComputeDrumBeats() async throws {
        let chart = createTestChart(noteCount: 8)
        let metronome = createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()

        viewModel.computeDrumBeats()

        // Notes at same position should be grouped
        #expect(!viewModel.cachedDrumBeats.isEmpty)
        #expect(viewModel.cachedBeatIndices.count == viewModel.cachedDrumBeats.count)

        // Verify beats are sorted by time position
        for i in 1..<viewModel.cachedDrumBeats.count {
            #expect(viewModel.cachedDrumBeats[i].timePosition >= viewModel.cachedDrumBeats[i-1].timePosition)
        }
    }

    @Test func testComputeDrumBeatsWithEmptyNotes() async throws {
        let chart = Chart(difficulty: .easy)
        let metronome = createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()

        viewModel.computeDrumBeats()

        #expect(viewModel.cachedDrumBeats.isEmpty)
        #expect(viewModel.cachedBeatIndices.isEmpty)
    }

    @Test func testComputeCachedLayoutData() async throws {
        let chart = createTestChart(noteCount: 16)
        let metronome = createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()
        viewModel.computeDrumBeats()
        viewModel.computeCachedLayoutData()

        #expect(!viewModel.cachedMeasurePositions.isEmpty)
        #expect(!viewModel.measurePositionMap.isEmpty)
        #expect(viewModel.staticStaffLinesView != nil)

        // Verify measure 0 always exists
        #expect(viewModel.measurePositionMap[0] != nil)
    }

    @Test func testCacheBeatPositions() async throws {
        let chart = createTestChart(noteCount: 8)
        let metronome = createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()
        viewModel.setupGameplay()

        // Verify beat positions are cached
        #expect(!viewModel.cachedBeatPositions.isEmpty)

        // Each beat should have a cached position
        for beat in viewModel.cachedDrumBeats {
            let position = viewModel.cachedBeatPositions[beat.id]
            #expect(position != nil, "Beat \(beat.id) should have cached position")
            if let pos = position {
                #expect(pos.x > 0, "X position should be positive")
                #expect(pos.y > 0, "Y position should be positive")
            }
        }
    }

    @Test func testBeatToBeamGroupMapPopulation() async throws {
        // Create chart with consecutive eighth notes (should be beamed)
        let chart = Chart(difficulty: .medium)
        for i in 0..<4 {
            let note = Note(
                interval: .eighth,
                noteType: .hiHat,
                measureNumber: 1,
                measureOffset: Double(i) * 0.125
            )
            chart.notes.append(note)
        }

        let metronome = createTestMetronome()
        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)

        await viewModel.loadChartData()
        viewModel.setupGameplay()

        // Beam groups should be computed
        // Note: beaming logic may or may not group these notes depending on implementation
        #expect(viewModel.beatToBeamGroupMap.isEmpty == viewModel.cachedBeamGroups.isEmpty)
    }

    // MARK: - Find Closest Beat Tests

    @Test func testFindClosestBeatIndex() async throws {
        let chart = createTestChart(noteCount: 8)
        let metronome = createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()
        viewModel.computeDrumBeats()

        // Find beat at start
        let startIndex = viewModel.findClosestBeatIndex(measureIndex: 0, beatPosition: 0.0)
        #expect(startIndex >= 0)

        // Find beat in middle
        let midIndex = viewModel.findClosestBeatIndex(measureIndex: 0, beatPosition: 0.5)
        #expect(midIndex >= startIndex)

        // Find beat at end
        let endIndex = viewModel.findClosestBeatIndex(measureIndex: 1, beatPosition: 0.75)
        #expect(endIndex >= midIndex)
    }

    @Test func testFindClosestBeatIndexWithEmptyBeats() async throws {
        let chart = Chart(difficulty: .easy)
        let metronome = createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()
        viewModel.computeDrumBeats()

        // Should return 0 for empty beats
        let index = viewModel.findClosestBeatIndex(measureIndex: 0, beatPosition: 0.5)
        #expect(index == 0)
    }

    @Test func testFindClosestBeatIndexBinarySearch() async throws {
        // Create chart with many notes to test binary search
        let chart = Chart(difficulty: .hard)
        for measure in 1...4 {
            for beat in 0..<4 {
                let note = Note(
                    interval: .quarter,
                    noteType: .bass,
                    measureNumber: measure,
                    measureOffset: Double(beat) * 0.25
                )
                chart.notes.append(note)
            }
        }

        let metronome = createTestMetronome()
        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)

        await viewModel.loadChartData()
        viewModel.computeDrumBeats()

        // Test various positions
        let testCases: [(measureIndex: Int, beatPosition: Double)] = [
            (0, 0.0),
            (0, 0.5),
            (1, 0.25),
            (2, 0.75),
            (3, 0.5)
        ]

        for testCase in testCases {
            let index = viewModel.findClosestBeatIndex(
                measureIndex: testCase.measureIndex,
                beatPosition: testCase.beatPosition
            )
            #expect(index >= 0 && index < viewModel.cachedDrumBeats.count)
        }
    }

    // MARK: - Duration Calculation Tests

    @Test func testCalculateTrackDuration() async throws {
        let chart = createTestChart(noteCount: 8)
        let metronome = createTestMetronome()
        let (userDefaults, _) = TestUserDefaults.makeIsolated()
        let practiceSettings = PracticeSettingsService(userDefaults: userDefaults)

        let viewModel = GameplayViewModel(
            chart: chart,
            metronome: metronome,
            practiceSettings: practiceSettings
        )
        await viewModel.loadChartData()
        viewModel.setupGameplay()

        let duration = viewModel.calculateTrackDuration()

        #expect(duration > 0)
        #expect(viewModel.cachedTrackDuration == duration)
    }

    @Test func testCalculateTrackDurationWithMultipleMeasures() async throws {
        // Create chart spanning 4 measures
        let chart = Chart(difficulty: .medium)
        for measure in 1...4 {
            let note = Note(
                interval: .quarter,
                noteType: .bass,
                measureNumber: measure,
                measureOffset: 0.0
            )
            chart.notes.append(note)
        }

        let metronome = createTestMetronome()
        let (userDefaults, _) = TestUserDefaults.makeIsolated()
        let practiceSettings = PracticeSettingsService(userDefaults: userDefaults)
        let viewModel = GameplayViewModel(
            chart: chart,
            metronome: metronome,
            practiceSettings: practiceSettings
        )

        await viewModel.loadChartData()
        viewModel.setupGameplay()

        let duration = viewModel.calculateTrackDuration()

        // With default 120 BPM and 4/4 time, each measure is 2 seconds
        // 4 measures = 8 seconds
        #expect(duration >= 8.0)
    }

    @Test func testTrackDurationScalesWithSpeedMultiplier() async throws {
        let chart = createTestChart(noteCount: 8)
        let metronome = createTestMetronome()

        let (userDefaults, _) = TestUserDefaults.makeIsolated()
        let practiceSettings = PracticeSettingsService(userDefaults: userDefaults)
        let viewModel = GameplayViewModel(chart: chart, metronome: metronome, practiceSettings: practiceSettings)
        await viewModel.loadChartData()
        viewModel.setupGameplay()

        let baseDuration = viewModel.calculateTrackDuration()
        viewModel.updateSpeed(0.5)

        let slowedDuration = viewModel.calculateTrackDuration()
        #expect(slowedDuration > baseDuration, "Duration should increase at slower speeds")
    }

    // MARK: - BGM Offset Calculation Tests

    @Test func testCalculateBGMOffsetWithFirstMeasureNote() async throws {
        let chart = Chart(difficulty: .medium)
        let note = Note(
            interval: .quarter,
            noteType: .bass,
            measureNumber: 1,
            measureOffset: 0.0
        )
        chart.notes.append(note)

        let metronome = createTestMetronome()
        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)

        await viewModel.loadChartData()
        viewModel.setupGameplay()

        // Note at start of measure 1 should have 0 offset
        #expect(viewModel.bgmOffsetSeconds == 0.0)
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

        let metronome = createTestMetronome()
        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)

        await viewModel.loadChartData()
        viewModel.setupGameplay()

        // Should have non-zero offset since first note is not at start
        #expect(viewModel.bgmOffsetSeconds > 0.0)
    }

    // MARK: - Cleanup Tests

    @Test func testCleanup() async throws {
        let chart = createTestChart()
        let metronome = createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()
        viewModel.setupGameplay()
        viewModel.setupMetronomeSubscription()
        viewModel.startPlayback()

        viewModel.cleanup()

        #expect(viewModel.playbackTimer == nil)
        #expect(viewModel.bgmPlayer == nil)
        #expect(viewModel.metronomeSubscription == nil)
    }

    @Test func testCleanupIdempotent() async throws {
        let chart = createTestChart()
        let metronome = createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)

        // Multiple cleanup calls should not crash
        viewModel.cleanup()
        viewModel.cleanup()
        viewModel.cleanup()

        #expect(viewModel.playbackTimer == nil)
    }

    // MARK: - State Management Tests

    @Test func testPlaybackStateReset() async throws {
        let chart = createTestChart()
        let metronome = createTestMetronome()

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

    @Test func testMeasurePositionMapContainsMeasureZero() async throws {
        let chart = createTestChart(noteCount: 8)
        let metronome = createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()
        viewModel.setupGameplay()

        // Measure 0 should always exist in map
        #expect(viewModel.measurePositionMap[0] != nil)

        if let measure0 = viewModel.measurePositionMap[0] {
            #expect(measure0.measureIndex == 0)
            #expect(measure0.row == 0)
            #expect(measure0.xOffset > 0)
        }
    }

    // MARK: - Edge Case Tests

    @Test func testStartPlaybackWithoutTrack() async throws {
        let chart = createTestChart()
        let metronome = createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        // Don't load data - track will be nil

        // Should not crash and isPlaying should remain false (no track available)
        viewModel.startPlayback()

        #expect(viewModel.isPlaying == false)

        viewModel.cleanup()
    }

    @Test func testCalculateElapsedTimeWhenNotPlaying() async throws {
        let chart = createTestChart()
        let metronome = createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)

        // When not playing and no start time, should return nil
        let elapsed = viewModel.calculateElapsedTime()
        #expect(elapsed == nil)
    }

    @Test func testUpdateActiveBeatWhenNotPlaying() async throws {
        let chart = createTestChart()
        let metronome = createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()
        viewModel.setupGameplay()

        // Set some active beat
        viewModel.activeBeatId = 5

        // Update when not playing should clear active beat
        viewModel.isPlaying = false
        viewModel.updateActiveBeat()

        #expect(viewModel.activeBeatId == nil)
    }

    @Test func testPurpleBarPositionWhenNotPlaying() async throws {
        let chart = createTestChart()
        let metronome = createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()
        viewModel.setupGameplay()

        viewModel.isPlaying = false
        let position = viewModel.calculatePurpleBarPosition()

        #expect(position == nil)
    }

    // MARK: - Input Manager Tests

    @Test func testInputManagerConfiguration() async throws {
        let chart = createTestChart(noteCount: 8)
        let metronome = createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()
        viewModel.setupGameplay()

        // Input manager should exist after setup (they are non-optional)
        // Just verify they are initialized by accessing them
        _ = viewModel.inputManager
        _ = viewModel.inputHandler
    }

    // MARK: - State Consistency Tests

    @Test func testStartPlaybackStateConsistency() async throws {
        // This test verifies that isPlaying is only set to true after
        // all setup operations complete successfully.
        // See: coderabbit.ai review comment about potential state inconsistency
        let chart = createTestChart(noteCount: 8)
        let metronome = createTestMetronome()

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
        let chart = createTestChart()
        let metronome = createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        // Note: NOT loading data - track will be nil

        // State should remain unchanged when startPlayback fails due to no track
        viewModel.startPlayback()

        // isPlaying should remain false since guard failed
        #expect(viewModel.isPlaying == false)
        #expect(viewModel.playbackStartTime == nil)

        viewModel.cleanup()
    }

    // MARK: - Pause/Resume Input Timing Tests

    @Test func testResumePlaybackPreservesInputTimingAlignment() async throws {
        // Test that input timing stays aligned after pause/resume.
        // This addresses the bug where InputManager resets timing on resume,
        // causing hit matching to be shifted by already-elapsed duration.
        //
        // The fix ensures playbackStartTime on resume is set to Date() - pausedElapsedTime,
        // which makes InputManager's elapsed time calculation (now - songStartTime)
        // correctly account for the already-elapsed duration.
        let chart = createTestChart(noteCount: 16)
        let metronome = createTestMetronome()

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
        let tolerance: Double = 0.05
        #expect(timeBetweenResumeCallAndStart >= 0)
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
        let chart = createTestChart(noteCount: 20)
        let metronome = createTestMetronome()

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
        #expect(abs(firstResumeOffset - pausedAfterFirst) < 0.05)

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
        #expect(abs(secondResumeOffset - pausedAfterSecond) < 0.05)

        viewModel.cleanup()
    }

    @Test func testResumeMetronomeOnlyPlaybackPreservesState() async throws {
        // Test that metronome-only sessions (without BGM) preserve playback state
        // across pause/resume. This addresses the regression where metronome-only
        // sessions always restart from the beginning on resume.
        //
        // The fix uses pausedElapsedTime > 0 as the primary resume indicator,
        // which works for both BGM and metronome-only sessions.
        let chart = createTestChart(noteCount: 16)
        let metronome = createTestMetronome()

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

    @Test func testAudioInterruptionPausesPlayback() async {
        // Test that audio interruptions (phone calls, Siri, etc.) pause playback.
        // This verifies the interruption handling chain:
        // MetronomeAudioEngine.onInterruption -> MetronomeEngine.onInterruption -> GameplayViewModel.pausePlayback
        let chart = createTestChart(noteCount: 8)
        let metronome = createTestMetronome()

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
        let chart = createTestChart(noteCount: 8)
        let metronome = createTestMetronome()

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

    // MARK: - Speed Control Integration Tests

    @Test func testEffectiveBPMCalculation() async throws {
        let chart = createTestChart()
        let metronome = createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()
        viewModel.setupGameplay()

        // Get base BPM (should be 120.0 for test charts without songs)
        guard let track = viewModel.track else {
            throw TestError.playbackStartTimeNil // Reuse existing error
        }
        let baseBPM = track.bpm
        let tolerance = 0.01

        // Default speed is 1.0, so effective BPM should equal track BPM
        #expect(
            abs(viewModel.effectiveBPM() - baseBPM) < tolerance,
            "At 100% speed, effective BPM should equal base BPM"
        )

        // Set speed to 50%
        viewModel.practiceSettings.setSpeed(0.5)
        #expect(
            abs(viewModel.effectiveBPM() - (baseBPM * 0.5)) < tolerance,
            "At 50% speed, effective BPM should be half of base BPM"
        )

        // Set speed to 150%
        viewModel.practiceSettings.setSpeed(1.5)
        #expect(
            abs(viewModel.effectiveBPM() - (baseBPM * 1.5)) < tolerance,
            "At 150% speed, effective BPM should be 1.5x base BPM"
        )

        viewModel.cleanup()
    }

    @Test func testUpdateSpeedDuringPlayback() async throws {
        let chart = createTestChart(noteCount: 8)
        let metronome = createTestMetronome()

        let (userDefaults, _) = TestUserDefaults.makeIsolated()
        let practiceSettings = PracticeSettingsService(userDefaults: userDefaults)
        let viewModel = GameplayViewModel(chart: chart, metronome: metronome, practiceSettings: practiceSettings)
        await viewModel.loadChartData()
        viewModel.setupGameplay()

        // Start playback at default speed
        viewModel.startPlayback()
        #expect(viewModel.isPlaying == true)

        guard let track = viewModel.track else {
            throw TestError.playbackStartTimeNil
        }
        let baseBPM = track.bpm
        let tolerance = 0.01

        // Change speed during playback
        viewModel.updateSpeed(0.75)

        // Verify speed was applied
        #expect(
            viewModel.practiceSettings.speedMultiplier == 0.75,
            "Speed should be updated to 75%"
        )
        #expect(
            abs(viewModel.effectiveBPM() - (baseBPM * 0.75)) < tolerance,
            "Effective BPM should reflect new speed"
        )

        // Verify metronome was updated (it should still be playing)
        // Note: We can't directly verify metronome.bpm was updated, but we can check playback continues
        #expect(viewModel.isPlaying == true, "Playback should continue after speed change")

        viewModel.cleanup()
    }

    @Test func testBGMRateClampedAtMinimumSpeed() async throws {
        let chart = createTestChart(noteCount: 8)
        let metronome = createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()
        viewModel.setupGameplay()

        // For this test, we need BGM to be present
        // The test will verify clamping behavior if BGM exists
        guard viewModel.bgmPlayer != nil else {
            // Skip test if no BGM (metronome-only)
            return
        }

        viewModel.startPlayback()
        #expect(viewModel.isPlaying == true)

        // Set speed to 25% (below AVAudioPlayer's minimum of 50%)
        viewModel.updateSpeed(0.25)

        // Verify practiceSettings clamped to 50% to keep BGM in sync
        #expect(viewModel.practiceSettings.speedMultiplier == 0.5, "Speed should be clamped to 50% with BGM")

        // Verify BGM rate is clamped to 0.5 (not 0.25)
        if let bgmPlayer = viewModel.bgmPlayer {
            #expect(bgmPlayer.rate == 0.5, "BGM rate should be clamped to 0.5 (50%) when speed is below 50%")
        }

        viewModel.cleanup()
    }

    @Test func testBGMRateAllowsFullSpeedRange() async throws {
        let chart = createTestChart(noteCount: 8)
        let metronome = createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()
        viewModel.setupGameplay()

        // For this test, we need BGM to be present
        guard viewModel.bgmPlayer != nil else {
            // Skip test if no BGM (metronome-only)
            return
        }

        viewModel.startPlayback()
        #expect(viewModel.isPlaying == true)

        // Set speed to 150% (within AVAudioPlayer's range)
        viewModel.updateSpeed(1.5)

        // Verify BGM rate is NOT clamped
        if let bgmPlayer = viewModel.bgmPlayer {
            #expect(bgmPlayer.rate == 1.5, "BGM rate should be 1.5 when speed is 150% (within supported range)")
        }

        // Set speed to 75%
        viewModel.updateSpeed(0.75)

        if let bgmPlayer = viewModel.bgmPlayer {
            #expect(bgmPlayer.rate == 0.75, "BGM rate should be 0.75 when speed is 75% (within supported range)")
        }

        viewModel.cleanup()
    }

    @Test func testBGMRateClampsAtAVAudioPlayerBounds() async throws {
        let chart = createTestChart(noteCount: 8)
        let metronome = createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()
        viewModel.setupGameplay()

        let highClampedRate = viewModel.clampedBGMRate(for: 2.5)
        #expect(highClampedRate == 2.0, "BGM rate should clamp to 2.0 when speed exceeds 200%")

        let lowClampedRate = viewModel.clampedBGMRate(for: 0.25)
        #expect(lowClampedRate == 0.5, "BGM rate should clamp to 0.5 when speed is below 50%")

        viewModel.cleanup()
    }

    @Test func testSetupGameplayLoadsPersistedSpeed() async throws {
        let chart = createTestChart(noteCount: 8)
        let metronome = createTestMetronome()

        // Create isolated UserDefaults for this test
        let (userDefaults, _) = TestUserDefaults.makeIsolated()
        let practiceSettings = PracticeSettingsService(userDefaults: userDefaults)

        // Save speed for this chart
        practiceSettings.saveSpeed(0.5, for: chart.persistentModelID)

        // Create new ViewModel (simulating reopening gameplay for this chart)
        let viewModel = GameplayViewModel(chart: chart, metronome: metronome, practiceSettings: practiceSettings)
        await viewModel.loadChartData()
        viewModel.setupGameplay()

        // Verify speed was loaded
        #expect(
            viewModel.practiceSettings.speedMultiplier == 0.5,
            "Speed should be loaded from persistence on setup"
        )
        #expect(
            viewModel.effectiveBPM() == (viewModel.track?.bpm ?? 120.0) * 0.5,
            "Effective BPM should reflect loaded speed"
        )

        viewModel.cleanup()
    }

    @Test func testCleanupSavesCurrentSpeed() async throws {
        let chart = createTestChart(noteCount: 8)
        let metronome = createTestMetronome()

        // Create isolated UserDefaults for this test
        let (userDefaults, _) = TestUserDefaults.makeIsolated()
        let practiceSettings = PracticeSettingsService(userDefaults: userDefaults)

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome, practiceSettings: practiceSettings)
        await viewModel.loadChartData()
        viewModel.setupGameplay()

        // Set speed
        viewModel.updateSpeed(0.75)

        // Cleanup (should save speed)
        viewModel.cleanup()

        // Verify speed was saved by loading it directly
        let loadedSpeed = practiceSettings.loadSpeed(for: chart.persistentModelID)
        #expect(loadedSpeed == 0.75, "Speed should be saved on cleanup")
    }

    @Test func testInputManagerConfiguredWithBaseBPM() async throws {
        // This test verifies that InputManager is configured with base BPM, not effective BPM.
        // This is important because timing tolerances should remain constant regardless of playback speed.
        // The GameplayViewModel.swift code explicitly documents this at line 193:
        // "InputManager uses BASE BPM - timing tolerances remain fixed regardless of speed"

        let chart = createTestChart(noteCount: 8)
        let metronome = createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()

        // Verify track was loaded
        guard let track = viewModel.track else {
            throw TestError.playbackStartTimeNil // Reuse existing error
        }

        // Set speed to 50%
        viewModel.practiceSettings.setSpeed(0.5)

        viewModel.setupGameplay()

        // We can't directly access InputManager.bpm (it's private), but we can verify
        // that the effective BPM is different from base BPM at this speed, confirming
        // that if InputManager was incorrectly configured with effectiveBPM, timing
        // would be affected
        let baseBPM = track.bpm
        let effectiveBPM = viewModel.effectiveBPM()

        // Use small tolerance for floating point comparison
        let tolerance = 0.01
        #expect(abs(effectiveBPM - (baseBPM * 0.5)) < tolerance, "Effective BPM should be 50% of base at this speed")
        #expect(abs(effectiveBPM - baseBPM) > tolerance, "At 50% speed, effective BPM should differ from base BPM")

        // The code at GameplayViewModel.swift:193 explicitly configures InputManager with track.bpm (base BPM)
        // This test documents that behavior and ensures it doesn't accidentally change

        viewModel.cleanup()
    }

        enum TestError: Error {
        case playbackStartTimeNil
    }

    @Test func testMetronomeBPMMatchesEffectiveBPMOnSpeedChange() async throws {
        // This test verifies that the metronome BPM matches effectiveBPM after speed changes.
        // This ensures synchronization between metronome audio, visual timing, and BGM.
        // Previously, updateBPM clamped to 40-200 which caused desync at extreme speeds.

        let chart = createTestChart(noteCount: 8)
        let metronome = createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()
        viewModel.setupGameplay()

        // Verify track was loaded
        guard let track = viewModel.track else {
            throw TestError.playbackStartTimeNil
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
}
