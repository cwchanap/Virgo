//
//  CollectionAndLayoutExtensionTests.swift
//  VirgoTests
//
//  Tests for:
//  - Array.removingDuplicates() extension (order, deduplication, edge cases)
//  - GameplayLayout.NotePosition gap positions (spaceBetween1And2, spaceBetweenLine1AndBelow)
//  - PersistentIdentifierPersistenceKey.Resolution.needsMigration
//  - BeamGroupingHelper threshold boundary (exactly 0.3 apart = grouped; > 0.3 = not grouped)
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

// MARK: - PersistentIdentifierPersistenceKey.Resolution.needsMigration

@Suite("PersistentIdentifierPersistenceKey Resolution Tests")
struct PersistentIdentifierResolutionTests {

    @Test("needsMigration is false when canonicalKey equals matchedKey")
    func testNeedsMigrationFalseWhenKeysEqual() {
        let resolution = PersistentIdentifierPersistenceKey.Resolution(
            canonicalKey: "key-abc",
            matchedKey: "key-abc",
            value: 42
        )
        #expect(resolution.needsMigration == false)
    }

    @Test("needsMigration is true when canonicalKey differs from matchedKey")
    func testNeedsMigrationTrueWhenKeysDiffer() {
        let resolution = PersistentIdentifierPersistenceKey.Resolution(
            canonicalKey: "canonical-key",
            matchedKey: "legacy-key",
            value: "some-value"
        )
        #expect(resolution.needsMigration == true)
    }

    @Test("needsMigration is false for empty string keys that match")
    func testNeedsMigrationFalseForEmptyMatchingKeys() {
        let resolution = PersistentIdentifierPersistenceKey.Resolution(
            canonicalKey: "",
            matchedKey: "",
            value: 0
        )
        #expect(resolution.needsMigration == false)
    }

    @Test("needsMigration is true even for single character difference")
    func testNeedsMigrationTrueForMinorKeyDifference() {
        let resolution = PersistentIdentifierPersistenceKey.Resolution(
            canonicalKey: "key-v2",
            matchedKey: "key-v1",
            value: true
        )
        #expect(resolution.needsMigration == true)
    }

    @Test("Resolution stores the value regardless of migration state")
    func testResolutionStoresValue() {
        let resolution = PersistentIdentifierPersistenceKey.Resolution(
            canonicalKey: "new-key",
            matchedKey: "old-key",
            value: 999
        )
        #expect(resolution.value == 999)
        #expect(resolution.canonicalKey == "new-key")
        #expect(resolution.matchedKey == "old-key")
    }
}

// MARK: - BeamGroupingHelper Threshold Boundary

@Suite("BeamGroupingHelper Threshold Boundary Tests")
struct BeamGroupingHelperThresholdTests {

    // maxConsecutiveInterval = 0.3 (inclusive boundary: timeDifference <= 0.3)

    @Test("Notes exactly 0.3 apart in same measure ARE grouped (inclusive boundary)")
    func testExactThresholdIsGrouped() {
        let beats = [
            DrumBeat(id: 1, drums: [.snare], timePosition: 1.0, interval: .eighth),
            DrumBeat(id: 2, drums: [.hiHat], timePosition: 1.3, interval: .eighth)
        ]
        let groups = BeamGroupingHelper.calculateBeamGroups(from: beats)
        #expect(groups.count == 1)
        #expect(groups.first?.beats.count == 2)
    }

    @Test("Notes just over 0.3 apart in same measure are NOT grouped")
    func testJustOverThresholdIsNotGrouped() {
        // 0.301 > 0.3 → separate groups, each with 1 note → no beam group
        let beats = [
            DrumBeat(id: 1, drums: [.snare], timePosition: 1.0, interval: .eighth),
            DrumBeat(id: 2, drums: [.hiHat], timePosition: 1.301, interval: .eighth)
        ]
        let groups = BeamGroupingHelper.calculateBeamGroups(from: beats)
        #expect(groups.isEmpty)
    }

    @Test("Three notes each 0.125 apart are all grouped together")
    func testThreeConsecutiveNotesGrouped() {
        let beats = [
            DrumBeat(id: 1, drums: [.snare], timePosition: 2.0, interval: .eighth),
            DrumBeat(id: 2, drums: [.hiHat], timePosition: 2.125, interval: .eighth),
            DrumBeat(id: 3, drums: [.kick],  timePosition: 2.25,  interval: .eighth)
        ]
        let groups = BeamGroupingHelper.calculateBeamGroups(from: beats)
        #expect(groups.count == 1)
        #expect(groups.first?.beats.count == 3)
    }

    @Test("Notes at exactly 0.0 apart (same time) are grouped")
    func testZeroTimeDifferenceGrouped() {
        let beats = [
            DrumBeat(id: 1, drums: [.snare], timePosition: 0.0, interval: .eighth),
            DrumBeat(id: 2, drums: [.hiHat], timePosition: 0.0, interval: .eighth)
        ]
        let groups = BeamGroupingHelper.calculateBeamGroups(from: beats)
        #expect(groups.count == 1)
    }

    @Test("Notes in different measures are NOT grouped even if time values are close")
    func testDifferentMeasuresAreNotGrouped() {
        // Int(0.9) = 0, Int(1.0) = 1 → different measure numbers
        let beats = [
            DrumBeat(id: 1, drums: [.snare], timePosition: 0.9, interval: .eighth),
            DrumBeat(id: 2, drums: [.hiHat], timePosition: 1.0, interval: .eighth)
        ]
        let groups = BeamGroupingHelper.calculateBeamGroups(from: beats)
        #expect(groups.isEmpty)
    }
}
