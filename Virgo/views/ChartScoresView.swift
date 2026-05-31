//
//  ChartScoresView.swift
//  Virgo
//
//  Reusable per-chart scores: all-time best + recent attempts.
//

import SwiftUI
import SwiftData

struct ChartScoresView: View {
    let chart: Chart

    @Environment(\.modelContext) private var modelContext
    @State private var attempts: [ScoreAttemptSummary] = []
    @State private var bestScore: Int

    init(chart: Chart) {
        self.chart = chart
        self._bestScore = State(initialValue: chart.bestScore)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 16) {
                bestScoreHeader

                if attempts.isEmpty {
                    emptyState
                } else {
                    attemptsList
                }
            }
            .padding(.top, 16)
        }
        .navigationTitle("Scores")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        #endif
        .task { load() }
    }

    private var bestScoreHeader: some View {
        VStack(spacing: 4) {
            Text("\(bestScore)")
                .font(.system(size: 40, weight: .bold, design: .monospaced))
                .foregroundColor(.purple)
            Text("BEST SCORE")
                .font(.caption)
                .foregroundColor(.gray)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 48))
                .foregroundColor(.white.opacity(0.3))
            Text("No attempts yet")
                .font(.headline)
                .foregroundColor(.white)
            Text("Play this chart to record a score")
                .font(.subheadline)
                .foregroundColor(.gray)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var attemptsList: some View {
        List(attempts) { attempt in
            ScoreAttemptRow(attempt: attempt)
                .listRowBackground(Color.white.opacity(0.05))
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func load() {
        let service = ScorePersistenceService(modelContext: modelContext)
        bestScore = service.bestScore(for: chart)
        attempts = service.recentAttempts(for: chart)
    }
}

struct ScoreAttemptRow: View {
    let attempt: ScoreAttemptSummary

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(attempt.score)")
                    .font(.system(.headline, design: .monospaced))
                    .foregroundColor(.white)
                Text(Self.relativeFormatter.localizedString(for: attempt.playedAt, relativeTo: Date()))
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(attempt.maxCombo)x · \(Int(attempt.accuracy.rounded()))%")
                    .font(.caption)
                    .foregroundColor(.cyan)
                Text("\(Int((attempt.speedMultiplier * 100).rounded()))% speed")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        ChartScoresView(chart: Chart(difficulty: .medium))
    }
    .modelContainer(
        for: [Song.self, Chart.self, Note.self, ServerSong.self, ServerChart.self, ScoreRecord.self],
        inMemory: true
    )
}
