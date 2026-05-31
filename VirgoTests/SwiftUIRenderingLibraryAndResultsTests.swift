//
//  SwiftUIRenderingLibraryAndResultsTests.swift
//  VirgoTests
//
//  Created by Devin on 30/5/2026.
//

import Testing
import SwiftUI
import Foundation
import SwiftData
#if os(macOS)
import AppKit
#endif
@testable import Virgo

@Suite("SwiftUI Library and Results Rendering Tests", .serialized)
@MainActor
struct SwiftUIRenderingLibraryAndResultsTests {
    @Test("LibraryView renders empty and populated downloaded-song states")
    func testLibraryViewRenderingStates() async throws {
        try await TestSetup.withTestSetup {
            let serverSongService = ServerSongService()

            SwiftUITestUtilities.assertViewWithEnvironment(
                LibraryView(songs: [], serverSongService: serverSongService)
            )

            let populatedView = LibraryView(
                songs: [makeDownloadedSong(title: "Library Song")],
                serverSongService: serverSongService
            )
            SwiftUITestUtilities.assertViewWithEnvironment(populatedView)
        }
    }

    @Test("ChartScoresView renders empty score state")
    func testChartScoresViewEmptyState() async throws {
        try await TestSetup.withTestSetup {
            let emptyChart = makeChartInContext(title: "Empty Scores", bestScore: 0)
            let emptyView = NavigationStack {
                ChartScoresView(chart: emptyChart)
            }
            .modelContainer(TestContainer.shared.container)

            SwiftUITestUtilities.assertView(
                emptyView,
                containsStrings: [
                    "0", "BEST SCORE", "No attempts yet", "Play this chart to record a score"
                ],
                size: CGSize(width: 900, height: 900)
            )
        }
    }

    @Test("ChartScoresView renders populated score state")
    func testChartScoresViewPopulatedState() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let scoredChart = makeChartInContext(title: "Scored Chart", bestScore: 567)
            let record = ScoreRecord(
                score: 567,
                maxCombo: 24,
                accuracy: 94.0,
                speedMultiplier: 0.75,
                playedAt: Date(timeIntervalSinceNow: -60),
                chart: scoredChart
            )
            context.insert(record)
            try context.save()

            let scoredView = NavigationStack {
                ChartScoresView(chart: scoredChart)
            }
            .modelContainer(TestContainer.shared.container)

            let mounted = SwiftUITestUtilities.assertViewWithEnvironment(
                scoredView,
                size: CGSize(width: 900, height: 900)
            )
            try await Task.sleep(nanoseconds: 300_000_000)

            let texts = SwiftUITestUtilities.renderedTexts(from: mounted.root)
            #expect(texts.contains("567"))
            #expect(texts.contains("BEST SCORE"))
            #expect(!texts.contains("No attempts yet"))
        }
    }

    @Test("ScoreAttemptRow renders attempt metadata")
    func testScoreAttemptRowRendering() async throws {
        try await TestSetup.withTestSetup {
            let context = TestContainer.shared.context
            let chart = makeChartInContext(title: "Attempt Row", bestScore: 9_876)
            let record = ScoreRecord(
                score: 9_876,
                maxCombo: 123,
                accuracy: 94.4,
                speedMultiplier: 0.875,
                playedAt: Date(timeIntervalSinceNow: -90),
                chart: chart
            )
            context.insert(record)
            try context.save()

            let attempt = try #require(
                ScorePersistenceService(modelContext: context)
                    .recentAttempts(for: chart)
                    .first
            )

            SwiftUITestUtilities.assertView(
                ScoreAttemptRow(attempt: attempt),
                containsStrings: ["9,876", "123x · 94%", "88% speed"],
                size: CGSize(width: 600, height: 120)
            )
        }
    }

    @Test("SongScoresView renders empty chart state")
    func testSongScoresViewEmptyState() async throws {
        try await TestSetup.withTestSetup {
            let emptySong = Song(
                title: "Scoreless Song", artist: "Scores", bpm: 120, duration: "1:00", genre: "DTX Import"
            )
            TestContainer.shared.context.insert(emptySong)
            try TestContainer.shared.context.save()

            let emptyView = NavigationStack {
                SongScoresView(song: emptySong)
            }
            .modelContainer(TestContainer.shared.container)

            SwiftUITestUtilities.assertView(
                emptyView,
                containsStrings: ["No charts available"],
                size: CGSize(width: 900, height: 900)
            )
        }
    }

    @Test("SongScoresView renders populated chart state")
    func testSongScoresViewPopulatedState() async throws {
        try await TestSetup.withTestSetup {
            let hardChart = SwiftUICoverageFixtures.makeChart(difficulty: .hard, level: 70)
            hardChart.bestScore = 890
            let easyChart = SwiftUICoverageFixtures.makeChart(difficulty: .easy, level: 20)
            easyChart.bestScore = 567
            let song = SwiftUICoverageFixtures.makeSong(
                title: "Scores Song",
                charts: [hardChart, easyChart]
            )

            let populatedView = NavigationStack {
                SongScoresView(song: song)
            }

            let mounted = SwiftUITestUtilities.assertViewWithEnvironment(
                populatedView,
                size: CGSize(width: 900, height: 900)
            )
            try await Task.sleep(nanoseconds: 300_000_000)

            let texts = SwiftUITestUtilities.renderedTexts(from: mounted.root)
            #expect(!texts.contains("No charts available"))
        }
    }

    @Test("DifficultyExpansionView renders sorted chart choices")
    func testDifficultyExpansionViewRendering() async throws {
        try await TestSetup.withTestSetup {
            let hardChart = SwiftUICoverageFixtures.makeChart(
                difficulty: .hard,
                level: 70,
                notes: [
                    SwiftUICoverageFixtures.makeNote(measureNumber: 1),
                    SwiftUICoverageFixtures.makeNote(noteType: .snare, measureNumber: 1)
                ]
            )
            let easyChart = SwiftUICoverageFixtures.makeChart(difficulty: .easy, level: 20)

            SwiftUITestUtilities.assertView(
                DifficultyExpansionView(charts: [hardChart, easyChart], onChartSelect: { _ in }),
                containsStrings: ["Select Difficulty", "0 notes", "4 notes", "Level 20", "Level 70"],
                size: CGSize(width: 900, height: 360)
            )
        }
    }

    @Test("ChartSelectionCard renders best score and scores button affordance")
    func testChartSelectionCardRendersScoresAffordance() async throws {
        try await TestSetup.withTestSetup {
            let chart = SwiftUICoverageFixtures.makeChart(difficulty: .expert, level: 95)
            chart.bestScore = 4321

            SwiftUITestUtilities.assertView(
                ChartSelectionCard(chart: chart, onSelect: {}),
                containsStrings: ["4,321", "Level 95"],
                size: CGSize(width: 900, height: 300)
            )
        }
    }

    @Test("SavedSongRow renders metadata and delete states")
    func testSavedSongRowRenderingStates() async throws {
        try await TestSetup.withTestSetup {
            let song = SwiftUICoverageFixtures.makeSong(title: "Saved Row Song")

            let row = SavedSongRow(song: song, isDeleting: false, onDelete: {})
            #expect(row.showsDeleteButton)

            let mountedRow = SwiftUITestUtilities.assertViewWithEnvironment(
                row,
                size: CGSize(width: 900, height: 220)
            )
            let texts = SwiftUITestUtilities.renderedTexts(from: mountedRow.root)
            for expected in ["Saved Row Song", "Fixture Artist", "128 BPM", "2:15", "DTX Import"] {
                #expect(texts.contains(expected), "Expected rendered texts to include '\(expected)', got \(texts)")
            }
            #expect(!texts.contains("Deleting..."), "Expected non-deleting row; got \(texts)")

            let deletingRow = SavedSongRow(song: song, isDeleting: true, onDelete: {})
            #expect(!deletingRow.showsDeleteButton)

            SwiftUITestUtilities.assertView(
                deletingRow,
                containsStrings: ["Saved Row Song", "Deleting..."],
                excludesStrings: ["Delete"],
                size: CGSize(width: 900, height: 220)
            )
        }
    }

    @Test("ServerSongsView renders empty, loading, and populated states")
    func testServerSongsViewRenderingStates() async throws {
        try await TestSetup.withTestSetup {
            let idleService = ServerSongService()
            SwiftUITestUtilities.assertViewWithEnvironment(
                ServerSongsView(serverSongs: [], serverSongService: idleService)
            )

            let loadingService = ServerSongService()
            loadingService.isRefreshing = true
            SwiftUITestUtilities.assertViewWithEnvironment(
                ServerSongsView(serverSongs: [], serverSongService: loadingService)
            )

            let populatedView = ServerSongsView(
                serverSongs: [makeServerSong(title: "Server Song", isDownloaded: true)],
                serverSongService: ServerSongService()
            )
            SwiftUITestUtilities.assertViewWithEnvironment(populatedView)
        }
    }

    @Test("SongsTabView renders downloaded content and filtering state")
    func testSongsTabViewRendering() async throws {
        try await TestSetup.withTestSetup {
            let downloadedSong = makeDownloadedSong(title: "Downloaded Groove")
            let remoteSong = makeServerSong(title: "Remote Groove")
            let audioPlaybackService = AudioPlaybackService(startPlayback: { _ in false })

            let view = SongsTabView(
                allSongs: [downloadedSong],
                serverSongs: [remoteSong],
                serverSongService: ServerSongService(),
                searchText: .constant("Downloaded"),
                currentlyPlaying: .constant(nil),
                expandedSongId: .constant(nil),
                selectedChart: .constant(nil),
                navigateToGameplay: .constant(false),
                audioPlaybackService: audioPlaybackService,
                onPlayTap: { _ in },
                onSaveTap: { _ in }
            )

            SwiftUITestUtilities.assertViewWithEnvironment(
                view,
                size: CGSize(width: 1280, height: 900)
            )
        }
    }

    @Test("SessionResultsView renders a verified new high score state")
    func testSessionResultsViewRenderingForNewRecord() async throws {
        try await TestSetup.withTestSetup {
            let scoreEngine = makeScoreEngineForResults()
            let expectedScore = scoreEngine.score.formatted()
            let view = SessionResultsView(
                highScore: 2450,
                recordResult: .newBest,
                scoreSnapshot: LiveScoreSnapshot(scoreEngine: scoreEngine),
                onPlayAgain: {},
                onDone: {}
            )

            SwiftUITestUtilities.assertView(
                view,
                containsStrings: [expectedScore, "QUALITY"],
                size: CGSize(width: 900, height: 900)
            )
        }
    }

    @Test("SessionResultsView renders non-record results without the badge path")
    func testSessionResultsViewRenderingWithoutRecordBadge() async throws {
        try await TestSetup.withTestSetup {
            var scoreEngine = ScoreEngine()
            scoreEngine.processHit(accuracy: .great, timingError: 12.0)
            scoreEngine.processHit(accuracy: .miss)

            let view = SessionResultsView(
                highScore: 900,
                recordResult: .recorded,
                scoreSnapshot: LiveScoreSnapshot(scoreEngine: scoreEngine),
                onPlayAgain: {},
                onDone: {}
            )

            SwiftUITestUtilities.assertView(
                view,
                containsStrings: ["QUALITY", "40%"],
                size: CGSize(width: 900, height: 900)
            )
        }
    }

    private func makeDownloadedSong(title: String) -> Song {
        let notes = [
            Note(interval: .quarter, noteType: .bass, measureNumber: 1, measureOffset: 0.0),
            Note(interval: .quarter, noteType: .snare, measureNumber: 2, measureOffset: 0.5)
        ]
        let chart = Chart(difficulty: .hard, level: 70, notes: notes)
        let song = Song(
            title: title,
            artist: "Render Artist",
            bpm: 128.0,
            duration: "2:15",
            genre: "DTX Import",
            charts: [chart],
            isSaved: true
        )

        chart.song = song
        notes.forEach { $0.chart = chart }
        return song
    }

    private func makeChartInContext(title: String, bestScore: Int) -> Chart {
        let context = TestContainer.shared.context
        let song = Song(
            title: title, artist: "Score Artist", bpm: 120, duration: "1:00", genre: "DTX Import"
        )
        let chart = Chart(difficulty: .medium, level: 42, song: song)
        chart.bestScore = bestScore
        song.charts = [chart]
        context.insert(song)
        context.insert(chart)
        return chart
    }

    private func makeServerSong(title: String, isDownloaded: Bool = false) -> ServerSong {
        let charts = [
            ServerChart(
                difficulty: "easy",
                difficultyLabel: "BASIC",
                level: 25,
                filename: "basic.dtx",
                size: 1024
            ),
            ServerChart(
                difficulty: "hard",
                difficultyLabel: "EXTREME",
                level: 70,
                filename: "extreme.dtx",
                size: 2048
            )
        ]

        let song = ServerSong(
            songId: title.lowercased().replacingOccurrences(of: " ", with: "-"),
            title: title,
            artist: "Server Artist",
            bpm: 150.0,
            charts: charts,
            isDownloaded: isDownloaded,
            hasBGM: true,
            bgmDownloaded: isDownloaded,
            hasPreview: true,
            previewDownloaded: isDownloaded
        )

        charts.forEach { $0.serverSong = song }
        return song
    }

    private func makeScoreEngineForResults() -> ScoreEngine {
        var engine = ScoreEngine()
        for _ in 0..<15 { engine.processHit(accuracy: .perfect, timingError: -8.0) }
        for _ in 0..<5 { engine.processHit(accuracy: .great, timingError: 15.0) }
        for _ in 0..<2 { engine.processHit(accuracy: .good, timingError: 45.0) }
        for _ in 0..<3 { engine.processHit(accuracy: .miss) }
        return engine
    }
}
