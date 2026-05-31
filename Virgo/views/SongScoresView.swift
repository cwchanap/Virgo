//
//  SongScoresView.swift
//  Virgo
//
//  Per-song list of charts, each linking to its scores.
//

import SwiftUI
import SwiftData

struct SongScoresView: View {
    let song: Song

    @State private var charts: [Chart]

    @MainActor
    init(song: Song) {
        self.song = song
        self._charts = State(initialValue: Self.sortedCharts(for: song))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            let displayCharts = charts.filter { SongRelationshipLoader.isModelAvailable($0) }

            if displayCharts.isEmpty {
                Text("No charts available")
                    .foregroundColor(.gray)
            } else {
                List(displayCharts, id: \.persistentModelID) { chart in
                    NavigationLink {
                        ChartScoresView(chart: chart)
                    } label: {
                        HStack {
                            DifficultyBadge(difficulty: chart.difficulty, size: .normal)
                            Spacer()
                            Text("Best \(chart.bestScore)")
                                .font(.system(.subheadline, design: .monospaced))
                                .foregroundColor(.purple)
                        }
                    }
                    .listRowBackground(Color.white.opacity(0.05))
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle(song.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        #endif
        .task { load() }
    }

    private func load() {
        charts = Self.sortedCharts(for: song)
    }

    private static func sortedCharts(for song: Song) -> [Chart] {
        guard SongRelationshipLoader.isModelAvailable(song) else { return [] }

        return song.charts
            .filter { SongRelationshipLoader.isModelAvailable($0) }
            .sorted { $0.difficulty.sortOrder < $1.difficulty.sortOrder }
    }
}
