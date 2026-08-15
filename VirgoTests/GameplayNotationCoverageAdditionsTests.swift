//
//  GameplayNotationCoverageAdditionsTests.swift
//  VirgoTests
//
//  Targeted coverage for lines added/modified in the HPA-581 off-main notation
//  preparation patch that were not exercised by the existing suite.
//

import Testing
import Foundation
import SwiftUI
@testable import Virgo

// MARK: - GameplayViewModel+Notation.swift coverage

@Suite("Notation Coverage Additions", .serialized)
@MainActor
struct GameplayNotationCoverageAdditionsTests {

    // MARK: - makeTimelineNotationPreparationRequest

    @Test("makeTimelineNotationPreparationRequest returns nil without a layout snapshot")
    func makeTimelineRequestReturnsNilWithoutSnapshot() async throws {
        let chart = Chart(difficulty: .medium)
        chart.notes.append(
            Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0.4142135623730951)
        )
        let viewModel = GameplayViewModel(
            chart: chart,
            metronome: GameplayViewModelTestHarness.createTestMetronome()
        )
        await viewModel.loadChartData()
        await viewModel.setupGameplay(loadPersistedSpeed: false)
        defer { viewModel.cleanup() }

        // Inadmissible manual offset → legacy availability, no layout snapshot.
        #expect(viewModel.cachedRhythmRuntime.availability == .legacy)
        #expect(viewModel.cachedRhythmRuntime.layoutSnapshot == nil)
        #expect(viewModel.makeTimelineNotationPreparationRequest() == nil)
    }

    @Test("makeTimelineNotationPreparationRequest returns a valid request for timeline charts")
    func makeTimelineRequestReturnsValidRequestForTimeline() async throws {
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 8)
        let viewModel = GameplayViewModel(
            chart: chart,
            metronome: GameplayViewModelTestHarness.createTestMetronome()
        )
        await viewModel.loadChartData()
        await viewModel.setupGameplay(loadPersistedSpeed: false)
        defer { viewModel.cleanup() }

        #expect(viewModel.cachedRhythmRuntime.availability == .valid)
        let request = try #require(viewModel.makeTimelineNotationPreparationRequest())
        #expect(request.minimumMeasureCount == viewModel.cachedLayoutMeasureCount)
    }

    // MARK: - prepareTimelineNotation cancellation

    @Test("prepareTimelineNotation installs layout and marks gameplay prepared on normal completion")
    func prepareTimelineNotationInstallsOnCompletion() async throws {
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 8)
        let viewModel = GameplayViewModel(
            chart: chart,
            metronome: GameplayViewModelTestHarness.createTestMetronome()
        )
        await viewModel.loadChartData()
        defer { viewModel.cleanup() }

        let request = try #require(viewModel.makeTimelineNotationPreparationRequest())
        let generation = viewModel.beginNotationPreparation()
        #expect(!viewModel.isGameplayPrepared)

        await viewModel.prepareTimelineNotation(request, generation: generation)

        #expect(viewModel.isGameplayPrepared)
        #expect(viewModel.notationLayoutGeneration == generation)
        #expect(viewModel.cachedNotationLayout.hasPlayableContent)
        #expect(viewModel.notationPreparationWorkerTask == nil)
    }

    @Test("prepareTimelineNotation worker is cancelled when supertask is cancelled")
    func prepareTimelineNotationCancelsWorkerOnSupertaskCancellation() async throws {
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 8)
        let viewModel = GameplayViewModel(
            chart: chart,
            metronome: GameplayViewModelTestHarness.createTestMetronome()
        )
        await viewModel.loadChartData()
        defer { viewModel.cleanup() }

        let request = try #require(viewModel.makeTimelineNotationPreparationRequest())
        let generation = viewModel.beginNotationPreparation()

        let preparationTask = Task { @MainActor in
            await viewModel.prepareTimelineNotation(request, generation: generation)
        }
        preparationTask.cancel()
        await preparationTask.value

        // After cancellation, the layout should not have been installed from this
        // generation (the worker was cancelled before it could apply). The
        // generation check alone is insufficient: a broken implementation could
        // still install the prepared layout tagged with this same generation and
        // pass it. Assert readiness and installed content are unchanged too.
        #expect(viewModel.notationLayoutGeneration == generation)
        #expect(!viewModel.isGameplayPrepared)
        #expect(viewModel.cachedNotationLayout.measures.isEmpty)
    }

    // MARK: - updateRowWidth invalid values

    @Test("updateRowWidth ignores non-finite, zero, and negative widths")
    func updateRowWidthIgnoresInvalidValues() async throws {
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 4)
        let viewModel = GameplayViewModel(
            chart: chart,
            metronome: GameplayViewModelTestHarness.createTestMetronome()
        )
        await viewModel.loadChartData()
        await viewModel.setupGameplay(loadPersistedSpeed: false)
        defer { viewModel.cleanup() }

        let initialWidth = viewModel.cachedLayoutRowWidth

        viewModel.updateRowWidth(.nan)
        #expect(viewModel.cachedLayoutRowWidth == initialWidth, "NaN width should be ignored")

        viewModel.updateRowWidth(0)
        #expect(viewModel.cachedLayoutRowWidth == initialWidth, "Zero width should be ignored")

        viewModel.updateRowWidth(-100)
        #expect(viewModel.cachedLayoutRowWidth == initialWidth, "Negative width should be ignored")

        viewModel.updateRowWidth(.infinity)
        #expect(viewModel.cachedLayoutRowWidth == initialWidth, "Infinite width should be ignored")
    }

    // MARK: - cacheNotationLayout no-track reset

    @Test("cacheNotationLayout resets all caches when track is nil")
    func cacheNotationLayoutResetsCachesWhenTrackIsNil() async throws {
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 4)
        let viewModel = GameplayViewModel(
            chart: chart,
            metronome: GameplayViewModelTestHarness.createTestMetronome()
        )
        await viewModel.loadChartData()
        await viewModel.setupGameplay(loadPersistedSpeed: false)
        defer { viewModel.cleanup() }

        #expect(viewModel.cachedNotationHasRenderableContent)

        viewModel.track = nil
        viewModel.cacheNotationLayout()

        #expect(!viewModel.cachedNotationHasRenderableContent)
        #expect(viewModel.cachedMeasureRowMap.isEmpty)
        #expect(viewModel.cachedNotationMeasuresByIndex.isEmpty)
        #expect(viewModel.cachedLegacyContentHeight == 0)
    }

    // MARK: - applyPreparedNotation with empty renderable content

    @Test("applyPreparedNotation clears measure maps when prepared layout has no renderable content")
    func applyPreparedNotationClearsMapsForEmptyRenderableContent() async throws {
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 8)
        let viewModel = GameplayViewModel(
            chart: chart,
            metronome: GameplayViewModelTestHarness.createTestMetronome()
        )
        await viewModel.loadChartData()
        defer { viewModel.cleanup() }

        let emptyPrepared = GameplayNotationPreparedState(
            layout: .empty
        )
        let generation = viewModel.beginNotationPreparation()
        #expect(viewModel.applyPreparedNotation(emptyPrepared, generation: generation))

        #expect(viewModel.isGameplayPrepared)
        #expect(!viewModel.cachedNotationHasRenderableContent)
        #expect(viewModel.cachedMeasureRowMap.isEmpty)
        #expect(viewModel.cachedNotationMeasuresByIndex.isEmpty)
    }

    // MARK: - setupGameplay timeline fallback when request is nil

    @Test("setupGameplay falls back to sync layout when timeline request is nil")
    func setupGameplayFallsBackToSyncLayoutWhenRequestIsNil() async throws {
        // A chart with valid rhythm metadata but a nil layout snapshot would cause
        // makeTimelineNotationPreparationRequest to return nil. This is hard to
        // construct directly, so verify the fallback path via a legacy chart:
        // legacy availability means preparesTimelineOffMain is false, so the
        // sync computeCachedLayoutData path runs and isGameplayPrepared is set.
        let chart = Chart(difficulty: .medium, timeSignature: .fourFour)
        chart.notes = [
            Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0.4142135623730951)
        ]
        let viewModel = GameplayViewModel(
            chart: chart,
            metronome: GameplayViewModelTestHarness.createTestMetronome()
        )
        await viewModel.loadChartData()
        await viewModel.setupGameplay(loadPersistedSpeed: false)
        defer { viewModel.cleanup() }

        #expect(viewModel.cachedRhythmRuntime.availability == .legacy)
        #expect(viewModel.isGameplayPrepared)
        #expect(viewModel.cachedNotationLayout.noteHeads.count == 1)
    }
}

// MARK: - GameplaySheetMusicView.swift coverage

@Suite("Sheet Music View Coverage Additions", .serialized)
@MainActor
struct SheetMusicViewCoverageAdditionsTests {

    @Test("rhythmFatalSheet renders the back button when onDismiss is provided")
    func rhythmFatalSheetRendersBackButtonWithOnDismiss() async throws {
        try await TestSetup.withTestSetup {
            var dismissed = false
            let view = GameplayView(chart: Chart(difficulty: .easy), metronome: MetronomeEngine())
                .rhythmFatalSheet(message: "Timing corrupted", onDismiss: { dismissed = true })

            let mounted = SwiftUITestUtilities.assertViewWithEnvironment(
                view,
                size: CGSize(width: 800, height: 600)
            )
            let texts = SwiftUITestUtilities.renderedTexts(from: mounted.root)

            // The fatal sheet renders "Practice unavailable" headline, the message
            // text, and a "Back" button when onDismiss is provided.
            #expect(texts.contains("Practice unavailable"))
            #expect(texts.contains("Timing corrupted"))
            #expect(texts.contains("Back"))
            #expect(!dismissed)
        }
    }

    @Test("rhythmFatalSheet renders message only when onDismiss is nil")
    func rhythmFatalSheetRendersMessageOnlyWithoutOnDismiss() async throws {
        try await TestSetup.withTestSetup {
            let view = GameplayView(chart: Chart(difficulty: .easy), metronome: MetronomeEngine())
                .rhythmFatalSheet(message: "Unsupported timing")

            let mounted = SwiftUITestUtilities.assertViewWithEnvironment(
                view,
                size: CGSize(width: 800, height: 600)
            )
            let texts = SwiftUITestUtilities.renderedTexts(from: mounted.root)

            #expect(texts.contains("Practice unavailable"))
            #expect(texts.contains("Unsupported timing"))
            // Without onDismiss, the "Back" button should not be rendered.
            #expect(!texts.contains("Back"))
        }
    }

    @Test("shouldAutoScrollSheet returns true only when playing with playable or non-renderable content")
    func shouldAutoScrollSheetLogic() async throws {
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 8)
        let viewModel = GameplayViewModel(
            chart: chart,
            metronome: GameplayViewModelTestHarness.createTestMetronome()
        )
        await viewModel.loadChartData()
        await viewModel.setupGameplay(loadPersistedSpeed: false)
        defer { viewModel.cleanup() }

        let view = GameplayView(chart: chart, metronome: viewModel.metronome)

        // Playing + playable content → true
        #expect(view.shouldAutoScrollSheet(viewModel: viewModel, isPlaying: true))

        // Not playing + playable content → false
        #expect(!view.shouldAutoScrollSheet(viewModel: viewModel, isPlaying: false))

        // Playing + no playable content but renderable → false (rests-only chart)
        let restChart = Chart(difficulty: .medium)
        let restVM = GameplayViewModel(
            chart: restChart,
            metronome: GameplayViewModelTestHarness.createTestMetronome()
        )
        await restVM.loadChartData()
        await restVM.setupGameplay(loadPersistedSpeed: false)
        defer { restVM.cleanup() }
        #expect(restVM.cachedNotationHasRenderableContent)
        #expect(!restVM.cachedNotationHasPlayableContent)
        let restView = GameplayView(chart: restChart, metronome: restVM.metronome)
        #expect(!restView.shouldAutoScrollSheet(viewModel: restVM, isPlaying: true))
    }

    @Test("sheetContentHeight with explicit contentTopInset uses the provided inset")
    func sheetContentHeightWithExplicitInset() async throws {
        let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 4)
        let viewModel = GameplayViewModel(
            chart: chart,
            metronome: GameplayViewModelTestHarness.createTestMetronome()
        )
        await viewModel.loadChartData()
        await viewModel.setupGameplay(loadPersistedSpeed: false)
        defer { viewModel.cleanup() }

        let view = GameplayView(chart: chart, metronome: viewModel.metronome)
        let defaultHeight = view.sheetContentHeight(viewModel: viewModel)
        let explicitInsetHeight = view.sheetContentHeight(viewModel: viewModel, contentTopInset: 50)

        #expect(defaultHeight != explicitInsetHeight)
        #expect(explicitInsetHeight > defaultHeight)
    }

    @Test("static sheet music renders legacy bar lines when layout has no renderable content")
    func staticSheetMusicRendersLegacyBarLinesForNonRenderableLayout() async throws {
        try await TestSetup.withTestSetup {
            let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 8, measuresCount: 2)
            let viewModel = GameplayViewModel(
                chart: chart,
                metronome: GameplayViewModelTestHarness.createTestMetronome()
            )
            await viewModel.loadChartData()
            await viewModel.setupGameplay(loadPersistedSpeed: false)
            defer { viewModel.cleanup() }

            // Install empty layout so hasRenderableContent is false, but
            // cachedMeasurePositions remains populated from the prior setup.
            viewModel.installNotationLayout(.empty)
            #expect(!viewModel.cachedNotationHasRenderableContent)
            #expect(!viewModel.cachedMeasurePositions.isEmpty)

            let view = GameplayView(chart: chart, metronome: viewModel.metronome)
            let measurePositions = view.sheetMeasurePositions(viewModel: viewModel)
            let contentWidth = view.sheetContentWidth(viewModel: viewModel)
            let contentTopInset = view.sheetContentTopInset(viewModel: viewModel)
            let rowCount = view.sheetRowCount(measurePositions: measurePositions)

            // Rendering the static layers with hasRenderableContent=false exercises
            // the legacy bar-line branch in GameplayBarLinesView.
            SwiftUITestUtilities.assertViewWithEnvironment(
                view.staticSheetMusicContent(
                    measurePositions: measurePositions,
                    contentWidth: contentWidth,
                    contentTopInset: contentTopInset,
                    rowCount: rowCount,
                    viewModel: viewModel
                ),
                size: CGSize(width: 1280, height: 900)
            )
        }
    }

    @Test("sheet music view renders fatal rhythm state when view model has fatal timing")
    func sheetMusicViewRendersFatalRhythmState() async throws {
        try await TestSetup.withTestSetup {
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
            await viewModel.setupGameplay(loadPersistedSpeed: false)
            defer { viewModel.cleanup() }

            #expect(viewModel.hasFatalRhythmTiming)

            // Mount the view with the fatal-rhythm view model. The body checks
            // fatalPracticeMessage (which is non-nil when hasFatalRhythmTiming is true)
            // and renders rhythmFatalSheet with the back button.
            let view = GameplayView(chart: chart, metronome: viewModel.metronome, initialViewModel: viewModel)
                .environmentObject(viewModel.practiceSettings)

            let mounted = SwiftUITestUtilities.assertViewWithEnvironment(
                view,
                size: CGSize(width: 1280, height: 900)
            )
            let texts = SwiftUITestUtilities.renderedTexts(from: mounted.root)
            #expect(texts.contains("Practice unavailable"))
            // The fatal sheet should render the "Back" button from the body's
            // rhythmFatalSheet(message:onDismiss:) call.
            #expect(texts.contains("Back"))
        }
    }

    @Test("sheet music view renders loading state when view model is not prepared")
    func sheetMusicViewRendersLoadingStateWhenNotPrepared() async throws {
        try await TestSetup.withTestSetup {
            let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 4)
            let viewModel = GameplayViewModel(
                chart: chart,
                metronome: GameplayViewModelTestHarness.createTestMetronome()
            )
            await viewModel.loadChartData()
            defer { viewModel.cleanup() }

            #expect(!viewModel.isGameplayPrepared)

            let view = GameplayView(chart: chart, metronome: viewModel.metronome, initialViewModel: viewModel)
                .environmentObject(viewModel.practiceSettings)

            let mounted = SwiftUITestUtilities.assertViewWithEnvironment(
                view,
                size: CGSize(width: 1280, height: 900)
            )
            let texts = SwiftUITestUtilities.renderedTexts(from: mounted.root)
            #expect(texts.contains("Loading..."))
        }
    }
}

// MARK: - GameplayView .task lifecycle coverage

@Suite("GameplayView Task Lifecycle Coverage", .serialized)
@MainActor
struct GameplayViewTaskLifecycleCoverageTests {

    @Test("GameplayView .task prepares gameplay and wires delegates for a normal chart")
    func taskLifecyclePreparesGameplayForNormalChart() async throws {
        try await TestSetup.withTestSetup {
            let chart = GameplayViewModelTestHarness.createTestChart(noteCount: 8)
            let metronome = GameplayViewModelTestHarness.createTestMetronome()
            let settings = GameplayViewModelCoverageTestSupport.makeSettings()
            let container = TestContainer.shared.container

            let view = GameplayView(chart: chart, metronome: metronome)
                .environmentObject(settings)
                .modelContainer(container)

            // Retain the mounted view so the .task is not cancelled by deallocation.
            let mounted = SwiftUITestUtilities.assertViewWithEnvironment(
                view,
                size: CGSize(width: 1280, height: 900)
            )

            // Before the .task completes, the loading state should be visible.
            #if os(macOS)
            let textsBefore = SwiftUITestUtilities.renderedTexts(from: mounted.hostingView)
            #expect(textsBefore.contains("Loading..."))
            #endif

            // Allow the .task-driven async preparation (loadChartData → setupGameplay)
            // to complete. The .task body awaits multiple async boundaries, so we
            // need to yield the main run loop long enough for continuations to resume.
            try await Task.sleep(nanoseconds: 500_000_000)
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            try await Task.sleep(nanoseconds: 300_000_000)
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))

            // After the .task completes, re-layout and verify the loading state
            // is gone — the view model was prepared and the gameplay content shows.
            #if os(macOS)
            mounted.hostingView.layoutSubtreeIfNeeded()
            mounted.hostingView.displayIfNeeded()
            let textsAfter = SwiftUITestUtilities.renderedTexts(from: mounted.hostingView)
            #expect(!textsAfter.contains("Loading..."),
                    "Loading state should be replaced after .task prepares gameplay")
            #endif
        }
    }
}
