//
//  TestModelFactory.swift
//  VirgoTests
//
//  Created by Claude Code on 22/8/2025.
//

import Testing
import SwiftUI
import SwiftData
import Foundation
@testable import Virgo

// MARK: - Model Factory for Tests

@MainActor
struct TestModelFactory {
    
    static func createSong(
        in context: ModelContext,
        title: String = "Test Song",
        artist: String = "Test Artist",
        bpm: Double = 120.0,
        duration: String = "3:00",
        genre: String = "Rock",
        timeSignature: TimeSignature = .fourFour
    ) -> Song {
        let song = Song(
            title: title,
            artist: artist,
            bpm: bpm,
            duration: duration,
            genre: genre,
            timeSignature: timeSignature
        )
        context.insert(song)
        return song
    }
    
    static func createChart(
        in context: ModelContext,
        difficulty: Difficulty = .medium,
        level: Int? = nil,
        song: Song? = nil
    ) -> Chart {
        let chart = Chart(
            difficulty: difficulty,
            level: level,
            song: song
        )
        context.insert(chart)
        return chart
    }
    
    static func createNote(
        in context: ModelContext,
        interval: NoteInterval = .quarter,
        noteType: NoteType = .bass,
        measureNumber: Int = 1,
        measureOffset: Double = 0.0,
        chart: Chart? = nil
    ) -> Note {
        let note = Note(
            interval: interval,
            noteType: noteType,
            measureNumber: measureNumber,
            measureOffset: measureOffset,
            chart: chart
        )
        context.insert(note)
        return note
    }
    
    static func createSongWithChart(
        in context: ModelContext,
        title: String = "Test Song",
        artist: String = "Test Artist",
        bpm: Double = 120.0,
        difficulty: Difficulty = .medium,
        noteCount: Int = 0
    ) async throws -> (song: Song, chart: Chart) {
        let song = createSong(
            in: context,
            title: title,
            artist: artist,
            bpm: bpm
        )
        
        let chart = createChart(
            in: context,
            difficulty: difficulty,
            song: song
        )
        
        // Create notes if requested
        var notes: [Note] = []
        for i in 0..<noteCount {
            let note = createNote(
                in: context,
                measureNumber: (i / 4) + 1,
                measureOffset: Double(i % 4) * 0.25,
                chart: chart
            )
            notes.append(note)
        }
        
        // Properly set up relationships
        song.charts = [chart]
        chart.notes = notes
        
        // Save context to ensure relationships are persisted
        try context.save()
        
        // Allow relationship loading
        try await AsyncTestingUtilities.loadRelationships(for: song)
        try await AsyncTestingUtilities.loadRelationships(for: chart)
        
        return (song: song, chart: chart)
    }
    
    static func createServerSong(
        in context: ModelContext,
        songId: String = "test-song",
        title: String = "Test Server Song",
        artist: String = "Test Server Artist",
        bpm: Double = 120.0
    ) -> ServerSong {
        let serverSong = ServerSong(
            songId: songId,
            title: title,
            artist: artist,
            bpm: bpm
        )
        context.insert(serverSong)
        return serverSong
    }
    
    static func createServerChart(
        in context: ModelContext,
        difficulty: String = "medium",
        difficultyLabel: String = "STANDARD",
        level: Int = 50,
        filename: String = "test.dtx",
        size: Int = 1024,
        serverSong: ServerSong? = nil
    ) -> ServerChart {
        let serverChart = ServerChart(
            difficulty: difficulty,
            difficultyLabel: difficultyLabel,
            level: level,
            filename: filename,
            size: size,
            serverSong: serverSong
        )
        context.insert(serverChart)
        return serverChart
    }
}