//
//  MetronomeTimingEngineTests.swift
//  VirgoTests
//
//  Split from MetronomeEngineTests to keep each file under the SwiftLint
//  file-length warn limit (600). Holds the MetronomeTimingEngine-specific
//  suites (timing origin, beat-phase preservation, scheduled-start clamping,
//  token supersession).
//

import Testing
import SwiftUI
import AVFoundation
@testable import Virgo

private func timingEngineValue<T>(
    _ timingEngine: MetronomeTimingEngine,
    label: String,
    as type: T.Type = T.self
) -> T? {
    let mirror = Mirror(reflecting: timingEngine)
    return mirror.children.first { $0.label == label }?.value as? T
}

@Suite("Metronome Timing Engine Tests", .serialized)
@MainActor
struct MetronomeTimingEngineTests {

    @Test("MetronomeTimingEngine initializes with default values")
    func testTimingEngineInitialization() {
        let timingEngine = MetronomeTimingEngine()

        #expect(timingEngine.currentBeat == 1)
        #expect(timingEngine.isPlaying == false)
        #expect(timingEngine.bpm == 120)
        #expect(timingEngine.timeSignature == .fourFour)
    }

    @Test("MetronomeTimingEngine toggle starts and stops playback")
    func testTimingEngineToggle() {
        let timingEngine = MetronomeTimingEngine()

        timingEngine.toggle()
        #expect(timingEngine.isPlaying == true)

        timingEngine.toggle()
        #expect(timingEngine.isPlaying == false)
        #expect(timingEngine.currentBeat == 1)
    }

    @Test("MetronomeTimingEngine BPM updates correctly")
    func testTimingEngineBPMUpdate() {
        let timingEngine = MetronomeTimingEngine()

        timingEngine.bpm = 140
        #expect(timingEngine.bpm == 140)
    }

    @Test("MetronomeTimingEngine beat interval stays aligned with gameplay beat clock")
    func testTimingEngineBeatIntervalMatchesGameplayBeatClock() {
        let timingEngine = MetronomeTimingEngine()

        timingEngine.bpm = 120
        timingEngine.timeSignature = .fourFour
        let quarterBeatInterval = timingEngineValue(timingEngine, label: "cachedBeatInterval", as: Double.self)

        timingEngine.timeSignature = .sixEight
        let sixEightBeatInterval = timingEngineValue(timingEngine, label: "cachedBeatInterval", as: Double.self)

        #expect(quarterBeatInterval != nil)
        #expect(sixEightBeatInterval != nil)
        #expect(abs((quarterBeatInterval ?? 0) - 0.5) < 0.0001)
        #expect(abs((sixEightBeatInterval ?? 0) - 0.5) < 0.0001)
    }

    @Test("MetronomeTimingEngine derives fired beat from monotonic beat count instead of UI state")
    func testTimingEngineBeatNumberComesFromFiredBeatCount() {
        #expect(MetronomeTimingEngine.beatInMeasure(forFiredBeatNumber: 1, timeSignature: .fourFour) == 1)
        #expect(MetronomeTimingEngine.beatInMeasure(forFiredBeatNumber: 2, timeSignature: .fourFour) == 2)
        #expect(MetronomeTimingEngine.beatInMeasure(forFiredBeatNumber: 4, timeSignature: .fourFour) == 4)
        #expect(MetronomeTimingEngine.beatInMeasure(forFiredBeatNumber: 5, timeSignature: .fourFour) == 1)
        #expect(MetronomeTimingEngine.beatInMeasure(forFiredBeatNumber: 4, timeSignature: .threeFour) == 1)
    }

    @Test("MetronomeTimingEngine time signature resets beat")
    func testTimeSignatureResetsBeat() {
        let timingEngine = MetronomeTimingEngine()

        // Simulate changing beat position
        timingEngine.timeSignature = .threeFour
        #expect(timingEngine.currentBeat == 1)
    }

    @Test("MetronomeTimingEngine callback mechanism")
    func testCallbackMechanism() async {
        let timingEngine = MetronomeTimingEngine()
        var callbackTriggered = false
        var receivedBeat: Int = 0
        var receivedAccented: Bool = false

        timingEngine.onBeat = { beat, isAccented, _ in
            callbackTriggered = true
            receivedBeat = beat
            receivedAccented = isAccented
        }

        timingEngine.start()

        // Wait for callback to be triggered
        let callbackTriggeredSuccessfully = await TestHelpers.waitFor(
            condition: { callbackTriggered },
            timeout: 10.0 // Give more time for timing engine callback
        )

        timingEngine.stop()

        #expect(callbackTriggeredSuccessfully)
        #expect(receivedBeat >= 1)
    }

    @Test("MetronomeTimingEngine publishes the audible beat, not the next beat")
    func testCurrentBeatMatchesAudibleBeatAfterScheduledTick() async throws {
        let timingEngine = MetronomeTimingEngine(isTestEnvironment: false)
        timingEngine.bpm = 120
        timingEngine.timeSignature = .fourFour
        var receivedBeat: Int?

        timingEngine.onBeat = { beat, _, _ in
            if receivedBeat == nil {
                receivedBeat = beat
            }
        }

        timingEngine.startAtTime(startTime: CFAbsoluteTimeGetCurrent() + 0.05)
        defer { timingEngine.stop() }
        try await Task.sleep(nanoseconds: 200_000_000)

        let beat = try #require(receivedBeat)
        #expect(beat == 1)
        #expect(timingEngine.currentBeat == beat)
    }

    @Test("MetronomeTimingEngine cancels delayed visual beats from a previous playback token")
    func testDelayedVisualBeatDoesNotPublishAfterRestart() async throws {
        let timingEngine = MetronomeTimingEngine(isTestEnvironment: false)
        timingEngine.bpm = 120
        timingEngine.timeSignature = .fourFour
        var receivedBeats: [(beat: Int, timestamp: CFAbsoluteTime)] = []

        timingEngine.onBeat = { beat, _, _ in
            receivedBeats.append((beat: beat, timestamp: CFAbsoluteTimeGetCurrent()))
        }

        let firstStartTime = CFAbsoluteTimeGetCurrent() + 0.20
        timingEngine.startAtTime(startTime: firstStartTime, totalBeatsElapsed: 0)

        // Let the first timer fire early and enqueue its delayed visual callback,
        // then restart before the audible beat boundary. The old visual callback
        // must not leak into the new playback session.
        try await Task.sleep(nanoseconds: 180_000_000)

        let secondStartTime = CFAbsoluteTimeGetCurrent() + 0.20
        timingEngine.stop()
        timingEngine.startAtTime(startTime: secondStartTime, totalBeatsElapsed: 2)
        defer { timingEngine.stop() }

        try await Task.sleep(nanoseconds: 120_000_000)
        #expect(
            receivedBeats.isEmpty,
            "No visual beat should publish before the restarted playback reaches its own scheduled start"
        )

        let receivedRestartedBeat = await TestHelpers.waitFor(
            condition: { !receivedBeats.isEmpty },
            timeout: 1.0,
            checkInterval: 0.02
        )
        #expect(receivedRestartedBeat)
        let firstBeat = try #require(receivedBeats.first)
        #expect(firstBeat.timestamp >= secondStartTime)
        #expect(firstBeat.beat == 3)
    }

    @Test("MetronomeTimingEngine reports beat progress only while playing")
    func testGetCurrentBeatProgress() {
        let timingEngine = MetronomeTimingEngine()

        #expect(timingEngine.getCurrentBeatProgress(timeSignature: .fourFour) == nil)

        timingEngine.startAtTime(startTime: CFAbsoluteTimeGetCurrent() - 1.0, totalBeatsElapsed: 2)
        let progress = timingEngine.getCurrentBeatProgress(timeSignature: .fourFour)

        #expect(progress != nil)
        #expect((progress?.totalBeats ?? 0) > 0)
        #expect((progress?.beatInMeasure ?? -1) >= 0)

        timingEngine.stop()
        #expect(timingEngine.getCurrentBeatProgress(timeSignature: .fourFour) == nil)
    }

    @Test("MetronomeEngine preserves beat phase when resuming")
    func testBeatPhasePreservationOnResume() {
        let timingEngine = MetronomeTimingEngine()
        timingEngine.bpm = 120
        timingEngine.timeSignature = .fourFour

        // Test resuming at beat 5 (should be beat 2 of second measure)
        let totalBeatsElapsed = 5
        let startTime: TimeInterval = 100.0

        timingEngine.startAtTime(startTime: startTime, totalBeatsElapsed: totalBeatsElapsed)

        // After starting with totalBeatsElapsed=5, currentBeat should be:
        // 5 % 4 + 1 = 2 (second beat of the measure, since we're 1-indexed)
        #expect(timingEngine.currentBeat == 2)
        #expect(timingEngine.isPlaying == true)

        timingEngine.stop()

        // Test resuming at beat 8 (should be beat 1 of third measure)
        timingEngine.startAtTime(startTime: startTime, totalBeatsElapsed: 8)

        // After starting with totalBeatsElapsed=8, currentBeat should be:
        // 8 % 4 + 1 = 1 (first beat of the measure)
        #expect(timingEngine.currentBeat == 1)

        timingEngine.stop()

        // Test resuming at beat 0 (should be beat 1 of first measure)
        timingEngine.startAtTime(startTime: startTime, totalBeatsElapsed: 0)

        // After starting with totalBeatsElapsed=0, currentBeat should be:
        // 0 % 4 + 1 = 1 (first beat of the measure)
        #expect(timingEngine.currentBeat == 1)

        timingEngine.stop()
    }

    @Test("MetronomeEngine handles different time signatures on resume")
    func testBeatPhasePreservationWithDifferentTimeSignatures() {
        let timingEngine = MetronomeTimingEngine()

        // Test with 3/4 time signature
        timingEngine.bpm = 120
        timingEngine.timeSignature = .threeFour

        // Resume at beat 4 (should be beat 1 of second measure)
        timingEngine.startAtTime(startTime: 100.0, totalBeatsElapsed: 4)
        #expect(timingEngine.currentBeat == 2) // 4 % 3 = 1, +1 = 2

        timingEngine.stop()

        // Resume at beat 6 (should be beat 1 of third measure)
        timingEngine.startAtTime(startTime: 100.0, totalBeatsElapsed: 6)
        #expect(timingEngine.currentBeat == 1) // 6 % 3 = 0, +1 = 1

        timingEngine.stop()

        // Test with 6/8 time signature
        timingEngine.bpm = 120
        timingEngine.timeSignature = .sixEight

        // Resume at beat 7 (should be beat 2 of second measure)
        timingEngine.startAtTime(startTime: 100.0, totalBeatsElapsed: 7)
        #expect(timingEngine.currentBeat == 2) // 7 % 6 = 1, +1 = 2

        timingEngine.stop()
    }

    @Test("MetronomeTimingEngine stores beat origin offset on resume")
    func testBeatOriginOffsetOnResume() {
        let timingEngine = MetronomeTimingEngine()
        timingEngine.bpm = 120

        let startTime: TimeInterval = 100.0
        let totalBeatsElapsed = 4
        timingEngine.startAtTime(startTime: startTime, totalBeatsElapsed: totalBeatsElapsed)

        let beatOffset = timingEngineValue(timingEngine, label: "beatOffset", as: Int.self)
        let beatOriginTime = timingEngineValue(timingEngine, label: "beatOriginTime", as: Double.self)
        let storedStartTime = timingEngineValue(timingEngine, label: "startTime", as: Double.self)

        #expect(beatOffset == totalBeatsElapsed)
        #expect(storedStartTime == startTime)

        let expectedOriginTime = startTime - (Double(totalBeatsElapsed) * (60.0 / timingEngine.bpm))
        if let beatOriginTime {
            #expect(abs(beatOriginTime - expectedOriginTime) < 0.0001)
        } else {
            #expect(false, "Expected beatOriginTime to be set")
        }

        timingEngine.stop()
    }

    @Test("MetronomeTimingEngine clamps playback time and beat progress before a future scheduled start")
    func testFutureScheduledStartClampsNegativeElapsedTime() {
        let timingEngine = MetronomeTimingEngine()
        timingEngine.bpm = 120
        timingEngine.timeSignature = .fourFour

        let futureStartTime = CFAbsoluteTimeGetCurrent() + 5.0
        timingEngine.startAtTime(startTime: futureStartTime, totalBeatsElapsed: 6)

        let playbackTime = timingEngine.getCurrentPlaybackTime()
        let progress = timingEngine.getCurrentBeatProgress(timeSignature: .fourFour)

        #expect(playbackTime != nil)
        #expect((playbackTime ?? -1) >= 0)
        #expect(progress != nil)
        #expect((progress?.totalBeats ?? -1) >= 0)
        #expect((progress?.beatInMeasure ?? -1) >= 0)
        #expect((progress?.beatInMeasure ?? 4) < 4)

        timingEngine.stop()
    }

    @Test("MetronomeTimingEngine stop clears scheduled timing state")
    func testStopClearsScheduledTimingState() {
        let timingEngine = MetronomeTimingEngine()
        timingEngine.bpm = 120
        timingEngine.startAtTime(startTime: 100.0, totalBeatsElapsed: 3)

        timingEngine.stop()

        let beatOffset = timingEngineValue(timingEngine, label: "beatOffset", as: Int.self)
        let beatOriginTime = timingEngineValue(timingEngine, label: "beatOriginTime", as: Double.self)
        let storedStartTime = timingEngineValue(timingEngine, label: "startTime", as: Double.self)

        #expect(timingEngine.isPlaying == false)
        #expect(timingEngine.currentBeat == 1)
        #expect(beatOffset == 0)
        #expect(storedStartTime == 0)
        #expect(beatOriginTime == 0)
        #expect(timingEngine.getCurrentPlaybackTime() == nil)
    }

    @Test("MetronomeTimingEngine rebuilds timing origin after stop and reschedule")
    func testRescheduleAfterStopRebuildsTimingOrigin() {
        let timingEngine = MetronomeTimingEngine()
        timingEngine.bpm = 120

        timingEngine.startAtTime(startTime: 100.0, totalBeatsElapsed: 4)
        timingEngine.stop()
        timingEngine.startAtTime(startTime: 200.0, totalBeatsElapsed: 1)

        let beatOffset = timingEngineValue(timingEngine, label: "beatOffset", as: Int.self)
        let beatOriginTime = timingEngineValue(timingEngine, label: "beatOriginTime", as: Double.self)
        let storedStartTime = timingEngineValue(timingEngine, label: "startTime", as: Double.self)

        #expect(timingEngine.currentBeat == 2)
        #expect(beatOffset == 1)
        #expect(storedStartTime == 200.0)
        if let beatOriginTime {
            #expect(abs(beatOriginTime - 199.5) < 0.0001)
        } else {
            #expect(Bool(false), "Expected beatOriginTime to be rebuilt")
        }

        timingEngine.stop()
    }

    @Test("MetronomeTimingEngine rebases scheduled start while already playing")
    func testStartAtTimeRebasesAlreadyRunningTimingOrigin() {
        let timingEngine = MetronomeTimingEngine()
        timingEngine.bpm = 120
        timingEngine.timeSignature = .fourFour

        timingEngine.startAtTime(startTime: 100.0, totalBeatsElapsed: 1)
        timingEngine.startAtTime(startTime: 200.0, totalBeatsElapsed: 8)

        let beatOffset = timingEngineValue(timingEngine, label: "beatOffset", as: Int.self)
        let beatOriginTime = timingEngineValue(timingEngine, label: "beatOriginTime", as: Double.self)
        let storedStartTime = timingEngineValue(timingEngine, label: "startTime", as: Double.self)

        #expect(timingEngine.currentBeat == 1)
        #expect(beatOffset == 8)
        #expect(storedStartTime == 200.0)
        if let beatOriginTime {
            #expect(abs(beatOriginTime - 196.0) < 0.0001)
        } else {
            #expect(Bool(false), "Expected beatOriginTime to be rebased")
        }

        timingEngine.stop()
    }
}
