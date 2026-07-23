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
    let isResolved: Bool
    let isPracticeEnabled: Bool
    let badgeTitle: String?
    let reason: String?
    let accessibilityExplanation: String

    static let loading = ChartPracticeState(
        isResolved: false,
        isPracticeEnabled: false,
        badgeTitle: nil,
        reason: nil,
        accessibilityExplanation: String(localized: "Checking chart timing")
    )

    init(chart: Chart) {
        let resolved = RhythmTimelineResolver().resolve(chart: chart)
        guard let fatalDiagnostic = Self.fatalDiagnostic(
            for: resolved,
            bpm: chart.bpm
        ) else {
            self = Self.availableState
            return
        }

        let additionalFatalCount = Self.additionalFatalCount(
            in: resolved.runtimeDiagnostics
        )
        self = Self.unavailableState(
            diagnostic: fatalDiagnostic,
            additionalFatalCount: additionalFatalCount
        )
    }

    static func resolve(chart: Chart) -> ChartPracticeState {
        ChartPracticeState(chart: chart)
    }

    /// Produces an initializer-safe state without traversing SwiftData relationships.
    /// Metadata-fatal charts can render their error immediately; all other charts
    /// remain disabled until ``ChartPracticeStateLoader`` resolves them from a task.
    static func initial(chart: Chart) -> ChartPracticeState {
        switch chart.rhythmMetadataState {
        case let .invalid(code):
            return unavailableState(diagnostic: makeFatalDiagnostic(code: code))
        case let .valid(metadata) where metadata.timingStatus == .fatal:
            let fatalDiagnostics = metadata.diagnostics.filter { $0.severity == .timingFatal }
            let diagnostic = fatalDiagnostics.first ?? metadata.diagnostics.first
            let additionalFatalCount = max(0, fatalDiagnostics.count - 1)
            return unavailableState(
                diagnostic: diagnostic,
                additionalFatalCount: additionalFatalCount
            )
        case .missing, .valid:
            return .loading
        }
    }

    private static let fallbackReason = String(localized: "Unsupported chart timing")

    private static let availableState = ChartPracticeState(
        isResolved: true,
        isPracticeEnabled: true,
        badgeTitle: nil,
        reason: nil,
        accessibilityExplanation: String(localized: "Practice available")
    )

    private init(
        isResolved: Bool,
        isPracticeEnabled: Bool,
        badgeTitle: String?,
        reason: String?,
        accessibilityExplanation: String
    ) {
        self.isResolved = isResolved
        self.isPracticeEnabled = isPracticeEnabled
        self.badgeTitle = badgeTitle
        self.reason = reason
        self.accessibilityExplanation = accessibilityExplanation
    }

    private static func unavailableState(
        diagnostic: PersistedRhythmDiagnostic?,
        additionalFatalCount: Int = 0
    ) -> ChartPracticeState {
        var reason = reason(for: diagnostic)
        if additionalFatalCount > 0 {
            // Surface the count of further timing-fatal diagnostics so the badge
            // does not silently drop multi-error charts to a single reason.
            let issueSuffix = additionalFatalCount == 1 ? "" : "s"
            reason = String(
                localized: "\(reason) (+\(additionalFatalCount) more timing issue\(issueSuffix))"
            )
        }
        return ChartPracticeState(
            isResolved: true,
            isPracticeEnabled: false,
            badgeTitle: String(localized: "Timing issue"),
            reason: reason,
            accessibilityExplanation: String(localized: "Practice unavailable. \(reason)")
        )
    }

    /// Count of timing-fatal diagnostics beyond the primary one already surfaced.
    /// Only the `.fatal` availability path carries multiple runtime diagnostics;
    /// the synthesized single-diagnostic paths (`makeFatalDiagnostic`) pass 0.
    private static func additionalFatalCount(
        in diagnostics: [PersistedRhythmDiagnostic]
    ) -> Int {
        let fatalCount = diagnostics.filter { $0.severity == .timingFatal }.count
        return max(0, fatalCount - 1)
    }

    private static func fatalDiagnostic(
        for resolved: ResolvedChartRhythm,
        bpm: Double
    ) -> PersistedRhythmDiagnostic? {
        switch resolved.availability {
        case .fatal:
            return resolved.runtimeDiagnostics.first { $0.severity == .timingFatal }
                ?? resolved.runtimeDiagnostics.first
        case .legacy:
            return nil
        case .valid:
            break
        }
        guard let timeline = resolved.timeline else {
            return makeFatalDiagnostic(code: .inconsistentPersistedTiming)
        }
        do {
            _ = try RhythmMetronomeSchedule.preflight(timeline: timeline, bpm: bpm)
            return nil
        } catch let error as RhythmTimelineBuildError {
            return makeFatalDiagnostic(code: error.diagnosticCode)
        } catch {
            return makeFatalDiagnostic(code: .inconsistentPersistedTiming)
        }
    }

    private static func makeFatalDiagnostic(
        code: RhythmDiagnosticCode
    ) -> PersistedRhythmDiagnostic {
        do {
            return try PersistedRhythmDiagnostic(code: code, severity: .timingFatal)
        } catch {
            preconditionFailure("Timing-fatal rhythm code has invalid severity: \(code)")
        }
    }

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
@MainActor
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
@MainActor
struct ChartSelectionCard: View {
    let chart: Chart
    let onSelect: () -> Void
    private let initialPracticeState: ChartPracticeState
    @StateObject private var practiceStateLoader: ChartPracticeStateLoader
    @State private var showingScores = false
    @Environment(\.theme) private var theme

    var practiceState: ChartPracticeState {
        initialPracticeState.isResolved ? initialPracticeState : practiceStateLoader.state
    }

    init(chart: Chart, onSelect: @escaping () -> Void) {
        let initialState = ChartPracticeState.initial(chart: chart)
        self.chart = chart
        self.onSelect = onSelect
        self.initialPracticeState = initialState
        self._practiceStateLoader = StateObject(
            wrappedValue: ChartPracticeStateLoader(initialState: initialState)
        )
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
        .task(id: chart.persistentModelID) {
            await practiceStateLoader.load(chart: chart)
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
