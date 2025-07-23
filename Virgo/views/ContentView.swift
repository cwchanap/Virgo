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
    @Query private var allSongs: [Song]
    @Query private var serverSongs: [ServerSong]
    @StateObject private var serverSongService = ServerSongService()
    @State private var selectedTab = 0
    @State private var currentlyPlaying: PersistentIdentifier?
    @State private var searchText = ""
    @State private var expandedSongId: PersistentIdentifier?
    @State private var selectedChart: Chart?
    @State private var navigateToGameplay = false
    @State private var showingServerSongs = false
    
    // Computed property for filtered songs
    var songs: [Song] {
        if searchText.isEmpty {
            return allSongs
        } else {
            return allSongs.filter { song in
                song.title.localizedCaseInsensitiveContains(searchText) ||
                song.artist.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    // Computed property for filtered server songs
    var filteredServerSongs: [ServerSong] {
        if searchText.isEmpty {
            return serverSongs
        } else {
            return serverSongs.filter { song in
                song.title.localizedCaseInsensitiveContains(searchText) ||
                song.artist.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    // Combined count for display
    var totalSongsCount: Int {
        return songs.count + (showingServerSongs ? filteredServerSongs.count : 0)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            // Songs Tab
            ZStack {
                // Background gradient
                LinearGradient(
                    gradient: Gradient(colors: [Color.black, Color.purple.opacity(0.3)]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header with stats
                    VStack(spacing: 10) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Songs")
                                    .font(.largeTitle)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                Text("\(totalSongsCount) songs available")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            }
                            Spacer()
                            HStack(spacing: 16) {
                                Button(action: {
                                    showingServerSongs.toggle()
                                }) {
                                    Image(systemName: showingServerSongs ? "cloud.fill" : "cloud")
                                        .font(.title2)
                                        .foregroundColor(.white)
                                }
                                
                                if showingServerSongs {
                                    Button(action: {
                                        Task {
                                            await serverSongService.refreshServerSongs()
                                        }
                                    }) {
                                        Image(systemName: serverSongService.isRefreshing ? "arrow.clockwise" : "arrow.clockwise")
                                            .font(.title2)
                                            .foregroundColor(.white)
                                            .rotationEffect(.degrees(serverSongService.isRefreshing ? 360 : 0))
                                            .animation(serverSongService.isRefreshing ? 
                                                     Animation.linear(duration: 1).repeatForever(autoreverses: false) : 
                                                     .default, value: serverSongService.isRefreshing)
                                    }
                                    .disabled(serverSongService.isRefreshing)
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top)
                        
                        // Search Bar
                        HStack {
                            HStack {
                                Image(systemName: "magnifyingglass")
                                    .foregroundColor(.gray)
                                    .font(.system(size: 16))
                                
                                TextField("Search songs or artists...", text: $searchText)
                                    .font(.system(size: 16))
                                    .foregroundColor(.white)
                                    .accessibilityIdentifier("searchField")
                                
                                if !searchText.isEmpty {
                                    Button(action: {
                                        searchText = ""
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.gray)
                                            .font(.system(size: 16))
                                    }
                                    .accessibilityIdentifier("clearSearchButton")
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
                            )
                        }
                        .padding(.horizontal)
                    }
                    .padding(.top, 20)
                    .padding(.bottom, 16)
                    
                    // Songs List
                    List {
                        // Local Songs Section
                        if !songs.isEmpty {
                            Section(header: Text("Downloaded Songs")
                                .foregroundColor(.white)
                                .font(.headline)
                                .textCase(nil)
                            ) {
                                ForEach(songs, id: \.id) { song in
                                    ExpandableSongRowContainer(
                                        song: song,
                                        isPlaying: currentlyPlaying == song.id,
                                        isExpanded: expandedSongId == song.persistentModelID,
                                        expandedSongId: $expandedSongId,
                                        selectedChart: $selectedChart,
                                        navigateToGameplay: $navigateToGameplay,
                                        onPlayTap: { togglePlayback(for: song) },
                                        onSaveTap: { toggleSave(for: song) }
                                    )
                                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Color.clear)
                                }
                            }
                        }
                        
                        // Server Songs Section
                        if showingServerSongs && !filteredServerSongs.isEmpty {
                            Section(header: Text("Server Songs")
                                .foregroundColor(.white)
                                .font(.headline)
                                .textCase(nil)
                            ) {
                                ForEach(filteredServerSongs, id: \.filename) { serverSong in
                                    ServerSongRow(
                                        serverSong: serverSong,
                                        isLoading: serverSongService.isLoading,
                                        onDownload: {
                                            Task {
                                                let success = await serverSongService.downloadAndImportSong(serverSong)
                                                if success {
                                                    // Song was imported successfully
                                                }
                                            }
                                        }
                                    )
                                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Color.clear)
                                }
                            }
                        }
                        
                        // Loading state for server songs
                        if showingServerSongs && serverSongService.isRefreshing {
                            Section {
                                HStack {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("Loading server songs...")
                                        .foregroundColor(.secondary)
                                }
                                .listRowBackground(Color.clear)
                            }
                        }
                        
                        // Empty state
                        if songs.isEmpty && (!showingServerSongs || filteredServerSongs.isEmpty) && !serverSongService.isRefreshing {
                            Section {
                                VStack(spacing: 16) {
                                    Image(systemName: "music.note")
                                        .font(.system(size: 50))
                                        .foregroundColor(.secondary)
                                    
                                    Text("No Songs Available")
                                        .font(.title2)
                                        .foregroundColor(.white)
                                    
                                    Text("Tap the cloud button to browse server songs")
                                        .font(.body)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 40)
                                .listRowBackground(Color.clear)
                            }
                        }
                    }
                    .listStyle(PlainListStyle())
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                }
            }
            .navigationDestination(isPresented: $navigateToGameplay) {
                if let chart = selectedChart {
                    GameplayView(chart: chart)
                }
            }
            .tabItem {
                Image(systemName: "music.note.list")
                Text("Songs")
            }
            .tag(0)
            
            // Metronome Tab
            MetronomeView()
                .tabItem {
                    Image(systemName: "metronome")
                    Text("Metronome")
                }
                .tag(1)
            
            SavedSongsView(songs: allSongs)
                .tabItem {
                    Image(systemName: "music.note")
                    Text("Library")
                }
                .tag(2)
            
            ZStack {
                // Background gradient
                LinearGradient(
                    gradient: Gradient(colors: [Color.black, Color.purple.opacity(0.3)]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                VStack(spacing: 20) {
                    // Header
                    VStack(spacing: 10) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Profile")
                                    .font(.largeTitle)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                Text("Manage your account and preferences")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            }
                            Spacer()
                            Image(systemName: "person.circle")
                                .font(.title2)
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal)
                        .padding(.top)
                    }
                    .padding(.top, 20)
                    .padding(.bottom, 16)
                    
                    Spacer()
                    
                    // Profile content placeholder
                    VStack(spacing: 16) {
                        Text("Profile features coming soon!")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                        
                        Text("User settings, achievements, and preferences will be available here")
                            .font(.body)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 32)
                    
                    Spacer()
                }
            }
            .tabItem {
                Image(systemName: "person")
                Text("Profile")
            }
            .tag(3)
        }
        .accentColor(.purple)
        .onAppear {
            loadSampleDataIfNeeded()
            serverSongService.setModelContext(modelContext)
            Task {
                await serverSongService.loadServerSongs()
            }
        }
    }
    
    private func togglePlayback(for song: Song) {
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
    
    private func toggleSave(for song: Song) {
        song.isSaved.toggle()
        Logger.database("Song \(song.title) \(song.isSaved ? "saved" : "unsaved")")
    }
    
    private func loadSampleDataIfNeeded() {
        // Check if we need to load sample data
        let needsReload = allSongs.isEmpty
        
        if needsReload {
            Logger.database("Database needs sample data reload...")
            
            // Insert fresh sample data
            for sampleSong in Song.sampleData {
                modelContext.insert(sampleSong)
                // Insert charts and notes (they're related via relationships)
                for chart in sampleSong.charts {
                    modelContext.insert(chart)
                    for note in chart.notes {
                        modelContext.insert(note)
                    }
                }
            }
            
            do {
                try modelContext.save()
                Logger.database("Successfully loaded \(Song.sampleData.count) sample songs")
            } catch {
                Logger.databaseError(error)
            }
        } else {
            Logger.database("Database already has \(allSongs.count) songs")
        }
    }
    
}

// Custom components
struct ExpandableSongRowContainer: View {
    let song: Song
    let isPlaying: Bool
    let isExpanded: Bool
    @Binding var expandedSongId: PersistentIdentifier?
    @Binding var selectedChart: Chart?
    @Binding var navigateToGameplay: Bool
    let onPlayTap: () -> Void
    let onSaveTap: () -> Void
    
    var body: some View {
        ExpandableSongRow(
            song: song,
            isPlaying: isPlaying,
            isExpanded: isExpanded,
            onPlayTap: onPlayTap,
            onSaveTap: onSaveTap,
            onSongTap: handleSongTap,
            onChartSelect: handleChartSelect
        )
    }
    
    private func handleSongTap() {
        expandedSongId = expandedSongId == song.persistentModelID ? nil : song.persistentModelID
    }
    
    private func handleChartSelect(_ chart: Chart) {
        selectedChart = chart
        navigateToGameplay = true
    }
}

struct ExpandableSongRow: View {
    let song: Song
    let isPlaying: Bool
    let isExpanded: Bool
    let onPlayTap: () -> Void
    let onSaveTap: () -> Void
    let onSongTap: () -> Void
    let onChartSelect: (Chart) -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Main song row
            Button(action: onSongTap) {
                HStack(spacing: 12) {
                    // Play/Pause Button
                    Button(action: onPlayTap) {
                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(isPlaying ? .red : .purple)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .onTapGesture { onPlayTap() } // Prevent song expansion when tapping play
                    
                    // Song Info
                    VStack(alignment: .leading, spacing: 4) {
                        Text(song.title)
                            .font(.headline)
                            .lineLimit(1)
                            .foregroundColor(.white)
                        
                        Text(song.artist)
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .lineLimit(1)
                        
                        HStack(spacing: 12) {
                            Label("\(song.bpm) BPM", systemImage: "metronome")
                            Label(song.duration, systemImage: "clock")
                            Label(song.genre, systemImage: "music.quarternote.3")
                            Label(song.timeSignature.displayName, systemImage: "music.note")
                            Label("\(song.measureCount) measures", systemImage: "music.note.list")
                        }
                        .font(.caption)
                        .foregroundColor(.gray)
                    }
                    
                    Spacer()
                    
                    // Save Button and Available Difficulties and Expand Indicator
                    VStack(spacing: 4) {
                        HStack(spacing: 8) {
                            // Save Button
                            Button(action: onSaveTap) {
                                Image(systemName: song.isSaved ? "bookmark.fill" : "bookmark")
                                    .font(.system(size: 18))
                                    .foregroundColor(song.isSaved ? .purple : .gray)
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            // Available Difficulties
                            HStack(spacing: 2) {
                                ForEach(song.availableDifficulties, id: \.self) { difficulty in
                                    DifficultyBadge(difficulty: difficulty, size: .small)
                                }
                            }
                        }
                        
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.down")
                                .font(.caption)
                                .foregroundColor(.gray)
                                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                                .animation(.easeInOut(duration: 0.3), value: isExpanded)
                            
                            Text("\(song.charts.count) charts")
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(isPlaying ? Color.purple.opacity(0.2) : Color.white.opacity(0.1))
                .cornerRadius(12)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Expanded difficulty options
            if isExpanded {
                DifficultyExpansionView(
                    song: song,
                    onChartSelect: onChartSelect
                )
                .padding(.top, 8)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)),
                    removal: .opacity.combined(with: .move(edge: .top))
                ))
                .animation(.easeInOut(duration: 0.3), value: isExpanded)
            }
        }
    }
}

struct DifficultyExpansionView: View {
    let song: Song
    let onChartSelect: (Chart) -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            // Expansion header
            HStack {
                Text("Select Difficulty")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                Spacer()
            }
            .padding(.horizontal, 16)
            
            // Difficulty cards in rows
            VStack(spacing: 6) {
                ForEach(song.charts.sorted { $0.difficulty.rawValue < $1.difficulty.rawValue }, id: \.id) { chart in
                    ChartSelectionCard(chart: chart) {
                        onChartSelect(chart)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.1))
        .cornerRadius(12)
        .padding(.horizontal, 4)
    }
}

struct ChartSelectionCard: View {
    let chart: Chart
    let onSelect: () -> Void
    @State private var isPressed = false
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                DifficultyBadge(difficulty: chart.difficulty, size: .normal)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(chart.notes.count) notes")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(Color.white.opacity(0.1))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(chart.difficulty.color.opacity(0.4), lineWidth: 1)
            )
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .opacity(isPressed ? 0.8 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = pressing
            }
        }, perform: {})
    }
}

struct DifficultyBadge: View {
    let difficulty: Difficulty
    var size: BadgeSize = .normal
    
    enum BadgeSize {
        case small, normal, large
        
        var font: Font {
            switch self {
            case .small: return .caption2
            case .normal: return .caption2
            case .large: return .caption
            }
        }
        
        var padding: (horizontal: CGFloat, vertical: CGFloat) {
            switch self {
            case .small: return (4, 2)
            case .normal: return (8, 4)
            case .large: return (12, 6)
            }
        }
    }
    
    var body: some View {
        Text(difficulty.rawValue)
            .font(size.font)
            .fontWeight(.semibold)
            .padding(.horizontal, size.padding.horizontal)
            .padding(.vertical, size.padding.vertical)
            .background(difficulty.color.opacity(0.2))
            .foregroundColor(difficulty.color)
            .cornerRadius(12)
    }
}

struct SavedSongsView: View {
    let songs: [Song]
    
    var savedSongs: [Song] {
        songs.filter { $0.isSaved }
    }
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: [Color.black, Color.purple.opacity(0.3)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 10) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Bookmarked Songs")
                                .font(.largeTitle)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            Text("\(savedSongs.count) songs bookmarked")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                        Spacer()
                        Image(systemName: "bookmark.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal)
                    .padding(.top)
                }
                .padding(.top, 20)
                .padding(.bottom, 16)
                
                // Saved Songs List
                if savedSongs.isEmpty {
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "bookmark")
                            .font(.system(size: 64))
                            .foregroundColor(.white.opacity(0.3))
                        
                        VStack(spacing: 8) {
                            Text("No Bookmarked Songs")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                            
                            Text("Tap the bookmark icon on any song to bookmark it here")
                                .font(.body)
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 32)
                } else {
                    List {
                        ForEach(savedSongs, id: \.id) { song in
                            SavedSongRow(song: song)
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        }
                    }
                    .listStyle(PlainListStyle())
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                }
            }
        }
    }
}

struct SavedSongRow: View {
    let song: Song
    
    var body: some View {
        HStack(spacing: 12) {
            // Song Info
            VStack(alignment: .leading, spacing: 4) {
                Text(song.title)
                    .font(.headline)
                    .lineLimit(1)
                    .foregroundColor(.white)
                
                Text(song.artist)
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .lineLimit(1)
                
                HStack(spacing: 12) {
                    Label("\(song.bpm) BPM", systemImage: "metronome")
                    Label(song.duration, systemImage: "clock")
                    Label(song.genre, systemImage: "music.quarternote.3")
                }
                .font(.caption)
                .foregroundColor(.gray)
            }
            
            Spacer()
            
            // Available Difficulties
            HStack(spacing: 2) {
                ForEach(song.availableDifficulties, id: \.self) { difficulty in
                    DifficultyBadge(difficulty: difficulty, size: .small)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.white.opacity(0.1))
        .cornerRadius(12)
    }
}

struct ServerSongRow: View {
    let serverSong: ServerSong
    let isLoading: Bool
    let onDownload: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(serverSong.title)
                    .font(.headline)
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Text("by \(serverSong.artist)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                HStack {
                    Label("\(Int(serverSong.bpm)) BPM", systemImage: "metronome")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Label("Level \(serverSong.difficultyLevel)", systemImage: "chart.bar")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text(serverSong.formatFileSize())
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            if serverSong.isDownloaded {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.green)
            } else if isLoading {
                ProgressView()
                    .scaleEffect(0.8)
            } else {
                Button("Download") {
                    onDownload()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding()
        .background(Color.white.opacity(0.1))
        .cornerRadius(12)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Song.self, inMemory: true)
}
