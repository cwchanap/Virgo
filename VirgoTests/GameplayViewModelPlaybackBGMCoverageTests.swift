//
//  GameplayViewModelPlaybackBGMCoverageTests.swift
//  VirgoTests
//
//  Targeted coverage for GameplayViewModel+Playback.swift and +BGM.swift.
//  Avoids duplicating branches already covered by the existing playback,
//  resume, BGM-timeline, and coverage-additions suites.
//

import Testing
import Foundation
import AVFoundation
@testable import Virgo

@Suite("Playback Coverage Additions 2", .serialized)
@MainActor
struct GameplayViewModelPlaybackCoverage2Tests {

    // MARK: - togglePlayback (lines 15–24 guard)

    @Test("togglePlayback stays stopped and does not crash when data not loaded")
    func togglePlaybackNoOpWhenNotLoaded() async throws {
        let vm = GameplayViewModelCoverageTestSupport.makeViewModel(noteCount: 4)
        // Intentionally do NOT call loadChartData; isDataLoaded stays false.
        vm.togglePlayback()
        #expect(vm.isPlaying == false)
        vm.cleanup()
    }

    // MARK: - startPlayback MIDI gating (lines 40–50)

    @Test("startPlayback surfaces MIDI alert when gating on and no source preference")
    func startPlaybackMIDIGateNoPreference() async throws {
        let vm = GameplayViewModelCoverageTestSupport.makeViewModel(noteCount: 8)
        await vm.loadChartData()
        vm.setupGameplay(loadPersistedSpeed: false)
        defer { vm.cleanup() }

        vm.inputManager.requiresMIDISourceForGameplay = true
        vm.startPlayback()

        #expect(vm.isShowingMIDIDeviceAlert == true)
        #expect(vm.midiDeviceAlertMessage == "Select your MIDI device before starting.")
        #expect(vm.isPlaying == false)
    }

    @Test("startPlayback surfaces reconnect alert when selected source is unavailable")
    func startPlaybackMIDIGateSourceUnavailable() async throws {
        // Isolated settings with a selected source that no connected device matches.
        let (settingsManager, userDefaults, suiteName) = TestInputSettingsManager.makeIsolated()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        settingsManager.setSelectedMIDISource(id: "test-midi", displayName: "Test Device")
        let inputManager = InputManager(settingsManager: settingsManager)
        inputManager.requiresMIDISourceForGameplay = true

        let vm = GameplayViewModelCoverageTestSupport.makeViewModel(noteCount: 8)
        vm.inputManager = inputManager
        await vm.loadChartData()
        vm.setupGameplay(loadPersistedSpeed: false)
        defer { vm.cleanup() }

        vm.startPlayback()

        #expect(vm.isShowingMIDIDeviceAlert == true)
        #expect(vm.midiDeviceAlertMessage == "Reconnect or select your MIDI device before starting.")
        #expect(vm.isPlaying == false)
    }

    // MARK: - startPlayback fresh vs resume (lines 73–95)

    @Test("startPlayback fresh at full speed marks session eligible for best score")
    func startPlaybackFreshFullSpeed() async throws {
        let vm = GameplayViewModelCoverageTestSupport.makeViewModel(noteCount: 8)
        await vm.loadChartData()
        vm.setupGameplay(loadPersistedSpeed: false)
        defer { vm.cleanup() }

        vm.startPlayback()

        #expect(vm.isPlaying == true)
        #expect(vm.sessionAtFullSpeed == true)
    }

    @Test("startPlayback fresh below full speed clears best-score eligibility")
    func startPlaybackFreshNonFullSpeed() async throws {
        let vm = GameplayViewModelCoverageTestSupport.makeViewModel(noteCount: 8)
        await vm.loadChartData()
        vm.setupGameplay(loadPersistedSpeed: false)
        defer { vm.cleanup() }

        vm.practiceSettings.setSpeed(0.75)
        vm.startPlayback()

        #expect(vm.isPlaying == true)
        #expect(vm.sessionAtFullSpeed == false)
    }

    @Test("startPlayback resume uses BGM timeline when bgmPlayer.currentTime > 0")
    func startPlaybackResumeViaBGMTimeline() async throws {
        let vm = GameplayViewModelCoverageTestSupport.makeViewModel(noteCount: 8)
        await vm.loadChartData()
        vm.setupGameplay(loadPersistedSpeed: false)
        defer { vm.cleanup() }

        let player = try GameplayViewModelTestHarness.makeSilentAudioPlayer()
        player.prepareToPlay()
        vm.bgmPlayer = player
        player.currentTime = 2.0
        vm.bgmOffsetSeconds = 0.5
        vm.cachedTrackDuration = 60.0
        vm.pausedElapsedTime = 3.0

        vm.startPlayback()

        #expect(vm.isPlaying == true)
    }

    // MARK: - handleSelectedMIDISourceDisconnect (lines 147–159)

    @Test("handleSelectedMIDISourceDisconnect is a no-op when gating is off")
    func disconnectNoOpWhenGatingOff() async throws {
        let vm = GameplayViewModelCoverageTestSupport.makeViewModel(noteCount: 4)
        await vm.loadChartData()
        vm.setupGameplay(loadPersistedSpeed: false)
        defer { vm.cleanup() }

        vm.handleSelectedMIDISourceDisconnect()

        #expect(vm.isShowingMIDIDeviceAlert == false)
        #expect(vm.midiDeviceAlertMessage.isEmpty)
    }

    @Test("handleSelectedMIDISourceDisconnect pauses and warns when playing")
    func disconnectPausesWhenPlaying() async throws {
        let vm = GameplayViewModelCoverageTestSupport.makeViewModel(noteCount: 4)
        await vm.loadChartData()
        vm.setupGameplay(loadPersistedSpeed: false)
        defer { vm.cleanup() }

        vm.inputManager.requiresMIDISourceForGameplay = true
        vm.isPlaying = true
        vm.handleSelectedMIDISourceDisconnect()

        #expect(vm.isPlaying == false)
        #expect(vm.isShowingMIDIDeviceAlert == true)
        #expect(vm.midiDeviceAlertMessage.contains("disconnected"))
    }

    @Test("handleSelectedMIDISourceDisconnect shows reselect message when not playing")
    func disconnectMessageWhenNotPlaying() async throws {
        let vm = GameplayViewModelCoverageTestSupport.makeViewModel(noteCount: 4)
        await vm.loadChartData()
        vm.setupGameplay(loadPersistedSpeed: false)
        defer { vm.cleanup() }

        vm.inputManager.requiresMIDISourceForGameplay = true
        vm.handleSelectedMIDISourceDisconnect()

        #expect(vm.isShowingMIDIDeviceAlert == true)
        #expect(vm.midiDeviceAlertMessage == "Reconnect or reselect your MIDI device before starting.")
    }

    // MARK: - restartPlayback while playing (lines 207–209)

    @Test("restartPlayback while playing restarts and keeps isPlaying true")
    func restartPlaybackWhilePlaying() async throws {
        let vm = GameplayViewModelCoverageTestSupport.makeViewModel(noteCount: 8)
        await vm.loadChartData()
        vm.setupGameplay(loadPersistedSpeed: false)
        defer { vm.cleanup() }

        vm.startPlayback()
        vm.currentBeat = 5
        vm.playbackProgress = 0.5

        vm.restartPlayback()

        #expect(vm.isPlaying == true)
        #expect(vm.currentBeat == 0)
        #expect(vm.playbackProgress == 0.0)
    }

    // MARK: - cleanup (lines 293–327)

    @Test("cleanup clears prepared state, BGM player, subscriptions, and timers")
    func cleanupClearsAllResources() async throws {
        let vm = GameplayViewModelCoverageTestSupport.makeViewModel(noteCount: 8)
        await vm.loadChartData()
        vm.setupGameplay(loadPersistedSpeed: false)
        vm.bgmPlayer = try GameplayViewModelTestHarness.makeSilentAudioPlayer()
        vm.setupMetronomeSubscription()
        vm.startPlayback()

        vm.cleanup()

        #expect(vm.isGameplayPrepared == false)
        #expect(vm.bgmPlayer == nil)
        #expect(vm.metronomeSubscription == nil)
        #expect(vm.playbackTimer == nil)
    }
}

@Suite("BGM Coverage Additions", .serialized)
@MainActor
struct GameplayViewModelBGMCoverageTests {

    // MARK: - resetPlaybackState (lines 12–29)

    @Test("resetPlaybackState zeroes all playback and scheduling fields")
    func resetPlaybackStateZeroesFields() async throws {
        let vm = GameplayViewModelCoverageTestSupport.makeViewModel(noteCount: 4)
        await vm.loadChartData()
        vm.setupGameplay(loadPersistedSpeed: false)
        defer { vm.cleanup() }

        vm.currentBeat = 5
        vm.playbackProgress = 0.5
        vm.totalBeatsElapsed = 9
        vm.currentRow = 3
        vm.purpleBarPosition = (1.0, 2.0)
        vm.lastScheduledPlaybackStartTime = CFAbsoluteTimeGetCurrent()

        vm.resetPlaybackState()

        #expect(vm.currentBeat == 0)
        #expect(vm.playbackProgress == 0.0)
        #expect(vm.totalBeatsElapsed == 0)
        #expect(vm.currentRow == 0)
        #expect(vm.purpleBarPosition == nil)
        #expect(vm.lastScheduledPlaybackStartTime == nil)
    }

    // MARK: - refreshTimingCaches (lines 31–35)

    @Test("refreshTimingCaches returns early when data not loaded")
    func refreshTimingCachesEarlyReturnWhenNotLoaded() async throws {
        let vm = GameplayViewModelCoverageTestSupport.makeViewModel(noteCount: 4)
        // Not loaded yet: guard should bail without mutating state.
        vm.refreshTimingCaches()

        #expect(vm.bgmOffsetSeconds == 0.0)
        #expect(vm.cachedTrackDuration == 0.0)
    }

    @Test("refreshTimingCaches populates duration when data is loaded")
    func refreshTimingCachesSetsDurationWhenLoaded() async throws {
        let chart = Chart(difficulty: .medium)
        chart.notes.append(Note(interval: .quarter, noteType: .bass, measureNumber: 3, measureOffset: 0.0))
        let vm = GameplayViewModelCoverageTestSupport.makeViewModel(chart: chart)
        await vm.loadChartData()
        defer { vm.cleanup() }

        vm.refreshTimingCaches()

        #expect(vm.cachedTrackDuration > 0.0)
    }

    // MARK: - enforceBGMMinimumSpeedIfNeeded (lines 39–47)

    @Test("enforceBGMMinimumSpeedIfNeeded returns nil without a BGM player")
    func enforceMinSpeedNilWithoutBGM() async throws {
        let vm = GameplayViewModelCoverageTestSupport.makeViewModel(noteCount: 4)
        await vm.loadChartData()
        vm.setupGameplay(loadPersistedSpeed: false)
        defer { vm.cleanup() }

        #expect(vm.enforceBGMMinimumSpeedIfNeeded() == nil)
    }

    @Test("enforceBGMMinimumSpeedIfNeeded clamps sub-minimum speed to 0.5")
    func enforceMinSpeedClampsLowSpeed() async throws {
        let vm = GameplayViewModelCoverageTestSupport.makeViewModel(noteCount: 4)
        await vm.loadChartData()
        vm.setupGameplay(loadPersistedSpeed: false)
        defer { vm.cleanup() }

        vm.bgmPlayer = try GameplayViewModelTestHarness.makeSilentAudioPlayer()
        vm.practiceSettings.setSpeed(0.3)

        #expect(vm.enforceBGMMinimumSpeedIfNeeded() == 0.5)
    }

    @Test("enforceBGMMinimumSpeedIfNeeded returns nil above the minimum")
    func enforceMinSpeedNilAboveMinimum() async throws {
        let vm = GameplayViewModelCoverageTestSupport.makeViewModel(noteCount: 4)
        await vm.loadChartData()
        vm.setupGameplay(loadPersistedSpeed: false)
        defer { vm.cleanup() }

        vm.bgmPlayer = try GameplayViewModelTestHarness.makeSilentAudioPlayer()
        vm.practiceSettings.setSpeed(0.75)

        #expect(vm.enforceBGMMinimumSpeedIfNeeded() == nil)
    }

    // MARK: - startBGMPlayback(track:) (lines 49–69)

    @Test("startBGMPlayback starts fresh metronome-only with no BGM and no pause")
    func startBGMMetronomeOnlyFresh() async throws {
        let spy = ScheduledMetronomeSpy()
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 4)
        let vm = GameplayViewModel(chart: chart, metronome: spy)
        await vm.loadChartData()
        defer { vm.cleanup() }

        vm.startBGMPlayback(track: vm.track!)

        #expect(spy.timelineStartAtTimeCalls.count == 1)
        #expect(vm.lastScheduledPlaybackStartTime != nil)
    }

    @Test("startBGMPlayback resumes metronome-only when pausedElapsedTime > 0")
    func startBGMMetronomeOnlyResume() async throws {
        let spy = ScheduledMetronomeSpy()
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 4)
        let vm = GameplayViewModel(chart: chart, metronome: spy)
        await vm.loadChartData()
        defer { vm.cleanup() }

        vm.pausedElapsedTime = 2.0
        vm.startBGMPlayback(track: vm.track!)

        #expect(spy.timelineStartAtTimeCalls.count == 1)
        #expect((spy.timelineStartAtTimeCalls.first?.elapsedTime ?? 0) > 0)
        #expect(vm.lastScheduledPlaybackStartTime != nil)
    }

    @Test("startBGMPlayback resumes from BGM position when currentTime > 0")
    func startBGMResumeFromPosition() async throws {
        let spy = ScheduledMetronomeSpy()
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 4)
        let vm = GameplayViewModel(chart: chart, metronome: spy)
        await vm.loadChartData()
        defer { vm.cleanup() }

        let player = try GameplayViewModelTestHarness.makeSilentAudioPlayer()
        player.prepareToPlay()
        vm.bgmPlayer = player
        player.currentTime = 1.0
        vm.startBGMPlayback(track: vm.track!)

        #expect(spy.timelineStartAtTimeCalls.count == 1)
        #expect(vm.lastScheduledPlaybackStartTime != nil)
    }

    @Test("startBGMPlayback resumes during offset when paused and currentTime 0")
    func startBGMResumeDuringOffset() async throws {
        let spy = ScheduledMetronomeSpy()
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 4)
        let vm = GameplayViewModel(chart: chart, metronome: spy)
        await vm.loadChartData()
        defer { vm.cleanup() }

        let player = try GameplayViewModelTestHarness.makeSilentAudioPlayer()
        player.prepareToPlay()
        vm.bgmPlayer = player
        vm.bgmOffsetSeconds = 2.0
        vm.pausedElapsedTime = 1.0
        vm.startBGMPlayback(track: vm.track!)

        #expect(spy.timelineStartAtTimeCalls.count == 1)
        #expect(vm.lastScheduledPlaybackStartTime != nil)
    }

    @Test("startBGMPlayback starts fresh BGM when currentTime 0 and no pause")
    func startBGMFreshStart() async throws {
        let spy = ScheduledMetronomeSpy()
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 4)
        let vm = GameplayViewModel(chart: chart, metronome: spy)
        await vm.loadChartData()
        defer { vm.cleanup() }

        let player = try GameplayViewModelTestHarness.makeSilentAudioPlayer()
        player.prepareToPlay()
        vm.bgmPlayer = player
        vm.bgmOffsetSeconds = 0.5
        vm.startBGMPlayback(track: vm.track!)

        #expect(spy.timelineStartAtTimeCalls.count == 1)
        #expect(vm.lastScheduledPlaybackStartTime != nil)
    }

    // MARK: - convertToAudioPlayerDeviceTime (lines 171–176)

    @Test("convertToAudioPlayerDeviceTime maps CF time onto the audio device clock")
    func convertToAudioPlayerDeviceTimeAccuracy() async throws {
        let vm = GameplayViewModelCoverageTestSupport.makeViewModel(noteCount: 4)
        await vm.loadChartData()
        defer { vm.cleanup() }

        let player = try GameplayViewModelTestHarness.makeSilentAudioPlayer()
        player.prepareToPlay()
        let cfTime = CFAbsoluteTimeGetCurrent() + 1.0
        let deviceTime = vm.convertToAudioPlayerDeviceTime(cfTime, bgmPlayer: player)
        let expected = player.deviceCurrentTime + 1.0

        #expect(abs(deviceTime - expected) < 0.05)
    }

    // MARK: - remainingBGMOffset clamp (lines 180–182)

    @Test("remainingBGMOffset clamps to zero when paused time exceeds the offset")
    func remainingBGMOffsetClampsToZero() async throws {
        let vm = GameplayViewModelCoverageTestSupport.makeViewModel(noteCount: 4)
        await vm.loadChartData()
        defer { vm.cleanup() }

        vm.bgmOffsetSeconds = 2.0
        vm.pausedElapsedTime = 3.0

        #expect(vm.remainingBGMOffset() == 0.0)
    }

    // MARK: - setupBGMPlayer (lines 186–207)

    @Test("setupBGMPlayer is a no-op when cachedSong is nil")
    func setupBGMPlayerNoOpWhenSongNil() async throws {
        let vm = GameplayViewModelCoverageTestSupport.makeViewModel(noteCount: 4)
        await vm.loadChartData()
        defer { vm.cleanup() }

        vm.cachedSong = nil
        vm.setupBGMPlayer()

        #expect(vm.bgmPlayer == nil)
    }

    @Test("setupBGMPlayer is a no-op when bgmFilePath is empty")
    func setupBGMPlayerNoOpWhenPathEmpty() async throws {
        let vm = GameplayViewModelCoverageTestSupport.makeViewModel(noteCount: 4)
        await vm.loadChartData()
        defer { vm.cleanup() }

        vm.cachedSong = Song(title: "T", artist: "A", bpm: 120, duration: "1:00", genre: "Rock", bgmFilePath: "")
        vm.setupBGMPlayer()

        #expect(vm.bgmPlayer == nil)
    }

    @Test("setupBGMPlayer loads a player from a valid WAV file")
    func setupBGMPlayerLoadsFromValidFile() async throws {
        let vm = GameplayViewModelCoverageTestSupport.makeViewModel(noteCount: 4)
        await vm.loadChartData()
        defer { vm.cleanup() }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("bgm-\(UUID().uuidString).wav")
        try GameplayViewModelTestHarness.makeSilentWAVData().write(to: url)
        vm.cachedSong = Song(title: "T", artist: "A", bpm: 120, duration: "1:00", genre: "Rock", bgmFilePath: url.path)

        vm.setupBGMPlayer()

        #expect(vm.bgmPlayer != nil)
        try? FileManager.default.removeItem(at: url)
    }
}
