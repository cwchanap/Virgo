//
//  SwiftUICoverageFixtures.swift
//  VirgoTests
//
//  Created by Copilot on coverage-app-target-plus-ten task.
//

import SwiftUI
import SwiftData
@testable import Virgo

// MARK: - Coverage Fixtures

/// Shared fixture builders for song library coverage tests.
@MainActor
enum SongLibraryFixtures {

    // MARK: ServerSong

    static func makeServerSong(
        title: String = "Fixture Song",
        isDownloaded: Bool = false,
        hasBGM: Bool = true,
        bgmDownloaded: Bool = false,
        hasPreview: Bool = true,
        previewDownloaded: Bool = false,
        charts: [ServerChart] = []
    ) -> ServerSong {
        let song = ServerSong(
            songId: title.lowercased().replacingOccurrences(of: " ", with: "-"),
            title: title,
            artist: "Fixture Artist",
            bpm: 140.0,
            charts: charts,
            isDownloaded: isDownloaded,
            hasBGM: hasBGM,
            bgmDownloaded: bgmDownloaded,
            hasPreview: hasPreview,
            previewDownloaded: previewDownloaded
        )
        // Do not set serverSong back-references here; passing charts in the init
        // is sufficient. Setting the inverse after init causes duplication in
        // SwiftData's in-memory relationship tracking.
        return song
    }

    static func makeSingleChartServerSong(
        title: String = "Single Chart Song",
        isDownloaded: Bool = false
    ) -> ServerSong {
        let chart = ServerChart(
            difficulty: "hard",
            difficultyLabel: "EXTREME",
            level: 70,
            filename: "extreme.dtx",
            size: 2048
        )
        return makeServerSong(
            title: title,
            isDownloaded: isDownloaded,
            charts: [chart]
        )
    }

    static func makeMultiChartServerSong(
        title: String = "Multi Chart Song",
        isDownloaded: Bool = false
    ) -> ServerSong {
        let charts = [
            ServerChart(
                difficulty: "easy",
                difficultyLabel: "BASIC",
                level: 25,
                filename: "basic.dtx",
                size: 512
            ),
            ServerChart(
                difficulty: "hard",
                difficultyLabel: "EXTREME",
                level: 72,
                filename: "extreme.dtx",
                size: 2048
            )
        ]
        return makeServerSong(
            title: title,
            isDownloaded: isDownloaded,
            charts: charts
        )
    }

    // MARK: Song (downloaded/local)

    /// Creates a `Song` with the "DTX Import" genre so `LibraryView.downloadedSongs` picks it up.
    static func makeDownloadedSong(
        title: String = "Downloaded Song",
        difficulties: [Difficulty] = [.hard]
    ) -> Song {
        let notes = [
            Note(interval: .quarter, noteType: .bass, measureNumber: 1, measureOffset: 0.0),
            Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: 0.5)
        ]
        let charts = difficulties.enumerated().map { idx, diff -> Chart in
            let chart = Chart(difficulty: diff, level: 50 + idx * 10, notes: notes)
            notes.forEach { $0.chart = chart }
            return chart
        }
        let song = Song(
            title: title,
            artist: "Library Artist",
            bpm: 128.0,
            duration: "3:00",
            genre: "DTX Import",
            charts: charts,
            isSaved: true
        )
        charts.forEach { $0.song = song }
        return song
    }
}
