
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
            Color.black.opacity(0.8)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                Image(systemName: "keyboard.badge.ellipsis")
                    .font(.system(size: 60))
                    .foregroundColor(.purple)
                
                Text("Press any key")
                    .font(.title)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                
                if let drumType = selectedDrumType {
                    VStack(spacing: 8) {
                        HStack {
                            Text(drumType.symbol)
                                .font(.title2)
                            Text(drumType.displayName)
                                .font(.title3)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(.white)
                        
                        Text("for \(drumType.description)")
                            .font(.body)
                            .foregroundColor(.gray)
                    }
                }
                
                Button("Cancel") {
                    cancelKeyCapture()
                }
                .foregroundColor(.gray)
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
