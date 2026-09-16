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
        viewModel.refreshNotationEngraving()

        #expect(viewModel.notationLayoutGeneration == initialGeneration &+ 1)
        #expect(viewModel.cachedNotationHasRenderableContent)
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
        viewModel.refreshNotationEngraving()
        let renderableEngraving = try #require(viewModel.cachedEngravedNotation)
        let renderablePresentation = try #require(viewModel.notationPresentation)

        viewModel.installPreparedNotation(.unavailable)
        let emptyGeneration = viewModel.notationLayoutGeneration
        #expect(!viewModel.cachedNotationHasRenderableContent)

        viewModel.installPreparedNotation(.ready(renderableEngraving, renderablePresentation))
        let renderableGeneration = viewModel.notationLayoutGeneration

        #expect(renderableGeneration == emptyGeneration &+ 1)
        #expect(viewModel.cachedNotationHasRenderableContent)
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
        let initialEngraving = viewModel.cachedEngravedNotation
        let workerGeneration = viewModel.beginNotationPreparation()
        let newerGeneration = viewModel.beginNotationPreparation()

        #expect(newerGeneration == workerGeneration &+ 1)
        #expect(!viewModel.applyPreparedNotation(prepared, generation: workerGeneration))
        #expect(viewModel.notationLayoutGeneration == newerGeneration)
        // The rejected stale apply must leave the installed engraving
        // untouched — compare identities, not emptiness.
        #expect(viewModel.cachedEngravedNotation?.measures.map(\.index)
                == initialEngraving?.measures.map(\.index))
        #expect(viewModel.cachedEngravedNotation?.measures.map(\.rowIndex)
                == initialEngraving?.measures.map(\.rowIndex))
        #expect(viewModel.cachedEngravedNotation?.noteHeads.map(\.noteID)
                == initialEngraving?.noteHeads.map(\.noteID))
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
        guard case let .ready(preparedEngraving, _) = prepared else {
            Issue.record("Expected a .ready preparation for the fixture chart")
            return
        }
        #expect(viewModel.cachedEngravedNotation?.noteHeads.map(\.noteID)
                == preparedEngraving.noteHeads.map(\.noteID))
        let installedMeasures = viewModel.cachedEngravedNotation?.measures.map { ($0.index, $0.rowIndex) } ?? []
        let preparedMeasures = preparedEngraving.measures.map { ($0.index, $0.rowIndex) }
        #expect(installedMeasures.count == preparedMeasures.count)
        for (installed, expected) in zip(installedMeasures, preparedMeasures) {
            #expect(installed.0 == expected.0)
            #expect(installed.1 == expected.1)
        }

        let staticInput = GameplayView(chart: chart, metronome: viewModel.metronome)
            .staticNotationInput(viewModel: viewModel)
        #expect(staticInput.generation == generation)
    }

    @Test("timeline setup preserves pinned measure row map")
    func timelineSetupPreservesPinnedMeasureRowMap() async throws {
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 8, measuresCount: 2)
        let viewModel = GameplayViewModel(
            chart: chart,
            metronome: GameplayViewModelTestHarness.createTestMetronome()
        )
        await viewModel.loadChartData()
        await viewModel.setupGameplay(loadPersistedSpeed: false)
        defer { viewModel.cleanup() }

        #expect(viewModel.cachedMeasureRowMap == [0: 0, 1: 0])
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
        #expect(playbackInput.engraving?.noteHeads.map(\.noteID)
                == installedInput.engraving?.noteHeads.map(\.noteID))

        viewModel.clearNotationInstallation()
        let replacementInput = gameplayView.staticNotationInput(viewModel: viewModel)
        #expect(replacementInput.generation != installedInput.generation)
    }
}

@MainActor
private func makePreparedTimelineState(
    for viewModel: GameplayViewModel
) throws -> GameplayNotationPreparedState {
    let snapshot = try #require(viewModel.cachedRhythmRuntime.layoutSnapshot)
    let request = GameplayNotationPreparationRequest(
        snapshot: snapshot,
        minimumMeasureCount: viewModel.cachedLayoutMeasureCount,
        style: .gameplayDefault.with(rowWidth: max(GameplayLayout.maxRowWidth, viewModel.cachedLayoutRowWidth)),
        notePositionOverrides: Dictionary(
            uniqueKeysWithValues: DrumType.allCases.map { ($0, $0.notePosition) }
        )
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
