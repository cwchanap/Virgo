//
//  ContentView.swift
//  Virgo
//
//  Created by Chan Wai Chan on 29/6/2025.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allDrumTracks: [DrumTrack]
    @State private var selectedTab = 0
    @State private var currentlyPlaying: PersistentIdentifier?
    @State private var searchText = ""
    
    // Computed property for filtered tracks
    var drumTracks: [DrumTrack] {
        if searchText.isEmpty {
            return allDrumTracks
        } else {
            return allDrumTracks.filter { track in
                track.title.localizedCaseInsensitiveContains(searchText) ||
                track.artist.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            // Drum Tracks Tab
            NavigationStack {
                VStack(spacing: 0) {
                    // Header with stats
                    VStack(spacing: 10) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Drum Tracks")
                                    .font(.largeTitle)
                                    .fontWeight(.bold)
                                Text("\(drumTracks.count) tracks available")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button(action: {}) {
                                Image(systemName: "line.3.horizontal.decrease")
                                    .font(.title2)
                                    .foregroundColor(.primary)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top)
                        
                        // Search Bar
                        HStack {
                            HStack {
                                Image(systemName: "magnifyingglass")
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 16))
                                
                                TextField("Search songs or artists...", text: $searchText)
                                    .font(.system(size: 16))
                                    .accessibilityIdentifier("searchField")
                                
                                if !searchText.isEmpty {
                                    Button(action: {
                                        searchText = ""
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.secondary)
                                            .font(.system(size: 16))
                                    }
                                    .accessibilityIdentifier("clearSearchButton")
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color.white)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                        }
                        .padding(.horizontal)
                    }
                    .background(.thinMaterial)
                    
                    // Tracks List
                    List {
                        ForEach(drumTracks, id: \.id) { track in
                            NavigationLink(destination: GameplayView(track: track)) {
                                DrumTrackRow(track: track, isPlaying: currentlyPlaying == track.id) {
                                    togglePlayback(for: track)
                                }
                            }
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        }
                    }
                    .listStyle(PlainListStyle())
                }
            }
            .tabItem {
                Image(systemName: "music.note.list")
                Text("Drums")
            }
            .tag(0)
            
            // Metronome Tab
            MetronomeView()
                .tabItem {
                    Image(systemName: "metronome")
                    Text("Metronome")
                }
                .tag(1)
            
            Text("Library Tab")
                .tabItem {
                    Image(systemName: "music.note")
                    Text("Library")
                }
                .tag(2)
            
            Text("Profile Tab")
                .tabItem {
                    Image(systemName: "person")
                    Text("Profile")
                }
                .tag(3)
        }
        .accentColor(.purple)
        .onAppear {
            loadSampleDataIfNeeded()
        }
    }
    
    private func togglePlayback(for track: DrumTrack) {
        // Toggle playback state for the selected track
        if currentlyPlaying == track.id {
            currentlyPlaying = nil
            Logger.audioPlayback("Stopped track: \(track.title)")
        } else {
            currentlyPlaying = track.id
            Logger.audioPlayback("Started track: \(track.title)")
        }
    }
    
    private func loadSampleDataIfNeeded() {
        // Single pass to check for empty tracks and collect tracks to delete
        var tracksToDelete: [DrumTrack] = []
        var hasValidTracks = false
        
        for track in allDrumTracks {
            if track.notes.isEmpty {
                tracksToDelete.append(track)
            } else {
                hasValidTracks = true
            }
        }
        
        // Determine if we need to reload (either no tracks or all tracks are empty)
        let needsReload = allDrumTracks.isEmpty || !hasValidTracks
        
        if needsReload {
            Logger.database("Database needs sample data reload...")
            
            // Delete empty tracks collected during the single pass
            for track in tracksToDelete {
                modelContext.delete(track)
            }
            
            // Insert fresh sample data
            for sampleTrack in DrumTrack.sampleData {
                modelContext.insert(sampleTrack)
            }
            
            do {
                try modelContext.save()
                Logger.database("Successfully loaded \(DrumTrack.sampleData.count) sample tracks")
            } catch {
                Logger.databaseError(error)
            }
        } else {
            Logger.database("Database already has \(allDrumTracks.count) tracks with notes")
        }
    }
}

// Custom components
struct DrumTrackRow: View {
    let track: DrumTrack
    let isPlaying: Bool
    let onPlayTap: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Play/Pause Button
            Button(action: onPlayTap) {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(isPlaying ? .red : .purple)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Track Info
            VStack(alignment: .leading, spacing: 4) {
                Text(track.title)
                    .font(.headline)
                    .lineLimit(1)
                
                Text(track.artist)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                HStack(spacing: 12) {
                    Label("\(track.bpm) BPM", systemImage: "metronome")
                    Label(track.duration, systemImage: "clock")
                    Label(track.genre, systemImage: "music.quarternote.3")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Difficulty Badge
            VStack(spacing: 4) {
                DifficultyBadge(difficulty: track.difficulty)
                
                Button(action: {}) {
                    Image(systemName: "ellipsis")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .background(isPlaying ? Color.purple.opacity(0.1) : Color.clear)
        .cornerRadius(8)
    }
}

struct DifficultyBadge: View {
    let difficulty: Difficulty
    
    var body: some View {
        Text(difficulty.rawValue)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(difficulty.color.opacity(0.2))
            .foregroundColor(difficulty.color)
            .cornerRadius(12)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: DrumTrack.self, inMemory: true)
}
