import Foundation
import Combine

/// Builds the `DispatchSourceTimer` that enforces the capture timeout.
/// `action` must be invoked on the main actor when the timer fires. The default
/// implementation uses a background-queue timer; tests inject a controllable
/// scheduler to avoid relying on wall-clock timing under CI load.
typealias MIDILearnTimeoutTimerFactory = @MainActor (
    Double, // timeoutSeconds
    @escaping @MainActor () -> Void
) -> DispatchSourceTimer

@MainActor
final class MIDILearnSession: ObservableObject {
    @Published private(set) var targetDrumType: DrumType?
    @Published private(set) var isCapturing = false
    @Published private(set) var lastConflictMessage: String?

    private let settingsManager: InputSettingsManager
    private let isSelectedSourceAvailable: @MainActor () -> Bool
    private let timeoutQueue = DispatchQueue(label: "com.virgo.midi.learn-timeout")
    private let makeTimer: MIDILearnTimeoutTimerFactory
    // nonisolated so `deinit` (which is nonisolated) can cancel without a main-actor hop.
    // All access is serialized through `timeoutQueue`.
    private nonisolated(unsafe) var timeoutTimer: DispatchSourceTimer?
    private var activeCaptureID = UUID()

    var canBeginCapture: Bool {
        guard settingsManager.getSelectedMIDISource() != nil else {
            return false
        }
        return isSelectedSourceAvailable()
    }

    init(
        settingsManager: InputSettingsManager,
        isSelectedSourceAvailable: @escaping @MainActor () -> Bool = { true },
        makeTimeoutTimer: MIDILearnTimeoutTimerFactory? = nil
    ) {
        self.settingsManager = settingsManager
        self.isSelectedSourceAvailable = isSelectedSourceAvailable
        self.makeTimer = makeTimeoutTimer ?? Self.defaultTimeoutTimer(queue: timeoutQueue)
    }

    deinit {
        cancelTimeout()
    }

    func beginCapture(for drumType: DrumType, timeoutSeconds: Double = 10) {
        cancelTimeout()
        guard canBeginCapture else {
            targetDrumType = nil
            isCapturing = false
            return
        }

        let captureID = UUID()
        activeCaptureID = captureID
        targetDrumType = drumType
        isCapturing = true
        lastConflictMessage = nil

        let timer = makeTimer(timeoutSeconds) { [weak self] in
            self?.timeoutCaptureIfNeeded(captureID: captureID)
        }
        timeoutQueue.sync { timeoutTimer = timer }
    }

    func cancelCapture() {
        cancelTimeout()
        targetDrumType = nil
        isCapturing = false
    }

    /// Cancels any in-flight timeout timer. Safe from the main actor and from `deinit`
    /// because it only touches the nonisolated timer via the serial `timeoutQueue`.
    private nonisolated func cancelTimeout() {
        timeoutQueue.sync {
            timeoutTimer?.cancel()
            timeoutTimer = nil
        }
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

    /// Production default: a background-queue `DispatchSourceTimer` whose handler
    /// hops to the main actor to mutate capture state. Behavior is identical to the
    /// previous inline implementation.
    private static func defaultTimeoutTimer(queue: DispatchQueue) -> MIDILearnTimeoutTimerFactory {
        { seconds, action in
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + seconds)
            timer.setEventHandler {
                // Hop to the main actor to mutate @MainActor state.
                Task { @MainActor in action() }
            }
            timer.resume()
            return timer
        }
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
