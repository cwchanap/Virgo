//
//  MetronomeSettingsComponent.swift
//  Virgo
//
//  Created by Chan Wai Chan on 14/7/2025.
//

import SwiftUI

// MARK: - Constants
private struct MetronomeConstants {
    static let minBPM: Double = 60
    static let maxBPM: Double = 200
    static let defaultBPM: Double = 120
    static let largeAdjustment: Double = 10
    static let smallAdjustment: Double = 1
    static let bpmStep: Double = 1
    static let volumeRange: ClosedRange<Float> = 0.0...1.0
    static let beatIndicatorSize: CGFloat = 16
    static let beatIndicatorActiveScale: CGFloat = 1.3
    static let beatIndicatorAnimationDuration: Double = 0.1
}

struct MetronomeSettingsView: View {
    @ObservedObject var metronome: MetronomeEngine
    @State private var tempBPM: Double = MetronomeConstants.defaultBPM
    @State private var selectedTimeSignature: TimeSignature = .fourFour
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 20) {
            Text("Metronome Settings")
                .font(AppType.headline)
                .foregroundColor(theme.primary)

            // BPM Control
            VStack(spacing: 8) {
                VStack(spacing: 2) {
                    Text("\(Int(tempBPM))")
                        .font(AppType.numericLarge)
                        .foregroundColor(theme.primary)

                    Text("BPM")
                        .font(.plexMono(11, weight: .medium))
                        .tracking(1.5)
                        .foregroundColor(theme.secondary)
                }

                Slider(
                    value: $tempBPM,
                    in: MetronomeConstants.minBPM...MetronomeConstants.maxBPM,
                    step: MetronomeConstants.bpmStep
                )
                .tint(theme.accent)
                .onChange(of: tempBPM) { bpm in
                    metronome.configure(bpm: bpm, timeSignature: selectedTimeSignature)
                }

                HStack(spacing: 16) {
                    Button("-\(Int(MetronomeConstants.largeAdjustment))") {
                        tempBPM = max(MetronomeConstants.minBPM, tempBPM - MetronomeConstants.largeAdjustment)
                    }
                    .buttonStyle(MetronomeButtonStyle())

                    Button("-\(Int(MetronomeConstants.smallAdjustment))") {
                        tempBPM = max(MetronomeConstants.minBPM, tempBPM - MetronomeConstants.smallAdjustment)
                    }
                    .buttonStyle(MetronomeButtonStyle())

                    Button("+\(Int(MetronomeConstants.smallAdjustment))") {
                        tempBPM = min(MetronomeConstants.maxBPM, tempBPM + MetronomeConstants.smallAdjustment)
                    }
                    .buttonStyle(MetronomeButtonStyle())

                    Button("+\(Int(MetronomeConstants.largeAdjustment))") {
                        tempBPM = min(MetronomeConstants.maxBPM, tempBPM + MetronomeConstants.largeAdjustment)
                    }
                    .buttonStyle(MetronomeButtonStyle())
                }
            }

            // Time Signature
            VStack(spacing: 8) {
                Text("Time Signature")
                    .font(.subheadline)
                    .foregroundColor(theme.secondary)

                Picker("Time Signature", selection: $selectedTimeSignature) {
                    ForEach(
                        [TimeSignature.twoFour, .threeFour, .fourFour, .fiveFour],
                        id: \.self
                    ) { signature in
                        Text(signature.displayName).tag(signature)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .tint(theme.accent)
                .onChange(of: selectedTimeSignature) { signature in
                    metronome.configure(bpm: tempBPM, timeSignature: signature)
                }
            }

            // Volume Control
            VStack(spacing: 8) {
                Text("Volume")
                    .font(.subheadline)
                    .foregroundColor(theme.secondary)

                HStack {
                    Image(systemName: "speaker.fill")
                        .foregroundColor(theme.secondary)

                    Slider(value: $metronome.volume, in: MetronomeConstants.volumeRange)
                        .tint(theme.accent)

                    Image(systemName: "speaker.wave.3.fill")
                        .foregroundColor(theme.secondary)
                }
            }

            // Beat indicator
            HStack(spacing: 8) {
                ForEach(0..<selectedTimeSignature.beatsPerMeasure, id: \.self) { beat in
                    Circle()
                        .frame(
                            width: MetronomeConstants.beatIndicatorSize,
                            height: MetronomeConstants.beatIndicatorSize
                        )
                        .foregroundColor(
                            metronome.isEnabled && metronome.currentBeat == beat + 1 ?
                                (beat == 0 ? theme.accent : theme.primary) :
                                theme.secondary.opacity(0.4)
                        )
                        .scaleEffect(
                            metronome.isEnabled && metronome.currentBeat == beat + 1 ?
                                MetronomeConstants.beatIndicatorActiveScale : 1.0
                        )
                        .animation(
                            .easeInOut(duration: MetronomeConstants.beatIndicatorAnimationDuration),
                            value: metronome.currentBeat
                        )
                }
            }
            .padding(.top)

            // Control buttons
            HStack(spacing: 20) {
                Button(
                    action: {
                        metronome.toggle(bpm: tempBPM, timeSignature: selectedTimeSignature)
                    },
                    label: {
                    Text(metronome.isEnabled ? "Stop" : "Start")
                        .font(.title3)
                        .foregroundColor(theme.primary)
                        .frame(width: 80, height: 40)
                        .background(theme.accent)
                        .cornerRadius(8)
                    }
                )

                Button("Test Click") {
                    metronome.testClick()
                }
                .buttonStyle(MetronomeButtonStyle())
            }
        }
        .padding()
        .background(theme.raised)
        .cornerRadius(Radius.md)
        .onAppear {
            metronome.configure(bpm: tempBPM, timeSignature: selectedTimeSignature)
        }
    }
}

struct MetronomeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration)
    }

    private struct StyleBody: View {
        let configuration: Configuration
        @Environment(\.theme) private var theme

        var body: some View {
            configuration.label
                .font(.caption)
                .foregroundColor(theme.primary)
                .frame(width: 40, height: 30)
                .background(theme.raised)
                .cornerRadius(6)
                .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
        }
    }
}

#Preview {
    MetronomeSettingsView(metronome: MetronomeEngine())
        .padding()
        .background(Palette.stage)
}
