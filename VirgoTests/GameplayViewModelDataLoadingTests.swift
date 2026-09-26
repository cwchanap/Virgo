//
//  GameplayViewModelDataLoadingTests.swift
//  VirgoTests
//

import Testing
import Foundation
import AVFoundation
import Observation
import SwiftUI
@testable import Virgo

@Suite("Data Loading & Notation Layout", .serialized)
@MainActor
struct GameplayViewModelDataLoadingTests {

    @Test("no-track notation reset replaces an existing layout")
    func noTrackNotationResetAdvancesGeneration() async throws {
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 1)
        let viewModel = GameplayViewModel(
            chart: chart,
            metronome: GameplayViewModelTestHarness.createTestMetronome()
        )
        await viewModel.loadChartData()
        viewModel.refreshNotationEngraving()
        #expect(viewModel.cachedNotationHasRenderableContent)

        let initialGeneration = viewModel.notationLayoutGeneration
        viewModel.track = nil
        viewModel.computeCachedLayoutData()

        #expect(viewModel.notationLayoutGeneration == initialGeneration &+ 1)
        #expect(!viewModel.cachedNotationHasRenderableContent)
        #expect(viewModel.cachedEngravedNotation?.measures.isEmpty ?? true)
    }

    @Test("fatal rhythm timing reset replaces an existing layout")
    func fatalRhythmTimingResetAdvancesGeneration() async throws {
        let chart = Chart(difficulty: .medium)
        chart.rhythmMetadataData = Data([0xFF, 0x00, 0xFE])
        chart.notes.append(
            Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0)
        )
        let viewModel = GameplayViewModel(
            chart: chart,
            metronome: GameplayViewModelTestHarness.createTestMetronome()
        )
        await viewModel.loadChartData()
        // Seed a renderable engraving directly: legacy availability no longer
        // formats notes (HPA-164 no-snapshot policy), so install one through
        // the preparation route to prove the fatal reset clears it.
        let seeded = NotationSnapshotTestSupport().prepare(rests: [
            RhythmLayoutRest(
                position: RhythmEventPosition(measureIndex: 0, localTick: 0, absoluteTick: 0),
                durationTicks: 960,
                voice: .upper,
                rhythm: NotationRhythm(baseInterval: .full),
                visibility: .printed,
                tupletID: nil
            )
        ])
        viewModel.installPreparedNotation(seeded)
        #expect(viewModel.cachedNotationHasRenderableContent)

        let initialGeneration = viewModel.notationLayoutGeneration
        await viewModel.setupGameplay(loadPersistedSpeed: false)

        #expect(viewModel.notationLayoutGeneration == initialGeneration &+ 1)
        #expect(!viewModel.cachedNotationHasRenderableContent)
        #expect(viewModel.cachedEngravedNotation?.measures.isEmpty ?? true)
        #expect(viewModel.hasFatalRhythmTiming)
    }

    @Test func testLoadChartData() async throws {
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 8)
        let metronome = GameplayViewModelTestHarness.createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)

        #expect(viewModel.isDataLoaded == false)

        await viewModel.loadChartData()

        #expect(viewModel.isDataLoaded == true)
        #expect(viewModel.cachedNotes.count == 8)
        #expect(viewModel.track != nil)
    }

    @Test func testLoadChartDataWithEmptyNotes() async throws {
        let chart = Chart(difficulty: .easy)
        let metronome = GameplayViewModelTestHarness.createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)

        await viewModel.loadChartData()

        #expect(viewModel.isDataLoaded == true)
        #expect(viewModel.cachedNotes.isEmpty)
        #expect(viewModel.track != nil)
    }

    @Test("loadChartData snapshots control events independently from SwiftData models")
    func testLoadChartDataSnapshotsControlEvents() async throws {
        let chart = Chart(difficulty: .medium)
        let control = ChartControlEvent(
            kind: .choke,
            measureNumber: 2,
            measureOffset: 0.25,
            sourceLaneID: "55",
            sourceNoteID: "0A",
            targetLaneID: "1A"
        )
        chart.controlEvents.append(control)
        let viewModel = GameplayViewModel(
            chart: chart,
            metronome: GameplayViewModelTestHarness.createTestMetronome()
        )

        await viewModel.loadChartData()
        let snapshot = try #require(viewModel.cachedControlEvents.first)
        control.kind = .damp
        control.measureNumber = 9
        control.targetLaneID = "11"

        #expect(snapshot.kind == .choke)
        #expect(snapshot.measureNumber == 2)
        #expect(snapshot.measureOffset == 0.25)
        #expect(snapshot.sourceLaneID == "55")
        #expect(snapshot.sourceNoteID == "0A")
        #expect(snapshot.targetLaneID == "1A")
    }

    @Test func testSetupGameplay() async throws {
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 8)
        let metronome = GameplayViewModelTestHarness.createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)

        await viewModel.loadChartData()
        #expect(viewModel.isDataLoaded)
        #expect(!viewModel.isGameplayPrepared)

        await viewModel.setupGameplay()

        // Verify computed data is populated
        #expect(viewModel.isGameplayPrepared)
        #expect(!viewModel.cachedDrumBeats.isEmpty)
        #expect(!viewModel.cachedMeasurePositions.isEmpty)
        #expect(!viewModel.cachedBeatIndices.isEmpty)
        #expect(!viewModel.measurePositionMap.isEmpty)
        #expect(viewModel.cachedTrackDuration > 0)
    }

    @Test func testSetupGameplayCachesEngravedNotation() async throws {
        let chart = Chart(difficulty: .medium, timeSignature: .fourFour)
        chart.notes.append(
            Note(interval: .sixteenth, noteType: .snare, measureNumber: 1, measureOffset: 0.0)
        )
        chart.notes.append(
            Note(interval: .sixteenth, noteType: .bass, measureNumber: 1, measureOffset: 0.0004)
        )
        let metronome = GameplayViewModelTestHarness.createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)

        await viewModel.loadChartData()
        await viewModel.setupGameplay(loadPersistedSpeed: false)

        #expect(viewModel.cachedDrumBeats.count == 2)
        #expect(viewModel.cachedNotationHasRenderableContent)
        #expect(viewModel.cachedNotationHasPlayableContent)
        let engraved = try #require(viewModel.cachedEngravedNotation)
        #expect(engraved.noteHeads.count == 2)
        // Both manual sixteenth notes retain distinct exact onsets, but their
        // near-overlap makes the measure conservatively unsupported.
        #expect(engraved.stems.isEmpty)
    }

    @Test("empty chart prepares renderable rests without playable caches")
    func testEmptyChartPreparesRenderableRestsWithoutPlayableCaches() async throws {
        let chart = Chart(difficulty: .medium, timeSignature: .fourFour)
        let viewModel = GameplayViewModel(
            chart: chart,
            metronome: GameplayViewModelTestHarness.createTestMetronome()
        )

        await viewModel.loadChartData()
        await viewModel.setupGameplay(loadPersistedSpeed: false)

        #expect(viewModel.cachedNotationHasRenderableContent)
        #expect(!viewModel.cachedNotationHasPlayableContent)
        #expect(!(viewModel.cachedEngravedNotation?.measures.isEmpty ?? true))
        // Every engraved rest is printed by construction.
        #expect(!(viewModel.cachedEngravedNotation?.rests.isEmpty ?? true))
        #expect(!viewModel.cachedMeasureRowMap.isEmpty)
        #expect(!viewModel.cachedNotationMeasuresByIndex.isEmpty)
        #expect(viewModel.cachedNotationHasRenderableContent)
        #expect(viewModel.cachedDrumBeats.isEmpty)
    }

    @Test("control-only chart prepares renderable controls without playable caches")
    func testControlOnlyChartPreparesRenderableControlsWithoutPlayableCaches() async throws {
        let chart = Chart(difficulty: .medium, timeSignature: .fourFour)
        chart.controlEvents.append(ChartControlEvent(
            kind: .damp,
            measureNumber: 1,
            measureOffset: 0.5,
            targetLaneID: "1A"
        ))
        let viewModel = GameplayViewModel(
            chart: chart,
            metronome: GameplayViewModelTestHarness.createTestMetronome()
        )

        await viewModel.loadChartData()
        await viewModel.setupGameplay(loadPersistedSpeed: false)

        #expect(viewModel.cachedControlEvents.count == 1)
        #expect(viewModel.cachedNotationHasRenderableContent)
        #expect(!viewModel.cachedNotationHasPlayableContent)
        #expect(viewModel.cachedEngravedNotation?.controls.count == 1)
        #expect(!viewModel.cachedMeasureRowMap.isEmpty)
        #expect(!viewModel.cachedNotationMeasuresByIndex.isEmpty)
        #expect(viewModel.cachedNotationHasRenderableContent)
        #expect(viewModel.cachedDrumBeats.isEmpty)
    }

    @Test func testNotationLayoutCachesClearWithoutTrack() async throws {
        let chart = Chart(difficulty: .easy)
        let metronome = GameplayViewModelTestHarness.createTestMetronome()
        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)

        viewModel.computeCachedLayoutData()

        #expect(viewModel.cachedEngravedNotation?.noteHeads.isEmpty ?? true)
        #expect(!viewModel.cachedNotationHasRenderableContent)
    }

    @Test func testNotesAtSameMusicalInstantEncodedDifferentlyShareBeatID() async throws {
        // Note A: (measureNumber: 1, measureOffset: 1.0) → timePosition 1.0
        // Note B: (measureNumber: 2, measureOffset: 0.0) → timePosition 1.0
        // Both represent the same musical instant and should map to the same DrumBeat.
        let chart = Chart(difficulty: .medium, timeSignature: .fourFour)
        chart.notes.append(
            Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 1.0)
        )
        chart.notes.append(
            Note(interval: .quarter, noteType: .bass, measureNumber: 2, measureOffset: 0.0)
        )
        let metronome = GameplayViewModelTestHarness.createTestMetronome()
        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)

        await viewModel.loadChartData()
        await viewModel.setupGameplay(loadPersistedSpeed: false)

        // Normalization merges both notes into a single DrumBeat
        #expect(viewModel.cachedDrumBeats.count == 1,
                "Notes at the same timePosition should be grouped into one DrumBeat")

        // The single grouped beat carries both notes' drum types.
        let beat = try #require(viewModel.cachedDrumBeats.first)
        #expect(beat.drums.count == 2,
                "The merged DrumBeat should carry both notes' drum types")
    }

    @Test func testNotationStaticInputRetainsRenderableStateWhenLayoutHasNotes() async throws {
        let chart = Chart(difficulty: .medium, timeSignature: .fourFour)
        chart.notes.append(
            Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0.0)
        )
        let metronome = GameplayViewModelTestHarness.createTestMetronome()
        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)

        await viewModel.loadChartData()
        await viewModel.setupGameplay(loadPersistedSpeed: false)

        #expect(viewModel.cachedNotationHasRenderableContent)
    }

    @Test func testNotationStaticInputRetainsRenderableStateForRenderableRests() async throws {
        let chart = Chart(difficulty: .medium, timeSignature: .fourFour)
        let metronome = GameplayViewModelTestHarness.createTestMetronome()
        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)

        await viewModel.loadChartData()
        await viewModel.setupGameplay(loadPersistedSpeed: false)

        #expect(viewModel.cachedEngravedNotation?.noteHeads.isEmpty ?? true)
        #expect(viewModel.cachedNotationHasRenderableContent)
        #expect(viewModel.cachedNotationHasRenderableContent)
    }

    @Test func testFreshViewModelHasNoInstalledNotation() {
        let viewModel = GameplayViewModel(
            chart: Chart(difficulty: .easy),
            metronome: GameplayViewModelTestHarness.createTestMetronome()
        )

        #expect(viewModel.cachedEngravedNotation == nil)
        #expect(viewModel.notationPresentation == nil)
        #expect(!viewModel.cachedNotationHasRenderableContent)
        #expect(!viewModel.cachedNotationHasPlayableContent)
        #expect(viewModel.cachedMeasureRowMap.isEmpty)
        #expect(viewModel.cachedNotationMeasuresByIndex.isEmpty)
        #expect(viewModel.notationPreparationFailure == nil)
    }

    @Test func testSetupGameplayWithoutLoadingData() async throws {
        let chart = GameplayViewModelTestHarness.createTestChart()
        let metronome = GameplayViewModelTestHarness.createTestMetronome()

        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)

        // Call setupGameplay without loading data first
        await viewModel.setupGameplay()

        // Should not crash, but data should remain empty since track is nil
        #expect(viewModel.cachedDrumBeats.isEmpty)
    }

    @Test func testSetupGameplayLoadsPersistedSpeed() async throws {
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 8)
        let metronome = GameplayViewModelTestHarness.createTestMetronome()

        // Create isolated UserDefaults for this test
        let (userDefaults, _) = TestUserDefaults.makeIsolated()
        let practiceSettings = PracticeSettingsService(userDefaults: userDefaults)

        // Save speed for this chart
        practiceSettings.saveSpeed(0.5, for: chart.persistentModelID)

        // Create new ViewModel (simulating reopening gameplay for this chart)
        let viewModel = GameplayViewModel(chart: chart, metronome: metronome, practiceSettings: practiceSettings)
        await viewModel.loadChartData()
        await viewModel.setupGameplay()

        // Poll for the expected speed/BPM state with a bounded timeout instead of
        // relying on a fixed sleep. The clamp/speed-load path is synchronous in
        // tests, so this typically resolves on the first iteration, but polling
        // guards against any future async setup work without flaking under CI load.
        let expectedSpeed: Double = 0.5
        var attempts = 0
        while abs(viewModel.practiceSettings.speedMultiplier - expectedSpeed) > 0.0001, attempts < 50 {
            try await Task.sleep(nanoseconds: 10_000_000)
            attempts += 1
        }

        // Verify speed was loaded
        #expect(
            viewModel.practiceSettings.speedMultiplier == 0.5,
            "Speed should be loaded from persistence on setup"
        )
        #expect(
            viewModel.effectiveBPM() == (viewModel.track?.bpm ?? 120.0) * 0.5,
            "Effective BPM should reflect loaded speed"
        )

        viewModel.cleanup()
    }

    @Test func testSharedPracticeSettingsResetBeforeNewChart() async throws {
        // Simulates the stale-speed scenario: Song A sets speed to 50%,
        // then Song B is opened. The shared PracticeSettingsService should
        // be reset to 1.0 before the new chart's persisted speed is loaded,
        // preventing the UI from briefly showing Song A's speed.
        let chartA = GameplayViewModelTestHarness.createTestChart(noteCount: 4)
        let chartB = GameplayViewModelTestHarness.createTestChart(noteCount: 8)
        let metronome = GameplayViewModelTestHarness.createTestMetronome()

        let (userDefaults, _) = TestUserDefaults.makeIsolated()
        let sharedSettings = PracticeSettingsService(userDefaults: userDefaults)

        // --- Session A: play at 50% and cleanup ---
        let vmA = GameplayViewModel(chart: chartA, metronome: metronome, practiceSettings: sharedSettings)
        await vmA.loadChartData()
        await vmA.setupGameplay(loadPersistedSpeed: false)
        vmA.updateSpeed(0.5)
        // Wait for trailing-edge debounce timer to fire
        try await Task.sleep(nanoseconds: 300_000_000)
        vmA.cleanup()   // saves 50% for chartA

        // Shared service still holds stale 50% from Song A
        #expect(sharedSettings.speedMultiplier == 0.5, "Stale speed from Song A should persist in shared service")

        // --- Simulate what GameplayView.task does for Song B ---
        // 1. Reset speed before creating ViewModel (as the fix does)
        sharedSettings.resetSpeed()
        #expect(sharedSettings.speedMultiplier == 1.0, "Speed should be reset to 1.0 before new chart")

        // 2. Create ViewModel for Song B
        let vmB = GameplayViewModel(chart: chartB, metronome: metronome, practiceSettings: sharedSettings)
        await vmB.loadChartData()
        await vmB.setupGameplay()  // loads persisted speed for chartB (none saved → stays 1.0)

        #expect(sharedSettings.speedMultiplier == 1.0, "Song B should use default speed since none was saved")

        vmB.cleanup()
    }

    @Test func testCacheNotationLayoutIgnoresPersistedOverrides() async throws {
        // Write a non-default position override to a test UserDefaults that is
        // *not* the isolated one used by PracticeSettingsService.  This simulates
        // a developer having custom positions saved locally.
        let suiteName = "virgo-test-override-isolation"
        let externalDefaults = UserDefaults(suiteName: suiteName)!
        defer {
            externalDefaults.removePersistentDomain(forName: suiteName)
        }
        let customPositions: [String: String] = [DrumType.snare.storageKey: GameplayLayout.NotePosition.aboveLine9.rawValue]
        let data = try JSONEncoder().encode(customPositions)
        externalDefaults.set(data, forKey: DrumNotationSettingsManager.settingsKey)

        // Build a chart with snare notes so the notation layout is non-empty.
        let chart = Chart(difficulty: .medium, timeSignature: .fourFour)
        chart.notes.append(
            Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0.0)
        )
        let metronome = GameplayViewModelTestHarness.createTestMetronome()
        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()
        await viewModel.setupGameplay()

        // The engraving must use the DEFAULT snare position (.line3 — the
        // staff's middle line), NOT the persisted override (.aboveLine9). In
        // tests, TestEnvironment.isRunningTests is true, so the preparation
        // route bypasses UserDefaults entirely.
        let engraved = try #require(viewModel.cachedEngravedNotation,
                                    "Engraving should be installed for the snare note")
        let snareHead = try #require(
            engraved.noteHeads.first,
            "Engraving should contain a snare note head"
        )
        let staffCenterY = engraved.rows[snareHead.rowIndex].staffCenterY
        #expect(snareHead.position.y == staffCenterY,
                "Snare should be at default line3 (the staff's middle line), not at persisted aboveLine9")
    }

    /// Verifies the @Observable `currentRow` updates as the playhead crosses measures.
    /// Drives the same code path the metronome tick uses (`updateContinuousVisualsForTesting`)
    /// so we don't depend on real audio.

    @Test func testPreSetupRowWidthSeedsInitialLayoutWithoutPrebuildingNotation() async throws {
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 8, measuresCount: 2)
        let metronome = GameplayViewModelTestHarness.createTestMetronome()
        let viewModel = GameplayViewModel(chart: chart, metronome: metronome)
        await viewModel.loadChartData()

        viewModel.updateRowWidth(1200)

        #expect(viewModel.cachedLayoutRowWidth == 1200,
                "Initial geometry width should be stored before gameplay setup")
        #expect(viewModel.cachedEngravedNotation == nil,
                "Pre-setup width seeding should not build a throwaway notation layout")

        await viewModel.setupGameplay()

        #expect(viewModel.cachedLayoutRowWidth == 1200,
                "setupGameplay should build the first visible layout with the seeded width")
        #expect(!(viewModel.cachedEngravedNotation?.measures.isEmpty ?? true),
                "setupGameplay should build notation after data and row width are ready")
    }
}
