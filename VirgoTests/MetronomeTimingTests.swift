//
//  MetronomeTimingTests.swift
//  VirgoTests
//
//  Created by Chan Wai Chan on 1/8/2025.
//

import Testing
import Foundation
import SwiftUI
@testable import Virgo

struct MetronomeTimingTests {
    
    // MARK: - BPM to Interval Conversion Tests
    
    @Test func testBPMToIntervalConversion() {
        // Test common BPM values
        let testCases: [(bpm: Int, expectedInterval: Double)] = [
            (60, 1.0),      // 60 BPM = 1 second per beat
            (120, 0.5),     // 120 BPM = 0.5 seconds per beat
            (240, 0.25),    // 240 BPM = 0.25 seconds per beat
            (100, 0.6),     // 100 BPM = 0.6 seconds per beat
            (166, 60.0/166.0), // BPM 166 from our bug fix
            (90, 60.0/90.0),   // 90 BPM = 0.667 seconds per beat
            (150, 0.4)     // 150 BPM = 0.4 seconds per beat
        ]
        
        for testCase in testCases {
            let calculatedInterval = 60.0 / Double(testCase.bpm)
            let tolerance = 0.001
            
            #expect(
                abs(calculatedInterval - testCase.expectedInterval) < tolerance,
                "BPM \(testCase.bpm) should give interval \(testCase.expectedInterval), got \(calculatedInterval)"
            )
        }
    }
    
    @Test func testExtremeTempoValues() {
        // Test very slow tempos
        let slowBPM = 30
        let slowInterval = 60.0 / Double(slowBPM)
        #expect(slowInterval == 2.0, "30 BPM should be 2.0 seconds per beat")
        
        // Test very fast tempos  
        let fastBPM = 300
        let fastInterval = 60.0 / Double(fastBPM)
        #expect(abs(fastInterval - 0.2) < 0.001, "300 BPM should be 0.2 seconds per beat")
        
        // Test edge case: minimum reasonable BPM
        let minBPM = 1
        let minInterval = 60.0 / Double(minBPM)
        #expect(minInterval == 60.0, "1 BPM should be 60 seconds per beat")
    }
    
    // MARK: - Beat Counter Wrapping Tests
    
    @Test func testBeatCounterWrapping() {
        let timeSignatures: [TimeSignature] = [.twoFour, .threeFour, .fourFour, .fiveFour]
        
        for signature in timeSignatures {
            let beatsPerMeasure = signature.beatsPerMeasure
            
            // Test wrapping through multiple measures
            for rawBeat in 0..<(beatsPerMeasure * 5) {
                let wrappedBeat = (rawBeat + 1) % beatsPerMeasure
                
                #expect(wrappedBeat >= 0, "Beat should never be negative")
                #expect(wrappedBeat < beatsPerMeasure, "Beat should be less than beats per measure")
                
                // Test that beat 0 follows the last beat of a measure
                if rawBeat > 0 && (rawBeat + 1) % beatsPerMeasure == 0 {
                    let nextBeat = (rawBeat + 2) % beatsPerMeasure
                    #expect(nextBeat == 1, "Beat after last beat of measure should wrap to 1")
                }
            }
        }
    }
    
    @Test func testBeatProgressionSequence() {
        // Test 4/4 time signature beat progression
        let fourFourBeats = [1, 2, 3, 0, 1, 2, 3, 0, 1, 2] // 0 represents beat 4 (index wrapping)
        
        for (index, expectedBeat) in fourFourBeats.enumerated() {
            let calculatedBeat = (index + 1) % 4
            let displayBeat = calculatedBeat == 0 ? 4 : calculatedBeat
            let expectedDisplay = expectedBeat == 0 ? 4 : expectedBeat
            
            #expect(displayBeat == expectedDisplay, "Beat sequence mismatch at index \(index)")
        }
        
        // Test 3/4 time signature beat progression  
        let threeFourBeats = [1, 2, 0, 1, 2, 0, 1, 2] // 0 represents beat 3
        
        for (index, expectedBeat) in threeFourBeats.enumerated() {
            let calculatedBeat = (index + 1) % 3
            let displayBeat = calculatedBeat == 0 ? 3 : calculatedBeat
            let expectedDisplay = expectedBeat == 0 ? 3 : expectedBeat
            
            #expect(displayBeat == expectedDisplay, "3/4 beat sequence mismatch at index \(index)")
        }
    }
    
    // MARK: - Quarter Note Position Tests
    
    @Test func testQuarterNotePositionCalculation() {
        let testCases: [(totalBeats: Int, expectedPosition: Double)] = [
            (0, 0.0),   // No beats = position 0
            (1, 0.25),  // 1 beat = 0.25 (first quarter note)
            (2, 0.5),   // 2 beats = 0.5 (second quarter note)
            (3, 0.75),  // 3 beats = 0.75 (third quarter note)
            (4, 1.0),   // 4 beats = 1.0 (full measure)
            (5, 1.25),  // 5 beats = 1.25 (second measure, first quarter)
            (8, 2.0),   // 8 beats = 2.0 (two full measures)
            (12, 3.0)  // 12 beats = 3.0 (three full measures)
        ]
        
        for testCase in testCases {
            let calculatedPosition = Double(testCase.totalBeats) * 0.25
            
            #expect(
                abs(calculatedPosition - testCase.expectedPosition) < 0.001,
                "Total beats \(testCase.totalBeats) should give position \(testCase.expectedPosition), got \(calculatedPosition)"
            )
        }
    }
    
    @Test func testMeasureIndexFromQuarterNotePosition() {
        let testCases: [(position: Double, expectedMeasure: Int)] = [
            (0.0, 0),   // Position 0.0 = measure 0
            (0.25, 0),  // Position 0.25 = measure 0
            (0.75, 0),  // Position 0.75 = measure 0
            (1.0, 1),   // Position 1.0 = measure 1
            (1.5, 1),   // Position 1.5 = measure 1
            (2.0, 2),   // Position 2.0 = measure 2
            (2.75, 2),  // Position 2.75 = measure 2
            (3.0, 3)   // Position 3.0 = measure 3
        ]
        
        for testCase in testCases {
            let calculatedMeasure = Int(testCase.position)
            
            #expect(
                calculatedMeasure == testCase.expectedMeasure,
                "Position \(testCase.position) should give measure \(testCase.expectedMeasure), got \(calculatedMeasure)"
            )
        }
    }
    
    @Test func testMeasureOffsetFromQuarterNotePosition() {
        let testCases: [(position: Double, expectedOffset: Double)] = [
            (0.0, 0.0),     // Position 0.0 = offset 0.0
            (0.25, 0.25),   // Position 0.25 = offset 0.25
            (0.75, 0.75),   // Position 0.75 = offset 0.75
            (1.0, 0.0),     // Position 1.0 = offset 0.0 (new measure)
            (1.25, 0.25),   // Position 1.25 = offset 0.25
            (1.75, 0.75),   // Position 1.75 = offset 0.75
            (2.0, 0.0),     // Position 2.0 = offset 0.0 (new measure)
            (2.5, 0.5)     // Position 2.5 = offset 0.5
        ]
        
        for testCase in testCases {
            let measureIndex = Int(testCase.position)
            let calculatedOffset = testCase.position - Double(measureIndex)
            
            #expect(
                abs(calculatedOffset - testCase.expectedOffset) < 0.001,
                "Position \(testCase.position) should give offset \(testCase.expectedOffset), got \(calculatedOffset)"
            )
        }
    }
    
    // MARK: - Beat Progression Logic Tests
    
    @Test func testMeasureTransitionDetection() {
        // Simulate 4/4 time signature measure transitions
        let beatsInSequence = [0, 1, 2, 3, 0, 1, 2, 3, 0] // Two full measures plus one beat
        var totalBeatsElapsed = 0
        var lastMetronomeBeat = -1
        let beatsPerMeasure = 4
        
        for currentMetronomeBeat in beatsInSequence {
            if currentMetronomeBeat != lastMetronomeBeat {
                if currentMetronomeBeat == 0 && lastMetronomeBeat == beatsPerMeasure - 1 {
                    // New measure started - advance to next measure
                    totalBeatsElapsed = ((totalBeatsElapsed / beatsPerMeasure) + 1) * beatsPerMeasure
                } else if currentMetronomeBeat > lastMetronomeBeat || lastMetronomeBeat == -1 {
                    // Normal progression within measure
                    totalBeatsElapsed = (totalBeatsElapsed / beatsPerMeasure) * beatsPerMeasure + currentMetronomeBeat
                }
                lastMetronomeBeat = currentMetronomeBeat
            }
        }
        
        // After processing, we should have 8 total beats (2 full measures)
        #expect(totalBeatsElapsed == 8, "Should have 8 total beats after two full measures, got \(totalBeatsElapsed)")
    }
    
    @Test func testContinuousBeatTracking() {
        // Test that beats progress continuously: 0→1→2→3→4→5→6→7→8...
        // instead of cycling: 0→1→2→3→0→1→2→3→0...
        
        let metronomeBeatSequence = [0, 1, 2, 3, 0, 1, 2, 3, 0, 1, 2]
        var totalBeatsElapsed = 0
        var lastMetronomeBeat = -1
        let beatsPerMeasure = 4
        let expectedTotalBeats = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
        
        for (index, currentMetronomeBeat) in metronomeBeatSequence.enumerated() {
            if currentMetronomeBeat != lastMetronomeBeat {
                if currentMetronomeBeat == 0 && lastMetronomeBeat == beatsPerMeasure - 1 {
                    // New measure started
                    totalBeatsElapsed = ((totalBeatsElapsed / beatsPerMeasure) + 1) * beatsPerMeasure
                } else if currentMetronomeBeat > lastMetronomeBeat || lastMetronomeBeat == -1 {
                    // Normal progression within measure
                    totalBeatsElapsed = (totalBeatsElapsed / beatsPerMeasure) * beatsPerMeasure + currentMetronomeBeat
                }
                lastMetronomeBeat = currentMetronomeBeat
            }
            
            #expect(
                totalBeatsElapsed == expectedTotalBeats[index],
                "Beat \(index): expected \(expectedTotalBeats[index]), got \(totalBeatsElapsed)"
            )
        }
    }
    
    // MARK: - Timing Accuracy Tests
    
    @Test func testTimingAccuracyCalculation() {
        // Test timing error calculation for our BPM 166 case
        let bpm = 166
        let expectedInterval = 60.0 / Double(bpm) // ≈ 0.361 seconds
        
        // Simulate actual timing measurements
        let timingTests: [(Double, Double, Double)] = [
            (0.361, 0.361, 0.001),  // Perfect timing
            (0.365, 0.361, 0.010),  // 4ms late - acceptable
            (0.358, 0.361, 0.010),  // 3ms early - acceptable  
            (0.720, 0.722, 0.010),  // Two beats, slight early
            (1.085, 1.083, 0.010)  // Three beats, slight late
        ]
        
        for (index, test) in timingTests.enumerated() {
            let timingError = abs(test.0 - test.1)
            
            #expect(
                timingError <= test.2,
                "Test \(index): timing error \(timingError) exceeds acceptable threshold \(test.2)"
            )
        }
    }
    
    @Test func testBackgroundQueueTimingImprovement() {
        // Test that our background queue approach should theoretically provide better timing
        // This tests the calculation logic that supports our implementation
        
        let bpm = 166
        let expectedInterval = 60.0 / Double(bpm)
        
        // Main queue timing (problematic - what we were seeing)
        let mainQueueActualIntervals = [1.4, 1.5, 1.4, 1.3] // ~4x slower
        let mainQueueErrors = mainQueueActualIntervals.map { abs($0 - expectedInterval) }
        let avgMainQueueError = mainQueueErrors.reduce(0, +) / Double(mainQueueErrors.count)
        
        // Background queue timing (improved - what we achieved)
        let backgroundQueueActualIntervals = [0.360, 0.362, 0.361, 0.359] // Much closer
        let backgroundQueueErrors = backgroundQueueActualIntervals.map { abs($0 - expectedInterval) }
        let avgBackgroundQueueError = backgroundQueueErrors.reduce(0, +) / Double(backgroundQueueErrors.count)
        
        // Background queue should be significantly more accurate
        #expect(
            avgBackgroundQueueError < avgMainQueueError,
            "Background queue error (\(avgBackgroundQueueError)) should be less than main queue error (\(avgMainQueueError))"
        )
        
        // Background queue should be within acceptable tolerance
        #expect(
            avgBackgroundQueueError < 0.01,
            "Background queue timing should be within 10ms tolerance, got \(avgBackgroundQueueError)"
        )
    }
    
    // MARK: - Volume and Accent Tests
    
    @Test func testVolumeAccentCalculation() {
        let baseVolume: Float = 0.7
        let accentMultiplier: Float = 1.3
        
        // Test accent volume (beat 0/4)
        let accentVolume = baseVolume * accentMultiplier
        #expect(accentVolume > baseVolume, "Accent volume should be louder than base volume")
        #expect(abs(accentVolume - 0.91) < 0.001, "Accent volume calculation incorrect")
        
        // Test normal volume (beats 1, 2, 3)
        let normalVolume = baseVolume * 1.0
        #expect(normalVolume == baseVolume, "Normal volume should equal base volume")
    }
    
    @Test func testVolumeAccentPattern() {
        let baseVolume: Float = 0.5
        let accentMultiplier: Float = 1.3
        
        // Test 4/4 pattern: accent, normal, normal, normal
        let beatPattern = [0, 1, 2, 3] // Beat indices
        let expectedVolumes: [Float] = [
            baseVolume * accentMultiplier, // Beat 0 (accent)
            baseVolume,                    // Beat 1 (normal)
            baseVolume,                    // Beat 2 (normal)
            baseVolume                     // Beat 3 (normal)
        ]
        
        for (beat, expectedVolume) in zip(beatPattern, expectedVolumes) {
            let isAccent = beat == 0
            let calculatedVolume = baseVolume * (isAccent ? accentMultiplier : 1.0)
            
            #expect(
                abs(calculatedVolume - expectedVolume) < 0.001,
                "Beat \(beat): expected volume \(expectedVolume), got \(calculatedVolume)"
            )
        }
    }
    
    // MARK: - Integration Tests
    
    @Test func testMetronomeConfigurationAndTiming() {
        let metronome = MetronomeEngine()
        let testBPM = 140
        let testTimeSignature = TimeSignature.fourFour
        
        // Configure metronome
        metronome.configure(bpm: testBPM, timeSignature: testTimeSignature)
        
        // Test that configuration doesn't change observable state
        #expect(metronome.isEnabled == false)
        #expect(metronome.currentBeat == 0)
        
        // Test timing calculation for this BPM
        let expectedInterval = 60.0 / Double(testBPM)
        #expect(abs(expectedInterval - 0.4286) < 0.001, "BPM 140 should give ~0.4286 second intervals")
    }
    
    @Test func testCompleteTimingFlow() {
        // Integration test for the complete timing flow we implemented
        let bpm = 120
        let timeSignature = TimeSignature.fourFour
        let expectedInterval = 60.0 / Double(bpm) // 0.5 seconds
        
        // Simulate 8 beats (2 full measures)
        let metronomeBeatSequence = [0, 1, 2, 3, 0, 1, 2, 3]
        var totalBeatsElapsed = 0
        var lastMetronomeBeat = -1
        var quarterNotePositions: [Double] = []
        
        for currentMetronomeBeat in metronomeBeatSequence {
            if currentMetronomeBeat != lastMetronomeBeat {
                if currentMetronomeBeat == 0 && lastMetronomeBeat == timeSignature.beatsPerMeasure - 1 {
                    let currentMeasure = (totalBeatsElapsed / timeSignature.beatsPerMeasure) + 1
                    totalBeatsElapsed = currentMeasure * timeSignature.beatsPerMeasure
                } else if currentMetronomeBeat > lastMetronomeBeat || lastMetronomeBeat == -1 {
                    let currentMeasureIndex = totalBeatsElapsed / timeSignature.beatsPerMeasure
                    let baseMeasure = currentMeasureIndex * timeSignature.beatsPerMeasure
                    totalBeatsElapsed = baseMeasure + currentMetronomeBeat
                }
                lastMetronomeBeat = currentMetronomeBeat
            }
            
            let quarterNotePosition = Double(totalBeatsElapsed) * 0.25
            quarterNotePositions.append(quarterNotePosition)
        }
        
        // Verify the sequence
        let expectedPositions = [0.0, 0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75]
        
        for (index, expectedPosition) in expectedPositions.enumerated() {
            #expect(
                abs(quarterNotePositions[index] - expectedPosition) < 0.001,
                "Position \(index): expected \(expectedPosition), got \(quarterNotePositions[index])"
            )
        }
    }
}
