//
//  DrumTrack.swift (formerly Item.swift)
//  Virgo
//
//  Created by Chan Wai Chan on 29/6/2025.
//

import Foundation
import SwiftData
import SwiftUI

@Model
final class Note {
    var interval: NoteInterval
    var noteType: NoteType
    var measureNumber: Int
    var measureOffset: Double
    
    init(interval: NoteInterval, noteType: NoteType, measureNumber: Int, measureOffset: Double) {
        self.interval = interval
        self.noteType = noteType
        self.measureNumber = measureNumber
        self.measureOffset = measureOffset
    }
}

@Model
final class DrumTrack {
    var title: String
    var artist: String
    var bpm: Int
    var duration: String
    var genre: String
    var difficulty: Difficulty
    private var _timeSignature: TimeSignature?
    
    var timeSignature: TimeSignature {
        get { _timeSignature ?? .fourFour }
        set { _timeSignature = newValue }
    }
    var isPlaying: Bool
    var dateAdded: Date
    var playCount: Int
    var isFavorite: Bool
    var notes: [Note]
    
    init(
        title: String,
        artist: String,
        bpm: Int,
        duration: String,
        genre: String,
        difficulty: Difficulty,
        timeSignature: TimeSignature = .fourFour,
        notes: [Note] = [],
        isPlaying: Bool = false,
        playCount: Int = 0,
        isFavorite: Bool = false
    ) {
        self.title = title
        self.artist = artist
        self.bpm = bpm
        self.duration = duration
        self.genre = genre
        self.difficulty = difficulty
        self._timeSignature = timeSignature
        self.notes = notes
        self.isPlaying = isPlaying
        self.dateAdded = Date()
        self.playCount = playCount
        self.isFavorite = isFavorite
    }
}

// MARK: - Extensions
extension DrumTrack {
    var difficultyColor: Color {
        return difficulty.color
    }
    
    static var sampleData: [DrumTrack] {
        [
            DrumTrack(
                title: "Thunder Beat",
                artist: "DrumMaster Pro",
                bpm: 120,
                duration: "3:45",
                genre: "Rock",
                difficulty: .medium,
                timeSignature: .fourFour,
                notes: [
                    // Measure 1 - Basic rock pattern
                    Note(interval: .quarter, noteType: .bass, measureNumber: 1, measureOffset: 0.0),
                    Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0.5),
                    Note(interval: .eighth, noteType: .hiHat, measureNumber: 1, measureOffset: 0.0),
                    Note(interval: .eighth, noteType: .hiHat, measureNumber: 1, measureOffset: 0.25),
                    Note(interval: .eighth, noteType: .hiHat, measureNumber: 1, measureOffset: 0.5),
                    Note(interval: .eighth, noteType: .hiHat, measureNumber: 1, measureOffset: 0.75),
                    
                    // Measure 2 - Repeat pattern
                    Note(interval: .quarter, noteType: .bass, measureNumber: 2, measureOffset: 0.0),
                    Note(interval: .quarter, noteType: .snare, measureNumber: 2, measureOffset: 0.5),
                    Note(interval: .eighth, noteType: .hiHat, measureNumber: 2, measureOffset: 0.0),
                    Note(interval: .eighth, noteType: .hiHat, measureNumber: 2, measureOffset: 0.25),
                    Note(interval: .eighth, noteType: .hiHat, measureNumber: 2, measureOffset: 0.5),
                    Note(interval: .eighth, noteType: .hiHat, measureNumber: 2, measureOffset: 0.75),
                    
                    // Measure 3 - Variation with bass on beat 3
                    Note(interval: .quarter, noteType: .bass, measureNumber: 3, measureOffset: 0.0),
                    Note(interval: .quarter, noteType: .bass, measureNumber: 3, measureOffset: 0.5),
                    Note(interval: .quarter, noteType: .snare, measureNumber: 3, measureOffset: 0.25),
                    Note(interval: .eighth, noteType: .hiHat, measureNumber: 3, measureOffset: 0.0),
                    Note(interval: .eighth, noteType: .hiHat, measureNumber: 3, measureOffset: 0.25),
                    Note(interval: .eighth, noteType: .hiHat, measureNumber: 3, measureOffset: 0.5),
                    Note(interval: .eighth, noteType: .hiHat, measureNumber: 3, measureOffset: 0.75),
                    
                    // Measure 4 - Back to basic pattern
                    Note(interval: .quarter, noteType: .bass, measureNumber: 4, measureOffset: 0.0),
                    Note(interval: .quarter, noteType: .snare, measureNumber: 4, measureOffset: 0.5),
                    Note(interval: .eighth, noteType: .hiHat, measureNumber: 4, measureOffset: 0.0),
                    Note(interval: .eighth, noteType: .hiHat, measureNumber: 4, measureOffset: 0.25),
                    Note(interval: .eighth, noteType: .hiHat, measureNumber: 4, measureOffset: 0.5),
                    Note(interval: .eighth, noteType: .hiHat, measureNumber: 4, measureOffset: 0.75),
                    
                    // Measure 5 - Add crash cymbal
                    Note(interval: .quarter, noteType: .bass, measureNumber: 5, measureOffset: 0.0),
                    Note(interval: .quarter, noteType: .crash, measureNumber: 5, measureOffset: 0.0),
                    Note(interval: .quarter, noteType: .snare, measureNumber: 5, measureOffset: 0.5),
                    Note(interval: .eighth, noteType: .hiHat, measureNumber: 5, measureOffset: 0.25),
                    Note(interval: .eighth, noteType: .hiHat, measureNumber: 5, measureOffset: 0.5),
                    Note(interval: .eighth, noteType: .hiHat, measureNumber: 5, measureOffset: 0.75),
                    
                    // Measure 6 - Regular pattern
                    Note(interval: .quarter, noteType: .bass, measureNumber: 6, measureOffset: 0.0),
                    Note(interval: .quarter, noteType: .snare, measureNumber: 6, measureOffset: 0.5),
                    Note(interval: .eighth, noteType: .hiHat, measureNumber: 6, measureOffset: 0.0),
                    Note(interval: .eighth, noteType: .hiHat, measureNumber: 6, measureOffset: 0.25),
                    Note(interval: .eighth, noteType: .hiHat, measureNumber: 6, measureOffset: 0.5),
                    Note(interval: .eighth, noteType: .hiHat, measureNumber: 6, measureOffset: 0.75),
                    
                    // Measure 7 - Tom fill
                    Note(interval: .quarter, noteType: .bass, measureNumber: 7, measureOffset: 0.0),
                    Note(interval: .quarter, noteType: .snare, measureNumber: 7, measureOffset: 0.5),
                    Note(interval: .eighth, noteType: .highTom, measureNumber: 7, measureOffset: 0.75),
                    Note(interval: .eighth, noteType: .midTom, measureNumber: 7, measureOffset: 0.875),
                    Note(interval: .eighth, noteType: .hiHat, measureNumber: 7, measureOffset: 0.0),
                    Note(interval: .eighth, noteType: .hiHat, measureNumber: 7, measureOffset: 0.25),
                    
                    // Measure 8 - Regular pattern
                    Note(interval: .quarter, noteType: .bass, measureNumber: 8, measureOffset: 0.0),
                    Note(interval: .quarter, noteType: .snare, measureNumber: 8, measureOffset: 0.5),
                    Note(interval: .eighth, noteType: .hiHat, measureNumber: 8, measureOffset: 0.0),
                    Note(interval: .eighth, noteType: .hiHat, measureNumber: 8, measureOffset: 0.25),
                    Note(interval: .eighth, noteType: .hiHat, measureNumber: 8, measureOffset: 0.5),
                    Note(interval: .eighth, noteType: .hiHat, measureNumber: 8, measureOffset: 0.75),
                    
                    // Measure 9 - Build up with double bass
                    Note(interval: .eighth, noteType: .bass, measureNumber: 9, measureOffset: 0.0),
                    Note(interval: .eighth, noteType: .bass, measureNumber: 9, measureOffset: 0.25),
                    Note(interval: .quarter, noteType: .snare, measureNumber: 9, measureOffset: 0.5),
                    Note(interval: .eighth, noteType: .hiHat, measureNumber: 9, measureOffset: 0.0),
                    Note(interval: .eighth, noteType: .hiHat, measureNumber: 9, measureOffset: 0.25),
                    Note(interval: .eighth, noteType: .hiHat, measureNumber: 9, measureOffset: 0.5),
                    Note(interval: .eighth, noteType: .hiHat, measureNumber: 9, measureOffset: 0.75),
                    
                    // Measure 10 - Continue build
                    Note(interval: .eighth, noteType: .bass, measureNumber: 10, measureOffset: 0.0),
                    Note(interval: .eighth, noteType: .bass, measureNumber: 10, measureOffset: 0.25),
                    Note(interval: .quarter, noteType: .snare, measureNumber: 10, measureOffset: 0.5),
                    Note(interval: .eighth, noteType: .hiHat, measureNumber: 10, measureOffset: 0.0),
                    Note(interval: .eighth, noteType: .hiHat, measureNumber: 10, measureOffset: 0.25),
                    Note(interval: .eighth, noteType: .hiHat, measureNumber: 10, measureOffset: 0.5),
                    Note(interval: .eighth, noteType: .hiHat, measureNumber: 10, measureOffset: 0.75),
                    
                    // Measure 11 - Climax with ride cymbal
                    Note(interval: .quarter, noteType: .bass, measureNumber: 11, measureOffset: 0.0),
                    Note(interval: .quarter, noteType: .snare, measureNumber: 11, measureOffset: 0.5),
                    Note(interval: .eighth, noteType: .ride, measureNumber: 11, measureOffset: 0.0),
                    Note(interval: .eighth, noteType: .ride, measureNumber: 11, measureOffset: 0.25),
                    Note(interval: .eighth, noteType: .ride, measureNumber: 11, measureOffset: 0.5),
                    Note(interval: .eighth, noteType: .ride, measureNumber: 11, measureOffset: 0.75),
                    
                    // Measure 12 - Final measure with crash ending
                    Note(interval: .quarter, noteType: .bass, measureNumber: 12, measureOffset: 0.0),
                    Note(interval: .quarter, noteType: .crash, measureNumber: 12, measureOffset: 0.0),
                    Note(interval: .quarter, noteType: .snare, measureNumber: 12, measureOffset: 0.5),
                    Note(interval: .quarter, noteType: .crash, measureNumber: 12, measureOffset: 0.75),
                    Note(interval: .eighth, noteType: .hiHat, measureNumber: 12, measureOffset: 0.25),
                    Note(interval: .eighth, noteType: .hiHat, measureNumber: 12, measureOffset: 0.5)
                ]
            ),
            DrumTrack(
                title: "Jungle Rhythm",
                artist: "Percussionist",
                bpm: 140,
                duration: "4:12",
                genre: "Electronic",
                difficulty: .hard,
                timeSignature: .fourFour,
                notes: [
                    Note(interval: .sixteenth, noteType: .bass, measureNumber: 1, measureOffset: 0.0),
                    Note(interval: .sixteenth, noteType: .bass, measureNumber: 1, measureOffset: 0.375),
                    Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0.5),
                    Note(interval: .sixteenth, noteType: .crash, measureNumber: 1, measureOffset: 0.0)
                ]
            ),
            DrumTrack(
                title: "Classic Rock Fill",
                artist: "Studio Sessions",
                bpm: 110,
                duration: "2:30",
                genre: "Rock",
                difficulty: .easy,
                timeSignature: .fourFour,
                notes: [
                    Note(interval: .quarter, noteType: .bass, measureNumber: 1, measureOffset: 0.0),
                    Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0.5),
                    Note(interval: .quarter, noteType: .highTom, measureNumber: 1, measureOffset: 0.25),
                    Note(interval: .quarter, noteType: .lowTom, measureNumber: 1, measureOffset: 0.75)
                ]
            ),
            DrumTrack(
                title: "Latin Groove",
                artist: "World Beats",
                bpm: 95,
                duration: "5:20",
                genre: "Latin",
                difficulty: .medium,
                timeSignature: .twoFour,
                notes: [
                    Note(interval: .eighth, noteType: .bass, measureNumber: 1, measureOffset: 0.0),
                    Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: 0.5),
                    Note(interval: .sixteenth, noteType: .cowbell, measureNumber: 1, measureOffset: 0.25),
                    Note(interval: .sixteenth, noteType: .cowbell, measureNumber: 1, measureOffset: 0.75)
                ]
            ),
            DrumTrack(
                title: "Blast Beat Fury",
                artist: "Metal Core",
                bpm: 180,
                duration: "2:45",
                genre: "Metal",
                difficulty: .expert,
                timeSignature: .fourFour,
                notes: [
                    Note(interval: .sixteenth, noteType: .bass, measureNumber: 1, measureOffset: 0.0),
                    Note(interval: .sixteenth, noteType: .bass, measureNumber: 1, measureOffset: 0.25),
                    Note(interval: .sixteenth, noteType: .snare, measureNumber: 1, measureOffset: 0.125),
                    Note(interval: .sixteenth, noteType: .snare, measureNumber: 1, measureOffset: 0.375),
                    Note(interval: .sixteenth, noteType: .crash, measureNumber: 1, measureOffset: 0.0)
                ]
            ),
            DrumTrack(
                title: "Jazz Swing",
                artist: "Blue Note",
                bpm: 125,
                duration: "6:15",
                genre: "Jazz",
                difficulty: .hard,
                timeSignature: .threeFour,
                notes: [
                    Note(interval: .quarter, noteType: .bass, measureNumber: 1, measureOffset: 0.0),
                    Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0.5),
                    Note(interval: .eighth, noteType: .ride, measureNumber: 1, measureOffset: 0.0),
                    Note(interval: .eighth, noteType: .ride, measureNumber: 1, measureOffset: 0.33),
                    Note(interval: .eighth, noteType: .ride, measureNumber: 1, measureOffset: 0.66)
                ]
            ),
            DrumTrack(
                title: "Hip Hop Beats",
                artist: "Urban Flow",
                bpm: 85,
                duration: "3:30",
                genre: "Hip Hop",
                difficulty: .easy,
                timeSignature: .fourFour,
                notes: [
                    Note(interval: .quarter, noteType: .bass, measureNumber: 1, measureOffset: 0.0),
                    Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0.5),
                    Note(interval: .eighth, noteType: .hiHat, measureNumber: 1, measureOffset: 0.0),
                    Note(interval: .eighth, noteType: .hiHat, measureNumber: 1, measureOffset: 0.25),
                    Note(interval: .eighth, noteType: .openHiHat, measureNumber: 1, measureOffset: 0.75)
                ]
            ),
            DrumTrack(
                title: "Polyrhythm Challenge",
                artist: "Complex Time",
                bpm: 160,
                duration: "4:45",
                genre: "Progressive",
                difficulty: .expert,
                timeSignature: .fiveFour,
                notes: [
                    Note(interval: .eighth, noteType: .bass, measureNumber: 1, measureOffset: 0.0),
                    Note(interval: .eighth, noteType: .bass, measureNumber: 1, measureOffset: 0.6),
                    Note(interval: .sixteenth, noteType: .snare, measureNumber: 1, measureOffset: 0.33),
                    Note(interval: .sixteenth, noteType: .china, measureNumber: 1, measureOffset: 0.0),
                    Note(interval: .sixteenth, noteType: .splash, measureNumber: 1, measureOffset: 0.66)
                ]
            )
        ]
    }
}
