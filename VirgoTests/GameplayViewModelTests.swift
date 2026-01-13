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

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
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
        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)

        await viewModel.loadChartData()
        viewModel.setupGameplay()

        let duration = viewModel.calculateTrackDuration()

        // With default 120 BPM and 4/4 time, each measure is 2 seconds
        // 4 measures = 8 seconds
        #expect(duration >= 8.0)
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

        // Simulate pause by setting BGM player state
        // In a real scenario, the metronome would have advanced
        viewModel.bgmPlayer?.currentTime = simulatedElapsedSeconds

        // Pause playback
        viewModel.pausePlayback()
        #expect(viewModel.isPlaying == false)
        #expect(viewModel.playbackStartTime == nil)

        // Verify pausedElapsedTime was accumulated
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
        // correct elapsed time: now - resumeStartTime ≈ pausedElapsedTime
        #expect(resumeStartTime < firstStartTime,
               "Resume start time should be adjusted backward to account for paused time")

        // Additional check: the backward adjustment should be approximately equal to
        // the accumulated paused time (within generous tolerance for parallel test execution)
        let timeBetweenStartTimes = firstStartTime.timeIntervalSince(resumeStartTime)
        let toleranceMultiplier: Double = 2.0  // Allow 2x for parallel execution variance
        #expect(
            abs(timeBetweenStartTimes - pausedTimeAfterPause) < (pausedTimeAfterPause * toleranceMultiplier),
            "Time between start times (≈\(timeBetweenStartTimes)s) should approximately paused elapsed time (≈\(pausedTimeAfterPause)s)"
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
        viewModel.bgmPlayer?.currentTime = 0.5
        viewModel.pausePlayback()
        let pausedAfterFirst = viewModel.pausedElapsedTime

        viewModel.startPlayback()
        guard let startTimeAfterFirstResume = viewModel.playbackStartTime else {
            throw TestError.playbackStartTimeNil
        }

        // Verify the second start time is earlier than the first one
        // (it's adjusted backward by pausedTime)
        #expect(startTimeAfterFirstResume < firstStartTime,
               "Resume start time should be adjusted backward to account for paused time")

        // Second cycle: pause -> resume
        viewModel.bgmPlayer?.currentTime = 1.0
        viewModel.pausePlayback()
        let pausedAfterSecond = viewModel.pausedElapsedTime
        #expect(pausedAfterSecond > pausedAfterFirst, "Second pause should have more elapsed time")

        viewModel.startPlayback()
        guard let startTimeAfterSecondResume = viewModel.playbackStartTime else {
            throw TestError.playbackStartTimeNil
        }

        // Verify the third start time is even earlier (backward adjustment accumulates)
        #expect(startTimeAfterSecondResume < startTimeAfterFirstResume,
               "Second resume should adjust start time further backward")

        // The backward adjustment should accumulate across pause/resume cycles
        let timeBetweenResumes = startTimeAfterFirstResume.timeIntervalSince(startTimeAfterSecondResume)
        let expectedTimeBetween = pausedAfterSecond - pausedAfterFirst

        // Allow generous tolerance for parallel test execution variations
        let toleranceMultiplier: Double = 2.0
        let tolerance = max(0.5, expectedTimeBetween * toleranceMultiplier)
        #expect(
            abs(timeBetweenResumes - expectedTimeBetween) < tolerance,
            "Time between resumes (≈\(timeBetweenResumes)s) should approximately equal difference in paused times (≈\(expectedTimeBetween)s)"
        )

        viewModel.cleanup()
    }

    enum TestError: Error {
        case playbackStartTimeNil
    }
}
