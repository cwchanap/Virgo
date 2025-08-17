//
//  SettingsView.swift
//  Virgo
//
//  Created by Claude Code on 14/8/2025.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var metronome: MetronomeEngine
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: [Color.black, Color.purple.opacity(0.3)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea(.container, edges: .bottom)

            VStack(spacing: 20) {
                // Header
                VStack(spacing: 10) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Settings")
                                .font(.largeTitle)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            Text("Configure app preferences and controls")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                        Spacer()
                        Image(systemName: "gearshape")
                            .font(.title2)
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal)
                    .padding(.top)
                }
                .padding(.top, 20)
                .padding(.bottom, 16)

                // Settings sections
                VStack(spacing: 16) {
                    // Input Settings
                    NavigationLink(destination: InputSettingsView()) {
                        settingsRow(
                            icon: "keyboard.fill",
                            title: "Input Settings",
                            subtitle: "Configure keyboard and MIDI mappings",
                            iconColor: .purple
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    // Audio Settings
                    NavigationLink(destination: AudioSettingsView()) {
                        settingsRow(
                            icon: "waveform",
                            title: "Audio Settings",
                            subtitle: "Configure audio and playback preferences",
                            iconColor: .blue
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    // Drum Notation Settings
                    NavigationLink(destination: DrumNotationSettingsView()) {
                        settingsRow(
                            icon: "music.note",
                            title: "Drum Notation",
                            subtitle: "Configure drum note positions on staff lines",
                            iconColor: .cyan
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    // Placeholder for future settings
                    VStack(spacing: 12) {
                        settingsRowDisabled(
                            icon: "bell.fill",
                            title: "Notifications",
                            subtitle: "Configure app notifications and alerts",
                            iconColor: .orange
                        )
                        
                        settingsRowDisabled(
                            icon: "paintbrush.fill",
                            title: "Appearance",
                            subtitle: "Customize app theme and visual preferences",
                            iconColor: .cyan
                        )
                        
                        settingsRowDisabled(
                            icon: "icloud.fill",
                            title: "Sync Settings",
                            subtitle: "Manage cloud sync and backup preferences",
                            iconColor: .green
                        )
                    }
                }
                .padding(.horizontal)

                Spacer()
            }
        }
        .navigationTitle("Settings")
    }
    
    // MARK: - Helper Views
    
    private func settingsRow(icon: String, title: String, subtitle: String, iconColor: Color) -> some View {
        HStack(spacing: 16) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(iconColor.opacity(0.2))
                    .frame(width: 50, height: 50)
                
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(iconColor)
            }
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.leading)
            }
            
            Spacer()
            
            // Chevron
            Image(systemName: "chevron.right")
                .font(.body)
                .fontWeight(.medium)
                .foregroundColor(.gray)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.3))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }
    
    private func settingsRowDisabled(icon: String, title: String, subtitle: String, iconColor: Color) -> some View {
        HStack(spacing: 16) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(iconColor.opacity(0.1))
                    .frame(width: 50, height: 50)
                
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(iconColor.opacity(0.5))
            }
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.gray)
                
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.gray.opacity(0.7))
                    .multilineTextAlignment(.leading)
            }
            
            Spacer()
            
            // "Coming Soon" badge
            Text("Soon")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.gray.opacity(0.7))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.gray.opacity(0.2))
                )
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.2))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.05), lineWidth: 1)
                )
        )
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environmentObject(MetronomeEngine())
    }
}
