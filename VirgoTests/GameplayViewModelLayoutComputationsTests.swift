//
//  GameplayViewModelLayoutComputationsTests.swift
//  VirgoTests
//

import Testing
import Foundation
import AVFoundation
import Observation
import SwiftUI
@testable import Virgo

@Suite("Layout Computations", .serialized)
@MainActor
struct GameplayViewModelLayoutComputationsTests {

    @Test func testComputeDrumBeats() async throws {
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 8)
        let metronome = GameplayViewModelTestHarness.createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()

        viewModel.computeDrumBeats()

        // Notes at same position should be grouped
        #expect(!viewModel.cachedDrumBeats.isEmpty)
        #expect(viewModel.cachedBeatIndices.count == viewModel.cachedDrumBeats.count)

        // Verify beats are sorted by time position
        for i in 1..<viewModel.cachedDrumBeats.count {
            #expect(viewModel.cachedDrumBeats[i].timePosition >= viewModel.cachedDrumBeats[i-1].timePosition)
        }
    }

    @Test func testComputeDrumBeatsWithEmptyNotes() async throws {
        let chart = Chart(difficulty: .easy)
        let metronome = GameplayViewModelTestHarness.createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()

        viewModel.computeDrumBeats()

        #expect(viewModel.cachedDrumBeats.isEmpty)
        #expect(viewModel.cachedBeatIndices.isEmpty)
    }

    @Test("Timeline beat with duplicate legacy fraction retains stable canonical identity")
    func timelineBeatWithDuplicateFractionRetainsIdentity() async throws {
        let chart = Chart(difficulty: .medium, timeSignature: .sixEight)
        chart.notes = [
            Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: 1.0 / 3.0),
            Note(interval: .eighth, noteType: .bass, measureNumber: 1, measureOffset: 1.0 / 3.0)
        ]
        let viewModel = GameplayViewModel(
            chart: chart,
            metronome: GameplayViewModelTestHarness.createTestMetronome()
        )
        await viewModel.loadChartData()
        viewModel.setupGameplay(loadPersistedSpeed: false)
        defer { viewModel.cleanup() }

        let targets = viewModel.cachedRhythmNoteTargets
        let expectedTarget = try #require(targets.min {
            $0.eventID.rawValue < $1.eventID.rawValue
        })
        let beat = try #require(viewModel.cachedDrumBeats.first)

        #expect(targets.count == 2)
        #expect(viewModel.cachedDrumBeats.count == 1)
        #expect(beat.rhythmEventID == expectedTarget.eventID)
        #expect(beat.rhythmPosition == expectedTarget.position)
        #expect(viewModel.cachedBeatPositions[beat.id] != nil)
    }

    @Test("metadata-free DTX stays on the fixed legacy gameplay path")
    func metadataFreeDTXUsesFixedLegacyPath() async throws {
        let song = Song(
            title: "Legacy DTX",
            artist: "Tester",
            bpm: 120,
            duration: "0:02",
            genre: "DTX",
            bgmStartOffsetSeconds: 0.5
        )
        let chart = Chart(difficulty: .medium, timeSignature: .fourFour, song: song)
        chart.notes = [Note(
            interval: .quarter,
            noteType: .snare,
            measureNumber: 1,
            measureOffset: 0.25,
            chart: chart,
            originKind: .dtx,
            sourceLaneID: "12",
            sourceNoteID: "01",
            sourceGridPosition: 1,
            sourceGridSize: 4
        )]
        let metronome = ScheduledMetronomeSpy()
        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)

        await viewModel.loadChartData()
        viewModel.setupGameplay(loadPersistedSpeed: false)

        #expect(viewModel.cachedRhythmRuntime.availability == .legacy)
        #expect(viewModel.cachedRhythmRuntime.diagnostics.isEmpty)
        #expect(viewModel.cachedRhythmTimeline == nil)
        #expect(viewModel.cachedRhythmNoteTargets.isEmpty)
        #expect(viewModel.cachedDrumBeats.first?.rhythmEventID == nil)
        #expect(viewModel.cachedDrumBeats.first?.rhythmPosition == nil)
        #expect(viewModel.cachedNotationLayout.noteHeads.first?.eventID == nil)
        #expect(viewModel.bgmOffsetSeconds == 0.5)
        if case .legacy = try #require(viewModel.inputTimingConfiguration(speed: 1)) {
            // Expected fixed-grid input configuration.
        } else {
            Issue.record("Metadata-free DTX must not synthesize a partial timeline")
        }
        viewModel.startPlayback()
        #expect(metronome.startAtTimeCalls.count == 1)
        #expect(metronome.timelineStartAtTimeCalls.isEmpty)
        viewModel.cleanup()
    }

    @Test("metadata-free manual exact offsets synthesize the complete timeline path")
    func metadataFreeManualExactOffsetSynthesizesTimeline() async throws {
        let song = Song(
            title: "Manual Exact",
            artist: "Tester",
            bpm: 120,
            duration: "0:00",
            genre: "Manual"
        )
        let chart = Chart(difficulty: .medium, timeSignature: .fourFour, song: song)
        chart.notes = [Note(
            interval: .quarter,
            noteType: .snare,
            measureNumber: 1,
            measureOffset: 1.0 / 3.0,
            chart: chart
        )]
        let metronome = ScheduledMetronomeSpy()
        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)

        await viewModel.loadChartData()
        viewModel.setupGameplay(loadPersistedSpeed: false)

        let target = try #require(viewModel.cachedRhythmNoteTargets.first)
        let timeline = try #require(viewModel.cachedRhythmTimeline)
        #expect(viewModel.cachedRhythmRuntime.availability == .valid)
        #expect(target.position == viewModel.cachedDrumBeats.first?.rhythmPosition)
        #expect(target.eventID == viewModel.cachedNotationLayout.noteHeads.first?.eventID)
        #expect(timeline.seconds(for: target.position, bpm: 120, speed: 1) == target.targetSecondsAtOneX)
        if case .timeline = try #require(viewModel.inputTimingConfiguration(speed: 1)) {
            // Expected canonical input configuration.
        } else {
            Issue.record("An exactly representable manual offset must synthesize a timeline")
        }
        viewModel.startPlayback()
        #expect(metronome.startAtTimeCalls.isEmpty)
        #expect(metronome.timelineStartAtTimeCalls.count == 1)
        viewModel.cleanup()
    }

    @Test("authoritative manual durations synthesize a note-rest-note triplet")
    func manualDurationsSynthesizeNoteRestNoteTriplet() async throws {
        let chart = Chart(difficulty: .medium, timeSignature: .fourFour)
        chart.notes = [
            Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: 0),
            Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: 1.0 / 6.0),
            Note(interval: .quarter, noteType: .bass, measureNumber: 2, measureOffset: 1.0 / 8.0)
        ]
        let viewModel = GameplayViewModel(
            chart: chart,
            metronome: GameplayViewModelTestHarness.createTestMetronome()
        )

        await viewModel.loadChartData()
        viewModel.setupGameplay(loadPersistedSpeed: false)

        let snapshot = try #require(viewModel.cachedRhythmRuntime.layoutSnapshot)
        let rest = try #require(snapshot.rests.first { $0.visibility == .printed && $0.tupletID != nil })
        let tupletID = try #require(rest.tupletID)
        let memberTicks = snapshot.notes
            .filter { $0.tupletID == tupletID }
            .map(\.position.localTick)
            .sorted()

        #expect(viewModel.cachedRhythmRuntime.availability == .valid)
        #expect(memberTicks.count == 2)
        #expect(memberTicks.first.map { $0 < rest.position.localTick } == true)
        #expect(memberTicks.last.map { rest.position.localTick < $0 } == true)
        #expect(viewModel.cachedNotationLayout.tuplets.contains { $0.id == tupletID })
        viewModel.cleanup()
    }

    @Test("inadmissible manual offsets fall back wholly to playable legacy")
    func inadmissibleManualOffsetFallsBackWhollyToLegacy() async throws {
        let song = Song(
            title: "Manual Legacy",
            artist: "Tester",
            bpm: 120,
            duration: "0:02",
            genre: "Manual"
        )
        let chart = Chart(difficulty: .medium, timeSignature: .fourFour, song: song)
        chart.notes = [
            Note(interval: .quarter, noteType: .bass, measureNumber: 1, measureOffset: 0, chart: chart),
            Note(
                interval: .quarter,
                noteType: .snare,
                measureNumber: 1,
                measureOffset: 0.4142135623730951,
                chart: chart
            )
        ]
        let metronome = ScheduledMetronomeSpy()
        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)

        await viewModel.loadChartData()
        viewModel.setupGameplay(loadPersistedSpeed: false)

        #expect(viewModel.cachedRhythmRuntime.availability == .legacy)
        #expect(viewModel.cachedRhythmRuntime.diagnostics.map(\.code) == [.manualTimelineUnavailable])
        #expect(viewModel.cachedRhythmRuntime.diagnostics.allSatisfy { $0.severity == .engravingOnly })
        #expect(viewModel.cachedRhythmTimeline == nil)
        #expect(viewModel.cachedRhythmNoteTargets.isEmpty)
        #expect(viewModel.cachedNotationLayout.noteHeads.count == 2)
        #expect(viewModel.isGameplayPrepared)
        if case .legacy = try #require(viewModel.inputTimingConfiguration(speed: 1)) {
            // Expected all-or-nothing legacy fallback.
        } else {
            Issue.record("Inadmissible manual timing must not leak partial timeline state")
        }
        viewModel.startPlayback()
        #expect(viewModel.isPlaying)
        #expect(metronome.startAtTimeCalls.count == 1)
        #expect(metronome.timelineStartAtTimeCalls.isEmpty)
        viewModel.cleanup()
    }

    @Test func testComputeCachedLayoutData() async throws {
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 16)
        let metronome = GameplayViewModelTestHarness.createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()
        viewModel.computeDrumBeats()
        viewModel.computeCachedLayoutData()

        #expect(!viewModel.cachedMeasurePositions.isEmpty)
        #expect(!viewModel.measurePositionMap.isEmpty)
        #expect(viewModel.staticStaffLinesView != nil)

        // Verify measure 0 always exists
        #expect(viewModel.measurePositionMap[0] != nil)
    }

    @Test func testCacheBeatPositions() async throws {
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 8)
        let metronome = GameplayViewModelTestHarness.createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()
        viewModel.setupGameplay()

        // Verify beat positions are cached
        #expect(!viewModel.cachedBeatPositions.isEmpty)

        // Each beat should have a cached position
        for beat in viewModel.cachedDrumBeats {
            let position = viewModel.cachedBeatPositions[beat.id]
            #expect(position != nil, "Beat \(beat.id) should have cached position")
            if let pos = position {
                #expect(pos.x > 0, "X position should be positive")
                #expect(pos.y > 0, "Y position should be positive")
            }
        }
    }

    @Test func testFindClosestBeatIndex() async throws {
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 8)
        let metronome = GameplayViewModelTestHarness.createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()
        viewModel.computeDrumBeats()

        // Find beat at start
        let startIndex = viewModel.findClosestBeatIndex(measureIndex: 0, beatPosition: 0.0)
        #expect(startIndex >= 0)

        // Find beat in middle
        let midIndex = viewModel.findClosestBeatIndex(measureIndex: 0, beatPosition: 0.5)
        #expect(midIndex >= startIndex)

        // Find beat at end
        let endIndex = viewModel.findClosestBeatIndex(measureIndex: 1, beatPosition: 0.75)
        #expect(endIndex >= midIndex)
    }

    @Test func testFindClosestBeatIndexWithEmptyBeats() async throws {
        let chart = Chart(difficulty: .easy)
        let metronome = GameplayViewModelTestHarness.createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()
        viewModel.computeDrumBeats()

        // Should return 0 for empty beats
        let index = viewModel.findClosestBeatIndex(measureIndex: 0, beatPosition: 0.5)
        #expect(index == 0)
    }

    @Test func testFindClosestBeatIndexBinarySearch() async throws {
        // Create chart with many notes to test binary search
        let chart = Chart(difficulty: .hard)
        for measure in 1...4 {
            for beat in 0..<4 {
                let note = Note(
                    interval: .quarter,
                    noteType: .bass,
                    measureNumber: measure,
                    measureOffset: Double(beat) * 0.25
                )
                chart.notes.append(note)
            }
        }

        let metronome = GameplayViewModelTestHarness.createTestMetronome()
        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)

        await viewModel.loadChartData()
        viewModel.computeDrumBeats()

        // Test various positions
        let testCases: [(measureIndex: Int, beatPosition: Double)] = [
            (0, 0.0),
            (0, 0.5),
            (1, 0.25),
            (2, 0.75),
            (3, 0.5)
        ]

        for testCase in testCases {
            let index = viewModel.findClosestBeatIndex(
                measureIndex: testCase.measureIndex,
                beatPosition: testCase.beatPosition
            )
            #expect(index >= 0 && index < viewModel.cachedDrumBeats.count)
        }
    }

    @Test func testCalculateTrackDuration() async throws {
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 8)
        let metronome = GameplayViewModelTestHarness.createTestMetronome()
        let (userDefaults, _) = TestUserDefaults.makeIsolated()
        let practiceSettings = PracticeSettingsService(userDefaults: userDefaults)

        let viewModel = GameplayViewModel(
            chart: chart,
            metronome: metronome,
            practiceSettings: practiceSettings
        )
        await viewModel.loadChartData()
        viewModel.setupGameplay()

        let duration = viewModel.calculateTrackDuration()

        #expect(duration > 0)
        #expect(viewModel.cachedTrackDuration == duration)
    }

    @Test func testCalculateTrackDurationWithMultipleMeasures() async throws {
        // Create chart spanning 4 measures
        let chart = Chart(difficulty: .medium)
        for measure in 1...4 {
            let note = Note(
                interval: .quarter,
                noteType: .bass,
                measureNumber: measure,
                measureOffset: 0.0
            )
            chart.notes.append(note)
        }

        let metronome = GameplayViewModelTestHarness.createTestMetronome()
        let (userDefaults, _) = TestUserDefaults.makeIsolated()
        let practiceSettings = PracticeSettingsService(userDefaults: userDefaults)
        let viewModel = GameplayViewModel(
            chart: chart,
            metronome: metronome,
            practiceSettings: practiceSettings
        )

        await viewModel.loadChartData()
        viewModel.setupGameplay()

        let duration = viewModel.calculateTrackDuration()

        // With default 120 BPM and 4/4 time, each measure is 2 seconds
        #expect(abs(duration - 8.0) < 0.01, "Duration should be 8 seconds for 4 measures at 120 BPM")
        #expect(viewModel.cachedTrackDuration == duration)
    }

    @Test func testTrackDurationScalesWithSpeedMultiplier() async throws {
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 8)
        let metronome = GameplayViewModelTestHarness.createTestMetronome()

        let (userDefaults, _) = TestUserDefaults.makeIsolated()
        let practiceSettings = PracticeSettingsService(userDefaults: userDefaults)
        let viewModel = GameplayViewModel(chart: chart, metronome: metronome, practiceSettings: practiceSettings)
        await viewModel.loadChartData()
        viewModel.setupGameplay()

        let baseDuration = viewModel.calculateTrackDuration()
        viewModel.updateSpeed(0.5)

        // Wait for trailing-edge debounce timer to fire (100ms debounce interval + small buffer)
        try await Task.sleep(nanoseconds: 300_000_000)

        let slowedDuration = viewModel.calculateTrackDuration()
        #expect(slowedDuration > baseDuration, "Duration should increase at slower speeds")
    }

    @Test func testMeasurePositionMapContainsMeasureZero() async throws {
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 8)
        let metronome = GameplayViewModelTestHarness.createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()
        viewModel.setupGameplay()

        // Measure 0 should always exist in map
        #expect(viewModel.measurePositionMap[0] != nil)

        if let measure0 = viewModel.measurePositionMap[0] {
            #expect(measure0.measureIndex == 0)
            #expect(measure0.row == 0)
            #expect(measure0.xOffset > 0)
        }
    }

    @Test func testRowForMeasureFollowsNotationMeasureRows() async throws {
        // 8 fixed-grid measures at the default row width wrap to multiple notation rows.
        let chart = Chart(difficulty: .medium, timeSignature: .fourFour)
        for measureNumber in 1...8 {
            chart.notes.append(
                Note(interval: .quarter, noteType: .snare, measureNumber: measureNumber, measureOffset: 0.0)
            )
        }
        let metronome = GameplayViewModelTestHarness.createTestMetronome()
        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()
        viewModel.setupGameplay()

        // Sanity: layout actually produced multiple rows.
        let maxRow = viewModel.cachedNotationLayout.measures.map { $0.row }.max() ?? 0
        try #require(maxRow >= 1)

        // Each measure index must resolve to the rendered notation row.
        for measure in viewModel.cachedNotationLayout.measures {
            #expect(viewModel.rowForMeasure(measure.measureIndex) == measure.row,
                    "rowForMeasure(\(measure.measureIndex)) should equal notation row \(measure.row)")
        }

        // Out-of-range indices clamp to the last known row instead of snapping to 0.
        #expect(viewModel.rowForMeasure(9_999) == maxRow)
    }

    /// Verifies that cacheNotationLayout() populates cachedMeasureRowMap and that
    /// rowForMeasure uses it instead of scanning measures with first(where:).

    @Test func testCachedMeasureRowMapPopulatedAfterLayout() async throws {
        let chart = Chart(difficulty: .medium, timeSignature: .fourFour)
        for measureNumber in 1...8 {
            chart.notes.append(
                Note(interval: .quarter, noteType: .snare, measureNumber: measureNumber, measureOffset: 0.0)
            )
        }
        let metronome = GameplayViewModelTestHarness.createTestMetronome()
        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()
        viewModel.setupGameplay()

        // If the notation layout is active, cachedMeasureRowMap must be populated.
        if !viewModel.cachedNotationLayout.noteHeads.isEmpty {
            try #require(!viewModel.cachedMeasureRowMap.isEmpty,
                         "cachedMeasureRowMap should be populated after setupGameplay")
            // Every measure in the layout must have an entry in the map.
            for measure in viewModel.cachedNotationLayout.measures {
                #expect(viewModel.cachedMeasureRowMap[measure.measureIndex] == measure.row,
                        "cachedMeasureRowMap[\(measure.measureIndex)] should be \(measure.row)")
            }
        }
    }

    /// Verifies that cacheNotationLayout() uses default drum positions regardless
    /// of what is persisted in UserDefaults, ensuring test determinism.

    @Test func testUpdateRowWidthCancelsStaleTimerOnReturnToCachedWidth() async throws {
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 8, measuresCount: 2)
        let metronome = GameplayViewModelTestHarness.createTestMetronome()
        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()
        viewModel.setupGameplay()

        let initialRowWidth = viewModel.cachedLayoutRowWidth

        // In the test environment the debounce timer is bypassed and width changes
        // apply immediately.  This test verifies the early-return guard is safe:
        // after applying a wider width and then returning to the initial value,
        // cachedLayoutRowWidth must remain at the initial value (not at the wider
        // stale value).
        viewModel.updateRowWidth(1200)
        #expect(viewModel.cachedLayoutRowWidth == 1200,
                "Widening to 1200 should update cached width immediately in tests")

        // Return to the initial width — the guard should recognise no change is
        // needed and leave the cached value as-is.
        viewModel.updateRowWidth(initialRowWidth)
        #expect(viewModel.cachedLayoutRowWidth == initialRowWidth,
                "Returning to initial width should restore cached width")
    }
}
