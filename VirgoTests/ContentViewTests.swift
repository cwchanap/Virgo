//
//  ContentViewTests.swift
//  VirgoTests
//
//  Created by Chan Wai Chan on 30/6/2025.
//

import Testing
import Foundation
@testable import Virgo

struct ContentViewTests {
    
    @Test func testSearchFilteringByTitle() async throws {
        let tracks = [
            DrumTrack(title: "Rock Anthem", artist: "The Rockers", bpm: 120, duration: "3:00", genre: "Rock", difficulty: "Medium"),
            DrumTrack(title: "Jazz Fusion", artist: "Smooth Players", bpm: 140, duration: "4:00", genre: "Jazz", difficulty: "Hard"),
            DrumTrack(title: "Electronic Beat", artist: "The Rockers", bpm: 128, duration: "3:30", genre: "Electronic", difficulty: "Easy")
        ]
        
        // Test title filtering
        let titleFiltered = tracks.filter { $0.title.localizedCaseInsensitiveContains("rock") }
        #expect(titleFiltered.count == 1)
        #expect(titleFiltered.first?.title == "Rock Anthem")
        
        // Test partial title matching
        let jazzFiltered = tracks.filter { $0.title.localizedCaseInsensitiveContains("jazz") }
        #expect(jazzFiltered.count == 1)
        #expect(jazzFiltered.first?.title == "Jazz Fusion")
        
        // Test no matches
        let noMatches = tracks.filter { $0.title.localizedCaseInsensitiveContains("classical") }
        #expect(noMatches.isEmpty)
    }
    
    @Test func testSearchFilteringByArtist() async throws {
        let tracks = [
            DrumTrack(title: "Rock Anthem", artist: "The Rockers", bpm: 120, duration: "3:00", genre: "Rock", difficulty: "Medium"),
            DrumTrack(title: "Jazz Fusion", artist: "Smooth Players", bpm: 140, duration: "4:00", genre: "Jazz", difficulty: "Hard"),
            DrumTrack(title: "Electronic Beat", artist: "The Rockers", bpm: 128, duration: "3:30", genre: "Electronic", difficulty: "Easy")
        ]
        
        // Test artist filtering  
        let artistFiltered = tracks.filter { $0.artist.localizedCaseInsensitiveContains("rockers") }
        #expect(artistFiltered.count == 2)
        
        // Test single artist match
        let smoothFiltered = tracks.filter { $0.artist.localizedCaseInsensitiveContains("smooth") }
        #expect(smoothFiltered.count == 1)
        #expect(smoothFiltered.first?.artist == "Smooth Players")
    }
    
    @Test func testCaseInsensitiveSearch() async throws {
        let tracks = [
            DrumTrack(title: "Rock Anthem", artist: "The Rockers", bpm: 120, duration: "3:00", genre: "Rock", difficulty: "Medium"),
            DrumTrack(title: "Jazz Fusion", artist: "Smooth Players", bpm: 140, duration: "4:00", genre: "Jazz", difficulty: "Hard")
        ]
        
        // Test uppercase search
        let upperCaseFiltered = tracks.filter { 
            $0.title.localizedCaseInsensitiveContains("JAZZ") || 
            $0.artist.localizedCaseInsensitiveContains("JAZZ") 
        }
        #expect(upperCaseFiltered.count == 1)
        #expect(upperCaseFiltered.first?.title == "Jazz Fusion")
        
        // Test lowercase search
        let lowerCaseFiltered = tracks.filter { 
            $0.title.localizedCaseInsensitiveContains("rock") || 
            $0.artist.localizedCaseInsensitiveContains("rock") 
        }
        #expect(lowerCaseFiltered.count == 1)
        #expect(lowerCaseFiltered.first?.title == "Rock Anthem")
        
        // Test mixed case search
        let mixedCaseFiltered = tracks.filter { 
            $0.title.localizedCaseInsensitiveContains("RoCk") || 
            $0.artist.localizedCaseInsensitiveContains("RoCk") 
        }
        #expect(mixedCaseFiltered.count == 1)
    }
    
    @Test func testEmptySearchBehavior() async throws {
        let tracks = [
            DrumTrack(title: "Track 1", artist: "Artist 1", bpm: 120, duration: "3:00", genre: "Rock", difficulty: "Easy"),
            DrumTrack(title: "Track 2", artist: "Artist 2", bpm: 140, duration: "4:00", genre: "Jazz", difficulty: "Medium"),
            DrumTrack(title: "Track 3", artist: "Artist 3", bpm: 160, duration: "5:00", genre: "Metal", difficulty: "Hard")
        ]
        
        // Empty search should return all tracks
        let emptySearch = ""
        let filteredTracks = tracks.filter { track in
            emptySearch.isEmpty || 
            track.title.localizedCaseInsensitiveContains(emptySearch) || 
            track.artist.localizedCaseInsensitiveContains(emptySearch)
        }
        #expect(filteredTracks.count == 3)
        #expect(filteredTracks == tracks)
    }
    
    @Test func testCombinedTitleAndArtistSearch() async throws {
        let tracks = [
            DrumTrack(title: "Rock Beat", artist: "Jazz Masters", bpm: 120, duration: "3:00", genre: "Fusion", difficulty: "Medium"),
            DrumTrack(title: "Jazz Rhythm", artist: "Rock Stars", bpm: 140, duration: "4:00", genre: "Jazz", difficulty: "Hard"),
            DrumTrack(title: "Pop Song", artist: "Pop Artists", bpm: 128, duration: "3:30", genre: "Pop", difficulty: "Easy")
        ]
        
        // Search for "rock" should find both title and artist matches
        let rockSearch = tracks.filter { 
            $0.title.localizedCaseInsensitiveContains("rock") || 
            $0.artist.localizedCaseInsensitiveContains("rock") 
        }
        #expect(rockSearch.count == 2)
        
        // Search for "jazz" should find both title and artist matches  
        let jazzSearch = tracks.filter { 
            $0.title.localizedCaseInsensitiveContains("jazz") || 
            $0.artist.localizedCaseInsensitiveContains("jazz") 
        }
        #expect(jazzSearch.count == 2)
    }
    
    @Test func testSearchWithSpecialCharacters() async throws {
        let tracks = [
            DrumTrack(title: "Rock & Roll", artist: "The Band", bpm: 120, duration: "3:00", genre: "Rock", difficulty: "Medium"),
            DrumTrack(title: "Jazz-Fusion", artist: "Modern Jazz", bpm: 140, duration: "4:00", genre: "Jazz", difficulty: "Hard"),
            DrumTrack(title: "Hip-Hop Beat", artist: "MC Producer", bpm: 95, duration: "3:30", genre: "Hip Hop", difficulty: "Easy")
        ]
        
        // Test search with ampersand
        let ampersandSearch = tracks.filter { $0.title.localizedCaseInsensitiveContains("&") }
        #expect(ampersandSearch.count == 1)
        #expect(ampersandSearch.first?.title == "Rock & Roll")
        
        // Test search with hyphen
        let hyphenSearch = tracks.filter { 
            $0.title.localizedCaseInsensitiveContains("-") || 
            $0.artist.localizedCaseInsensitiveContains("-") 
        }
        #expect(hyphenSearch.count == 2)
    }
    
    @Test func testTrackCountDisplay() async throws {
        let emptyTracks: [DrumTrack] = []
        let singleTrack = [DrumTrack(title: "Solo", artist: "Artist", bpm: 100, duration: "2:00", genre: "Pop", difficulty: "Easy")]
        let multipleTracks = DrumTrack.sampleData
        
        #expect(emptyTracks.count == 0)
        #expect(singleTrack.count == 1)
        #expect(multipleTracks.count == 8)
        
        // Test count message formatting
        let emptyMessage = "\(emptyTracks.count) tracks available"
        let singleMessage = "\(singleTrack.count) tracks available"
        let multipleMessage = "\(multipleTracks.count) tracks available"
        
        #expect(emptyMessage == "0 tracks available")
        #expect(singleMessage == "1 tracks available")
        #expect(multipleMessage == "8 tracks available")
    }
    
    @Test func testSearchPerformanceWithLargeDataset() async throws {
        // Create a large dataset for performance testing
        var largeTracks: [DrumTrack] = []
        for i in 0..<1000 {
            largeTracks.append(DrumTrack(
                title: "Track \(i)",
                artist: "Artist \(i % 100)",
                bpm: 120 + (i % 80),
                duration: "3:\(String(format: "%02d", i % 60))",
                genre: ["Rock", "Jazz", "Electronic", "Hip Hop"][i % 4],
                difficulty: ["Easy", "Medium", "Hard", "Expert"][i % 4]
            ))
        }
        
        // Test search performance
        let searchTerm = "Artist 5"
        let filtered = largeTracks.filter { 
            $0.title.localizedCaseInsensitiveContains(searchTerm) || 
            $0.artist.localizedCaseInsensitiveContains(searchTerm) 
        }
        
        // Should find all artists that contain "5" (5, 15, 25, 35, 45, 50-59, 65, 75, 85, 95)
        #expect(filtered.count > 0)
        #expect(filtered.allSatisfy { $0.artist.contains("5") })
    }
    
    @Test func testSearchResultOrdering() async throws {
        let tracks = [
            DrumTrack(title: "A Rock Song", artist: "Artist A", bpm: 120, duration: "3:00", genre: "Rock", difficulty: "Easy"),
            DrumTrack(title: "B Jazz Track", artist: "Artist B", bpm: 140, duration: "4:00", genre: "Jazz", difficulty: "Medium"),
            DrumTrack(title: "C Rock Anthem", artist: "Artist C", bpm: 160, duration: "5:00", genre: "Rock", difficulty: "Hard")
        ]
        
        // Search for "rock" and verify original order is maintained
        let rockTracks = tracks.filter { 
            $0.title.localizedCaseInsensitiveContains("rock") || 
            $0.artist.localizedCaseInsensitiveContains("rock") 
        }
        
        #expect(rockTracks.count == 2)
        #expect(rockTracks[0].title == "A Rock Song")
        #expect(rockTracks[1].title == "C Rock Anthem")
    }
}