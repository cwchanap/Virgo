//
//  SongRowComponents.swift
//  Virgo
//
//  Created by Claude Code on 27/7/2025.
//

import SwiftUI
import SwiftData

// MARK: - Main Container
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

// MARK: - Expandable Song Row
struct ExpandableSongRow: View {
    let song: Song
    let isPlaying: Bool
    let isExpanded: Bool
    let onPlayTap: () -> Void
    let onSaveTap: () -> Void
    let onSongTap: () -> Void
    let onChartSelect: (Chart) -> Void
    
    // Cache relationship data to prevent SwiftData concurrency issues
    @State private var chartCount: Int = 0
    @State private var measureCount: Int = 0
    @State private var charts: [Chart] = []
    
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
                            Label("\(measureCount) measures", systemImage: "music.note.list")
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
                            
                            Text("\(chartCount) charts")
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
                    charts: charts,
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
        .task {
            // Load relationship data asynchronously to prevent SwiftData concurrency issues
            await loadSongRelationshipData()
        }
        .onChange(of: song.id) { _, _ in
            // Reload if song changes
            Task {
                await loadSongRelationshipData()
            }
        }
    }
    
    @MainActor
    private func loadSongRelationshipData() async {
        await Task {
            // Access SwiftData relationships in a safe background context
            let songCharts = song.charts.filter { !$0.isDeleted }
            let songMeasureCount = calculateMeasureCount(from: songCharts)
            
            await MainActor.run {
                self.charts = songCharts
                self.chartCount = songCharts.count
                self.measureCount = songMeasureCount
            }
        }.value
    }
    
    private func calculateMeasureCount(from charts: [Chart]) -> Int {
        let allNotes = charts.flatMap { chart in
            chart.notes.filter { !$0.isDeleted }
        }
        return allNotes.map(\.measureNumber).max() ?? 1
    }
}

// MARK: - Difficulty Expansion View
struct DifficultyExpansionView: View {
    let charts: [Chart]
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
                ForEach(charts.sorted { $0.difficulty.sortOrder < $1.difficulty.sortOrder }, id: \.id) { chart in
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

// MARK: - Chart Selection Card
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

// MARK: - Difficulty Badge
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

// MARK: - Server Song Row
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
                VStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.green)
                    
                    // Show downloaded content indicators
                    VStack(spacing: 2) {
                        HStack(spacing: 4) {
                            Image(systemName: "music.note")
                                .font(.caption2)
                                .foregroundColor(.green)
                            Text("Charts")
                                .font(.caption2)
                                .foregroundColor(.green)
                        }
                        
                        if serverSong.hasBGM {
                            HStack(spacing: 4) {
                                Image(systemName: serverSong.bgmDownloaded ? "waveform" : "waveform.badge.exclamationmark")
                                    .font(.caption2)
                                    .foregroundColor(serverSong.bgmDownloaded ? .green : .orange)
                                Text("BGM")
                                    .font(.caption2)
                                    .foregroundColor(serverSong.bgmDownloaded ? .green : .orange)
                            }
                        }
                        
                        if serverSong.hasPreview {
                            HStack(spacing: 4) {
                                Image(systemName: serverSong.previewDownloaded ? "play.circle" : "play.circle.badge.exclamationmark")
                                    .font(.caption2)
                                    .foregroundColor(serverSong.previewDownloaded ? .green : .orange)
                                Text("Preview")
                                    .font(.caption2)
                                    .foregroundColor(serverSong.previewDownloaded ? .green : .orange)
                            }
                        }
                    }
                }
            } else if isLoading {
                VStack(spacing: 4) {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Downloading...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    // Show what's being downloaded
                    VStack(spacing: 2) {
                        HStack(spacing: 4) {
                            Image(systemName: "music.note")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text("Chart files")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        if serverSong.hasBGM {
                            HStack(spacing: 4) {
                                Image(systemName: "waveform")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text("Background music")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        if serverSong.hasPreview {
                            HStack(spacing: 4) {
                                Image(systemName: "play.circle")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text("Preview audio")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
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
