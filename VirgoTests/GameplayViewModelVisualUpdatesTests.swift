//
//  GameplayViewModelVisualUpdatesTests.swift
//  VirgoTests
//

import Testing
import Foundation
import AVFoundation
import Observation
import SwiftUI
@testable import Virgo

@Suite("Visual Updates", .serialized)
@MainActor
// swiftlint:disable:next type_body_length
struct GameplayViewModelVisualUpdatesTests {

    @Test("updateVisualElementsFromMetronome updates playback progress and indicators while playing")
    func testUpdateVisualElementsFromMetronomeUpdatesPlaybackIndicators() async throws {
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 8)
        let metronome = GameplayViewModelTestHarness.createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()
        viewModel.setupGameplay(loadPersistedSpeed: false)
        viewModel.isPlaying = true

        let didStart = await CombineTestUtilities.performAndWait(
            action: {
                metronome.startAtTime(
                    bpm: viewModel.effectiveBPM(),
                    timeSignature: .fourFour,
                    startTime: CFAbsoluteTimeGetCurrent() - 1.0
                )
            },
            publisher: metronome.$isEnabled,
            condition: { $0 == true },
            timeout: 0.5
        )
        #expect(didStart, "Metronome should start before visual updates are calculated")

        viewModel.updateVisualElementsFromMetronome()

        #expect(viewModel.playbackProgress > 0.0)
        #expect(viewModel.currentMeasureIndex == viewModel.totalBeatsElapsed / 4)
        #expect(viewModel.currentBeatPosition >= 0.0)
        #expect(viewModel.currentBeatPosition < 1.0)
        let expectedMeasureFraction = viewModel.currentQuarterNotePosition / 4
            - Double(viewModel.currentMeasureIndex)
        #expect(abs(viewModel.currentBeatPosition - expectedMeasureFraction) < 0.0001)
        #expect(viewModel.totalBeatsElapsed >= 1)
        #expect(viewModel.purpleBarPosition != nil)

        metronome.stop()
        viewModel.cleanup()
    }

    @Test("updateVisualElementsFromMetronome returns early when track duration was not initialized")
    func testUpdateVisualElementsFromMetronomeSkipsWhenTrackDurationMissing() async throws {
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 8)
        let metronome = GameplayViewModelTestHarness.createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()
        #expect(viewModel.track != nil, "loadChartData must succeed for this test to exercise the duration guard")
        #expect(viewModel.cachedTrackDuration == 0.0, "cachedTrackDuration should be 0 before setupGameplay is called")
        viewModel.isPlaying = true
        viewModel.currentMeasureIndex = 99
        viewModel.currentBeatPosition = 0.25
        viewModel.playbackProgress = 0.5

        viewModel.updateVisualElementsFromMetronome()

        #expect(viewModel.currentMeasureIndex == 99)
        #expect(abs(viewModel.currentBeatPosition - 0.25) < 0.0001)
        #expect(abs(viewModel.playbackProgress - 0.5) < 0.0001)

        viewModel.cleanup()
    }

    @Test("timeline purple bar moves continuously within each measure")
    func testTimelinePurpleBarMovesContinuouslyWithinMeasure() async throws {
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 8)
        let metronome = GameplayViewModelTestHarness.createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()
        viewModel.setupGameplay(loadPersistedSpeed: false)
        viewModel.isPlaying = true

        // At 120 BPM in 4/4, one beat is 0.5s. The playhead should hold
        // between beat boundaries, then jump to each beat within the measure.
        viewModel.updatePurpleBarPosition(elapsedTime: 0.01)
        let positionAtStart = try #require(viewModel.purpleBarPosition)

        viewModel.updatePurpleBarPosition(elapsedTime: 0.49)
        let positionBeforeSecondBeat = try #require(viewModel.purpleBarPosition)

        viewModel.updatePurpleBarPosition(elapsedTime: 0.51)
        let positionAtSecondBeat = try #require(viewModel.purpleBarPosition)

        viewModel.updatePurpleBarPosition(elapsedTime: 0.99)
        let positionBeforeThirdBeat = try #require(viewModel.purpleBarPosition)

        viewModel.updatePurpleBarPosition(elapsedTime: 1.01)
        let positionAtThirdBeat = try #require(viewModel.purpleBarPosition)

        #expect(positionBeforeSecondBeat.x > positionAtStart.x)
        #expect(abs(positionAtStart.y - positionBeforeSecondBeat.y) < 0.0001)
        #expect(positionAtSecondBeat.x > positionBeforeSecondBeat.x)
        #expect(positionBeforeThirdBeat.x > positionAtSecondBeat.x)
        #expect(positionAtThirdBeat.x > positionBeforeThirdBeat.x)

        viewModel.cleanup()
    }

    @Test("purple bar beat-boundary quantization follows the chart time signature")
    func testPurpleBarBeatBoundaryQuantizationFollowsTimeSignature() async throws {
        let chart = Chart(difficulty: .medium, timeSignature: .threeFour)
        chart.notes.append(Note(interval: .quarter, noteType: .bass, measureNumber: 1, measureOffset: 0.0))
        chart.notes.append(Note(interval: .quarter, noteType: .snare, measureNumber: 2, measureOffset: 0.0))
        let metronome = GameplayViewModelTestHarness.createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()
        viewModel.setupGameplay(loadPersistedSpeed: false)
        viewModel.isPlaying = true

        // At 120 BPM in 3/4, one beat is 0.5s and the next measure starts
        // after the third beat slot.
        viewModel.updatePurpleBarPosition(elapsedTime: 0.01)
        let positionAtStart = try #require(viewModel.purpleBarPosition)

        viewModel.updatePurpleBarPosition(elapsedTime: 0.51)
        let positionAtSecondBeat = try #require(viewModel.purpleBarPosition)

        viewModel.updatePurpleBarPosition(elapsedTime: 1.01)
        let positionAtThirdBeat = try #require(viewModel.purpleBarPosition)

        viewModel.updatePurpleBarPosition(elapsedTime: 1.51)
        let positionAtNextMeasure = try #require(viewModel.purpleBarPosition)

        #expect(abs(positionAtSecondBeat.x - positionAtStart.x) > 0.0001)
        #expect(abs(positionAtThirdBeat.x - positionAtSecondBeat.x) > 0.0001)
        #expect(abs(positionAtNextMeasure.x - positionAtThirdBeat.x) > 0.0001)

        viewModel.cleanup()
    }

    @Test func testVisualTickThrottlesObservablePlaybackProgressUpdates() async throws {
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 32)
        let metronome = GameplayViewModelTestHarness.createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()
        viewModel.setupGameplay(loadPersistedSpeed: false)
        viewModel.isPlaying = true

        viewModel.updateContinuousVisualsForTesting(elapsedTime: 1.00)
        let firstPublishedProgress = viewModel.playbackProgress

        viewModel.updateContinuousVisualsForTesting(elapsedTime: 1.02)
        #expect(
            viewModel.playbackProgress == firstPublishedProgress,
            "A 30 Hz visual tick should not publish playbackProgress on every frame"
        )

        viewModel.updateContinuousVisualsForTesting(elapsedTime: 1.12)
        #expect(
            viewModel.playbackProgress > firstPublishedProgress,
            "Progress should still publish after the throttle interval"
        )

        viewModel.cleanup()
    }

    @Test func testPurpleBarPositionWhenNotPlaying() async throws {
        let chart = GameplayViewModelTestHarness.createTestChart()
        let metronome = GameplayViewModelTestHarness.createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()
        viewModel.setupGameplay()

        viewModel.isPlaying = false
        let position = viewModel.calculatePurpleBarPosition()

        #expect(position == nil)
    }

    @Test func testNotationPurpleBarPositionUsesTabGridMapper() async throws {
        let chart = Chart(difficulty: .medium, timeSignature: .fourFour)
        chart.notes.append(
            Note(interval: .sixteenth, noteType: .snare, measureNumber: 1, measureOffset: 0.0)
        )
        chart.notes.append(
            Note(interval: .sixteenth, noteType: .bass, measureNumber: 1, measureOffset: 1.0 / 16.0)
        )
        let metronome = GameplayViewModelTestHarness.createTestMetronome()
        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)

        await viewModel.loadChartData()
        viewModel.setupGameplay(loadPersistedSpeed: false)

        let measure = try #require(viewModel.cachedNotationLayout.measures.first)
        let position = try #require(
            viewModel.calculateNotationPurpleBarPosition(measureIndex: 0, beatWithinMeasure: 1.0)
        )
        let tick = viewModel.cachedNotationLayout.tabGrid.tickIndex(
            forBeatWithinMeasure: 1.0,
            beatsPerMeasure: 4
        )
        let expectedX = viewModel.cachedNotationLayout.tabGrid.xPosition(in: measure, tickIndex: tick)

        #expect(abs(position.x - Double(expectedX)) < 0.001)
    }

    @Test func testRowForMeasureUsesRenderedNotationRows() async throws {
        let chart = Chart(difficulty: .medium, timeSignature: .fourFour)
        for measure in 1...4 {
            chart.notes.append(
                Note(interval: .quarter, noteType: .snare, measureNumber: measure, measureOffset: 0.0)
            )
        }
        let metronome = GameplayViewModelTestHarness.createTestMetronome()
        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)

        await viewModel.loadChartData()
        viewModel.cachedLayoutRowWidth = 620
        viewModel.setupGameplay(loadPersistedSpeed: false)

        let measureRows = Dictionary(
            uniqueKeysWithValues: viewModel.cachedNotationLayout.measures.map { ($0.measureIndex, $0.row) }
        )

        #expect(viewModel.rowForMeasure(0) == measureRows[0])
        #expect(viewModel.rowForMeasure(1) == measureRows[1])
        #expect(viewModel.rowForMeasure(3) == measureRows[3])
    }

    @Test func testPurpleBarPositionUsesResumedElapsedTime() async throws {
        let chart = Chart(difficulty: .medium, timeSignature: .fourFour)
        chart.notes.append(
            Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0.0)
        )
        chart.notes.append(
            Note(interval: .quarter, noteType: .bass, measureNumber: 2, measureOffset: 0.0)
        )
        let metronome = GameplayViewModelTestHarness.createTestMetronome()
        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)

        await viewModel.loadChartData()
        viewModel.setupGameplay(loadPersistedSpeed: false)
        viewModel.isPlaying = true
        viewModel.pausedElapsedTime = 2.0

        let position = try #require(
            viewModel.calculatePurpleBarPosition(elapsedTime: viewModel.pausedElapsedTime)
        )
        let expectedPosition = try #require(
            viewModel.calculateNotationPurpleBarPosition(measureIndex: 1, beatWithinMeasure: 0.0)
        )

        #expect(abs(position.x - expectedPosition.x) < 0.001)
        #expect(abs(position.y - expectedPosition.y) < 0.001)
    }

    @Test func testNotationPurpleBarPositionClampsAtEndOfTrack() async throws {
        // Creates a chart with one measure (measureIndex 0) at BPM 120 (4 beats per measure)
        // At elapsedTime = 2.0 seconds: 2 * 120 / 60 = 4 beats, measureIndex = 4 / 4 = 1
        // This is one past the last measure, so the position should clamp to the last measure
        let chart = Chart(difficulty: .medium, timeSignature: .fourFour)
        chart.notes.append(
            Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0.0)
        )
        let metronome = GameplayViewModelTestHarness.createTestMetronome()
        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)

        await viewModel.loadChartData()
        viewModel.setupGameplay(loadPersistedSpeed: false)
        viewModel.isPlaying = true

        // calculateNotationPurpleBarPosition directly returns nil when measure doesn't exist
        #expect(viewModel.calculateNotationPurpleBarPosition(measureIndex: 1, beatWithinMeasure: 0.0) == nil)
        // But calculatePurpleBarPosition clamps to the last valid measure at track end
        #expect(viewModel.calculatePurpleBarPosition(elapsedTime: 2.0) != nil)
    }

    @Test func testPurpleBarClampsToEndOfFinalMeasure() async throws {
        // One measure, 4/4 at BPM 120. At elapsedTime = 2.0s:
        // totalBeatsElapsed = 4.0, measureIndex = 1 (past last measure).
        // The bar should be at the END of measure 0 (beatWithinMeasure = 4.0),
        // NOT at the start (beatWithinMeasure = 0.0).
        let chart = Chart(difficulty: .medium, timeSignature: .fourFour)
        chart.notes.append(
            Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0.0)
        )
        let metronome = GameplayViewModelTestHarness.createTestMetronome()
        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)

        await viewModel.loadChartData()
        viewModel.setupGameplay(loadPersistedSpeed: false)
        viewModel.isPlaying = true

        let clampedPosition = try #require(
            viewModel.calculatePurpleBarPosition(elapsedTime: 2.0)
        )
        let measure = try #require(viewModel.cachedNotationLayout.measures.first)
        let endTick = viewModel.cachedNotationLayout.tabGrid.ticksPerMeasure
        let expectedX = viewModel.cachedNotationLayout.tabGrid.xPosition(in: measure, tickIndex: endTick)

        #expect(abs(clampedPosition.x - Double(expectedX)) < 0.5)

        // Verify it's NOT at the start of the measure (beat 0)
        let startX = measure.xOffset
            + GameplayLayout.barLineWidth
            + GameplayLayout.uniformSpacing
        #expect(abs(clampedPosition.x - Double(startX)) > 1.0)
    }

    @Test func testTimelinePurpleBarUsesExactSubBeatPosition() async throws {
        let chart = Chart(difficulty: .medium, timeSignature: .fourFour)
        chart.notes.append(
            Note(interval: .sixteenth, noteType: .snare, measureNumber: 1, measureOffset: 0.0625)
        )
        let metronome = GameplayViewModelTestHarness.createTestMetronome()
        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)

        await viewModel.loadChartData()
        viewModel.setupGameplay(loadPersistedSpeed: false)
        viewModel.isPlaying = true

        let position = try #require(
            viewModel.calculatePurpleBarPosition(elapsedTime: 0.125)
        )
        let measure = try #require(viewModel.cachedNotationLayout.measures.first)
        let expectedX = viewModel.cachedNotationLayout.tabGrid.xPosition(in: measure, tickIndex: 1)

        #expect(abs(position.x - Double(expectedX)) < 0.5)
    }

    @Test("renderable rest-only notation does not move playhead or current row")
    func testRestOnlyNotationDoesNotMovePlayheadOrCurrentRow() async throws {
        let chart = Chart(difficulty: .medium, timeSignature: .fourFour)
        let song = Song(
            title: "Silent Practice",
            artist: "Test",
            bpm: 120,
            duration: "0:20",
            genre: "Test",
            charts: [chart]
        )
        chart.song = song
        let viewModel = GameplayViewModel(
            chart: chart,
            metronome: GameplayViewModelTestHarness.createTestMetronome()
        )
        await viewModel.loadChartData()
        viewModel.setupGameplay(loadPersistedSpeed: false)
        viewModel.isPlaying = true
        viewModel.currentRow = 2

        #expect(viewModel.cachedNotationLayout.hasRenderableContent)
        #expect(!viewModel.cachedNotationLayout.hasPlayableContent)
        #expect(viewModel.rowForMeasure(8) == 2)

        viewModel.updateContinuousVisualsForTesting(elapsedTime: 18)

        #expect(viewModel.currentRow == 2)
        #expect(viewModel.purpleBarPosition == nil)
    }

    @Test("renderable control-only notation does not move playhead or current row")
    func testControlOnlyNotationDoesNotMovePlayheadOrCurrentRow() async throws {
        let chart = Chart(difficulty: .medium, timeSignature: .fourFour)
        chart.controlEvents.append(ChartControlEvent(
            kind: .damp,
            measureNumber: 4,
            measureOffset: 0.5,
            targetLaneID: "1A"
        ))
        let viewModel = GameplayViewModel(
            chart: chart,
            metronome: GameplayViewModelTestHarness.createTestMetronome()
        )
        await viewModel.loadChartData()
        viewModel.setupGameplay(loadPersistedSpeed: false)
        viewModel.isPlaying = true
        viewModel.currentRow = 1

        #expect(viewModel.cachedNotationLayout.hasRenderableContent)
        #expect(!viewModel.cachedNotationLayout.hasPlayableContent)
        #expect(viewModel.rowForMeasure(3) == 1)

        viewModel.updateContinuousVisualsForTesting(elapsedTime: 6)

        #expect(viewModel.currentRow == 1)
        #expect(viewModel.purpleBarPosition == nil)
    }

    // MARK: - currentRow / Auto-scroll

    /// Builds a multi-row chart so that measure layout actually wraps onto a new row,
    /// then verifies rowForMeasure resolves the correct row for each measure index.
    @Test func testCurrentRowAdvancesAsPlayheadCrossesRowBoundary() async throws {
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

        // Find the first measure that lives on a row > 0; we need the playhead to land in it.
        let firstNonZeroRowMeasure = viewModel.cachedNotationLayout.measures
            .first(where: { $0.row > 0 })
        try #require(firstNonZeroRowMeasure != nil)
        let targetMeasure = firstNonZeroRowMeasure!.measureIndex
        let targetRow = firstNonZeroRowMeasure!.row

        // Initial state: row 0.
        #expect(viewModel.currentRow == 0)

        // Drive the visuals forward to the target measure. currentRow is updated
        // unconditionally on every tick when isPlaying == true.
        viewModel.isPlaying = true
        let bpm = viewModel.effectiveBPM()
        let secondsPerBeat = 60.0 / bpm
        let beatsPerMeasure = Double(chart.timeSignature.beatsPerMeasure)
        // Land squarely inside the target measure so continuousMeasureIdx == targetMeasure.
        let elapsedSeconds = (Double(targetMeasure) + 0.5) * beatsPerMeasure * secondsPerBeat

        viewModel.updateContinuousVisualsForTesting(elapsedTime: elapsedSeconds)

        #expect(viewModel.currentRow == targetRow,
                "Playhead in measure \(targetMeasure) should set currentRow to \(targetRow)")

        // Resetting playback should snap currentRow back to 0.
        viewModel.isPlaying = false
        viewModel.restartPlayback()
        #expect(viewModel.currentRow == 0)
    }

}
