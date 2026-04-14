import Foundation
import Combine

@MainActor
final class MIDILearnSession: ObservableObject {
    @Published private(set) var targetDrumType: DrumType?
    @Published private(set) var isCapturing = false
    @Published private(set) var lastConflictMessage: String?

    private let settingsManager: InputSettingsManager
    private var timeoutTask: Task<Void, Never>?
    private var activeCaptureID = UUID()

    init(settingsManager: InputSettingsManager) {
        self.settingsManager = settingsManager
    }

    deinit {
        timeoutTask?.cancel()
    }

    func beginCapture(for drumType: DrumType, timeoutSeconds: Double = 10) {
        timeoutTask?.cancel()
        let captureID = UUID()
        activeCaptureID = captureID
        targetDrumType = drumType
        isCapturing = true
        lastConflictMessage = nil

        timeoutTask = Task.detached { [weak self] in
            do {
                try await Task.sleep(for: .seconds(timeoutSeconds))
            } catch {
                return
            }

            guard let self else { return }
            await self.timeoutCaptureIfNeeded(captureID: captureID)
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

    private func timeoutCaptureIfNeeded(captureID: UUID) {
        guard isCapturing, activeCaptureID == captureID else { return }
        cancelCapture()
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
