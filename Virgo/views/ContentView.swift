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
    @State private var gameplayNavigation = GameplayNavigationState()
    @State private var isPreparingStartupData =
        ContentStartupPolicy.shouldPrepareBeforeFirstRender(arguments: ProcessInfo.processInfo.arguments)
    @State private var startupSongsOverride: [Song]?

    @State private var databaseService: DatabaseMaintenanceService?

    var body: some View {
        currentContent
            .onChange(of: gameplayNavigation.isShowingGameplay) { _, isNavigating in
                guard isNavigating else { return }
                audioPlaybackService.stop()
                playbackService.stopAll()
            }
            .onAppear {
                let args = ProcessInfo.processInfo.arguments
                let missingFixtures: Set<String>
                if args.contains(LaunchArguments.uiTesting) {
                    let fixtureTitles = Set(Song.sampleData.map { $0.title })
                    let existingTitles = Set(fetchLiveSongs().map { $0.title })
                    missingFixtures = fixtureTitles.subtracting(existingTitles)
                } else {
                    missingFixtures = []
                }

                var startupSongs: [Song]?
                var shouldRefreshStartupSongs = false
                switch ContentStartupPolicy.startupAction(arguments: args, missingFixtureTitles: missingFixtures) {
                case .clearAndSeed:
                    clearPersistedTestState()
                    seedUITestData()
                    shouldRefreshStartupSongs = true
                case .clearOnly:
                    clearPersistedTestState()
                    startupSongs = []
                    startupSongsOverride = []
                case .seedIfNeeded:
                    seedUITestData(missingFixtures: missingFixtures)
                    shouldRefreshStartupSongs = true
                case .noAction:
                    break
                }
                if ContentStartupPolicy.shouldImportBundledLocalDTXFixtures(arguments: args) {
                    seedLocalDTXFixtures()
                    shouldRefreshStartupSongs = true
                }
                if shouldRefreshStartupSongs {
                    startupSongs = fetchLiveSongs()
                    startupSongsOverride = startupSongs
                }
                if databaseService == nil {
                    databaseService = DatabaseMaintenanceService(modelContext: modelContext)
                }
                databaseService?.performInitialMaintenance(songs: startupSongs ?? displayedSongs)
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
                    Logger.error(
                        "ContentView: failed to fetch charts for legacy migration: \(error.localizedDescription)"
                    )
                }
                serverSongService.setModelContext(modelContext)
                let serverSongService = serverSongService
                if startupSongsOverride != nil {
                    startupSongsOverride = fetchLiveSongs()
                }
                isPreparingStartupData = false
                Task { @MainActor in
                    _ = await serverSongService.loadServerSongs()
                }
            }
    }

    @ViewBuilder
    private var currentContent: some View {
        if isPreparingStartupData {
            startupPreparationView
        } else if let chart = gameplayNavigation.selectedChart {
            GameplayView(
                chart: chart,
                metronome: metronome,
                onDismiss: dismissGameplay
            )
        } else {
            tabShell
        }
    }

    private var displayedSongs: [Song] {
        startupSongsOverride ?? allSongs.filter { SongRelationshipLoader.isModelAvailable($0) }
    }

    private var startupPreparationView: some View {
        Color.black
            .ignoresSafeArea()
            .overlay {
                ProgressView()
                    .controlSize(.large)
            }
            .accessibilityIdentifier("startupPreparationView")
    }

    private var tabShell: some View {
        TabView(selection: $selectedTab) {
            // Songs Tab with Sub-tabs
            NavigationStack {
                SongsTabView(
                    allSongs: displayedSongs,
                    serverSongs: serverSongs,
                    serverSongService: serverSongService,
                    searchText: $searchText,
                    currentlyPlaying: $playbackService.currentlyPlaying,
                    expandedSongId: $expandedSongId,
                    audioPlaybackService: audioPlaybackService,
                    onChartSelect: openGameplay,
                    onPlayTap: { song in
                        if ContentStartupPolicy.shouldUsePreviewPlayer(for: song) {
                            audioPlaybackService.togglePlayback(for: song)
                        } else {
                            playbackService.togglePlayback(for: song)
                        }
                    },
                    onSaveTap: toggleSave
                )
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

            LibraryView(songs: displayedSongs, serverSongService: serverSongService)
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
        .accessibilityIdentifier("appTabShell")
    }

    private func toggleSave(for song: Song) {
        song.isSaved.toggle()
        Logger.database("Song \(song.title) \(song.isSaved ? "saved" : "unsaved")")
    }

    private func dismissGameplay() {
        gameplayNavigation.dismissGameplay()
    }

    private func openGameplay(with chart: Chart) {
        gameplayNavigation.openGameplay(with: chart)
    }

    private func fetchLiveSongs() -> [Song] {
        do {
            return try modelContext.fetch(FetchDescriptor<Song>())
                .filter { SongRelationshipLoader.isModelAvailable($0) }
        } catch {
            Logger.databaseError(error)
            return []
        }
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
            let song = Song.fixtureCopy(from: templateSong, genre: "DTX Import", isServerImported: true)
            modelContext.insert(song)
            for chart in song.charts {
                modelContext.insert(chart)
                for note in chart.notes {
                    modelContext.insert(note)
                }
            }
        }

        do {
            try modelContext.save()
            let titles = fixturesToSeed.sorted().joined(separator: ", ")
            Logger.database("Seeded \(sampleSongs.count) UI test songs: \(titles)")
        } catch {
            Logger.databaseError(error)
            assertionFailure("Failed to seed UI test data: \(error.localizedDescription)")
        }
    }

    private func seedLocalDTXFixtures() {
        do {
            let song = try LocalDTXFixtureImporter.importBundledSoukyuuIfAvailable(into: modelContext)
            if let song {
                Logger.database("Seeded local DTX fixture: \(song.title)")
            }
        } catch {
            Logger.databaseError(error)
            assertionFailure("Failed to seed local DTX fixture: \(error.localizedDescription)")
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Song.self, inMemory: true)
        .environmentObject(MetronomeEngine())
        .environmentObject(PracticeSettingsService())
}
