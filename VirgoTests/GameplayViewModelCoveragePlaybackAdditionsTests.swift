//
//  GameplayViewModelCoveragePlaybackAdditionsTests.swift
//  VirgoTests
//

import Testing
import Foundation
@testable import Virgo

@Suite("GameplayViewModelPlaybackCoverageTests", .serialized)
@MainActor
struct GameplayViewModelPlaybackCoverageTests {
    // MARK: - handlePlaybackCompletion session-result state (lines 1041–1049)

    @Test("handlePlaybackCompletion sets isShowingSessionResults and captures session score snapshot")
    func testHandlePlaybackCompletionSetsSessionResults() async throws {
        let vm = GameplayViewModelCoverageTestSupport.makeViewModel(noteCount: 4)
        await vm.loadChartData()
        vm.setupGameplay()
        defer { vm.cleanup() }
        vm.startPlayback()

        let note = vm.cachedNotes.first!
        let hit = InputHit(drumType: .kick, velocity: 1.0, timestamp: Date())
        let result = NoteMatchResult(
            hitInput: hit,
            matchedNote: note,
            timingAccuracy: .perfect,
            measureNumber: note.measureNumber,
            measureOffset: note.measureOffset,
            timingError: 0.0
        )
        vm.recordHit(result: result)

        let scoreAtCompletion = vm.scoreEngine.score
        #expect(scoreAtCompletion > 0, "Pre-condition: at least one hit must be recorded")

        vm.handlePlaybackCompletion()

        #expect(vm.isShowingSessionResults == true)
        #expect(vm.sessionFinalScore == scoreAtCompletion)
        #expect(vm.sessionScoreEngine.score == scoreAtCompletion)
        #expect(vm.scoreEngine.score == 0)
    }

    // MARK: - restartPlayback when not playing (line 665–667)

    @Test("restartPlayback when not playing does not start playback")
    func testRestartPlaybackWhenNotPlayingDoesNotStartPlayback() async throws {
        let vm = GameplayViewModelCoverageTestSupport.makeViewModel(noteCount: 4)
        await vm.loadChartData()
        vm.setupGameplay()

        #expect(vm.isPlaying == false)
        vm.pausedElapsedTime = 5.0

        vm.restartPlayback()

        #expect(vm.isPlaying == false, "Should remain stopped after restart from idle state")
        #expect(vm.pausedElapsedTime == 0.0, "Elapsed time should have been reset")

        vm.cleanup()
    }

    // MARK: - setupMetronomeSubscription (lines 511–520)

    @Test("setupMetronomeSubscription creates a Combine subscription")
    func testSetupMetronomeSubscriptionCreatesSubscription() async throws {
        let vm = GameplayViewModelCoverageTestSupport.makeViewModel()

        #expect(vm.metronomeSubscription == nil, "No subscription before explicit setup call")

        vm.setupMetronomeSubscription()

        #expect(vm.metronomeSubscription != nil, "Subscription should exist after setup")

        vm.cleanup()
    }

    // MARK: - triggerMilestoneAnimation via recordHit combo buildup (lines 1241–1244)

    @Test("Milestone animation is triggered when combo reaches 10")
    func testMilestoneAnimationTriggeredAtCombo10() async throws {
        let chart = Chart(difficulty: .medium)
        var notes: [Note] = []
        for i in 0..<10 {
            let note = Note(
                interval: .quarter,
                noteType: .bass,
                measureNumber: 1,
                measureOffset: Double(i) * 0.09
            )
            chart.notes.append(note)
            notes.append(note)
        }

        let vm = GameplayViewModelCoverageTestSupport.makeViewModel(chart: chart)
        await vm.loadChartData()
        vm.setupGameplay()

        vm.isPlaying = true
        vm.playbackStartTime = Date()

        for note in notes {
            let hit = InputHit(drumType: .kick, velocity: 1.0, timestamp: Date())
            let result = NoteMatchResult(
                hitInput: hit,
                matchedNote: note,
                timingAccuracy: .perfect,
                measureNumber: note.measureNumber,
                measureOffset: note.measureOffset,
                timingError: 0.0
            )
            vm.recordHit(result: result)
        }

        vm.isPlaying = false
        vm.cleanup()

        #expect(vm.scoreEngine.combo == 10, "Combo should be 10 after 10 perfect hits")
        #expect(vm.showMilestoneAnimation == true)
    }

    // MARK: - setupBGMPlayer error branch (lines 1379–1382)

    @Test("setupBGMPlayer sets bgmLoadingError when file path is invalid")
    func testSetupBGMPlayerSetsErrorForInvalidPath() async throws {
        let vm = GameplayViewModelCoverageTestSupport.makeViewModel(noteCount: 2)
        await vm.loadChartData()

        let song = Song(
            title: "T",
            artist: "A",
            bpm: 120.0,
            duration: "3:00",
            genre: "Rock",
            bgmFilePath: "/nonexistent/path/audio.ogg"
        )
        vm.cachedSong = song

        vm.setupBGMPlayer()

        #expect(vm.bgmLoadingError != nil, "bgmLoadingError should be set on AVAudioPlayer failure")
        #expect(vm.bgmPlayer == nil, "bgmPlayer should remain nil after a failed setup")
    }

    // MARK: - applySpeedChangeInternal !isPlaying && metronome.isEnabled (lines 359–361)

    @Test("Speed change calls metronome.updateBPM when metronome is enabled but ViewModel is not playing")
    func testSpeedChangeUpdatesMetronomeWhenEnabledNotPlaying() async throws {
        let settings = GameplayViewModelCoverageTestSupport.makeSettings()
        let chart = GameplayViewModelCoverageTestSupport.makeChart(noteCount: 8)
        let driver = RecordingAudioDriver()
        let metronome = GameplayViewModelCoverageTestSupport.makeMetronome(driver: driver)
        let vm = GameplayViewModel(
            chart: chart,
            metronome: metronome,
            practiceSettings: settings
        )

        await vm.loadChartData()
        vm.setupGameplay(loadPersistedSpeed: false)

        let started = await CombineTestUtilities.performAndWait(
            action: { metronome.toggle(bpm: vm.effectiveBPM(), timeSignature: .fourFour) },
            publisher: metronome.$isEnabled,
            condition: { $0 == true },
            timeout: 0.5
        )
        #expect(started, "Metronome should start before the speed-change test")
        #expect(vm.isPlaying == false, "ViewModel must not be playing for this code path")

        vm.updateSpeed(0.75)

        metronome.stop()
        vm.cleanup()

        #expect(abs(settings.speedMultiplier - 0.75) < 0.001)
        #expect(abs(metronome.bpm - 90.0) < 0.001)
        #expect(driver.resumeCallCount >= 1)
    }

    // MARK: - pausePlayback elapsed-time fallback (lines 646–648)

    @Test("pausePlayback falls back to playbackStartTime when metronome has no playback time")
    func testPausePlaybackFallsBackToPlaybackStartTime() async throws {
        let vm = GameplayViewModelCoverageTestSupport.makeViewModel(noteCount: 4)
        await vm.loadChartData()
        vm.setupGameplay()
        defer { vm.cleanup() }

        vm.isPlaying = true
        let startTime = Date().addingTimeInterval(-1.5)
        vm.playbackStartTime = startTime
        vm.pausedElapsedTime = 0.0

        vm.pausePlayback()

        #expect(vm.isPlaying == false)
        #expect(vm.pausedElapsedTime >= 1.4, "Should accumulate ~1.5 s from playbackStartTime fallback")
    }
}
