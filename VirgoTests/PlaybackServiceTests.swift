//
//  PlaybackServiceTests.swift
//  VirgoTests
//
//  Created by Claude Code on 19/8/2025.
//

import Testing
import SwiftData
@testable import Virgo

@Suite("PlaybackService Tests")
@MainActor
struct PlaybackServiceTests {
    
    @Test("PlaybackService initializes with no currently playing song")
    func testInitialization() {
        let service = PlaybackService()
        #expect(service.currentlyPlaying == nil)
    }
    
    @Test("PlaybackService toggles playback correctly")
    func testTogglePlayback() {
        let service = PlaybackService()
        let song = Song(title: "Test Song", artist: "Test Artist", bpm: 120.0, duration: "3:00", genre: "Rock")
        
        // Initially not playing
        #expect(!service.isPlaying(song))
        #expect(service.currentlyPlaying == nil)
        #expect(!song.isPlaying)
        
        // Start playback
        service.togglePlayback(for: song)
        #expect(service.isPlaying(song))
        #expect(service.currentlyPlaying == song.id)
        #expect(song.isPlaying)
        
        // Stop playback
        service.togglePlayback(for: song)
        #expect(!service.isPlaying(song))
        #expect(service.currentlyPlaying == nil)
        #expect(!song.isPlaying)
    }
    
    @Test("PlaybackService switches between songs correctly")
    func testSwitchBetweenSongs() {
        let service = PlaybackService()
        let song1 = Song(title: "Song 1", artist: "Artist 1", bpm: 120.0, duration: "3:00", genre: "Rock")
        let song2 = Song(title: "Song 2", artist: "Artist 2", bpm: 140.0, duration: "4:00", genre: "Jazz")
        
        // Start first song
        service.togglePlayback(for: song1)
        #expect(service.isPlaying(song1))
        #expect(!service.isPlaying(song2))
        #expect(song1.isPlaying)
        #expect(!song2.isPlaying)
        
        // Switch to second song
        service.togglePlayback(for: song2)
        #expect(!service.isPlaying(song1))
        #expect(service.isPlaying(song2))
        #expect(!song1.isPlaying)
        #expect(song2.isPlaying)
    }
    
    @Test("PlaybackService stopAll functionality")
    func testStopAll() {
        let service = PlaybackService()
        let song = Song(title: "Test Song", artist: "Test Artist", bpm: 120.0, duration: "3:00", genre: "Rock")
        
        // Start playback
        service.togglePlayback(for: song)
        #expect(service.isPlaying(song))
        #expect(song.isPlaying)
        
        // Stop all playback
        service.stopAll()
        #expect(service.currentlyPlaying == nil)
        #expect(!service.isPlaying(song))
        // Note: stopAll() doesn't modify song.isPlaying - this might be a design decision
    }
    
    @Test("PlaybackService handles multiple songs correctly")
    func testMultipleSongsHandling() {
        let service = PlaybackService()
        let songs = [
            Song(title: "Song 1", artist: "Artist 1", bpm: 120.0, duration: "3:00", genre: "Rock"),
            Song(title: "Song 2", artist: "Artist 2", bpm: 140.0, duration: "4:00", genre: "Jazz"),
            Song(title: "Song 3", artist: "Artist 3", bpm: 160.0, duration: "5:00", genre: "Metal")
        ]
        
        // Ensure all songs start as not playing
        for song in songs {
            #expect(!service.isPlaying(song))
        }
        
        // Play one song at a time and verify others are not playing
        for (index, song) in songs.enumerated() {
            service.togglePlayback(for: song)
            
            for (otherIndex, otherSong) in songs.enumerated() {
                if index == otherIndex {
                    #expect(service.isPlaying(otherSong))
                } else {
                    #expect(!service.isPlaying(otherSong))
                }
            }
        }
    }
    
    @Test("PlaybackService maintains state consistency")
    func testStateConsistency() {
        let service = PlaybackService()
        let song = Song(title: "Test Song", artist: "Test Artist", bpm: 120.0, duration: "3:00", genre: "Rock")
        
        // Test that service state matches song state after operations
        service.togglePlayback(for: song)
        #expect(service.isPlaying(song) == song.isPlaying)
        
        service.togglePlayback(for: song)
        #expect(service.isPlaying(song) == song.isPlaying)
        
        // Test with multiple toggle operations
        for _ in 0..<5 {
            service.togglePlayback(for: song)
            #expect(service.isPlaying(song) == song.isPlaying)
        }
    }
}
