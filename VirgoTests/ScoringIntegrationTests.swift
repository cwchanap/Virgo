//
//  ScoringIntegrationTests.swift
//  VirgoTests
//
//  Integration tests for combo/scoring through GameplayViewModel.
//  Written BEFORE implementation (TDD).
//

import Testing
import Foundation
@testable import Virgo

@Suite("Scoring Integration Tests", .serialized)
@MainActor
struct ScoringIntegrationTests {

    // MARK: - Helpers

    private func makeViewModel() -> GameplayViewModel {
        let chart = Chart(difficulty: .medium)
        let (ud, _) = TestUserDefaults.makeIsolated()
        return GameplayViewModel(
            chart: chart,
            metronome: MetronomeEngine(),
            practiceSettings: PracticeSettingsService(userDefaults: ud),
            highScoreService: HighScoreService(userDefaults: ud)
        )
    }

    private func makePerfectResult() -> NoteMatchResult {
        NoteMatchResult(
            hitInput: InputHit(drumType: .snare, velocity: 1.0, timestamp: Date()),
            matchedNote: Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0.0),
            timingAccuracy: .perfect,
            measureNumber: 1,
            measureOffset: 0.0,
            timingError: 0.0
        )
    }

    private func makeGreatResult() -> NoteMatchResult {
        NoteMatchResult(
            hitInput: InputHit(drumType: .snare, velocity: 1.0, timestamp: Date()),
            matchedNote: Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0.0),
            timingAccuracy: .great,
            measureNumber: 1,
            measureOffset: 0.0,
            timingError: 30.0
        )
    }

    private func makeMissResult() -> NoteMatchResult {
        NoteMatchResult(
            hitInput: InputHit(drumType: .snare, velocity: 1.0, timestamp: Date()),
            matchedNote: nil,
            timingAccuracy: .miss,
            measureNumber: 1,
            measureOffset: 0.0,
            timingError: 999.0
        )
    }

    // MARK: - Initial State

    @Test("Initial scoring state is zero")
    func testInitialState() {
        let vm = makeViewModel()
        #expect(vm.scoreEngine.score == 0)
        #expect(vm.scoreEngine.combo == 0)
        #expect(vm.isShowingSessionResults == false)
        #expect(vm.sessionFinalScore == 0)
    }

    // MARK: - recordHit

    @Test("recordHit ignored when not playing")
    func testRecordHitIgnoredWhenNotPlaying() {
        let vm = makeViewModel()
        vm.recordHit(result: makePerfectResult())
        #expect(vm.scoreEngine.combo == 0)
        #expect(vm.scoreEngine.score == 0)
    }

    @Test("Perfect hit increments combo and adds 100 points")
    func testPerfectHitScoring() {
        let vm = makeViewModel()
        vm.isPlaying = true
        vm.recordHit(result: makePerfectResult())
        #expect(vm.scoreEngine.combo == 1)
        #expect(vm.scoreEngine.score == 100)
    }

    @Test("Great hit adds 80 points at combo 1")
    func testGreatHitScoring() {
        let vm = makeViewModel()
        vm.isPlaying = true
        vm.recordHit(result: makeGreatResult())
        #expect(vm.scoreEngine.combo == 1)
        #expect(vm.scoreEngine.score == 80)
    }

    @Test("Miss breaks combo and adds 0 points")
    func testMissBreaksCombo() {
        let vm = makeViewModel()
        vm.isPlaying = true
        // Keep results alive so their Notes share no memory address before each recordHit.
        let r1 = makePerfectResult()
        let r2 = makePerfectResult()
        vm.recordHit(result: r1)
        vm.recordHit(result: r2)
        #expect(vm.scoreEngine.combo == 2)
        let scoreBefore = vm.scoreEngine.score
        vm.recordHit(result: makeMissResult())
        #expect(vm.scoreEngine.combo == 0)
        #expect(vm.scoreEngine.score == scoreBefore)
    }

    @Test("Miss triggers showComboBreakFeedback")
    func testMissTriggersBreakFeedback() {
        let vm = makeViewModel()
        vm.isPlaying = true
        vm.recordHit(result: makePerfectResult()) // build combo first
        vm.recordHit(result: makeMissResult())
        #expect(vm.showComboBreakFeedback == true)
    }

    @Test("Combo accumulates across multiple hits")
    func testComboAccumulates() {
        let vm = makeViewModel()
        vm.isPlaying = true
        // Create all results upfront to keep Notes alive with distinct addresses.
        let results = (0..<5).map { _ in makePerfectResult() }
        for result in results {
            vm.recordHit(result: result)
        }
        #expect(vm.scoreEngine.combo == 5)
    }

    @Test("Score uses combo multiplier tier at combo 10")
    func testScoreUsesComboMultiplierAt10() {
        let vm = makeViewModel()
        vm.isPlaying = true
        // Create all results upfront to keep Notes alive with distinct addresses.
        let results = (0..<10).map { _ in makePerfectResult() }
        for result in results.prefix(9) {
            vm.recordHit(result: result)
        }
        let scoreAt9 = vm.scoreEngine.score
        vm.recordHit(result: results[9]) // combo becomes 10, tier 1.5x
        #expect(vm.scoreEngine.combo == 10)
        #expect(vm.scoreEngine.score == scoreAt9 + 150) // 100 × 1.0 × 1.5
    }

    @Test("Milestone at combo 10 sets showMilestoneAnimation")
    func testMilestoneAt10SetsFlag() {
        let vm = makeViewModel()
        vm.isPlaying = true
        // Create all results upfront to keep Notes alive with distinct addresses.
        let results = (0..<10).map { _ in makePerfectResult() }
        for result in results.prefix(9) {
            vm.recordHit(result: result)
        }
        #expect(vm.showMilestoneAnimation == false)
        vm.recordHit(result: results[9]) // combo 10
        #expect(vm.showMilestoneAnimation == true)
    }

    // MARK: - resetScoring / restartPlayback

    @Test("resetScoring zeroes all scoring state")
    func testResetScoring() {
        let vm = makeViewModel()
        vm.isPlaying = true
        let r1 = makePerfectResult()
        let r2 = makePerfectResult()
        vm.recordHit(result: r1)
        vm.recordHit(result: r2)
        vm.resetScoring()
        #expect(vm.scoreEngine.score == 0)
        #expect(vm.scoreEngine.combo == 0)
        #expect(vm.showMilestoneAnimation == false)
        #expect(vm.showComboBreakFeedback == false)
        #expect(vm.isShowingSessionResults == false)
    }

    @Test("restartPlayback resets score and combo")
    func testRestartResetsScoring() {
        let vm = makeViewModel()
        vm.isPlaying = true
        let r1 = makePerfectResult()
        let r2 = makePerfectResult()
        vm.recordHit(result: r1)
        vm.recordHit(result: r2)
        #expect(vm.scoreEngine.combo == 2)
        vm.restartPlayback()
        #expect(vm.scoreEngine.score == 0)
        #expect(vm.scoreEngine.combo == 0)
    }

    // MARK: - Session Results

    @Test("handlePlaybackCompletion sets sessionFinalScore before reset")
    func testHandlePlaybackCompletionPreservesScore() {
        let vm = makeViewModel()
        vm.isPlaying = true
        vm.recordHit(result: makePerfectResult())
        let expectedScore = vm.scoreEngine.score
        vm.handlePlaybackCompletion()
        #expect(vm.sessionFinalScore == expectedScore)
        #expect(vm.isShowingSessionResults == true)
    }

    @Test("handlePlaybackCompletion resets current score to 0")
    func testHandlePlaybackCompletionResetsCurrentScore() {
        let vm = makeViewModel()
        vm.isPlaying = true
        vm.recordHit(result: makePerfectResult())
        vm.handlePlaybackCompletion()
        #expect(vm.scoreEngine.score == 0) // reset, sessionFinalScore holds the final
    }
}
