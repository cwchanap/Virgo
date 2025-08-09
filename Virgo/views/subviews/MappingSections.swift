//
//  MappingSections.swift
//  Virgo
//
//  Created by Claude Code on 9/8/2025.
//

import SwiftUI

extension InputSettingsView {
    var keyboardMappingSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "keyboard.fill")
                    .foregroundColor(.purple)
                Text("Keyboard Mapping")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                Spacer()
            }
            
            VStack(spacing: 12) {
                ForEach(DrumType.allCases.sorted(by: { $0.sortOrder < $1.sortOrder }), id: \.self) { drumType in
                    keyboardMappingRow(for: drumType)
                }
            }
            .padding()
            .background(Color.black.opacity(0.3))
            .cornerRadius(12)
        }
    }
    
    func keyboardMappingRow(for drumType: DrumType) -> some View {
        HStack {
            // Drum type info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(drumType.symbol)
                        .font(.title2)
                        .foregroundColor(.white)
                    Text(drumType.displayName)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                }
                Text(drumType.description)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            // Current key mapping
            Button(action: {
                startKeyCapture(for: drumType)
            }, label: {
                Text(settingsManager.getKeyBinding(for: drumType) ?? "Not Set")
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)
                    .foregroundColor(isCapturingKey && selectedDrumType == drumType ? .purple : .white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isCapturingKey && selectedDrumType == drumType ?
                                  Color.purple.opacity(0.3) : Color.gray.opacity(0.2))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(isCapturingKey && selectedDrumType == drumType ?
                                           Color.purple : Color.gray.opacity(0.5), lineWidth: 1)
                            )
                    )
            })
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.vertical, 8)
    }
    
    var midiMappingSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "pianokeys")
                    .foregroundColor(.green)
                Text("MIDI Mapping")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                Spacer()
            }
            
            VStack(spacing: 12) {
                ForEach(DrumType.allCases.sorted(by: { $0.sortOrder < $1.sortOrder }), id: \.self) { drumType in
                    midiMappingRow(for: drumType)
                }
            }
            .padding()
            .background(Color.black.opacity(0.3))
            .cornerRadius(12)
        }
    }
    
    func midiMappingRow(for drumType: DrumType) -> some View {
        HStack {
            // Drum type info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(drumType.symbol)
                        .font(.title2)
                        .foregroundColor(.white)
                    Text(drumType.displayName)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                }
                Text("General MIDI Standard")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            // MIDI note number (read-only for now)
            if let midiNote = settingsManager.getMidiMapping(for: drumType) {
                Text("Note \(midiNote)")
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)
                    .foregroundColor(.green)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.green.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.green.opacity(0.3), lineWidth: 1)
                            )
                    )
            } else {
                Text("Not Mapped")
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)
                    .foregroundColor(.gray)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.1))
                    )
            }
        }
        .padding(.vertical, 8)
    }
}
