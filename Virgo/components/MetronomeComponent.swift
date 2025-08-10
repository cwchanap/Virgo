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
    let bpm: Int
    let timeSignature: TimeSignature

    var body: some View {
        VStack(spacing: 20) {
            // BPM and Time Signature Display
            VStack(spacing: 8) {
                Text("\(bpm)")
                    .font(.system(size: 48, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)

                Text("BPM")
                    .font(.headline)
                    .foregroundColor(.gray)

                Text(timeSignature.displayName)
                    .font(.title2)
                    .foregroundColor(.gray)
            }

            // Beat Indicator - isolated from main metronome state
            HStack(spacing: 12) {
                ForEach(1...timeSignature.beatsPerMeasure, id: \.self) { beat in
                    Circle()
                        .fill(beat == beatState.currentBeat ? Color.purple : Color.gray.opacity(0.3))
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
                        metronome.toggle(bpm: Double(bpm), timeSignature: timeSignature)
                    },
                    label: {
                        Image(systemName: metronome.isEnabled ? "stop.circle.fill" : "play.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(metronome.isEnabled ? .red : .green)
                    }
                )
                .buttonStyle(PlainButtonStyle())
            }

            // Volume Control
            VStack(spacing: 8) {
                Text("Volume")
                    .font(.caption)
                    .foregroundColor(.gray)

                HStack {
                    Image(systemName: "speaker.fill")
                        .foregroundColor(.gray)
                        .font(.caption)

                    Slider(value: Binding(
                        get: { metronome.volume },
                        set: { metronome.updateVolume($0) }
                    ), in: 0...1)
                    .accentColor(.purple)

                    Image(systemName: "speaker.wave.3.fill")
                        .foregroundColor(.gray)
                        .font(.caption)
                }
            }
        }
        .padding()
        .background(Color.black.opacity(0.3))
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
        bpm: 120,
        timeSignature: .fourFour
    )
    .background(Color.black)
}
