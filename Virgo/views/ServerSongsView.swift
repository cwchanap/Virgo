//
//  ServerSongsView.swift
//  Virgo
//
//  Created by Chan Wai Chan on 23/7/2025.
//

import SwiftUI
import SwiftData

// MARK: - Server Songs View
struct ServerSongsView: View {
    let serverSongs: [ServerSong]
    @ObservedObject var serverSongService: ServerSongService
    @Environment(\.theme) private var theme

    var body: some View {
        GeometryReader { proxy in
            layout(for: SongsLayoutMode.forWidth(proxy.size.width))
        }
    }

    @ViewBuilder
    private func layout(for mode: SongsLayoutMode) -> some View {
        switch mode {
        case .grid: serverGrid
        case .rows: serverList
        }
    }

    private var serverList: some View {
        List {
            if !serverSongs.isEmpty {
                ForEach(serverSongs, id: \.songId) { serverSong in
                    ServerSongRow(
                        serverSong: serverSong,
                        isLoading: serverSongService.isDownloading(serverSong),
                        onDownload: { downloadSong(serverSong) }
                    )
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            } else if serverSongService.isRefreshing {
                loadingRow.listRowBackground(Color.clear)
            } else {
                emptyState.listRowBackground(Color.clear)
            }
        }
        .listStyle(PlainListStyle())
        .scrollContentBackground(.hidden)
        .background(Color.clear)
    }

    private var serverGrid: some View {
        Group {
            if serverSongs.isEmpty {
                (serverSongService.isRefreshing ? AnyView(loadingRow) : AnyView(emptyState))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: SongsGrid.columns, spacing: Spacing.md) {
                        ForEach(serverSongs, id: \.songId) { serverSong in
                            ServerSongCard(
                                serverSong: serverSong,
                                isLoading: serverSongService.isDownloading(serverSong),
                                onDownload: { downloadSong(serverSong) }
                            )
                        }
                    }
                    .padding(Spacing.md)
                }
            }
        }
    }

    private var loadingRow: some View {
        HStack {
            ProgressView().scaleEffect(0.8)
            Text("Loading server songs...")
                .foregroundColor(theme.secondary)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "cloud")
                .font(.system(size: 50))
                .foregroundColor(theme.secondary)
            Text("No Server Songs")
                .font(.title2)
                .foregroundColor(theme.primary)
            Text("Tap the refresh button to load songs from the server")
                .font(.body)
                .foregroundColor(theme.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func downloadSong(_ serverSong: ServerSong) {
        Task {
            await serverSongService.downloadAndImportSong(serverSong)
        }
    }
}
