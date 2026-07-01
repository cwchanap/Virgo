//
//  AppearanceSettingsView.swift
//  Virgo
//
//  Lets the user choose System / Light / Dark. Persisted via @AppStorage and
//  applied at the app root through `.preferredColorScheme`.
//

import SwiftUI

struct AppearanceSettingsView: View {
    @AppStorage(AppearanceMode.storageKey) private var appearanceMode: AppearanceMode = .system
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            #if os(macOS)
            // In-view back navigation for macOS (matches sibling settings screens).
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

                    Text("Appearance")
                        .font(AppType.display)
                        .foregroundColor(theme.primary)

                    Spacer()
                }
            }
            #endif

            VStack(spacing: 10) {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Appearance")
                            .font(AppType.display)
                            .foregroundColor(theme.primary)
                        Text("Choose Light, Dark, or follow your device")
                            .font(.plexMono(13))
                            .foregroundColor(theme.secondary)
                    }
                    Spacer()
                    Image(systemName: "paintbrush.fill")
                        .font(.title2)
                        .foregroundColor(theme.secondary)
                }
                .padding(.horizontal)
                .padding(.top)
            }
            .padding(.top, 20)
            .padding(.bottom, 16)

            LedgerRow {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Theme")
                        .font(AppType.headline)
                        .foregroundColor(theme.primary)

                    Picker("Appearance", selection: $appearanceMode) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .tint(Palette.vermillion)
                    .accessibilityIdentifier("appearanceModePicker")

                    Text("\u{201C}System\u{201D} follows your device\u{2019}s Light/Dark setting.")
                        .font(.hanken(14))
                        .foregroundColor(theme.secondary)
                }
            }

            Spacer()
        }
        .appSurface()
        .navigationTitle("Appearance")
    }
}

#Preview {
    NavigationStack {
        AppearanceSettingsView()
    }
}
