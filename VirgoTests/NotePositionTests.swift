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

    @Test func testNotePositionKeyMillisecondRoundingEquality() {
        // Two offsets that differ by less than 1ms should be treated as equal
        let key1 = NotePositionKey(measureNumber: 1, measureOffset: 0.2504)   // rounds to 250ms
        let key2 = NotePositionKey(measureNumber: 1, measureOffset: 0.2501)   // rounds to 250ms
        let key3 = NotePositionKey(measureNumber: 1, measureOffset: 0.2509)   // rounds to 250ms
        let key4 = NotePositionKey(measureNumber: 1, measureOffset: 0.2510)   // rounds to 251ms

        #expect(key1 == key2)
        #expect(key1 == key3)
        #expect(key1 != key4)
    }

    @Test func testNotePositionKeyUsableAsDictionaryKey() {
        var noteDict: [NotePositionKey: String] = [:]
        let key1 = NotePositionKey(measureNumber: 1, measureOffset: 0.0)
        let key2 = NotePositionKey(measureNumber: 1, measureOffset: 0.25)
        let key3 = NotePositionKey(measureNumber: 2, measureOffset: 0.0)

        noteDict[key1] = "beat 1"
        noteDict[key2] = "beat 1.25"
        noteDict[key3] = "measure 2 start"

        #expect(noteDict.count == 3)
        #expect(noteDict[key1] == "beat 1")
        #expect(noteDict[key2] == "beat 1.25")
        #expect(noteDict[key3] == "measure 2 start")

        // Inserting equivalent key overwrites existing entry
        let key1Duplicate = NotePositionKey(measureNumber: 1, measureOffset: 0.0)
        noteDict[key1Duplicate] = "overwritten"
        #expect(noteDict.count == 3)
        #expect(noteDict[key1] == "overwritten")
    }

    @Test func testNotePositionKeyZeroValues() {
        let key = NotePositionKey(measureNumber: 0, measureOffset: 0.0)
        #expect(key.measureNumber == 0)
        #expect(key.measureOffset == 0.0)
        #expect(key.measureOffsetInMilliseconds == 0)
    }

    @Test func testNotePositionKeyLargeMeasureNumbers() {
        let key = NotePositionKey(measureNumber: 1000, measureOffset: 0.999)
        #expect(key.measureNumber == 1000)
        #expect(key.measureOffsetInMilliseconds == 999)
    }

    @Test func testNotePositionKeyHashConsistency() {
        // Same key created twice should produce same hash
        let key1 = NotePositionKey(measureNumber: 5, measureOffset: 0.75)
        let key2 = NotePositionKey(measureNumber: 5, measureOffset: 0.75)
        var hasher1 = Hasher()
        var hasher2 = Hasher()
        key1.hash(into: &hasher1)
        key2.hash(into: &hasher2)
        #expect(hasher1.finalize() == hasher2.finalize())
    }
}
