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

    var body: some View {
        TabView(selection: $selectedTab) {
            // Songs Tab with Sub-tabs
            SongsTabView(
                allSongs: allSongs,
                serverSongs: serverSongs,
                serverSongService: serverSongService,
                searchText: $searchText,
                currentlyPlaying: $currentlyPlaying,
                expandedSongId: $expandedSongId,
                selectedChart: $selectedChart,
                navigateToGameplay: $navigateToGameplay,
                onPlayTap: togglePlayback,
                onSaveTap: toggleSave
            )
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
            
            SavedSongsView(songs: allSongs, serverSongService: serverSongService)
                .tabItem {
                    Image(systemName: "arrow.down.circle")
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
            // Removed loadSampleDataIfNeeded() since we have real DTX data now
            updateExistingChartLevels()
            cleanupDuplicateSongs()
            cleanupOldSampleSongs() // Remove any old sample data
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
    
    // REMOVED: loadSampleDataIfNeeded() - no longer needed since we have real DTX data
    
    private func updateExistingChartLevels() {
        // Update any existing charts that still have the default level of 50
        // and haven't been assigned proper difficulty-based levels
        var needsUpdate = false
        
        for song in allSongs {
            for chart in song.charts {
                // Only update charts that have the default level (50) and would get a different level
                if chart.level == 50 && chart.difficulty.defaultLevel != 50 {
                    chart.level = chart.difficulty.defaultLevel
                    needsUpdate = true
                }
            }
        }
        
        if needsUpdate {
            do {
                try modelContext.save()
                Logger.database("Updated existing chart levels based on difficulty")
            } catch {
                Logger.databaseError(error)
            }
        }
    }
    
    private func cleanupDuplicateSongs() {
        // Find and remove duplicate songs (same title + artist)
        var songTitleArtistPairs: Set<String> = []
        var duplicatesToRemove: [Song] = []
        
        for song in allSongs {
            let key = "\(song.title.lowercased())|\(song.artist.lowercased())"
            if songTitleArtistPairs.contains(key) {
                // This is a duplicate
                duplicatesToRemove.append(song)
                Logger.database("Found duplicate song to remove: \(song.title) by \(song.artist)")
            } else {
                songTitleArtistPairs.insert(key)
            }
        }
        
        if !duplicatesToRemove.isEmpty {
            for song in duplicatesToRemove {
                modelContext.delete(song)
            }
            
            do {
                try modelContext.save()
                Logger.database("Cleaned up \(duplicatesToRemove.count) duplicate songs")
            } catch {
                Logger.databaseError(error)
            }
        }
    }
    
    private func cleanupOldSampleSongs() {
        // Remove any old sample songs that are not DTX Import data
        let oldSampleSongs = allSongs.filter { song in
            song.genre != "DTX Import"
        }
        
        if !oldSampleSongs.isEmpty {
            Logger.database("Found \(oldSampleSongs.count) old sample songs to remove")
            
            for song in oldSampleSongs {
                Logger.database("Removing old sample song: \(song.title) by \(song.artist) (genre: \(song.genre))")
                
                // Delete all charts and their notes first for proper cleanup
                for chart in song.charts {
                    for note in chart.notes {
                        modelContext.delete(note)
                    }
                    modelContext.delete(chart)
                }
                
                // Then delete the song
                modelContext.delete(song)
            }
            
            do {
                try modelContext.save()
                Logger.database("Successfully cleaned up \(oldSampleSongs.count) old sample songs")
            } catch {
                Logger.databaseError(error)
            }
        } else {
            Logger.database("No old sample songs found to clean up")
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
                ForEach(song.charts.sorted { $0.difficulty.sortOrder < $1.difficulty.sortOrder }, id: \.id) { chart in
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
                    Text("\(chart.notesCount) notes")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Text("Level \(chart.level)")
                        .font(.caption2)
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
    @ObservedObject var serverSongService: ServerSongService
    
    var downloadedSongs: [Song] {
        // Show all songs that were downloaded from server (DTX Import genre)
        songs.filter { $0.genre == "DTX Import" }
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
                            Text("Downloaded Songs")
                                .font(.largeTitle)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            Text("\(downloadedSongs.count) songs downloaded")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                        Spacer()
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal)
                    .padding(.top)
                }
                .padding(.top, 20)
                .padding(.bottom, 16)
                
                // Downloaded Songs List
                if downloadedSongs.isEmpty {
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 64))
                            .foregroundColor(.white.opacity(0.3))
                        
                        VStack(spacing: 8) {
                            Text("No Downloaded Songs")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                            
                            Text("Download songs from the server to see them here")
                                .font(.body)
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 32)
                } else {
                    List {
                        ForEach(downloadedSongs, id: \.id) { song in
                            SavedSongRow(
                                song: song,
                                isDeleting: serverSongService.isDeleting(song),
                                onDelete: {
                                    Task { @MainActor in
                                        await serverSongService.deleteLocalSong(song)
                                    }
                                }
                            )
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
    let isDeleting: Bool
    let onDelete: (() -> Void)?
    
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
            
            // Available Difficulties and Delete Button
            VStack(spacing: 8) {
                HStack(spacing: 2) {
                    ForEach(song.availableDifficulties, id: \.self) { difficulty in
                        DifficultyBadge(difficulty: difficulty, size: .small)
                    }
                }
                
                if let onDelete = onDelete {
                    if isDeleting {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Deleting...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Button("Delete") {
                            onDelete()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .foregroundColor(.red)
                        .disabled(isDeleting)
                    }
                } else {
                    Text("No delete")
                        .font(.caption2)
                        .foregroundColor(.gray)
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
                    
                    // Display multiple difficulty levels or single level
                    if serverSong.charts.count > 1 {
                        let levels = serverSong.charts.map { String($0.level) }.joined(separator: ", ")
                        Label("Levels \(levels)", systemImage: "chart.bar")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else if let chart = serverSong.charts.first {
                        Label("Level \(chart.level)", systemImage: "chart.bar")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    // Display total size for multi-chart songs
                    let totalSize = serverSong.charts.reduce(0) { $0 + $1.size }
                    Text(formatFileSize(totalSize))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Display difficulty labels for multi-chart songs
                if serverSong.charts.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(serverSong.charts.indices, id: \.self) { index in
                                let chart = serverSong.charts[index]
                                Text("\(chart.difficultyLabel) (\(chart.level))")
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(difficultyColor(for: chart.difficulty))
                                    .foregroundColor(.white)
                                    .cornerRadius(4)
                            }
                        }
                        .padding(.horizontal, 1)
                    }
                }
            }
            
            Spacer()
            
            if serverSong.isDownloaded {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.green)
            } else if isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Downloading...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                Button("Download") {
                    onDownload()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isLoading)
            }
        }
        .padding()
        .background(Color.white.opacity(0.1))
        .cornerRadius(12)
    }
    
    private func formatFileSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
    
    private func difficultyColor(for difficulty: String) -> Color {
        switch difficulty.lowercased() {
        case "easy":
            return .green
        case "medium":
            return .yellow
        case "hard":
            return .orange
        case "expert":
            return .red
        default:
            return .blue
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Song.self, inMemory: true)
}
