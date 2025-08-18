//
//  DownloadedSongsView.swift
//  Virgo
//
//  Created by Chan Wai Chan on 23/7/2025.
//

import SwiftUI
import SwiftData

// MARK: - Downloaded Songs View
struct DownloadedSongsView: View {
    let songs: [Song]
    @ObservedObject var serverSongService: ServerSongService
    @Binding var currentlyPlaying: PersistentIdentifier?
    @Binding var expandedSongId: PersistentIdentifier?
    @Binding var selectedChart: Chart?
    @Binding var navigateToGameplay: Bool
    @ObservedObject var audioPlaybackService: AudioPlaybackService
    let onPlayTap: (Song) -> Void
    let onSaveTap: (Song) -> Void

    // Filter to show only downloaded songs (DTX Import genre)
    var downloadedSongs: [Song] {
        songs.filter { $0.genre == "DTX Import" }
    }

    // Helper function to determine if a song is currently playing
    private func isPlaying(_ song: Song) -> Bool {
        // Check if playing via preview audio (for DTX Import songs with preview)
        if song.genre == "DTX Import" && song.previewFilePath != nil {
            return audioPlaybackService.isPlaying && audioPlaybackService.currentlyPlayingSong == song.title
        }
        // Check if playing via regular playback service
        return currentlyPlaying == song.id
    }

    var body: some View {
        List {
            if !downloadedSongs.isEmpty {
                ForEach(downloadedSongs, id: \.id) { song in
                    DownloadedSongRowWithDelete(
                        song: song,
                        isPlaying: isPlaying(song),
                        isExpanded: expandedSongId == song.persistentModelID,
                        isDeleting: serverSongService.isDeleting(song),
                        expandedSongId: $expandedSongId,
                        selectedChart: $selectedChart,
                        navigateToGameplay: $navigateToGameplay,
                        onPlayTap: { onPlayTap(song) },
                        onSaveTap: { onSaveTap(song) },
                        onDelete: {
                            Task {
                                let success = await serverSongService.deleteLocalSong(song)
                                Logger.debug("Delete downloaded song result: \(success)")
                            }
                        }
                    )
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 50))
                        .foregroundColor(.secondary)

                    Text("No Downloaded Songs")
                        .font(.title2)
                        .foregroundColor(.white)

                    Text("Download songs from the Server tab to see them here")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(PlainListStyle())
        .scrollContentBackground(.hidden)
        .background(Color.clear)
    }
}

// MARK: - Downloaded Song Row with Delete Button
struct DownloadedSongRowWithDelete: View {
    let song: Song
    let isPlaying: Bool
    let isExpanded: Bool
    let isDeleting: Bool
    @Binding var expandedSongId: PersistentIdentifier?
    @Binding var selectedChart: Chart?
    @Binding var navigateToGameplay: Bool
    let onPlayTap: () -> Void
    let onSaveTap: () -> Void
    let onDelete: () -> Void

    // Cache relationship data to prevent SwiftData concurrency issues
    @State private var chartCount: Int = 0
    @State private var measureCount: Int = 0
    @State private var charts: [Chart] = []

    var body: some View {
        VStack(spacing: 0) {
            mainSongRow
            expandedContent
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
    
    private var mainSongRow: some View {
        HStack(spacing: 12) {
            playButton
            songInfoSection
            Spacer()
            actionsSection
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(isPlaying ? Color.purple.opacity(0.2) : Color.white.opacity(0.1))
        .cornerRadius(12)
    }
    
    private var playButton: some View {
        Button(action: onPlayTap) {
            Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                .font(.system(size: 40))
                .foregroundColor(isPlaying ? .red : .purple)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var songInfoSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(song.title)
                .font(.headline)
                .lineLimit(1)
                .foregroundColor(.white)

            Text(song.artist)
                .font(.subheadline)
                .foregroundColor(.gray)
                .lineLimit(1)

            songMetadataLabels
        }
    }
    
    private var songMetadataLabels: some View {
        HStack(spacing: 12) {
            let bpmText = song.bpm.truncatingRemainder(dividingBy: 1) == 0 
                ? String(format: "%.0f", song.bpm) 
                : String(format: "%.2f", song.bpm)
            Label("\(bpmText) BPM", systemImage: "metronome")
            Label(song.duration, systemImage: "clock")
            Label(song.genre, systemImage: "music.quarternote.3")
            Label(song.timeSignature.displayName, systemImage: "music.note")
            Label("\(measureCount) measures", systemImage: "music.note.list")
        }
        .font(.caption)
        .foregroundColor(.gray)
    }
    
    private var actionsSection: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                saveButton
                difficultyBadges
                deleteSection
            }
            expandIndicator
        }
    }
    
    private var saveButton: some View {
        Button(action: onSaveTap) {
            Image(systemName: song.isSaved ? "bookmark.fill" : "bookmark")
                .font(.system(size: 18))
                .foregroundColor(song.isSaved ? .purple : .gray)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var difficultyBadges: some View {
        HStack(spacing: 2) {
            ForEach(song.availableDifficulties, id: \.self) { difficulty in
                DifficultyBadge(difficulty: difficulty, size: .small)
            }
        }
    }
    
    private var deleteSection: some View {
        Group {
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
        }
    }
    
    private var expandIndicator: some View {
        Button(action: handleSongTap) {
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
        .buttonStyle(PlainButtonStyle())
    }
    
    private var expandedContent: some View {
        Group {
            if isExpanded {
                DifficultyExpansionView(
                    charts: charts,
                    onChartSelect: handleChartSelect
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

    private func handleSongTap() {
        expandedSongId = expandedSongId == song.persistentModelID ? nil : song.persistentModelID
    }

    private func handleChartSelect(_ chart: Chart) {
        selectedChart = chart
        navigateToGameplay = true
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
