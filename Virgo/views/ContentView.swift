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
    @State private var selectedTab = 0
    @State private var currentlyPlaying: PersistentIdentifier?
    @State private var searchText = ""
    @State private var expandedSongId: PersistentIdentifier?
    @State private var selectedChart: Chart?
    @State private var navigateToGameplay = false
    
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

    var body: some View {
        TabView(selection: $selectedTab) {
            // Songs Tab
            VStack(spacing: 0) {
                    // Header with stats
                    VStack(spacing: 10) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Songs")
                                    .font(.largeTitle)
                                    .fontWeight(.bold)
                                Text("\(songs.count) songs available")
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
                            .background(.regularMaterial)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                        }
                        .padding(.horizontal)
                    }
                    .background(.thinMaterial)
                    
                    // Songs List
                    List {
                        ForEach(songs, id: \.id) { song in
                            ExpandableSongRowContainer(
                                song: song,
                                isPlaying: currentlyPlaying == song.id,
                                isExpanded: expandedSongId == song.persistentModelID,
                                expandedSongId: $expandedSongId,
                                selectedChart: $selectedChart,
                                navigateToGameplay: $navigateToGameplay
                            ) {
                                togglePlayback(for: song)
                            }
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(PlainListStyle())
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
    
    var body: some View {
        ExpandableSongRow(
            song: song,
            isPlaying: isPlaying,
            isExpanded: isExpanded,
            onPlayTap: onPlayTap,
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
                            .foregroundColor(.primary)
                        
                        Text(song.artist)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        
                        HStack(spacing: 12) {
                            Label("\(song.bpm) BPM", systemImage: "metronome")
                            Label(song.duration, systemImage: "clock")
                            Label(song.genre, systemImage: "music.quarternote.3")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    // Available Difficulties and Expand Indicator
                    VStack(spacing: 4) {
                        HStack(spacing: 2) {
                            ForEach(song.availableDifficulties, id: \.self) { difficulty in
                                DifficultyBadge(difficulty: difficulty, size: .small)
                            }
                        }
                        
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.down")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                                .animation(.easeInOut(duration: 0.3), value: isExpanded)
                            
                            Text("\(song.charts.count) charts")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(isPlaying ? Color.purple.opacity(0.1) : Color.clear)
                .background(.ultraThinMaterial)
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
                    .foregroundColor(.primary)
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
        .background(.regularMaterial)
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
                        .foregroundColor(.secondary)
                    
                    Text(chart.timeSignature.displayName)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(.ultraThinMaterial)
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

#Preview {
    ContentView()
        .modelContainer(for: Song.self, inMemory: true)
}