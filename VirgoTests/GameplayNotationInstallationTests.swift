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

        viewModel.clearNotationInstallation()
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

    // MARK: - Failed installation semantics (HPA-166 review)

    @Test("current failed preparation clears the install and settles readiness")
    func currentFailureClearsInstallAndSettlesReadiness() async throws {
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 8)
        let viewModel = GameplayViewModel(
            chart: chart,
            metronome: GameplayViewModelTestHarness.createTestMetronome()
        )
        await viewModel.loadChartData()
        defer { viewModel.cleanup() }

        // Install a real engraving first so the failure has prior state to clear.
        let ready = try makePreparedTimelineState(for: viewModel)
        let readyGeneration = viewModel.beginNotationPreparation()
        #expect(viewModel.applyPreparedNotation(ready, generation: readyGeneration))
        #expect(viewModel.cachedEngravedNotation != nil)
        #expect(!viewModel.cachedMeasureRowMap.isEmpty)

        let failure = GameplayNotationPreparationFailure(detail: "probe failure")
        let failureGeneration = viewModel.beginNotationPreparation()
        #expect(viewModel.applyPreparedNotation(.failed(failure), generation: failureGeneration))

        // A current failure is a settled outcome: readiness completes, the
        // install and its derived measure caches clear, and the failure is
        // the only notation state left standing.
        #expect(viewModel.isGameplayPrepared)
        #expect(viewModel.cachedEngravedNotation == nil)
        #expect(viewModel.notationPresentation == nil)
        #expect(!viewModel.cachedNotationHasRenderableContent)
        #expect(viewModel.cachedMeasureRowMap.isEmpty)
        #expect(viewModel.cachedNotationMeasuresByIndex.isEmpty)
        #expect(viewModel.notationPreparationFailure == failure)
    }

    @Test("stale failed preparation preserves the installed notation and readiness")
    func staleFailurePreservesPriorState() async throws {
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 8)
        let viewModel = GameplayViewModel(
            chart: chart,
            metronome: GameplayViewModelTestHarness.createTestMetronome()
        )
        await viewModel.loadChartData()
        defer { viewModel.cleanup() }

        let ready = try makePreparedTimelineState(for: viewModel)
        let readyGeneration = viewModel.beginNotationPreparation()
        #expect(viewModel.applyPreparedNotation(ready, generation: readyGeneration))
        let installedEngraving = try #require(viewModel.cachedEngravedNotation)
        let installedPresentation = try #require(viewModel.notationPresentation)
        #expect(viewModel.isGameplayPrepared)

        // A newer preparation supersedes the failed worker's generation.
        _ = viewModel.beginNotationPreparation()
        let staleFailure = GameplayNotationPreparationFailure(detail: "stale probe failure")
        #expect(!viewModel.applyPreparedNotation(.failed(staleFailure), generation: readyGeneration))

        // Nothing may change: install, failure slot, and readiness are the
        // prior generation's values.
        #expect(viewModel.cachedEngravedNotation?.noteHeads.map(\.noteID)
                == installedEngraving.noteHeads.map(\.noteID))
        #expect(viewModel.notationPresentation == installedPresentation)
        #expect(viewModel.cachedNotationHasRenderableContent)
        #expect(viewModel.notationPreparationFailure == nil)
        #expect(viewModel.isGameplayPrepared)
        #expect(viewModel.practiceUnavailableMessage == nil)
    }

    @Test("failed preparation propagates detail and the practice-unavailable message")
    func failurePropagatesDetailAndPracticeUnavailableMessage() async throws {
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 8)
        let viewModel = GameplayViewModel(
            chart: chart,
            metronome: GameplayViewModelTestHarness.createTestMetronome()
        )
        await viewModel.loadChartData()
        defer { viewModel.cleanup() }

        let failure = GameplayNotationPreparationFailure(
            detail: "engraver probe: boom"
        )
        let generation = viewModel.beginNotationPreparation()
        #expect(viewModel.applyPreparedNotation(.failed(failure), generation: generation))

        // The stored failure round-trips both payloads, and the view model's
        // single practice-unavailable surface reads the failure's user copy —
        // the existing default, not a second message.
        #expect(viewModel.notationPreparationFailure?.detail == "engraver probe: boom")
        #expect(viewModel.notationPreparationFailure?.userMessage == failure.userMessage)
        #expect(viewModel.practiceUnavailableMessage == failure.userMessage)
        #expect(
            viewModel.practiceUnavailableMessage
                == String(localized: "This chart's notation could not be prepared.")
        )
    }

    @Test("printable-empty engraving fails preparation with the practice-unavailable message")
    func printableEmptyEngravingFailsWithPracticeUnavailableMessage() throws {
        // A hidden-only rest sheet resolves to no printable primitives — an
        // unexpected engraving outcome that must surface as `.failed`, never
        // as a silent non-state.
        let prepared = NotationSnapshotTestSupport().prepare(
            rests: [
                RhythmLayoutRest(
                    position: RhythmEventPosition(measureIndex: 0, localTick: 0, absoluteTick: 0),
                    durationTicks: 960,
                    voice: .lower,
                    rhythm: NotationRhythm(baseInterval: .full),
                    visibility: .hiddenDuplicate,
                    tupletID: nil
                )
            ]
        )

        guard case let .failed(failure) = prepared else {
            Issue.record("Expected .failed for a printable-empty engraving, got \(prepared)")
            return
        }
        #expect(!failure.detail.isEmpty)
        #expect(
            failure.userMessage == String(localized: "This chart's notation could not be prepared.")
        )
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
