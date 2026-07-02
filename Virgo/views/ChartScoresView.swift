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
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @State private var attempts: [ScoreAttemptSummary]
    @State private var bestScore: Int

    @MainActor
    init(chart: Chart) {
        self.chart = chart
        if SongRelationshipLoader.isModelAvailable(chart) {
            self._bestScore = State(initialValue: chart.bestScore)
            self._attempts = State(initialValue: Self.summaries(from: chart.scoreRecords))
        } else {
            self._bestScore = State(initialValue: 0)
            self._attempts = State(initialValue: [])
        }
    }

    var body: some View {
        ZStack {
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
        .appSurface()
        .navigationTitle("Scores")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(colorScheme == .dark ? .dark : .light, for: .navigationBar)
        #endif
        .task { load() }
    }

    private var bestScoreHeader: some View {
        VStack(spacing: 4) {
            Text("\(bestScore)")
                .font(.plexMono(40, weight: .bold))
                .foregroundColor(theme.accent)
            Text("BEST SCORE")
                .font(.plexMono(11, weight: .medium))
                .tracking(1.5)
                .foregroundColor(theme.secondary)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 48))
                .foregroundColor(theme.rule)
            Text("No attempts yet")
                .font(AppType.headline)
                .foregroundColor(theme.primary)
            Text("Play this chart to record a score")
                .font(.subheadline)
                .foregroundColor(theme.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var attemptsList: some View {
        List(attempts) { attempt in
            ScoreAttemptRow(attempt: attempt)
                .listRowBackground(Color.clear)
                .listRowSeparator(.visible)
                .listRowSeparatorTint(theme.rule)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func load() {
        guard SongRelationshipLoader.isModelAvailable(chart) else {
            bestScore = 0
            attempts = []
            return
        }

        let service = ScorePersistenceService(modelContext: modelContext)
        bestScore = service.bestScore(for: chart)
        attempts = service.recentAttempts(for: chart)
    }

    private static func summaries(from records: [ScoreRecord]) -> [ScoreAttemptSummary] {
        records
            .filter { !$0.isDeleted }
            .sorted { $0.playedAt > $1.playedAt }
            .prefix(ScorePersistenceService.maxRecentAttempts)
            .map { record in
                ScoreAttemptSummary(
                    id: record.persistentModelID,
                    score: record.score,
                    maxCombo: record.maxCombo,
                    accuracy: record.accuracy,
                    speedMultiplier: record.speedMultiplier,
                    playedAt: record.playedAt
                )
            }
    }
}

struct ScoreAttemptRow: View {
    let attempt: ScoreAttemptSummary
    @Environment(\.theme) private var theme

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(attempt.score)")
                    .font(.plexMono(16, weight: .semibold))
                    .foregroundColor(theme.primary)
                Text(Self.relativeFormatter.localizedString(for: attempt.playedAt, relativeTo: Date()))
                    .font(.caption2)
                    .foregroundColor(theme.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(attempt.maxCombo)x · \(Int(attempt.accuracy.rounded()))%")
                    .font(.plexMono(11))
                    .foregroundColor(theme.accent)
                Text("\(Int((attempt.speedMultiplier * 100).rounded()))% speed")
                    .font(.plexMono(10))
                    .foregroundColor(theme.secondary)
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
