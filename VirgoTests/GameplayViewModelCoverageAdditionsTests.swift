//
//  GameplayViewModelCoverageAdditionsTests.swift
//  VirgoTests
//
//  Targeted coverage additions for GameplayViewModel branches not reached by
//  the primary GameplayViewModelTests suite.
//

import Testing
import Foundation
@testable import Virgo

@Suite("GameplayViewModelCoverageAdditionsTests", .serialized)
@MainActor
struct GameplayViewModelCoverageAdditionsTests {

    @Test("GameplayViewModelCoverageTestSupport.makeViewModel uses an injected score persistence service")
    func testMakeViewModelUsesInjectedScorePersistence() async throws {
        let service = ScorePersistenceService.makeInMemory()

        let vm = GameplayViewModelCoverageTestSupport.makeViewModel(
            scorePersistence: service
        )

        #expect(vm.scorePersistence === service)
    }

    // MARK: - effectiveBPM nil-track fallback (line 210–213)

    @Test("effectiveBPM falls back to 120 BPM when track is nil")
    func testEffectiveBPMNilTrackFallback() async throws {
        let vm = GameplayViewModelCoverageTestSupport.makeViewModel()
        // Do NOT call loadChartData – track stays nil.
        let bpm = vm.effectiveBPM()
        #expect(abs(bpm - 120.0) < 0.001, "Should use 120 BPM fallback when track is nil")
    }

    // MARK: - calculateTrackDuration nil-track fallback (lines 1173–1176)

    @Test("calculateTrackDuration returns 0.0 when track is nil")
    func testCalculateTrackDurationNilTrack() async throws {
        let vm = GameplayViewModelCoverageTestSupport.makeViewModel()
        // track is nil before data is loaded
        let duration = vm.calculateTrackDuration()
        #expect(duration == 0.0)
    }

    // MARK: - calculateBGMOffset nil-track fallback (line 1190)

    @Test("calculateBGMOffset returns 0.0 when track is nil")
    func testCalculateBGMOffsetNilTrack() async throws {
        let vm = GameplayViewModelCoverageTestSupport.makeViewModel()
        let offset = vm.calculateBGMOffset()
        #expect(offset == 0.0)
    }

    // MARK: - calculateTrackDurationInSeconds uses song.duration "MM:SS" (lines 1156–1162)

    @Test("calculateTrackDuration uses MM:SS song.duration when available")
    func testCalculateTrackDurationUsesSongDurationMMSS() async throws {
        let chart = GameplayViewModelCoverageTestSupport.makeChart(noteCount: 2)
        chart.notes.forEach { $0.originKind = .dtx }
        let vm = GameplayViewModelCoverageTestSupport.makeViewModel(chart: chart)
        defer { vm.cleanup() }
        await vm.loadChartData()
        vm.setupGameplay()

        // Override cachedSong with a known "2:30" duration = 150 seconds.
        let song = Song(title: "T", artist: "A", bpm: 120.0, duration: "2:30", genre: "Rock")
        vm.cachedSong = song

        let duration = vm.calculateTrackDuration()
        #expect(abs(duration - 150.0) < 0.001,
                "Should return 150 s (2×60+30) from song.duration at 1× speed")
    }

    @Test("calculateTrackDuration ignores '0:00' song.duration and uses note-based calculation")
    func testCalculateTrackDurationIgnoresZeroDurationString() async throws {
        let vm = GameplayViewModelCoverageTestSupport.makeViewModel(noteCount: 4)
        defer { vm.cleanup() }
        await vm.loadChartData()
        vm.setupGameplay()

        let song = Song(title: "T", artist: "A", bpm: 120.0, duration: "0:00", genre: "Rock")
        vm.cachedSong = song

        let duration = vm.calculateTrackDuration()
        // 4 notes at measure 1 (offsets 0.0–0.3) → 1 measure × 2.0 s/measure at 120 BPM 4/4 = 2.0 s
        #expect(abs(duration - 2.0) < 0.001,
                "Should compute 2.0 s from note positions when song.duration is '0:00'")
    }

    // MARK: - calculateElapsedTime fallback to playbackStartTime (lines 1008–1010)

    @Test("calculateElapsedTime falls back to playbackStartTime when metronome is idle")
    func testCalculateElapsedTimeFallbackToPlaybackStartTime() async throws {
        let vm = GameplayViewModelCoverageTestSupport.makeViewModel(noteCount: 2)
        await vm.loadChartData()
        vm.setupGameplay()
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

    // MARK: - wireInputHandler closure routes to recordHit (lines 1321–1323)

    @Test("wireInputHandler routes onNoteResult hits to recordHit while playing")
    func testWireInputHandlerRoutesHitsWhenPlaying() async throws {
        let vm = GameplayViewModelCoverageTestSupport.makeViewModel(noteCount: 4)
        defer { vm.cleanup() }
        await vm.loadChartData()
        vm.setupGameplay()

        vm.wireInputHandler()
        vm.startPlayback()

        guard let note = vm.cachedNotes.first else {
            Issue.record("expected at least one cachedNote in testWireInputHandlerRoutesHitsWhenPlaying")
            return
        }
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

        #expect(vm.scoreEngine.score > scoreBefore,
                "Score should increase when a hit is delivered via the wired handler")
    }

    // MARK: - recordHit guard: not playing (line 1218)

    @Test("recordHit is a no-op when isPlaying is false")
    func testRecordHitIgnoredWhenNotPlaying() async throws {
        let vm = GameplayViewModelCoverageTestSupport.makeViewModel(noteCount: 4)
        await vm.loadChartData()
        vm.setupGameplay()
        defer { vm.cleanup() }

        #expect(vm.isPlaying == false)

        guard let note = vm.cachedNotes.first else {
            Issue.record("expected at least one cachedNote in testRecordHitIgnoredWhenNotPlaying")
            return
        }
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
        let settings = GameplayViewModelCoverageTestSupport.makeSettings()
        let vm = GameplayViewModelCoverageTestSupport.makeViewModel(noteCount: 8, settings: settings)
        defer { vm.cleanup() }
        await vm.loadChartData()
        vm.setupGameplay(loadPersistedSpeed: false)

        let bpmBefore = vm.effectiveBPM()
        #expect(abs(bpmBefore - 120.0) < 0.001, "Pre-condition: effectiveBPM should be 120 at 1× speed")

        settings.setSpeed(0.75)

        vm.updateSettings(settings)

        let bpmAfter = vm.effectiveBPM()
        #expect(abs(bpmAfter - 90.0) < 0.001,
                "effectiveBPM should be 90 (120 × 0.75) after updateSettings applied the speed change")
        #expect(bpmAfter < bpmBefore, "effectiveBPM must decrease after slowing down to 0.75×")
    }

    @Test("isFullSpeed allows tiny floating point drift around 1x")
    func testIsFullSpeedTolerance() {
        #expect(GameplayViewModel.isFullSpeed(1.0))
        #expect(GameplayViewModel.isFullSpeed(1.00005))
        #expect(!GameplayViewModel.isFullSpeed(0.9998))
        #expect(!GameplayViewModel.isFullSpeed(1.25))
    }

    @Test("active playback speed change clears full-speed score eligibility")
    func testActiveSpeedChangeClearsFullSpeedEligibility() async throws {
        let settings = GameplayViewModelCoverageTestSupport.makeSettings()
        let vm = GameplayViewModelCoverageTestSupport.makeViewModel(noteCount: 8, settings: settings)
        defer { vm.cleanup() }
        await vm.loadChartData()
        vm.setupGameplay(loadPersistedSpeed: false)

        vm.sessionAtFullSpeed = true
        vm.isPlaying = true

        settings.setSpeed(0.75)
        vm.updateSettings(settings)

        #expect(vm.sessionAtFullSpeed == false)
        vm.isPlaying = false
    }

    @Test("fresh playback eligibility follows starting speed")
    func testFreshPlaybackEligibilityFollowsStartingSpeed() async throws {
        let settings = GameplayViewModelCoverageTestSupport.makeSettings()
        settings.setSpeed(0.75)
        let vm = GameplayViewModelCoverageTestSupport.makeViewModel(noteCount: 4, settings: settings)
        defer { vm.cleanup() }
        await vm.loadChartData()
        vm.setupGameplay(loadPersistedSpeed: false)

        vm.startPlayback()

        #expect(vm.isPlaying)
        #expect(vm.sessionAtFullSpeed == false)
        vm.pausePlayback()
    }

    @Test("playback completion records score through injected persistence")
    func testPlaybackCompletionRecordsInjectedPersistenceResult() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let service = ScorePersistenceService(modelContext: context)
            let vm = GameplayViewModelCoverageTestSupport.makeViewModel(
                noteCount: 4,
                scorePersistence: service
            )
            defer { vm.cleanup() }
            await vm.loadChartData()
            vm.setupGameplay(loadPersistedSpeed: false)
            vm.isPlaying = true
            vm.sessionAtFullSpeed = true
            vm.scoreEngine.processHit(accuracy: .perfect, timingError: 0)

            vm.handlePlaybackCompletion()

            #expect(vm.sessionRecordResult == .newBest)
            #expect(vm.isShowingSessionResults)
            #expect(service.bestScore(for: vm.chart) == vm.sessionScoreSnapshot.score)
            #expect(vm.chart.scoreRecords.count == 1)
        }
    }

    // MARK: - DEBUG convenience init coverage

    @Test("DEBUG convenience init creates a view model with in-memory score persistence")
    func testDEBUGConvenienceInit() {
        let chart = GameplayViewModelCoverageTestSupport.makeChart(noteCount: 4)
        let vm = GameplayViewModel(chart: chart, metronome: MetronomeEngine(audioDriver: RecordingAudioDriver()))

        #expect(vm.chart === chart)
        #expect(vm.scorePersistence is ScorePersistenceService)
        vm.cleanup()
    }
}
