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
    // MARK: - Dependencies
    /// Shared practice settings service - single source of truth injected via environment
    @EnvironmentObject private var practiceSettings: PracticeSettingsService
    @EnvironmentObject private var metronome: MetronomeEngine
    @Environment(\.dismiss) private var dismiss

    let chart: Chart

    // MARK: - ViewModel
    /// Consolidated state management - initialized lazily with environment dependencies
    @State var viewModel: GameplayViewModel?

    init(chart: Chart) {
        self.chart = chart
    }

    /// Creates a binding for isPlaying when viewModel exists, or returns a constant false binding
    private var isPlayingBinding: Binding<Bool> {
        guard let viewModel = viewModel else {
            return .constant(false)
        }
        return Binding(
            get: { viewModel.isPlaying },
            set: { viewModel.isPlaying = $0 }
        )
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Header with track info and controls
                GameplayHeaderView(
                    track: viewModel?.track ?? DrumTrack(chart: chart),
                    isPlaying: isPlayingBinding,
                    onDismiss: { dismiss() },
                    onPlayPause: { viewModel?.togglePlayback() },
                    onRestart: { viewModel?.restartPlayback() }
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
            // Initialize viewModel with environment dependencies
            if viewModel == nil {
                viewModel = GameplayViewModel(
                    chart: chart,
                    metronome: metronome,
                    practiceSettings: practiceSettings
                )
            }
            // Load SwiftData relationships asynchronously to avoid blocking main thread
            await viewModel?.loadChartData()
            viewModel?.setupGameplay()
        }
        .onAppear {
            Logger.userAction("Opened gameplay view for track: \(viewModel?.track?.title ?? "Unknown")")
            // Setup InputManager delegate
            viewModel?.inputManager.delegate = viewModel?.inputHandler
            // Setup metronome subscription for visual sync
            viewModel?.setupMetronomeSubscription()
        }
        .onChange(of: practiceSettings.speedMultiplier) { _, _ in
            viewModel?.updateSettings(practiceSettings)
        }
        .onDisappear {
            viewModel?.cleanup()
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
