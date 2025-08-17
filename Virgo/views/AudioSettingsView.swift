//
//  AudioSettingsView.swift
//  Virgo
//
//  Created by Claude Code on 14/8/2025.
//

import SwiftUI

struct AudioSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                #if os(macOS)
                // Title section with back button for macOS
                HStack {
                    Button(action: { dismiss() }) {
                        HStack(spacing: 8) {
                            Image(systemName: "chevron.left")
                                .font(.title2)
                                .foregroundColor(.white)
                            Text("Back")
                                .font(.headline)
                                .foregroundColor(.white)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Spacer()
                    
                    Text("Audio Settings")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 10)
                #endif
                
                // Audio Playback Settings
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Image(systemName: "speaker.wave.3")
                            .foregroundColor(.green)
                        Text("Playback Settings")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                        Spacer()
                    }
                    
                    VStack(spacing: 12) {
                        disabledSettingRow(
                            icon: "speaker.wave.3",
                            title: "Master Volume",
                            subtitle: "Control overall app volume"
                        )
                        
                        disabledSettingRow(
                            icon: "headphones",
                            title: "Audio Output",
                            subtitle: "Select audio output device"
                        )
                        
                        disabledSettingRow(
                            icon: "waveform.path.ecg",
                            title: "Audio Quality",
                            subtitle: "Configure audio quality settings"
                        )
                        
                        disabledSettingRow(
                            icon: "speaker.badge.plus",
                            title: "Audio Effects",
                            subtitle: "Configure reverb, compression, and EQ"
                        )
                    }
                }
                .padding()
                .background(Color.black.opacity(0.3))
                .cornerRadius(12)
                
                // Audio Engine Settings
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Image(systemName: "gear.badge.checkmark")
                            .foregroundColor(.blue)
                        Text("Audio Engine")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                        Spacer()
                    }
                    
                    VStack(spacing: 12) {
                        disabledSettingRow(
                            icon: "clock.badge",
                            title: "Buffer Size",
                            subtitle: "Adjust audio buffer for latency vs stability"
                        )
                        
                        disabledSettingRow(
                            icon: "waveform.path.badge.plus",
                            title: "Sample Rate",
                            subtitle: "Configure audio sample rate (44.1kHz, 48kHz)"
                        )
                        
                        disabledSettingRow(
                            icon: "cpu",
                            title: "Audio Processing",
                            subtitle: "Enable hardware acceleration"
                        )
                    }
                }
                .padding()
                .background(Color.black.opacity(0.3))
                .cornerRadius(12)
            }
            .padding(.horizontal)
            .padding(.top, 20)
        }
        .background(
            LinearGradient(
                gradient: Gradient(colors: [Color.black, Color.purple.opacity(0.3)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea(.container, edges: .bottom)
        )
        #if os(iOS)
        .navigationTitle("Audio Settings")
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
    
    // MARK: - Helper Views
    
    private func disabledSettingRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 16) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.1))
                    .frame(width: 40, height: 40)
                
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(.gray.opacity(0.5))
            }
            
            // Content
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.medium)
                    .foregroundColor(.gray)
                
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.gray.opacity(0.7))
            }
            
            Spacer()
            
            // "Coming Soon" badge
            Text("Soon")
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(.gray.opacity(0.6))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.2))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.05), lineWidth: 1)
                )
        )
    }
}

#Preview {
    NavigationStack {
        AudioSettingsView()
    }
}
