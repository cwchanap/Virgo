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

    /// Detects if the app is running in UI testing mode.
    /// Uses the LaunchArguments.uiTesting launch argument to distinguish from unit tests.
    private var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains(LaunchArguments.uiTesting)
    }

    private var shouldResetState: Bool {
        ProcessInfo.processInfo.arguments.contains(LaunchArguments.resetState)
    }

    private var shouldSkipSeed: Bool {
        ProcessInfo.processInfo.arguments.contains(LaunchArguments.skipSeed)
    }

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
            if isUITesting && shouldResetState {
                clearPersistedTestState()
                // When resetting state in UI testing mode, unconditionally seed fresh data
                // to avoid stale data issues from @Query not refreshing synchronously
                // Skip seeding if -SkipSeed flag is present (for empty-state tests)
                if !shouldSkipSeed {
                    seedUITestData()
                }
            } else if isUITesting && !shouldSkipSeed {
                seedUITestDataIfNeeded()
            }
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

    private func clearPersistedTestState() {
        // Delete all existing songs and their cascaded charts/notes for a clean test slate
        for song in allSongs {
            modelContext.delete(song)
        }
        do {
            try modelContext.save()
            Logger.database("Cleared persisted test state for UI test isolation")
        } catch {
            Logger.databaseError(error)
            assertionFailure("Failed to clear persisted test state: \(error.localizedDescription)")
        }
    }

    private func seedUITestDataIfNeeded() {
        // Check for specific fixture songs rather than just isEmpty
        // This ensures UI tests always have the expected data even if
        // the simulator/device has songs from previous runs
        let fixtureTitles = Set(Song.sampleData.map { $0.title })
        let existingTitles = Set(allSongs.map { $0.title })
        let missingFixtures = fixtureTitles.subtracting(existingTitles)

        guard !missingFixtures.isEmpty else { return }

        seedUITestData(missingFixtures: missingFixtures)
    }

    /// Unconditionally seeds all UI test data. Used after reset to ensure fresh data.
    private func seedUITestData(missingFixtures: Set<String>? = nil) {
        let fixturesToSeed = missingFixtures ?? Set(Song.sampleData.map { $0.title })
        let sampleSongs = Song.sampleData.filter { fixturesToSeed.contains($0.title) }

        for templateSong in sampleSongs {
            // Create a fresh Song instance to avoid mutating shared/static sampleData
            let song = Song(
                title: templateSong.title,
                artist: templateSong.artist,
                bpm: templateSong.bpm,
                duration: templateSong.duration,
                genre: "DTX Import",
                timeSignature: templateSong.timeSignature
            )
            modelContext.insert(song)
            for templateChart in templateSong.charts {
                let chart = Chart(difficulty: templateChart.difficulty, level: templateChart.level)
                chart.song = song
                modelContext.insert(chart)
            }
        }

        do {
            try modelContext.save()
            Logger.database("Seeded \(sampleSongs.count) UI test songs: \(fixturesToSeed.sorted().joined(separator: ", "))")
        } catch {
            Logger.databaseError(error)
            assertionFailure("Failed to seed UI test data: \(error.localizedDescription)")
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Song.self, inMemory: true)
        .environmentObject(MetronomeEngine())
        .environmentObject(PracticeSettingsService())
}
