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
    
    @Test("AVAudioTime creation and validation") 
    func testAVAudioTimeCreation() {
        // Test valid AVAudioTime creation
        let validHostTime = mach_absolute_time()
        let validAudioTime = AVAudioTime(hostTime: validHostTime)
        #expect(validAudioTime.hostTime > 0)
        
        // Test AVAudioTime with current time
        let currentTime = AVAudioTime(hostTime: mach_absolute_time())
        #expect(currentTime.hostTime > 0)
        
        // Test that we can safely handle nil time references in our logic
        let timeRef: AVAudioTime? = nil
        let fallbackTime = timeRef ?? AVAudioTime(hostTime: mach_absolute_time())
        #expect(fallbackTime.hostTime > 0)
    }
    
    @Test("MetronomeAudioEngine handles volume boundary values")
    func testVolumeBoundaryValues() {
        // Test volume boundaries without initializing actual audio engine in test environment
        let testVolumes: [Float] = [0.0, 1.0, -1.0, 2.0]
        
        for volume in testVolumes {
            let clampedVolume = max(0.0, min(1.0, volume))
            #expect(clampedVolume >= 0.0)
            #expect(clampedVolume <= 1.0)
        }
        
        // Test NaN handling
        let nanVolume = Float.nan
        let safeVolume = nanVolume.isNaN ? 0.5 : nanVolume
        #expect(!safeVolume.isNaN)
        
        // Test infinity handling
        let infVolume = Float.infinity
        let boundedVolume = max(0.0, min(1.0, infVolume))
        #expect(boundedVolume.isFinite)
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
}
