//
//  DifficultyExpansionView.swift
//  Virgo
//
//  Created by Claude Code on 4/8/2025.
//

import SwiftUI
import SwiftData

// MARK: - Difficulty Expansion View
struct DifficultyExpansionView: View {
    let charts: [Chart]
    let onChartSelect: (Chart) -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 12) {
            // Expansion header
            HStack {
                Text("Select Difficulty")
                    .font(AppType.label)
                    .foregroundColor(theme.primary)
                Spacer()
            }
            .padding(.horizontal, 16)

            // Difficulty cards in rows
            VStack(spacing: 6) {
                ForEach(charts.sorted { $0.difficulty.sortOrder < $1.difficulty.sortOrder }, id: \.id) { chart in
                    ChartSelectionCard(chart: chart) {
                        onChartSelect(chart)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 12)
        .background(theme.raised)
        .cornerRadius(Radius.md)
        .padding(.horizontal, 4)
    }
}

// MARK: - Chart Selection Card
struct ChartSelectionCard: View {
    let chart: Chart
    let onSelect: () -> Void
    @State private var showingScores = false
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            playButton
            scoresButton
        }
        .sheet(isPresented: $showingScores) {
            NavigationStack {
                ChartScoresView(chart: chart)
            }
        }
    }

    private var playButton: some View {
        Button(action: handleSelect) {
            playButtonContent
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityIdentifier("chartDifficulty\(chart.difficulty.rawValue)")
        .accessibilityLabel(playButtonAccessibilityLabel)
    }

    private var playButtonContent: some View {
        HStack(spacing: 12) {
            DifficultyPips(difficulty: chart.difficulty)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(chart.notesCount) notes")
                    .font(.plexMono(11))
                    .foregroundColor(theme.secondary)
                Text("Level \(chart.level)")
                    .font(.plexMono(11))
                    .foregroundColor(theme.secondary)
            }

            Spacer()

            if chart.bestScore > 0 {
                Text("\(chart.bestScore)")
                    .font(.plexMono(11))
                    .foregroundColor(theme.accent)
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(theme.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(theme.raised)
        .cornerRadius(Radius.sm)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm)
                .stroke(chart.difficulty.color.opacity(0.4), lineWidth: 1)
        )
        .contentShape(Rectangle())
    }

    private var scoresButton: some View {
        Button {
            showingScores = true
        } label: {
            Image(systemName: "list.bullet.rectangle")
                .font(.body)
                .foregroundColor(theme.secondary)
                .frame(width: 36, height: 36)
                .background(theme.raised)
                .cornerRadius(Radius.sm)
                .accessibilityHidden(true)
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier(scoreButtonIdentifier)
        .accessibilityLabel(scoreButtonAccessibilityLabel)
        .accessibilityAddTraits(.isButton)
    }

    private var scoreButtonIdentifier: String {
        "chartScores\(chart.difficulty.rawValue)"
    }

    private var scoreButtonAccessibilityLabel: String {
        "View scores for \(chart.difficulty.rawValue) difficulty"
    }

    private var playButtonAccessibilityLabel: String {
        let base = "\(chart.difficulty.rawValue) difficulty, \(chart.notesCount) notes, Level \(chart.level)"
        guard chart.bestScore > 0 else { return base }
        return base + ", best \(chart.bestScore)"
    }

    private func handleSelect() {
        onSelect()
    }
}
