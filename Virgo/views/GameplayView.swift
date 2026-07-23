//
//  GameplayView.swift
//  Virgo
//
//  Created by Chan Wai Chan on 30/6/2025.
//

import SwiftUI
import AVFoundation
import Combine

@MainActor
struct GameplayView: View {
    // MARK: - Dependencies
    /// Shared practice settings service - single source of truth injected via environment
    @EnvironmentObject private var practiceSettings: PracticeSettingsService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let chart: Chart
    let metronome: MetronomeEngine
    private let usesInjectedViewModel: Bool
    private let initialPracticeState: ChartPracticeState
    private let onDismissOverride: (() -> Void)?

    // MARK: - ViewModel
    /// Consolidated state management - initialized lazily with environment dependencies
    @State var viewModel: GameplayViewModel?
    /// Cached fallback track to avoid constructing a new DrumTrack on every render
    @State private var cachedFallbackTrack: DrumTrack
    @StateObject private var practiceStateLoader: ChartPracticeStateLoader

    var practiceState: ChartPracticeState {
        initialPracticeState.isResolved ? initialPracticeState : practiceStateLoader.state
    }

    init(
        chart: Chart,
        metronome: MetronomeEngine,
        initialViewModel: GameplayViewModel? = nil,
        initialPracticeState: ChartPracticeState? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        let resolvedInitialPracticeState = initialPracticeState ?? ChartPracticeState.initial(chart: chart)
        self.chart = chart
        self.metronome = metronome
        self.usesInjectedViewModel = initialViewModel != nil
        self.initialPracticeState = resolvedInitialPracticeState
        self.onDismissOverride = onDismiss
        self._cachedFallbackTrack = State(initialValue: DrumTrack(chart: chart))
        self._viewModel = State(initialValue: initialViewModel)
        self._practiceStateLoader = StateObject(wrappedValue: ChartPracticeStateLoader(
            initialState: resolvedInitialPracticeState
        ))
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

    private var isGameplayReady: Bool {
        viewModel?.isGameplayPrepared == true
    }

    private var fatalPracticeMessage: String? {
        if practiceState.isResolved, !practiceState.isPracticeEnabled {
            return practiceState.reason ?? String(localized: "Unsupported chart timing")
        }
        guard let viewModel, viewModel.hasFatalRhythmTiming else { return nil }
        return viewModel.rhythmFatalMessage
    }

    private func dismissGameplay() {
        if let onDismissOverride {
            onDismissOverride()
        } else {
            dismiss()
        }
    }

    func dismissFatalPractice() {
        guard fatalPracticeMessage != nil else { return }
        dismissGameplay()
    }

    @MainActor
    private func prepareGameplay(initialRowWidth: CGFloat) async {
        if usesInjectedViewModel || viewModel?.isGameplayPrepared == true {
            return
        }
        // Reset speed to default before creating ViewModel to prevent stale speed from previous chart
        practiceSettings.resetSpeed()
        // Initialize viewModel with environment dependencies
        if viewModel == nil {
            viewModel = GameplayViewModel(
                chart: chart,
                metronome: metronome,
                practiceSettings: practiceSettings,
                scorePersistence: ScorePersistenceService(modelContext: modelContext)
            )
        }
        // Check if the task was cancelled immediately after viewModel creation
        if Task.isCancelled {
            viewModel?.cleanup()
            viewModel = nil
            return
        }
        guard let vm = viewModel else { return }
        // Load SwiftData relationships asynchronously to avoid blocking main thread
        await vm.loadChartData()
        // Check cancellation after the async boundary to avoid setup with incomplete state
        guard !Task.isCancelled else { return }
        // Seed the sheet width before setupGameplay builds the first visible notation layout.
        vm.updateRowWidth(initialRowWidth)
        // setupGameplay loads the persisted speed for this chart (SC-06)
        vm.setupGameplay()
        guard vm.isGameplayPrepared else { return }
        // Setup InputManager delegate and metronome subscription after viewModel is ready
        vm.inputManager.delegate = vm.inputHandler
        vm.wireInputHandler()
        vm.setupMetronomeSubscription()
        Logger.userAction("Opened gameplay view for track: \(vm.track?.title ?? "Unknown")")
    }

    var body: some View {
        GeometryReader { geometry in
            if let fatalPracticeMessage {
                rhythmFatalSheet(
                    message: fatalPracticeMessage,
                    onDismiss: dismissFatalPractice
                )
                .accessibilityIdentifier("gameplayRoot")
            } else {
                Group {
                    if isGameplayReady {
                        VStack(spacing: 0) {
                            // Header with track info and controls
                            GameplayHeaderView(
                                track: viewModel?.track ?? cachedFallbackTrack,
                                isPlaying: isPlayingBinding,
                                viewModel: viewModel,
                                onDismiss: dismissGameplay,
                                onPlayPause: { viewModel?.togglePlayback() },
                                onRestart: { viewModel?.restartPlayback() }
                            )
                            .background(Palette.stage)

                            // Main sheet music area - now the primary scrollable content
                            sheetMusicView(geometry: geometry)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)

                            // Bottom controls
                            controlsView
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("gameplayRoot")
                    } else {
                        Palette.stage
                            .overlay(Text("Loading...").foregroundColor(Palette.chalk))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .task(id: chart.persistentModelID) {
                    await practiceStateLoader.load(chart: chart)
                    guard practiceStateLoader.state.isPracticeEnabled else { return }
                    await prepareGameplay(initialRowWidth: geometry.size.width)
                }
            }
        }
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .surface(.ink)
        .foregroundColor(Palette.chalk)
        .colorScheme(.dark)
        .onDisappear {
            viewModel?.cleanup()
        }
        .sheet(isPresented: Binding(
            get: { viewModel?.isShowingSessionResults ?? false },
            set: { viewModel?.isShowingSessionResults = $0 }
        )) {
            if let vm = viewModel {
                SessionResultsView(
                    highScore: vm.scorePersistence.bestScore(for: chart),
                    recordResult: vm.sessionRecordResult,
                    scoreSnapshot: vm.sessionScoreSnapshot,
                    onPlayAgain: {
                        vm.isShowingSessionResults = false
                        vm.restartPlayback()
                        vm.togglePlayback()
                    },
                    onDone: {
                        vm.isShowingSessionResults = false
                        dismissGameplay()
                    }
                )
            }
        }
        .alert("MIDI Device Required", isPresented: Binding(
            get: { viewModel?.isShowingMIDIDeviceAlert ?? false },
            set: { viewModel?.isShowingMIDIDeviceAlert = $0 }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel?.midiDeviceAlertMessage ?? "")
        }
        .alert("Background Music Unavailable", isPresented: Binding(
            get: { viewModel?.bgmLoadingError != nil },
            set: { if !$0 { viewModel?.bgmLoadingError = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            // `bgmLoadingError` is only non-nil when this alert presents, so the
            // empty default never renders. Tells the user gameplay fell back to
            // metronome-only instead of dropping the BGM failure silently.
            Text((viewModel?.bgmLoadingError ?? "") + "\n\nPlaying with the metronome only.")
        }
    }
}

// MARK: - Stable Staff Lines Background View
struct StaffLinesBackgroundView: View {
    let measurePositions: [GameplayLayout.MeasurePosition]
    let width: CGFloat
    private let rows: [Int]

    init(measurePositions: [GameplayLayout.MeasurePosition], width: CGFloat = GameplayLayout.maxRowWidth) {
        self.measurePositions = measurePositions
        self.width = width
        self.rows = Array(Set(measurePositions.map { $0.row })).sorted()
    }

    var body: some View {
        ZStack {
            ForEach(rows, id: \.self) { row in
                ZStack {
                    ForEach(0..<GameplayLayout.staffLineCount, id: \.self) { lineIndex in
                        Rectangle()
                            .frame(width: width, height: 1)
                            // chalkMuted.opacity(0.5), not Palette.gridline — gridline (#2A2419) is near-invisible on stage (#15120D).
                            .foregroundColor(Palette.chalkMuted.opacity(0.5))
                            .position(
                                x: width / 2,
                                y: GameplayLayout.StaffLinePosition(rawValue: lineIndex)?.absoluteY(for: row) ?? 0
                            )
                    }
                }
            }
        }
    }
}
