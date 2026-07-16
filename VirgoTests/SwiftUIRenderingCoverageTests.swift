//
//  SwiftUIRenderingCoverageTests.swift
//  VirgoTests
//
//  Created by Copilot on 22/3/2026.
//

import Testing
import SwiftUI
import Foundation
import SwiftData
#if os(macOS)
import AppKit
#endif
@testable import Virgo

@Suite("SwiftUI Rendering Coverage Tests", .serialized)
@MainActor
struct SwiftUIRenderingCoverageTests {
    private let drumNotationSettingsKey = "DrumNotationSettings"

    private struct MountedLifecycleTextView: View {
        @State private var text = "Initial Text"

        var body: some View {
            Text(text)
                .onAppear {
                    text = "Mounted Text"
                }
        }
    }

    @Test("SettingsView renders inside a navigation stack")
    func testSettingsViewRendering() async throws {
        try await TestSetup.withTestSetup {
            let view = NavigationStack {
                SettingsView()
            }
            .environmentObject(MetronomeEngine(audioDriver: RecordingAudioDriver()))

            SwiftUITestUtilities.assertViewWithEnvironment(view)
        }
    }

    @Test("Render helper does not create visible windows")
    func testRenderHelperDoesNotCreateVisibleWindows() async throws {
        try await TestSetup.withTestSetup {
            #if os(macOS)
            let initialVisibleWindowCount = NSApp.windows.filter(\.isVisible).count

            SwiftUITestUtilities.assertViewWithEnvironment(Text("Offscreen Render"))

            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
            let finalVisibleWindowCount = NSApp.windows.filter(\.isVisible).count
            #expect(finalVisibleWindowCount == initialVisibleWindowCount)
            #endif
        }
    }

    @Test("assertView inspects the mounted hierarchy after onAppear updates")
    func testAssertViewUsesMountedHierarchyAfterOnAppear() async throws {
        try await TestSetup.withTestSetup {
            SwiftUITestUtilities.assertView(
                MountedLifecycleTextView(),
                containsStrings: ["Mounted Text"],
                excludesStrings: ["Initial Text"]
            )
        }
    }

    @Test("AudioSettingsView renders its sections")
    func testAudioSettingsViewRendering() async throws {
        try await TestSetup.withTestSetup {
            let view = NavigationStack {
                AudioSettingsView()
            }

            SwiftUITestUtilities.assertViewWithEnvironment(view)
        }
    }

    @Test("DrumNotationSettingsView renders interactive notation controls")
    func testDrumNotationSettingsViewRendering() async throws {
        try await TestSetup.withTestSetup {
            let view = NavigationStack {
                DrumNotationSettingsView()
            }

            SwiftUITestUtilities.assertViewWithEnvironment(
                view,
                size: CGSize(width: 1280, height: 1600)
            )
        }
    }

    @Test("DrumNotationSettingsManager persists custom positions and resets defaults")
    func testDrumNotationSettingsManagerPersistence() async throws {
        try await TestSetup.withTestSetup {
            let (userDefaults, _) = TestUserDefaults.makeIsolated()
            userDefaults.removeObject(forKey: drumNotationSettingsKey)

            let manager = DrumNotationSettingsManager(userDefaults: userDefaults)
            manager.loadSettings()

            for drumType in DrumType.allCases {
                #expect(manager.getNotePosition(for: drumType) == drumType.notePosition)
            }

            manager.setNotePosition(.belowLine6, for: .snare)
            #expect(manager.getNotePosition(for: .snare) == .belowLine6)

            let reloadedManager = DrumNotationSettingsManager(userDefaults: userDefaults)
            reloadedManager.loadSettings()
            #expect(reloadedManager.getNotePosition(for: .snare) == .belowLine6)

            manager.resetToDefaults()
            #expect(manager.getNotePosition(for: .snare) == DrumType.snare.notePosition)
        }
    }

    @Test("GameplayLayout note positions expose stable display names and raw values")
    func testNotePositionDisplayNamesAndRawValues() {
        let positions = GameplayLayout.NotePosition.allCases
        #expect(!positions.isEmpty)

        let rawValues = Set(positions.map(\.rawValue))
        #expect(rawValues.count == positions.count)

        for position in positions {
            #expect(!position.displayName.isEmpty)
            #expect(!position.rawValue.isEmpty)
        }
    }

    @Test("Gameplay sheet sizing uses renderable notation and reserves legacy fallback for malformed empty layout")
    // swiftlint:disable:next function_body_length
    func testGameplaySheetSizingUsesRenderableNotation() async throws {
        try await TestSetup.withTestSetup {
            let emptyViewModel = GameplayViewModelCoverageTestSupport.makeViewModel(
                chart: Chart(difficulty: .medium),
                noteCount: 0
            )
            await emptyViewModel.loadChartData()
            emptyViewModel.setupGameplay()

            let gameplayView = GameplayView(chart: emptyViewModel.chart, metronome: emptyViewModel.metronome)
            #expect(gameplayView.usesNotationLayout(viewModel: emptyViewModel))
            #expect(emptyViewModel.cachedNotationLayout.hasRenderableContent)
            #expect(!emptyViewModel.cachedNotationLayout.hasPlayableContent)
            #expect(emptyViewModel.cachedNotationLayout.measureBars.count >= 1)
            #expect(
                gameplayView.sheetMeasurePositions(viewModel: emptyViewModel).count
                    == emptyViewModel.cachedNotationLayout.measures.count
            )
            #expect(
                gameplayView.sheetContentWidth(viewModel: emptyViewModel)
                    == emptyViewModel.cachedNotationLayout.contentWidth
            )
            #expect(
                gameplayView.sheetContentHeight(viewModel: emptyViewModel)
                    == emptyViewModel.cachedNotationLayout.totalHeight
            )

            emptyViewModel.cachedNotationLayout = .empty
            #expect(!gameplayView.usesNotationLayout(viewModel: emptyViewModel))
            #expect(gameplayView.sheetContentWidth(viewModel: emptyViewModel) == GameplayLayout.maxRowWidth)
            #expect(
                gameplayView.sheetContentHeight(viewModel: emptyViewModel)
                    == GameplayLayout.totalHeight(for: emptyViewModel.cachedMeasurePositions)
            )

            let denseChart = Chart(difficulty: .medium)
            for index in 0..<32 {
                denseChart.notes.append(
                    Note(
                        interval: .sixteenth,
                        noteType: .snare,
                        measureNumber: 1,
                        measureOffset: Double(index) / 32.0
                    )
                )
            }
            let denseViewModel = GameplayViewModelCoverageTestSupport.makeViewModel(chart: denseChart)
            await denseViewModel.loadChartData()
            denseViewModel.setupGameplay()

            #expect(gameplayView.usesNotationLayout(viewModel: denseViewModel))
            #expect(gameplayView.sheetContentWidth(viewModel: denseViewModel) > GameplayLayout.maxRowWidth)
            #expect(
                gameplayView.sheetContentHeight(viewModel: denseViewModel)
                    == denseViewModel.cachedNotationLayout.totalHeight
            )
        }
    }

    @Test("Gameplay sheet auto-scroll preserves legacy empty layout without scrolling notation-only content")
    func testGameplaySheetAutoScrollPolicy() async throws {
        try await TestSetup.withTestSetup {
            let restOnlyViewModel = GameplayViewModelCoverageTestSupport.makeViewModel(
                chart: Chart(difficulty: .medium),
                noteCount: 0
            )
            await restOnlyViewModel.loadChartData()
            restOnlyViewModel.setupGameplay(loadPersistedSpeed: false)

            let controlOnlyChart = Chart(difficulty: .medium)
            controlOnlyChart.controlEvents.append(ChartControlEvent(
                kind: .choke,
                measureNumber: 1,
                measureOffset: 0,
                targetLaneID: "1A"
            ))
            let controlOnlyViewModel = GameplayViewModelCoverageTestSupport.makeViewModel(chart: controlOnlyChart)
            await controlOnlyViewModel.loadChartData()
            controlOnlyViewModel.setupGameplay(loadPersistedSpeed: false)

            let playableViewModel = GameplayViewModelCoverageTestSupport.makeViewModel(noteCount: 1)
            await playableViewModel.loadChartData()
            playableViewModel.setupGameplay(loadPersistedSpeed: false)

            let legacyEmptyViewModel = GameplayViewModelCoverageTestSupport.makeViewModel(noteCount: 0)
            await legacyEmptyViewModel.loadChartData()
            legacyEmptyViewModel.setupGameplay(loadPersistedSpeed: false)
            legacyEmptyViewModel.cachedNotationLayout = .empty

            let gameplayView = GameplayView(chart: playableViewModel.chart, metronome: playableViewModel.metronome)
            #expect(!gameplayView.shouldAutoScrollSheet(viewModel: restOnlyViewModel, isPlaying: true))
            #expect(!gameplayView.shouldAutoScrollSheet(viewModel: controlOnlyViewModel, isPlaying: true))
            #expect(gameplayView.shouldAutoScrollSheet(viewModel: playableViewModel, isPlaying: true))
            #expect(gameplayView.shouldAutoScrollSheet(viewModel: legacyEmptyViewModel, isPlaying: true))
            #expect(!gameplayView.shouldAutoScrollSheet(viewModel: playableViewModel, isPlaying: false))
        }
    }
}
