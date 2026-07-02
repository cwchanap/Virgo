//
//  MetronomeView.swift
//  Virgo
//
//  Created by Chan Wai Chan on 13/7/2025.
//

import SwiftUI

struct MetronomeView: View {
    @EnvironmentObject private var metronome: MetronomeEngine
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            VStack(spacing: 30) {
                // Header
                VStack(spacing: 8) {
                    Text("Metronome")
                        .font(AppType.display)
                        .foregroundColor(theme.primary)

                    Text("Perfect your timing with precision beats")
                        .font(.plexMono(13))
                        .foregroundColor(theme.secondary)
                }
                .padding(.top, 20)

                Spacer()

                // Main metronome settings
                MetronomeSettingsView(metronome: metronome)
                    .padding(.horizontal, 20)

                Spacer()

                // Practice tips section
                VStack(spacing: 16) {
                    Text("Practice Tips")
                        .font(AppType.headline)
                        .foregroundColor(theme.primary)

                    VStack(spacing: 12) {
                        PracticeTipRow(
                            icon: "1.circle.fill",
                            title: "Start Slow",
                            description: "Begin at a comfortable tempo and gradually increase"
                        )

                        PracticeTipRow(
                            icon: "2.circle.fill",
                            title: "Stay Consistent",
                            description: "Focus on maintaining steady timing throughout"
                        )

                        PracticeTipRow(
                            icon: "3.circle.fill",
                            title: "Use Accents",
                            description: "Listen for the emphasized downbeat to stay oriented"
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
        }
        .appSurface()
    }
}

struct PracticeTipRow: View {
    let icon: String
    let title: String
    let description: String

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(theme.accent)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(theme.primary)

                Text(description)
                    .font(.caption)
                    .foregroundColor(theme.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(theme.raised)
        .cornerRadius(Radius.md)
    }
}

#Preview {
    MetronomeView()
        .environmentObject(MetronomeEngine())
        .modelContainer(for: Song.self, inMemory: true)
}
