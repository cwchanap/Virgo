//
//  SwiftDataRelationshipLoaderTests.swift
//  VirgoTests
//
//  Created by Claude Code on 4/8/2025.
//

import Testing
import SwiftData
import SwiftUI
@testable import Virgo

@Suite("SwiftData Relationship Loader Tests")
@MainActor
struct SwiftDataRelationshipLoaderTests {

    @Test("SongRelationshipData initializes with default values")
    func testSongRelationshipDataInitialization() {
        let data = SongRelationshipData(
            chartCount: 0,
            measureCount: 1,
            charts: [],
            availableDifficulties: []
        )

        #expect(data.chartCount == 0)
        #expect(data.measureCount == 1)
        #expect(data.charts.isEmpty)
        #expect(data.availableDifficulties.isEmpty)
    }

    @Test("ChartRelationshipData initializes with default values")
    func testChartRelationshipDataInitialization() {
        let data = ChartRelationshipData(
            notesCount: 0,
            notes: [],
            measureCount: 1
        )

        #expect(data.notesCount == 0)
        #expect(data.notes.isEmpty)
        #expect(data.measureCount == 1)
    }

    @Test("BaseSwiftDataRelationshipLoader initializes correctly")
    func testBaseLoaderInitialization() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let mockSong = TestModelFactory.createSong(in: context)
            let defaultData = SongRelationshipData(
                chartCount: 0,
                measureCount: 1,
                charts: [],
                availableDifficulties: []
            )

            let loader = BaseSwiftDataRelationshipLoader(
                model: mockSong,
                defaultData: defaultData
            ) { _ in
                return defaultData
            }

            // Wait for loading to complete
            let loadingCompleted = await CombineTestUtilities.waitForLoading(
                object: loader,
                isLoadingKeyPath: \.isLoading,
                timeout: 1.0
            )

            #expect(loadingCompleted, "Loading should complete")
            #expect(loader.relationshipData.chartCount == 0)
            #expect(loader.isLoading == false)
        }
    }

    @Test("Array removingDuplicates extension works correctly")
    func testRemovingDuplicates() {
        let array = [1, 2, 2, 3, 3, 3, 4]
        let uniqueArray = array.removingDuplicates()

        #expect(uniqueArray == [1, 2, 3, 4])
        #expect(uniqueArray.count == 4)
    }

    @Test("Array removingDuplicates preserves order")
    func testRemovingDuplicatesPreservesOrder() {
        let array = [3, 1, 4, 1, 5, 9, 2, 6, 5, 3, 5]
        let uniqueArray = array.removingDuplicates()

        #expect(uniqueArray == [3, 1, 4, 5, 9, 2, 6])
        #expect(uniqueArray.first == 3)
        #expect(uniqueArray.last == 6)
    }

    @Test("Array removingDuplicates handles empty array")
    func testRemovingDuplicatesEmptyArray() {
        let emptyArray: [Int] = []
        let result = emptyArray.removingDuplicates()

        #expect(result.isEmpty)
    }
}
