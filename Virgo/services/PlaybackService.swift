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

    func togglePlayback(for song: Song) {
        // Toggle playback state for the selected song
        if currentlyPlaying == song.id {
            currentlyPlaying = nil
            song.isPlaying = false
            Logger.audioPlayback("Stopped song: \(song.title)")
        } else {
            currentlyPlaying = song.id
            song.isPlaying = true
            Logger.audioPlayback("Started song: \(song.title)")
        }
    }

    func isPlaying(_ song: Song) -> Bool {
        return currentlyPlaying == song.id
    }

    func stopAll() {
        currentlyPlaying = nil
    }
}
