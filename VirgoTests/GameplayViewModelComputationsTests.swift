//
//  GameplayViewModelComputationsTests.swift
//  VirgoTests
//
//  Targeted coverage for branches in GameplayViewModel+Computations.swift and
//  GameplayViewModel+VisualUpdates.swift not reached by existing suites.
//

import Testing
import Foundation
@testable import Virgo

// MARK: - Shared helpers

@MainActor
private enum CoverageHelpers {
    static func preparedVM(noteCount: Int = 4) async -> GameplayViewModel {
        let vm = GameplayViewModelCoverageTestSupport.makeViewModel(noteCount: noteCount)
        await vm.loadChartData()
        vm.setupGameplay(loadPersistedSpeed: false)
        return vm
    }

    static func makeResult(
        note: Note?,
        timingAccuracy: TimingAccuracy,
        measureNumber: Int,
        measureOffset: Double,
        timingError: Double? = 0.0
    ) -> NoteMatchResult {
        NoteMatchResult(
            hitInput: InputHit(drumType: .kick, velocity: 1.0, timestamp: Date()),
            matchedNote: note,
            timingAccuracy: timingAccuracy,
            measureNumber: measureNumber,
            measureOffset: measureOffset,
            timingError: timingError
        )
    }
}

// MARK: - Computations coverage

@Suite("ComputationsCoverage", .serialized)
@MainActor
struct GameplayViewModelComputationsTests {

    // MARK: - updateRowWidth

    @Test("updateRowWidth ignores non-finite, zero, and negative widths")
    func testUpdateRowWidthIgnoresInvalidWidths() async throws {
        let vm = GameplayViewModelCoverageTestSupport.makeViewModel(noteCount: 4)
        defer { vm.cleanup() }
        await vm.loadChartData()
        vm.setupGameplay(loadPersistedSpeed: false)

        let baseline = vm.cachedLayoutRowWidth
        vm.updateRowWidth(.nan)
        vm.updateRowWidth(0)
        vm.updateRowWidth(-300)

        #expect(vm.cachedLayoutRowWidth == baseline,
                "Invalid widths must not change the cached row width")
    }

    // MARK: - cacheBeatPositions

    @Test("cacheBeatPositions returns early when track is nil")
    func testCacheBeatPositionsReturnsEarlyWhenTrackIsNil() {
        let vm = GameplayViewModelCoverageTestSupport.makeViewModel()
        defer { vm.cleanup() }
        // track is nil before loadChartData
        vm.cacheBeatPositions()

        #expect(vm.cachedBeatPositions.isEmpty, "No beat positions should be cached without a track")
    }

    // MARK: - calculateTrackDurationInSeconds

    @Test("calculateTrackDuration falls back when song.duration is non-numeric")
    func testCalculateTrackDurationFallsBackOnMalformedDurationString() async throws {
        let vm = await CoverageHelpers.preparedVM(noteCount: 4)
        defer { vm.cleanup() }

        vm.cachedSong = Song(title: "T", artist: "A", bpm: 120.0, duration: "abc", genre: "Rock")
        let duration = vm.calculateTrackDuration()

        // Falls back to note-based calc: 1 measure at 120 BPM 4/4 = 2.0 s
        #expect(abs(duration - 2.0) < 0.001,
                "Non-numeric duration should fall back to note-based calculation")
    }

    @Test("calculateTrackDuration falls back when seconds component fails to parse")
    func testCalculateTrackDurationFallsBackOnUnparsableSeconds() async throws {
        let vm = await CoverageHelpers.preparedVM(noteCount: 4)
        defer { vm.cleanup() }

        vm.cachedSong = Song(title: "T", artist: "A", bpm: 120.0, duration: "1:xx", genre: "Rock")
        let duration = vm.calculateTrackDuration()

        #expect(abs(duration - 2.0) < 0.001,
                "Unparsable seconds component should fall back to note-based calculation")
    }

    // MARK: - resetScoring

    @Test("resetScoring clears all scoring and feedback state")
    func testResetScoringClearsAllScoringState() async throws {
        let vm = await CoverageHelpers.preparedVM(noteCount: 1)
        defer { vm.cleanup() }

        let note = try #require(vm.cachedNotes.first)
        vm.isPlaying = true
        vm.recordHit(result: CoverageHelpers.makeResult(
            note: note, timingAccuracy: .perfect,
            measureNumber: note.measureNumber, measureOffset: note.measureOffset))
        vm.showMilestoneAnimation = true
        vm.showComboBreakFeedback = true
        vm.isShowingSessionResults = true
        vm.scoredNoteIDs.insert(ObjectIdentifier(note))
        vm.missedNoteScanCursor = 5
        vm.lastScannedTimePosition = 3.0
        vm.completionScheduled = true

        vm.resetScoring()

        #expect(vm.scoreEngine.score == 0)
        #expect(vm.scoreEngine.combo == 0)
        #expect(vm.sessionScoreSnapshot == .empty)
        #expect(vm.sessionRecordResult == .recorded)
        #expect(vm.isShowingSessionResults == false)
        #expect(vm.showMilestoneAnimation == false)
        #expect(vm.showComboBreakFeedback == false)
        #expect(vm.scoredNoteIDs.isEmpty)
        #expect(vm.missedNoteScanCursor == 0)
        #expect(vm.lastScannedTimePosition == 0.0)
        #expect(vm.completionScheduled == false)
        #expect(vm.milestoneAnimationTask == nil)
        #expect(vm.completionTask == nil)
    }

    // MARK: - recordHit branches

    @Test("recordHit ignores a duplicate score for an already-scored note")
    func testRecordHitIgnoresDuplicateScoredNote() async throws {
        let vm = await CoverageHelpers.preparedVM(noteCount: 1)
        defer { vm.cleanup() }

        let note = try #require(vm.cachedNotes.first)
        vm.isPlaying = true
        let result = CoverageHelpers.makeResult(
            note: note, timingAccuracy: .perfect,
            measureNumber: note.measureNumber, measureOffset: note.measureOffset)

        vm.recordHit(result: result)
        let scoreAfterFirst = vm.scoreEngine.score
        #expect(scoreAfterFirst > 0, "Pre-condition: first hit must score")

        vm.recordHit(result: result)
        #expect(vm.scoreEngine.score == scoreAfterFirst,
                "Duplicate scoring of the same note must not add score again")
    }

    @Test("recordHit miss triggers combo-break feedback when combo was non-zero")
    func testRecordHitMissTriggersComboBreakFeedback() async throws {
        let vm = await CoverageHelpers.preparedVM(noteCount: 1)
        defer { vm.cleanup() }

        let note = try #require(vm.cachedNotes.first)
        vm.isPlaying = true
        vm.recordHit(result: CoverageHelpers.makeResult(
            note: note, timingAccuracy: .perfect,
            measureNumber: note.measureNumber, measureOffset: note.measureOffset))
        #expect(vm.scoreEngine.combo == 1, "Pre-condition: combo must be built")

        vm.recordHit(result: CoverageHelpers.makeResult(
            note: nil, timingAccuracy: .miss,
            measureNumber: 1, measureOffset: 0.5, timingError: 200.0))

        #expect(vm.scoreEngine.combo == 0, "Miss must break the combo")
        #expect(vm.scoreEngine.missCount == 1)
        #expect(vm.showComboBreakFeedback == true,
                "Combo-break feedback must fire when combo drops from non-zero")
    }

    @Test("recordHit miss skips combo-break feedback when combo is already zero")
    func testRecordHitMissSkipsFeedbackWhenComboIsZero() async throws {
        // Place the chart's single note well ahead of the miss position so the
        // auto miss-scan triggered inside recordHit does not also mark it,
        // which would double-count the miss.
        let chart = Chart(difficulty: .medium)
        chart.notes.append(Note(interval: .quarter, noteType: .bass,
                                measureNumber: 10, measureOffset: 0.0))
        let vm = GameplayViewModelCoverageTestSupport.makeViewModel(chart: chart)
        await vm.loadChartData()
        vm.setupGameplay(loadPersistedSpeed: false)
        defer { vm.cleanup() }

        vm.isPlaying = true
        #expect(vm.scoreEngine.combo == 0)

        vm.recordHit(result: CoverageHelpers.makeResult(
            note: nil, timingAccuracy: .miss,
            measureNumber: 1, measureOffset: 0.5, timingError: 200.0))

        #expect(vm.scoreEngine.missCount == 1)
        #expect(vm.showComboBreakFeedback == false,
                "No combo-break feedback when combo was already zero")
    }

    // MARK: - scanForMissedNotes

    @Test("scanForMissedNotes bails when the scan boundary does not advance")
    func testScanForMissedNotesBailsWhenBoundaryNotAdvanced() async throws {
        // Notes at measure 10 so an early scan marks nothing.
        let chart = Chart(difficulty: .medium)
        chart.notes.append(Note(interval: .quarter, noteType: .bass,
                                measureNumber: 10, measureOffset: 0.0))
        let vm = GameplayViewModelCoverageTestSupport.makeViewModel(chart: chart)
        defer { vm.cleanup() }
        await vm.loadChartData()
        vm.setupGameplay(loadPersistedSpeed: false)
        vm.isPlaying = true

        vm.scanForMissedNotes(upToTimePosition: 5.0)
        let cursorAfterFirst = vm.missedNoteScanCursor
        let lastScanned = vm.lastScannedTimePosition
        #expect(vm.scoreEngine.missCount == 0, "Pre-condition: nothing marked yet")

        // Second call with a regressed playhead must bail out immediately.
        vm.scanForMissedNotes(upToTimePosition: 1.0)

        #expect(vm.missedNoteScanCursor == cursorAfterFirst, "Cursor must not move backward")
        #expect(vm.lastScannedTimePosition == lastScanned, "High-water mark must not regress")
        #expect(vm.scoreEngine.missCount == 0, "Regressed scan must not mark any note")
    }

    @Test("scanForMissedNotes auto-marks past notes and fires combo-break feedback while playing")
    func testScanForMissedNotesAutoMarksMissesWhilePlaying() async throws {
        let chart = Chart(difficulty: .medium)
        chart.notes.append(Note(interval: .quarter, noteType: .bass,
                                measureNumber: 1, measureOffset: 0.0))
        chart.notes.append(Note(interval: .quarter, noteType: .snare,
                                measureNumber: 1, measureOffset: 0.25))
        let vm = GameplayViewModelCoverageTestSupport.makeViewModel(chart: chart)
        defer { vm.cleanup() }
        await vm.loadChartData()
        vm.setupGameplay(loadPersistedSpeed: false)

        // Build combo with the first note, then auto-miss the second via a scan
        // playhead well past it.
        vm.isPlaying = true
        let first = try #require(vm.cachedNotes.first)
        vm.recordHit(result: CoverageHelpers.makeResult(
            note: first, timingAccuracy: .perfect,
            measureNumber: first.measureNumber, measureOffset: first.measureOffset))
        #expect(vm.scoreEngine.combo == 1)

        vm.scanForMissedNotes(upToTimePosition: 5.0)

        #expect(vm.scoreEngine.missCount == 1, "Unscored past note must be auto-missed")
        #expect(vm.scoreEngine.combo == 0, "Auto-miss must break the combo")
        #expect(vm.showComboBreakFeedback == true,
                "Combo dropping from non-zero via auto-miss must fire feedback")
    }
}

// MARK: - Visual updates coverage

@Suite("ComputationsVisualUpdates", .serialized)
@MainActor
struct ComputationsVisualUpdatesTests {

    // MARK: - startVisualTickTimer

    @Test("startVisualTickTimer is a no-op in the test environment")
    func testStartVisualTickTimerIsNoOpInTestEnvironment() async throws {
        let vm = await CoverageHelpers.preparedVM(noteCount: 4)
        defer { vm.cleanup() }

        vm.startVisualTickTimer()

        #expect(vm.playbackTimer == nil,
                "The visual tick timer must not be scheduled under test environment")
    }

    // MARK: - updateVisualElementsFromMetronome

    @Test("updateVisualElementsFromMetronome skips when elapsed time is unavailable")
    func testUpdateVisualElementsFromMetronomeSkipsWhenElapsedTimeUnavailable() async throws {
        let vm = await CoverageHelpers.preparedVM(noteCount: 4)
        defer { vm.cleanup() }

        vm.isPlaying = true
        vm.playbackProgress = 0.3
        // No BGM player, metronome idle, no playbackStartTime → calculateElapsedTime nil
        vm.updateVisualElementsFromMetronome()

        #expect(abs(vm.playbackProgress - 0.3) < 0.0001,
                "Visuals must not update when elapsed time cannot be computed")
    }

    // MARK: - updatePurpleBarPosition / isSamePurpleBarPosition

    @Test("updatePurpleBarPosition leaves purple bar nil when not playing")
    func testUpdatePurpleBarPositionStaysNilWhenNotPlaying() async throws {
        let vm = await CoverageHelpers.preparedVM(noteCount: 4)
        defer { vm.cleanup() }

        #expect(vm.isPlaying == false)
        #expect(vm.purpleBarPosition == nil)

        vm.updatePurpleBarPosition()
        vm.updatePurpleBarPosition()

        #expect(vm.purpleBarPosition == nil,
                "Purple bar must stay nil (nil→nil compare) while not playing")
    }

    // MARK: - calculatePurpleBarPosition

    @Test("calculatePurpleBarPosition uses the live clock when no explicit elapsed time is given")
    func testCalculatePurpleBarPositionUsesLiveClockWithoutExplicitElapsedTime() async throws {
        let vm = await CoverageHelpers.preparedVM(noteCount: 4)
        defer { vm.cleanup() }

        vm.isPlaying = true
        vm.playbackStartTime = Date().addingTimeInterval(-1.0)

        let position = vm.calculatePurpleBarPosition()

        #expect(position != nil, "Live-clock fallback path should resolve a position")
    }

    @Test("calculatePurpleBarPosition uses the legacy layout when notation layout is inactive")
    func testCalculatePurpleBarPositionUsesLegacyLayoutWhenNotationInactive() async throws {
        let vm = await CoverageHelpers.preparedVM(noteCount: 4)
        defer { vm.cleanup() }

        vm.cachedNotationLayout = .empty
        try #require(vm.measurePositionMap[0] != nil, "Pre-condition: legacy positions present")
        vm.isPlaying = true

        let position = try #require(vm.calculatePurpleBarPosition(elapsedTime: 0.0))

        let measurePos = try #require(vm.measurePositionMap[0])
        let expectedX = GameplayLayout.preciseNoteXPosition(
            measurePosition: measurePos, beatPosition: 0.0,
            timeSignature: vm.track?.timeSignature ?? .fourFour)
        #expect(abs(position.x - Double(expectedX)) < 0.001,
                "Legacy path should place the bar at measure 0 beat 0")
    }

    @Test("calculatePurpleBarPosition quantizes non-finite beat counts to zero")
    func testCalculatePurpleBarPositionQuantizesNonFiniteBeatsToZero() async throws {
        let vm = await CoverageHelpers.preparedVM(noteCount: 4)
        defer { vm.cleanup() }

        vm.isPlaying = true
        let position = try #require(vm.calculatePurpleBarPosition(elapsedTime: .infinity))

        // Infinity must clamp to beat 0 of measure 0 rather than crashing or returning nil.
        let beatZero = try #require(
            vm.calculateNotationPurpleBarPosition(measureIndex: 0, beatWithinMeasure: 0.0))
        #expect(abs(position.x - beatZero.x) < 0.001)
        #expect(abs(position.y - beatZero.y) < 0.001)
    }

    // MARK: - updatePlaybackProgress

    @Test("updatePlaybackProgress republishes on rewind")
    func testUpdatePlaybackProgressPublishesOnRewind() async throws {
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 32, measuresCount: 8)
        let vm = GameplayViewModelCoverageTestSupport.makeViewModel(chart: chart)
        defer { vm.cleanup() }
        await vm.loadChartData()
        vm.setupGameplay(loadPersistedSpeed: false)
        vm.isPlaying = true

        vm.updateContinuousVisualsForTesting(elapsedTime: 4.0)
        let forwardProgress = vm.playbackProgress
        #expect(forwardProgress > 0.0)

        // A regressed elapsed time must force a progress republish (rewind branch).
        vm.updateContinuousVisualsForTesting(elapsedTime: 2.0)
        #expect(vm.playbackProgress < forwardProgress,
                "Progress must republish with a lower value after a rewind")
        #expect(vm.playbackProgress > 0.0)
    }

    // MARK: - calculateNotationPurpleBarPosition

    @Test("calculateNotationPurpleBarPosition returns nil without a notation layout")
    func testCalculateNotationPurpleBarPositionReturnsNilWithoutLayout() {
        let vm = GameplayViewModelCoverageTestSupport.makeViewModel()
        defer { vm.cleanup() }
        // track is nil and notation layout is empty before data is loaded

        let position = vm.calculateNotationPurpleBarPosition(measureIndex: 0, beatWithinMeasure: 0.0)

        #expect(position == nil, "Must return nil when track is nil / layout has no note heads")
    }

    // MARK: - rowForMeasure

    @Test("rowForMeasure uses the legacy measurePositionMap when notation layout is inactive")
    func testRowForMeasureUsesMeasurePositionMapWhenNotationInactive() async throws {
        let chart = Chart(difficulty: .medium, timeSignature: .fourFour)
        for measureNumber in 1...8 {
            chart.notes.append(Note(interval: .quarter, noteType: .snare,
                                    measureNumber: measureNumber, measureOffset: 0.0))
        }
        let vm = GameplayViewModelCoverageTestSupport.makeViewModel(chart: chart)
        defer { vm.cleanup() }
        await vm.loadChartData()
        vm.setupGameplay(loadPersistedSpeed: false)

        let maxRow = vm.cachedMeasurePositions.map { $0.row }.max() ?? 0
        try #require(maxRow >= 1, "Pre-condition: layout must wrap to multiple rows")

        // Force the legacy path by clearing the notation layout.
        vm.cachedNotationLayout = .empty

        let measureZeroRow = vm.measurePositionMap[0]?.row ?? 0
        #expect(vm.rowForMeasure(0) == measureZeroRow,
                "Legacy path should look up the row directly from measurePositionMap")
        #expect(vm.rowForMeasure(9_999) == maxRow,
                "Out-of-range index should clamp to the last known row in legacy path")
    }
}
