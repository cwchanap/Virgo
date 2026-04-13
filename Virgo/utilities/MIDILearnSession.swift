import Foundation
import Combine

@MainActor
final class MIDILearnSession: ObservableObject {
    @Published private(set) var targetDrumType: DrumType?
    @Published private(set) var isCapturing = false
    @Published private(set) var lastConflictMessage: String?

    private let settingsManager: InputSettingsManager
    private var timeoutTask: Task<Void, Never>?

    init(settingsManager: InputSettingsManager) {
        self.settingsManager = settingsManager
    }

    deinit {
        timeoutTask?.cancel()
    }

    func beginCapture(for drumType: DrumType, timeoutSeconds: Double = 10) {
        timeoutTask?.cancel()
        targetDrumType = drumType
        isCapturing = true
        lastConflictMessage = nil

        timeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(timeoutSeconds))
            } catch {
                return
            }

            await MainActor.run {
                guard let self, self.isCapturing else { return }
                self.cancelCapture()
            }
        }
    }

    func cancelCapture() {
        timeoutTask?.cancel()
        timeoutTask = nil
        targetDrumType = nil
        isCapturing = false
    }

    @discardableResult
    func consume(_ event: MIDINoteEvent, selectedSourceID: String?) -> Bool {
        guard isCapturing,
              let targetDrumType,
              event.sourceID == selectedSourceID,
              event.velocity > 0 else {
            return false
        }

        if let previousDrum = settingsManager.getMidiMappings()[event.note],
           previousDrum != targetDrumType {
            lastConflictMessage =
                "Replaced \(previousDrum.learnDisplayName) " +
                "with \(targetDrumType.learnDisplayName) for note \(event.note)"
        }

        settingsManager.setMidiMapping(event.note, for: targetDrumType)
        cancelCapture()
        return true
    }
}

private extension DrumType {
    var learnDisplayName: String {
        switch self {
        case .kick: return "Kick"
        case .snare: return "Snare"
        case .hiHat: return "Hi-Hat"
        case .hiHatPedal: return "Hi-Hat Pedal"
        case .crash: return "Crash"
        case .ride: return "Ride"
        case .tom1: return "High Tom"
        case .tom2: return "Mid Tom"
        case .tom3: return "Low Tom"
        case .cowbell: return "Cowbell"
        }
    }
}
