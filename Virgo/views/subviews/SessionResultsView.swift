//
//  SessionResultsView.swift
//  Virgo
//
//  End-of-session results sheet shown after playback completes.
//

import SwiftUI

struct SessionResultsView: View {
    let finalScore: Int
    let highScore: Int
    /// Whether the save service confirmed this score as a verified new record.
    /// Derived from `HighScoreService.saveIfHighScore` return value rather than
    /// a local score comparison, so the badge only appears when the write succeeded.
    let isNewRecord: Bool
    let scoreEngine: ScoreEngine
    let onPlayAgain: () -> Void
    let onDone: () -> Void

    private var isNewHighScore: Bool { finalScore > 0 && isNewRecord }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // New high score badge
                        if isNewHighScore {
                            Text("NEW HIGH SCORE!")
                                .font(.system(.caption, design: .rounded).weight(.bold))
                                .foregroundColor(.black)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.yellow)
                                .clipShape(Capsule())
                        }

                        // Accuracy ring + Score
                        HStack(spacing: 32) {
                            AccuracyCircleView(percentage: scoreEngine.accuracyPercentage)

                            VStack(spacing: 4) {
                                Text("\(finalScore)")
                                    .font(.system(size: 44, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white)
                                Text("SCORE")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                        }

                        // Hit breakdown chart
                        AccuracyBreakdownChart(
                            perfectCount: scoreEngine.perfectCount,
                            greatCount: scoreEngine.greatCount,
                            goodCount: scoreEngine.goodCount,
                            missCount: scoreEngine.missCount
                        )
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)

                        // Timing deviation
                        TimingDeviationView(
                            averageDeviation: scoreEngine.averageTimingDeviation,
                            earlyPercentage: scoreEngine.earlyPercentage,
                            latePercentage: scoreEngine.latePercentage,
                            tendency: scoreEngine.timingTendency
                        )
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)

                        // Max combo + best score
                        statsGrid

                        // Actions
                        VStack(spacing: 12) {
                            Button(action: onPlayAgain) {
                                Text("Play Again")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.green)
                                    .foregroundColor(.black)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }

                            Button(action: onDone) {
                                Text("Done")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.white.opacity(0.15))
                                    .foregroundColor(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 24)
                    }
                    .padding(.top, 24)
                }
            }
            .navigationTitle("Results")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            #endif
        }
    }

    private var statsGrid: some View {
        HStack(spacing: 0) {
            statCell(label: "MAX COMBO", value: "\(scoreEngine.maxCombo)x", color: .orange)
            statCell(label: "BEST SCORE", value: "\(highScore)", color: .purple)
        }
        .padding(.horizontal)
    }

    private func statCell(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(.title2, design: .monospaced).weight(.semibold))
                .foregroundColor(color)
            Text(label)
                .font(.caption2)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.05))
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
        finalScore: 2450,
        highScore: 2450,
        isNewRecord: true,
        scoreEngine: engine,
        onPlayAgain: {},
        onDone: {}
    )
}
