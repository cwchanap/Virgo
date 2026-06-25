//
//  MetronomeHostTimeConversionTests.swift
//  VirgoTests
//

import Testing
import AVFoundation
@testable import Virgo

@Suite("Metronome Host Time Conversion Tests")
@MainActor
struct MetronomeHostTimeConversionTests {
    @Test("MetronomeTimingEngine converts CFAbsoluteTime to nearby mach host time")
    func testHostTimeConversionUsesMachReferenceTime() {
        let referenceCFTime: CFAbsoluteTime = 1_000.0
        let referenceHostTime: UInt64 = 10_000_000
        let targetCFTime = referenceCFTime + 0.5

        let convertedHostTime = MetronomeTimingEngine.hostTime(
            forCFAbsoluteTime: targetCFTime,
            referenceCFTime: referenceCFTime,
            referenceHostTime: referenceHostTime
        )

        let elapsedSeconds = AVAudioTime.seconds(forHostTime: convertedHostTime)
            - AVAudioTime.seconds(forHostTime: referenceHostTime)
        #expect(abs(elapsedSeconds - 0.5) < 0.001)
    }

    @Test("MetronomeTimingEngine maps a slightly-past target to a host time before the reference")
    func testHostTimeConversionReturnsTruePastTargetHostTime() {
        // Regression: a slightly-past target must convert to
        // `referenceHostTime - |delta|` (the true target host time), not collapse
        // onto `referenceHostTime`. Collapsing made late timer callbacks schedule
        // against "now" instead of the converted target. See eec7966.
        let referenceCFTime: CFAbsoluteTime = 1_000.0
        let referenceHostTime: UInt64 = 10_000_000
        let staleTargetCFTime = referenceCFTime - 0.05

        let convertedHostTime = MetronomeTimingEngine.hostTime(
            forCFAbsoluteTime: staleTargetCFTime,
            referenceCFTime: referenceCFTime,
            referenceHostTime: referenceHostTime
        )

        let elapsedSeconds = AVAudioTime.seconds(forHostTime: convertedHostTime)
            - AVAudioTime.seconds(forHostTime: referenceHostTime)
        // The converted host time sits ~0.05s before the reference (the true
        // past target), not at or after it.
        #expect(elapsedSeconds < 0)
        #expect(abs(elapsedSeconds + 0.05) < 0.001)
        // Must not collapse onto the reference host time.
        #expect(convertedHostTime != referenceHostTime)
    }

    @Test("MetronomeTimingEngine host time conversion clamps before mach zero")
    func testHostTimeConversionClampsBeforeMachZero() {
        let convertedHostTime = MetronomeTimingEngine.hostTime(
            forCFAbsoluteTime: 999.0,
            referenceCFTime: 1_000.0,
            referenceHostTime: 10
        )

        #expect(convertedHostTime == 0)
    }

    @Test("Metronome beat scheduler wakes before the ideal beat and schedules audio at the beat")
    func testBeatSchedulerUsesLookaheadDeadline() {
        let schedule = MetronomeBeatSchedule(
            beatOriginTime: 10.0,
            beatInterval: 0.5,
            schedulingLeadTime: 0.1
        )

        #expect(abs(schedule.timerDeadline(forBeatNumber: 1) - 9.9) < 0.0001)
        #expect(abs(schedule.audioTargetTime(forBeatNumber: 1) - 10.0) < 0.0001)
        #expect(abs(schedule.timerDeadline(forBeatNumber: 4) - 11.4) < 0.0001)
        #expect(abs(schedule.audioTargetTime(forBeatNumber: 4) - 11.5) < 0.0001)
    }
}
