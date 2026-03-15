//
//  SwiftDataRelationshipLoaderTests.swift
//  VirgoTests
//
//  Created by Claude Code on 4/8/2025.
//

import Testing
import SwiftData
import SwiftUI
import Foundation
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

    @Test("SongRelationshipLoader computes chart count, measure count, and sorted difficulties")
    func testSongRelationshipLoaderComputedData() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context

            let song = TestModelFactory.createSong(in: context, title: "Loader Song", artist: "Loader Artist")
            let hardChart = TestModelFactory.createChart(in: context, difficulty: .hard, song: song)
            let easyChart = TestModelFactory.createChart(in: context, difficulty: .easy, song: song)
            let duplicateEasyChart = TestModelFactory.createChart(in: context, difficulty: .easy, song: song)

            let noteA = TestModelFactory.createNote(
                in: context,
                interval: .quarter,
                noteType: .snare,
                measureNumber: 2,
                measureOffset: 0.0,
                chart: hardChart
            )
            let noteB = TestModelFactory.createNote(
                in: context,
                interval: .eighth,
                noteType: .bass,
                measureNumber: 5,
                measureOffset: 0.5,
                chart: easyChart
            )

            hardChart.notes = [noteA]
            easyChart.notes = [noteB]
            duplicateEasyChart.notes = []
            song.charts = [hardChart, easyChart, duplicateEasyChart]
            try context.save()

            let loader = SongRelationshipLoader(song: song)
            let loaded = await TestHelpers.waitFor(
                condition: {
                    loader.relationshipData.chartCount == 3 &&
                    loader.relationshipData.measureCount == 5 &&
                    loader.relationshipData.availableDifficulties == [.easy, .hard] &&
                    loader.isLoading == false
                },
                timeout: 2.0,
                checkInterval: 0.01
            )

            #expect(loaded)
            #expect(loader.relationshipData.chartCount == 3)
            #expect(loader.relationshipData.measureCount == 5)
            #expect(loader.relationshipData.charts.count == 3)
            #expect(loader.relationshipData.availableDifficulties == [.easy, .hard])
            #expect(loader.isLoading == false)
            loader.stopObserving()
        }
    }

    @Test("ChartRelationshipLoader computes notes count and measure count")
    func testChartRelationshipLoaderComputedData() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context

            let song = TestModelFactory.createSong(in: context)
            let chart = TestModelFactory.createChart(in: context, difficulty: .medium, song: song)

            let note1 = TestModelFactory.createNote(
                in: context,
                interval: .quarter,
                noteType: .bass,
                measureNumber: 1,
                measureOffset: 0.0,
                chart: chart
            )
            let note2 = TestModelFactory.createNote(
                in: context,
                interval: .eighth,
                noteType: .snare,
                measureNumber: 4,
                measureOffset: 0.5,
                chart: chart
            )

            chart.notes = [note1, note2]
            song.charts = [chart]
            try context.save()

            let loader = ChartRelationshipLoader(chart: chart)
            let loaded = await TestHelpers.waitFor(
                condition: {
                    loader.relationshipData.notesCount == 2 &&
                    loader.relationshipData.measureCount == 4 &&
                    loader.relationshipData.notes.count == 2 &&
                    loader.isLoading == false
                },
                timeout: 2.0,
                checkInterval: 0.01
            )

            #expect(loaded)
            #expect(loader.relationshipData.notesCount == 2)
            #expect(loader.relationshipData.measureCount == 4)
            #expect(loader.relationshipData.notes.count == 2)
            #expect(loader.isLoading == false)
            loader.stopObserving()
        }
    }

    @Test("BaseSwiftDataRelationshipLoader refresh reloads and replaces previous data")
    func testBaseLoaderRefreshReplacesData() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let mockSong = TestModelFactory.createSong(in: context)

            var loadCount = 0
            let loader = BaseSwiftDataRelationshipLoader(
                model: mockSong,
                defaultData: 0
            ) { _ in
                try? await Task.sleep(nanoseconds: 20_000_000)
                loadCount += 1
                return loadCount
            }

            let initialLoaded = await TestHelpers.waitFor(
                condition: { loader.relationshipData >= 1 && loader.isLoading == false },
                timeout: 1.5,
                checkInterval: 0.01
            )

            #expect(initialLoaded)
            let firstValue = loader.relationshipData
            #expect(firstValue >= 1)

            loader.refresh()
            let refreshed = await TestHelpers.waitFor(
                condition: { loader.relationshipData > firstValue && loader.isLoading == false },
                timeout: 1.5,
                checkInterval: 0.01
            )

            #expect(refreshed)
            #expect(loader.relationshipData > firstValue)
            loader.stopObserving()
        }
    }

    @Test("BaseSwiftDataRelationshipLoader stopObserving cancels in-flight load")
    func testBaseLoaderStopObservingCancelsLoad() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let mockSong = TestModelFactory.createSong(in: context)

            let loader = BaseSwiftDataRelationshipLoader(
                model: mockSong,
                defaultData: "default"
            ) { _ in
                try? await Task.sleep(nanoseconds: 300_000_000)
                return "loaded"
            }

            // Cancel any auto-started load first so we can control timing for this assertion.
            loader.stopObserving()

            let loadingTask = Task {
                await loader.loadRelationshipData()
            }

            try await Task.sleep(nanoseconds: 30_000_000)
            loader.stopObserving()
            await loadingTask.value

            #expect(loader.relationshipData == "default")
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

// MARK: - PersistentIdentifierPersistenceKey.Resolution Tests

@Suite("PersistentIdentifierPersistenceKey Resolution Tests")
struct PersistentIdentifierPersistenceKeyResolutionTests {

    @Test("Resolution.needsMigration is false when canonicalKey equals matchedKey")
    func testNeedsMigrationFalseWhenKeysMatch() {
        let resolution = PersistentIdentifierPersistenceKey.Resolution(
            canonicalKey: "chart_abc123",
            matchedKey: "chart_abc123",
            value: 42
        )
        #expect(resolution.needsMigration == false)
    }

    @Test("Resolution.needsMigration is true when canonicalKey differs from matchedKey")
    func testNeedsMigrationTrueWhenKeysDiffer() {
        let resolution = PersistentIdentifierPersistenceKey.Resolution(
            canonicalKey: "chart_abc123",
            matchedKey: "old_chart_key",
            value: 42
        )
        #expect(resolution.needsMigration == true)
    }

    @Test("Resolution stores its value correctly")
    func testResolutionStoresValue() {
        let resolution = PersistentIdentifierPersistenceKey.Resolution(
            canonicalKey: "key",
            matchedKey: "key",
            value: "test-value"
        )
        #expect(resolution.value == "test-value")
    }

    @Test("Resolution stores canonicalKey and matchedKey correctly")
    func testResolutionStoresKeys() {
        let resolution = PersistentIdentifierPersistenceKey.Resolution(
            canonicalKey: "canonical",
            matchedKey: "matched",
            value: true
        )
        #expect(resolution.canonicalKey == "canonical")
        #expect(resolution.matchedKey == "matched")
    }

    @Test("Resolution works with various value types")
    func testResolutionWithVariousValueTypes() {
        let intResolution = PersistentIdentifierPersistenceKey.Resolution(
            canonicalKey: "k1", matchedKey: "k1", value: 100
        )
        let stringResolution = PersistentIdentifierPersistenceKey.Resolution(
            canonicalKey: "k2", matchedKey: "k2", value: "score"
        )
        let doubleResolution = PersistentIdentifierPersistenceKey.Resolution(
            canonicalKey: "k3", matchedKey: "k3", value: 3.14
        )
        #expect(intResolution.value == 100)
        #expect(stringResolution.value == "score")
        #expect(abs(doubleResolution.value - 3.14) < 0.001)
    }

    @Test("Resolution.needsMigration is true for empty canonicalKey with non-empty matchedKey")
    func testNeedsMigrationWithEmptyCanonicalKey() {
        let resolution = PersistentIdentifierPersistenceKey.Resolution(
            canonicalKey: "",
            matchedKey: "old_key",
            value: 0
        )
        #expect(resolution.needsMigration == true)
    }

    @Test("Resolution.needsMigration is false for both empty keys")
    func testNeedsMigrationWithBothEmptyKeys() {
        let resolution = PersistentIdentifierPersistenceKey.Resolution(
            canonicalKey: "",
            matchedKey: "",
            value: 0
        )
        #expect(resolution.needsMigration == false)
    }
}
