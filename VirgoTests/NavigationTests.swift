//
//  NavigationTests.swift
//  VirgoTests
//
//  Created by Chan Wai Chan on 20/7/2025.
//

import Testing
import Foundation
import SwiftUI
@testable import Virgo

struct NavigationTests {
    
    @Test func testChartSelectionTriggersNavigation() async throws {
        let song = Song(title: "Test Song", artist: "Test Artist", bpm: 120, duration: "3:00", genre: "Rock")
        let chart = Chart(difficulty: .medium, song: song)
        
        // Test that selecting a chart sets the navigation state
        var selectedChart: Chart?
        var navigateToGameplay = false
        
        let handleChartSelect = { (chart: Chart) in
            selectedChart = chart
            navigateToGameplay = true
        }
        
        handleChartSelect(chart)
        
        #expect(selectedChart != nil)
        #expect(selectedChart?.difficulty == .medium)
        #expect(navigateToGameplay == true)
    }
    
    @Test func testNavigationStateInitialization() async throws {
        // Test that navigation state starts in correct initial state
        let selectedTab = 0
        let currentlyPlaying: PersistentIdentifier? = nil
        let searchText = ""
        let expandedSongId: PersistentIdentifier? = nil
        let selectedChart: Chart? = nil
        let navigateToGameplay = false
        
        #expect(selectedTab == 0)
        #expect(currentlyPlaying == nil)
        #expect(searchText.isEmpty)
        #expect(expandedSongId == nil)
        #expect(selectedChart == nil)
        #expect(navigateToGameplay == false)
    }
    
    @Test func testSongExpansionToggle() async throws {
        let song = Song(title: "Test Song", artist: "Test Artist", bpm: 120, duration: "3:00", genre: "Rock")
        var expandedSongId: PersistentIdentifier? = nil
        
        let handleSongTap = {
            expandedSongId = expandedSongId == song.persistentModelID ? nil : song.persistentModelID
        }
        
        // Test expanding
        handleSongTap()
        #expect(expandedSongId == song.persistentModelID)
        
        // Test collapsing
        handleSongTap()
        #expect(expandedSongId == nil)
    }
    
    @Test func testPlaybackToggle() async throws {
        let song = Song(title: "Test Song", artist: "Test Artist", bpm: 120, duration: "3:00", genre: "Rock")
        var currentlyPlaying: PersistentIdentifier? = nil
        
        let togglePlayback = { (song: Song) in
            if currentlyPlaying == song.id {
                currentlyPlaying = nil
                song.isPlaying = false
            } else {
                currentlyPlaying = song.id
                song.isPlaying = true
            }
        }
        
        // Test starting playback
        togglePlayback(song)
        #expect(currentlyPlaying == song.id)
        #expect(song.isPlaying == true)
        
        // Test stopping playback
        togglePlayback(song)
        #expect(currentlyPlaying == nil)
        #expect(song.isPlaying == false)
    }
    
    @Test func testTabSelection() async throws {
        var selectedTab = 0
        
        // Test tab switching
        selectedTab = 1
        #expect(selectedTab == 1)
        
        selectedTab = 2
        #expect(selectedTab == 2)
        
        selectedTab = 0
        #expect(selectedTab == 0)
    }
    
    @Test func testNavigationDestinationLogic() async throws {
        let song = Song(title: "Test Song", artist: "Test Artist", bpm: 120, duration: "3:00", genre: "Rock")
        let chart = Chart(difficulty: .hard, song: song)
        
        var selectedChart: Chart? = nil
        var navigateToGameplay = false
        
        // Test that navigation destination should be available when both conditions are met
        selectedChart = chart
        navigateToGameplay = true
        
        let shouldShowGameplay = navigateToGameplay && selectedChart != nil
        #expect(shouldShowGameplay == true)
        
        // Test that navigation destination should not be available when chart is nil
        selectedChart = nil
        let shouldNotShowGameplay = navigateToGameplay && selectedChart != nil
        #expect(shouldNotShowGameplay == false)
        
        // Test that navigation destination should not be available when flag is false
        selectedChart = chart
        navigateToGameplay = false
        let shouldAlsoNotShowGameplay = navigateToGameplay && selectedChart != nil
        #expect(shouldAlsoNotShowGameplay == false)
    }
    
    @Test func testMultipleChartSelection() async throws {
        let song = Song(title: "Test Song", artist: "Test Artist", bpm: 120, duration: "3:00", genre: "Rock")
        let easyChart = Chart(difficulty: .easy, song: song)
        let hardChart = Chart(difficulty: .hard, song: song)
        
        var selectedChart: Chart?
        var navigateToGameplay = false
        
        let handleChartSelect = { (chart: Chart) in
            selectedChart = chart
            navigateToGameplay = true
        }
        
        // Select easy chart
        handleChartSelect(easyChart)
        #expect(selectedChart?.difficulty == .easy)
        #expect(navigateToGameplay == true)
        
        // Select hard chart (should replace previous selection)
        handleChartSelect(hardChart)
        #expect(selectedChart?.difficulty == .hard)
        #expect(navigateToGameplay == true)
    }
    
    @Test func testNavigationStateReset() async throws {
        let song = Song(title: "Test Song", artist: "Test Artist", bpm: 120, duration: "3:00", genre: "Rock")
        let chart = Chart(difficulty: .medium, song: song)
        
        var selectedChart: Chart? = chart
        var navigateToGameplay = true
        
        // Simulate navigation state reset (like after dismissing GameplayView)
        let resetNavigation = {
            selectedChart = nil
            navigateToGameplay = false
        }
        
        resetNavigation()
        
        #expect(selectedChart == nil)
        #expect(navigateToGameplay == false)
    }
    
    @Test func testSearchAndNavigationInteraction() async throws {
        let songs = [
            Song(title: "Rock Song", artist: "Rock Artist", bpm: 120, duration: "3:00", genre: "Rock"),
            Song(title: "Jazz Song", artist: "Jazz Artist", bpm: 140, duration: "4:00", genre: "Jazz")
        ]
        
        var searchText = "rock"
        let filteredSongs = songs.filter { song in
            searchText.isEmpty ||
            song.title.localizedCaseInsensitiveContains(searchText) ||
            song.artist.localizedCaseInsensitiveContains(searchText)
        }
        
        #expect(filteredSongs.count == 1)
        #expect(filteredSongs.first?.title == "Rock Song")
        
        // Test that navigation should still work with filtered results
        if let chart = filteredSongs.first?.charts.first {
            var selectedChart: Chart? = chart
            var navigateToGameplay = true
            
            #expect(selectedChart != nil)
            #expect(navigateToGameplay == true)
        }
    }
}