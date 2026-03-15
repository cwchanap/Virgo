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

    // Shared helper encapsulating the beat-position calculation used throughout
    // these tests. Centralising it here means a change to the formula is caught
    // in one place rather than silently missing some test cases.
    private func beatProgress(
        for position: Double,
        in timeSignature: TimeSignature
    ) -> (measureIndex: Int, measureOffset: Double, beatPosition: Double) {
        let measureIndex = Int(position)
        let measureOffset = position - Double(measureIndex)
        let beatPosition = measureOffset * Double(timeSignature.beatsPerMeasure)
        return (measureIndex, measureOffset, beatPosition)
    }

    @Test func testBasicBeatProgression() {
        let progress = beatProgress(for: 0.25, in: .fourFour)

        #expect(progress.measureIndex == 0)
        #expect(abs(progress.measureOffset - 0.25) < 0.001)
        #expect(abs(progress.beatPosition - 1.0) < 0.001)
    }

    @Test func testBeatProgressionAcrossMultipleMeasures() {
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
            let progress = beatProgress(for: testCase.position, in: .fourFour)
            #expect(progress.measureIndex == testCase.expectedMeasure)
            #expect(abs(progress.beatPosition - testCase.expectedBeat) < 0.001)
        }
    }

    @Test func testBeatProgressionIn3_4Time() {
        // 3/4 has 3 beats per measure, so each beat is 1/3 of a measure
        let testCases: [(position: Double, expectedMeasure: Int, expectedBeat: Double)] = [
            (0.000, 0, 0.0),
            (1.0 / 3.0, 0, 1.0),
            (2.0 / 3.0, 0, 2.0),
            (1.000, 1, 0.0),
            (1.0 + 1.0 / 3.0, 1, 1.0)
        ]

        for testCase in testCases {
            let progress = beatProgress(for: testCase.position, in: .threeFour)
            #expect(progress.measureIndex == testCase.expectedMeasure)
            #expect(abs(progress.beatPosition - testCase.expectedBeat) < 0.01)
        }
    }

    @Test func testBeatProgressionIn6_8Time() {
        // 6/8 has 6 beats per measure; halfway through = beat 3
        let progress = beatProgress(for: 0.5, in: .sixEight)
        #expect(progress.measureIndex == 0)
        #expect(abs(progress.beatPosition - 3.0) < 0.001)
    }

    @Test func testBeatProgressionStartOfEachMeasureIsAlwaysBeatZero() {
        let timeSignatures: [TimeSignature] = [.twoFour, .threeFour, .fourFour, .fiveFour, .sixEight]

        for signature in timeSignatures {
            for measureNum in 0..<5 {
                let progress = beatProgress(for: Double(measureNum), in: signature)
                #expect(progress.measureIndex == measureNum)
                #expect(abs(progress.beatPosition - 0.0) < 0.001)
            }
        }
    }

    @Test func testBeatPositionNeverExceedsBeatsPerMeasure() {
        let timeSignature = TimeSignature.fourFour
        let offsets: [Double] = [0.0, 0.1, 0.25, 0.5, 0.75, 0.9, 0.99]
        for offset in offsets {
            let progress = beatProgress(for: offset, in: timeSignature)
            #expect(progress.beatPosition >= 0.0)
            #expect(progress.beatPosition < Double(timeSignature.beatsPerMeasure))
        }
    }
}
