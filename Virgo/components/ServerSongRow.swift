//
//  ServerSongRow.swift
//  Virgo
//
//  Created by Claude Code on 4/8/2025.
//

import SwiftUI
import SwiftData

// MARK: - Server Song Row
struct ServerSongRow: View {
    let serverSong: ServerSong
    let isLoading: Bool
    let onDownload: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(serverSong.title)
                    .font(.headline)
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text("by \(serverSong.artist)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                HStack {
                    Label("\(Int(serverSong.bpm)) BPM", systemImage: "metronome")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    // Display multiple difficulty levels or single level
                    if serverSong.charts.count > 1 {
                        let levels = serverSong.charts.map { String($0.level) }.joined(separator: ", ")
                        Label("Levels \(levels)", systemImage: "chart.bar")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else if let chart = serverSong.charts.first {
                        Label("Level \(chart.level)", systemImage: "chart.bar")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    // Display total size for multi-chart songs
                    let totalSize = serverSong.charts.reduce(0) { $0 + $1.size }
                    Text(formatFileSize(totalSize))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Display difficulty labels for multi-chart songs
                if serverSong.charts.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(serverSong.charts.indices, id: \.self) { index in
                                let chart = serverSong.charts[index]
                                Text("\(chart.difficultyLabel) (\(chart.level))")
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(difficultyColor(for: chart.difficulty))
                                    .foregroundColor(.white)
                                    .cornerRadius(4)
                            }
                        }
                        .padding(.horizontal, 1)
                    }
                }
            }

            Spacer()

            if serverSong.isDownloaded {
                VStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.green)

                    // Show downloaded content indicators
                    VStack(spacing: 2) {
                        HStack(spacing: 4) {
                            Image(systemName: "music.note")
                                .font(.caption2)
                                .foregroundColor(.green)
                            Text("Charts")
                                .font(.caption2)
                                .foregroundColor(.green)
                        }

                        if serverSong.hasBGM {
                            HStack(spacing: 4) {
                                Image(systemName: serverSong.bgmDownloaded ? "waveform" : "waveform.badge.exclamationmark")
                                    .font(.caption2)
                                    .foregroundColor(serverSong.bgmDownloaded ? .green : .orange)
                                Text("BGM")
                                    .font(.caption2)
                                    .foregroundColor(serverSong.bgmDownloaded ? .green : .orange)
                            }
                        }

                        if serverSong.hasPreview {
                            HStack(spacing: 4) {
                                Image(systemName: serverSong.previewDownloaded ? "play.circle" : "play.circle.badge.exclamationmark")
                                    .font(.caption2)
                                    .foregroundColor(serverSong.previewDownloaded ? .green : .orange)
                                Text("Preview")
                                    .font(.caption2)
                                    .foregroundColor(serverSong.previewDownloaded ? .green : .orange)
                            }
                        }
                    }
                }
            } else if isLoading {
                VStack(spacing: 4) {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Downloading...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // Show what's being downloaded
                    VStack(spacing: 2) {
                        HStack(spacing: 4) {
                            Image(systemName: "music.note")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text("Chart files")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        if serverSong.hasBGM {
                            HStack(spacing: 4) {
                                Image(systemName: "waveform")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text("Background music")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }

                        if serverSong.hasPreview {
                            HStack(spacing: 4) {
                                Image(systemName: "play.circle")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text("Preview audio")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            } else {
                Button("Download") {
                    onDownload()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isLoading)
            }
        }
        .padding()
        .background(Color.white.opacity(0.1))
        .cornerRadius(12)
    }

    private func formatFileSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    private func difficultyColor(for difficulty: String) -> Color {
        switch difficulty.lowercased() {
        case "easy":
            return .green
        case "medium":
            return .yellow
        case "hard":
            return .orange
        case "expert":
            return .red
        default:
            return .blue
        }
    }
}
