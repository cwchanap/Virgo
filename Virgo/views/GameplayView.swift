//
//  GameplayView.swift
//  Virgo
//
//  Created by Chan Wai Chan on 30/6/2025.
//

import SwiftUI
import AVFoundation
import Combine

struct GameplayView: View {
    // MARK: - ViewModel
    /// Consolidated state management - replaces 40+ individual @State variables
    @State var viewModel: GameplayViewModel

    @EnvironmentObject private var practiceSettings: PracticeSettingsService
    @Environment(\.dismiss) private var dismiss

    // PERFORMANCE FIX: Accept metronome as parameter instead of @EnvironmentObject
    init(chart: Chart, metronome: MetronomeEngine, practiceSettings: PracticeSettingsService) {
        self._viewModel = State(initialValue: GameplayViewModel(
            chart: chart,
            metronome: metronome,
            practiceSettings: practiceSettings
        ))
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Header with track info and controls
                GameplayHeaderView(
                    track: viewModel.track ?? DrumTrack(chart: viewModel.chart),
                    isPlaying: $viewModel.isPlaying,
                    onDismiss: { dismiss() },
                    onPlayPause: { viewModel.togglePlayback() },
                    onRestart: { viewModel.restartPlayback() }
                )
                .background(Color.black)

                // Main sheet music area - now the primary scrollable content
                sheetMusicView(geometry: geometry)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Bottom controls
                controlsView
            }
        }
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .background(Color.black)
        .foregroundColor(.white)
        .task {
            if viewModel.practiceSettings !== practiceSettings {
                viewModel = GameplayViewModel(
                    chart: viewModel.chart,
                    metronome: viewModel.metronome,
                    practiceSettings: practiceSettings
                )
                viewModel.inputManager.delegate = viewModel.inputHandler
                viewModel.setupMetronomeSubscription()
            }

            // Load SwiftData relationships asynchronously to avoid blocking main thread
            await viewModel.loadChartData()
            viewModel.setupGameplay()
        }
        .onAppear {
            Logger.userAction("Opened gameplay view for track: \(viewModel.track?.title ?? "Unknown")")
            // Setup InputManager delegate
            viewModel.inputManager.delegate = viewModel.inputHandler
            // Setup metronome subscription for visual sync
            viewModel.setupMetronomeSubscription()
        }
        .onDisappear {
            viewModel.cleanup()
        }
    }
}

// MARK: - Stable Staff Lines Background View
struct StaffLinesBackgroundView: View {
    let measurePositions: [GameplayLayout.MeasurePosition]
    private let rows: [Int]

    init(measurePositions: [GameplayLayout.MeasurePosition]) {
        self.measurePositions = measurePositions
        self.rows = Array(Set(measurePositions.map { $0.row })).sorted()
    }

    var body: some View {
        ZStack {
            ForEach(rows, id: \.self) { row in
                ZStack {
                    ForEach(0..<GameplayLayout.staffLineCount, id: \.self) { lineIndex in
                        Rectangle()
                            .frame(width: GameplayLayout.maxRowWidth, height: 1)
                            .foregroundColor(.gray.opacity(0.5))
                            .position(
                                x: GameplayLayout.maxRowWidth / 2,
                                y: GameplayLayout.StaffLinePosition(rawValue: lineIndex)?.absoluteY(for: row) ?? 0
                            )
                    }
                }
            }
        }
    }
}
