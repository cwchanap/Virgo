//
//  SettingsView.swift
//  Virgo
//
//  Created by Claude Code on 14/8/2025.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var metronome: MetronomeEngine
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 10) {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Settings")
                            .font(AppType.display)
                            .foregroundColor(theme.primary)
                        Text("Configure app preferences and controls")
                            .font(.plexMono(13))
                            .foregroundColor(theme.secondary)
                    }
                    Spacer()
                    Image(systemName: "gearshape")
                        .font(.title2)
                        .foregroundColor(theme.secondary)
                }
                .padding(.horizontal)
                .padding(.top)
            }
            .padding(.top, 20)
            .padding(.bottom, 16)

            // Settings sections
            VStack(spacing: 0) {
                // Input Settings
                NavigationLink(destination: InputSettingsView()) {
                    settingsRow(
                        icon: "keyboard.fill",
                        title: "Input Settings",
                        subtitle: "Configure keyboard and MIDI mappings"
                    )
                }
                .buttonStyle(PlainButtonStyle())

                // Audio Settings
                NavigationLink(destination: AudioSettingsView()) {
                    settingsRow(
                        icon: "waveform",
                        title: "Audio Settings",
                        subtitle: "Configure audio and playback preferences"
                    )
                }
                .buttonStyle(PlainButtonStyle())

                // Drum Notation Settings
                NavigationLink(destination: DrumNotationSettingsView()) {
                    settingsRow(
                        icon: "music.note",
                        title: "Drum Notation",
                        subtitle: "Configure drum note positions on staff lines"
                    )
                }
                .buttonStyle(PlainButtonStyle())

                // Placeholder for future settings
                settingsRowDisabled(
                    icon: "bell.fill",
                    title: "Notifications",
                    subtitle: "Configure app notifications and alerts"
                )

                NavigationLink(destination: AppearanceSettingsView()) {
                    settingsRow(
                        icon: "paintbrush.fill",
                        title: "Appearance",
                        subtitle: "Light, dark, or follow system"
                    )
                }
                .buttonStyle(PlainButtonStyle())

                settingsRowDisabled(
                    icon: "icloud.fill",
                    title: "Sync Settings",
                    subtitle: "Manage cloud sync and backup preferences"
                )
            }

            Spacer()
        }
        .appSurface()
        .navigationTitle("Settings")
    }

    // MARK: - Helper Views

    private func settingsRow(icon: String, title: String, subtitle: String) -> some View {
        LedgerRow {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(theme.accent)
                    .frame(width: 32, alignment: .center)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(AppType.headline)
                        .foregroundColor(theme.primary)

                    Text(subtitle)
                        .font(.hanken(14))
                        .foregroundColor(theme.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(theme.secondary)
            }
        }
    }

    private func settingsRowDisabled(icon: String, title: String, subtitle: String) -> some View {
        LedgerRow {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(theme.secondary)
                    .frame(width: 32, alignment: .center)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(AppType.headline)
                        .foregroundColor(theme.secondary)

                    Text(subtitle)
                        .font(.hanken(14))
                        .foregroundColor(theme.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                Text("Soon")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(theme.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(theme.rule, lineWidth: 1)
                    )
            }
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environmentObject(MetronomeEngine())
    }
}
