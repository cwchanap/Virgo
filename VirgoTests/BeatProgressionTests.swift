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
}
