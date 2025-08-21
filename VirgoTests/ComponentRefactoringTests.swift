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
    
    // Create a test model container for SwiftData models
    static let testContainer: ModelContainer = {
        do {
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            return try ModelContainer(for: Song.self, Chart.self, Note.self, ServerSong.self, ServerChart.self, configurations: config)
        } catch {
            fatalError("Failed to create test container: \(error)")
        }
    }()

    @Test("DifficultyBadge displays correct difficulty")
    func testDifficultyBadgeRendering() {
        let badge = DifficultyBadge(difficulty: .easy, size: .normal)

        // Test that the badge is created without crashing
        #expect(badge.difficulty == .easy)
        #expect(badge.size == .normal)
    }

    @Test("DifficultyBadge size variations work correctly")
    func testDifficultyBadgeSizes() {
        let smallBadge = DifficultyBadge(difficulty: .easy, size: .small)
        let normalBadge = DifficultyBadge(difficulty: .easy, size: .normal)
        let largeBadge = DifficultyBadge(difficulty: .easy, size: .large)

        #expect(smallBadge.size == .small)
        #expect(normalBadge.size == .normal)
        #expect(largeBadge.size == .large)

        // Test that size affects padding
        #expect(DifficultyBadge.BadgeSize.small.padding.horizontal == 4)
        #expect(DifficultyBadge.BadgeSize.normal.padding.horizontal == 8)
        #expect(DifficultyBadge.BadgeSize.large.padding.horizontal == 12)
    }

    @Test("DifficultyBadge fonts scale correctly")
    func testDifficultyBadgeFonts() {
        #expect(DifficultyBadge.BadgeSize.small.font == .caption2)
        #expect(DifficultyBadge.BadgeSize.normal.font == .caption2)
        #expect(DifficultyBadge.BadgeSize.large.font == .caption)
    }

    @Test("ExpandableSongRowContainer handles state correctly")
    func testExpandableSongRowContainer() {
        let context = ModelContext(Self.testContainer)
        let mockSong = createMockSong(context: context)
        let expandedSongId = Binding.constant(Optional<PersistentIdentifier>.none)
        let selectedChart = Binding.constant(Optional<Chart>.none)
        let navigateToGameplay = Binding.constant(false)

        let container = ExpandableSongRowContainer(
            song: mockSong,
            isPlaying: false,
            isExpanded: false,
            expandedSongId: expandedSongId,
            selectedChart: selectedChart,
            navigateToGameplay: navigateToGameplay,
            onPlayTap: {},
            onSaveTap: {}
        )

        // Test that the container is created without crashing
        #expect(container.song.title == "Test Song")
        #expect(container.isPlaying == false)
        #expect(container.isExpanded == false)
    }

    @Test("DifficultyExpansionView displays charts correctly")
    func testDifficultyExpansionView() {
        let context = ModelContext(Self.testContainer)
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
    }

    @Test("ChartSelectionCard displays chart information")
    func testChartSelectionCard() {
        let context = ModelContext(Self.testContainer)
        let mockChart = createMockChart(context: context, difficulty: .hard)

        let selectionCard = ChartSelectionCard(
            chart: mockChart,
            onSelect: {}
        )

        #expect(selectionCard.chart.difficulty == .hard)
        #expect(selectionCard.chart.level == 50)
    }

    @Test("ServerSongRow displays server song information")
    func testServerSongRow() {
        let context = ModelContext(Self.testContainer)
        let mockServerSong = createMockServerSong(context: context)

        let serverRow = ServerSongRow(
            serverSong: mockServerSong,
            isLoading: false,
            onDownload: {}
        )

        #expect(serverRow.serverSong.title == "Test Server Song")
        #expect(serverRow.isLoading == false)
    }

    @Test("ServerSongRow handles loading state")
    func testServerSongRowLoadingState() {
        let context = ModelContext(Self.testContainer)
        let mockServerSong = createMockServerSong(context: context)

        let loadingRow = ServerSongRow(
            serverSong: mockServerSong,
            isLoading: true,
            onDownload: {}
        )

        #expect(loadingRow.isLoading == true)
    }

    @Test("MetronomeComponent displays correctly")
    func testMetronomeComponent() {
        let mockMetronome = MetronomeEngine()

        let component = MetronomeComponent(
            metronome: mockMetronome,
            bpm: 120,
            timeSignature: .fourFour
        )

        #expect(component.bpm == 120)
        #expect(component.timeSignature == .fourFour)
    }
}

// MARK: - Mock Data Helpers

extension ComponentRefactoringTests {
    private func createMockSong(context: ModelContext) -> Song {
        let song = Song(
            title: "Test Song",
            artist: "Test Artist",
            bpm: 120,
            duration: "3:30",
            genre: "Test Genre"
        )
        context.insert(song)
        return song
    }

    private func createMockChart(context: ModelContext, difficulty: Difficulty = .easy) -> Chart {
        let song = createMockSong(context: context)
        let chart = Chart(
            difficulty: difficulty,
            level: 50,
            song: song
        )
        context.insert(chart)
        return chart
    }

    private func createMockServerSong(context: ModelContext) -> ServerSong {
        let serverSong = ServerSong(
            songId: "test-song",
            title: "Test Server Song",
            artist: "Test Server Artist",
            bpm: 140.0
        )
        context.insert(serverSong)
        return serverSong
    }
}
