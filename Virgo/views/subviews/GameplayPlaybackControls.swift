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
            onPlayPause: { viewModel.togglePlayback() },
            onRestart: { viewModel.restartPlayback() },
            onSkipToEnd: { viewModel.skipToEnd() }
        )
        .background(Color.black)
    }
}
