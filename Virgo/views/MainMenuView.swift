//
//  MainMenuView.swift
//  Virgo
//
//  Created by Chan Wai Chan on 29/6/2025.
//

import SwiftUI
import SwiftData

struct MainMenuView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.theme) private var theme
    @EnvironmentObject private var sharedMetronome: MetronomeEngine
    @State private var logoScale: CGFloat = 0.8
    @State private var musicNoteRotation: Double = 0
    @State private var isAnimating = false
    @State private var showingDebugAlert = false

    var body: some View {
        // NavigationStack wraps the splash menu so the START push to ContentView
        // gets a back button, keeping the debug "Clear Database" control reachable.
        // ContentView's own root is a TabView (per-tab NavigationStacks), so this
        // outer stack does not create a nested-NavigationStack hierarchy.
        NavigationStack {
            GeometryReader { _ in
                ZStack {
                    VStack(spacing: 50) {
                        Spacer()

                        // Virgo Logo Section
                        VStack(spacing: 20) {
                            // Music Note Icon
                            Image(systemName: "music.note")
                                .font(.system(size: 60, weight: .light))
                                .foregroundColor(theme.accent)
                                .rotationEffect(.degrees(musicNoteRotation))
                                .onAppear {
                                    if isAnimating {
                                        withAnimation(
                                            .easeInOut(duration: 2.0)
                                                .repeatForever(autoreverses: true)
                                        ) {
                                            musicNoteRotation = 10
                                        }
                                    }
                                }

                            // Virgo Text Logo
                            Text("VIRGO")
                                .font(AppType.wordmark)
                                .foregroundColor(theme.primary)
                                .tracking(6)
                                .scaleEffect(logoScale)
                                .drawnUnderline(active: isAnimating)
                                .accessibilityIdentifier("logoText")
                                .onAppear {
                                    if isAnimating {
                                        withAnimation(
                                            .easeInOut(duration: 1.5)
                                                .repeatForever(autoreverses: true)
                                        ) {
                                            logoScale = 1.0
                                        }
                                    }
                                }

                            // Subtitle
                            Text("Music App")
                                .font(.plexMono(13))
                                .foregroundColor(theme.secondary)
                                .tracking(2)
                                .accessibilityIdentifier("subtitleText")

                            TempoMark(bpm: 120)
                        }

                        Spacer()

                        // Start Button — NavigationLink provides back-navigation to this menu
                        NavigationLink(destination: ContentView()) {
                            HStack(spacing: Spacing.md) {
                                Image(systemName: "play.fill")
                                Text("START").tracking(2)
                            }
                        }
                        .buttonStyle(VermillionButtonStyle())
                        .accessibilityIdentifier("startButton")

                        #if DEBUG
                        // Debug button to clear database
                        Button("Clear Database (Debug)") {
                            showingDebugAlert = true
                        }
                        .foregroundColor(theme.accent.opacity(0.8))
                        .font(.caption)
                        .padding(.top, 20)
                        #endif

                        Spacer()
                    }
                    .padding()
                    .onAppear {
                        isAnimating = true
                    }
                    .onDisappear {
                        isAnimating = false
                    }
                    .alert("Clear Database", isPresented: $showingDebugAlert) {
                        Button("Cancel", role: .cancel) { }
                        Button("Clear", role: .destructive) {
                            clearDatabase()
                        }
                    } message: {
                        Text("This will delete all existing data and reload sample tracks. This action cannot be undone.")
                    }
                }
                .surface(.paper)
            }
        }
    }

    private func clearDatabase() {
        do {
            // Delete all existing Song records (and related charts/notes via cascade)
            try modelContext.delete(model: Song.self)
            try modelContext.save()
            Logger.database("Database cleared successfully")
        } catch {
            Logger.databaseError(error)
        }
    }

}

#Preview {
    MainMenuView()
        .environmentObject(MetronomeEngine())
}
