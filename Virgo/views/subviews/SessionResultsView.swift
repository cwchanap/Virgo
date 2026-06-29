//
//  SessionResultsView.swift
//  Virgo
//
//  End-of-session results sheet shown after playback completes.
//

import SwiftUI

struct SessionResultsView: View {
    let highScore: Int
    /// The save outcome from `ScorePersistenceService.recordAttempt`.
    /// `.newBest` shows the NEW HIGH SCORE badge; `.saveFailed` shows a non-blocking
    /// warning that the score was not persisted.
    let recordResult: ScorePersistenceService.RecordResult
    let scoreSnapshot: LiveScoreSnapshot
    let onPlayAgain: () -> Void
    let onDone: () -> Void

    private var isNewHighScore: Bool { scoreSnapshot.score > 0 && recordResult == .newBest }

    var body: some View {
        NavigationStack {
            ZStack {
                ScrollView {
                    VStack(spacing: 20) {
                        // New high score badge
                        if isNewHighScore {
                            Text("NEW HIGH SCORE!")
                                .font(.system(.caption, design: .rounded).weight(.bold))
                                .foregroundColor(Palette.stage)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Palette.vermillion)
                                .clipShape(Capsule())
                        }

                        // Save-failure warning — non-blocking so the user can still see their score
                        if recordResult == .saveFailed {
                            Text("Score not saved")
                                .font(.system(.caption, design: .rounded).weight(.semibold))
                                .foregroundColor(Palette.chalk)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Palette.vermillion.opacity(0.8))
                                .clipShape(Capsule())
                        }

                        // Accuracy ring + Score
                        HStack(spacing: 32) {
                            AccuracyCircleView(percentage: scoreSnapshot.hitAccuracy)

                            VStack(spacing: 4) {
                                Text("\(scoreSnapshot.score)")
                                    .font(AppType.numericLarge)
                                    .foregroundColor(Palette.chalk)
                                Text("SCORE")
                                    .font(.plexMono(10, weight: .medium))
                                    .tracking(1.5)
                                    .foregroundColor(Palette.chalkMuted)
                            }
                        }

                        // Hit breakdown chart
                        AccuracyBreakdownChart(
                            perfectCount: scoreSnapshot.perfectCount,
                            greatCount: scoreSnapshot.greatCount,
                            goodCount: scoreSnapshot.goodCount,
                            missCount: scoreSnapshot.missCount
                        )
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(Palette.stageRaised)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)

                        // Timing deviation
                        TimingDeviationView(
                            averageDeviation: scoreSnapshot.averageTimingDeviation,
                            earlyPercentage: scoreSnapshot.earlyPercentage,
                            latePercentage: scoreSnapshot.latePercentage,
                            tendency: scoreSnapshot.timingTendency
                        )
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(Palette.stageRaised)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)

                        // Max combo + best score
                        statsGrid

                        // Actions
                        VStack(spacing: 12) {
                            Button(action: onPlayAgain) {
                                Text("Play Again")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(VermillionButtonStyle())

                            Button(action: onDone) {
                                Text("Done")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(GhostButtonStyle())
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 24)
                    }
                    .padding(.top, 24)
                }
            }
            .surface(.ink)
            .navigationTitle("Results")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            #endif
        }
    }

    private var statsGrid: some View {
        HStack(spacing: 0) {
            statCell(label: "MAX COMBO", value: "\(scoreSnapshot.maxCombo)x")
            statCell(label: "QUALITY", value: scoreSnapshot.timingQualityPercentText)
            statCell(label: "BEST SCORE", value: "\(highScore)")
        }
        .padding(.horizontal)
    }

    private func statCell(label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.plexMono(20, weight: .semibold))
                .foregroundColor(Palette.chalk)
            Text(label)
                .font(.plexMono(10, weight: .medium))
                .tracking(1)
                .foregroundColor(Palette.chalkMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Palette.stageRaised)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(4)
    }
}

#Preview {
    var engine = ScoreEngine()
    for _ in 0..<15 { engine.processHit(accuracy: .perfect, timingError: -8.0) }
    for _ in 0..<5 { engine.processHit(accuracy: .great, timingError: 15.0) }
    for _ in 0..<2 { engine.processHit(accuracy: .good, timingError: 45.0) }
    for _ in 0..<3 { engine.processHit(accuracy: .miss) }

    return SessionResultsView(
        highScore: 2450,
        recordResult: .newBest,
        scoreSnapshot: LiveScoreSnapshot(scoreEngine: engine),
        onPlayAgain: {},
        onDone: {}
    )
}
