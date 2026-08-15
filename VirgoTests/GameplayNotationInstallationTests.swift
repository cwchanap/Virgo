//
//  GameplayViewModelNotationInstallationTests.swift
//  VirgoTests
//
//  Notation layout installation and generation-identity coverage, split from
//  GameplayViewModelLayoutComputationsTests.swift to respect SwiftLint limits.
//

import Testing
import Foundation
import SwiftUI
@testable import Virgo

@Suite("Notation Installation", .serialized)
@MainActor
struct GameplayNotationInstallationTests {

    @Test("normal notation layout installation advances the generation")
    func normalNotationLayoutInstallationAdvancesGeneration() async throws {
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 1)
        let viewModel = GameplayViewModel(
            chart: chart,
            metronome: GameplayViewModelTestHarness.createTestMetronome()
        )
        await viewModel.loadChartData()

        let initialGeneration = viewModel.notationLayoutGeneration
        viewModel.cacheNotationLayout()

        #expect(viewModel.notationLayoutGeneration == initialGeneration &+ 1)
        #expect(viewModel.cachedNotationLayout.hasRenderableContent)
    }

    @Test("notation layout generation is exposed as read-only state")
    func notationLayoutGenerationIsReadOnly() {
        let viewModel = GameplayViewModel(
            chart: Chart(difficulty: .easy),
            metronome: GameplayViewModelTestHarness.createTestMetronome()
        )

        #expect(notationLayoutGenerationAccess(\GameplayViewModel.notationLayoutGeneration) == .readOnly)
        #expect(notationLayoutGenerationAccess(\GameplayViewModel.nextBeatId) == .writable)
        #expect(viewModel.notationLayoutGeneration == 0)
    }

    @Test("two notation layout installations receive different generations")
    func notationLayoutInstallationsReceiveDifferentGenerations() async throws {
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 1)
        let viewModel = GameplayViewModel(
            chart: chart,
            metronome: GameplayViewModelTestHarness.createTestMetronome()
        )
        await viewModel.loadChartData()
        viewModel.cacheNotationLayout()
        let renderableLayout = viewModel.cachedNotationLayout
        #expect(renderableLayout.hasRenderableContent)

        viewModel.installNotationLayout(.empty)
        let emptyGeneration = viewModel.notationLayoutGeneration
        #expect(!viewModel.cachedNotationLayout.hasRenderableContent)

        viewModel.installNotationLayout(renderableLayout)
        let renderableGeneration = viewModel.notationLayoutGeneration

        #expect(renderableGeneration == emptyGeneration &+ 1)
        #expect(viewModel.cachedNotationLayout.hasRenderableContent)
    }

    @Test("stale timeline preparation cannot install layout or readiness")
    func staleTimelinePreparationCannotInstallLayoutOrReadiness() async throws {
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 8)
        let viewModel = GameplayViewModel(
            chart: chart,
            metronome: GameplayViewModelTestHarness.createTestMetronome()
        )
        await viewModel.loadChartData()

        let prepared = try makePreparedTimelineState(for: viewModel)
        let initialLayout = viewModel.cachedNotationLayout
        let workerGeneration = viewModel.beginNotationPreparation()
        let newerGeneration = viewModel.beginNotationPreparation()

        #expect(newerGeneration == workerGeneration &+ 1)
        #expect(!viewModel.applyPreparedNotation(prepared, generation: workerGeneration))
        #expect(viewModel.notationLayoutGeneration == newerGeneration)
        #expect(viewModel.cachedNotationLayout.measures.isEmpty == initialLayout.measures.isEmpty)
        #expect(viewModel.cachedNotationLayout.noteHeads.isEmpty == initialLayout.noteHeads.isEmpty)
        #expect(viewModel.cachedBeatPositions.isEmpty)
        #expect(!viewModel.isGameplayPrepared)
    }

    @Test("current timeline preparation installs without a second generation")
    func currentTimelinePreparationInstallsWithoutSecondGeneration() async throws {
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 8)
        let viewModel = GameplayViewModel(
            chart: chart,
            metronome: GameplayViewModelTestHarness.createTestMetronome()
        )
        await viewModel.loadChartData()

        let prepared = try makePreparedTimelineState(for: viewModel)
        let generation = viewModel.beginNotationPreparation()
        #expect(viewModel.applyPreparedNotation(prepared, generation: generation))

        #expect(viewModel.notationLayoutGeneration == generation)
        #expect(viewModel.isGameplayPrepared)
        #expect(viewModel.cachedNotationLayout.noteHeads.map(\.eventID) == prepared.layout.noteHeads.map(\.eventID))
        let installedMeasures = viewModel.cachedNotationLayout.measures.map { ($0.measureIndex, $0.row) }
        let preparedMeasures = prepared.layout.measures.map { ($0.measureIndex, $0.row) }
        #expect(installedMeasures.count == preparedMeasures.count)
        for (installed, expected) in zip(installedMeasures, preparedMeasures) {
            #expect(installed.0 == expected.0)
            #expect(installed.1 == expected.1)
        }
        #expect(viewModel.cachedBeatPositions.count == prepared.beatPositionsByID.count)
        for (beatID, position) in prepared.beatPositionsByID {
            let cached = try #require(viewModel.cachedBeatPositions[beatID])
            #expect(cached.x == Double(position.x))
            #expect(cached.y == Double(position.y))
        }

        let staticInput = GameplayView(chart: chart, metronome: viewModel.metronome)
            .staticNotationInput(viewModel: viewModel)
        #expect(staticInput.generation == generation)
    }

    @Test("timeline setup preserves pinned row and coordinate maps")
    func timelineSetupPreservesPinnedRowAndCoordinateMaps() async throws {
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 8, measuresCount: 2)
        let viewModel = GameplayViewModel(
            chart: chart,
            metronome: GameplayViewModelTestHarness.createTestMetronome()
        )
        await viewModel.loadChartData()
        await viewModel.setupGameplay(loadPersistedSpeed: false)
        defer { viewModel.cleanup() }

        #expect(viewModel.cachedMeasureRowMap == [0: 0, 1: 0])
        #expect(viewModel.cachedNotationNoteHeadPositions.count == viewModel.cachedNotationLayout.noteHeads.count)
        #expect(viewModel.cachedBeatPositions.count == viewModel.cachedDrumBeats.count)
        for noteHead in viewModel.cachedNotationLayout.noteHeads {
            let cached = try #require(viewModel.cachedNotationNoteHeadPositions[noteHead.id])
            #expect(cached.x == Double(noteHead.position.x))
            #expect(cached.y == Double(noteHead.position.y))
        }
        for beat in viewModel.cachedDrumBeats {
            #expect(viewModel.cachedBeatPositions[beat.id] != nil)
        }
    }

    @Test("playback updates retain the static notation input until a layout install")
    func playbackUpdatesRetainStaticNotationInputUntilLayoutInstall() async throws {
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 8)
        let viewModel = GameplayViewModel(
            chart: chart,
            metronome: GameplayViewModelTestHarness.createTestMetronome()
        )
        await viewModel.loadChartData()
        await viewModel.setupGameplay(loadPersistedSpeed: false)
        defer { viewModel.cleanup() }

        let gameplayView = GameplayView(chart: chart, metronome: viewModel.metronome)
        let installedInput = gameplayView.staticNotationInput(viewModel: viewModel)

        viewModel.isPlaying = true
        viewModel.updateContinuousVisualsForTesting(elapsedTime: 0.25)
        let playbackInput = gameplayView.staticNotationInput(viewModel: viewModel)

        #expect(playbackInput == installedInput)
        #expect(playbackInput.generation == installedInput.generation)
        #expect(playbackInput.layout.noteHeads.map(\.id) == installedInput.layout.noteHeads.map(\.id))

        viewModel.installNotationLayout(.empty)
        let replacementInput = gameplayView.staticNotationInput(viewModel: viewModel)
        #expect(replacementInput.generation != installedInput.generation)
    }
}

@MainActor
private func makePreparedTimelineState(
    for viewModel: GameplayViewModel
) throws -> GameplayNotationPreparedState {
    let snapshot = try #require(viewModel.cachedRhythmRuntime.layoutSnapshot)
    let beatPositionsByID: [UInt64: RhythmEventPosition] = Dictionary(
        uniqueKeysWithValues: viewModel.cachedDrumBeats.compactMap { beat in
            guard let position = beat.rhythmPosition else { return nil }
            return (beat.id, position)
        }
    )
    let request = GameplayNotationPreparationRequest(
        snapshot: snapshot,
        minimumMeasureCount: viewModel.cachedLayoutMeasureCount,
        style: .gameplayDefault.with(rowWidth: max(GameplayLayout.maxRowWidth, viewModel.cachedLayoutRowWidth)),
        notePositionOverrides: Dictionary(
            uniqueKeysWithValues: DrumType.allCases.map { ($0, $0.notePosition) }
        ),
        beatPositionsByID: beatPositionsByID
    )
    return GameplayNotationPreparer.prepare(request)
}

private enum NotationLayoutGenerationAccess: Equatable { case readOnly, writable }

private func notationLayoutGenerationAccess<Root>(
    _: KeyPath<Root, UInt64>
) -> NotationLayoutGenerationAccess {
    .readOnly
}

private func notationLayoutGenerationAccess<Root>(
    _: ReferenceWritableKeyPath<Root, UInt64>
) -> NotationLayoutGenerationAccess {
    .writable
}
