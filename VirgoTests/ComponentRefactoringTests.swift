//
//  ComponentRefactoringTests.swift
//  VirgoTests
//
//  Created by Claude Code on 4/8/2025.
//

import Testing
import SwiftUI
@testable import Virgo

@Suite("Component Refactoring Tests")
@MainActor
struct ComponentRefactoringTests {

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
        let mockSong = createMockSong()
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
        let mockCharts = [
            createMockChart(difficulty: .easy),
            createMockChart(difficulty: .hard),
            createMockChart(difficulty: .expert)
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
        let mockChart = createMockChart(difficulty: .hard)

        let selectionCard = ChartSelectionCard(
            chart: mockChart,
            onSelect: {}
        )

        #expect(selectionCard.chart.difficulty == .hard)
        #expect(selectionCard.chart.level == 50)
    }

    @Test("ServerSongRow displays server song information")
    func testServerSongRow() {
        let mockServerSong = createMockServerSong()

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
        let mockServerSong = createMockServerSong()

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
    private func createMockSong() -> Song {
        return Song(
            title: "Test Song",
            artist: "Test Artist",
            bpm: 120,
            duration: "3:30",
            genre: "Test Genre"
        )
    }

    private func createMockChart(difficulty: Difficulty = .easy) -> Chart {
        return Chart(
            difficulty: difficulty,
            level: 50
        )
    }

    private func createMockServerSong() -> ServerSong {
        return ServerSong(
            songId: "test-song",
            title: "Test Server Song",
            artist: "Test Server Artist",
            bpm: 140.0
        )
    }
}
