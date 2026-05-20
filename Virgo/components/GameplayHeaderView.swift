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
    /// The ViewModel is accepted here (instead of individual score values) so that
    /// only this subview's body observes scoreEngine / animation flags.
    /// GameplayView.body never reads those properties and avoids costly full-tree
    /// re-renders on every hit or miss.
    let viewModel: GameplayViewModel?
    let onDismiss: () -> Void
    let onPlayPause: () -> Void
    let onRestart: () -> Void

    var body: some View {
        // Score display reads a snapshot here so score observation stays scoped
        // to this compact HUD instead of the full gameplay view tree.
        let snapshot = viewModel?.liveScoreSnapshot ?? .empty
        ViewThatFits(in: .horizontal) {
            regularHeader(snapshot: snapshot)
                .frame(minWidth: 620)

            compactHeader(snapshot: snapshot)
        }
        .background(Color.black.opacity(0.8))
    }

    private func regularHeader(snapshot: LiveScoreSnapshot) -> some View {
        HStack {
            backButton
            .padding(.leading)

            Spacer()

            titleBlock(alignment: .center, titleLineLimit: nil, artistLineLimit: nil)

            Spacer()

            scoreHUD(snapshot: snapshot)

            transportControls
            .padding(.trailing)
        }
        .padding(.vertical, 8)
    }

    private func compactHeader(snapshot: LiveScoreSnapshot) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                backButton

                titleBlock(alignment: .leading, titleLineLimit: 1, artistLineLimit: 1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)

                transportControls
            }

            scoreHUD(snapshot: snapshot)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var backButton: some View {
        Button(action: onDismiss) {
            Image(systemName: "chevron.left")
                .font(.title2)
                .foregroundColor(.white)
        }
        .accessibilityLabel("Go back")
        .accessibilityHint("Returns to the song list")
    }

    private var transportControls: some View {
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
    }

    private func titleBlock(
        alignment: HorizontalAlignment,
        titleLineLimit: Int?,
        artistLineLimit: Int?
    ) -> some View {
        VStack(alignment: alignment, spacing: 4) {
            Text(track.title)
                .font(.headline)
                .foregroundColor(.white)
                .multilineTextAlignment(alignment.textAlignment)
                .lineLimit(titleLineLimit)
                .minimumScaleFactor(0.75)

            Text(track.artist)
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(alignment.textAlignment)
                .lineLimit(artistLineLimit)
                .minimumScaleFactor(0.75)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(track.title) by \(track.artist)")
    }

    private func scoreHUD(snapshot: LiveScoreSnapshot) -> some View {
        GameplayScoreHUDView(
            snapshot: snapshot,
            showMilestone: viewModel?.showMilestoneAnimation ?? false,
            showBreak: viewModel?.showComboBreakFeedback ?? false
        )
    }
}

private extension HorizontalAlignment {
    var textAlignment: TextAlignment {
        switch self {
        case .leading:
            return .leading
        case .trailing:
            return .trailing
        default:
            return .center
        }
    }
}

// MARK: - Score HUD

private struct GameplayScoreHUDView: View {
    let snapshot: LiveScoreSnapshot
    let showMilestone: Bool
    let showBreak: Bool

    var body: some View {
        HStack(spacing: 8) {
            ScoreStatCell(label: "SCORE", value: "\(snapshot.score)", color: .white, minWidth: 76)
            ScoreStatCell(label: "ACC", value: snapshot.hitAccuracyPercentText, color: .green, minWidth: 54)
            ScoreStatCell(label: "QLTY", value: snapshot.timingQualityPercentText, color: .cyan, minWidth: 54)
            ComboCounterView(
                combo: snapshot.currentCombo,
                showMilestone: showMilestone,
                showBreak: showBreak
            )
            .frame(minWidth: 44, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Score \(snapshot.score), accuracy \(snapshot.hitAccuracyPercentText), " +
            "quality \(snapshot.timingQualityPercentText), combo \(snapshot.currentCombo)"
        )
    }
}

private struct ScoreStatCell: View {
    let label: String
    let value: String
    let color: Color
    let minWidth: CGFloat

    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(value)
                .font(.system(.body, design: .monospaced).weight(.semibold))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundColor(.gray)
        }
        .frame(minWidth: minWidth, alignment: .trailing)
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
        .accessibilityLabel(combo > 0 ? "Combo: \(combo)" : (showBreak ? "BREAK" : ""))
    }

    private var comboColor: Color {
        showMilestone ? .yellow : .orange
    }
}

#Preview {
    GameplayHeaderView(
        track: DrumTrack.sampleData.first!,
        isPlaying: .constant(false),
        viewModel: nil,
        onDismiss: {},
        onPlayPause: {},
        onRestart: {}
    )
    .background(Color.black)
}
