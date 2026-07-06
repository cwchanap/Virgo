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
    @ObservedObject var audioPlaybackService: AudioPlaybackService
    let onChartSelect: (Chart) -> Void
    let onPlayTap: (Song) -> Void
    let onSaveTap: (Song) -> Void

    @State private var selectedSubTab = 0
    @Environment(\.theme) private var theme

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
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 10) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Songs")
                                .font(AppType.display)
                                .foregroundColor(theme.primary)
                            Text("\(selectedSubTab == 0 ? songs.count : filteredServerSongs.count) songs available")
                                .font(.plexMono(13))
                                .foregroundColor(theme.secondary)
                        }
                        Spacer()

                        if selectedSubTab == 1 {
                            Button {
                                Task {
                                    await serverSongService.refreshCatalog()
                                }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.title2)
                                    .foregroundColor(theme.primary)
                                    .rotationEffect(.degrees(serverSongService.isRefreshing ? 360 : 0))
                                    .animation(
                                        serverSongService.isRefreshing ?
                                            Animation.linear(duration: 1).repeatForever(autoreverses: false) :
                                            .default,
                                        value: serverSongService.isRefreshing
                                    )
                            }
                            .disabled(serverSongService.isRefreshing)
                            .accessibilityIdentifier("refreshServerSongsButton")
                            .accessibilityLabel("Refresh server songs")
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top)

                    // Search Bar — underlined input, no rounded border
                    VStack(spacing: 0) {
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(theme.secondary)
                                .font(.system(size: 16))

                            TextField("Search songs or artists...", text: $searchText)
                                .font(.system(size: 16))
                                .foregroundColor(theme.primary)
                                .accessibilityIdentifier("searchField")

                            if !searchText.isEmpty {
                                Button {
                                    searchText = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(theme.secondary)
                                        .font(.system(size: 16))
                                }
                                .accessibilityIdentifier("clearSearchButton")
                            }
                        }
                        .padding(.vertical, 10)

                        RuleDivider()
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
                .tint(theme.accent)
                .padding(.horizontal)
                .padding(.bottom, 16)

                // Content based on selected sub-tab
                if selectedSubTab == 0 {
                    DownloadedSongsView(
                        songs: songs,
                        serverSongService: serverSongService,
                        currentlyPlaying: $currentlyPlaying,
                        expandedSongId: $expandedSongId,
                        audioPlaybackService: audioPlaybackService,
                        onChartSelect: onChartSelect,
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
        .appSurface()
        .alert("Error", isPresented: Binding(
            get: { serverSongService.errorMessage != nil },
            set: { if !$0 { serverSongService.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(serverSongService.errorMessage ?? "")
        }
        .alert("Imported with warnings", isPresented: Binding(
            get: { serverSongService.warningMessage != nil },
            set: { if !$0 { serverSongService.warningMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(serverSongService.warningMessage ?? "")
        }
    }
}
