//
//  GameplayPlaybackControls.swift
//  Virgo
//
//  Created by Claude Code on 9/8/2025.
//

import SwiftUI

extension GameplayView {
    var controlsView: some View {
        Group {
            if let viewModel = viewModel {
                let isPlayingBinding = Binding(
                    get: { viewModel.isPlaying },
                    set: { self.viewModel?.isPlaying = $0 }
                )
                let playbackProgressBinding = Binding(
                    get: { viewModel.playbackProgress },
                    set: { self.viewModel?.playbackProgress = $0 }
                )
                GameplayControlsView(
                    track: viewModel.track ?? DrumTrack(chart: viewModel.chart),
                    isPlaying: isPlayingBinding,
                    playbackProgress: playbackProgressBinding,
                    metronome: viewModel.metronome,
                    practiceSettings: viewModel.practiceSettings,
                    onPlayPause: { viewModel.togglePlayback() },
                    onRestart: { viewModel.restartPlayback() },
                    onSkipToEnd: { viewModel.skipToEnd() },
                    onSpeedChange: { viewModel.updateSpeed($0) }
                )
                .background(Color.black)
            } else {
                // Placeholder when viewModel is not yet initialized
                Color.black
                    .frame(height: 100)
            }
        }
    }
}
