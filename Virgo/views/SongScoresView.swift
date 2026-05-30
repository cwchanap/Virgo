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

    @Environment(\.modelContext) private var modelContext
    @State private var charts: [Chart] = []
    @State private var bestScores: [PersistentIdentifier: Int] = [:]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if charts.isEmpty {
                Text("No charts available")
                    .foregroundColor(.gray)
            } else {
                List(charts, id: \.persistentModelID) { chart in
                    NavigationLink {
                        ChartScoresView(chart: chart)
                    } label: {
                        HStack {
                            DifficultyBadge(difficulty: chart.difficulty, size: .normal)
                            Spacer()
                            Text("Best \(bestScores[chart.persistentModelID] ?? 0)")
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
        let service = ScorePersistenceService(modelContext: modelContext)
        let sorted = song.charts.sorted { $0.difficulty.sortOrder < $1.difficulty.sortOrder }
        charts = sorted
        bestScores = Dictionary(
            uniqueKeysWithValues: sorted.map { ($0.persistentModelID, service.bestScore(for: $0)) }
        )
    }
}
