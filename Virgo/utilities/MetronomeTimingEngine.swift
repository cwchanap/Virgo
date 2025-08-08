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
    
    // High-precision timing
    private var startTime: CFAbsoluteTime = 0
    private var lastFiredBeat: Int = 0

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
    }

    func stop() {
        guard isPlaying else { return }

        isPlaying = false
        stopTimer()
        currentBeat = 1
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

        // Record start time and reset beat counter
        startTime = CFAbsoluteTimeGetCurrent()
        lastFiredBeat = 0
        
        let timer = DispatchSource.makeTimerSource(queue: timerQueue)
        beatTimer = timer

        // Use a high-frequency timer (60Hz) to check for beat timing
        let checkInterval: TimeInterval = 1.0 / 60.0 // 60Hz check rate
        let nanoseconds = UInt64(checkInterval * 1_000_000_000)

        timer.schedule(deadline: .now(), repeating: .nanoseconds(Int(nanoseconds)))

        timer.setEventHandler { [weak self] in
            self?.checkForNextBeat()
        }

        timer.resume()
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
    
    private func checkForNextBeat() {
        guard isPlaying else { return }
        
        let currentTime = CFAbsoluteTimeGetCurrent()
        let elapsedTime = currentTime - startTime
        
        // Calculate which beat we should be at based on elapsed time
        let expectedBeatNumber = Int(elapsedTime / beatInterval) + 1
        
        // Only fire if we haven't fired this beat yet
        if expectedBeatNumber > lastFiredBeat {
            lastFiredBeat = expectedBeatNumber
            self.handleBeat()
        }
    }

    private func handleBeat() {
        let isAccented = (currentBeat == 1)
        let beatToPlay = currentBeat

        // Notify audio callback immediately on timing thread for precise audio
        onBeat?(beatToPlay, isAccented)

        // Update UI properties on main thread
        DispatchQueue.main.async {
            self.currentBeat += 1
            if self.currentBeat > self.timeSignature.beatsPerMeasure {
                self.currentBeat = 1
            }
        }
    }
}
