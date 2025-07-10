//
//  DrumTrack.swift (formerly Item.swift)
//  Virgo
//
//  Created by Chan Wai Chan on 29/6/2025.
//

import Foundation
import SwiftData
import SwiftUI

enum Difficulty: String, Codable {
    case easy = "Easy"
    case medium = "Medium"
    case hard = "Hard"
    case expert = "Expert"

    var color: Color {
        switch self {
        case .easy: return .green
        case .medium: return .orange
        case .hard: return .red
        case .expert: return .purple
        }
    }
}

enum TimeSignature: String, Codable, CaseIterable {
    case fourFour = "4/4"
    case threeFour = "3/4"
    case twoFour = "2/4"
    case sixEight = "6/8"
    case fiveFour = "5/4"
    case sevenEight = "7/8"
    case nineEight = "9/8"
    case twelveEight = "12/8"
    
    var beatsPerMeasure: Int {
        switch self {
        case .fourFour: return 4
        case .threeFour: return 3
        case .twoFour: return 2
        case .sixEight: return 6
        case .fiveFour: return 5
        case .sevenEight: return 7
        case .nineEight: return 9
        case .twelveEight: return 12
        }
    }
    
    var noteValue: Int {
        switch self {
        case .fourFour, .threeFour, .twoFour, .fiveFour: return 4
        case .sixEight, .sevenEight, .nineEight, .twelveEight: return 8
        }
    }
    
    var displayName: String {
        return self.rawValue
    }
}

enum NoteInterval: String, Codable, CaseIterable {
    case full = "Full"
    case half = "Half"
    case quarter = "Quarter"
    case eighth = "Eighth"
    case sixteenth = "Sixteenth"
    case thirtysecond = "Thirty Second"
    case sixtyfourth = "Sixty Fourth"
    
    var needsStem: Bool {
        switch self {
        case .full, .half:
            return false
        case .quarter, .eighth, .sixteenth, .thirtysecond, .sixtyfourth:
            return true
        }
    }
    
    var needsFlag: Bool {
        switch self {
        case .full, .half, .quarter:
            return false
        case .eighth, .sixteenth, .thirtysecond, .sixtyfourth:
            return true
        }
    }
    
    var flagCount: Int {
        switch self {
        case .full, .half, .quarter:
            return 0
        case .eighth:
            return 1
        case .sixteenth:
            return 2
        case .thirtysecond:
            return 3
        case .sixtyfourth:
            return 4
        }
    }
}

enum NoteType: String, Codable, CaseIterable {
    case bass = "Bass"
    case snare = "Snare"
    case highTom = "High Tom"
    case midTom = "Mid Tom"
    case lowTom = "Low Tom"
    case hiHat = "Hi-Hat"
    case openHiHat = "Open Hi-Hat"
    case crash = "Crash"
    case ride = "Ride"
    case china = "China"
    case splash = "Splash"
    case cowbell = "Cowbell"
}

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
    var timeSignature: TimeSignature
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
        self.timeSignature = timeSignature
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
        switch difficulty {
        case .easy: return .green
        case .medium: return .orange
        case .hard: return .red
        case .expert: return .purple
        }
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
                    Note(interval: .quarter, noteType: .bass, measureNumber: 1, measureOffset: 0.0),
                    Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0.5),
                    Note(interval: .eighth, noteType: .hiHat, measureNumber: 1, measureOffset: 0.0),
                    Note(interval: .eighth, noteType: .hiHat, measureNumber: 1, measureOffset: 0.25),
                    Note(interval: .eighth, noteType: .hiHat, measureNumber: 1, measureOffset: 0.5),
                    Note(interval: .eighth, noteType: .hiHat, measureNumber: 1, measureOffset: 0.75)
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
