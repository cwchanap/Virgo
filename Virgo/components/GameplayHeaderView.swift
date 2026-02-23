//
//  GameplayHeaderView.swift
//  Virgo
//
//  Created by Chan Wai Chan on 14/7/2025.
//

import SwiftUI

struct GameplayHeaderView: View {
    let track: DrumTrack
    @Binding var isPlaying: Bool
    let currentScore: Int
    let currentCombo: Int
    let showMilestoneAnimation: Bool
    let showComboBreakFeedback: Bool
    let onDismiss: () -> Void
    let onPlayPause: () -> Void
    let onRestart: () -> Void

    var body: some View {
        HStack {
            Button(action: onDismiss) {
                Image(systemName: "chevron.left")
                    .font(.title2)
                    .foregroundColor(.white)
            }
            .accessibilityLabel("Go back")
            .accessibilityHint("Returns to the song list")
            .padding(.leading)

            Spacer()

            VStack(spacing: 4) {
                Text(track.title)
                    .font(.headline)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                Text(track.artist)
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(track.title) by \(track.artist)")

            Spacer()

            // Score and combo display
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(currentScore)")
                    .font(.system(.body, design: .monospaced).weight(.semibold))
                    .foregroundColor(.white)
                    .accessibilityLabel("Score: \(currentScore)")

                ComboCounterView(
                    combo: currentCombo,
                    showMilestone: showMilestoneAnimation,
                    showBreak: showComboBreakFeedback
                )
            }

            HStack(spacing: 12) {
                Button(action: onRestart) {
                    Image(systemName: "backward.end.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                }
                .accessibilityLabel("Restart")
                .accessibilityHint("Restarts playback from the beginning")

                Button(action: onPlayPause) {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.largeTitle)
                        .foregroundColor(isPlaying ? .red : .green)
                }
                .accessibilityLabel(isPlaying ? "Pause" : "Play")
                .accessibilityHint(isPlaying ? "Pauses the drum track" : "Starts playing the drum track")
            }
            .padding(.trailing)
        }
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.8))
    }
}

// MARK: - Combo Counter

private struct ComboCounterView: View {
    let combo: Int
    let showMilestone: Bool
    let showBreak: Bool

    var body: some View {
        Group {
            if combo > 0 {
                Text("\(combo)x")
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundColor(comboColor)
                    .scaleEffect(showMilestone ? 1.4 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.5), value: showMilestone)
                    .animation(.default, value: combo)
            } else if showBreak {
                Text("BREAK")
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundColor(.red)
                    .transition(.opacity)
            }
        }
        .accessibilityLabel(combo > 0 ? "Combo: \(combo)" : "")
    }

    private var comboColor: Color {
        showBreak ? .red : (showMilestone ? .yellow : .orange)
    }
}

#Preview {
    GameplayHeaderView(
        track: DrumTrack.sampleData.first!,
        isPlaying: .constant(false),
        currentScore: 1250,
        currentCombo: 7,
        showMilestoneAnimation: false,
        showComboBreakFeedback: false,
        onDismiss: {},
        onPlayPause: {},
        onRestart: {}
    )
    .background(Color.black)
}
