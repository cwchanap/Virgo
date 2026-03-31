//
//  SwiftUICoverageFixtures.swift
//  VirgoTests
//
//  Created by Copilot on 31/3/2026.
//

import Foundation
@testable import Virgo

@MainActor
enum SwiftUICoverageFixtures {
    static func makeNote(
        interval: NoteInterval = .quarter,
        noteType: NoteType = .bass,
        measureNumber: Int = 1,
        measureOffset: Double = 0.0,
        chart: Chart? = nil
    ) -> Note {
        Note(
            interval: interval,
            noteType: noteType,
            measureNumber: measureNumber,
            measureOffset: measureOffset,
            chart: chart
        )
    }

    static func makeChart(
        difficulty: Difficulty = .medium,
        level: Int? = nil,
        timeSignature: TimeSignature? = nil,
        notes: [Note] = [],
        song: Song? = nil
    ) -> Chart {
        let chart = Chart(
            difficulty: difficulty,
            level: level,
            timeSignature: timeSignature,
            notes: notes,
            song: song
        )
        notes.forEach { $0.chart = chart }
        return chart
    }

    static func makeSong(
        title: String = "Fixture Song",
        artist: String = "Fixture Artist",
        bpm: Double = 128,
        duration: String = "2:15",
        genre: String = "DTX Import",
        timeSignature: TimeSignature = .fourFour,
        charts: [Chart] = [],
        isPlaying: Bool = false,
        playCount: Int = 0,
        isSaved: Bool = true,
        bgmFilePath: String? = nil,
        previewFilePath: String? = nil
    ) -> Song {
        let song = Song(
            title: title,
            artist: artist,
            bpm: bpm,
            duration: duration,
            genre: genre,
            timeSignature: timeSignature,
            charts: charts,
            isPlaying: isPlaying,
            playCount: playCount,
            isSaved: isSaved,
            bgmFilePath: bgmFilePath,
            previewFilePath: previewFilePath
        )
        // Only wire the song→chart back-reference here. Note→chart wiring is
        // already handled inside makeChart, so re-wiring it here would duplicate state.
        charts.forEach { $0.song = song }
        return song
    }

    static func makeServerChart(
        difficulty: String = "medium",
        difficultyLabel: String = "STANDARD",
        level: Int = 50,
        filename: String = "test.dtx",
        size: Int = 1_024,
        serverSong: ServerSong? = nil
    ) -> ServerChart {
        ServerChart(
            difficulty: difficulty,
            difficultyLabel: difficultyLabel,
            level: level,
            filename: filename,
            size: size,
            serverSong: serverSong
        )
    }

    static func makeServerSong(
        songId: String? = nil,
        title: String = "Fixture Server Song",
        artist: String = "Fixture Server Artist",
        bpm: Double = 150,
        charts: [ServerChart] = [],
        isDownloaded: Bool = false,
        hasBGM: Bool = false,
        bgmDownloaded: Bool = false,
        hasPreview: Bool = false,
        previewDownloaded: Bool = false
    ) -> ServerSong {
        let resolvedSongId = songId ?? title.lowercased().replacingOccurrences(of: " ", with: "-")
        let serverSong = ServerSong(
            songId: resolvedSongId,
            title: title,
            artist: artist,
            bpm: bpm,
            charts: charts,
            isDownloaded: isDownloaded,
            hasBGM: hasBGM,
            bgmDownloaded: bgmDownloaded,
            hasPreview: hasPreview,
            previewDownloaded: previewDownloaded
        )
        return serverSong
    }
}
