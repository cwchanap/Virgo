//
//  MetronomeEngine.swift
//  Virgo
//
//  Created by Claude Code on 4/8/2025.
//

import SwiftUI
import AVFoundation
import os.log
import Combine

// MARK: - Main Metronome Engine
@MainActor
class MetronomeEngine: ObservableObject {
    private let logger = Logger()

    // Published properties for UI
    @Published var isEnabled = false
    @Published var volume: Float = 0.7

    // Beat tracking - use private published for internal updates only
    @Published private(set) var currentBeat = 1

    // Engine components
    private let audioEngine: MetronomeAudioEngine
    private let timingEngine: MetronomeTimingEngine
    private var cancellables = Set<AnyCancellable>()

    // Configuration
    var bpm: Double = 120.0 {
        didSet {
            timingEngine.bpm = bpm
        }
    }

    var timeSignature: TimeSignature = .fourFour {
        didSet {
            timingEngine.timeSignature = timeSignature
            currentBeat = 1
        }
    }

    init() {
        self.audioEngine = MetronomeAudioEngine()
        self.timingEngine = MetronomeTimingEngine()

        // Connect timing engine to audio engine
        timingEngine.onBeat = { [weak self] beat, isAccented in
            // Audio playback runs on background thread for precise timing
            self?.handleBeat(beat: beat, isAccented: isAccented)
        }

        // Observe timing engine state
        observeTimingEngine()
    }

    deinit {
        // Cleanup Combine subscriptions
        cancellables.removeAll()
        // Engines have their own deinit cleanup
    }

    // MARK: - Observation

    private func observeTimingEngine() {
        // Update published properties when timing engine changes
        timingEngine.$isPlaying
            .receive(on: DispatchQueue.main)
            .assign(to: \.isEnabled, on: self)
            .store(in: &cancellables)

        timingEngine.$currentBeat
            .receive(on: DispatchQueue.main)
            .assign(to: \.currentBeat, on: self)
            .store(in: &cancellables)
    }

    // MARK: - Playback Control

    func start(bpm: Double, timeSignature: TimeSignature) {
        self.bpm = bpm
        self.timeSignature = timeSignature

        audioEngine.resume()
        timingEngine.start()
    }

    func stop() {
        timingEngine.stop()
        audioEngine.stop()

    }

    func toggle(bpm: Double, timeSignature: TimeSignature) {
        if isEnabled {
            stop()
        } else {
            start(bpm: bpm, timeSignature: timeSignature)
        }
    }

    func configure(bpm: Double, timeSignature: TimeSignature) {
        self.bpm = bpm
        self.timeSignature = timeSignature
    }

    func testClick() {
        // Play a single test click
        audioEngine.playTick(volume: volume, isAccented: true)
    }

    // MARK: - Beat Handling

    private func handleBeat(beat: Int, isAccented: Bool) {
        // Play audio tick
        audioEngine.playTick(volume: volume, isAccented: isAccented)
    }

    // MARK: - Configuration Updates

    func updateVolume(_ newVolume: Float) {
        volume = max(0.0, min(1.0, newVolume))
    }

    func updateBPM(_ newBPM: Double) {
        let clampedBPM = max(40.0, min(200.0, newBPM))
        bpm = clampedBPM
    }

    func updateTimeSignature(_ newTimeSignature: TimeSignature) {
        timeSignature = newTimeSignature
    }
}
