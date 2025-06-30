//
//  DrumTrack.swift (formerly Item.swift)
//  Virgo
//
//  Created by Chan Wai Chan on 29/6/2025.
//

import Foundation
import SwiftData

@Model
final class DrumTrack {
    var title: String
    var artist: String
    var bpm: Int
    var duration: String
    var genre: String
    var difficulty: String
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
        difficulty: String,
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
    var difficultyColor: String {
        switch difficulty {
        case "Easy": return "green"
        case "Medium": return "orange"
        case "Hard": return "red"
        case "Expert": return "purple"
        default: return "gray"
        }
    }
    
    static var sampleData: [DrumTrack] {
        [
            DrumTrack(title: "Thunder Beat", artist: "DrumMaster Pro", bpm: 120, duration: "3:45", genre: "Rock", difficulty: "Medium"),
            DrumTrack(title: "Jungle Rhythm", artist: "Percussionist", bpm: 140, duration: "4:12", genre: "Electronic", difficulty: "Hard"),
            DrumTrack(title: "Classic Rock Fill", artist: "Studio Sessions", bpm: 110, duration: "2:30", genre: "Rock", difficulty: "Easy"),
            DrumTrack(title: "Latin Groove", artist: "World Beats", bpm: 95, duration: "5:20", genre: "Latin", difficulty: "Medium"),
            DrumTrack(title: "Blast Beat Fury", artist: "Metal Core", bpm: 180, duration: "2:45", genre: "Metal", difficulty: "Expert"),
            DrumTrack(title: "Jazz Swing", artist: "Blue Note", bpm: 125, duration: "6:15", genre: "Jazz", difficulty: "Hard"),
            DrumTrack(title: "Hip Hop Beats", artist: "Urban Flow", bpm: 85, duration: "3:30", genre: "Hip Hop", difficulty: "Easy"),
            DrumTrack(title: "Polyrhythm Challenge", artist: "Complex Time", bpm: 160, duration: "4:45", genre: "Progressive", difficulty: "Expert")
        ]
    }
}
