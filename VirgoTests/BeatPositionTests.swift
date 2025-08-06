//
//  BeatPositionTests.swift
//  VirgoTests
//
//  Created by Chan Wai Chan on 1/8/2025.
//

import Testing
import Foundation
import SwiftUI
@testable import Virgo

struct BeatPositionTests {

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
}
