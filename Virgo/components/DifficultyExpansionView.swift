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

    var body: some View {
        VStack(spacing: 12) {
            // Expansion header
            HStack {
                Text("Select Difficulty")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
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
        .background(Color.white.opacity(0.1))
        .cornerRadius(12)
        .padding(.horizontal, 4)
    }
}

// MARK: - Chart Selection Card
struct ChartSelectionCard: View {
    let chart: Chart
    let onSelect: () -> Void
    @State private var showingScores = false

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
            DifficultyBadge(difficulty: chart.difficulty, size: .normal)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(chart.notesCount) notes")
                    .font(.caption)
                    .foregroundColor(.gray)
                Text("Level \(chart.level)")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }

            Spacer()

            if chart.bestScore > 0 {
                Text("\(chart.bestScore)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.purple)
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.white.opacity(0.1))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
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
                .foregroundColor(.cyan)
                .frame(width: 36, height: 36)
                .background(Color.white.opacity(0.1))
                .cornerRadius(8)
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
