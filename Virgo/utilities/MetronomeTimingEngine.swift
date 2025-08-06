//
//  MetronomeTimingEngine.swift
//  Virgo
//
//  Created by Claude Code on 4/8/2025.
//

import Foundation
import os.log

// MARK: - Timing Engine
@MainActor
class MetronomeTimingEngine: ObservableObject {
    private let logger = Logger()

    // Timing state
    @Published var currentBeat: Int = 1
    @Published var isPlaying: Bool = false

    // Configuration
    var bpm: Int = 120 {
        didSet {
            if isPlaying {
                restartTimer()
            }
        }
    }

    var timeSignature: TimeSignature = .fourFour {
        didSet {
            currentBeat = 1
        }
    }

    // Timer - using single DispatchSourceTimer for consistency
    private var beatTimer: DispatchSourceTimer?
    private let timerQueue = DispatchQueue(label: "com.virgo.metronome.timing", qos: .userInitiated)

    // Callbacks
    var onBeat: ((Int, Bool) -> Void)?

    private var beatInterval: TimeInterval {
        60.0 / Double(bpm)
    }

    deinit {
        // Stop timer synchronously without MainActor isolation
        beatTimer?.cancel()
        beatTimer = nil
    }

    // MARK: - Playback Control

    func start() {
        guard !isPlaying else { return }

        isPlaying = true
        currentBeat = 1
        startTimer()

        Logger.audioPlayback("Started metronome at \(self.bpm) BPM")
    }

    func stop() {
        guard isPlaying else { return }

        isPlaying = false
        stopTimer()
        currentBeat = 1

        Logger.audioPlayback("Stopped metronome")
    }

    func toggle() {
        if isPlaying {
            stop()
        } else {
            start()
        }
    }

    // MARK: - Timer Management

    private func startTimer() {
        stopTimer()

        let timer = DispatchSource.makeTimerSource(queue: timerQueue)
        beatTimer = timer

        let interval = beatInterval
        let nanoseconds = UInt64(interval * 1_000_000_000)

        timer.schedule(deadline: .now() + interval, repeating: .nanoseconds(Int(nanoseconds)))

        timer.setEventHandler { [weak self] in
            Task { @MainActor in
                self?.handleBeat()
            }
        }

        timer.resume()

        // Trigger first beat immediately
        Task {
            await handleBeat()
        }
    }

    private func stopTimer() {
        beatTimer?.cancel()
        beatTimer = nil
    }

    private func restartTimer() {
        if isPlaying {
            startTimer()
        }
    }

    private func handleBeat() {
        let isAccented = (currentBeat == 1)

        // Notify callback
        onBeat?(currentBeat, isAccented)

        // Advance beat
        currentBeat += 1
        if currentBeat > timeSignature.beatsPerMeasure {
            currentBeat = 1
        }

        Logger.audioPlayback("Beat \(self.currentBeat) (accented: \(isAccented))")
    }
}
