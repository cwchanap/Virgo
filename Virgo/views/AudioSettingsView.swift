//
//  AudioSettingsView.swift
//  Virgo
//
//  Created by Claude Code on 14/8/2025.
//

import SwiftUI

struct AudioSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                #if os(macOS)
                // Title section with back button for macOS
                LedgerRow {
                    HStack {
                        Button(action: { dismiss() }, label: {
                            HStack(spacing: 8) {
                                Image(systemName: "chevron.left")
                                    .font(.title2)
                                    .foregroundColor(theme.primary)
                                Text("Back")
                                    .font(.headline)
                                    .foregroundColor(theme.primary)
                            }
                        })
                        .buttonStyle(PlainButtonStyle())

                        Spacer()

                        Text("Audio Settings")
                            .font(AppType.display)
                            .foregroundColor(theme.primary)

                        Spacer()
                    }
                }
                #endif

                // Audio Playback Settings header
                LedgerRow {
                    HStack {
                        Image(systemName: "speaker.wave.3")
                            .foregroundColor(theme.accent)
                        Text("Playback Settings")
                            .font(AppType.headline)
                            .foregroundColor(theme.primary)
                        Spacer()
                    }
                }

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

                // Audio Engine Settings header
                LedgerRow {
                    HStack {
                        Image(systemName: "gear.badge.checkmark")
                            .foregroundColor(theme.accent)
                        Text("Audio Engine")
                            .font(AppType.headline)
                            .foregroundColor(theme.primary)
                        Spacer()
                    }
                }

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
            .padding(.top, 20)
        }
        .surface(.paper)
        #if os(iOS)
        .navigationTitle("Audio Settings")
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - Helper Views

    private func disabledSettingRow(icon: String, title: String, subtitle: String) -> some View {
        LedgerRow {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(theme.secondary)
                    .frame(width: 32, alignment: .center)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AppType.headline)
                        .foregroundColor(theme.secondary)

                    Text(subtitle)
                        .font(.hanken(12))
                        .foregroundColor(theme.secondary)
                }

                Spacer()

                Text("Soon")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(theme.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(theme.rule, lineWidth: 1)
                    )
            }
        }
    }
}

#Preview {
    NavigationStack {
        AudioSettingsView()
    }
}
