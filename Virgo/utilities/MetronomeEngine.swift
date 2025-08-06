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

    // Configuration
    var bpm: Int = 120 {
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
            Task { @MainActor in
                self?.handleBeat(beat: beat, isAccented: isAccented)
            }
        }

        // Observe timing engine state
        observeTimingEngine()
    }

    deinit {
        Task { @MainActor in
            self.stop()
        }
    }

    // MARK: - Observation

    private func observeTimingEngine() {
        // Update published properties when timing engine changes
        timingEngine.$isPlaying
            .receive(on: DispatchQueue.main)
            .assign(to: &$isEnabled)

        timingEngine.$currentBeat
            .receive(on: DispatchQueue.main)
            .assign(to: &$currentBeat)
    }

    // MARK: - Playback Control

    func start(bpm: Int, timeSignature: TimeSignature) {
        self.bpm = bpm
        self.timeSignature = timeSignature

        audioEngine.resume()
        timingEngine.start()

        Logger.audioPlayback("Started metronome: \(bpm) BPM, \(timeSignature.displayName)")
    }

    func stop() {
        timingEngine.stop()
        audioEngine.stop()

        Logger.audioPlayback("Stopped metronome")
    }

    func toggle(bpm: Int, timeSignature: TimeSignature) {
        if isEnabled {
            stop()
        } else {
            start(bpm: bpm, timeSignature: timeSignature)
        }
    }

    func configure(bpm: Int, timeSignature: TimeSignature) {
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

        Logger.audioPlayback("Beat \(beat) (accented: \(isAccented))")
    }

    // MARK: - Configuration Updates

    func updateVolume(_ newVolume: Float) {
        volume = max(0.0, min(1.0, newVolume))
    }

    func updateBPM(_ newBPM: Int) {
        let clampedBPM = max(40, min(200, newBPM))
        bpm = clampedBPM
    }

    func updateTimeSignature(_ newTimeSignature: TimeSignature) {
        timeSignature = newTimeSignature
    }
}
