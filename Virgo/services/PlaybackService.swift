//
//  PlaybackService.swift
//  Virgo
//
//  Created by Claude Code on 27/7/2025.
//

import SwiftUI
import SwiftData

class WeakSongRef {
    weak var song: Song?
    
    init(_ song: Song) {
        self.song = song
    }
}

@MainActor
class PlaybackService: ObservableObject {
    @Published var currentlyPlaying: PersistentIdentifier?
    
    private var songRefs: [PersistentIdentifier: WeakSongRef] = [:]
    
    func togglePlayback(for song: Song) {
        // Store weak reference to song
        songRefs[song.id] = WeakSongRef(song)
        
        // Toggle playback state for the selected song
        if currentlyPlaying == song.id {
            currentlyPlaying = nil
            song.isPlaying = false
            Logger.audioPlayback("Stopped song: \(song.title)")
        } else {
            // Stop any currently playing song
            if let currentId = currentlyPlaying,
               let previousSong = songRefs[currentId]?.song {
                previousSong.isPlaying = false
                Logger.audioPlayback("Stopped previous song: \(previousSong.title)")
            }
            currentlyPlaying = song.id
            song.isPlaying = true
            Logger.audioPlayback("Started song: \(song.title)")
        }
    }

    func isPlaying(_ song: Song) -> Bool {
        return currentlyPlaying == song.id
    }

    func stopAll() {
        // Stop currently playing song if any
        if let currentId = currentlyPlaying,
           let currentSong = songRefs[currentId]?.song {
            currentSong.isPlaying = false
        }
        currentlyPlaying = nil
    }
}
