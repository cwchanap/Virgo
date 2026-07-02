//
//  KeyCapturingOverlay.swift
//  Virgo
//
//  Created by Claude Code on 9/8/2025.
//

import SwiftUI

extension InputSettingsView {
    var keyCapturingOverlay: some View {
        ZStack {
            Palette.stage.opacity(0.85)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "keyboard.badge.ellipsis")
                    .font(.system(size: 60))
                    .foregroundColor(Palette.vermillion)

                Text("Press any key")
                    .font(.title)
                    .fontWeight(.semibold)
                    .foregroundColor(Palette.chalk)

                if let drumType = selectedDrumType {
                    VStack(spacing: 8) {
                        HStack {
                            Text(drumType.symbol)
                                .font(.title2)
                            Text(drumType.displayName)
                                .font(.title3)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(Palette.chalk)

                        Text("for \(drumType.description)")
                            .font(.body)
                            .foregroundColor(Palette.chalkMuted)
                    }
                }

                Button("Cancel") {
                    cancelKeyCapture()
                }
                .foregroundColor(Palette.chalkMuted)
                .padding(.top)
            }
            .padding()
        }
        .onAppear {
            #if os(macOS)
            startKeyEventMonitoring()
            #endif
        }
        .onDisappear {
            #if os(macOS)
            stopKeyEventMonitoring()
            #endif
        }
    }
}
