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
    @EnvironmentObject private var sharedMetronome: MetronomeEngine
    @State private var logoScale: CGFloat = 0.8
    @State private var musicNoteRotation: Double = 0
    @State private var isAnimating = false
    @State private var showingDebugAlert = false

    var body: some View {
        NavigationStack {
            GeometryReader { _ in
                ZStack {
                    // Gradient background
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.purple.opacity(0.8),
                            Color.blue.opacity(0.6),
                            Color.indigo.opacity(0.8)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .ignoresSafeArea()

                    VStack(spacing: 50) {
                        Spacer()

                        // Virgo Logo Section
                        VStack(spacing: 20) {
                            // Music Note Icon
                            Image(systemName: "music.note")
                                .font(.system(size: 60, weight: .light))
                                .foregroundColor(.white)
                                .rotationEffect(.degrees(musicNoteRotation))
                                .shadow(color: .white.opacity(0.3), radius: 10)
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
                                .font(.custom("Helvetica Neue", size: 48))
                                .fontWeight(.ultraLight)
                                .foregroundColor(.white)
                                .tracking(8)
                                .scaleEffect(logoScale)
                                .shadow(color: .white.opacity(0.5), radius: 20)
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
                                .font(.system(size: 16, weight: .light))
                                .foregroundColor(.white.opacity(0.8))
                                .tracking(2)
                                .accessibilityIdentifier("subtitleText")
                        }

                        Spacer()

                        // Start Button
                        NavigationLink(destination: ContentView()) {
                            HStack(spacing: 15) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 18, weight: .medium))
                                Text("START")
                                    .font(.headline)
                                    .fontWeight(.medium)
                                    .tracking(2)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 40)
                            .padding(.vertical, 15)
                            .background(
                                RoundedRectangle(cornerRadius: 25)
                                    .fill(
                                        LinearGradient(
                                            gradient: Gradient(colors: [
                                                Color.white.opacity(0.2),
                                                Color.white.opacity(0.1)
                                            ]),
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 25)
                                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                                    )
                            )
                            .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
                        }
                        .buttonStyle(PressableButtonStyle())
                        .accessibilityIdentifier("startButton")

                        #if DEBUG
                        // Debug button to clear database
                        Button("Clear Database (Debug)") {
                            showingDebugAlert = true
                        }
                        .foregroundColor(.red.opacity(0.7))
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

// Custom button style for press effect
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

#Preview {
    MainMenuView()
}
