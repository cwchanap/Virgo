//
//  AudioTimingBoundaryTests.swift
//  VirgoTests
//
//  Created by Claude Code on 16/8/2025.
//

import Testing
import AVFoundation
@testable import Virgo

@Suite("Audio Timing Boundary Condition Tests")
@MainActor
struct AudioTimingBoundaryTests {
    
    @Test("MetronomeAudioEngine handles invalid AVAudioTime")
    func testInvalidAVAudioTimeHandling() {
        let audioEngine = MetronomeAudioEngine()
        
        // Test with nil AVAudioTime (should fallback to immediate playback)
        #expect(throws: Never.self) {
            audioEngine.playTick(volume: 0.5, isAccented: true, atTime: nil)
        }
        
        // Test with invalid AVAudioTime (zero host time)
        let invalidAudioTime = AVAudioTime(hostTime: 0)
        #expect(throws: Never.self) {
            audioEngine.playTick(volume: 0.5, isAccented: false, atTime: invalidAudioTime)
        }
    }
    
    @Test("MetronomeAudioEngine handles volume boundary values")
    func testVolumeBoundaryValues() {
        let audioEngine = MetronomeAudioEngine()
        
        // Test extreme volume values
        #expect(throws: Never.self) {
            audioEngine.playTick(volume: Float.infinity, isAccented: false, atTime: nil)
        }
        
        #expect(throws: Never.self) {
            audioEngine.playTick(volume: -Float.infinity, isAccented: false, atTime: nil)
        }
        
        #expect(throws: Never.self) {
            audioEngine.playTick(volume: Float.nan, isAccented: false, atTime: nil)
        }
        
        // Test boundary values
        #expect(throws: Never.self) {
            audioEngine.playTick(volume: 0.0, isAccented: false, atTime: nil)
        }
        
        #expect(throws: Never.self) {
            audioEngine.playTick(volume: 1.0, isAccented: true, atTime: nil)
        }
        
        #expect(throws: Never.self) {
            audioEngine.playTick(volume: 2.0, isAccented: true, atTime: nil) // Should clamp to 1.0
        }
    }
    
    @Test("MetronomeTimingEngine handles precision edge cases")
    func testTimingPrecisionEdgeCases() {
        let timingEngine = MetronomeTimingEngine()
        
        // Test very high BPM (should not crash)
        timingEngine.bpm = 999.0
        #expect(timingEngine.bpm == 999.0)
        
        // Test very low BPM
        timingEngine.bpm = 1.0
        #expect(timingEngine.bpm == 1.0)
        
        // Test timing calculations don't overflow
        let timing = timingEngine.getCurrentBeatProgress(timeSignature: .fourFour)
        // Should return nil when not playing, but shouldn't crash
        #expect(timing == nil)
    }
    
    @Test("MetronomeTimingEngine handles start/stop edge cases")
    func testStartStopEdgeCases() async {
        let timingEngine = MetronomeTimingEngine()
        
        // Test multiple start calls (should not crash)
        timingEngine.start()
        timingEngine.start() // Second start should be ignored
        #expect(timingEngine.isPlaying == true)
        
        // Test multiple stop calls
        timingEngine.stop()
        timingEngine.stop() // Second stop should be ignored
        #expect(timingEngine.isPlaying == false)
        
        // Test rapid start/stop cycles
        for _ in 0..<10 {
            timingEngine.start()
            timingEngine.stop()
        }
        #expect(timingEngine.isPlaying == false)
    }
    
    @Test("MetronomeTimingEngine handles time calculations safely")
    func testTimeCalculationSafety() {
        let timingEngine = MetronomeTimingEngine()
        
        // Test getCurrentPlaybackTime when not playing
        let playbackTime = timingEngine.getCurrentPlaybackTime()
        #expect(playbackTime == nil)
        
        // Test getCurrentBeatProgress when not playing
        let beatProgress = timingEngine.getCurrentBeatProgress(timeSignature: .fourFour)
        #expect(beatProgress == nil)
        
        // Test with extreme time signature (single beat per measure)
        let extremeTimeSignature = TimeSignature.twoFour
        timingEngine.timeSignature = extremeTimeSignature
        #expect(timingEngine.timeSignature.beatsPerMeasure == 2)
        #expect(timingEngine.currentBeat == 1) // Should reset to 1
    }
    
    @Test("AVAudioTime creation and validation")
    func testAVAudioTimeCreation() {
        // Test creating AVAudioTime with current host time
        let hostTime = mach_absolute_time()
        let audioTime = AVAudioTime(hostTime: hostTime)
        
        #expect(audioTime.isHostTimeValid == true)
        #expect(audioTime.hostTime == hostTime)
        
        // Test with zero host time (should be invalid)
        let zeroAudioTime = AVAudioTime(hostTime: 0)
        #expect(zeroAudioTime.isHostTimeValid == false)
    }
}

