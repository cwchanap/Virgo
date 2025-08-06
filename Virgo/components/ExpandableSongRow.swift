//
//  ExpandableSongRow.swift
//  Virgo
//
//  Created by Claude Code on 4/8/2025.
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

    // Use SwiftData relationship loader to prevent concurrency issues
    @State private var relationshipData = SongRelationshipData(
        chartCount: 0,
        measureCount: 1,
        charts: [],
        availableDifficulties: []
    )

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
                            Label("\(relationshipData.measureCount) measures", systemImage: "music.note.list")
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
                                ForEach(relationshipData.availableDifficulties, id: \.self) { difficulty in
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

                            Text("\(relationshipData.chartCount) charts")
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
                    charts: relationshipData.charts,
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
        .loadSongRelationships(for: song) { data in
            relationshipData = data
        }
    }
}
