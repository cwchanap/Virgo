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

    @State private var charts: [Chart] = []
    @Environment(\.theme) private var theme

    @MainActor
    init(song: Song, initialCharts: [Chart] = []) {
        self.song = song
        self._charts = State(initialValue: Self.sortedCharts(initialCharts))
    }

    var body: some View {
        ZStack {
            let displayCharts = charts.filter { SongRelationshipLoader.isModelAvailable($0) }

            if displayCharts.isEmpty {
                Text("No charts available")
                    .foregroundColor(theme.secondary)
            } else {
                List(displayCharts, id: \.persistentModelID) { chart in
                    NavigationLink {
                        ChartScoresView(chart: chart)
                    } label: {
                        HStack {
                            DifficultyPips(difficulty: chart.difficulty)
                            Spacer()
                            Text("Best \(chart.bestScore)")
                                .font(.plexMono(14))
                                .foregroundColor(theme.accent)
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.visible)
                    .listRowSeparatorTint(theme.rule)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .appSurface()
        .navigationTitle(song.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.light, for: .navigationBar)
        #endif
        .task {
            guard charts.isEmpty else { return }
            loadCharts()
        }
    }

    private func loadCharts() {
        let data = SongRelationshipLoader.relationshipData(for: song)
        charts = Self.sortedCharts(data.charts)
    }

    private static func sortedCharts(_ charts: [Chart]) -> [Chart] {
        charts.sorted { $0.difficulty.sortOrder < $1.difficulty.sortOrder }
    }
}
