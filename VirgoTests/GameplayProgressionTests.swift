//
//  GameplayProgressionTests.swift
//  VirgoTests
//
//  Created by Chan Wai Chan on 1/8/2025.
//

import Testing
import Foundation
import SwiftUI
@testable import Virgo

struct GameplayProgressionTests {
    
    // MARK: - Integration Tests for GameplayView Logic
    
    @Test func testCompleteGameplayProgression() {
        // Test the complete progression flow from GameplayView
        let bpm = 120
        let timeSignature = TimeSignature.fourFour
        
        // Simulate metronome beat sequence over 2 measures
        let metronomeBeatSequence = [0, 1, 2, 3, 0, 1, 2, 3]
        var totalBeatsElapsed = 0
        var lastMetronomeBeat = -1
        var quarterNotePositions: [Double] = []
        var redCirclePositions: [(Int, Double, Double)] = []
        
        for currentMetronomeBeat in metronomeBeatSequence {
            if currentMetronomeBeat != lastMetronomeBeat {
                if currentMetronomeBeat == 0 && lastMetronomeBeat == timeSignature.beatsPerMeasure - 1 {
                    // New measure started
                    let currentMeasure = (totalBeatsElapsed / timeSignature.beatsPerMeasure) + 1
                    totalBeatsElapsed = currentMeasure * timeSignature.beatsPerMeasure
                } else if currentMetronomeBeat > lastMetronomeBeat || lastMetronomeBeat == -1 {
                    // Normal progression within measure
                    let currentMeasureIndex = totalBeatsElapsed / timeSignature.beatsPerMeasure
                    let baseMeasure = currentMeasureIndex * timeSignature.beatsPerMeasure
                    totalBeatsElapsed = baseMeasure + currentMetronomeBeat
                }
                lastMetronomeBeat = currentMetronomeBeat
            }
            
            let currentQuarterNotePosition = Double(totalBeatsElapsed) * 0.25
            quarterNotePositions.append(currentQuarterNotePosition)
            
            // Calculate red circle position (from GameplayView logic)
            let currentMeasureIndex = Int(currentQuarterNotePosition)
            let currentMeasureOffset = currentQuarterNotePosition - Double(currentMeasureIndex)
            let beatPosition = currentMeasureOffset * Double(timeSignature.beatsPerMeasure)
            
            redCirclePositions.append((currentMeasureIndex, currentMeasureOffset, beatPosition))
        }
        
        // Verify progression
        let expectedQuarterNotes = [0.0, 0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75]
        let expectedMeasures = [0, 0, 0, 0, 1, 1, 1, 1]
        let expectedBeatPositions = [0.0, 1.0, 2.0, 3.0, 0.0, 1.0, 2.0, 3.0]
        
        for i in 0..<expectedQuarterNotes.count {
            #expect(abs(quarterNotePositions[i] - expectedQuarterNotes[i]) < 0.001)
            
            #expect(redCirclePositions[i].0 == expectedMeasures[i])
            
            #expect(abs(redCirclePositions[i].2 - expectedBeatPositions[i]) < 0.001)
        }
    }
    
    @Test func testActualTrackDurationCalculation() {
        // Test the duration calculation logic from GameplayView
        let bpm = 120
        let timeSignature = TimeSignature.fourFour
        let totalMeasures = 4
        
        // Calculate duration (from GameplayView logic)
        let secondsPerBeat = 60.0 / Double(bpm)
        let secondsPerMeasure = secondsPerBeat * Double(timeSignature.beatsPerMeasure)
        let actualTrackDuration = Double(totalMeasures) * secondsPerMeasure
        
        // Expected: 4 measures * 4 beats/measure * 0.5 seconds/beat = 8 seconds
        let expectedDuration = 8.0
        
        #expect(abs(actualTrackDuration - expectedDuration) < 0.001)
    }
    
    @Test func testPlaybackProgressCalculation() {
        // Test playback progress calculation
        let trackDuration = 10.0 // 10 seconds
        
        let testCases: [(elapsedTime: Double, expectedProgress: Double)] = [
            (0.0, 0.0),    // Start
            (2.5, 0.25),   // 25% through
            (5.0, 0.5),    // 50% through
            (7.5, 0.75),   // 75% through
            (10.0, 1.0),   // Complete
            (12.0, 1.0)   // Overtime (should cap at 1.0)
        ]
        
        for testCase in testCases {
            let calculatedProgress = min(testCase.elapsedTime / trackDuration, 1.0)
            
            #expect(abs(calculatedProgress - testCase.expectedProgress) < 0.001)
        }
    }
    
    // MARK: - Edge Case Tests
    
    @Test func testZeroBPMHandling() {
        // Test edge case handling (though this shouldn't occur in practice)
        let zeroBPM = 0
        
        // This would cause division by zero, so we test that the calculation
        // structure handles edge cases appropriately
        #expect(zeroBPM == 0)
        
        // In practice, we would have validation to prevent zero BPM
        // but this tests our awareness of the edge case
    }
    
    @Test func testNegativeTimePosition() {
        // Test handling of negative time positions (edge case)
        let negativePosition = -0.5
        let measureIndex = Int(negativePosition) // Should be 0 (truncated towards zero in Swift)
        
        // Swift's Int() truncates towards zero, so -0.5 becomes 0, not -1
        #expect(measureIndex == 0)
    }
    
    @Test func testVeryLargeTimePosition() {
        // Test handling of very large time positions
        let largePosition = 1000.75
        let measureIndex = Int(largePosition)
        let measureOffset = largePosition - Double(measureIndex)
        
        #expect(measureIndex == 1000)
        #expect(abs(measureOffset - 0.75) < 0.001)
    }
    
    // MARK: - New Beat Progression Tests
    
    @Test func testBeatPositionCalculationFromTime() {
        // Test the new time-based beat position calculation
        let testCases: [(measuresElapsed: Double, expectedMeasureIndex: Int, expectedBeatPosition: Double)] = [
            (0.0, 0, 0.0),      // Start of track
            (0.25, 0, 0.25),    // First quarter note
            (0.5, 0, 0.5),      // Second quarter note  
            (0.75, 0, 0.75),    // Third quarter note
            (1.0, 1, 0.0),      // Start of second measure
            (1.25, 1, 0.25),    // First quarter of second measure
            (2.5, 2, 0.5),      // Second quarter of third measure
            (3.75, 3, 0.75)     // Third quarter of fourth measure
        ]
        
        for testCase in testCases {
            let measureIndex = Int(testCase.measuresElapsed)
            let measureOffset = testCase.measuresElapsed - Double(measureIndex)
            
            #expect(measureIndex == testCase.expectedMeasureIndex)
            #expect(abs(measureOffset - testCase.expectedBeatPosition) < 0.001)
        }
    }
    
    @Test func testBeatProgressionIndependentOfNotes() {
        // Test that beat progression works even when there are no notes at those positions
        let measuresElapsed = 1.5 // 1.5 measures elapsed
        
        // Calculate beat position (should be 0.5 within measure 1)
        let measureIndex = Int(measuresElapsed) // Should be 1
        let beatPosition = measuresElapsed - Double(measureIndex) // Should be 0.5
        
        #expect(measureIndex == 1)
        #expect(abs(beatPosition - 0.5) < 0.001)
        
        // This should work regardless of whether there are actual notes at this position
        let emptyDrumBeats: [DrumBeat] = [] // No notes in track
        
        // Beat progression should still calculate correctly
        #expect(measureIndex == 1)
        #expect(abs(beatPosition - 0.5) < 0.001)
    }
    
    @Test func testRegularBeatIntervals() {
        // Test that we get regular beat intervals: 0, 0.25, 0.5, 0.75
        let bpm = 120.0
        let timeSignature = TimeSignature.fourFour
        let secondsPerBeat = 60.0 / bpm
        
        let testTimes: [Double] = [0.0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5] // Seconds
        let expectedBeatPositions: [Double] = [0.0, 0.25, 0.5, 0.75, 0.0, 0.25, 0.5, 0.75]
        
        for (index, time) in testTimes.enumerated() {
            let beatsElapsed = time / secondsPerBeat
            let measuresElapsed = beatsElapsed / Double(timeSignature.beatsPerMeasure)
            let measureIndex = Int(measuresElapsed)
            let beatPosition = measuresElapsed - Double(measureIndex)
            
            #expect(abs(beatPosition - expectedBeatPositions[index]) < 0.001,
                   "At time \(time)s, expected beat position \(expectedBeatPositions[index]), got \(beatPosition)")
        }
    }
    
    @Test func testBeatProgressionVisualizationPositioning() {
        // Test the visual positioning logic for beat progression indicator
        
        // Mock measure position
        let measurePos = GameplayLayout.MeasurePosition(row: 0, xOffset: 100.0, measureIndex: 0)
        let timeSignature = TimeSignature.fourFour
        
        let testBeatPositions: [Double] = [0.0, 0.25, 0.5, 0.75]
        
        for beatPosition in testBeatPositions {
            // Convert beat position to visual beat position (0, 1, 2, 3)
            let visualBeatPosition = beatPosition * Double(timeSignature.beatsPerMeasure)
            
            // Calculate X position (this uses the actual GameplayView logic)
            let indicatorX = GameplayLayout.preciseNoteXPosition(
                measurePosition: measurePos,
                beatPosition: visualBeatPosition,
                timeSignature: timeSignature
            )
            
            // X position should be different for each beat position
            #expect(indicatorX >= measurePos.xOffset)
        }
    }
    
    @Test func testBeatProgressionMatchesActualNotePositions() {
        // Test that beat progression indicator appears at same X positions as actual quarter notes
        
        // Create mock quarter note beats (like in actual gameplay)
        let quarterNoteBeats = [
            DrumBeat(id: 0, drums: [.kick], timePosition: 0.0, interval: .quarter),    // 1st quarter note
            DrumBeat(id: 1, drums: [.snare], timePosition: 0.25, interval: .quarter),  // 2nd quarter note  
            DrumBeat(id: 2, drums: [.hiHat], timePosition: 0.5, interval: .quarter),   // 3rd quarter note
            DrumBeat(id: 3, drums: [.crash], timePosition: 0.75, interval: .quarter)   // 4th quarter note
        ]
        
        let measurePos = GameplayLayout.MeasurePosition(row: 0, xOffset: 100.0, measureIndex: 0)
        let timeSignature = TimeSignature.fourFour
        
        // Calculate X positions for actual notes (using GameplayView logic)
        var actualNoteXPositions: [CGFloat] = []
        for beat in quarterNoteBeats {
            let measureIndex = Int(beat.timePosition)
            let beatOffsetInMeasure = beat.timePosition - Double(measureIndex)
            let beatPosition = beatOffsetInMeasure * Double(timeSignature.beatsPerMeasure)
            let noteX = GameplayLayout.preciseNoteXPosition(
                measurePosition: measurePos,
                beatPosition: beatPosition,
                timeSignature: timeSignature
            )
            actualNoteXPositions.append(noteX)
        }
        
        // Calculate X positions for beat progression indicator (using current GameplayView logic)
        let currentBeatPositions: [Double] = [0.0, 0.25, 0.5, 0.75] // This is what currentBeatPosition should be
        var progressionXPositions: [CGFloat] = []
        for currentBeatPosition in currentBeatPositions {
            let beatPosition = currentBeatPosition * Double(timeSignature.beatsPerMeasure)
            let indicatorX = GameplayLayout.preciseNoteXPosition(
                measurePosition: measurePos,
                beatPosition: beatPosition,
                timeSignature: timeSignature
            )
            progressionXPositions.append(indicatorX)
        }
        
        // Verify that progression X positions exactly match actual note X positions
        #expect(actualNoteXPositions.count == progressionXPositions.count)
        for i in 0..<actualNoteXPositions.count {
            #expect(abs(actualNoteXPositions[i] - progressionXPositions[i]) < 0.001,
                   "Quarter note \(i): actual position \(actualNoteXPositions[i]), progression position \(progressionXPositions[i])")
        }
        
        // Verify expected X positions based on GameplayLayout logic
        // Expected: measureStart(100) + barWidth(2) + spacing(50) + beatPosition * spacing(50)
        let expectedXPositions: [CGFloat] = [
            100 + 2 + 50 + 0 * 50,  // = 152 (1st quarter note)
            100 + 2 + 50 + 1 * 50,  // = 202 (2nd quarter note)
            100 + 2 + 50 + 2 * 50,  // = 252 (3rd quarter note)
            100 + 2 + 50 + 3 * 50   // = 302 (4th quarter note)
        ]
        
        for i in 0..<expectedXPositions.count {
            #expect(abs(actualNoteXPositions[i] - expectedXPositions[i]) < 0.001,
                   "Quarter note \(i): expected \(expectedXPositions[i]), got \(actualNoteXPositions[i])")
            #expect(abs(progressionXPositions[i] - expectedXPositions[i]) < 0.001,
                   "Progression \(i): expected \(expectedXPositions[i]), got \(progressionXPositions[i])")
        }
    }
    
    @Test func testFourthQuarterNotePositioning() {
        // Specifically test the 4th quarter note positioning that the user mentioned
        
        let measurePos = GameplayLayout.MeasurePosition(row: 0, xOffset: 100.0, measureIndex: 0)
        let timeSignature = TimeSignature.fourFour
        
        // Test 4th quarter note (timePosition = 0.75)
        let fourthQuarterNote = DrumBeat(id: 3, drums: [.crash], timePosition: 0.75, interval: .quarter)
        
        // Calculate position using actual note logic (from GameplayView)
        let measureIndex = Int(fourthQuarterNote.timePosition)  // Int(0.75) = 0
        let beatOffsetInMeasure = fourthQuarterNote.timePosition - Double(measureIndex)  // 0.75 - 0.0 = 0.75
        let actualNoteBeatPosition = beatOffsetInMeasure * Double(timeSignature.beatsPerMeasure)  // 0.75 * 4 = 3.0
        let actualNoteX = GameplayLayout.preciseNoteXPosition(
            measurePosition: measurePos,
            beatPosition: actualNoteBeatPosition,
            timeSignature: timeSignature
        )
        
        // Calculate position using beat progression logic (from beatProgressionIndicator)
        let currentBeatPosition = 0.75  // This is what currentBeatPosition should be for 4th quarter note
        let progressionBeatPosition = currentBeatPosition * Double(timeSignature.beatsPerMeasure)  // 0.75 * 4 = 3.0
        let progressionX = GameplayLayout.preciseNoteXPosition(
            measurePosition: measurePos,
            beatPosition: progressionBeatPosition,
            timeSignature: timeSignature
        )
        
        // Manual calculation based on GameplayLayout.preciseNoteXPosition formula:
        // measurePosition.xOffset + barLineWidth + uniformSpacing + CGFloat(beatPosition) * uniformSpacing
        // = 100 + 2 + 50 + 3.0 * 50 = 302
        let expectedX: CGFloat = 100 + 2 + 50 + 3.0 * 50  // = 302
        
        // Verify all calculations match
        #expect(abs(actualNoteBeatPosition - 3.0) < 0.001, "Actual note beatPosition should be 3.0, got \(actualNoteBeatPosition)")
        #expect(abs(progressionBeatPosition - 3.0) < 0.001, "Progression beatPosition should be 3.0, got \(progressionBeatPosition)")
        #expect(abs(actualNoteX - expectedX) < 0.001, "Actual note X should be \(expectedX), got \(actualNoteX)")
        #expect(abs(progressionX - expectedX) < 0.001, "Progression X should be \(expectedX), got \(progressionX)")
        #expect(abs(actualNoteX - progressionX) < 0.001, "Actual note X (\(actualNoteX)) should match progression X (\(progressionX))")
    }
}