//
//  ServerSongCard.swift
//  Virgo
//
//  Server-song card for the wide-width grid layout. Reuses ServerSongInfoView
//  and ServerSongStatusView so the card and row stay in sync.
//

import SwiftUI
import SwiftData

struct ServerSongCard: View {
    let serverSong: ServerSong
    let isLoading: Bool
    let onDownload: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            ServerSongInfoView(serverSong: serverSong)
            RuleDivider()
            HStack {
                Spacer()
                ServerSongStatusView(
                    serverSong: serverSong,
                    isLoading: isLoading,
                    onDownload: onDownload
                )
            }
        }
        .padding(Spacing.md)
        .background(theme.raised)
        .cornerRadius(Radius.md)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .stroke(theme.rule, lineWidth: RuleWeight.hairline)
        )
        .accessibilityIdentifier("serverSongCard-\(serverSong.songId)")
    }
}
