//
//  GameplayControlsView.swift
//  Virgo
//
//  Created by Chan Wai Chan on 14/7/2025.
//

import SwiftUI

struct GameplayControlsView: View {
    let track: DrumTrack
    @Binding var isPlaying: Bool
    @Binding var playbackProgress: Double
    @ObservedObject var metronome: MetronomeEngine
    let onPlayPause: () -> Void
    let onRestart: () -> Void
    let onSkipToEnd: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            // Progress Bar
            VStack(spacing: 8) {
                HStack {
                    Text(formatTime(playbackProgress))
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    Spacer()
                    
                    Text(track.duration)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                ProgressView(value: playbackProgress, total: 1.0)
                    .progressViewStyle(LinearProgressViewStyle(tint: .purple))
                    .frame(height: 4)
            }
            .padding(.horizontal)
            
            // Main Controls
            HStack(spacing: 24) {
                Button(action: onRestart) {
                    Image(systemName: "backward.end.fill")
                        .font(.title)
                        .foregroundColor(.white)
                }
                
                Button(action: onPlayPause) {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 64))
                        .foregroundColor(isPlaying ? .red : .green)
                }
                
                Button(action: onSkipToEnd) {
                    Image(systemName: "forward.end.fill")
                        .font(.title)
                        .foregroundColor(.white)
                }
            }
            
            // Metronome Controls (simplified for now)
            HStack {
                Button("♩") {
                    // Toggle metronome
                    metronome.toggle(bpm: track.bpm, timeSignature: track.timeSignature)
                }
                .foregroundColor(metronome.isEnabled ? .purple : .white)
                .font(.title2)
            }
            .padding(.horizontal)
        }
        .padding()
        .background(
            LinearGradient(
                gradient: Gradient(colors: [Color.clear, Color.black.opacity(0.8)]),
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
    
    private func formatTime(_ progress: Double) -> String {
        let duration = parseDuration(track.duration)
        let currentSeconds = Int(progress * duration)
        let minutes = currentSeconds / 60
        let seconds = currentSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func parseDuration(_ duration: String) -> Double {
        let components = duration.split(separator: ":").compactMap { Double($0) }
        guard components.count == 2 else { return 180.0 }
        return components[0] * 60 + components[1]
    }
}

#Preview {
    GameplayControlsView(
        track: DrumTrack.sampleData.first!,
        isPlaying: .constant(false),
        playbackProgress: .constant(0.3),
        metronome: MetronomeEngine(),
        onPlayPause: {},
        onRestart: {},
        onSkipToEnd: {}
    )
    .background(Color.black)
}
