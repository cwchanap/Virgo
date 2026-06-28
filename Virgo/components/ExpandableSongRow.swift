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
    let onChartSelect: (Chart) -> Void
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
            onChartSelect: onChartSelect
        )
    }

    private func handleSongTap() {
        expandedSongId = expandedSongId == song.persistentModelID ? nil : song.persistentModelID
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

    @Environment(\.theme) private var theme

    // Use SwiftData relationship loader to prevent concurrency issues
    @State private var relationshipData = SongRelationshipData(
        chartCount: 0,
        measureCount: 1,
        charts: [],
        availableDifficulties: []
    )

    var body: some View {
        VStack(spacing: 0) {
            // Main song row wrapped in ledger-line container
            LedgerRow {
                HStack(spacing: 12) {
                    // Play/Pause Button
                    Button(action: onPlayTap) {
                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(isPlaying ? theme.accent : theme.primary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .accessibilityLabel(isPlaying ? "Pause" : "Play")

                    // Song Info
                    VStack(alignment: .leading, spacing: 4) {
                        Text(song.title)
                            .font(AppType.headline)
                            .lineLimit(1)
                            .foregroundColor(theme.primary)

                        Text(song.artist)
                            .font(.hanken(14))
                            .foregroundColor(theme.secondary)
                            .lineLimit(1)

                        HStack(spacing: 12) {
                            Label("\(song.bpm) BPM", systemImage: "metronome")
                            Label(song.duration, systemImage: "clock")
                            Label(song.genre, systemImage: "music.quarternote.3")
                            Label(song.timeSignature.displayName, systemImage: "music.note")
                            Label("\(relationshipData.measureCount) measures", systemImage: "music.note.list")
                        }
                        .font(.plexMono(11))
                        .foregroundColor(theme.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onSongTap)

                    // Save Button, Available Difficulties, and Expand Indicator
                    VStack(spacing: 4) {
                        HStack(spacing: 8) {
                            // Save Button
                            Button(action: onSaveTap) {
                                Image(systemName: song.isSaved ? "bookmark.fill" : "bookmark")
                                    .font(.system(size: 18))
                                    .foregroundColor(song.isSaved ? theme.accent : theme.secondary)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .accessibilityLabel(song.isSaved ? "Remove bookmark" : "Save song")
                            .accessibilityIdentifier("downloadedSongBookmarkButton")
                            .accessibilityValue(song.isSaved ? "Saved" : "Not saved")

                            // Available Difficulties
                            HStack(spacing: 2) {
                                ForEach(relationshipData.availableDifficulties, id: \.self) { difficulty in
                                    DifficultyPips(difficulty: difficulty, showLabel: false)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture(perform: onSongTap)
                        }

                        HStack(spacing: 4) {
                            Image(systemName: "chevron.down")
                                .foregroundColor(theme.secondary)
                                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                                .animation(.easeInOut(duration: 0.3), value: isExpanded)

                            Text("\(relationshipData.chartCount) charts")
                                .foregroundColor(theme.secondary)
                        }
                        .font(.plexMono(11))
                        .contentShape(Rectangle())
                        .onTapGesture(perform: onSongTap)
                    }
                }
                .overlay(alignment: .leading) {
                    if isPlaying {
                        Rectangle()
                            .fill(theme.accent)
                            .frame(width: 2)
                    }
                }
            }

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
