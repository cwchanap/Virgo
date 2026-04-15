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
            
            VStack(spacing: 16) {
                midiSourceSelectionPanel
                midiDiagnosticsPanel
                midiActionLegend

                if let lastConflictMessage = midiLearnSession.lastConflictMessage {
                    Text(lastConflictMessage)
                        .font(.caption)
                        .foregroundColor(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                VStack(spacing: 12) {
                    ForEach(DrumType.allCases.sorted(by: { $0.sortOrder < $1.sortOrder }), id: \.self) { drumType in
                        midiMappingRow(for: drumType)
                    }
                }
            }
            .padding()
            .background(Color.black.opacity(0.3))
            .cornerRadius(12)
        }
    }
    
    var midiSourceSelectionPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Gameplay MIDI Source")
                .font(.headline)
                .foregroundColor(.white)

            Picker("Gameplay MIDI Source", selection: selectedSourceBinding) {
                Text("Not Selected").tag(nil as String?)

                if let selectedSourceID = midiDeviceRegistry.selectedSourceID,
                   !midiDeviceRegistry.sources.contains(where: { $0.id == selectedSourceID }) {
                    Text("\(midiDeviceRegistry.displayName(for: selectedSourceID)) (Unavailable)")
                        .tag(Optional(selectedSourceID))
                }

                ForEach(midiDeviceRegistry.sources) { source in
                    Text(source.displayName).tag(Optional(source.id))
                }
            }
            .pickerStyle(.menu)

            if let selectedSourceID = midiDeviceRegistry.selectedSourceID {
                Text(midiDeviceRegistry.displayName(for: selectedSourceID))
                    .font(.caption)
                    .foregroundColor(midiDeviceRegistry.isSelectedSourceAvailable ? .green : .orange)
            } else {
                Text("Not Selected")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
    }

    var midiDiagnosticsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Last MIDI Event")
                .font(.headline)
                .foregroundColor(.white)

            if let lastEvent = midiDiagnosticsStore.lastEvent {
                Text(lastEvent.sourceDisplayName)
                    .font(.subheadline)
                    .foregroundColor(.white)

                HStack(spacing: 12) {
                    Text("Channel \(Int(lastEvent.channel) + 1)")
                    Text("Note \(lastEvent.note)")
                    Text("Velocity \(lastEvent.velocity)")
                }
                .font(.caption)
                .foregroundColor(.gray)

                Text(lastEvent.mappedDrumType?.displayName ?? "No mapping")
                    .font(.caption)
                    .foregroundColor(lastEvent.mappedDrumType == nil ? .orange : .green)
            } else {
                Text("No MIDI activity yet")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var midiActionLegend: some View {
        HStack(spacing: 12) {
            Text("Learn")
            Text("Replace")
            Text("Clear")
        }
        .font(.caption)
        .foregroundColor(.gray)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func midiMappingRow(for drumType: DrumType) -> some View {
        HStack(alignment: .top, spacing: 12) {
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
            
            VStack(alignment: .trailing, spacing: 8) {
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

                HStack(spacing: 8) {
                    if settingsManager.getMidiMapping(for: drumType) == nil {
                        Button("Learn") {
                            guard midiLearnSession.canBeginCapture else { return }
                            midiLearnSession.beginCapture(for: drumType)
                        }
                        .disabled(!midiLearnSession.canBeginCapture)
                    } else {
                        Button("Replace") {
                            guard midiLearnSession.canBeginCapture else { return }
                            midiLearnSession.beginCapture(for: drumType)
                        }
                        .disabled(!midiLearnSession.canBeginCapture)

                        Button("Clear") {
                            if midiLearnSession.isCapturing && midiLearnSession.targetDrumType == drumType {
                                midiLearnSession.cancelCapture()
                            }
                            settingsManager.removeMidiMapping(for: drumType)
                        }
                    }
                }
                .buttonStyle(.bordered)

                if midiLearnSession.isCapturing && midiLearnSession.targetDrumType == drumType {
                    Text("Listening for \(drumType.displayName)...")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding(.vertical, 8)
    }
}
