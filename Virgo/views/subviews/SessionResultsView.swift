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
    let scoreEngine: ScoreEngine
    let onPlayAgain: () -> Void
    let onDone: () -> Void

    private var isNewHighScore: Bool { finalScore > 0 && finalScore > highScore }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 24) {
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

                    // Score
                    VStack(spacing: 4) {
                        Text("\(finalScore)")
                            .font(.system(size: 56, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                        Text("SCORE")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }

                    // Stats grid
                    statsGrid

                    Spacer()

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
                }
                .padding(.top, 32)
            }
            .navigationTitle("Results")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            #endif
        }
    }

    private var statsGrid: some View {
        VStack(spacing: 16) {
            HStack(spacing: 0) {
                statCell(label: "PERFECT", value: "\(scoreEngine.perfectCount)", color: .cyan)
                statCell(label: "GREAT", value: "\(scoreEngine.greatCount)", color: .green)
            }
            HStack(spacing: 0) {
                statCell(label: "GOOD", value: "\(scoreEngine.goodCount)", color: .yellow)
                statCell(label: "MISS", value: "\(scoreEngine.missCount)", color: .red)
            }
            HStack(spacing: 0) {
                statCell(label: "MAX COMBO", value: "\(scoreEngine.maxCombo)x", color: .orange)
                statCell(label: "BEST SCORE", value: "\(highScore)", color: .purple)
            }
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
    for _ in 0..<15 { engine.processHit(accuracy: .perfect) }
    for _ in 0..<5  { engine.processHit(accuracy: .great) }
    for _ in 0..<2  { engine.processHit(accuracy: .good) }
    for _ in 0..<3  { engine.processHit(accuracy: .miss) }

    return SessionResultsView(
        finalScore: 2450,
        highScore: 2100,
        scoreEngine: engine,
        onPlayAgain: {},
        onDone: {}
    )
}
