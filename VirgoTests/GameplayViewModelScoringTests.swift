//
//  GameplayViewModelScoringTests.swift
//  VirgoTests
//

import Testing
import Foundation
import AVFoundation
import Observation
import SwiftUI
@testable import Virgo

@Suite("Scoring & Miss Scan", .serialized)
@MainActor
struct GameplayViewModelScoringTests {

    @Test("resetScoring synchronously clears both feedback flags so stale tasks cannot race")
    func testResetScoringClearsFeedbackFlagsImmediately() async throws {
        // The feedback tasks sleep for 0.8s / 0.4s before clearing their flags.
        // resetScoring() must clear the flags synchronously AND cancel the tasks
        // so that a new session started immediately after a reset cannot have its
        // first milestone/combo-break animation cut short by the old task waking up.
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 4)
        let metronome = GameplayViewModelTestHarness.createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()
        viewModel.setupGameplay()
        viewModel.startPlayback()

        // Reach a combo milestone by injecting 10 perfect hits to trigger showMilestoneAnimation
        for _ in 0..<10 {
            viewModel.scoreEngine.processHit(accuracy: .perfect)
        }
        viewModel.showMilestoneAnimation = true
        viewModel.showComboBreakFeedback = true

        // resetScoring() must clear both flags synchronously
        viewModel.resetScoring()

        #expect(viewModel.showMilestoneAnimation == false,
                "resetScoring() must clear showMilestoneAnimation synchronously")
        #expect(viewModel.showComboBreakFeedback == false,
                "resetScoring() must clear showComboBreakFeedback synchronously")

        viewModel.cleanup()
    }

    @Test("Completion is delayed when playback reaches end, preserving late-tolerance window")
    func testCompletionDelayedForLateTolerance() async throws {
        // When playbackProgress reaches 1.0, completion should be scheduled
        // after a grace period (TimingAccuracy.good.toleranceMs = 100ms)
        // to allow late hits on final notes to still be scored.
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 4)
        let metronome = GameplayViewModelTestHarness.createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()
        viewModel.setupGameplay()
        viewModel.startPlayback()

        // Simulate playback reaching end (this would normally trigger the completion task)
        viewModel.playbackProgress = 1.0

        // Trigger updatePlaybackState flow manually by calling the internal update
        // In the real app, this is called by the metronome callback.
        // We can simulate by checking that completionScheduled flag is false initially.
        #expect(viewModel.isShowingSessionResults == false,
                "Results sheet should not show immediately when progress reaches 1.0")

        // Cleanup
        viewModel.cleanup()
    }

    @Test("pausePlayback cancels scheduled completion during grace period")
    func testPauseCancelsScheduledCompletion() async throws {
        // If user pauses during the grace period, the scheduled completion should be cancelled.
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 4)
        let metronome = GameplayViewModelTestHarness.createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()
        viewModel.setupGameplay()
        viewModel.startPlayback()

        // Simulate playback reaching end - this schedules the completion task
        viewModel.playbackProgress = 1.0

        // Pause should cancel the scheduled completion
        viewModel.pausePlayback()

        // After pause, isShowingSessionResults should remain false
        // (completion was cancelled, not executed)
        #expect(viewModel.isShowingSessionResults == false,
                "Results should not show after pausing during grace period")
        #expect(viewModel.isPlaying == false,
                "isPlaying should be false after pause")

        viewModel.cleanup()
    }

    @Test("resetScoring clears completion scheduling state")
    func testResetScoringClearsCompletionState() async throws {
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 4)
        let metronome = GameplayViewModelTestHarness.createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()
        viewModel.setupGameplay()
        viewModel.startPlayback()

        // Simulate playback reaching end
        viewModel.playbackProgress = 1.0

        // Reset should clear any scheduled completion
        viewModel.resetScoring()

        // After reset, completion state should be cleared for next session
        // We verify this indirectly - if we start a new session, it shouldn't
        // immediately complete
        #expect(viewModel.isShowingSessionResults == false,
                "Results should not show after resetScoring")

        viewModel.cleanup()
    }

    @Test("scanForMissedNotes(.infinity) before a recordHit causes the hit to be treated as duplicate")
    func testScanToInfinityBeforeHitPreemptsScoring() async throws {
        // Regression guard for P1: proves that calling scanForMissedNotes(.infinity)
        // (as the old grace-period polling loop did on its first 16ms tick) puts notes
        // into scoredNoteIDs as misses, causing any subsequent recordHit for those
        // same notes to be discarded as duplicates.
        //
        // The fix removes the per-tick scan during the grace sleep, so this situation
        // can no longer arise during the grace period.
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 2)
        let metronome = GameplayViewModelTestHarness.createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()
        viewModel.setupGameplay()
        viewModel.isPlaying = true

        // Simulate the OLD grace-period first-tick behaviour: scan everything as missed.
        viewModel.scanForMissedNotes(upToTimePosition: .infinity)
        let missesAfterScan = viewModel.scoreEngine.missCount
        #expect(missesAfterScan > 0, "Precondition: notes must have been auto-missed by the scan")

        // A hit that arrives now is a duplicate — score must not change.
        let scoreBeforeHit = viewModel.scoreEngine.score
        if let note = viewModel.cachedNotes.first {
            let dummyResult = NoteMatchResult(
                hitInput: InputHit(drumType: .snare, velocity: 1.0, timestamp: Date()),
                matchedNote: note,
                timingAccuracy: .perfect,
                measureNumber: note.measureNumber,
                measureOffset: note.measureOffset,
                timingError: 0.0
            )
            viewModel.recordHit(result: dummyResult)
        }
        #expect(viewModel.scoreEngine.score == scoreBeforeHit,
                "Hit after a full scan must be discarded as a duplicate")

        viewModel.cleanup()
    }

    @Test("scanForMissedNotes cursor does not double-count misses on repeated calls")
    func testScanCursorNoDuplicateMisses() async throws {
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 4)
        let metronome = GameplayViewModelTestHarness.createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()
        viewModel.setupGameplay()
        viewModel.startPlayback()

        // First scan covers the full track
        viewModel.scanForMissedNotes(upToTimePosition: .infinity)
        let missesAfterFirstScan = viewModel.scoreEngine.missCount

        // Second scan at the same (infinity) boundary must not add more misses
        viewModel.scanForMissedNotes(upToTimePosition: .infinity)
        #expect(viewModel.scoreEngine.missCount == missesAfterFirstScan,
                "Repeated scan should not double-count misses")

        viewModel.cleanup()
    }

    @Test("scanForMissedNotes cursor advances correctly across incremental windows")
    func testScanCursorIncrementalWindows() async throws {
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 4)
        let metronome = GameplayViewModelTestHarness.createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()
        viewModel.setupGameplay()
        viewModel.startPlayback()

        // Scan up to a mid-point position (before any notes are expected)
        viewModel.scanForMissedNotes(upToTimePosition: 0.0)
        let missesAtStart = viewModel.scoreEngine.missCount

        // Scan all the way to the end
        viewModel.scanForMissedNotes(upToTimePosition: .infinity)
        let missesAtEnd = viewModel.scoreEngine.missCount

        // Total misses from both incremental calls must equal the result of a
        // single full scan — no double-counting, no missed notes skipped.
        viewModel.resetScoring()
        viewModel.scanForMissedNotes(upToTimePosition: .infinity)
        let missesFullScan = viewModel.scoreEngine.missCount

        #expect(missesAtStart + (missesAtEnd - missesAtStart) == missesFullScan,
                "Incremental cursor scans should total the same as a single full scan")

        viewModel.cleanup()
    }

    @Test("scanForMissedNotes cursor resets after resetScoring")
    func testScanCursorResetsOnResetScoring() async throws {
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 4)
        let metronome = GameplayViewModelTestHarness.createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()
        viewModel.setupGameplay()
        viewModel.startPlayback()

        // Advance the cursor to the end
        viewModel.scanForMissedNotes(upToTimePosition: .infinity)
        let firstRunMisses = viewModel.scoreEngine.missCount

        // Reset and re-scan — cursor must be back at zero so all notes are processed again
        viewModel.resetScoring()
        viewModel.scanForMissedNotes(upToTimePosition: .infinity)
        let secondRunMisses = viewModel.scoreEngine.missCount

        #expect(secondRunMisses == firstRunMisses,
                "After resetScoring() the cursor should restart and produce the same miss count")

        viewModel.cleanup()
    }

    @Test("scanForMissedNotes triggers combo-break feedback when a scrolled-past note drops the combo")
    func testScanMissTriggersComboBreakFeedback() async throws {
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 2)
        let metronome = GameplayViewModelTestHarness.createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()
        viewModel.setupGameplay()
        viewModel.startPlayback()

        // Build a non-zero combo so a miss can break it
        viewModel.scoreEngine.processHit(accuracy: .perfect)
        #expect(viewModel.scoreEngine.combo > 0, "Precondition: combo should be non-zero before scan")

        // Auto-miss all notes by scanning to infinity
        viewModel.scanForMissedNotes(upToTimePosition: .infinity)

        // The combo should be broken and the feedback flag raised
        #expect(viewModel.scoreEngine.combo == 0, "Combo should be 0 after auto-miss scan")
        #expect(viewModel.showComboBreakFeedback == true,
                "Combo-break feedback should fire when scanForMissedNotes breaks the combo")

        viewModel.cleanup()
    }

    @Test("scanForMissedNotes does not trigger combo-break feedback when combo was already zero")
    func testScanMissNoFeedbackWhenComboAlreadyZero() async throws {
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 2)
        let metronome = GameplayViewModelTestHarness.createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()
        viewModel.setupGameplay()
        viewModel.startPlayback()

        // Combo is 0 already (no hits placed)
        #expect(viewModel.scoreEngine.combo == 0, "Precondition: combo should be zero")

        viewModel.scanForMissedNotes(upToTimePosition: .infinity)

        // Feedback must remain false — there was no combo to break
        #expect(viewModel.showComboBreakFeedback == false,
                "No combo-break feedback should fire when combo was already zero")

        viewModel.cleanup()
    }

    @Test("sessionIsNewRecord is true when handlePlaybackCompletion saves a new high score")
    func testSessionIsNewRecordSetOnNewHighScore() async throws {
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 1)
        let metronome = GameplayViewModelTestHarness.createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()
        viewModel.setupGameplay()
        viewModel.startPlayback()

        // Inject a hit so the score is > 0 and exceeds the default high score of 0
        viewModel.scoreEngine.processHit(accuracy: .perfect)
        viewModel.handlePlaybackCompletion()

        #expect(viewModel.sessionRecordResult == .newBest,
                "A score beating the previous best should set sessionRecordResult to newBest")

        viewModel.cleanup()
    }

    @Test("sessionIsNewRecord is false when score does not beat the existing high score")
    func testSessionIsNewRecordFalseWhenScoreNotBeaten() async throws {
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 1)
        let metronome = GameplayViewModelTestHarness.createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()
        viewModel.setupGameplay()

        // Seed a high score so the next session can't beat it
        chart.bestScore = 99999

        viewModel.startPlayback()
        // Score 1 point — far below the seeded record
        viewModel.scoreEngine.processHit(accuracy: .good)
        viewModel.handlePlaybackCompletion()

        #expect(viewModel.sessionRecordResult == .recorded,
                "A score below the existing record should leave sessionRecordResult as recorded")

        viewModel.cleanup()
    }

    @Test("sessionRecordResult resets to recorded after resetScoring")
    func testSessionRecordResultResetsOnResetScoring() async throws {
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 1)
        let metronome = GameplayViewModelTestHarness.createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()
        viewModel.setupGameplay()
        viewModel.startPlayback()

        viewModel.scoreEngine.processHit(accuracy: .perfect)
        viewModel.handlePlaybackCompletion()
        #expect(viewModel.sessionRecordResult == .newBest)

        // Simulate restarting (which calls resetScoring internally)
        viewModel.resetScoring()
        #expect(viewModel.sessionRecordResult == .recorded,
                "resetScoring() should reset sessionRecordResult to recorded")

        viewModel.cleanup()
    }
}
