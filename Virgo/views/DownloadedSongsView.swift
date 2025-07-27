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
    let onPlayTap: (Song) -> Void
    let onSaveTap: (Song) -> Void
    
    // Filter to show only downloaded songs (DTX Import genre)
    var downloadedSongs: [Song] {
        songs.filter { $0.genre == "DTX Import" }
    }
    
    var body: some View {
        List {
            if !downloadedSongs.isEmpty {
                ForEach(downloadedSongs, id: \.id) { song in
                    DownloadedSongRowWithDelete(
                        song: song,
                        isPlaying: currentlyPlaying == song.id,
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
    
    var body: some View {
        VStack(spacing: 0) {
            // Main song row with delete button
            HStack(spacing: 12) {
                // Play/Pause Button
                Button(action: onPlayTap) {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(isPlaying ? .red : .purple)
                }
                .buttonStyle(PlainButtonStyle())
                
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
                
                // Actions: Save, Difficulties, Expand Indicator, and Delete Button
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
                        
                        // Delete Button (moved to far right)
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
                    
                    // Expand indicator
                    Button(action: handleSongTap) {
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
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(isPlaying ? Color.purple.opacity(0.2) : Color.white.opacity(0.1))
            .cornerRadius(12)
            
            // Expanded difficulty options
            if isExpanded {
                DifficultyExpansionView(
                    song: song,
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
}
