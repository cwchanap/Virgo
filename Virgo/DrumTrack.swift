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

@Model
final class DrumTrack {
    var title: String
    var artist: String
    var bpm: Int
    var duration: String
    var genre: String
    var difficulty: Difficulty
    var isPlaying: Bool
    var dateAdded: Date
    var playCount: Int
    var isFavorite: Bool
    
    init(
        title: String,
        artist: String,
        bpm: Int,
        duration: String,
        genre: String,
        difficulty: Difficulty,
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
            DrumTrack(title: "Thunder Beat", artist: "DrumMaster Pro", bpm: 120, duration: "3:45", genre: "Rock", difficulty: .medium),
            DrumTrack(title: "Jungle Rhythm", artist: "Percussionist", bpm: 140, duration: "4:12", genre: "Electronic", difficulty: .hard),
            DrumTrack(title: "Classic Rock Fill", artist: "Studio Sessions", bpm: 110, duration: "2:30", genre: "Rock", difficulty: .easy),
            DrumTrack(title: "Latin Groove", artist: "World Beats", bpm: 95, duration: "5:20", genre: "Latin", difficulty: .medium),
            DrumTrack(title: "Blast Beat Fury", artist: "Metal Core", bpm: 180, duration: "2:45", genre: "Metal", difficulty: .expert),
            DrumTrack(title: "Jazz Swing", artist: "Blue Note", bpm: 125, duration: "6:15", genre: "Jazz", difficulty: .hard),
            DrumTrack(title: "Hip Hop Beats", artist: "Urban Flow", bpm: 85, duration: "3:30", genre: "Hip Hop", difficulty: .easy),
            DrumTrack(title: "Polyrhythm Challenge", artist: "Complex Time", bpm: 160, duration: "4:45", genre: "Progressive", difficulty: .expert)
        ]
    }
}
