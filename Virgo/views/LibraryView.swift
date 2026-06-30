//
//  LibraryView.swift
//  Virgo
//
//  Created by Claude Code on 27/7/2025.
//

import SwiftUI
import SwiftData

struct LibraryView: View {
    let songs: [Song]
    @ObservedObject var serverSongService: ServerSongService
    @State private var locallyDeletedSongIDs: Set<PersistentIdentifier> = []
    @Environment(\.theme) private var theme

    static func rowViewID(for song: Song) -> String {
        let stableSongID = PersistentIdentifierPersistenceKey.canonicalKey(
            for: song.persistentModelID,
            logPrefix: "LibraryView"
        )
        return "library-song-row-\(stableSongID)"
    }

    var downloadedSongs: [Song] {
        Self.downloadedSongs(from: songs, excluding: locallyDeletedSongIDs)
    }

    static func downloadedSongs(
        from songs: [Song],
        excluding hiddenSongIDs: Set<PersistentIdentifier> = []
    ) -> [Song] {
        songs.filter { song in
            song.isServerImported &&
                !song.isDeleted &&
                !hiddenSongIDs.contains(song.persistentModelID)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                VStack(spacing: 0) {
                    headerSection
                    if downloadedSongs.isEmpty {
                        emptyState
                    } else {
                        songsList
                    }
                }
            }
            .appSurface()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Downloaded Songs")
                        .font(AppType.display)
                        .foregroundColor(theme.primary)
                    Text("\(downloadedSongs.count) songs downloaded")
                        .font(.plexMono(13))
                        .foregroundColor(theme.secondary)
                }
                Spacer()
                Image(systemName: "arrow.down.circle.fill")
                    .font(.title2)
                    .foregroundColor(theme.secondary)
            }
            .padding(.horizontal)
            .padding(.top)
        }
        .padding(.top, 20)
        .padding(.bottom, 16)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 64))
                .foregroundColor(theme.rule)

            VStack(spacing: 8) {
                Text("No Downloaded Songs")
                    .font(AppType.headline)
                    .foregroundColor(theme.primary)

                Text("Download songs from the server to see them here")
                    .font(.body)
                    .foregroundColor(theme.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Songs List

    private var songsList: some View {
        List {
            ForEach(downloadedSongs, id: \.id) { song in
                ZStack(alignment: .trailing) {
                    NavigationLink {
                        SongScoresView(song: song)
                    } label: {
                        SavedSongRow(
                            song: song,
                            isDeleting: serverSongService.isDeleting(song),
                            onDelete: nil
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(Self.rowViewID(for: song))
                    .accessibilityLabel("\(song.title), \(song.artist)")

                    // Delete button sits outside the NavigationLink
                    // so taps don't trigger both navigation and deletion.
                    if serverSongService.isDeleting(song) {
                        deletingIndicator
                    } else {
                        deleteButton(for: song)
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(PlainListStyle())
        .scrollContentBackground(.hidden)
        .background(Color.clear)
    }

    private var deletingIndicator: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.8)
            Text("Deleting...")
                .font(.caption)
                .foregroundColor(theme.secondary)
        }
        .padding(.trailing, 24)
    }

    private func deleteButton(for song: Song) -> some View {
        Button {
            let songID = song.persistentModelID
            locallyDeletedSongIDs.insert(songID)
            Task { @MainActor in
                let success = await serverSongService.deleteLocalSong(song)
                if !success {
                    locallyDeletedSongIDs.remove(songID)
                }
            }
        } label: {
            Text("Delete")
                .font(.subheadline)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .foregroundColor(theme.accent)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(theme.accent.opacity(0.4), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("libraryDeleteButton")
        .accessibilityLabel("Delete \(song.title)")
        .padding(.trailing, 16)
    }
}

struct SavedSongRow: View {
    let song: Song
    let isDeleting: Bool
    let onDelete: (() -> Void)?
    @Environment(\.theme) private var theme

    var showsDeleteButton: Bool {
        onDelete != nil && !isDeleting
    }

    var body: some View {
        LedgerRow {
            HStack(spacing: 12) {
                songInfoSection
                Spacer()
                trailingSection
            }
        }
    }

    // MARK: - Song Info

    private var songInfoSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(song.title)
                .font(AppType.headline)
                .lineLimit(1)
                .foregroundColor(theme.primary)

            Text(song.artist)
                .font(.subheadline)
                .foregroundColor(theme.secondary)
                .lineLimit(1)

            HStack(spacing: 12) {
                let bpmText = song.bpm.truncatingRemainder(dividingBy: 1) == 0
                    ? String(format: "%.0f", song.bpm)
                    : String(format: "%.2f", song.bpm)
                Label("\(bpmText) BPM", systemImage: "metronome")
                Label(song.duration, systemImage: "clock")
                Label(song.genre, systemImage: "music.quarternote.3")
            }
            .font(.plexMono(11))
            .foregroundColor(theme.secondary)
        }
    }

    // MARK: - Trailing Section

    private var trailingSection: some View {
        VStack(spacing: 8) {
            HStack(spacing: 2) {
                ForEach(song.availableDifficulties, id: \.self) { difficulty in
                    DifficultyPips(difficulty: difficulty, showLabel: false)
                }
            }

            if let onDelete = onDelete {
                if isDeleting {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Deleting...")
                            .font(.caption)
                            .foregroundColor(theme.secondary)
                    }
                } else {
                    Button(action: onDelete) {
                        Text("Delete")
                    }
                    .accessibilityIdentifier("savedSongDeleteButton")
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .foregroundColor(theme.accent)
                    .disabled(isDeleting)
                }
            }
        }
    }
}

#Preview {
    LibraryView(songs: [], serverSongService: ServerSongService())
        .modelContainer(for: Song.self, inMemory: true)
}
