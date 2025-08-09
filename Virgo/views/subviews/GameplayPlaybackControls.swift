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
            track: track ?? DrumTrack(chart: chart),
            isPlaying: $isPlaying,
            playbackProgress: $playbackProgress,
            metronome: metronome,
            onPlayPause: togglePlayback,
            onRestart: restartPlayback,
            onSkipToEnd: skipToEnd
        )
        .background(Color.black)
    }
}
