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
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                #if os(macOS)
                // Title section with back button for macOS
                HStack {
                    Button(action: { dismiss() }, label: {
                        HStack(spacing: 8) {
                            Image(systemName: "chevron.left")
                                .font(.title2)
                                .foregroundColor(.white)
                            Text("Back")
                                .font(.headline)
                                .foregroundColor(.white)
                        }
                    })
                    .buttonStyle(PlainButtonStyle())
                    
                    Spacer()
                    
                    Text("Input Settings")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 10)
                #endif
                
                // Keyboard and MIDI Mapping Sections (side by side)
                HStack(alignment: .top, spacing: 20) {
                    // Keyboard Mapping Section (left column)
                    keyboardMappingSection
                        .frame(maxWidth: .infinity)
                    
                    // MIDI Mapping Section (right column)
                    midiMappingSection
                        .frame(maxWidth: .infinity)
                }
                
                // Reset Section
                resetSection
            }
            .padding(.horizontal)
            .padding(.top, 20)
        }
        .background(
            LinearGradient(
                gradient: Gradient(colors: [Color.black, Color.purple.opacity(0.3)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea(.container, edges: .bottom)
        )
        #if os(iOS)
        .navigationTitle("Input Settings")
        .navigationBarTitleDisplayMode(.inline)
        #endif
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
                Button {
                    showResetAlert = true
                } label: {
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
                .alert("Reset Input Mappings", isPresented: $showResetAlert) {
                    Button("Cancel", role: .cancel) { }
                    Button("Reset", role: .destructive) {
                        settingsManager.resetToDefaults()
                    }
                } message: {
                    Text("This will reset all keyboard and MIDI mappings to their default values. " +
                         "This action cannot be undone.")
                }
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
        
        stopKeyEventMonitoring()
        isCapturingKey = false
        selectedDrumType = nil
    }
    
    private static let specialKeyCodes: [UInt16: String] = [
        49: "space",
        53: "escape",
        36: "return",
        48: "tab",
        51: "delete",
        123: "left",
        124: "right",
        125: "down",
        126: "up"
    ]
    
    private func keyStringFromEvent(_ event: NSEvent) -> String {
        // Handle special keys first
        if let specialKey = Self.specialKeyCodes[event.keyCode] {
            return specialKey
        }
        
        // For regular keys, use the character representation
        if let characters = event.characters?.lowercased(), !characters.isEmpty {
            return characters
        }
        
        // Fallback to key code for unmappable keys
        return "key\(event.keyCode)"
    }
    #endif
}

#Preview {
    InputSettingsView()
}
