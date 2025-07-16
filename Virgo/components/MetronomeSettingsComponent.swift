//
//  MetronomeSettingsComponent.swift
//  Virgo
//
//  Created by Chan Wai Chan on 14/7/2025.
//

import SwiftUI

struct MetronomeSettingsView: View {
    @StateObject private var metronome = MetronomeEngine()
    @State private var tempBPM: Double = 120
    @State private var selectedTimeSignature: TimeSignature = .fourFour
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Metronome Settings")
                .font(.headline)
                .foregroundColor(.white)
            
            // BPM Control
            VStack(spacing: 8) {
                Text("BPM: \(Int(tempBPM))")
                    .font(.title2)
                    .foregroundColor(.white)
                
                Slider(value: $tempBPM, in: 60...200, step: 1)
                    .accentColor(.purple)
                    .onChange(of: tempBPM) { bpm in
                        metronome.configure(bpm: Int(bpm), timeSignature: selectedTimeSignature)
                    }
                
                HStack(spacing: 16) {
                    Button("-10") {
                        tempBPM = max(60, tempBPM - 10)
                    }
                    .buttonStyle(MetronomeButtonStyle())
                    
                    Button("-1") {
                        tempBPM = max(60, tempBPM - 1)
                    }
                    .buttonStyle(MetronomeButtonStyle())
                    
                    Button("+1") {
                        tempBPM = min(200, tempBPM + 1)
                    }
                    .buttonStyle(MetronomeButtonStyle())
                    
                    Button("+10") {
                        tempBPM = min(200, tempBPM + 10)
                    }
                    .buttonStyle(MetronomeButtonStyle())
                }
            }
            
            // Time Signature
            VStack(spacing: 8) {
                Text("Time Signature")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                
                Picker("Time Signature", selection: $selectedTimeSignature) {
                    ForEach(
                        [TimeSignature.twoFour, .threeFour, .fourFour, .fiveFour], 
                        id: \.self
                    ) { signature in
                        Text(signature.displayName).tag(signature)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .onChange(of: selectedTimeSignature) { signature in
                    metronome.configure(bpm: Int(tempBPM), timeSignature: signature)
                }
            }
            
            // Volume Control
            VStack(spacing: 8) {
                Text("Volume")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                
                HStack {
                    Image(systemName: "speaker.fill")
                        .foregroundColor(.gray)
                    
                    Slider(value: $metronome.volume, in: 0.0...1.0)
                        .accentColor(.purple)
                    
                    Image(systemName: "speaker.wave.3.fill")
                        .foregroundColor(.gray)
                }
            }
            
            // Beat indicator
            HStack(spacing: 8) {
                ForEach(0..<selectedTimeSignature.beatsPerMeasure, id: \.self) { beat in
                    Circle()
                        .frame(width: 16, height: 16)
                        .foregroundColor(
                            metronome.isEnabled && metronome.currentBeat == beat ? 
                            (beat == 0 ? .purple : .white) : .gray.opacity(0.3)
                        )
                        .scaleEffect(
                            metronome.isEnabled && metronome.currentBeat == beat ? 1.3 : 1.0
                        )
                        .animation(.easeInOut(duration: 0.1), value: metronome.currentBeat)
                }
            }
            .padding(.top)
            
            // Control buttons
            HStack(spacing: 20) {
                Button(action: metronome.toggle) {
                    Text(metronome.isEnabled ? "Stop" : "Start")
                        .font(.title3)
                        .foregroundColor(.white)
                        .frame(width: 80, height: 40)
                        .background(metronome.isEnabled ? .red : .purple)
                        .cornerRadius(8)
                }
                
                Button("Test Click") {
                    metronome.testClick()
                }
                .buttonStyle(MetronomeButtonStyle())
            }
        }
        .padding()
        .background(Color.black.opacity(0.9))
        .cornerRadius(12)
        .onAppear {
            metronome.configure(bpm: Int(tempBPM), timeSignature: selectedTimeSignature)
        }
    }
}

struct MetronomeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption)
            .foregroundColor(.white)
            .frame(width: 40, height: 30)
            .background(Color.gray.opacity(0.5))
            .cornerRadius(6)
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
    }
}

#Preview {
    MetronomeSettingsView()
        .padding()
        .background(Color.black)
}
