//
//  ComponentRefactoringTests.swift
//  VirgoTests
//
//  Created by Claude Code on 4/8/2025.
//

import Testing
import SwiftUI
import SwiftData
@testable import Virgo

@Suite("Component Refactoring Tests")
@MainActor
struct ComponentRefactoringTests {
    
    private var container: ModelContainer {
        TestContainer.shared.container
    }
    
    private var context: ModelContext {
        TestContainer.shared.context
    }

    @Test("ExpandableSongRowContainer handles state correctly")
    func testExpandableSongRowContainer() async throws {
        try await TestSetup.withTestSetup {
            let mockSong = TestModelFactory.createSong(in: context)
            let expandedSongId = Binding.constant(Optional<PersistentIdentifier>.none)

            let container = ExpandableSongRowContainer(
                song: mockSong,
                isPlaying: false,
                isExpanded: false,
                expandedSongId: expandedSongId,
                onChartSelect: { _ in },
                onPlayTap: {},
                onSaveTap: {}
            )

            // Test that the container is created without crashing
            #expect(container.song.title == "Test Song")
            #expect(container.isPlaying == false)
            #expect(container.isExpanded == false)
            
            // Test that view can be created with proper environment
            SwiftUITestUtilities.assertViewWithEnvironment(container)
        }
    }

    @Test("DifficultyExpansionView displays charts correctly")
    func testDifficultyExpansionView() async throws {
        try await TestSetup.withTestSetup {
            let mockCharts = [
                createMockChart(context: context, difficulty: .easy),
                createMockChart(context: context, difficulty: .hard),
                createMockChart(context: context, difficulty: .expert)
            ]

            let expansionView = DifficultyExpansionView(
                charts: mockCharts,
                onChartSelect: { _ in }
            )

            #expect(expansionView.charts.count == 3)
            #expect(expansionView.charts[0].difficulty == .easy)
            #expect(expansionView.charts[1].difficulty == .hard)
            #expect(expansionView.charts[2].difficulty == .expert)
            
            // Test that view can be created with proper environment
            SwiftUITestUtilities.assertViewWithEnvironment(expansionView)
        }
    }

    @Test("ChartSelectionCard displays chart information")
    func testChartSelectionCard() async throws {
        try await TestSetup.withTestSetup {
            let mockChart = createMockChart(context: context, difficulty: .hard)

            let selectionCard = ChartSelectionCard(
                chart: mockChart,
                onSelect: {}
            )

            #expect(selectionCard.chart.difficulty == .hard)
            #expect(selectionCard.chart.level == 50)
            
            // Test that view can be created with proper environment
            SwiftUITestUtilities.assertViewWithEnvironment(selectionCard)
        }
    }

    @Test("ChartSelectionCard renders notes, level, best score, and scores action")
    func testChartSelectionCardRendersBestScoreAndScoresAction() async throws {
        try await TestSetup.withTestSetup {
            let notes = [
                Note(interval: .quarter, noteType: .bass, measureNumber: 1, measureOffset: 0.0),
                Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0.25),
                Note(interval: .quarter, noteType: .hiHat, measureNumber: 1, measureOffset: 0.5)
            ]
            let chart = Chart(difficulty: .expert, level: 85, notes: notes)
            chart.bestScore = 4567

            SwiftUITestUtilities.assertView(
                ChartSelectionCard(chart: chart, onSelect: {}),
                containsStrings: ["3 notes", "Level 85", "4,567"]
            )
        }
    }

    @Test("ChartSelectionCard omits best score when it is zero")
    func testChartSelectionCardOmitsBestScoreWhenZero() async throws {
        try await TestSetup.withTestSetup {
            let chart = Chart(difficulty: .easy, level: 20)
            chart.bestScore = 0

            SwiftUITestUtilities.assertView(
                ChartSelectionCard(chart: chart, onSelect: {}),
                containsStrings: ["0 notes", "Level 20"]
            )
        }
    }

    @Test("ServerSongRow displays server song information")
    func testServerSongRow() async throws {
        try await TestSetup.withTestSetup {
            let mockServerSong = createMockServerSong(context: context)

            let serverRow = ServerSongRow(
                serverSong: mockServerSong,
                isLoading: false,
                onDownload: {}
            )

            #expect(serverRow.serverSong.title == "Test Server Song")
            #expect(serverRow.isLoading == false)
            
            // Test that view can be created with proper environment
            SwiftUITestUtilities.assertViewWithEnvironment(serverRow)
        }
    }

    @Test("ServerSongRow handles loading state")
    func testServerSongRowLoadingState() async throws {
        try await TestSetup.withTestSetup {
            let mockServerSong = createMockServerSong(context: context)

            let loadingRow = ServerSongRow(
                serverSong: mockServerSong,
                isLoading: true,
                onDownload: {}
            )

            #expect(loadingRow.isLoading == true)
            
            // Test that view can be created with proper environment
            SwiftUITestUtilities.assertViewWithEnvironment(loadingRow)
        }
    }

    @Test("MetronomeComponent displays correctly")
    func testMetronomeComponent() async throws {
        try await TestSetup.withTestSetup {
            let mockMetronome = MetronomeEngine()

            let component = MetronomeComponent(
                metronome: mockMetronome,
                bpm: 120,
                timeSignature: .fourFour
            )

            #expect(component.bpm == 120)
            #expect(component.timeSignature == .fourFour)
            
            // Test that view can be created with proper environment
            SwiftUITestUtilities.assertViewWithEnvironment(component)
        }
    }

    @Test("GameplayControlsView renders correctly")
    func testGameplayControlsViewRendering() async throws {
        try await TestSetup.withTestSetup {
            guard let track = DrumTrack.sampleData.first else {
                #expect(false, "Sample track data should be available")
                return
            }

            let practiceSettings = PracticeSettingsService()
            let controlsView = GameplayControlsView(
                track: track,
                isPlaying: .constant(false),
                playbackProgress: .constant(0.25),
                metronome: MetronomeEngine(),
                practiceSettings: practiceSettings,
                cachedTrackDuration: 180.0,
                onPlayPause: {},
                onRestart: {},
                onSkipToEnd: {},
                onSpeedChange: { _ in }
            )

            #expect(controlsView.track.title == track.title)
            SwiftUITestUtilities.assertViewWithEnvironment(controlsView)
        }
    }

    @Test("GameplayControlsView returns cachedTrackDuration directly (already speed-adjusted)")
    func testGameplayControlsViewAdjustedDuration() async throws {
        try await TestSetup.withTestSetup {
            guard let track = DrumTrack.sampleData.first else {
                #expect(false, "Sample track data should be available")
                return
            }

            let practiceSettings = PracticeSettingsService()
            practiceSettings.setSpeed(0.5)
            let cachedTrackDuration = 180.0 // Already speed-adjusted by calculateTrackDuration()
            let controlsView = GameplayControlsView(
                track: track,
                isPlaying: .constant(false),
                playbackProgress: .constant(0.0),
                metronome: MetronomeEngine(),
                practiceSettings: practiceSettings,
                cachedTrackDuration: cachedTrackDuration,
                onPlayPause: {},
                onRestart: {},
                onSkipToEnd: {},
                onSpeedChange: { _ in }
            )

            // cachedTrackDuration is already divided by speedMultiplier in
            // calculateTrackDuration(), so the view should use it directly.
            #expect(abs(controlsView.cachedTrackDuration - cachedTrackDuration) < 0.001)
        }
    }
}

// MARK: - Mock Data Helpers

extension ComponentRefactoringTests {
    private func createMockSong(context: ModelContext) -> Song {
        return TestModelFactory.createSong(
            in: context,
            title: "Test Song",
            artist: "Test Artist",
            bpm: 120,
            duration: "3:30",
            genre: "Test Genre"
        )
    }

    private func createMockChart(context: ModelContext, difficulty: Difficulty = .easy) -> Chart {
        let song = createMockSong(context: context)
        return TestModelFactory.createChart(
            in: context,
            difficulty: difficulty,
            level: 50,
            song: song
        )
    }

    private func createMockServerSong(context: ModelContext) -> ServerSong {
        return TestModelFactory.createServerSong(
            in: context,
            songId: "test-song",
            title: "Test Server Song",
            artist: "Test Server Artist",
            bpm: 140.0
        )
    }
}
