//
//  MetronomeEngineTests.swift
//  VirgoTests
//
//  Created by Claude Code on 4/8/2025.
//

import Testing
import SwiftUI
import AVFoundation
@testable import Virgo

final class RecordingAudioDriver: AudioDriverProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private let tickSemaphore = DispatchSemaphore(value: 0)
    private(set) var playedTicks: [(volume: Float, isAccented: Bool)] = []
    private(set) var scheduledAudioTimes: [AVAudioTime?] = []
    private(set) var resumeCallCount = 0
    private(set) var stopCallCount = 0
    private let audioTimeToReturn: AVAudioTime?

    init(audioTimeToReturn: AVAudioTime? = nil) {
        self.audioTimeToReturn = audioTimeToReturn
    }

    func playTick(volume: Float, isAccented: Bool, atTime: AVAudioTime?) {
        lock.lock()
        defer { lock.unlock() }
        playedTicks.append((volume: volume, isAccented: isAccented))
        scheduledAudioTimes.append(atTime)
        tickSemaphore.signal()
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }
        stopCallCount += 1
    }

    func resume() {
        lock.lock()
        defer { lock.unlock() }
        resumeCallCount += 1
    }

    func convertToAudioEngineTime(_ cfTime: CFAbsoluteTime) -> AVAudioTime? {
        audioTimeToReturn
    }

    func waitForTicks(count: Int, timeout: TimeInterval) -> Bool {
        let deadline = DispatchTime.now() + timeout
        for _ in 0..<count {
            if tickSemaphore.wait(timeout: deadline) != .success {
                return false
            }
        }
        return true
    }

    var playedTicksSnapshot: [(volume: Float, isAccented: Bool)] {
        lock.lock()
        defer { lock.unlock() }
        return playedTicks
    }

    var scheduledAudioTimesSnapshot: [AVAudioTime?] {
        lock.lock()
        defer { lock.unlock() }
        return scheduledAudioTimes
    }
}

final class ThreadRecordingAudioDriver: AudioDriverProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private let firstTickSemaphore = DispatchSemaphore(value: 0)
    private var tickThreads: [Bool] = []

    func playTick(volume: Float, isAccented: Bool, atTime: AVAudioTime?) {
        lock.lock()
        tickThreads.append(Thread.isMainThread)
        lock.unlock()
        firstTickSemaphore.signal()
    }

    func stop() {
    }

    func resume() {
    }

    func convertToAudioEngineTime(_ cfTime: CFAbsoluteTime) -> AVAudioTime? {
        nil
    }

    func waitForFirstTick(timeout: TimeInterval) -> Bool {
        firstTickSemaphore.wait(timeout: .now() + timeout) == .success
    }

    var firstTickWasOnMainThread: Bool? {
        lock.lock()
        defer { lock.unlock() }
        return tickThreads.first
    }
}

@Suite("Metronome Engine Tests", .serialized)
@MainActor
struct MetronomeEngineTests {

    @Test("MetronomeEngine initializes with default values")
    func testMetronomeEngineInitialization() {
        let engine = MetronomeEngine()

        #expect(engine.isEnabled == false)
        #expect(engine.currentBeat == 1)
        #expect(engine.volume == 0.7)
        #expect(engine.bpm == 120)
        #expect(engine.timeSignature == .fourFour)
    }

    @Test("MetronomeEngine BPM updates correctly")
    func testBPMUpdate() async {
        // Add pre-test delay for stability
        try? await Task.sleep(nanoseconds: 300_000_000) // 300ms

        let engine = MetronomeEngine()

        engine.updateBPM(140)
        #expect(engine.bpm == 140)

        // Test that updateBPM accepts the full 10-300 BPM range needed for speed-adjusted playback
        engine.updateBPM(300)
        #expect(engine.bpm == 300) // Should accept 300 BPM (within expanded range)

        engine.updateBPM(10)
        #expect(engine.bpm == 10) // Should accept 10 BPM (within expanded range)
    }

    @Test("MetronomeEngine volume updates correctly")
    func testVolumeUpdate() {
        let engine = MetronomeEngine()

        engine.updateVolume(0.5)
        #expect(engine.volume == 0.5)

        // Test clamping
        engine.updateVolume(1.5)
        #expect(engine.volume == 1.0) // Should clamp to max

        engine.updateVolume(-0.1)
        #expect(engine.volume == 0.0) // Should clamp to min
    }
    
    @Test("MetronomeEngine handles invalid volume values")
    func testInvalidVolumeHandling() {
        let engine = MetronomeEngine()
        let originalVolume = engine.volume
        
        // Test infinite values
        engine.updateVolume(Float.infinity)
        #expect(engine.volume == originalVolume) // Should maintain original volume
        
        engine.updateVolume(-Float.infinity)
        #expect(engine.volume == originalVolume) // Should maintain original volume
        
        // Test NaN
        engine.updateVolume(Float.nan)
        #expect(engine.volume == originalVolume) // Should maintain original volume
    }
    
    @Test("MetronomeEngine handles invalid BPM values")
    func testInvalidBPMHandling() {
        let engine = MetronomeEngine()
        let originalBPM = engine.bpm

        // Test infinite values
        engine.updateBPM(Double.infinity)
        #expect(engine.bpm == originalBPM) // Should maintain original BPM

        engine.updateBPM(-Double.infinity)
        #expect(engine.bpm == originalBPM) // Should maintain original BPM

        // Test NaN
        engine.updateBPM(Double.nan)
        #expect(engine.bpm == originalBPM) // Should maintain original BPM

        // Test zero and negative values
        engine.updateBPM(0.0)
        #expect(engine.bpm == originalBPM) // Should maintain original BPM

        engine.updateBPM(-10.0)
        #expect(engine.bpm == originalBPM) // Should maintain original BPM
    }

    @Test("MetronomeBPM accepts full range for speed sync")
    func testBPMRangeForSpeedSync() {
        let engine = MetronomeEngine()

        // Test low BPM scenarios (slow practice)
        // 120 BPM at 25% speed = 30 BPM
        engine.updateBPM(30)
        #expect(engine.bpm == 30, "Should accept 30 BPM for slow practice")

        // 100 BPM at 20% speed = 20 BPM
        engine.updateBPM(20)
        #expect(engine.bpm == 20, "Should accept 20 BPM for very slow practice")

        // Test normal range
        engine.updateBPM(120)
        #expect(engine.bpm == 120, "Should accept normal 120 BPM")

        // Test high BPM scenarios (fast practice)
        // 160 BPM at 150% speed = 240 BPM
        engine.updateBPM(240)
        #expect(engine.bpm == 240, "Should accept 240 BPM for fast practice")

        // 180 BPM at 150% speed = 270 BPM
        engine.updateBPM(270)
        #expect(engine.bpm == 270, "Should accept 270 BPM for fast practice")
    }

    @Test("MetronomeEngine time signature updates correctly")
    func testTimeSignatureUpdate() {
        let engine = MetronomeEngine()

        engine.updateTimeSignature(.threeFour)
        #expect(engine.timeSignature == .threeFour)
        #expect(engine.currentBeat == 1) // Should reset beat
    }

    @Test("MetronomeEngine update applies BPM and time signature together")
    func testCombinedUpdate() {
        let engine = MetronomeEngine()

        engine.update(bpm: 180, timeSignature: .threeFour)

        #expect(engine.bpm == 180)
        #expect(engine.timeSignature == .threeFour)
    }

    @Test("MetronomeEngine start/stop functionality")
    func testStartStop() async {
        // Add controlled delay with serialized execution for better isolation
        try? await Task.sleep(nanoseconds: 400_000_000) // 400ms - balanced with serialization
        
        let engine = MetronomeEngine()

        #expect(engine.isEnabled == false)

        engine.start(bpm: 120, timeSignature: .fourFour)
        #expect(engine.bpm == 120)
        #expect(engine.timeSignature == .fourFour)

        // Wait for engine to be enabled with balanced timeout
        let enabledSuccessfully = await TestHelpers.waitFor(condition: { engine.isEnabled }, timeout: 2.0)
        #expect(enabledSuccessfully)

        engine.stop()
        
        // Wait for engine to be disabled with balanced timeout
        let disabledSuccessfully = await TestHelpers.waitFor(condition: { !engine.isEnabled }, timeout: 2.0)
        #expect(disabledSuccessfully)
    }

    @Test("MetronomeEngine onInterruption callback can be set and invoked")
    func testOnInterruptionCallback() {
        let engine = MetronomeEngine()
        var callbackInvoked = false
        var receivedInterrupted: Bool?

        engine.onInterruption = { isInterrupted in
            callbackInvoked = true
            receivedInterrupted = isInterrupted
        }

        // Manually invoke to verify the callback is accessible
        engine.onInterruption?(true)

        #expect(callbackInvoked == true)
        #expect(receivedInterrupted == true)

        // Test with false (interruption ended)
        engine.onInterruption?(false)
        #expect(receivedInterrupted == false)
    }

    @Test("MetronomeEngine testClick forwards the current volume to the audio driver")
    func testTestClickUsesAudioDriver() {
        let driver = RecordingAudioDriver()
        let engine = MetronomeEngine(audioDriver: driver)
        engine.updateVolume(0.42)

        engine.testClick()

        #expect(driver.playedTicks.count == 1)
        #expect(abs(driver.playedTicks[0].volume - 0.42) < 0.0001)
        #expect(driver.playedTicks[0].isAccented == true)
    }

    @Test("MetronomeEngine forwards audio-time conversion to the audio driver")
    func testConvertToAudioEngineTimeUsesAudioDriver() {
        let expected = AVAudioTime(hostTime: 123_456)
        let driver = RecordingAudioDriver(audioTimeToReturn: expected)
        let engine = MetronomeEngine(audioDriver: driver)

        let converted = engine.convertToAudioEngineTime(CFAbsoluteTimeGetCurrent())

        #expect(converted?.hostTime == expected.hostTime)
    }

    @Test("MetronomeEngine schedules audio ticks without waiting for the main actor")
    func testAudioTickSchedulingDoesNotWaitForMainActor() {
        let driver = ThreadRecordingAudioDriver()
        let timingEngine = MetronomeTimingEngine(isTestEnvironment: false)
        let engine = MetronomeEngine(audioDriver: driver, timingEngine: timingEngine)

        engine.start(bpm: 300, timeSignature: .fourFour)
        Thread.sleep(forTimeInterval: 0.25)
        let receivedTickWhileMainActorWasBlocked = driver.waitForFirstTick(timeout: 0.05)
        engine.stop()

        #expect(receivedTickWhileMainActorWasBlocked)
        #expect(driver.firstTickWasOnMainThread == false)
    }

    @Test("MetronomeEngine emits every beat with stable scheduled audio timing")
    func testMetronomeEmitsEveryBeatWithStableScheduledAudioTiming() {
        let driver = RecordingAudioDriver()
        let timingEngine = MetronomeTimingEngine(isTestEnvironment: false)
        let engine = MetronomeEngine(audioDriver: driver, timingEngine: timingEngine)
        let bpm = 300.0
        let expectedBeatCount = 10

        engine.startAtTime(
            bpm: bpm,
            timeSignature: .fourFour,
            startTime: CFAbsoluteTimeGetCurrent() + 0.08
        )
        let receivedExpectedTicks = driver.waitForTicks(count: expectedBeatCount, timeout: 3.0)
        engine.stop()

        #expect(receivedExpectedTicks, "Expected \(expectedBeatCount) audio ticks from the real timer path")
        let ticks = driver.playedTicksSnapshot
        let scheduledTimes = driver.scheduledAudioTimesSnapshot.compactMap { $0 }
        #expect(ticks.count >= expectedBeatCount)
        #expect(scheduledTimes.count >= expectedBeatCount)

        for index in 0..<min(expectedBeatCount, ticks.count) {
            let shouldAccent = index % 4 == 0
            #expect(
                ticks[index].isAccented == shouldAccent,
                "Beat \(index + 1) accent state should follow the 4/4 downbeat pattern"
            )
        }

        let expectedInterval = 60.0 / bpm
        let checkedTimes = Array(scheduledTimes.prefix(expectedBeatCount))
        for index in checkedTimes.indices.dropFirst() {
            let previousSeconds = AVAudioTime.seconds(forHostTime: checkedTimes[index - 1].hostTime)
            let currentSeconds = AVAudioTime.seconds(forHostTime: checkedTimes[index].hostTime)
            let interval = currentSeconds - previousSeconds
            #expect(
                abs(interval - expectedInterval) < 0.015,
                "Scheduled tick interval \(index) drifted to \(interval)s, expected \(expectedInterval)s"
            )
        }

        if let firstTime = checkedTimes.first, let lastTime = checkedTimes.last {
            let actualSpan = AVAudioTime.seconds(forHostTime: lastTime.hostTime)
                - AVAudioTime.seconds(forHostTime: firstTime.hostTime)
            let expectedSpan = Double(expectedBeatCount - 1) * expectedInterval
            #expect(
                abs(actualSpan - expectedSpan) < 0.02,
                "Scheduled audio beat span should not accumulate drift over \(expectedBeatCount) ticks"
            )
        }
    }

    @Test("MetronomeEngine flushes queued audio before rebasing an already-running metronome")
    func testStartAtTimeFlushesAudioWhenRebasingAlreadyRunningMetronome() {
        let driver = RecordingAudioDriver()
        let timingEngine = MetronomeTimingEngine()
        let engine = MetronomeEngine(audioDriver: driver, timingEngine: timingEngine)

        engine.start(bpm: 120, timeSignature: .fourFour)
        #expect(timingEngine.isPlaying == true)

        engine.startAtTime(
            bpm: 120,
            timeSignature: .fourFour,
            startTime: CFAbsoluteTimeGetCurrent() + 0.05,
            totalBeatsElapsed: 4
        )

        #expect(driver.stopCallCount == 1)
        #expect(driver.resumeCallCount == 2)
        engine.stop()
    }

    @Test("timeline rebase stops audio after a completed callback")
    func timelineRebaseStopsAudioAfterCompletedCallback() throws {
        let driver = RecordingAudioDriver()
        let timingEngine = MetronomeTimingEngine()
        let engine = MetronomeEngine(audioDriver: driver, timingEngine: timingEngine)
        let measure = RhythmMeasure(
            measureIndex: 0,
            startTick: 0,
            durationTicks: 4,
            timeSignature: .fourFour,
            beatGroups: (0..<4).map {
                RhythmBeatGroup(groupIndex: $0, startTick: $0, durationTicks: 1, isResidual: false)
            },
            engravingSupport: .supported
        )
        let schedule = try RhythmMetronomeSchedule(
            timeline: RhythmTimeline(
                ticksPerWholeNote: 4,
                measures: [measure],
                eventPositions: [:],
                bgmStartPosition: nil
            ),
            bpm: 120
        )

        engine.startAtTime(
            schedule: schedule,
            speed: 1,
            startTime: 100,
            elapsedTime: 0
        )
        timingEngine.onAudioBeat?(1, true, nil)
        #expect(driver.playedTicksSnapshot.count == 1)

        engine.startAtTime(
            schedule: schedule,
            speed: 1,
            startTime: 200,
            elapsedTime: 0
        )

        #expect(driver.stopCallCount == 1)
        #expect(driver.resumeCallCount == 2)
        engine.stop()
    }

    @Test("MetronomeEngine timeline start scales immutable pulse offsets with practice speed")
    func testTimelineStartScalesPulseOffsets() throws {
        let driver = RecordingAudioDriver()
        let timingEngine = MetronomeTimingEngine(isTestEnvironment: false)
        let engine = MetronomeEngine(audioDriver: driver, timingEngine: timingEngine)
        let measure = RhythmMeasure(
            measureIndex: 0,
            startTick: 0,
            durationTicks: 4,
            timeSignature: .fourFour,
            beatGroups: (0..<4).map {
                RhythmBeatGroup(groupIndex: $0, startTick: $0, durationTicks: 1, isResidual: false)
            },
            engravingSupport: .supported
        )
        let schedule = try RhythmMetronomeSchedule(
            timeline: RhythmTimeline(
                ticksPerWholeNote: 4,
                measures: [measure],
                eventPositions: [:],
                bgmStartPosition: nil
            ),
            bpm: 300
        )

        engine.startAtTime(
            schedule: schedule,
            speed: 2,
            startTime: CFAbsoluteTimeGetCurrent() + 0.08,
            elapsedTime: 0
        )
        let receivedAllTicks = driver.waitForTicks(count: 4, timeout: 1)
        engine.stop()

        #expect(receivedAllTicks)
        let ticks = driver.playedTicksSnapshot
        let scheduledTimes = driver.scheduledAudioTimesSnapshot.compactMap { $0 }
        let accentStates = Array(ticks.prefix(4)).map(\.isAccented)
        #expect(accentStates == [true, true, true, true])
        #expect(scheduledTimes.count >= 4)
        for index in 1..<min(4, scheduledTimes.count) {
            let previous = AVAudioTime.seconds(forHostTime: scheduledTimes[index - 1].hostTime)
            let current = AVAudioTime.seconds(forHostTime: scheduledTimes[index].hostTime)
            #expect(abs((current - previous) - 0.1) < 0.015)
        }
    }
}

@Suite("Metronome Audio Engine Tests", .serialized)
@MainActor
struct MetronomeAudioEngineTests {

    @Test("MetronomeAudioEngine initializes correctly")
    func testAudioEngineInitialization() {
        let audioEngine = MetronomeAudioEngine()
        // Test that it doesn't crash during initialization
        #expect(audioEngine != nil)
    }

    @Test("MetronomeAudioEngine handles test environment")
    func testTestEnvironmentHandling() {
        // In test environment, audio operations should be no-ops
        let audioEngine = MetronomeAudioEngine()

        // These should not crash in test environment
        audioEngine.playTick()
        audioEngine.playTick(volume: 0.5, isAccented: true, atTime: nil)
        audioEngine.stop()
        audioEngine.resume()
    }

    @Test("MetronomeAudioEngine onInterruption callback can be set")
    func testOnInterruptionCallbackAssignment() {
        let audioEngine = MetronomeAudioEngine()
        var callbackInvoked = false
        var receivedInterrupted = false

        audioEngine.onInterruption = { isInterrupted in
            callbackInvoked = true
            receivedInterrupted = isInterrupted
        }

        // Manually invoke the callback to verify it's wired correctly
        audioEngine.onInterruption?(true)

        #expect(callbackInvoked == true)
        #expect(receivedInterrupted == true)
    }

    @Test("MetronomeAudioEngine onInterruption callback reports false for resume")
    func testOnInterruptionCallbackResume() {
        let audioEngine = MetronomeAudioEngine()
        var receivedInterrupted: Bool?

        audioEngine.onInterruption = { isInterrupted in
            receivedInterrupted = isInterrupted
        }

        // Simulate interruption end (resume)
        audioEngine.onInterruption?(false)

        #expect(receivedInterrupted == false)
    }

    @Test("MetronomeAudioEngine onInterruption callback handles multiple calls")
    func testOnInterruptionCallbackMultipleCalls() {
        let audioEngine = MetronomeAudioEngine()
        var callCount = 0
        var states: [Bool] = []

        audioEngine.onInterruption = { isInterrupted in
            callCount += 1
            states.append(isInterrupted)
        }

        // Simulate interruption sequence: begin -> end
        audioEngine.onInterruption?(true)
        audioEngine.onInterruption?(false)

        #expect(callCount == 2)
        #expect(states == [true, false])
    }

    @Test("MetronomeAudioEngine is Sendable and onInterruption survives concurrent access")
    func testOnInterruptionConcurrentAccess() async {
        let audioEngine = MetronomeAudioEngine()

        // The engine is now Sendable, so it may cross actor boundaries — mirroring
        // how MetronomeTimingEngine drives playTick from a background queue while the
        // main actor reassigns onInterruption. Concurrently swap, read, and invoke the
        // callback from many detached tasks; the lock-backed storage must not crash.
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<200 {
                group.addTask {
                    audioEngine.onInterruption = { _ in }
                    audioEngine.onInterruption?(Bool.random())
                }
            }
        }

        // Final state is readable and clearable from the main actor.
        audioEngine.onInterruption = nil
        #expect(audioEngine.onInterruption == nil)
    }
}
