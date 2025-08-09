//
//  ProfileView.swift
//  Virgo
//
//  Created by Claude Code on 27/7/2025.
//

import SwiftUI

struct ProfileView: View {
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: [Color.black, Color.purple.opacity(0.3)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 20) {
                // Header
                VStack(spacing: 10) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Profile")
                                .font(.largeTitle)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            Text("Manage your account and preferences")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                        Spacer()
                        Image(systemName: "person.circle")
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
                    
                    // Placeholder for future settings
                    VStack(spacing: 12) {
                        settingsRowDisabled(
                            icon: "trophy.fill",
                            title: "Achievements",
                            subtitle: "View your progress and unlocked achievements",
                            iconColor: .orange
                        )
                        
                        settingsRowDisabled(
                            icon: "waveform",
                            title: "Audio Settings",
                            subtitle: "Configure metronome and playback preferences",
                            iconColor: .blue
                        )
                        
                        settingsRowDisabled(
                            icon: "person.crop.circle",
                            title: "User Profile",
                            subtitle: "Manage your account and personal information",
                            iconColor: .green
                        )
                    }
                }
                .padding(.horizontal)

                Spacer()
            }
        }
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
    NavigationView {
        ProfileView()
    }
}
