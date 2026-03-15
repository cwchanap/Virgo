//
//  BeatProgressionTests.swift
//  VirgoTests
//
//  This file now contains only essential beat progression tests.
//  Other tests have been moved to separate files for better organization.
//
//  Created by Chan Wai Chan on 1/8/2025.
//

import Testing
import Foundation
@testable import Virgo

struct BeatProgressionTests {

    @Test func testBasicBeatProgression() {
        let timeSignature = TimeSignature.fourFour
        let quarterNotePosition = 0.25

        let currentMeasureIndex = Int(quarterNotePosition)
        let currentMeasureOffset = quarterNotePosition - Double(currentMeasureIndex)
        let beatPosition = currentMeasureOffset * Double(timeSignature.beatsPerMeasure)

        #expect(currentMeasureIndex == 0)
        #expect(abs(currentMeasureOffset - 0.25) < 0.001)
        #expect(abs(beatPosition - 1.0) < 0.001)
    }

    @Test func testBeatProgressionAcrossMultipleMeasures() {
        let timeSignature = TimeSignature.fourFour
        // Positions at each quarter note boundary across 3 measures
        let testCases: [(position: Double, expectedMeasure: Int, expectedBeat: Double)] = [
            (0.00, 0, 0.0),   // Start of measure 1
            (0.25, 0, 1.0),   // Beat 2 of measure 1
            (0.50, 0, 2.0),   // Beat 3 of measure 1
            (0.75, 0, 3.0),   // Beat 4 of measure 1
            (1.00, 1, 0.0),   // Start of measure 2
            (1.25, 1, 1.0),   // Beat 2 of measure 2
            (2.00, 2, 0.0),   // Start of measure 3
            (2.75, 2, 3.0)    // Beat 4 of measure 3
        ]

        for testCase in testCases {
            let measureIndex = Int(testCase.position)
            let measureOffset = testCase.position - Double(measureIndex)
            let beatPosition = measureOffset * Double(timeSignature.beatsPerMeasure)

            #expect(measureIndex == testCase.expectedMeasure)
            #expect(abs(beatPosition - testCase.expectedBeat) < 0.001)
        }
    }

    @Test func testBeatProgressionIn3_4Time() {
        let timeSignature = TimeSignature.threeFour
        // 3/4 has 3 beats per measure, so each beat is 1/3 of a measure
        let testCases: [(position: Double, expectedMeasure: Int, expectedBeat: Double)] = [
            (0.000, 0, 0.0),
            (1.0 / 3.0, 0, 1.0),
            (2.0 / 3.0, 0, 2.0),
            (1.000, 1, 0.0),
            (1.0 + 1.0 / 3.0, 1, 1.0)
        ]

        for testCase in testCases {
            let measureIndex = Int(testCase.position)
            let measureOffset = testCase.position - Double(measureIndex)
            let beatPosition = measureOffset * Double(timeSignature.beatsPerMeasure)

            #expect(measureIndex == testCase.expectedMeasure)
            #expect(abs(beatPosition - testCase.expectedBeat) < 0.01)
        }
    }

    @Test func testBeatProgressionIn6_8Time() {
        let timeSignature = TimeSignature.sixEight
        // 6/8 has 6 beats per measure
        let position = 0.5   // halfway through measure 1
        let measureIndex = Int(position)
        let measureOffset = position - Double(measureIndex)
        let beatPosition = measureOffset * Double(timeSignature.beatsPerMeasure)

        #expect(measureIndex == 0)
        #expect(abs(beatPosition - 3.0) < 0.001)  // 0.5 * 6 = 3
    }

    @Test func testBeatProgressionStartOfEachMeasureIsAlwaysBeatZero() {
        let timeSignatures: [TimeSignature] = [.twoFour, .threeFour, .fourFour, .fiveFour, .sixEight]
        let measureCount = 5

        for signature in timeSignatures {
            for measureNum in 0..<measureCount {
                let position = Double(measureNum) + 0.0
                let measureIndex = Int(position)
                let measureOffset = position - Double(measureIndex)
                let beatPosition = measureOffset * Double(signature.beatsPerMeasure)

                #expect(measureIndex == measureNum)
                #expect(abs(beatPosition - 0.0) < 0.001)
            }
        }
    }

    @Test func testBeatPositionNeverExceedsBeatsPerMeasure() {
        let timeSignature = TimeSignature.fourFour
        // Test various positions within a single measure
        let offsets: [Double] = [0.0, 0.1, 0.25, 0.5, 0.75, 0.9, 0.99]
        for offset in offsets {
            let beatPosition = offset * Double(timeSignature.beatsPerMeasure)
            #expect(beatPosition >= 0.0)
            #expect(beatPosition < Double(timeSignature.beatsPerMeasure))
        }
    }
}
