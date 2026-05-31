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
                    if ContentStartupPolicy.shouldUsePreviewPlayer(for: song) {
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
            let args = ProcessInfo.processInfo.arguments
            let missingFixtures: Set<String>
            if args.contains(LaunchArguments.uiTesting) {
                let fixtureTitles = Set(Song.sampleData.map { $0.title })
                let existingTitles = Set(allSongs.map { $0.title })
                missingFixtures = fixtureTitles.subtracting(existingTitles)
            } else {
                missingFixtures = []
            }

            switch ContentStartupPolicy.startupAction(arguments: args, missingFixtureTitles: missingFixtures) {
            case .clearAndSeed:
                clearPersistedTestState()
                seedUITestData()
            case .clearOnly:
                clearPersistedTestState()
            case .seedIfNeeded:
                seedUITestData(missingFixtures: missingFixtures)
            case .noAction:
                break
            }
            if databaseService == nil {
                databaseService = DatabaseMaintenanceService(modelContext: modelContext)
            }
            databaseService?.performInitialMaintenance(songs: allSongs)
            // Re-fetch live charts after maintenance: performInitialMaintenance may delete
            // duplicate songs, making the @Query snapshot stale. Using a fresh fetch avoids
            // traversing charts on deleted Song objects that could fault or crash.
            // Only migrate legacy scores when the fetch succeeds — an empty result from a
            // failed fetch would cause migrateLegacyHighScores to delete the legacy
            // UserDefaults data and set the migration flag without migrating anything.
            do {
                let liveCharts = try modelContext.fetch(FetchDescriptor<Chart>())
                ScorePersistenceService(modelContext: modelContext)
                    .migrateLegacyHighScores(
                        charts: liveCharts,
                        from: .standard
                    )
            } catch {
                Logger.error("ContentView: failed to fetch charts for legacy migration: \(error.localizedDescription)")
            }
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
        // Fetch live objects instead of relying on a potentially stale @Query snapshot.
        let songsToDelete: [Song]
        do {
            songsToDelete = try modelContext.fetch(FetchDescriptor<Song>())
        } catch {
            Logger.databaseError(error)
            songsToDelete = allSongs
        }

        // Delete all existing songs and their cascaded charts/notes for a clean test slate.
        for song in songsToDelete {
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
            var seededCharts: [Chart] = []
            for templateChart in templateSong.charts {
                let chart = Chart(difficulty: templateChart.difficulty, level: templateChart.level)
                chart.song = song
                seededCharts.append(chart)
                modelContext.insert(chart)
            }
            song.charts = seededCharts
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
