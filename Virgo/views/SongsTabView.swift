//
//  SongsTabView.swift
//  Virgo
//
//  Created by Chan Wai Chan on 23/7/2025.
//

import SwiftUI
import SwiftData

// MARK: - Songs Tab with Sub-tabs
struct SongsTabView: View {
    let allSongs: [Song]
    let serverSongs: [ServerSong]
    @ObservedObject var serverSongService: ServerSongService
    @Binding var searchText: String
    @Binding var currentlyPlaying: PersistentIdentifier?
    @Binding var expandedSongId: PersistentIdentifier?
    @Binding var selectedChart: Chart?
    @Binding var navigateToGameplay: Bool
    @ObservedObject var audioPlaybackService: AudioPlaybackService
    let onPlayTap: (Song) -> Void
    let onSaveTap: (Song) -> Void

    @State private var selectedSubTab = 0

    // Computed property for filtered songs
    var songs: [Song] {
        if searchText.isEmpty {
            return allSongs
        } else {
            return allSongs.filter { song in
                song.title.localizedCaseInsensitiveContains(searchText) ||
                    song.artist.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    // Computed property for filtered server songs
    var filteredServerSongs: [ServerSong] {
        if searchText.isEmpty {
            return serverSongs
        } else {
            return serverSongs.filter { song in
                song.title.localizedCaseInsensitiveContains(searchText) ||
                    song.artist.localizedCaseInsensitiveContains(searchText)
            }
        }
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
                            Text("Songs")
                                .font(.largeTitle)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            Text("\(selectedSubTab == 0 ? songs.count : filteredServerSongs.count) songs available")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                        Spacer()

                        if selectedSubTab == 1 {
                            Button {
                                Task {
                                    await serverSongService.refreshServerSongs()
                                }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.title2)
                                    .foregroundColor(.white)
                                    .rotationEffect(.degrees(serverSongService.isRefreshing ? 360 : 0))
                                    .animation(
                                        serverSongService.isRefreshing ?
                                            Animation.linear(duration: 1).repeatForever(autoreverses: false) :
                                            .default,
                                        value: serverSongService.isRefreshing
                                    )
                            }
                            .disabled(serverSongService.isRefreshing)
                            .onLongPressGesture(minimumDuration: 1.0) {
                                Task {
                                    await serverSongService.forceRefreshServerSongs()
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top)

                    // Search Bar
                    HStack {
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.gray)
                                .font(.system(size: 16))

                            TextField("Search songs or artists...", text: $searchText)
                                .font(.system(size: 16))
                                .foregroundColor(.white)
                                .accessibilityIdentifier("searchField")

                            if !searchText.isEmpty {
                                Button {
                                    searchText = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.gray)
                                        .font(.system(size: 16))
                                }
                                .accessibilityIdentifier("clearSearchButton")
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .padding(.horizontal)
                }
                .padding(.top, 20)
                .padding(.bottom, 16)

                // Sub-tab Picker
                Picker("Song Source", selection: $selectedSubTab) {
                    Label("Downloaded", systemImage: "arrow.down.circle").tag(0)
                    Label("Server", systemImage: "cloud").tag(1)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)
                .padding(.bottom, 16)

                // Content based on selected sub-tab
                if selectedSubTab == 0 {
                    DownloadedSongsView(
                        songs: songs,
                        serverSongService: serverSongService,
                        currentlyPlaying: $currentlyPlaying,
                        expandedSongId: $expandedSongId,
                        selectedChart: $selectedChart,
                        navigateToGameplay: $navigateToGameplay,
                        audioPlaybackService: audioPlaybackService,
                        onPlayTap: onPlayTap,
                        onSaveTap: onSaveTap
                    )
                } else {
                    ServerSongsView(
                        serverSongs: filteredServerSongs,
                        serverSongService: serverSongService
                    )
                }
            }
        }
    }
}
