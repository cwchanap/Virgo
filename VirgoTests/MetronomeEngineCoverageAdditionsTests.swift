//
//  MetronomeEngineCoverageAdditionsTests.swift
//  VirgoTests
//
//  Targeted coverage additions for MetronomeTimingEngine and MetronomeAudioEngine.
//  Focuses on static helper edge cases, hostTime/audioTime conversions, playback
//  guards, restartTimer via property didSets while playing, simulateTestBeat
//  wrapping/guard branches, MetronomeBeatSchedule calculations, and
//  MetronomeAudioEngine test-environment paths.
//

import Testing
import Foundation
import AVFoundation
@testable import Virgo

@Suite("Metronome Engine Coverage Additions", .serialized)
@MainActor
struct MetronomeEngineCoverageAdditionsTests {

    // MARK: - MetronomeTimingEngine Static Helper Edge Cases

    @Test("completedBeatCount handles non-finite, negative, and near-boundary values")
    func completedBeatCountEdgeCases() {
        #expect(MetronomeTimingEngine.completedBeatCount(forTotalBeatsElapsed: .nan) == 0)
        #expect(MetronomeTimingEngine.completedBeatCount(forTotalBeatsElapsed: .infinity) == 0)
        #expect(MetronomeTimingEngine.completedBeatCount(forTotalBeatsElapsed: -.infinity) == 0)
        #expect(MetronomeTimingEngine.completedBeatCount(forTotalBeatsElapsed: -10.0) == 0)
        #expect(MetronomeTimingEngine.completedBeatCount(forTotalBeatsElapsed: 0) == 0)
        #expect(MetronomeTimingEngine.completedBeatCount(forTotalBeatsElapsed: 3.9) == 3)
        #expect(MetronomeTimingEngine.completedBeatCount(forTotalBeatsElapsed: 4.0) == 4)

        // Epsilon rounding: just-under-4 rounds up via +1e-9
        let nearFour = 4.0 - 1e-9
        #expect(MetronomeTimingEngine.completedBeatCount(forTotalBeatsElapsed: nearFour) == 4)
    }

    @Test("firstFiredBeatNumber handles non-finite, negative, and boundary values")
    func firstFiredBeatNumberEdgeCases() {
        #expect(MetronomeTimingEngine.firstFiredBeatNumber(afterTotalBeatsElapsed: .nan) == 1)
        #expect(MetronomeTimingEngine.firstFiredBeatNumber(afterTotalBeatsElapsed: .infinity) == 1)
        #expect(MetronomeTimingEngine.firstFiredBeatNumber(afterTotalBeatsElapsed: -.infinity) == 1)
        #expect(MetronomeTimingEngine.firstFiredBeatNumber(afterTotalBeatsElapsed: -5.0) == 1)
        #expect(MetronomeTimingEngine.firstFiredBeatNumber(afterTotalBeatsElapsed: 0) == 1)
        #expect(MetronomeTimingEngine.firstFiredBeatNumber(afterTotalBeatsElapsed: 3.0) == 4)
        #expect(MetronomeTimingEngine.firstFiredBeatNumber(afterTotalBeatsElapsed: 3.5) == 5)
    }

    @Test("beatInMeasure clamps non-positive beat numbers to 1")
    func beatInMeasureEdgeCases() {
        #expect(MetronomeTimingEngine.beatInMeasure(forFiredBeatNumber: 0, timeSignature: .fourFour) == 1)
        #expect(MetronomeTimingEngine.beatInMeasure(forFiredBeatNumber: -3, timeSignature: .fourFour) == 1)
        #expect(MetronomeTimingEngine.beatInMeasure(forFiredBeatNumber: 1, timeSignature: .fourFour) == 1)
        #expect(MetronomeTimingEngine.beatInMeasure(forFiredBeatNumber: 5, timeSignature: .fourFour) == 1)
        #expect(MetronomeTimingEngine.beatInMeasure(forFiredBeatNumber: 6, timeSignature: .fourFour) == 2)
    }

    // MARK: - hostTime / audioTime Static Conversions

    @Test("hostTime converts future, zero, and past deltas with explicit references")
    func hostTimeConversionBranches() {
        let refCFTime: CFAbsoluteTime = 5_000.0
        let refHostTime: UInt64 = 10_000

        // Positive delta (future) → addition path, result exceeds reference
        let futureHost = MetronomeTimingEngine.hostTime(
            forCFAbsoluteTime: refCFTime + 1.0,
            referenceCFTime: refCFTime,
            referenceHostTime: refHostTime
        )
        #expect(futureHost > refHostTime)

        // Zero delta → identity
        let sameHost = MetronomeTimingEngine.hostTime(
            forCFAbsoluteTime: refCFTime,
            referenceCFTime: refCFTime,
            referenceHostTime: refHostTime
        )
        #expect(sameHost == refHostTime)

        // Large negative delta with tiny reference → subtraction overflows → 0
        let pastHost = MetronomeTimingEngine.hostTime(
            forCFAbsoluteTime: refCFTime - 10.0,
            referenceCFTime: refCFTime,
            referenceHostTime: refHostTime
        )
        #expect(pastHost == 0)
    }

    @Test("audioTime returns non-nil AVAudioTime for future ideal beat time")
    func audioTimeFromIdealBeatTime() {
        let futureTime = CFAbsoluteTimeGetCurrent() + 2.0
        let audioTime = MetronomeTimingEngine.audioTime(forIdealBeatTime: futureTime)
        #expect(audioTime != nil)
        #expect(audioTime?.isHostTimeValid == true)
    }

    // MARK: - Playback Guards

    @Test("start() is a no-op when already playing")
    func startGuardWhenAlreadyPlaying() {
        let engine = MetronomeTimingEngine()
        engine.start()
        #expect(engine.isPlaying)

        engine.start()
        #expect(engine.isPlaying)

        engine.stop()
    }

    @Test("stop() is a no-op when not playing")
    func stopGuardWhenNotPlaying() {
        let engine = MetronomeTimingEngine()
        #expect(!engine.isPlaying)

        engine.stop()
        #expect(!engine.isPlaying)
        #expect(engine.currentBeat == 1)
    }

    // MARK: - restartTimer via Property didSet while Playing

    @Test("BPM change while playing triggers restartTimer path")
    func bpmChangeWhilePlayingRestartsTimer() {
        let engine = MetronomeTimingEngine(isTestEnvironment: false)
        engine.bpm = 200
        engine.onAudioBeat = { _, _, _ in }
        engine.onBeat = { _, _, _ in }

        engine.start()
        engine.bpm = 100
        #expect(engine.isPlaying)
        #expect(engine.bpm == 100)

        engine.stop()
    }

    @Test("timeSignature change while playing triggers restartTimer path")
    func timeSignatureChangeWhilePlayingRestartsTimer() {
        let engine = MetronomeTimingEngine(isTestEnvironment: false)
        engine.onAudioBeat = { _, _, _ in }
        engine.onBeat = { _, _, _ in }

        engine.start()
        engine.timeSignature = .threeFour
        #expect(engine.isPlaying)
        #expect(engine.timeSignature == .threeFour)
        #expect(engine.currentBeat == 1)

        engine.stop()
    }

    // MARK: - simulateTestBeat Branches

    @Test("simulateTestBeat wraps currentBeat past measure boundary")
    func simulateTestBeatWrapping() async {
        let engine = MetronomeTimingEngine()
        engine.timeSignature = .twoFour

        engine.startAtTime(startTime: CFAbsoluteTimeGetCurrent(), totalBeatsElapsed: 1)
        #expect(engine.currentBeat == 2)

        let wrapped = await TestHelpers.waitFor(
            condition: { engine.currentBeat == 1 },
            timeout: 1.0
        )
        #expect(wrapped)

        engine.stop()
    }

    @Test("simulateTestBeat skips onBeat when playback stops before Task runs")
    func simulateTestBeatGuardIsPlaying() async throws {
        let engine = MetronomeTimingEngine()
        var beatCallbackCount = 0
        engine.onBeat = { _, _, _ in beatCallbackCount += 1 }

        engine.start()
        engine.stop()

        try await Task.sleep(nanoseconds: 150_000_000)
        #expect(beatCallbackCount == 0)
    }

    // MARK: - MetronomeBeatSchedule

    @Test("MetronomeBeatSchedule computes audio targets and timer deadlines")
    func beatScheduleCalculations() {
        let schedule = MetronomeBeatSchedule(
            beatOriginTime: 100.0,
            beatInterval: 0.5,
            schedulingLeadTime: 0.04
        )

        #expect(abs(schedule.audioTargetTime(forBeatNumber: 1) - 100.0) < 0.0001)
        #expect(abs(schedule.audioTargetTime(forBeatNumber: 3) - 101.0) < 0.0001)
        #expect(abs(schedule.audioTargetTime(forBeatNumber: 0) - 100.0) < 0.0001)

        #expect(abs(schedule.timerDeadline(forBeatNumber: 1) - 99.96) < 0.0001)
        #expect(abs(schedule.timerDeadline(forBeatNumber: 3) - 100.96) < 0.0001)
    }

    // MARK: - MetronomeAudioEngine Coverage

    @Test("MetronomeAudioEngine.convertToAudioEngineTime returns nil in test environment")
    func audioEngineConvertReturnsNilInTestEnv() {
        let audioEngine = MetronomeAudioEngine()
        #expect(audioEngine.convertToAudioEngineTime(CFAbsoluteTimeGetCurrent()) == nil)
    }

    @Test("AudioEngineError produces human-readable localized descriptions")
    func audioEngineErrorDescriptions() {
        #expect(AudioEngineError.assetNotFound.errorDescription == "Ticker audio asset not found")
        #expect(AudioEngineError.bufferCreationFailed.errorDescription == "Failed to create audio buffer")
        #expect(
            AudioEngineError.audioEngineNotAvailable.errorDescription
                == "Audio engine not available in test environment"
        )

        let underlying = NSError(
            domain: "test", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "disk error"]
        )
        #expect(
            AudioEngineError.loadingFailed(underlying).errorDescription
                == "Failed to load audio buffer: disk error"
        )
    }

    @Test("MetronomeAudioEngine onInterruption defaults to nil and survives set/clear")
    func audioEngineOnInterruptionDefaultNil() {
        let audioEngine = MetronomeAudioEngine()
        #expect(audioEngine.onInterruption == nil)

        audioEngine.onInterruption = { _ in }
        #expect(audioEngine.onInterruption != nil)

        audioEngine.onInterruption = nil
        #expect(audioEngine.onInterruption == nil)
    }

    @Test("MetronomeAudioEngine init/deinit cycles in test environment do not crash")
    func audioEngineInitDeinitCycles() {
        for _ in 0..<3 {
            let engine = MetronomeAudioEngine()
            engine.playTick(volume: 0.5, isAccented: true, atTime: AVAudioTime(hostTime: 42))
            engine.resume()
            engine.stop()
        }
        #expect(Bool(true))
    }
}
