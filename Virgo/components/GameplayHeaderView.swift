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
    @Binding var playbackProgress: Double
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
            
            Spacer()
            
            HStack(spacing: 12) {
                Button(action: onRestart) {
                    Image(systemName: "backward.end.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                }
                
                Button(action: onPlayPause) {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.largeTitle)
                        .foregroundColor(isPlaying ? .red : .green)
                }
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
        playbackProgress: .constant(0.3),
        onDismiss: {},
        onPlayPause: {},
        onRestart: {}
    )
    .background(Color.black)
}
