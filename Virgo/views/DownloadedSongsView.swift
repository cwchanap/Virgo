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
    static let emptyStateViewID = "downloaded-empty-state"

    static func rowViewID(for song: Song) -> String {
        let stableSongID = PersistentIdentifierPersistenceKey.canonicalKey(
            for: song.persistentModelID,
            logPrefix: "DownloadedSongsView"
        )
        return "downloaded-song-row-\(stableSongID)"
    }

    let songs: [Song]
    @ObservedObject var serverSongService: ServerSongService
    @Binding var currentlyPlaying: PersistentIdentifier?
    @Binding var expandedSongId: PersistentIdentifier?
    @ObservedObject var audioPlaybackService: AudioPlaybackService
    let onChartSelect: (Chart) -> Void
    let onPlayTap: (Song) -> Void
    let onSaveTap: (Song) -> Void

    // Filter to show only downloaded songs (server-imported)
    var downloadedSongs: [Song] {
        Self.downloadedSongs(from: songs)
    }

    static func downloadedSongs(from songs: [Song]) -> [Song] {
        songs.filter { song in
            SongRelationshipLoader.isModelAvailable(song) && song.isServerImported
        }
    }

    // Helper function to determine if a song is currently playing
    private func isPlaying(_ song: Song) -> Bool {
        // Check if playing via preview audio (for server-imported songs with preview)
        if song.isServerImported && song.previewFilePath != nil {
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
                        onChartSelect: onChartSelect,
                        onPlayTap: { onPlayTap(song) },
                        onSaveTap: { onSaveTap(song) },
                        onDelete: {
                            Task {
                                let success = await serverSongService.deleteLocalSong(song)
                                Logger.debug("Delete downloaded song result: \(success)")
                            }
                        }
                    )
                    .accessibilityIdentifier(Self.rowViewID(for: song))
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
                .id(Self.emptyStateViewID)
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
    let onChartSelect: (Chart) -> Void
    let onPlayTap: () -> Void
    let onSaveTap: () -> Void
    let onDelete: () -> Void

    // Cache relationship data to prevent SwiftData concurrency issues
    @State private var chartCount: Int
    @State private var measureCount: Int
    @State private var charts: [Chart]
    @State private var availableDifficulties: [Difficulty]

    @MainActor
    init(
        song: Song,
        isPlaying: Bool,
        isExpanded: Bool,
        isDeleting: Bool,
        expandedSongId: Binding<PersistentIdentifier?>,
        onChartSelect: @escaping (Chart) -> Void,
        onPlayTap: @escaping () -> Void,
        onSaveTap: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.song = song
        self.isPlaying = isPlaying
        self.isExpanded = isExpanded
        self.isDeleting = isDeleting
        self._expandedSongId = expandedSongId
        self.onChartSelect = onChartSelect
        self.onPlayTap = onPlayTap
        self.onSaveTap = onSaveTap
        self.onDelete = onDelete

        // Seed empty state; the .loadSongRelationships modifier populates
        // asynchronously to avoid synchronous SwiftData relationship faulting
        // during view construction.
        self._chartCount = State(initialValue: 0)
        self._measureCount = State(initialValue: 1)
        self._charts = State(initialValue: [])
        self._availableDifficulties = State(initialValue: [])
    }

    var body: some View {
        VStack(spacing: 0) {
            mainSongRow
            expandedContent
        }
        .loadSongRelationships(for: song) { data in
            charts = data.charts.filter { SongRelationshipLoader.isModelAvailable($0) }
            chartCount = data.chartCount
            measureCount = data.measureCount
            availableDifficulties = data.availableDifficulties
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
        .accessibilityLabel(song.isSaved ? "Remove bookmark" : "Save song")
        .accessibilityIdentifier("downloadedSongBookmarkButton")
        .accessibilityValue(song.isSaved ? "Saved" : "Not saved")
    }
    
    private var difficultyBadges: some View {
        HStack(spacing: 2) {
            ForEach(availableDifficulties, id: \.self) { difficulty in
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
                Button(action: onDelete) {
                    Text("Delete")
                }
                .accessibilityIdentifier("downloadedSongDeleteButton")
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
        .accessibilityIdentifier("downloadedSongExpandButton_\(song.title)")
        .accessibilityLabel("\(song.title) - \(chartCount) charts")
    }
    
    private var expandedContent: some View {
        let displayCharts = charts.filter { SongRelationshipLoader.isModelAvailable($0) }

        return Group {
            if isExpanded {
                DifficultyExpansionView(
                    charts: displayCharts,
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
        onChartSelect(chart)
    }
}
