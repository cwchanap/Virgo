//
//  GameplayPlaybackControls.swift
//  Virgo
//
//  Created by Claude Code on 9/8/2025.
//

import SwiftUI

extension GameplayView {
    var controlsView: some View {
        GameplayControlsView(
            track: viewModel.track ?? DrumTrack(chart: viewModel.chart),
            isPlaying: $viewModel.isPlaying,
            playbackProgress: $viewModel.playbackProgress,
            metronome: viewModel.metronome,
            practiceSettings: viewModel.practiceSettings,
            onPlayPause: { viewModel.togglePlayback() },
            onRestart: { viewModel.restartPlayback() },
            onSkipToEnd: { viewModel.skipToEnd() },
            onSpeedChange: { viewModel.updateSpeed($0) }
        )
        .background(Color.black)
    }
}
