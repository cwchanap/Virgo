//
//  GameplayViewModelActiveBeatTests.swift
//  VirgoTests
//
//  Split from GameplayViewModelVisualUpdatesTests to keep each file under the
//  SwiftLint file-length warn limit (600). Holds the active-beat selection,
//  continuous visual-tick, and current-row advance tests.
//

import Testing
import Foundation
import AVFoundation
import Observation
import SwiftUI
@testable import Virgo

@Suite("Active Beat & Row Advance", .serialized)
@MainActor
struct GameplayViewModelActiveBeatTests {

    @Test("eighth note at sub-beat offset becomes active when playhead passes it")
    func eighthNoteAtSubBeatOffsetBecomesActive() async throws {
        // In 4/4, an eighth at offset 0.125 has timePosition 0.125.
        // The metronome fires at quarter-note positions (0.0, 0.25, ...).
        // When playhead reaches 0.25, the eighth at 0.125 should be
        // highlighted via look-behind matching.
        let chart = Chart(difficulty: .medium, timeSignature: .fourFour)
        chart.notes.append(
            Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: 0.125)
        )
        let metronome = GameplayViewModelTestHarness.createTestMetronome()
        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)

        await viewModel.loadChartData()
        viewModel.setupGameplay(loadPersistedSpeed: false)
        viewModel.isPlaying = true

        // At quarter-beat 1 (timePosition 0.25), the eighth at 0.125 should be found
        viewModel.updateActiveBeat(forTimePosition: 0.25)

        let eighthBeat = try #require(viewModel.cachedDrumBeats.first)
        #expect(viewModel.activeBeatId == eighthBeat.id)
    }

    @Test("sixteenth note at sub-beat offset becomes active when playhead passes it")
    func sixteenthNoteAtSubBeatOffsetBecomesActive() async throws {
        // A sixteenth at offset 0.0625 has timePosition 0.0625.
        // When playhead reaches 0.25, it should be highlighted via look-behind.
        let chart = Chart(difficulty: .medium, timeSignature: .fourFour)
        chart.notes.append(
            Note(interval: .sixteenth, noteType: .snare, measureNumber: 1, measureOffset: 0.0625)
        )
        let metronome = GameplayViewModelTestHarness.createTestMetronome()
        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)

        await viewModel.loadChartData()
        viewModel.setupGameplay(loadPersistedSpeed: false)
        viewModel.isPlaying = true

        viewModel.updateActiveBeat(forTimePosition: 0.25)

        let sixteenthBeat = try #require(viewModel.cachedDrumBeats.first)
        #expect(viewModel.activeBeatId == sixteenthBeat.id)
    }

    @Test("beat too far behind playhead is not highlighted")
    func beatTooFarBehindPlayheadIsNotHighlighted() async throws {
        // Place a note in measure 1 at offset 0.0, then advance the playhead
        // past one full quarter-beat beyond it — the note should no longer be
        // active once the look-behind window has expired.
        let chart = Chart(difficulty: .medium, timeSignature: .fourFour)
        chart.notes.append(
            Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0.0)
        )
        let metronome = GameplayViewModelTestHarness.createTestMetronome()
        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)

        await viewModel.loadChartData()
        viewModel.setupGameplay(loadPersistedSpeed: false)
        viewModel.isPlaying = true

        // At timePosition 0.0 → the quarter note should be active
        viewModel.updateActiveBeat(forTimePosition: 0.0)
        let quarterBeat = try #require(viewModel.cachedDrumBeats.first)
        #expect(viewModel.activeBeatId == quarterBeat.id)

        // At timePosition 0.5 (two quarter-beats ahead) → beyond maxLookBehind
        viewModel.updateActiveBeat(forTimePosition: 0.5)
        #expect(viewModel.activeBeatId == nil)
    }

    @Test("closest beat to playhead is selected when multiple beats are in range")
    func closestBeatToPlayheadIsSelectedWhenMultipleBeatsInRange() async throws {
        // Place a quarter at 0.0 and a sixteenth at 0.0625.
        // At playhead 0.25, the sixteenth (0.0625) is closer to the quarter at 0.25
        // that would be found via look-behind. Actually the sixteenth IS the last
        // beat at or before 0.25 + lookAhead, so it should be selected.
        let chart = Chart(difficulty: .medium, timeSignature: .fourFour)
        chart.notes.append(
            Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0.0)
        )
        chart.notes.append(
            Note(interval: .sixteenth, noteType: .snare, measureNumber: 1, measureOffset: 0.0625)
        )
        let metronome = GameplayViewModelTestHarness.createTestMetronome()
        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)

        await viewModel.loadChartData()
        viewModel.setupGameplay(loadPersistedSpeed: false)
        viewModel.isPlaying = true

        // At playhead 0.1, the last beat at or before 0.1 + 0.05 = 0.15
        // is the sixteenth at 0.0625 (not the quarter at 0.0)
        viewModel.updateActiveBeat(forTimePosition: 0.1)
        let sixteenthBeat = viewModel.cachedDrumBeats.first { $0.timePosition == 0.0625 }
        #expect(viewModel.activeBeatId == sixteenthBeat?.id)
    }

    @Test("beat at playhead is preferred over future look-ahead candidate")
    func beatAtPlayheadPreferredOverFutureLookAhead() async throws {
        // Regression test: when two beats are within the 0.05 look-ahead window,
        // the beat at the playhead must be selected, not the future one.
        // Place an eighth at offset 0.25 (timePosition 0.25) and a thirty-second
        // at offset 0.28125 (timePosition 0.28125).  The 0.03125 gap is < 0.05.
        // At playhead 0.25, the eighth should win — not the thirty-second.
        let chart = Chart(difficulty: .medium, timeSignature: .fourFour)
        chart.notes.append(
            Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: 0.25)
        )
        chart.notes.append(
            Note(interval: .thirtysecond, noteType: .snare, measureNumber: 1, measureOffset: 0.28125)
        )
        let metronome = GameplayViewModelTestHarness.createTestMetronome()
        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)

        await viewModel.loadChartData()
        viewModel.setupGameplay(loadPersistedSpeed: false)
        viewModel.isPlaying = true

        viewModel.updateActiveBeat(forTimePosition: 0.25)
        let eighthBeat = viewModel.cachedDrumBeats.first { $0.timePosition == 0.25 }
        let thirtysecondBeat = viewModel.cachedDrumBeats.first { $0.timePosition == 0.28125 }
        #expect(viewModel.activeBeatId == eighthBeat?.id)
        #expect(viewModel.activeBeatId != thirtysecondBeat?.id)
    }

    @Test("future beat within look-ahead is selected when no beat at playhead")
    func futureBeatWithinLookAheadSelectedWhenNoBeatAtPlayhead() async throws {
        // Ensures look-ahead still works when no beat is at/before the playhead.
        // Place a thirty-second at offset 0.28125 (timePosition 0.28125).
        // At playhead 0.25, there is no beat at/before 0.25, but 0.28125 is
        // within the 0.05 look-ahead window, so it should be selected.
        let chart = Chart(difficulty: .medium, timeSignature: .fourFour)
        chart.notes.append(
            Note(interval: .thirtysecond, noteType: .snare, measureNumber: 1, measureOffset: 0.28125)
        )
        let metronome = GameplayViewModelTestHarness.createTestMetronome()
        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)

        await viewModel.loadChartData()
        viewModel.setupGameplay(loadPersistedSpeed: false)
        viewModel.isPlaying = true

        viewModel.updateActiveBeat(forTimePosition: 0.25)
        let futureBeat = viewModel.cachedDrumBeats.first { $0.timePosition == 0.28125 }
        #expect(viewModel.activeBeatId == futureBeat?.id)
    }

    @Test("nearest upcoming beat is selected when multiple beats are in look-ahead window")
    func nearestUpcomingBeatSelectedWhenMultipleBeatsInLookAhead() async throws {
        // Regression: when multiple future notes fall inside the 0.05 look-ahead
        // window after a rest, the look-ahead branch should select the NEAREST
        // upcoming note, not the farthest one.
        // Place two notes just ahead of playhead 0.25: at 0.26 and 0.29.
        // Both are within look-ahead [0.25, 0.30], but 0.26 is nearer.
        let chart = Chart(difficulty: .medium, timeSignature: .fourFour)
        chart.notes.append(
            Note(interval: .thirtysecond, noteType: .snare, measureNumber: 1, measureOffset: 0.26)
        )
        chart.notes.append(
            Note(interval: .thirtysecond, noteType: .hiHat, measureNumber: 1, measureOffset: 0.29)
        )
        let metronome = GameplayViewModelTestHarness.createTestMetronome()
        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)

        await viewModel.loadChartData()
        viewModel.setupGameplay(loadPersistedSpeed: false)
        viewModel.isPlaying = true

        viewModel.updateActiveBeat(forTimePosition: 0.25)
        let nearerBeat = viewModel.cachedDrumBeats.first { abs($0.timePosition - 0.26) < 0.001 }
        let fartherBeat = viewModel.cachedDrumBeats.first { abs($0.timePosition - 0.29) < 0.001 }
        #expect(viewModel.activeBeatId == nearerBeat?.id,
                "Should select the nearer upcoming beat (0.26), not the farther one (0.29)")
        #expect(viewModel.activeBeatId != fartherBeat?.id)
    }

    @Test("continuous visual tick updates active beat at sub-beat positions between quarter boundaries")
    func continuousVisualTickUpdatesActiveBeatBetweenQuarters() async throws {
        // Regression: before the continuous tick was added, updateActiveBeat was
        // only called inside the discreteTotalBeats gate, so sub-beat notes were
        // never highlighted at the correct moment.  Now updateContinuousVisualsTick
        // calls updateActiveBeat on every tick regardless of the beat gate.
        let chart = Chart(difficulty: .medium, timeSignature: .fourFour)
        chart.notes.append(
            Note(interval: .sixteenth, noteType: .snare, measureNumber: 1, measureOffset: 0.0)
        )
        chart.notes.append(
            Note(interval: .sixteenth, noteType: .bass, measureNumber: 1, measureOffset: 0.0625)
        )
        let metronome = GameplayViewModelTestHarness.createTestMetronome()
        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)

        await viewModel.loadChartData()
        viewModel.setupGameplay(loadPersistedSpeed: false)
        viewModel.isPlaying = true

        // At timePosition 0.0625 (sub-beat, between quarter boundaries),
        // the sixteenth at 0.0625 should be active — not just the one at 0.0.
        // This simulates what happens inside updateContinuousVisualsTick.
        viewModel.updateActiveBeat(forTimePosition: 0.0625)
        let subBeatNote = viewModel.cachedDrumBeats.first { abs($0.timePosition - 0.0625) < 0.001 }
        #expect(viewModel.activeBeatId == subBeatNote?.id)
    }

    @Test("continuous visual tick does not mutate active-note highlight state after highlighting is disabled")
    func continuousVisualTickDoesNotMutateActiveHighlightState() async throws {
        let chart = Chart(difficulty: .medium, timeSignature: .fourFour)
        chart.notes.append(
            Note(interval: .sixteenth, noteType: .snare, measureNumber: 1, measureOffset: 0.0)
        )
        chart.notes.append(
            Note(interval: .sixteenth, noteType: .bass, measureNumber: 1, measureOffset: 0.0625)
        )
        let metronome = GameplayViewModelTestHarness.createTestMetronome()
        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)

        await viewModel.loadChartData()
        viewModel.setupGameplay(loadPersistedSpeed: false)
        viewModel.isPlaying = true

        viewModel.updateContinuousVisualsForTesting(elapsedTime: 0.03125)

        #expect(viewModel.activeBeatId == nil)
        #expect(viewModel.activeNotationNoteHeadIDs.isEmpty)
    }

    @Test("continuous visual ticks do not re-notify sheet state while active beat is unchanged")
    func continuousVisualTickAvoidsRedundantSheetInvalidation() async throws {
        let chart = Chart(difficulty: .medium, timeSignature: .fourFour)
        chart.notes.append(
            Note(interval: .sixteenth, noteType: .snare, measureNumber: 1, measureOffset: 0.0)
        )
        let metronome = GameplayViewModelTestHarness.createTestMetronome()
        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)

        await viewModel.loadChartData()
        viewModel.setupGameplay(loadPersistedSpeed: false)
        viewModel.isPlaying = true

        viewModel.updateActiveBeat(forTimePosition: 0.0)
        let activeBeat = try #require(viewModel.activeBeatId)
        let activeNoteHeads = viewModel.activeNotationNoteHeadIDs
        try #require(!activeNoteHeads.isEmpty)

        var invalidationCount = 0
        withObservationTracking {
            _ = viewModel.activeBeatId
            _ = viewModel.activeNotationNoteHeadIDs
        } onChange: {
            invalidationCount += 1
        }

        viewModel.updateActiveBeat(forTimePosition: 0.01)

        #expect(viewModel.activeBeatId == activeBeat)
        #expect(viewModel.activeNotationNoteHeadIDs == activeNoteHeads)
        #expect(invalidationCount == 0)
    }

    @Test("Setting activeBeatId to the same value preserves activeNotationNoteHeadIDs")
    func testActiveBeatIdSameValueDoesNotClearNoteHeads() async throws {
        let chart = Chart(difficulty: .medium, timeSignature: .fourFour)
        chart.notes.append(
            Note(interval: .sixteenth, noteType: .snare, measureNumber: 1, measureOffset: 0.0)
        )
        chart.notes.append(
            Note(interval: .sixteenth, noteType: .bass, measureNumber: 1, measureOffset: 0.0)
        )
        let metronome = GameplayViewModelTestHarness.createTestMetronome()
        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)

        await viewModel.loadChartData()
        viewModel.setupGameplay(loadPersistedSpeed: false)

        // First call to updateActiveNotation populates activeNotationNoteHeadIDs
        viewModel.updateActiveNotation(forTimePosition: 0)
        let firstIDs = viewModel.activeNotationNoteHeadIDs
        #expect(!firstIDs.isEmpty,
                "Expected activeNotationNoteHeadIDs to be populated for simultaneous notes at offset 0")

        // Setting activeBeatId to a different value clears note heads (old behavior)
        viewModel.activeBeatId = 9999
        #expect(viewModel.activeNotationNoteHeadIDs.isEmpty,
                "Setting activeBeatId to a different value should clear activeNotationNoteHeadIDs")

        // Re-populate via updateActiveNotation
        viewModel.activeBeatId = nil
        viewModel.updateActiveNotation(forTimePosition: 0)
        let repopulatedIDs = viewModel.activeNotationNoteHeadIDs
        #expect(!repopulatedIDs.isEmpty)

        // Setting activeBeatId to the SAME value should NOT clear activeNotationNoteHeadIDs
        let currentBeatId = viewModel.activeBeatId
        viewModel.activeBeatId = currentBeatId
        #expect(!viewModel.activeNotationNoteHeadIDs.isEmpty,
                "Setting activeBeatId to the same value should not clear activeNotationNoteHeadIDs")
    }

    // MARK: - currentRow / Auto-scroll Tests

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
        let firstNonZeroRowMeasure = viewModel.cachedMeasurePositions
            .first(where: { $0.row > 0 })
        try #require(firstNonZeroRowMeasure != nil)
        let targetMeasure = firstNonZeroRowMeasure!.measureIndex
        let targetRow = firstNonZeroRowMeasure!.row

        // Initial state: row 0.
        #expect(viewModel.currentRow == 0)

        // Drive the visuals forward to the target measure. updateContinuousVisuals
        // requires isPlaying == true to actually update active beats, but currentRow
        // is updated unconditionally on every tick.
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
