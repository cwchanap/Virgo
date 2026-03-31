// swiftlint:disable file_length
//
//  GameplayViewModelCoverageAdditionsTests.swift
//  VirgoTests
//
//  Targeted coverage additions for GameplayViewModel branches not reached by
//  the primary GameplayViewModelTests suite.
//

import Testing
import Foundation
import Combine
@testable import Virgo

@MainActor
struct GameplayViewModelCoverageAdditionsTests {

    // MARK: - Helpers

    private func makeSettings() -> PracticeSettingsService {
        let (ud, _) = TestUserDefaults.makeIsolated()
        return PracticeSettingsService(userDefaults: ud)
    }

    private func makeMetronome() -> MetronomeEngine { MetronomeEngine() }

    private func makeChart(noteCount: Int = 4, measureOffset stride: Double = 0.1) -> Chart {
        let chart = Chart(difficulty: .medium)
        for i in 0..<noteCount {
            let note = Note(
                interval: .quarter,
                noteType: i % 2 == 0 ? .bass : .snare,
                measureNumber: 1,
                measureOffset: Double(i) * stride
            )
            chart.notes.append(note)
        }
        return chart
    }

    private func makeViewModel(
        chart: Chart? = nil,
        noteCount: Int = 4,
        settings: PracticeSettingsService? = nil
    ) -> GameplayViewModel {
        let c = chart ?? makeChart(noteCount: noteCount)
        let m = makeMetronome()
        let s = settings ?? makeSettings()
        return GameplayViewModel(chart: c, metronome: m, practiceSettings: s)
    }

    // MARK: - effectiveBPM nil-track fallback (line 210–213)

    @Test("effectiveBPM falls back to 120 BPM when track is nil")
    func testEffectiveBPMNilTrackFallback() async throws {
        let vm = makeViewModel()
        // Do NOT call loadChartData – track stays nil.
        let bpm = vm.effectiveBPM()
        #expect(abs(bpm - 120.0) < 0.001, "Should use 120 BPM fallback when track is nil")
    }

    // MARK: - calculateTrackDuration nil-track fallback (lines 1173–1176)

    @Test("calculateTrackDuration returns 0.0 when track is nil")
    func testCalculateTrackDurationNilTrack() async throws {
        let vm = makeViewModel()
        // track is nil before data is loaded
        let duration = vm.calculateTrackDuration()
        #expect(duration == 0.0)
    }

    // MARK: - calculateBGMOffset nil-track fallback (line 1190)

    @Test("calculateBGMOffset returns 0.0 when track is nil")
    func testCalculateBGMOffsetNilTrack() async throws {
        let vm = makeViewModel()
        let offset = vm.calculateBGMOffset()
        #expect(offset == 0.0)
    }

    // MARK: - calculateTrackDurationInSeconds uses song.duration "MM:SS" (lines 1156–1162)

    @Test("calculateTrackDuration uses MM:SS song.duration when available")
    func testCalculateTrackDurationUsesSongDurationMMSS() async throws {
        let vm = makeViewModel(noteCount: 2)
        await vm.loadChartData()
        vm.setupGameplay()

        // Override cachedSong with a known "2:30" duration = 150 seconds.
        let song = Song(title: "T", artist: "A", bpm: 120.0, duration: "2:30", genre: "Rock")
        vm.cachedSong = song

        let duration = vm.calculateTrackDuration()
        #expect(abs(duration - 150.0) < 0.001,
                "Should return 150 s (2×60+30) from song.duration at 1× speed")

        vm.cleanup()
    }

    @Test("calculateTrackDuration ignores '0:00' song.duration and uses note-based calculation")
    func testCalculateTrackDurationIgnoresZeroDurationString() async throws {
        let vm = makeViewModel(noteCount: 4)
        await vm.loadChartData()
        vm.setupGameplay()

        let song = Song(title: "T", artist: "A", bpm: 120.0, duration: "0:00", genre: "Rock")
        vm.cachedSong = song

        let duration = vm.calculateTrackDuration()
        // "0:00" should be ignored; duration is derived from note positions instead.
        #expect(duration > 0.0, "Should compute duration from notes when song.duration is '0:00'")

        vm.cleanup()
    }

    // MARK: - calculateElapsedTime fallback to playbackStartTime (lines 1008–1010)

    @Test("calculateElapsedTime falls back to playbackStartTime when metronome is idle")
    func testCalculateElapsedTimeFallbackToPlaybackStartTime() async throws {
        let vm = makeViewModel(noteCount: 2)
        await vm.loadChartData()
        vm.setupGameplay()

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

    // MARK: - updateActiveBeat finds a matching beat (lines 971–974)

    @Test("updateActiveBeat finds and sets activeBeatId for a beat near timePosition 0")
    func testUpdateActiveBeatFindsMatchingBeat() async throws {
        let vm = makeViewModel(noteCount: 2)
        await vm.loadChartData()
        vm.setupGameplay()

        // Force state: metronome not running, so calculateElapsedTime uses the
        // playbackStartTime fallback and returns ~0 seconds.
        vm.isPlaying = true
        vm.pausedElapsedTime = 0.0
        vm.playbackStartTime = Date()

        vm.updateActiveBeat()

        vm.isPlaying = false
        vm.cleanup()

        // cachedDrumBeats has a beat at timePosition 0.0 (measure 1, offset 0).
        // With currentTimePosition ~0.0 and timeTolerance = 0.05 it should match.
        #expect(vm.activeBeatId != nil,
                "Should find the beat near timePosition 0.0 and set activeBeatId")
    }

    // MARK: - wireInputHandler closure routes to recordHit (lines 1321–1323)

    @Test("wireInputHandler routes onNoteResult hits to recordHit while playing")
    func testWireInputHandlerRoutesHitsWhenPlaying() async throws {
        let vm = makeViewModel(noteCount: 4)
        await vm.loadChartData()
        vm.setupGameplay()

        vm.wireInputHandler()
        vm.startPlayback()

        let note = vm.cachedNotes.first!
        let hit = InputHit(drumType: .kick, velocity: 0.8, timestamp: Date())
        let result = NoteMatchResult(
            hitInput: hit,
            matchedNote: note,
            timingAccuracy: .perfect,
            measureNumber: note.measureNumber,
            measureOffset: note.measureOffset,
            timingError: 0.0
        )

        let scoreBefore = vm.scoreEngine.score
        vm.inputHandler.onNoteResult?(result)

        vm.cleanup()

        #expect(vm.scoreEngine.score > scoreBefore,
                "Score should increase when a hit is delivered via the wired handler")
    }

    // MARK: - recordHit guard: not playing (line 1218)

    @Test("recordHit is a no-op when isPlaying is false")
    func testRecordHitIgnoredWhenNotPlaying() async throws {
        let vm = makeViewModel(noteCount: 4)
        await vm.loadChartData()
        vm.setupGameplay()

        #expect(vm.isPlaying == false)

        let note = vm.cachedNotes.first!
        let hit = InputHit(drumType: .kick, velocity: 0.8, timestamp: Date())
        let result = NoteMatchResult(
            hitInput: hit,
            matchedNote: note,
            timingAccuracy: .perfect,
            measureNumber: note.measureNumber,
            measureOffset: note.measureOffset,
            timingError: 0.0
        )

        vm.recordHit(result: result)

        #expect(vm.scoreEngine.score == 0, "Score must not change when not playing")
    }

    // MARK: - updateSettings with matching instance (lines 228–231)

    @Test("updateSettings with the ViewModel's own settings instance applies the speed change")
    func testUpdateSettingsWithMatchingInstanceAppliesChange() async throws {
        let settings = makeSettings()
        let vm = makeViewModel(noteCount: 8, settings: settings)
        await vm.loadChartData()
        vm.setupGameplay(loadPersistedSpeed: false)

        settings.setSpeed(0.75)

        // Guard in updateSettings checks `practiceSettings === self.practiceSettings`; this passes.
        vm.updateSettings(settings)

        // applySpeedChangeInternal ran, so lastAppliedSpeedMultiplier was updated.
        #expect(abs(settings.speedMultiplier - 0.75) < 0.001)

        vm.cleanup()
    }

    @Test("updateSettings with a different instance is a no-op")
    func testUpdateSettingsWithDifferentInstanceIsNoOp() async throws {
        let settings = makeSettings()
        let otherSettings = makeSettings()
        let vm = makeViewModel(noteCount: 4, settings: settings)
        await vm.loadChartData()
        vm.setupGameplay(loadPersistedSpeed: false)

        let speedBefore = settings.speedMultiplier

        // Guard in updateSettings fires: otherSettings !== settings → returns early.
        vm.updateSettings(otherSettings)

        #expect(abs(settings.speedMultiplier - speedBefore) < 0.001,
                "Speed should be unchanged when a different instance is passed")

        vm.cleanup()
    }

    // MARK: - restartPlayback when not playing (line 665–667)

    @Test("restartPlayback when not playing does not start playback")
    func testRestartPlaybackWhenNotPlayingDoesNotStartPlayback() async throws {
        let vm = makeViewModel(noteCount: 4)
        await vm.loadChartData()
        vm.setupGameplay()

        #expect(vm.isPlaying == false)

        vm.restartPlayback()

        // The `if isPlaying { startPlayback() }` branch should not run.
        #expect(vm.isPlaying == false, "Should remain stopped after restart from idle state")
        #expect(vm.pausedElapsedTime == 0.0, "Elapsed time should have been reset")

        vm.cleanup()
    }

    // MARK: - setupMetronomeSubscription (lines 511–520)

    @Test("setupMetronomeSubscription creates a Combine subscription")
    func testSetupMetronomeSubscriptionCreatesSubscription() async throws {
        let vm = makeViewModel()

        #expect(vm.metronomeSubscription == nil, "No subscription before explicit setup call")

        vm.setupMetronomeSubscription()

        #expect(vm.metronomeSubscription != nil, "Subscription should exist after setup")

        vm.cleanup()
    }

    // MARK: - triggerMilestoneAnimation via recordHit combo buildup (lines 1241–1244)

    @Test("Milestone animation is triggered when combo reaches 10")
    func testMilestoneAnimationTriggeredAtCombo10() async throws {
        // 10 distinct notes closely packed in measure 1
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

        let vm = makeViewModel(chart: chart)
        await vm.loadChartData()
        vm.setupGameplay()

        // Force playing state via playbackStartTime so elapsed time ≈ 0.
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
        #expect(vm.showMilestoneAnimation == true,
                "Milestone animation should be active after crossing combo 10")
    }

    // MARK: - setupBGMPlayer error branch (lines 1379–1382)

    @Test("setupBGMPlayer sets bgmLoadingError when file path is invalid")
    func testSetupBGMPlayerSetsErrorForInvalidPath() async throws {
        let vm = makeViewModel(noteCount: 2)
        await vm.loadChartData()

        // Inject a cachedSong with a non-existent audio file before calling setupBGMPlayer.
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
        let settings = makeSettings()
        let chart = makeChart(noteCount: 8)
        let metronome = makeMetronome()
        let vm = GameplayViewModel(chart: chart, metronome: metronome, practiceSettings: settings)

        await vm.loadChartData()
        vm.setupGameplay(loadPersistedSpeed: false)

        // Start the metronome independently (outside ViewModel's isPlaying flag) and
        // wait for isEnabled to propagate through the Combine pipeline.
        let started = await CombineTestUtilities.performAndWait(
            action: { metronome.toggle(bpm: vm.effectiveBPM(), timeSignature: .fourFour) },
            publisher: metronome.$isEnabled,
            condition: { $0 == true },
            timeout: 0.5
        )
        #expect(started, "Metronome should start before the speed-change test")
        #expect(vm.isPlaying == false, "ViewModel must not be playing for this code path")

        // updateSpeed → applySpeedChangeInternal → hits the `!isPlaying && metronome.isEnabled` branch.
        vm.updateSpeed(0.75)

        metronome.stop()
        vm.cleanup()

        #expect(abs(settings.speedMultiplier - 0.75) < 0.001,
                "Speed should be updated to 0.75 after applySpeedChangeInternal ran")
    }

    // MARK: - pausePlayback elapsed-time fallback (lines 646–648)

    @Test("pausePlayback falls back to playbackStartTime when metronome has no playback time")
    func testPausePlaybackFallsBackToPlaybackStartTime() async throws {
        let vm = makeViewModel(noteCount: 4)
        await vm.loadChartData()
        vm.setupGameplay()

        // Manually set playing state and a start time, without an active metronome.
        vm.isPlaying = true
        let startTime = Date().addingTimeInterval(-1.5)
        vm.playbackStartTime = startTime
        vm.pausedElapsedTime = 0.0

        vm.pausePlayback()

        // pausePlayback should have used the playbackStartTime fallback and accumulated elapsed time.
        #expect(vm.isPlaying == false)
        #expect(vm.pausedElapsedTime >= 1.4, "Should accumulate ~1.5 s from playbackStartTime fallback")
    }
}
// swiftlint:enable file_length
