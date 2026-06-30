//
//  MetronomeComponent.swift
//  Virgo
//
//  Created by Chan Wai Chan on 13/7/2025.
//

import SwiftUI

// MARK: - Lightweight Beat Indicator State
@MainActor
class BeatIndicatorState: ObservableObject {
    @Published var currentBeat: Int = 1

    func updateBeat(_ beat: Int) {
        currentBeat = beat
    }
}

// MARK: - Metronome Component
struct MetronomeComponent: View {
    @ObservedObject var metronome: MetronomeEngine
    @StateObject private var beatState = BeatIndicatorState()
    let bpm: Double
    let timeSignature: TimeSignature
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 20) {
            // BPM and Time Signature Display
            VStack(spacing: 8) {
                Text(String(format: "%.2f", bpm))
                    .font(AppType.numericLarge)
                    .foregroundColor(theme.primary)

                Text("BPM")
                    .font(.plexMono(11, weight: .medium))
                    .tracking(1.5)
                    .foregroundColor(theme.secondary)

                Text(timeSignature.displayName)
                    .font(.plexMono(16))
                    .foregroundColor(theme.secondary)
            }

            // Beat Indicator - isolated from main metronome state
            HStack(spacing: 12) {
                ForEach(1...timeSignature.beatsPerMeasure, id: \.self) { beat in
                    Circle()
                        .fill(beat == beatState.currentBeat ? theme.accent : theme.secondary.opacity(0.4))
                        .frame(width: 20, height: 20)
                        .scaleEffect(beat == beatState.currentBeat ? 1.2 : 1.0)
                        .animation(.easeInOut(duration: 0.1), value: beatState.currentBeat)
                }
            }

            // Control Buttons
            HStack(spacing: 30) {
                // Play/Stop Button
                Button(
                    action: {
                        metronome.toggle(bpm: bpm, timeSignature: timeSignature)
                    },
                    label: {
                        Image(systemName: metronome.isEnabled ? "stop.circle.fill" : "play.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(theme.accent)
                    }
                )
                .buttonStyle(PlainButtonStyle())
            }

            // Volume Control
            VStack(spacing: 8) {
                Text("Volume")
                    .font(.caption)
                    .foregroundColor(theme.secondary)

                HStack {
                    Image(systemName: "speaker.fill")
                        .foregroundColor(theme.secondary)
                        .font(.caption)

                    Slider(value: Binding(
                        get: { metronome.volume },
                        set: { metronome.updateVolume($0) }
                    ), in: 0...1)
                    .tint(theme.accent)

                    Image(systemName: "speaker.wave.3.fill")
                        .foregroundColor(theme.secondary)
                        .font(.caption)
                }
            }
        }
        .padding()
        .background(theme.raised)
        .cornerRadius(20)
        .onReceive(metronome.$currentBeat) { beat in
            beatState.updateBeat(beat)
        }
        .onAppear {
            beatState.updateBeat(metronome.currentBeat)
        }
    }
}

// MARK: - Preview
#Preview {
    MetronomeComponent(
        metronome: MetronomeEngine(),
        bpm: 120.0,
        timeSignature: .fourFour
    )
    .background(Palette.stage)
}
