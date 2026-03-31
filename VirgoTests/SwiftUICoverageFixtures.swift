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
enum SwiftUICoverageFixtures {

    // MARK: ServerChart

    static func makeServerChart(
        difficulty: String = "hard",
        difficultyLabel: String = "EXTREME",
        level: Int,
        filename: String,
        size: Int
    ) -> ServerChart {
        ServerChart(
            difficulty: difficulty,
            difficultyLabel: difficultyLabel,
            level: level,
            filename: filename,
            size: size
        )
    }

    // MARK: ServerSong

    static func makeServerSong(
        title: String = "Fixture Song",
        charts: [ServerChart] = [],
        isDownloaded: Bool = false,
        hasBGM: Bool = true,
        bgmDownloaded: Bool = false,
        hasPreview: Bool = true,
        previewDownloaded: Bool = false
    ) -> ServerSong {
        // Do not set serverSong back-references here; passing charts in the init
        // is sufficient. Setting the inverse after init causes duplication in
        // SwiftData's in-memory relationship tracking.
        ServerSong(
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
    }

    // MARK: Note / Chart / Song

    static func makeNote(
        measureNumber: Int = 1,
        noteType: NoteType = .bass,
        interval: NoteInterval = .quarter,
        measureOffset: Double = 0.0
    ) -> Note {
        Note(interval: interval, noteType: noteType, measureNumber: measureNumber, measureOffset: measureOffset)
    }

    static func makeChart(
        difficulty: Difficulty = .hard,
        level: Int? = nil,
        notes: [Note] = []
    ) -> Chart {
        Chart(difficulty: difficulty, level: level, notes: notes)
    }

    static func makeSong(
        title: String = "Fixture Song",
        artist: String = "Fixture Artist",
        bpm: Double = 128.0,
        duration: String = "3:00",
        genre: String = "DTX Import",
        charts: [Chart] = [],
        isSaved: Bool = true
    ) -> Song {
        let song = Song(
            title: title,
            artist: artist,
            bpm: bpm,
            duration: duration,
            genre: genre,
            charts: charts,
            isSaved: isSaved
        )
        charts.forEach { $0.song = song }
        return song
    }

    // MARK: Song (downloaded/local) - legacy helper

    /// Creates a `Song` with the "DTX Import" genre so `LibraryView.downloadedSongs` picks it up.
    static func makeDownloadedSong(
        title: String = "Downloaded Song",
        difficulties: [Difficulty] = [.hard]
    ) -> Song {
        let charts = difficulties.enumerated().map { idx, diff -> Chart in
            let notes = [
                Note(interval: .quarter, noteType: .bass, measureNumber: 1, measureOffset: 0.0),
                Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: 0.5)
            ]
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
