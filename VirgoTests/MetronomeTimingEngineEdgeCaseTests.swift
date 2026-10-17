//
//  MetronomeTimingEngineEdgeCaseTests.swift
//  VirgoTests
//
//  Split from MetronomeTimingEngineTests to keep each file under the SwiftLint
//  file-length warn limit (600).
//

import Testing
import Foundation
import AVFoundation
@testable import Virgo

private func expectedHostTime(
    referenceCF: CFAbsoluteTime,
    referenceHost: UInt64,
    deltaSeconds: Double
) -> UInt64 {
    var timebase = mach_timebase_info_data_t()
    _ = mach_timebase_info(&timebase)
    let deltaNanoseconds = deltaSeconds * Double(NSEC_PER_SEC)
    let deltaTicks = Int64(deltaNanoseconds * Double(timebase.denom) / Double(timebase.numer))
    return deltaTicks >= 0
        ? referenceHost + UInt64(deltaTicks)
        : referenceHost - UInt64(-deltaTicks)
}

/// Playback-guard, property-didSet restart, simulateTestBeat, host-time
/// conversion, and static-helper edge-case ownership, consolidated from the
/// campaign MetronomeEngineCoverageAdditionsTests plus the timing engine's
/// static-helper block: folding these into
/// `MetronomeTimingEngineTests` would breach its SwiftLint type_body_length
/// ERROR limit and keeping them in the same file breached file_length.
/// The three static-helper superset tests here are the covering owners for
/// the deleted PatchCoverageAdditionsTests subsumers — they must never be
/// dropped.
@Suite("Metronome Timing Engine Edge Case Tests", .serialized)
@MainActor
struct MetronomeTimingEngineEdgeCaseTests {

    // MARK: - hostTime(forCFAbsoluteTime:) conversion

    @Test("hostTime adds delta ticks for a future target")
    func hostTimeConvertsFutureTarget() {
        let referenceCF: CFAbsoluteTime = 5_000.0
        let referenceHost: UInt64 = 5_000_000_000
        let deltaSeconds: Double = 1.0
        let expected = expectedHostTime(
            referenceCF: referenceCF,
            referenceHost: referenceHost,
            deltaSeconds: deltaSeconds
        )

        let result = MetronomeTimingEngine.hostTime(
            forCFAbsoluteTime: referenceCF + deltaSeconds,
            referenceCFTime: referenceCF,
            referenceHostTime: referenceHost
        )

        #expect(result == expected, "Future target should map to referenceHostTime + delta ticks")
    }

    @Test("hostTime subtracts delta ticks for a slightly-past target (not referenceHostTime)")
    func hostTimeConvertsSlightlyPastTargetToSubtractedHostTime() {
        let referenceCF: CFAbsoluteTime = 5_000.0
        let referenceHost: UInt64 = 5_000_000_000
        let deltaSeconds: Double = -0.005 // 5ms before the reference

        let result = MetronomeTimingEngine.hostTime(
            forCFAbsoluteTime: referenceCF + deltaSeconds,
            referenceCFTime: referenceCF,
            referenceHostTime: referenceHost
        )

        let expected = expectedHostTime(
            referenceCF: referenceCF,
            referenceHost: referenceHost,
            deltaSeconds: deltaSeconds
        )
        #expect(
            result == expected,
            "Slightly-past target must map to referenceHostTime - |delta|, not referenceHostTime"
        )
        #expect(result != referenceHost, "A non-zero negative delta must not collapse to referenceHostTime")
    }

    @Test("hostTime clamps to 0 when a past target would underflow the host-time epoch")
    func hostTimeClampsToZeroOnUnderflow() {
        let referenceCF: CFAbsoluteTime = 5_000.0
        let referenceHost: UInt64 = 100
        let result = MetronomeTimingEngine.hostTime(
            forCFAbsoluteTime: referenceCF - 10.0,
            referenceCFTime: referenceCF,
            referenceHostTime: referenceHost
        )

        #expect(result == 0, "A past target that underflows must clamp to 0")
    }

    // MARK: - audioTime(forIdealBeatTime:)

    @Test("audioTime returns nil for a stale beat time that clamps to mach zero")
    func audioTimeReturnsNilForStaleBeat() {
        // Derive the stale input from the machine's uptime: a beat time more
        // than `uptime` seconds in the past always underflows the mach
        // host-time epoch and clamps to 0, regardless of when the machine
        // booted or what the wall clock reads. A fixed absolute time like
        // 999.0 would only underflow while uptime stays under ~26 years.
        var timebase = mach_timebase_info_data_t()
        #expect(mach_timebase_info(&timebase) == KERN_SUCCESS)
        let uptimeSeconds = Double(mach_absolute_time()) * Double(timebase.numer)
            / Double(timebase.denom) / Double(NSEC_PER_SEC)
        let staleBeatTime = CFAbsoluteTimeGetCurrent() - uptimeSeconds - 60.0

        let audioTime = MetronomeTimingEngine.audioTime(forIdealBeatTime: staleBeatTime)
        #expect(audioTime == nil, "A beat time before the reference should not produce a valid audio time")
    }

    @Test("audioTime returns a valid time for a future beat")
    func audioTimeReturnsValidTimeForFutureBeat() {
        let futureTime = CFAbsoluteTimeGetCurrent() + 1.0
        let audioTime = MetronomeTimingEngine.audioTime(forIdealBeatTime: futureTime)
        #expect(audioTime != nil)
        #expect(audioTime?.isHostTimeValid == true)
    }

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
}
