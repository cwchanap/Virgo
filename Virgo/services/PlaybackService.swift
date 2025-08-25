//
//  PlaybackService.swift
//  Virgo
//
//  Created by Claude Code on 27/7/2025.
//

import SwiftUI
import SwiftData

@MainActor
class PlaybackService: ObservableObject {
    @Published var currentlyPlaying: PersistentIdentifier?
    
    private var currentSong: Song?
    
    func togglePlayback(for song: Song) {
        // Toggle playback state for the selected song
        if currentlyPlaying == song.id {
            // Stop current song
            currentlyPlaying = nil
            currentSong?.isPlaying = false
            if let currentTitle = currentSong?.title {
                Logger.audioPlayback("Stopped song: \(currentTitle)")
            }
            currentSong = nil
        } else {
            // Stop any currently playing song
            currentSong?.isPlaying = false
            if let previousTitle = currentSong?.title {
                Logger.audioPlayback("Stopped previous song: \(previousTitle)")
            }
            
            // Start new song
            currentlyPlaying = song.id
            currentSong = song
            song.isPlaying = true
            Logger.audioPlayback("Started song: \(song.title)")
        }
    }

    func isPlaying(_ song: Song) -> Bool {
        return currentlyPlaying == song.id
    }

    func stopAll() {
        // Stop currently playing song if any
        if let currentSong = currentSong {
            currentSong.isPlaying = false
            Logger.audioPlayback("Stopped song via stopAll: \(currentSong.title)")
        }
        currentlyPlaying = nil
        self.currentSong = nil
        Logger.audioPlayback("Stopped all playback")
    }
}
