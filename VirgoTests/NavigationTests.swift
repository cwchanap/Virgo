//
//  NavigationTests.swift
//  VirgoTests
//
//  Created by Chan Wai Chan on 20/7/2025.
//

import Testing
import Foundation
import SwiftUI
import SwiftData
@testable import Virgo

struct NavigationTests {
    
    // Create a test model container for SwiftData models
    static let testContainer: ModelContainer = {
        do {
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            return try ModelContainer(
                for: Song.self, Chart.self, Note.self, ChartControlEvent.self,
                configurations: config
            )
        } catch {
            fatalError("Failed to create test container: \(error)")
        }
    }()

    @Test func testChartSelectionTriggersNavigation() async throws {
        let context = ModelContext(Self.testContainer)
        let song = Song(title: "Test Song", artist: "Test Artist", bpm: 120, duration: "3:00", genre: "Rock")
        let chart = Chart(difficulty: .medium, song: song)
        context.insert(song)
        context.insert(chart)

        var navigation = GameplayNavigationState()

        navigation.openGameplay(with: chart)

        #expect(navigation.selectedChart != nil)
        #expect(navigation.selectedChart?.difficulty == .medium)
        #expect(navigation.isShowingGameplay)
    }

    @Test func testNavigationStateInitialization() async throws {
        // Test that navigation state starts in correct initial state
        let selectedTab = 0
        let currentlyPlaying: PersistentIdentifier? = nil
        let searchText = ""
        let expandedSongId: PersistentIdentifier? = nil
        let navigation = GameplayNavigationState()

        #expect(selectedTab == 0)
        #expect(currentlyPlaying == nil)
        #expect(searchText.isEmpty)
        #expect(expandedSongId == nil)
        #expect(navigation.selectedChart == nil)
        #expect(!navigation.isShowingGameplay)
    }

    @Test func testSongExpansionToggle() async throws {
        let song = Song(title: "Test Song", artist: "Test Artist", bpm: 120, duration: "3:00", genre: "Rock")
        var expandedSongId: PersistentIdentifier?

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
        var currentlyPlaying: PersistentIdentifier?

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

        var navigation = GameplayNavigationState()

        // Test that navigation destination should be available when both conditions are met
        navigation.openGameplay(with: chart)

        let shouldShowGameplay = navigation.isShowingGameplay && navigation.selectedChart != nil
        #expect(shouldShowGameplay == true)

        // Test that navigation destination should not be available after dismiss clears the chart.
        navigation.dismissGameplay()
        let shouldNotShowGameplay = navigation.isShowingGameplay && navigation.selectedChart != nil
        #expect(shouldNotShowGameplay == false)
    }

    @Test func testMultipleChartSelection() async throws {
        let song = Song(title: "Test Song", artist: "Test Artist", bpm: 120, duration: "3:00", genre: "Rock")
        let easyChart = Chart(difficulty: .easy, song: song)
        let hardChart = Chart(difficulty: .hard, song: song)

        var navigation = GameplayNavigationState()

        // Select easy chart
        navigation.openGameplay(with: easyChart)
        #expect(navigation.selectedChart?.difficulty == .easy)
        #expect(navigation.isShowingGameplay)

        // Select hard chart (should replace previous selection)
        navigation.openGameplay(with: hardChart)
        #expect(navigation.selectedChart?.difficulty == .hard)
        #expect(navigation.isShowingGameplay)
    }

    @Test func testNavigationStateReset() async throws {
        let song = Song(title: "Test Song", artist: "Test Artist", bpm: 120, duration: "3:00", genre: "Rock")
        let chart = Chart(difficulty: .medium, song: song)

        var navigation = GameplayNavigationState()
        navigation.openGameplay(with: chart)

        // Simulate navigation state reset (like after dismissing GameplayView)
        navigation.dismissGameplay()

        #expect(navigation.selectedChart == nil)
        #expect(!navigation.isShowingGameplay)
    }

    @Test func testGameplayNavigationStateHasNoTabShellIntermediateState() async throws {
        let song = Song(title: "Test Song", artist: "Test Artist", bpm: 120, duration: "3:00", genre: "Rock")
        let chart = Chart(difficulty: .medium, song: song)
        var navigation = GameplayNavigationState()

        #expect(!navigation.isShowingGameplay)
        #expect(navigation.selectedChart == nil)

        navigation.openGameplay(with: chart)

        #expect(navigation.isShowingGameplay)
        #expect(navigation.selectedChart === chart)

        navigation.dismissGameplay()

        #expect(!navigation.isShowingGameplay)
        #expect(navigation.selectedChart == nil)
    }

    @Test func testSearchAndNavigationInteraction() async throws {
        let rockSong = Song(title: "Rock Song", artist: "Rock Artist", bpm: 120, duration: "3:00", genre: "Rock")
        let rockChart = Chart(difficulty: .medium, song: rockSong)
        rockSong.charts = [rockChart]

        let jazzSong = Song(title: "Jazz Song", artist: "Jazz Artist", bpm: 140, duration: "4:00", genre: "Jazz")
        let jazzChart = Chart(difficulty: .hard, song: jazzSong)
        jazzSong.charts = [jazzChart]

        let songs = [rockSong, jazzSong]

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
            var navigation = GameplayNavigationState()
            navigation.openGameplay(with: chart)

            #expect(navigation.selectedChart != nil)
            #expect(navigation.isShowingGameplay)
        }
    }
}
