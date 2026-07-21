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

    @Test("Timeline scoring suppresses duplicate hits by event ID")
    func timelineScoringSuppressesDuplicateEventID() async throws {
        let viewModel = GameplayViewModel(
            chart: GameplayViewModelTestHarness.createTestChart(noteCount: 1),
            metronome: GameplayViewModelTestHarness.createTestMetronome()
        )
        await viewModel.loadChartData()
        viewModel.setupGameplay()
        viewModel.isPlaying = true
        defer { viewModel.cleanup() }
        let target = try #require(viewModel.cachedRhythmNoteTargets.first)
        let result = timelineResult(target: target, hitSeconds: target.targetSecondsAtOneX)

        viewModel.recordHit(result: result)
        let scoreAfterFirstHit = viewModel.scoreEngine.score
        viewModel.recordHit(result: result)

        #expect(scoreAfterFirstHit > 0)
        #expect(viewModel.scoreEngine.score == scoreAfterFirstHit)
        #expect(viewModel.scoredRhythmEventIDs == [target.eventID])
    }

    @Test("Same-time timeline events remain independently scoreable")
    func distinctSameTimeEventIDsScoreSeparately() async {
        let viewModel = GameplayViewModel(
            chart: GameplayViewModelTestHarness.createTestChart(noteCount: 1),
            metronome: GameplayViewModelTestHarness.createTestMetronome()
        )
        await viewModel.loadChartData()
        viewModel.setupGameplay()
        viewModel.isPlaying = true
        defer { viewModel.cleanup() }
        let position = RhythmEventPosition(measureIndex: 0, localTick: 0, absoluteTick: 0)
        let first = RhythmNoteTarget(
            eventID: .init(rawValue: 100),
            drumType: .kick,
            position: position,
            targetSecondsAtOneX: 0
        )
        let second = RhythmNoteTarget(
            eventID: .init(rawValue: 101),
            drumType: .snare,
            position: position,
            targetSecondsAtOneX: 0
        )

        viewModel.recordHit(result: timelineResult(target: first, hitSeconds: 0))
        viewModel.recordHit(result: timelineResult(target: second, hitSeconds: 0))

        #expect(viewModel.scoreEngine.perfectCount == 2)
        #expect(viewModel.scoredRhythmEventIDs == [first.eventID, second.eventID])
    }

    @Test("Timeline missed-note scan marks a target at the exact 100 millisecond boundary")
    func timelineMissScanIncludesExactLateBoundary() async throws {
        let chart = Chart(difficulty: .medium)
        chart.notes.append(Note(
            interval: .quarter,
            noteType: .bass,
            measureNumber: 1,
            measureOffset: 0.25
        ))
        let viewModel = GameplayViewModel(
            chart: chart,
            metronome: GameplayViewModelTestHarness.createTestMetronome()
        )
        await viewModel.loadChartData()
        viewModel.setupGameplay(loadPersistedSpeed: false)
        viewModel.isPlaying = true
        defer { viewModel.cleanup() }
        let target = try #require(viewModel.cachedRhythmNoteTargets.first)

        viewModel.scanForMissedNotes(
            upToSeconds: target.targetSecondsAtOneX + TimingAccuracy.good.toleranceMs / 1_000
        )

        #expect(viewModel.scoreEngine.missCount == 1)
        #expect(viewModel.scoredRhythmEventIDs == [target.eventID])
    }

    @Test("Timeline chart load caches a MainActor note lookup by event ID")
    func timelineChartLoadCachesNoteLookup() async throws {
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 2)
        let viewModel = GameplayViewModel(
            chart: chart,
            metronome: GameplayViewModelTestHarness.createTestMetronome()
        )
        await viewModel.loadChartData()
        defer { viewModel.cleanup() }
        let target = try #require(viewModel.cachedRhythmNoteTargets.first)

        #expect(viewModel.cachedNoteByRhythmEventID[target.eventID] != nil)
    }

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
        // When playbackProgress reaches 1.0, completion is scheduled after a grace
        // period (TimingAccuracy.good.toleranceMs = 100ms) so late hits on the final
        // notes can still be scored. We drive the real continuous-visual path (the
        // same one the metronome/tick callback uses) to prove the scheduling and the
        // delayed finalization actually run, rather than only setting a property.
        //
        // The view model is constructed with an immediate completion scheduler so the
        // grace window resolves on the next main-actor tick instead of the real
        // 100ms wall-clock delay — the delay value itself is a production constant
        // that must not be re-measured by wall-clock in a unit test (it is flaky
        // under main-actor contention when the full bundle runs in parallel). This
        // still exercises the schedule-then-defer-then-fire mechanism end to end.
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 4)
        let metronome = GameplayViewModelTestHarness.createTestMetronome()

        let viewModel = GameplayViewModel(
            chart: chart,
            metronome: metronome,
            completionScheduler: GameplayViewModelTestHarness.immediateCompletionScheduler()
        )
        await viewModel.loadChartData()
        viewModel.setupGameplay()
        viewModel.startPlayback()

        // Before reaching the end, completion is not scheduled.
        #expect(viewModel.completionScheduled == false,
                "Completion should not be scheduled before playback reaches the end")
        #expect(viewModel.isShowingSessionResults == false,
                "Results sheet should be hidden during playback")

        // Drive the continuous-visual update with an elapsed time past the track
        // duration so playbackProgress crosses 1.0 and a fresh beat advances.
        viewModel.updateContinuousVisualsForTesting(elapsedTime: viewModel.cachedTrackDuration + 1.0)

        // Scheduling must have fired, but the deferred completion must not have run
        // yet (the immediate scheduler hops to the next main-actor tick, which has
        // not happened because no `await` has occurred since scheduling).
        #expect(viewModel.completionScheduled == true,
                "Reaching the end should schedule delayed completion")
        #expect(viewModel.isShowingSessionResults == false,
                "Results sheet should stay hidden during the late-tolerance grace window")

        // Yield so the immediate scheduler's deferred action can run and finalize.
        // A short poll is robust against ordering; it exits on the first tick.
        let clock = ContinuousClock()
        let completionDeadline = clock.now.advanced(by: .seconds(1))
        while clock.now < completionDeadline && !viewModel.isShowingSessionResults {
            try await Task.sleep(for: .milliseconds(5))
        }

        #expect(viewModel.isShowingSessionResults == true,
                "Results sheet should appear once the late-tolerance grace period elapses")
        #expect(viewModel.isPlaying == false,
                "Playback should be stopped after completion")

        viewModel.cleanup()
    }

    @Test("pausePlayback cancels scheduled completion during grace period")
    func testPauseCancelsScheduledCompletion() async throws {
        // If the user pauses during the grace period, the scheduled completion task
        // must be cancelled so the results sheet never appears.
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 4)
        let metronome = GameplayViewModelTestHarness.createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()
        viewModel.setupGameplay()
        viewModel.startPlayback()

        // Schedule completion by driving playback to the end.
        viewModel.updateContinuousVisualsForTesting(elapsedTime: viewModel.cachedTrackDuration + 1.0)
        #expect(viewModel.completionScheduled == true,
                "Precondition: completion should be scheduled after reaching the end")

        // Pause must cancel the scheduled completion task.
        viewModel.pausePlayback()

        #expect(viewModel.completionScheduled == false,
                "Pause must clear the completion-scheduled flag")
        #expect(viewModel.completionTask == nil,
                "Pause must cancel and clear the completion task reference")
        #expect(viewModel.isShowingSessionResults == false,
                "Results should not show after pausing during grace period")
        #expect(viewModel.isPlaying == false,
                "isPlaying should be false after pause")

        // Wait past the original grace window to confirm the cancelled task never fires.
        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(viewModel.isShowingSessionResults == false,
                "Cancelled completion task must not show results later")

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

        // Schedule completion by driving playback to the end.
        viewModel.updateContinuousVisualsForTesting(elapsedTime: viewModel.cachedTrackDuration + 1.0)
        #expect(viewModel.completionScheduled == true,
                "Precondition: completion should be scheduled after reaching the end")

        // Reset must cancel and clear the scheduled completion for the next session.
        viewModel.resetScoring()

        #expect(viewModel.completionScheduled == false,
                "resetScoring must clear the completion-scheduled flag")
        #expect(viewModel.completionTask == nil,
                "resetScoring must cancel the completion task")
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

    private func timelineResult(target: RhythmNoteTarget, hitSeconds: Double) -> NoteMatchResult {
        NoteMatchResult(
            hitInput: InputHit(
                drumType: target.drumType,
                velocity: 1.0,
                timestamp: Date(timeIntervalSinceReferenceDate: 1_000)
            ),
            timingAccuracy: .perfect,
            timingError: 0,
            matchedEventID: target.eventID,
            matchedTargetPosition: target.position,
            matchedTargetSeconds: target.targetSecondsAtOneX,
            hitSongSeconds: hitSeconds,
            hitPosition: target.position
        )
    }
}
