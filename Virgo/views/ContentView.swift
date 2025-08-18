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
    @EnvironmentObject private var metronome: MetronomeEngine
    @Query private var allSongs: [Song]
    @Query private var serverSongs: [ServerSong]
    @StateObject private var serverSongService = ServerSongService()
    @StateObject private var playbackService = PlaybackService()
    @StateObject private var audioPlaybackService = AudioPlaybackService()
    @State private var selectedTab = 0
    @State private var searchText = ""
    @State private var expandedSongId: PersistentIdentifier?
    @State private var selectedChart: Chart?
    @State private var navigateToGameplay = false

    @State private var databaseService: DatabaseMaintenanceService?

    var body: some View {
        TabView(selection: $selectedTab) {
            // Songs Tab with Sub-tabs
            SongsTabView(
                allSongs: allSongs,
                serverSongs: serverSongs,
                serverSongService: serverSongService,
                searchText: $searchText,
                currentlyPlaying: $playbackService.currentlyPlaying,
                expandedSongId: $expandedSongId,
                selectedChart: $selectedChart,
                navigateToGameplay: $navigateToGameplay,
                audioPlaybackService: audioPlaybackService,
                onPlayTap: { song in
                    // Use AudioPlaybackService for downloaded songs with preview files
                    if song.genre == "DTX Import" && song.previewFilePath != nil {
                        audioPlaybackService.togglePlayback(for: song)
                    } else {
                        playbackService.togglePlayback(for: song)
                    }
                },
                onSaveTap: toggleSave
            )
            .navigationDestination(isPresented: $navigateToGameplay) {
                if let chart = selectedChart {
                    GameplayView(chart: chart, metronome: metronome)
                }
            }
            .tabItem {
                Image(systemName: "music.note.list")
                Text("Songs")
            }
            .tag(0)

            // Metronome Tab - only pass metronome when this tab is active to reduce updates
            Group {
                if selectedTab == 1 {
                    MetronomeView()
                } else {
                    // Placeholder view when tab is not active to avoid metronome updates
                    Color.black
                        .overlay(
                            Text("Metronome")
                                .foregroundColor(.white)
                        )
                }
            }
            .tabItem {
                Image(systemName: "metronome")
                Text("Metronome")
            }
            .tag(1)

            LibraryView(songs: allSongs, serverSongService: serverSongService)
                .tabItem {
                    Image(systemName: "arrow.down.circle")
                    Text("Library")
                }
                .tag(2)

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Image(systemName: "gearshape")
                Text("Settings")
            }
            .tag(3)
            
            NavigationStack {
                ProfileView()
            }
            .tabItem {
                Image(systemName: "person")
                Text("Profile")
            }
            .tag(4)
        }
        .tint(.purple)
        .onAppear {
            if databaseService == nil {
                databaseService = DatabaseMaintenanceService(modelContext: modelContext)
            }
            databaseService?.performInitialMaintenance(songs: allSongs)
            serverSongService.setModelContext(modelContext)
            Task {
                await serverSongService.loadServerSongs()
            }
        }
    }

    private func toggleSave(for song: Song) {
        song.isSaved.toggle()
        Logger.database("Song \(song.title) \(song.isSaved ? "saved" : "unsaved")")
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Song.self, inMemory: true)
}
