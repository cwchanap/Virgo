//
//  InputSettingsView.swift
//  Virgo
//
//  Created by Claude Code on 9/8/2025.
//

import SwiftUI
import Combine
#if os(macOS)
import AppKit
#endif

@MainActor
final class InputKeyCaptureState: ObservableObject {
    @Published var selectedDrumType: DrumType?
    @Published var isCapturingKey = false
}

@MainActor
final class InputKeyCaptureViewModel: ObservableObject {
    @Published var selectedDrumType: DrumType?
    @Published var isCapturingKey = false

    let state: InputKeyCaptureState
    private var cancellables = Set<AnyCancellable>()

    init(state: InputKeyCaptureState) {
        self.state = state
        selectedDrumType = state.selectedDrumType
        isCapturingKey = state.isCapturingKey

        state.$selectedDrumType
            .sink { [weak self] selectedDrumType in
                self?.selectedDrumType = selectedDrumType
            }
            .store(in: &cancellables)

        state.$isCapturingKey
            .sink { [weak self] isCapturingKey in
                self?.isCapturingKey = isCapturingKey
            }
            .store(in: &cancellables)
    }

    func startCapture(for drumType: DrumType) {
        state.selectedDrumType = drumType
        state.isCapturingKey = true
    }

    func cancelCapture() {
        state.isCapturingKey = false
        state.selectedDrumType = nil
    }

    func completeCapture() {
        cancelCapture()
    }
}

struct InputSettingsView: View {
    @StateObject var settingsManager: InputSettingsManager
    @StateObject var midiDeviceRegistry: MIDIDeviceRegistry
    @StateObject var midiDiagnosticsStore: MIDIDiagnosticsStore
    @StateObject var midiLearnSession: MIDILearnSession
    @StateObject var midiPreviewMonitor: MIDIPreviewMonitor
    @StateObject private var keyCaptureViewModel: InputKeyCaptureViewModel
    @State private var showResetAlert = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) var theme

    @MainActor
    init(
        settingsManager: InputSettingsManager? = nil,
        keyCaptureState: InputKeyCaptureState? = nil,
        midiDeviceRegistry: MIDIDeviceRegistry? = nil,
        midiDiagnosticsStore: MIDIDiagnosticsStore? = nil,
        midiLearnSession: MIDILearnSession? = nil,
        midiPreviewMonitor: MIDIPreviewMonitor? = nil
    ) {
        let resolvedSettingsManager = settingsManager ?? InputSettingsManager()
        let resolvedKeyCaptureState = keyCaptureState ?? InputKeyCaptureState()
        let resolvedMIDIDiagnosticsStore = midiDiagnosticsStore ?? MIDIDiagnosticsStore()
        let resolvedMIDIDeviceRegistry =
            midiDeviceRegistry ?? MIDIDeviceRegistry(settingsManager: resolvedSettingsManager)
        let resolvedMIDILearnSession =
            midiLearnSession ?? MIDILearnSession(
                settingsManager: resolvedSettingsManager,
                isSelectedSourceAvailable: { resolvedMIDIDeviceRegistry.isSelectedSourceAvailable }
            )
        let resolvedMIDIPreviewMonitor = midiPreviewMonitor ?? MIDIPreviewMonitor(
            diagnosticsStore: resolvedMIDIDiagnosticsStore,
            settingsManager: resolvedSettingsManager
        )
        self._settingsManager = StateObject(wrappedValue: resolvedSettingsManager)
        self._midiDeviceRegistry = StateObject(wrappedValue: resolvedMIDIDeviceRegistry)
        self._midiDiagnosticsStore = StateObject(wrappedValue: resolvedMIDIDiagnosticsStore)
        self._midiLearnSession = StateObject(wrappedValue: resolvedMIDILearnSession)
        self._midiPreviewMonitor = StateObject(wrappedValue: resolvedMIDIPreviewMonitor)
        self._keyCaptureViewModel = StateObject(
            wrappedValue: InputKeyCaptureViewModel(state: resolvedKeyCaptureState)
        )
    }

    var selectedDrumType: DrumType? {
        keyCaptureViewModel.selectedDrumType
    }

    var isCapturingKey: Bool {
        keyCaptureViewModel.isCapturingKey
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                #if os(macOS)
                // Title section with back button for macOS
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

                        Text("Input Settings")
                            .font(AppType.display)
                            .foregroundColor(theme.primary)

                        Spacer()
                    }
                }
                #endif

                #if os(iOS)
                VStack(spacing: 0) {
                    keyboardMappingSection
                    midiMappingSection
                }
                #else
                HStack(alignment: .top, spacing: 20) {
                    keyboardMappingSection
                        .frame(maxWidth: .infinity)
                    midiMappingSection
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal)
                #endif

                // Reset Section
                resetSection
            }
            .padding(.top, 20)
        }
        .surface(.paper)
        #if os(iOS)
        .navigationTitle("Input Settings")
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            settingsManager.loadSettings()
            midiDeviceRegistry.refreshSources()
            midiPreviewMonitor.onEvent = { event in
                _ = midiLearnSession.consume(
                    event,
                    selectedSourceID: midiDeviceRegistry.selectedSourceID
                )
            }

            let isUITesting = ProcessInfo.processInfo.arguments.contains(LaunchArguments.uiTesting)
            if !TestEnvironment.isRunningTests && !isUITesting {
                midiDeviceRegistry.startMonitoring()
                midiPreviewMonitor.start()
            }
        }
        .onDisappear {
            let isUITesting = ProcessInfo.processInfo.arguments.contains(LaunchArguments.uiTesting)
            if !TestEnvironment.isRunningTests && !isUITesting {
                midiPreviewMonitor.stop()
                midiDeviceRegistry.stopMonitoring()
            }
        }
        .overlay {
            if isCapturingKey {
                keyCapturingOverlay
            }
        }
    }

    // MARK: - Reset Section

    private var resetSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            LedgerRow {
                HStack {
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(theme.accent)
                    Text("Reset Settings")
                        .font(AppType.headline)
                        .foregroundColor(theme.primary)
                    Spacer()
                }
            }

            LedgerRow {
                Button {
                    showResetAlert = true
                } label: {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                            .foregroundColor(theme.accent)
                        Text("Reset All Mappings to Default")
                            .fontWeight(.medium)
                        Spacer()
                    }
                    .foregroundColor(theme.accent)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.clear)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(theme.accent.opacity(0.4), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .alert("Reset Input Mappings", isPresented: $showResetAlert) {
                    Button("Cancel", role: .cancel) { }
                    Button("Reset", role: .destructive) {
                        settingsManager.resetToDefaults()
                        midiLearnSession.cancelCapture()
                        midiDeviceRegistry.refreshSources()
                    }
                } message: {
                    Text("This will reset all keyboard and MIDI mappings to their default values " +
                         "and clear the selected MIDI device. " +
                         "This action cannot be undone.")
                }
            }
        }
    }

    // MARK: - Key Capture Functions

    func startKeyCapture(for drumType: DrumType) {
        keyCaptureViewModel.startCapture(for: drumType)
    }

    func cancelKeyCapture() {
        keyCaptureViewModel.cancelCapture()
    }

    var selectedSourceBinding: Binding<String?> {
        Binding(
            get: { midiDeviceRegistry.selectedSourceID },
            set: { newValue in
                // Cancel any active learn capture when the source changes.
                // The capture was initiated against the previous source; allowing
                // it to complete against a different device would produce misleading mappings.
                midiLearnSession.cancelCapture()

                guard let newValue else {
                    settingsManager.clearSelectedMIDISource()
                    midiDeviceRegistry.refreshSources()
                    return
                }

                guard let source = midiDeviceRegistry.sources.first(where: { $0.id == newValue }) else {
                    return
                }

                midiDeviceRegistry.selectSource(source)
            }
        )
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
        keyCaptureViewModel.completeCapture()
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
