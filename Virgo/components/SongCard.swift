//
//  SongCard.swift
//  Virgo
//
//  Downloaded-song card for the wide-width grid layout. Tapping the info area
//  opens the difficulty picker; footer buttons handle play/save/delete inline.
//

import SwiftUI
import SwiftData

struct SongCard: View {
    let song: Song
    let isPlaying: Bool
    let isDeleting: Bool
    let onOpen: () -> Void
    let onPlayTap: () -> Void
    let onSaveTap: () -> Void
    let onDelete: () -> Void

    @Environment(\.theme) private var theme

    @State private var chartCount: Int = 0
    @State private var availableDifficulties: [Difficulty] = []

    static func cardViewID(for song: Song) -> String {
        let stableSongID = PersistentIdentifierPersistenceKey.canonicalKey(
            for: song.persistentModelID,
            logPrefix: "SongCard"
        )
        return "downloadedSongCard-\(stableSongID)"
    }

    /// Unique per-song identifier for the card's open button so UI tests can
    /// target a specific card without every card sharing the same id.
    static func cardOpenButtonID(for song: Song) -> String {
        let stableSongID = PersistentIdentifierPersistenceKey.canonicalKey(
            for: song.persistentModelID,
            logPrefix: "SongCardOpen"
        )
        return "downloadedSongCardOpenButton-\(stableSongID)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            infoButton
            RuleDivider()
            footer
        }
        .padding(Spacing.md)
        .background(isPlaying ? theme.accent.opacity(0.12) : theme.raised)
        .cornerRadius(Radius.md)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .stroke(theme.rule, lineWidth: RuleWeight.hairline)
        )
        .loadSongRelationships(for: song) { data in
            chartCount = data.chartCount
            availableDifficulties = data.availableDifficulties
        }
        .accessibilityIdentifier(Self.cardViewID(for: song))
    }

    private var infoButton: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(song.title)
                    .font(AppType.headline)
                    .foregroundColor(theme.primary)
                    .lineLimit(1)
                Text(song.artist)
                    .font(.subheadline)
                    .foregroundColor(theme.secondary)
                    .lineLimit(1)
                HStack(spacing: Spacing.sm) {
                    TempoMark(bpm: Int(song.bpm))
                    Text(song.genre)
                        .font(.plexMono(11))
                        .foregroundColor(theme.secondary)
                        .lineLimit(1)
                }
                difficultyPipsRow
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityIdentifier(Self.cardOpenButtonID(for: song))
        .accessibilityLabel("Open \(song.title)")
    }

    private var difficultyPipsRow: some View {
        HStack(spacing: Spacing.sm) {
            ForEach(availableDifficulties, id: \.self) { difficulty in
                DifficultyPips(difficulty: difficulty, showLabel: false)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: Spacing.md) {
            Button(action: onPlayTap) {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(isPlaying ? theme.accent : theme.primary)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(isDeleting)
            .accessibilityLabel(isPlaying ? "Pause" : "Play")

            Button(action: onSaveTap) {
                Image(systemName: song.isSaved ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 18))
                    .foregroundColor(song.isSaved ? theme.accent : theme.secondary)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(isDeleting)
            .accessibilityLabel(song.isSaved ? "Remove bookmark" : "Save song")
            .accessibilityIdentifier("downloadedSongBookmarkButton")
            .accessibilityValue(song.isSaved ? "Saved" : "Not saved")

            Text("\(chartCount) charts")
                .font(.caption2)
                .foregroundColor(theme.secondary)

            Spacer()

            deleteControl
        }
    }

    @ViewBuilder
    private var deleteControl: some View {
        if isDeleting {
            HStack(spacing: Spacing.sm) {
                ProgressView().scaleEffect(0.8)
                Text("Deleting...")
                    .font(.caption)
                    .foregroundColor(theme.secondary)
            }
        } else {
            Button("Delete", action: onDelete)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .foregroundColor(theme.accent)
                .accessibilityIdentifier("downloadedSongDeleteButton")
        }
    }
}
