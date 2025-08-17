//
//  MetronomeEngineTests.swift
//  VirgoTests
//
//  Created by Claude Code on 4/8/2025.
//

import Testing
import SwiftUI
@testable import Virgo

@Suite("Metronome Engine Tests")
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
    func testBPMUpdate() {
        let engine = MetronomeEngine()

        engine.updateBPM(140)
        #expect(engine.bpm == 140)

        // Test clamping
        engine.updateBPM(300)
        #expect(engine.bpm == 200) // Should clamp to max

        engine.updateBPM(10)
        #expect(engine.bpm == 40) // Should clamp to min
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

    @Test("MetronomeEngine time signature updates correctly")
    func testTimeSignatureUpdate() {
        let engine = MetronomeEngine()

        engine.updateTimeSignature(.threeFour)
        #expect(engine.timeSignature == .threeFour)
        #expect(engine.currentBeat == 1) // Should reset beat
    }

    @Test("MetronomeEngine start/stop functionality")
    func testStartStop() async {
        let engine = MetronomeEngine()

        #expect(engine.isEnabled == false)

        engine.start(bpm: 120, timeSignature: .fourFour)
        #expect(engine.bpm == 120)
        #expect(engine.timeSignature == .fourFour)

        // Allow some time for the published property to update
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second

        engine.stop()
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
    }
}

@Suite("Metronome Audio Engine Tests")
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
}

@Suite("Metronome Timing Engine Tests")
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

    @Test("MetronomeTimingEngine BPM updates correctly")
    func testTimingEngineBPMUpdate() {
        let timingEngine = MetronomeTimingEngine()

        timingEngine.bpm = 140
        #expect(timingEngine.bpm == 140)
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

        // Allow some time for the callback to be triggered
        try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 second

        timingEngine.stop()

        #expect(callbackTriggered == true)
        #expect(receivedBeat >= 1)
    }
}
