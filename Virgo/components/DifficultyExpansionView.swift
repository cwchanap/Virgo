//
//  DifficultyExpansionView.swift
//  Virgo
//
//  Created by Claude Code on 4/8/2025.
//

import SwiftUI
import SwiftData

@MainActor
struct ChartPracticeState: Hashable {
    let isPracticeEnabled: Bool
    let badgeTitle: String?
    let reason: String?
    let accessibilityExplanation: String

    init(chart: Chart) {
        let resolved = RhythmTimelineResolver().resolve(chart: chart)
        guard resolved.availability == .fatal else {
            isPracticeEnabled = true
            badgeTitle = nil
            reason = nil
            accessibilityExplanation = String(localized: "Practice available")
            return
        }

        isPracticeEnabled = false
        badgeTitle = String(localized: "Timing issue")
        reason = Self.reason(for: resolved.runtimeDiagnostics.first)
        accessibilityExplanation = String(localized: "Practice unavailable. \(reason ?? Self.fallbackReason)")
    }

    private static let fallbackReason = String(localized: "Unsupported chart timing")

    private static func reason(for diagnostic: PersistedRhythmDiagnostic?) -> String {
        guard let diagnostic else { return fallbackReason }
        let presentation = RhythmDiagnosticPresentation(code: diagnostic.code)
        if let measureIndex = diagnostic.sourceMeasureIndex {
            return String(
                localized: "\(presentation.title): measure \(measureIndex + 1) \(presentation.description)"
            )
        }
        return String(localized: "\(presentation.title): \(presentation.description)")
    }
}

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
    let practiceState: ChartPracticeState
    @State private var showingScores = false
    @Environment(\.theme) private var theme

    init(chart: Chart, onSelect: @escaping () -> Void) {
        self.chart = chart
        self.onSelect = onSelect
        self.practiceState = ChartPracticeState(chart: chart)
    }

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
        .disabled(!practiceState.isPracticeEnabled)
        .accessibilityIdentifier("chartDifficulty\(chart.difficulty.rawValue)")
        .accessibilityLabel(playButtonAccessibilityLabel)
        .accessibilityHint(practiceState.accessibilityExplanation)
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
                if let badgeTitle = practiceState.badgeTitle {
                    Text(badgeTitle)
                        .font(.plexMono(10))
                        .foregroundColor(theme.accent)
                        .accessibilityIdentifier("chartTimingWarning")
                }
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
                .stroke(theme.rule, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .opacity(practiceState.isPracticeEnabled ? 1 : 0.7)
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
        let score = chart.bestScore > 0 ? ", best \(chart.bestScore)" : ""
        guard !practiceState.isPracticeEnabled else { return base + score }
        return base + score + ". " + practiceState.accessibilityExplanation
    }

    func attemptPractice() {
        guard practiceState.isPracticeEnabled else { return }
        onSelect()
    }

    private func handleSelect() {
        attemptPractice()
    }
}
