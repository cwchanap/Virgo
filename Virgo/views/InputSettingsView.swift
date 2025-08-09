//
//  InputSettingsView.swift
//  Virgo
//
//  Created by Claude Code on 9/8/2025.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

struct InputSettingsView: View {
    @StateObject var settingsManager = InputSettingsManager()
    @State var selectedDrumType: DrumType?
    @State var isCapturingKey = false
    @State private var showResetAlert = false
    
    var body: some View {
        ZStack {
            // Background gradient matching app theme
            LinearGradient(
                gradient: Gradient(colors: [Color.black, Color.purple.opacity(0.3)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 20) {
                // Main content
                ScrollView {
                    VStack(spacing: 24) {
                        // Keyboard Mapping Section
                        keyboardMappingSection
                        
                        // MIDI Mapping Section
                        midiMappingSection
                        
                        // Reset Section
                        resetSection
                    }
                    .padding(.horizontal)
                    .padding(.top)
                }
            }
        }
        .navigationTitle("Input Settings")
        .onAppear {
            settingsManager.loadSettings()
        }
        .overlay {
            if isCapturingKey {
                keyCapturingOverlay
            }
        }
    }
    
    // MARK: - Reset Section
    
    private var resetSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "arrow.clockwise")
                    .foregroundColor(.orange)
                Text("Reset Settings")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                Spacer()
            }
            
            VStack(spacing: 12) {
                Button(action: {
                    showResetAlert = true
                }) {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                            .foregroundColor(.orange)
                        Text("Reset All Mappings to Default")
                            .fontWeight(.medium)
                        Spacer()
                    }
                    .foregroundColor(.orange)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.orange.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .alert("Reset Input Mappings", isPresented: $showResetAlert, actions: {
                    Button("Cancel", role: .cancel) { }
                    Button("Reset", role: .destructive) {
                        settingsManager.resetToDefaults()
                    }
                }, message: {
                    Text("This will reset all keyboard and MIDI mappings to their default values. " +
                         "This action cannot be undone.")
                })
            }
            .padding()
            .background(Color.black.opacity(0.3))
            .cornerRadius(12)
        }
    }
    
    // MARK: - Key Capture Functions
    
    func startKeyCapture(for drumType: DrumType) {
        selectedDrumType = drumType
        isCapturingKey = true
    }
    
    func cancelKeyCapture() {
        isCapturingKey = false
        selectedDrumType = nil
    }
    
    #if os(macOS)
    @State var keyMonitor: Any?
    
    func startKeyEventMonitoring() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleKeyCaptureEvent(event)
            return nil // Consume the event
        }
    }
    
    func stopKeyEventMonitoring() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }
    
    private func handleKeyCaptureEvent(_ event: NSEvent) {
        guard let drumType = selectedDrumType else { return }
        
        let keyString = keyStringFromEvent(event)
        settingsManager.setKeyBinding(keyString, for: drumType)
        
        isCapturingKey = false
        selectedDrumType = nil
    }
    
    // swiftlint:disable:next cyclomatic_complexity
    private func keyStringFromEvent(_ event: NSEvent) -> String {
        // Handle special keys first
        switch event.keyCode {
        case 49: return "space"
        case 53: return "escape"
        case 36: return "return"
        case 48: return "tab"
        case 51: return "delete"
        case 123: return "left"
        case 124: return "right"
        case 125: return "down"
        case 126: return "up"
        default:
            // For regular keys, use the character representation
            if let characters = event.characters?.lowercased(), !characters.isEmpty {
                return characters
            }
            // Fallback to key code for unmappable keys
            return "key\(event.keyCode)"
        }
    }
    #endif
}

#Preview {
    InputSettingsView()
}
