//
//  ProfileView.swift
//  Virgo
//
//  Created by Claude Code on 27/7/2025.
//

import SwiftUI

struct ProfileView: View {
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 10) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Profile")
                                .font(AppType.display)
                                .foregroundColor(theme.primary)
                            Text("Manage your account and preferences")
                                .font(.plexMono(13))
                                .foregroundColor(theme.secondary)
                        }
                        Spacer()
                        Image(systemName: "person.circle")
                            .font(.title2)
                            .foregroundColor(theme.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.top)
                }
                .padding(.top, 20)
                .padding(.bottom, 16)

                // Profile sections
                VStack(spacing: 0) {
                    settingsRowDisabled(
                        icon: "person.crop.circle",
                        title: "User Profile",
                        subtitle: "Manage your account and personal information"
                    )

                    settingsRowDisabled(
                        icon: "trophy.fill",
                        title: "Achievements",
                        subtitle: "View your progress and unlocked achievements"
                    )

                    settingsRowDisabled(
                        icon: "chart.bar.fill",
                        title: "Statistics",
                        subtitle: "View your practice stats and progress"
                    )

                    settingsRowDisabled(
                        icon: "heart.fill",
                        title: "Favorites",
                        subtitle: "Manage your favorite songs and charts"
                    )
                }

                Spacer()
            }
        }
        .appSurface()
        .navigationTitle("Profile")
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
        ProfileView()
    }
}
