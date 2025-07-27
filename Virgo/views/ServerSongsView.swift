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
    
    var body: some View {
        List {
            if !serverSongs.isEmpty {
                ForEach(serverSongs, id: \.songId) { serverSong in
                    ServerSongRow(
                        serverSong: serverSong,
                        isLoading: serverSongService.isDownloading(serverSong),
                        onDownload: {
                            Task {
                                await serverSongService.downloadAndImportSong(serverSong)
                            }
                        }
                    )
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            } else if serverSongService.isRefreshing {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading server songs...")
                        .foregroundColor(.secondary)
                }
                .listRowBackground(Color.clear)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "cloud")
                        .font(.system(size: 50))
                        .foregroundColor(.secondary)
                    
                    Text("No Server Songs")
                        .font(.title2)
                        .foregroundColor(.white)
                    
                    Text("Tap the refresh button to load songs from the server")
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
