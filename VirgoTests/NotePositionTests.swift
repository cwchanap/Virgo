//
//  NotePositionTests.swift
//  VirgoTests
//
//  Created by Chan Wai Chan on 1/8/2025.
//

import Testing
import Foundation
@testable import Virgo

struct NotePositionTests {

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
}
