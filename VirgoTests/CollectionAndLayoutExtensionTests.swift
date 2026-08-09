//
//  CollectionAndLayoutExtensionTests.swift
//  VirgoTests
//
//  Tests for:
//  - Array.removingDuplicates() extension (order, deduplication, edge cases)
//  - GameplayLayout.NotePosition gap positions (spaceBetween1And2, spaceBetweenLine1AndBelow)
//

import Testing
import SwiftUI
@testable import Virgo

// MARK: - Array.removingDuplicates()

@Suite("Array removingDuplicates Tests")
struct ArrayRemovingDuplicatesTests {

    @Test("removingDuplicates on empty array returns empty array")
    func testEmptyArray() {
        let empty: [Int] = []
        #expect(empty.removingDuplicates().isEmpty)
    }

    @Test("removingDuplicates on single-element array returns same element")
    func testSingleElement() {
        let single = [42]
        #expect(single.removingDuplicates() == [42])
    }

    @Test("removingDuplicates removes duplicate integers while preserving first occurrence")
    func testDeduplicatesIntegers() {
        let input = [1, 2, 3, 2, 1, 4]
        let result = input.removingDuplicates()
        #expect(result == [1, 2, 3, 4])
    }

    @Test("removingDuplicates preserves original order")
    func testPreservesOrder() {
        let input = [5, 3, 1, 3, 5, 2, 1]
        let result = input.removingDuplicates()
        #expect(result == [5, 3, 1, 2])
    }

    @Test("removingDuplicates on array with no duplicates returns same elements")
    func testNoDuplicates() {
        let input = [10, 20, 30, 40]
        #expect(input.removingDuplicates() == [10, 20, 30, 40])
    }

    @Test("removingDuplicates on all-same elements returns single element")
    func testAllSame() {
        let input = [7, 7, 7, 7, 7]
        #expect(input.removingDuplicates() == [7])
    }

    @Test("removingDuplicates works with String elements")
    func testStringElements() {
        let input = ["rock", "jazz", "rock", "pop", "jazz"]
        let result = input.removingDuplicates()
        #expect(result == ["rock", "jazz", "pop"])
    }

    @Test("removingDuplicates works with Difficulty enum elements")
    func testDifficultyElements() {
        let input: [Difficulty] = [.easy, .hard, .easy, .medium, .hard]
        let result = input.removingDuplicates()
        #expect(result == [.easy, .hard, .medium])
    }
}

// MARK: - GameplayLayout.NotePosition Gap Positions

@Suite("GameplayLayout NotePosition Gap Tests")
struct GameplayLayoutNotePositionGapTests {

    @Test("spaceBetween1And2 yOffset is -0.5 * staffLineSpacing")
    func testSpaceBetween1And2YOffset() {
        let expected = -0.5 * GameplayLayout.staffLineSpacing
        #expect(GameplayLayout.NotePosition.spaceBetween1And2.yOffset == expected)
    }

    @Test("spaceBetweenLine1AndBelow yOffset is +0.5 * staffLineSpacing")
    func testSpaceBetweenLine1AndBelowYOffset() {
        let expected = 0.5 * GameplayLayout.staffLineSpacing
        #expect(GameplayLayout.NotePosition.spaceBetweenLine1AndBelow.yOffset == expected)
    }

    @Test("spaceBetween1And2 yOffset is halfway between line1 and line2")
    func testSpaceBetween1And2IsHalfway() {
        let line1 = GameplayLayout.NotePosition.line1.yOffset
        let line2 = GameplayLayout.NotePosition.line2.yOffset
        let midpoint = (line1 + line2) / 2
        #expect(GameplayLayout.NotePosition.spaceBetween1And2.yOffset == midpoint)
    }

    @Test("spaceBetweenLine1AndBelow yOffset is halfway between line1 and belowLine1")
    func testSpaceBetweenLine1AndBelowIsHalfway() {
        let line1 = GameplayLayout.NotePosition.line1.yOffset
        let belowLine1 = GameplayLayout.NotePosition.belowLine1.yOffset
        let midpoint = (line1 + belowLine1) / 2
        #expect(GameplayLayout.NotePosition.spaceBetweenLine1AndBelow.yOffset == midpoint)
    }

    @Test("spaceBetween1And2 yOffset is negative (above staff baseline)")
    func testSpaceBetween1And2IsNegative() {
        #expect(GameplayLayout.NotePosition.spaceBetween1And2.yOffset < 0)
    }

    @Test("spaceBetweenLine1AndBelow yOffset is positive (below staff baseline)")
    func testSpaceBetweenLine1AndBelowIsPositive() {
        #expect(GameplayLayout.NotePosition.spaceBetweenLine1AndBelow.yOffset > 0)
    }
}
