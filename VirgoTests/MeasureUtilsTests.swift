//
//  MeasureUtilsTests.swift
//  VirgoTests
//
//  Created by Chan Wai Chan on 1/8/2025.
//

import Testing
import Foundation
@testable import Virgo

struct MeasureUtilsTests {

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

    @Test func testMeasureIndexExtractionLargeValues() {
        #expect(MeasureUtils.measureIndex(from: 100.0) == 100)
        #expect(MeasureUtils.measureIndex(from: 999.99) == 999)
        #expect(MeasureUtils.measureIndex(from: 1000.0) == 1000)
    }

    @Test func testTimePositionWithZeroOffset() {
        // measureNumber 1 with offset 0 = position 0.0 (first measure, start)
        #expect(MeasureUtils.timePosition(measureNumber: 1, measureOffset: 0.0) == 0.0)
        // measureNumber 10 with offset 0 = position 9.0
        #expect(MeasureUtils.timePosition(measureNumber: 10, measureOffset: 0.0) == 9.0)
    }

    @Test func testTimePositionWithFullOffset() {
        // measureOffset 1.0 would be the start of the next measure
        let position = MeasureUtils.timePosition(measureNumber: 3, measureOffset: 1.0)
        // measure 3 = index 2, index 2 + 1.0 = 3.0
        #expect(abs(position - 3.0) < 0.001)
    }

    @Test func testConversionRoundTripLargeValues() {
        for value in [10, 50, 100, 500] {
            let oneBased = MeasureUtils.toOneBasedNumber(value)
            let backToZero = MeasureUtils.toZeroBasedIndex(oneBased)
            #expect(backToZero == value)
        }
    }

    @Test func testMeasureIndexFromTimePositionMatchesConversion() {
        // measureIndex(from:) and toZeroBasedIndex should be consistent with integer positions
        for i in 0..<10 {
            let timePos = Double(i)
            let indexFromTimePos = MeasureUtils.measureIndex(from: timePos)
            #expect(indexFromTimePos == i)
        }
    }

    @Test func testTimePositionConsistencyWithMeasureIndex() {
        // timePosition then measureIndex should return the original zero-based index
        for measureNum in 1...10 {
            let timePos = MeasureUtils.timePosition(measureNumber: measureNum, measureOffset: 0.0)
            let measureIdx = MeasureUtils.measureIndex(from: timePos)
            #expect(measureIdx == MeasureUtils.toZeroBasedIndex(measureNum))
        }
    }
}
