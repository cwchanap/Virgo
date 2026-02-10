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
    @ObservedObject var practiceSettings: PracticeSettingsService
    /// Track duration from view model for consistent progress calculation (Bug 2 fix)
    let cachedTrackDuration: Double
    let onPlayPause: () -> Void
    let onRestart: () -> Void
    let onSkipToEnd: () -> Void
    let onSpeedChange: (Double) -> Void

    /// Debounce timer for speed slider to prevent rapid applySpeedChange calls during drags
    @State private var speedDebounceTimer: Timer?
    /// Debounce interval in seconds (100ms) for speed slider updates
    private let speedDebounceInterval: TimeInterval = 0.1

    var body: some View {
        let adjustedDuration = adjustedDurationSeconds()
        VStack(spacing: 16) {
            // Progress Bar
            VStack(spacing: 8) {
                HStack {
                    Text(formatTime(playbackProgress, durationSeconds: adjustedDuration))
                        .font(.caption)
                        .foregroundColor(.gray)

                    Spacer()

                    Text(formatDuration(adjustedDuration))
                        .font(.caption)
                        .foregroundColor(.gray)
                }

                ProgressView(value: playbackProgress, total: 1.0)
                    .progressViewStyle(LinearProgressViewStyle(tint: .purple))
                    .frame(height: 4)
            }
            .padding(.horizontal)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Playback progress")
            .accessibilityValue(
                "\(formatTime(playbackProgress, durationSeconds: adjustedDuration)) of \(formatDuration(adjustedDuration))"
            )

            // Speed Control Section
            speedControlSection
                .padding(.horizontal)

            // Main Controls
            HStack(spacing: 24) {
                Button(action: onRestart) {
                    Image(systemName: "backward.end.fill")
                        .font(.title)
                        .foregroundColor(.white)
                }
                .accessibilityLabel("Restart")
                .accessibilityHint("Restarts the track from the beginning")

                Button(action: onPlayPause) {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 64))
                        .foregroundColor(isPlaying ? .red : .green)
                }
                .accessibilityLabel(isPlaying ? "Pause" : "Play")
                .accessibilityHint(isPlaying ? "Pauses playback" : "Starts playback")

                Button(action: onSkipToEnd) {
                    Image(systemName: "forward.end.fill")
                        .font(.title)
                        .foregroundColor(.white)
                }
                .accessibilityLabel("Skip to end")
                .accessibilityHint("Jumps to the end of the track")
            }

            // Metronome Controls (simplified for now)
            HStack {
                Button("♩") {
                    // Toggle metronome
                    let effectiveBPM = practiceSettings.effectiveBPM(baseBPM: track.bpm)
                    metronome.toggle(bpm: effectiveBPM, timeSignature: track.timeSignature)
                }
                .foregroundColor(metronome.isEnabled ? .purple : .white)
                .font(.title2)
                .accessibilityLabel("Metronome")
                .accessibilityValue(metronome.isEnabled ? "On" : "Off")
                .accessibilityHint("Toggles the metronome click track")
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
        // Bug 3 fix: Invalidate debounce timer when view disappears to prevent
        // stale speed values from being written after cleanup
        .onDisappear {
            speedDebounceTimer?.invalidate()
            speedDebounceTimer = nil
        }
        // Note: Metronome BPM sync on speed change is handled by
        // GameplayViewModel.applySpeedChange() — no .onChange needed here.
    }

    // MARK: - Speed Control Section

    private var speedControlSection: some View {
        VStack(spacing: 10) {
            // Header row with label and current speed display
            HStack {
                Text("Speed")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                Spacer()
                Text(practiceSettings.formattedSpeed)
                    .font(.headline)
                    .foregroundColor(.purple)
                Text("(\(practiceSettings.formattedEffectiveBPM(baseBPM: track.bpm)))")
                    .font(.caption)
                    .foregroundColor(.gray)
            }

            // Preset buttons row
            HStack(spacing: 8) {
                ForEach(PracticeSettingsService.speedPresets, id: \.self) { preset in
                    Button(
                        action: { onSpeedChange(preset) },
                        label: {
                            Text("\(Int(preset * 100))%")
                                .font(.caption)
                                .fontWeight(isSpeedSelected(preset) ? .bold : .regular)
                                .foregroundColor(isSpeedSelected(preset) ? .white : .gray)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(isSpeedSelected(preset) ? Color.purple : Color.gray.opacity(0.3))
                                )
                        }
                    )
                    .accessibilityLabel("Speed \(Int(preset * 100)) percent")
                    .accessibilityAddTraits(isSpeedSelected(preset) ? .isSelected : [])
                }
            }

            // Slider for fine-grained control
            HStack(spacing: 8) {
                Text("25%")
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .frame(width: 30)

                Slider(
                    value: Binding(
                        get: { practiceSettings.speedMultiplier },
                        set: { newValue in
                            // Snap to 5% increments
                            let snapped = (newValue / PracticeSettingsService.speedIncrement).rounded()
                                * PracticeSettingsService.speedIncrement
                            // Update speed multiplier immediately for responsive UI feedback
                            practiceSettings.setSpeed(snapped)
                            // Debounce the expensive onSpeedChange call that restarts the metronome
                            speedDebounceTimer?.invalidate()
                            speedDebounceTimer = Timer.scheduledTimer(withTimeInterval: speedDebounceInterval, repeats: false) { _ in
                                onSpeedChange(snapped)
                            }
                        }
                    ),
                    in: PracticeSettingsService.minSpeed...PracticeSettingsService.maxSpeed
                )
                .accentColor(.purple)
                .accessibilityLabel("Speed adjustment slider")
                .accessibilityValue("\(Int(practiceSettings.speedMultiplier * 100)) percent")

                Text("150%")
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .frame(width: 35)
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Speed control")
    }

    private func isSpeedSelected(_ preset: Double) -> Bool {
        abs(practiceSettings.speedMultiplier - preset) < 0.01
    }

    // MARK: - Time Formatting

    private func formatTime(_ progress: Double, durationSeconds: Double) -> String {
        let currentSeconds = Int(progress * durationSeconds)
        let minutes = currentSeconds / 60
        let seconds = currentSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func formatDuration(_ durationSeconds: Double) -> String {
        let totalSeconds = Int(durationSeconds)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Returns the speed-adjusted track duration in seconds.
    /// Uses cachedTrackDuration from view model for consistency with progress bar (Bug 2 fix).
    func adjustedDurationSeconds() -> Double {
        let speedMultiplier = practiceSettings.speedMultiplier
        guard speedMultiplier > 0 else { return cachedTrackDuration }
        return cachedTrackDuration / speedMultiplier
    }
}

#Preview {
    GameplayControlsView(
        track: DrumTrack.sampleData.first!,
        isPlaying: .constant(false),
        playbackProgress: .constant(0.3),
        metronome: MetronomeEngine(),
        practiceSettings: PracticeSettingsService(),
        cachedTrackDuration: 180.0,
        onPlayPause: {},
        onRestart: {},
        onSkipToEnd: {},
        onSpeedChange: { _ in }
    )
    .background(Color.black)
}
