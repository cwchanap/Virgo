//
//  DrumTrackTests.swift
//  VirgoTests
//
//  Created by Chan Wai Chan on 30/6/2025.
//

import Testing
import Foundation
import SwiftUI
@testable import Virgo

struct DrumTrackTests {
    
    @Test func testDrumTrackInitialization() async throws {
        let track = DrumTrack(
            title: "Test Track",
            artist: "Test Artist",
            bpm: 120,
            duration: "3:45",
            genre: "Rock",
            difficulty: .medium,
            timeSignature: .fourFour
        )
        
        #expect(track.title == "Test Track")
        #expect(track.artist == "Test Artist")
        #expect(track.bpm == 120)
        #expect(track.duration == "3:45")
        #expect(track.genre == "Rock")
        #expect(track.difficulty == .medium)
        #expect(track.isPlaying == false)
        #expect(track.playCount == 0)
        #expect(track.isFavorite == false)
        #expect(track.dateAdded <= Date())
    }
    
    @Test func testDrumTrackWithCustomDefaults() async throws {
        let track = DrumTrack(
            title: "Custom Track",
            artist: "Custom Artist",
            bpm: 140,
            duration: "4:20",
            genre: "Electronic",
            difficulty: .hard,
            timeSignature: .sixEight,
            isPlaying: true,
            playCount: 5,
            isFavorite: true
        )
        
        #expect(track.isPlaying == true)
        #expect(track.playCount == 5)
        #expect(track.isFavorite == true)
    }
    
    @Test func testDifficultyColors() async throws {
        let easyTrack = DrumTrack(title: "Easy", artist: "Test", bpm: 100, duration: "2:00",
                                  genre: "Pop", difficulty: .easy, timeSignature: .fourFour)
        let mediumTrack = DrumTrack(title: "Medium", artist: "Test", bpm: 120, duration: "3:00",
                                    genre: "Rock", difficulty: .medium, timeSignature: .fourFour)
        let hardTrack = DrumTrack(title: "Hard", artist: "Test", bpm: 140, duration: "4:00",
                                  genre: "Metal", difficulty: .hard, timeSignature: .fourFour)
        let expertTrack = DrumTrack(title: "Expert", artist: "Test", bpm: 180, duration: "5:00",
                                    genre: "Progressive", difficulty: .expert, timeSignature: .fiveFour)
        
        #expect(easyTrack.difficultyColor == .green)
        #expect(mediumTrack.difficultyColor == .orange)
        #expect(hardTrack.difficultyColor == .red)
        #expect(expertTrack.difficultyColor == .purple)
    }
    
    @Test func testSampleDataGeneration() async throws {
        let sampleTracks = DrumTrack.sampleData
        
        #expect(sampleTracks.count == 8)
        #expect(sampleTracks.allSatisfy { !$0.title.isEmpty })
        #expect(sampleTracks.allSatisfy { !$0.artist.isEmpty })
        #expect(sampleTracks.allSatisfy { $0.bpm > 0 })
        #expect(sampleTracks.allSatisfy { !$0.duration.isEmpty })
        #expect(sampleTracks.allSatisfy { !$0.genre.isEmpty })
        
        // Test specific sample tracks
        let thunderBeat = sampleTracks.first { $0.title == "Thunder Beat" }
        #expect(thunderBeat != nil)
        #expect(thunderBeat?.bpm == 120)
        #expect(thunderBeat?.genre == "Rock")
        #expect(thunderBeat?.difficulty == .medium)
        
        let blastBeat = sampleTracks.first { $0.title == "Blast Beat Fury" }
        #expect(blastBeat != nil)
        #expect(blastBeat?.bpm == 180)
        #expect(blastBeat?.difficulty == .expert)
    }
    
    @Test func testBPMValidation() async throws {
        let sampleTracks = DrumTrack.sampleData
        let bpmValues = sampleTracks.map { $0.bpm }
        
        #expect(bpmValues.contains(85))  // Hip Hop Beats
        #expect(bpmValues.contains(95))  // Latin Groove  
        #expect(bpmValues.contains(180)) // Blast Beat Fury
        #expect(bpmValues.min() == 85)
        #expect(bpmValues.max() == 180)
        
        // Ensure all BPM values are reasonable for drum tracks
        #expect(bpmValues.allSatisfy { $0 >= 85 && $0 <= 180 })
    }
    
    @Test func testGenreVariety() async throws {
        let sampleTracks = DrumTrack.sampleData
        let genres = Set(sampleTracks.map { $0.genre })
        
        #expect(genres.contains("Rock"))
        #expect(genres.contains("Electronic"))
        #expect(genres.contains("Jazz"))
        #expect(genres.contains("Hip Hop"))
        #expect(genres.contains("Metal"))
        #expect(genres.contains("Latin"))
        #expect(genres.contains("Progressive"))
        #expect(genres.count >= 6) // At least 6 different genres
    }
    
    @Test func testDifficultyLevels() async throws {
        let sampleTracks = DrumTrack.sampleData
        let difficulties = Set(sampleTracks.map { $0.difficulty })
        
        #expect(difficulties.contains(.easy))
        #expect(difficulties.contains(.medium))
        #expect(difficulties.contains(.hard))
        #expect(difficulties.contains(.expert))
        #expect(difficulties.count == 4) // Exactly 4 difficulty levels
    }
    
    @Test func testDurationFormat() async throws {
        let sampleTracks = DrumTrack.sampleData
        
        // All durations should follow M:SS format
        for track in sampleTracks {
            let components = track.duration.components(separatedBy: ":")
            #expect(components.count == 2)
            #expect(Int(components[0]) != nil) // Minutes should be numeric
            #expect(Int(components[1]) != nil) // Seconds should be numeric
            #expect(components[1].count == 2) // Seconds should be 2 digits
        }
    }
    
    @Test func testTrackEquality() async throws {
        let track1 = DrumTrack(title: "Test", artist: "Artist", bpm: 120,
                               duration: "3:00", genre: "Rock", difficulty: .medium, timeSignature: .fourFour)
        let track2 = DrumTrack(title: "Test", artist: "Artist", bpm: 120,
                               duration: "3:00", genre: "Rock", difficulty: .medium, timeSignature: .fourFour)
        
        // Since these are different instances, they should have different IDs
        #expect(track1.id != track2.id)
        
        // But all other properties should be the same
        #expect(track1.title == track2.title)
        #expect(track1.artist == track2.artist)
        #expect(track1.bpm == track2.bpm)
        #expect(track1.difficulty == track2.difficulty)
    }
    
    @Test func testTimeSignature() async throws {
        // Test time signature properties
        #expect(TimeSignature.fourFour.beatsPerMeasure == 4)
        #expect(TimeSignature.fourFour.noteValue == 4)
        #expect(TimeSignature.threeFour.beatsPerMeasure == 3)
        #expect(TimeSignature.threeFour.noteValue == 4)
        #expect(TimeSignature.sixEight.beatsPerMeasure == 6)
        #expect(TimeSignature.sixEight.noteValue == 8)
        #expect(TimeSignature.fiveFour.beatsPerMeasure == 5)
        #expect(TimeSignature.fiveFour.noteValue == 4)
        
        // Test display names
        #expect(TimeSignature.fourFour.displayName == "4/4")
        #expect(TimeSignature.threeFour.displayName == "3/4")
        #expect(TimeSignature.sixEight.displayName == "6/8")
        #expect(TimeSignature.fiveFour.displayName == "5/4")
        
        // Test that tracks can have time signatures
        let track = DrumTrack(title: "Test", artist: "Test", bpm: 120,
                              duration: "3:00", genre: "Rock", difficulty: .medium, timeSignature: .threeFour)
        #expect(track.timeSignature == .threeFour)
    }
}
