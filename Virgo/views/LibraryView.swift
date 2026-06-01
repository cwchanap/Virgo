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
            song.genre == "DTX Import" &&
                !song.isDeleted &&
                !hiddenSongIDs.contains(song.persistentModelID)
        }
    }

    var body: some View {
        NavigationStack {
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
                                    HStack(spacing: 8) {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                        Text("Deleting...")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.trailing, 24)
                                } else {
                                    Button {
                                        let songID = song.persistentModelID
                                        Task { @MainActor in
                                            let success = await serverSongService.deleteLocalSong(song)
                                            if success {
                                                locallyDeletedSongIDs.insert(songID)
                                            }
                                        }
                                    } label: {
                                        Text("Delete")
                                            .font(.subheadline)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 4)
                                            .background(Color.red.opacity(0.2))
                                            .foregroundColor(.red)
                                            .cornerRadius(6)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("libraryDeleteButton")
                                    .accessibilityLabel("Delete \(song.title)")
                                    .padding(.trailing, 16)
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
            }
        }
        }
    }
}

struct SavedSongRow: View {
    let song: Song
    let isDeleting: Bool
    let onDelete: (() -> Void)?

    var showsDeleteButton: Bool {
        onDelete != nil && !isDeleting
    }

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
                    let bpmText = song.bpm.truncatingRemainder(dividingBy: 1) == 0 
                        ? String(format: "%.0f", song.bpm) 
                        : String(format: "%.2f", song.bpm)
                    Label("\(bpmText) BPM", systemImage: "metronome")
                    Label(song.duration, systemImage: "clock")
                    Label(song.genre, systemImage: "music.quarternote.3")
                }
                .font(.caption)
                .foregroundColor(.gray)
            }

            Spacer()

            // Available Difficulties
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
                        Button(action: onDelete) {
                            Text("Delete")
                        }
                        .accessibilityIdentifier("savedSongDeleteButton")
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .foregroundColor(.red)
                        .disabled(isDeleting)
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.white.opacity(0.1))
        .cornerRadius(12)
    }
}

#Preview {
    LibraryView(songs: [], serverSongService: ServerSongService())
        .modelContainer(for: Song.self, inMemory: true)
}
