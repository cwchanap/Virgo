//
//  GameplayViewModelSpeedTests.swift
//  VirgoTests
//
//  Targeted unit tests for GameplayViewModel+SpeedControl.swift.
//

import Testing
import Foundation
import AVFoundation
@testable import Virgo

/// Metronome stub returning a fixed playback time to exercise the
/// metronome-time-available branch of `applySpeedChangeWhilePlaying`.
@MainActor
final class MetronomePlaybackTimeStub: MetronomeEngine {
    override func getCurrentPlaybackTime() -> TimeInterval? { 1.0 }

    override func startAtTime(
        bpm: Double,
        timeSignature: TimeSignature,
        startTime: TimeInterval,
        totalBeatsElapsed: Double
    ) {
        self.bpm = bpm
        self.timeSignature = timeSignature
    }

    override func stop() {}
}

@Suite("SpeedCoverage", .serialized)
@MainActor
struct GameplayViewModelSpeedTests {

    @Test("Paused speed changes immediately reinstall the cached timeline targets")
    func pausedSpeedChangeReconfiguresTimelineMatcher() async throws {
        let vm = GameplayViewModelCoverageTestSupport.makeViewModel(noteCount: 4)
        await vm.loadChartData()
        vm.setupGameplay(loadPersistedSpeed: false)
        defer { vm.cleanup() }
        let originalTargets = vm.cachedRhythmNoteTargets
        let target = try #require(originalTargets.dropFirst().first)

        vm.updateSpeed(0.5)

        #expect(vm.cachedRhythmNoteTargets == originalTargets)
        let result = timelineMIDIResult(
            from: vm,
            target: target,
            elapsedSeconds: target.targetSecondsAtOneX / 0.5
        )
        #expect(result?.matchedEventID == target.eventID)
        #expect(result?.matchedTargetPosition == target.position)
    }

    @Test("Playing speed changes preserve event identity without a legacy matcher transition")
    func playingSpeedChangeKeepsTimelineIdentity() async throws {
        let vm = GameplayViewModelCoverageTestSupport.makeViewModel(noteCount: 4)
        await vm.loadChartData()
        vm.setupGameplay(loadPersistedSpeed: false)
        let originalTargets = vm.cachedRhythmNoteTargets
        let target = try #require(originalTargets.dropFirst().first)
        vm.inputManager.setMIDIMapping([midiNote(for: target.drumType): target.drumType])
        vm.isPlaying = true
        defer { vm.cleanup() }

        vm.updateSpeed(0.5)

        #expect(vm.cachedRhythmNoteTargets.map(\.eventID) == originalTargets.map(\.eventID))
        let capturedHostTime = try #require(vm.lastScheduledPlaybackHostTime)
        let converter = MIDIHostTimeConverter()
        let elapsedAfterScheduledStart = target.targetSecondsAtOneX / 0.5
        let eventHostTime = converter.hostTimeByAdding(
            seconds: 0.05 + elapsedAfterScheduledStart,
            to: capturedHostTime
        )
        let result = vm.inputManager.handleMIDINoteEvent(MIDINoteEvent(
            sourceID: "speed-test",
            channel: 9,
            note: midiNote(for: target.drumType),
            velocity: 100,
            hostTime: eventHostTime
        ))
        #expect(result?.matchedEventID == target.eventID)
    }

    // MARK: - effectiveBPM()

    @Test("effectiveBPM returns 120 fallback when track is nil")
    func effectiveBPM_nilTrack_returnsFallback() {
        let vm = GameplayViewModelCoverageTestSupport.makeViewModel(noteCount: 8)
        defer { vm.cleanup() }
        #expect(abs(vm.effectiveBPM() - 120.0) < 0.001)
    }

    @Test("effectiveBPM uses track BPM after data load")
    func effectiveBPM_afterLoad_usesTrackBPM() async throws {
        let vm = GameplayViewModelCoverageTestSupport.makeViewModel(noteCount: 8)
        await vm.loadChartData()
        defer { vm.cleanup() }
        let trackBPM = try #require(vm.track?.bpm)
        #expect(abs(vm.effectiveBPM() - trackBPM) < 0.001)
    }

    // MARK: - updateSettings(_:)

    @Test("updateSettings applies speed change when reference matches")
    func updateSettings_sameReference_applies() async {
        let settings = GameplayViewModelCoverageTestSupport.makeSettings()
        let vm = GameplayViewModelCoverageTestSupport.makeViewModel(noteCount: 4, settings: settings)
        await vm.loadChartData()
        vm.setupGameplay(loadPersistedSpeed: false)
        defer { vm.cleanup() }

        settings.setSpeed(0.75)
        vm.updateSettings(settings)

        #expect(abs(vm.lastAppliedSpeedMultiplier - 0.75) < 0.001)
    }

    @Test("updateSettings is a no-op when reference differs")
    func updateSettings_differentReference_isNoOp() async {
        let vm = GameplayViewModelCoverageTestSupport.makeViewModel(noteCount: 4)
        await vm.loadChartData()
        vm.setupGameplay(loadPersistedSpeed: false)
        defer { vm.cleanup() }

        let before = vm.effectiveBPM()
        vm.updateSettings(GameplayViewModelCoverageTestSupport.makeSettings())

        #expect(abs(vm.effectiveBPM() - before) < 0.001)
    }

    // MARK: - clampedBGMRate(for:)

    @Test("clampedBGMRate clamps speeds below 0.5 up to 0.5")
    func clampedBGMRate_clampsLow() {
        let vm = GameplayViewModelCoverageTestSupport.makeViewModel(noteCount: 1)
        defer { vm.cleanup() }
        #expect(vm.clampedBGMRate(for: 0.25) == Float(0.5))
    }

    @Test("clampedBGMRate clamps speeds above 2.0 down to 2.0")
    func clampedBGMRate_clampsHigh() {
        let vm = GameplayViewModelCoverageTestSupport.makeViewModel(noteCount: 1)
        defer { vm.cleanup() }
        #expect(vm.clampedBGMRate(for: 3.0) == Float(2.0))
    }

    @Test("clampedBGMRate keeps in-range speed unchanged")
    func clampedBGMRate_keepsNormal() {
        let vm = GameplayViewModelCoverageTestSupport.makeViewModel(noteCount: 1)
        defer { vm.cleanup() }
        #expect(vm.clampedBGMRate(for: 1.0) == Float(1.0))
    }

    // MARK: - bgmTimelineElapsedTime(for:)

    @Test("bgmTimelineElapsedTime divides by speed and adds offset")
    func bgmTimelineElapsedTime_normalCase() {
        let settings = GameplayViewModelCoverageTestSupport.makeSettings()
        settings.setSpeed(0.5)
        let vm = GameplayViewModelCoverageTestSupport.makeViewModel(noteCount: 4, settings: settings)
        vm.bgmOffsetSeconds = 2.0
        defer { vm.cleanup() }

        #expect(abs(vm.bgmTimelineElapsedTime(for: 1.0) - 4.0) < 0.001)
    }

    // MARK: - elapsedBeatsForScheduling(effectiveBPM:)

    @Test("elapsedBeatsForScheduling falls back to integer beat state for invalid BPM")
    func elapsedBeatsForScheduling_invalidBPM() {
        let vm = GameplayViewModelCoverageTestSupport.makeViewModel(noteCount: 1)
        vm.totalBeatsElapsed = 4
        defer { vm.cleanup() }

        // The guard is `effectiveBPM.isFinite, effectiveBPM > 0`. Each value below
        // targets a distinct failing branch, so neither assertion is redundant.
        // 0: finite but not > 0 (the positivity branch).
        #expect(vm.elapsedBeatsForScheduling(effectiveBPM: 0) == 4.0)
        // .nan: non-finite (the isFinite branch).
        #expect(vm.elapsedBeatsForScheduling(effectiveBPM: .nan) == 4.0)
    }

    @Test("elapsedBeatsForScheduling computes elapsed beats for valid BPM")
    func elapsedBeatsForScheduling_normalCase() {
        let vm = GameplayViewModelCoverageTestSupport.makeViewModel(noteCount: 1)
        vm.pausedElapsedTime = 2.0
        defer { vm.cleanup() }

        #expect(abs(vm.elapsedBeatsForScheduling(effectiveBPM: 120) - 4.0) < 0.001)
    }

    // MARK: - rescheduleBGMForSpeedChange(commonStartTime:)

    @Test("rescheduleBGMForSpeedChange returns false when no BGM player")
    func rescheduleBGM_nilPlayer_returnsFalse() {
        let vm = GameplayViewModelCoverageTestSupport.makeViewModel(noteCount: 1)
        vm.bgmPlayer = nil
        defer { vm.cleanup() }

        let result = vm.rescheduleBGMForSpeedChange(commonStartTime: CFAbsoluteTimeGetCurrent())
        #expect(result == false)
    }

    @Test("rescheduleBGMForSpeedChange schedules with offset when remaining")
    func rescheduleBGM_withOffset_returnsTrue() throws {
        let vm = GameplayViewModelCoverageTestSupport.makeViewModel(noteCount: 1)
        let player = try GameplayViewModelTestHarness.makeSilentAudioPlayer()
        player.prepareToPlay()
        vm.bgmPlayer = player
        vm.bgmOffsetSeconds = 2.0
        vm.pausedElapsedTime = 0.0
        defer { vm.cleanup() }

        let result = vm.rescheduleBGMForSpeedChange(commonStartTime: CFAbsoluteTimeGetCurrent())
        #expect(result == true)
    }

    @Test("rescheduleBGMForSpeedChange schedules at device time when no remaining offset")
    func rescheduleBGM_zeroOffset_returnsTrue() throws {
        let vm = GameplayViewModelCoverageTestSupport.makeViewModel(noteCount: 1)
        let player = try GameplayViewModelTestHarness.makeSilentAudioPlayer()
        player.prepareToPlay()
        vm.bgmPlayer = player
        vm.bgmOffsetSeconds = 2.0
        vm.pausedElapsedTime = 2.0
        defer { vm.cleanup() }

        let result = vm.rescheduleBGMForSpeedChange(commonStartTime: CFAbsoluteTimeGetCurrent())
        #expect(result == true)
    }

    // MARK: - applySpeedChangeInternal via updateSpeed

    @Test("updateSpeed before data load is a safe no-op")
    func updateSpeed_beforeLoad_noCrash() {
        let vm = GameplayViewModelCoverageTestSupport.makeViewModel(noteCount: 4)
        defer { vm.cleanup() }

        vm.updateSpeed(0.8)

        #expect(vm.isDataLoaded == false)
    }

    @Test("updateSpeed enforces BGM minimum speed when BGM player present")
    func updateSpeed_clampsBGMMinimum() async throws {
        let vm = GameplayViewModelCoverageTestSupport.makeViewModel(noteCount: 4)
        await vm.loadChartData()
        vm.setupGameplay(loadPersistedSpeed: false)
        let player = try GameplayViewModelTestHarness.makeSilentAudioPlayer()
        player.prepareToPlay()
        vm.bgmPlayer = player
        defer { vm.cleanup() }

        vm.updateSpeed(0.3)

        #expect(abs(vm.practiceSettings.speedMultiplier - 0.5) < 0.001)
    }

    @Test("updateSpeed while playing clears sessionAtFullSpeed")
    func updateSpeed_whilePlaying_clearsFullSpeed() async throws {
        let spy = ScheduledMetronomeSpy(audioDriver: RecordingAudioDriver())
        let settings = GameplayViewModelCoverageTestSupport.makeSettings()
        let vm = GameplayViewModel(
            chart: GameplayViewModelCoverageTestSupport.makeChart(noteCount: 4),
            metronome: spy,
            practiceSettings: settings
        )
        await vm.loadChartData()
        vm.setupGameplay(loadPersistedSpeed: false)
        defer { vm.cleanup() }

        vm.isPlaying = true
        vm.updateSpeed(0.75)

        #expect(vm.sessionAtFullSpeed == false)
    }

    @Test("updateSpeed while paused scales pausedElapsedTime and sets progress")
    func updateSpeed_paused_scalesElapsedAndProgress() async {
        let vm = GameplayViewModelCoverageTestSupport.makeViewModel(noteCount: 4)
        await vm.loadChartData()
        vm.setupGameplay(loadPersistedSpeed: false)
        defer { vm.cleanup() }

        vm.pausedElapsedTime = 4.0
        vm.updateSpeed(0.5)

        #expect(abs(vm.pausedElapsedTime - 8.0) < 0.001)
        #expect(vm.playbackProgress > 0.0)
    }

    @Test("updateSpeed with zero track duration sets playbackProgress to zero")
    func updateSpeed_paused_zeroDuration_setsProgressZero() async {
        let vm = GameplayViewModelCoverageTestSupport.makeViewModel(noteCount: 4)
        await vm.loadChartData()
        vm.setupGameplay(loadPersistedSpeed: false)
        defer { vm.cleanup() }

        vm.track = nil
        vm.cachedTrackDuration = 0.0
        vm.pausedElapsedTime = 4.0
        vm.lastAppliedSpeedMultiplier = 1.0
        vm.updateSpeed(0.5)

        #expect(vm.playbackProgress == 0.0)
    }

    @Test("updateSpeed updates metronome BPM when enabled but not playing")
    func updateSpeed_metronomeEnabled_updatesBPM() async {
        let vm = GameplayViewModelCoverageTestSupport.makeViewModel(noteCount: 4)
        await vm.loadChartData()
        vm.setupGameplay(loadPersistedSpeed: false)
        defer { vm.cleanup() }

        vm.metronome.isEnabled = true
        vm.updateSpeed(0.75)

        #expect(abs(vm.metronome.bpm - vm.effectiveBPM()) < 0.001)
    }

    // MARK: - applySpeedChangeWhilePlaying

    @Test("Speed change while playing sets scheduled start time without metronome time")
    func applySpeedChangeWhilePlaying_setsScheduledStartTime() async throws {
        let spy = ScheduledMetronomeSpy(audioDriver: RecordingAudioDriver())
        let settings = GameplayViewModelCoverageTestSupport.makeSettings()
        let vm = GameplayViewModel(
            chart: GameplayViewModelCoverageTestSupport.makeChart(noteCount: 4),
            metronome: spy,
            practiceSettings: settings
        )
        await vm.loadChartData()
        vm.setupGameplay(loadPersistedSpeed: false)
        let player = try GameplayViewModelTestHarness.makeSilentAudioPlayer()
        player.prepareToPlay()
        vm.bgmPlayer = player
        vm.isPlaying = true
        defer { vm.cleanup() }

        vm.updateSpeed(0.75)

        #expect(vm.lastScheduledPlaybackStartTime != nil)
    }

    @Test("Speed change while playing consumes metronome playback time when available")
    func applySpeedChangeWhilePlaying_usesMetronomeTime() async throws {
        let stub = MetronomePlaybackTimeStub(audioDriver: RecordingAudioDriver())
        let settings = GameplayViewModelCoverageTestSupport.makeSettings()
        let vm = GameplayViewModel(
            chart: GameplayViewModelCoverageTestSupport.makeChart(noteCount: 4),
            metronome: stub,
            practiceSettings: settings
        )
        await vm.loadChartData()
        vm.setupGameplay(loadPersistedSpeed: false)
        let player = try GameplayViewModelTestHarness.makeSilentAudioPlayer()
        player.prepareToPlay()
        vm.bgmPlayer = player
        vm.isPlaying = true
        defer { vm.cleanup() }

        vm.updateSpeed(0.75)

        #expect(vm.lastScheduledPlaybackStartTime != nil)
        #expect(vm.pausedElapsedTime > 0.0)
    }

    private func timelineMIDIResult(
        from viewModel: GameplayViewModel,
        target: RhythmNoteTarget,
        elapsedSeconds: Double
    ) -> NoteMatchResult? {
        let converter = MIDIHostTimeConverter()
        let startHostTime = mach_absolute_time()
        let note = midiNote(for: target.drumType)
        viewModel.inputManager.setMIDIMapping([note: target.drumType])
        viewModel.inputManager.startListening(songStartTime: Date(), capturedHostTime: startHostTime)
        return viewModel.inputManager.handleMIDINoteEvent(MIDINoteEvent(
            sourceID: "speed-test",
            channel: 9,
            note: note,
            velocity: 100,
            hostTime: converter.hostTimeByAdding(seconds: elapsedSeconds, to: startHostTime)
        ))
    }

    private func midiNote(for drumType: DrumType) -> UInt8 {
        switch drumType {
        case .kick: 36
        case .snare: 38
        default: 42
        }
    }
}
