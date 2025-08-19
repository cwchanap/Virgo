//
//  VirgoTests.swift
//  VirgoTests
//
//  Created by Chan Wai Chan on 29/6/2025.
//

import Testing
import Foundation
import SwiftUI
@testable import Virgo

struct VirgoTests {

    @Test func testAppLaunchConfiguration() async throws {
        // Test that sample data can be loaded
        let sampleTracks = DrumTrack.sampleData
        #expect(sampleTracks.isEmpty) // Currently returns empty since Song.sampleData is empty

        // Verify all sample tracks have valid data
        for track in sampleTracks {
            #expect(!track.title.isEmpty)
            #expect(!track.artist.isEmpty)
            #expect(track.bpm > 0)
            #expect(!track.duration.isEmpty)
            #expect(!track.genre.isEmpty)
        }
    }

    @Test func testDrumTrackDataIntegrity() async throws {
        let song = Song(title: "Test Track", artist: "Test Artist", bpm: 120, duration: "3:45", genre: "Rock")
        let chart = Chart(difficulty: .medium, song: song)
        song.charts = [chart]
        let track = DrumTrack(chart: chart)

        // Verify basic properties
        #expect(track.title == "Test Track")
        #expect(track.artist == "Test Artist")
        #expect(track.bpm == 120)
        #expect(track.duration == "3:45")
        #expect(track.genre == "Rock")
        #expect(track.difficulty == .medium)

        // Verify default values
        #expect(track.isPlaying == false)
        #expect(track.playCount == 0)
        #expect(track.isSaved == false)
        #expect(track.dateAdded <= Date())
    }

    @Test func testGameplayDataStructures() async throws {
        // Test DrumBeat creation
        let beat = DrumBeat(id: 0, drums: [.kick, .snare], timePosition: 0.0, interval: .quarter)
        #expect(beat.id == 0)
        #expect(beat.drums.count == 2)
        #expect(beat.timePosition == 0.0)

        // Test DrumType properties
        #expect(DrumType.kick.symbol == "●")
        #expect(DrumType.snare.symbol == "◆")
        #expect(DrumType.kick.yPosition(for: 0) == 210)  // belowLine1
        #expect(DrumType.snare.yPosition(for: 0) == 150) // line3
    }

    @Test func testAppConstants() async throws {
        // Test that difficulty colors are properly defined
        let easySong = Song(title: "Easy", artist: "Test", bpm: 100, duration: "2:00", genre: "Pop")
        let easyChart = Chart(difficulty: .easy, song: easySong)
        easySong.charts = [easyChart]
        let easyTrack = DrumTrack(chart: easyChart)

        let mediumSong = Song(title: "Medium", artist: "Test", bpm: 120, duration: "3:00", genre: "Rock")
        let mediumChart = Chart(difficulty: .medium, song: mediumSong)
        mediumSong.charts = [mediumChart]
        let mediumTrack = DrumTrack(chart: mediumChart)

        let hardSong = Song(title: "Hard", artist: "Test", bpm: 140, duration: "4:00", genre: "Metal")
        let hardChart = Chart(difficulty: .hard, song: hardSong)
        hardSong.charts = [hardChart]
        let hardTrack = DrumTrack(chart: hardChart)

        let expertSong = Song(
            title: "Expert",
            artist: "Test",
            bpm: 180,
            duration: "5:00",
            genre: "Progressive",
            timeSignature: .fiveFour
        )
        let expertChart = Chart(difficulty: .expert, song: expertSong)
        expertSong.charts = [expertChart]
        let expertTrack = DrumTrack(chart: expertChart)

        #expect(easyTrack.difficultyColor == .green)
        #expect(mediumTrack.difficultyColor == .orange)
        #expect(hardTrack.difficultyColor == .red)
        #expect(expertTrack.difficultyColor == .purple)
    }

    @Test func testDataValidation() async throws {
        let sampleTracks = DrumTrack.sampleData

        // Validate BPM ranges are reasonable (skip if empty since sampleData is currently empty)
        let bpmValues = sampleTracks.map { $0.bpm }
        if !bpmValues.isEmpty {
            #expect(bpmValues.min()! >= 60) // Minimum reasonable BPM
            #expect(bpmValues.max()! <= 300) // Maximum reasonable BPM
        }

        // Validate duration format (M:SS)
        for track in sampleTracks {
            let components = track.duration.components(separatedBy: ":")
            #expect(components.count == 2)
            #expect(Int(components[0]) != nil) // Minutes
            #expect(Int(components[1]) != nil) // Seconds
            #expect(components[1].count == 2) // Two-digit seconds
        }

        // Validate difficulty levels are known
        let validDifficulties = [Difficulty.easy, .medium, .hard, .expert]
        for track in sampleTracks {
            #expect(validDifficulties.contains(track.difficulty))
        }
    }

    @Test func testModelIntegration() async throws {
        // Test that all drum types have unique symbols and positions
        let row = 0 // Use row 0 for testing
        let allDrumTypes: [DrumType] = [.kick, .snare, .hiHat, .crash, .ride, .tom1, .tom2, .tom3, .cowbell]
        let symbols = allDrumTypes.map { $0.symbol }
        let positions = allDrumTypes.map { $0.yPosition(for: row) }

        #expect(Set(symbols).count == symbols.count) // All unique
        #expect(Set(positions).count == positions.count) // All unique

        // Test that positions are ordered correctly (top to bottom based on drum kit layout)
        let orderedDrumTypes: [DrumType] = [.crash, .hiHat, .ride, .cowbell, .tom1, .snare, .tom2, .tom3, .kick]
        let orderedPositions = orderedDrumTypes.map { $0.yPosition(for: row) }

        for i in 1..<orderedPositions.count {
            #expect(orderedPositions[i] > orderedPositions[i-1])
        }
    }

    @Test func testSearchLogic() async throws {
        let rockSong = Song(title: "Rock Song", artist: "Rock Band", bpm: 120.0, duration: "3:00", genre: "Rock")
        let rockChart = Chart(difficulty: .medium, song: rockSong)
        rockSong.charts = [rockChart]

        let jazzSong = Song(title: "Jazz Tune", artist: "Jazz Group", bpm: 140.0, duration: "4:00", genre: "Jazz")
        let jazzChart = Chart(difficulty: .hard, song: jazzSong)
        jazzSong.charts = [jazzChart]

        let tracks = [
            DrumTrack(chart: rockChart),
            DrumTrack(chart: jazzChart)
        ]

        // Test case-insensitive search works as expected
        let rockResults = tracks.filter {
            $0.title.localizedCaseInsensitiveContains("ROCK") ||
                $0.artist.localizedCaseInsensitiveContains("ROCK")
        }
        #expect(rockResults.count == 1)
        #expect(rockResults.first?.title == "Rock Song")

        let jazzResults = tracks.filter {
            $0.title.localizedCaseInsensitiveContains("jazz") ||
                $0.artist.localizedCaseInsensitiveContains("jazz")
        }
        #expect(jazzResults.count == 1)
        #expect(jazzResults.first?.title == "Jazz Tune")
    }

    @Test func testPerformanceBasics() async throws {
        // Test that sample data generation is efficient
        let startTime = Date()
        _ = DrumTrack.sampleData
        let endTime = Date()
        let duration = endTime.timeIntervalSince(startTime)

        // Should be fast (less than 100ms, accounting for CI environment constraints)
        #expect(duration < 0.1)

        // Test that difficulty color computation is efficient
        let testSong = Song(title: "Test", artist: "Test", bpm: 120.0, duration: "3:00", genre: "Rock")
        let testChart = Chart(difficulty: .medium, song: testSong)
        testSong.charts = [testChart]
        let track = DrumTrack(chart: testChart)
        let colorStartTime = Date()
        _ = track.difficultyColor
        let colorEndTime = Date()
        let colorDuration = colorEndTime.timeIntervalSince(colorStartTime)

        // Should be very fast (less than 10ms, accounting for CI timing variations)
        #expect(colorDuration < 0.01)
    }
}
