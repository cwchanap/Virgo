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

#Preview {
    GameplayHeaderView(
        track: DrumTrack.sampleData.first!,
        isPlaying: .constant(false),
        onDismiss: {},
        onPlayPause: {},
        onRestart: {}
    )
    .background(Color.black)
}
