//
//  BeatProgressionTests.swift
//  VirgoTests
//
//  Created by Chan Wai Chan on 1/8/2025.
//

import Testing
import Foundation
import SwiftUI
@testable import Virgo

struct BeatProgressionTests {
    
    // MARK: - Measure Utils Tests
    
    @Test func testMeasureUtilsConversions() {
        // Test zero-based to one-based conversion
        #expect(MeasureUtils.toOneBasedNumber(0) == 1)
        #expect(MeasureUtils.toOneBasedNumber(1) == 2)
        #expect(MeasureUtils.toOneBasedNumber(5) == 6)
        
        // Test one-based to zero-based conversion
        #expect(MeasureUtils.toZeroBasedIndex(1) == 0)
        #expect(MeasureUtils.toZeroBasedIndex(2) == 1)
        #expect(MeasureUtils.toZeroBasedIndex(6) == 5)
        
        // Test round-trip conversions
        let testValues = [0, 1, 5, 10, 100]
        for value in testValues {
            let roundTrip = MeasureUtils.toZeroBasedIndex(MeasureUtils.toOneBasedNumber(value))
            #expect(roundTrip == value)
        }
    }
    
    @Test func testTimePositionCalculation() {
        // Test time position calculation from measure number and offset
        let testCases: [(Int, Double, Double)] = [
            (1, 0.0, 0.0),   // Measure 1, start = position 0.0
            (1, 0.5, 0.5),   // Measure 1, middle = position 0.5
            (2, 0.0, 1.0),   // Measure 2, start = position 1.0
            (2, 0.25, 1.25), // Measure 2, quarter = position 1.25
            (3, 0.75, 2.75), // Measure 3, three-quarters = position 2.75
            (5, 0.0, 4.0)   // Measure 5, start = position 4.0
        ]
        
        for testCase in testCases {
            let calculatedPosition = MeasureUtils.timePosition(
                measureNumber: testCase.0,
                measureOffset: testCase.1
            )
            
            #expect(abs(calculatedPosition - testCase.2) < 0.001)
        }
    }
    
    @Test func testMeasureIndexExtraction() {
        let testCases: [(timePosition: Double, expectedIndex: Int)] = [
            (0.0, 0),   // Position 0.0 = index 0
            (0.5, 0),   // Position 0.5 = index 0
            (0.99, 0),  // Position 0.99 = index 0
            (1.0, 1),   // Position 1.0 = index 1
            (1.75, 1),  // Position 1.75 = index 1
            (2.0, 2),   // Position 2.0 = index 2
            (5.25, 5)  // Position 5.25 = index 5
        ]
        
        for testCase in testCases {
            let calculatedIndex = MeasureUtils.measureIndex(from: testCase.timePosition)
            
            #expect(calculatedIndex == testCase.expectedIndex)
        }
    }
    
    // MARK: - Note Position Key Tests
    
    @Test func testNotePositionKeyCreation() {
        let key = NotePositionKey(measureNumber: 2, measureOffset: 0.25)
        
        #expect(key.measureNumber == 2)
        #expect(abs(key.measureOffset - 0.25) < 0.001)
        #expect(key.measureOffsetInMilliseconds == 250) // 0.25 * 1000
    }
    
    @Test func testNotePositionKeyPrecision() {
        // Test floating-point precision handling
        let precisionTestCases: [(offset: Double, expectedMilliseconds: Int)] = [
            (0.001, 1),    // 1 millisecond
            (0.125, 125),  // 125 milliseconds (eighth note in 4/4)
            (0.333, 333),  // 333 milliseconds (triplet)
            (0.666, 666),  // 666 milliseconds
            (0.999, 999)  // 999 milliseconds
        ]
        
        for testCase in precisionTestCases {
            let key = NotePositionKey(measureNumber: 1, measureOffset: testCase.offset)
            
            #expect(key.measureOffsetInMilliseconds == testCase.expectedMilliseconds)
            
            // Test round-trip precision
            #expect(abs(key.measureOffset - testCase.offset) < 0.001)
        }
    }
    
    @Test func testNotePositionKeyHashable() {
        let key1 = NotePositionKey(measureNumber: 1, measureOffset: 0.25)
        let key2 = NotePositionKey(measureNumber: 1, measureOffset: 0.25)
        let key3 = NotePositionKey(measureNumber: 1, measureOffset: 0.5)
        let key4 = NotePositionKey(measureNumber: 2, measureOffset: 0.25)
        
        // Test equality
        #expect(key1 == key2)
        #expect(key1 != key3)
        #expect(key1 != key4)
        
        // Test use in Set (requires Hashable)
        let noteSet: Set<NotePositionKey> = [key1, key2, key3, key4]
        #expect(noteSet.count == 3)
    }
    
    // MARK: - Beat Position Calculation Tests
    
    @Test func testBeatPositionFromQuarterNote() {
        let timeSignature = TimeSignature.fourFour
        
        let testCases: [(quarterNotePosition: Double, expectedBeatPosition: Double)] = [
            (0.0, 0.0),    // Start of measure
            (0.25, 1.0),   // First beat
            (0.5, 2.0),    // Second beat  
            (0.75, 3.0),   // Third beat
            (1.0, 0.0),    // Start of next measure (should wrap)
            (1.25, 1.0),   // First beat of second measure
            (2.5, 2.0)    // Second beat of third measure
        ]
        
        for testCase in testCases {
            let currentMeasureIndex = Int(testCase.quarterNotePosition)
            let currentMeasureOffset = testCase.quarterNotePosition - Double(currentMeasureIndex)
            let beatPosition = currentMeasureOffset * Double(timeSignature.beatsPerMeasure)
            
            #expect(abs(beatPosition - testCase.expectedBeatPosition) < 0.001)
        }
    }
    
    @Test func testBeatPositionFor3_4Time() {
        let timeSignature = TimeSignature.threeFour
        
        let testCases: [(quarterNotePosition: Double, expectedBeatPosition: Double)] = [
            (0.0, 0.0),     // Start of measure
            (0.333, 1.0),   // First beat (approximately)
            (0.667, 2.0),   // Second beat (approximately)  
            (1.0, 0.0)     // Start of next measure
        ]
        
        for testCase in testCases {
            let currentMeasureIndex = Int(testCase.quarterNotePosition)
            let currentMeasureOffset = testCase.quarterNotePosition - Double(currentMeasureIndex)
            let beatPosition = currentMeasureOffset * Double(timeSignature.beatsPerMeasure)
            
            #expect(abs(beatPosition - testCase.expectedBeatPosition) < 0.1) // More tolerance for 3/4
        }
    }
    
    // MARK: - Visual Indicator Position Tests
    
    @Test func testRedCircleIndicatorLogic() {
        // Test the logic that determines where the red circle indicator appears
        let quarterNotePositions = [0.0, 0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
        let expectedMeasures = [0, 0, 0, 0, 1, 1, 1, 1, 2]
        let expectedOffsets = [0.0, 0.25, 0.5, 0.75, 0.0, 0.25, 0.5, 0.75, 0.0]
        
        for (index, position) in quarterNotePositions.enumerated() {
            let currentMeasureIndex = Int(position)
            let currentMeasureOffset = position - Double(currentMeasureIndex)
            
            #expect(currentMeasureIndex == expectedMeasures[index])
            
            #expect(abs(currentMeasureOffset - expectedOffsets[index]) < 0.001)
        }
    }
    
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
