//
//  MappingSections.swift
//  Virgo
//
//  Created by Claude Code on 9/8/2025.
//

import SwiftUI

extension InputSettingsView {
    var keyboardMappingSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            LedgerRow {
                HStack {
                    Image(systemName: "keyboard.fill")
                        .foregroundColor(theme.accent)
                    Text("Keyboard Mapping")
                        .font(AppType.headline)
                        .foregroundColor(theme.primary)
                    Spacer()
                }
            }

            ForEach(DrumType.allCases.sorted(by: { $0.sortOrder < $1.sortOrder }), id: \.self) { drumType in
                keyboardMappingRow(for: drumType)
            }
        }
    }

    func keyboardMappingRow(for drumType: DrumType) -> some View {
        LedgerRow {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(drumType.symbol)
                            .font(.title2)
                            .foregroundColor(theme.primary)
                        Text(drumType.displayName)
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundColor(theme.primary)
                    }
                    Text(drumType.description)
                        .font(.caption)
                        .foregroundColor(theme.secondary)
                }

                Spacer()

                let isActive = isCapturingKey && selectedDrumType == drumType
                Button(action: {
                    startKeyCapture(for: drumType)
                }, label: {
                    Text(settingsManager.getKeyBinding(for: drumType) ?? "Not Set")
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.medium)
                        .foregroundColor(isActive ? theme.accent : theme.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(isActive ? theme.accent.opacity(0.2) : Color.clear)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(isActive ? theme.accent : theme.rule, lineWidth: 1)
                                )
                        )
                })
                .buttonStyle(PlainButtonStyle())
            }
        }
    }

    var midiMappingSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            LedgerRow {
                HStack {
                    Image(systemName: "pianokeys")
                        .foregroundColor(theme.accent)
                    Text("MIDI Mapping")
                        .font(AppType.headline)
                        .foregroundColor(theme.primary)
                    Spacer()
                }
            }

            LedgerRow { midiSourceSelectionPanel }
            LedgerRow { midiDiagnosticsPanel }
            LedgerRow { midiActionLegend }

            if let lastConflictMessage = midiLearnSession.lastConflictMessage {
                LedgerRow {
                    Text(lastConflictMessage)
                        .font(.caption)
                        .foregroundColor(theme.accent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            ForEach(DrumType.allCases.sorted(by: { $0.sortOrder < $1.sortOrder }), id: \.self) { drumType in
                midiMappingRow(for: drumType)
            }
        }
    }

    var midiSourceSelectionPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Gameplay MIDI Source")
                .font(AppType.headline)
                .foregroundColor(theme.primary)

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
            .tint(Palette.vermillion)

            if let selectedSourceID = midiDeviceRegistry.selectedSourceID {
                Text(midiDeviceRegistry.displayName(for: selectedSourceID))
                    .font(.caption)
                    .foregroundColor(theme.accent)
            } else {
                Text("Not Selected")
                    .font(.caption)
                    .foregroundColor(theme.accent)
            }
        }
    }

    var midiDiagnosticsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Last MIDI Event")
                .font(AppType.headline)
                .foregroundColor(theme.primary)

            if let lastEvent = midiDiagnosticsStore.lastEvent {
                Text(lastEvent.sourceDisplayName)
                    .font(.subheadline)
                    .foregroundColor(theme.primary)

                HStack(spacing: 12) {
                    Text("Channel \(Int(lastEvent.channel) + 1)")
                    Text("Note \(lastEvent.note)")
                    Text("Velocity \(lastEvent.velocity)")
                }
                .font(.caption)
                .foregroundColor(theme.secondary)

                Text(lastEvent.mappedDrumType?.displayName ?? "No mapping")
                    .font(.caption)
                    .foregroundColor(theme.accent)
            } else {
                Text("No MIDI activity yet")
                    .font(.caption)
                    .foregroundColor(theme.secondary)
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
        .foregroundColor(theme.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func midiMappingRow(for drumType: DrumType) -> some View {
        LedgerRow {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(drumType.symbol)
                            .font(.title2)
                            .foregroundColor(theme.primary)
                        Text(drumType.displayName)
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundColor(theme.primary)
                    }
                    Text("General MIDI Standard")
                        .font(.caption)
                        .foregroundColor(theme.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 8) {
                    if let midiNote = settingsManager.getMidiMapping(for: drumType) {
                        Text("Note \(midiNote)")
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.medium)
                            .foregroundColor(theme.accent)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(theme.accent.opacity(0.2))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(theme.accent.opacity(0.4), lineWidth: 1)
                                    )
                            )
                    } else {
                        Text("Not Mapped")
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.medium)
                            .foregroundColor(theme.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.clear)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(theme.rule, lineWidth: 1)
                                    )
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
                            .foregroundColor(theme.accent)
                    }
                }
            }
        }
    }
}
