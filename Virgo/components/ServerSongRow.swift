//
//  ServerSongRow.swift
//  Virgo
//
//  Created by Claude Code on 4/8/2025.
//

import SwiftUI
import SwiftData

// MARK: - Server Song Row (narrow layout)
struct ServerSongRow: View {
    let serverSong: ServerSong
    let isLoading: Bool
    let onDownload: () -> Void

    var body: some View {
        LedgerRow {
            HStack {
                ServerSongInfoView(serverSong: serverSong)
                Spacer()
                ServerSongStatusView(
                    serverSong: serverSong,
                    isLoading: isLoading,
                    onDownload: onDownload
                )
            }
        }
    }
}

// MARK: - Shared Info Section
struct ServerSongInfoView: View {
    let serverSong: ServerSong
    @Environment(\.theme) private var theme

    // Chart-derived display values. `serverSong.charts` is a SwiftData
    // relationship; faulting it during `body` evaluation is unsafe (see
    // SwiftDataRelationshipLoader / app architecture notes). We resolve the
    // relationship once off the render path via `.loadServerSongRelationships`
    // and render from these snapshots.
    @State private var totalSize: Int = 0
    @State private var levelText: String?
    @State private var difficultyChips: [DifficultyChip] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(serverSong.title)
                .font(AppType.headline)
                .foregroundColor(theme.primary)
                .lineLimit(1)
            Text("by \(serverSong.artist)")
                .font(.subheadline)
                .foregroundColor(theme.secondary)
                .lineLimit(1)
            metadataRow
            difficultyChipsRow
        }
        .loadServerSongRelationships(for: serverSong) { data in
            totalSize = data.totalSize
            levelText = data.levelText
            difficultyChips = data.difficultyChips
        }
    }

    private var metadataRow: some View {
        HStack {
            let bpmText = serverSong.bpm.truncatingRemainder(dividingBy: 1) == 0
                ? String(format: "%.0f", serverSong.bpm)
                : String(format: "%.2f", serverSong.bpm)
            Label("\(bpmText) BPM", systemImage: "metronome")
                .font(.plexMono(11))
                .foregroundColor(theme.secondary)
            levelLabel
            Spacer()
            Text(formatFileSize(totalSize))
                .font(.plexMono(11))
                .foregroundColor(theme.secondary)
        }
    }

    @ViewBuilder
    private var levelLabel: some View {
        if let levelText {
            Label(levelText, systemImage: "chart.bar")
                .font(.plexMono(11))
                .foregroundColor(theme.secondary)
        }
    }

    @ViewBuilder
    private var difficultyChipsRow: some View {
        if !difficultyChips.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(difficultyChips) { chip in
                        Text("\(chip.label) (\(chip.level))")
                            .font(.plexMono(10, weight: .medium))
                            .tracking(1)
                            .foregroundColor(theme.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(theme.rule, lineWidth: 1))
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }

    private func formatFileSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

// MARK: - Server Song Display Snapshot

/// Immutable, model-detached chip data resolved from the `ServerSong.charts`
/// relationship. Holding primitives (not `ServerChart` references) keeps the
/// render path free of SwiftData relationship faults.
struct DifficultyChip: Identifiable {
    let label: String
    let level: Int
    var id: String { "\(label)-\(level)" }
}

// MARK: - Shared Status Section
struct ServerSongStatusView: View {
    let serverSong: ServerSong
    let isLoading: Bool
    let onDownload: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        if serverSong.isDownloaded {
            downloadedIndicator
        } else if isLoading {
            loadingIndicator
        } else {
            Button("Download") { onDownload() }
                .buttonStyle(GhostButtonStyle())
                .controlSize(.small)
                .disabled(isLoading)
        }
    }

    private var downloadedIndicator: some View {
        VStack(spacing: 4) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundColor(theme.accent)
            VStack(spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "music.note")
                        .font(.caption2)
                        .foregroundColor(theme.accent)
                    Text("Charts")
                        .font(.caption2)
                        .foregroundColor(theme.accent)
                }
                if serverSong.hasBGM {
                    HStack(spacing: 4) {
                        Image(systemName: serverSong.bgmDownloaded ?
                              "waveform" : "waveform.badge.exclamationmark")
                            .font(.caption2)
                            .foregroundColor(serverSong.bgmDownloaded ? theme.accent : theme.secondary)
                        Text("BGM")
                            .font(.caption2)
                            .foregroundColor(serverSong.bgmDownloaded ? theme.accent : theme.secondary)
                    }
                }
                if serverSong.hasPreview {
                    HStack(spacing: 4) {
                        Image(systemName: serverSong.previewDownloaded ?
                              "play.circle" : "play.circle.badge.exclamationmark")
                            .font(.caption2)
                            .foregroundColor(serverSong.previewDownloaded ? theme.accent : theme.secondary)
                        Text("Preview")
                            .font(.caption2)
                            .foregroundColor(serverSong.previewDownloaded ? theme.accent : theme.secondary)
                    }
                }
            }
        }
    }

    private var loadingIndicator: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Downloading...")
                    .font(.caption)
                    .foregroundColor(theme.secondary)
            }
            VStack(spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "music.note")
                        .font(.caption2)
                        .foregroundColor(theme.secondary)
                    Text("Chart files")
                        .font(.caption2)
                        .foregroundColor(theme.secondary)
                }
                if serverSong.hasBGM {
                    HStack(spacing: 4) {
                        Image(systemName: "waveform")
                            .font(.caption2)
                            .foregroundColor(theme.secondary)
                        Text("Background music")
                            .font(.caption2)
                            .foregroundColor(theme.secondary)
                    }
                }
                if serverSong.hasPreview {
                    HStack(spacing: 4) {
                        Image(systemName: "play.circle")
                            .font(.caption2)
                            .foregroundColor(theme.secondary)
                        Text("Preview audio")
                            .font(.caption2)
                            .foregroundColor(theme.secondary)
                    }
                }
            }
        }
    }
}
