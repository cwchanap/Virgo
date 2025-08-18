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

#Preview {
    LibraryView(songs: [], serverSongService: ServerSongService())
        .modelContainer(for: Song.self, inMemory: true)
}
