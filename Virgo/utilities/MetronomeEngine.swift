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
#if os(iOS)
import UIKit
#endif

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
    private let audioDriver: AudioDriverProtocol
    private let timingEngine: MetronomeTimingEngine
    private var cancellables = Set<AnyCancellable>()

    // Haptic feedback (iOS only)
    #if os(iOS)
    private let accentHapticGenerator = UIImpactFeedbackGenerator(style: .heavy)
    private let normalHapticGenerator = UIImpactFeedbackGenerator(style: .medium)
    #endif

    /// Enable or disable haptic feedback on beats (iOS only)
    var hapticFeedbackEnabled: Bool = true

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

    init(audioDriver: AudioDriverProtocol? = nil) {
        self.audioDriver = audioDriver ?? MetronomeAudioEngine()
        self.timingEngine = MetronomeTimingEngine()

        // Connect timing engine to audio engine
        timingEngine.onBeat = { [weak self] beat, isAccented, atTime in
            // Audio playback runs on background thread for precise timing
            self?.handleBeat(beat: beat, isAccented: isAccented, atTime: atTime)
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
        Logger.audioPlayback("🎵 MetronomeEngine.start() called with BPM: \(bpm), timeSignature: \(timeSignature)")
        self.bpm = bpm
        self.timeSignature = timeSignature

        Logger.audioPlayback("🎵 Resuming audio engine...")
        audioDriver.resume()
        Logger.audioPlayback("🎵 Starting timing engine...")
        timingEngine.start()
        Logger.audioPlayback("🎵 MetronomeEngine.start() completed - isEnabled: \(isEnabled)")
    }

    func startAtTime(bpm: Double, timeSignature: TimeSignature, startTime: TimeInterval) {
        Logger.audioPlayback("🎵 MetronomeEngine.startAtTime() called with BPM: \(bpm), timeSignature: \(timeSignature), startTime: \(startTime)")
        self.bpm = bpm
        self.timeSignature = timeSignature

        Logger.audioPlayback("🎵 Resuming audio engine for scheduled start...")
        audioDriver.resume()
        Logger.audioPlayback("🎵 Starting timing engine at scheduled time...")
        timingEngine.startAtTime(startTime: startTime)
        Logger.audioPlayback("🎵 MetronomeEngine.startAtTime() completed - isEnabled: \(isEnabled)")
    }

    func stop() {
        timingEngine.stop()
        audioDriver.stop()
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
        audioDriver.playTick(volume: volume, isAccented: true, atTime: nil)
    }

    // MARK: - Beat Handling

    private func handleBeat(beat: Int, isAccented: Bool, atTime: AVAudioTime? = nil) {
        Logger.audioPlayback("🎵 MetronomeEngine.handleBeat() called - beat: \(beat), isAccented: \(isAccented), volume: \(volume)")
        // Play audio tick with precise timing
        audioDriver.playTick(volume: volume, isAccented: isAccented, atTime: atTime)

        // Trigger haptic feedback on iOS
        #if os(iOS)
        if hapticFeedbackEnabled {
            if isAccented {
                accentHapticGenerator.impactOccurred(intensity: 1.0)
                // Prepare the normal generator for the next beat
                normalHapticGenerator.prepare()
            } else {
                normalHapticGenerator.impactOccurred(intensity: 0.7)
                // Prepare for next accent beat
                accentHapticGenerator.prepare()
            }
        }
        #endif

        Logger.audioPlayback("🎵 MetronomeEngine.handleBeat() completed")
    }

    // MARK: - Configuration Updates

    func updateVolume(_ newVolume: Float) {
        // Validate volume is a finite number
        guard newVolume.isFinite else {
            Logger.audioPlayback("Invalid volume value: \(newVolume), using current volume")
            return
        }
        volume = max(0.0, min(1.0, newVolume))
    }

    func updateBPM(_ newBPM: Double) {
        // Validate BPM is finite and within reasonable range
        guard newBPM.isFinite && newBPM > 0 else {
            Logger.audioPlayback("Invalid BPM value: \(newBPM), keeping current BPM: \(bpm)")
            return
        }
        let clampedBPM = max(40.0, min(200.0, newBPM))
        bpm = clampedBPM
    }

    func updateTimeSignature(_ newTimeSignature: TimeSignature) {
        // Validate time signature has positive beats per measure
        guard newTimeSignature.beatsPerMeasure > 0 else {
            Logger.audioPlayback("Invalid time signature: \(newTimeSignature), keeping current: \(timeSignature)")
            return
        }
        timeSignature = newTimeSignature
    }
    
    // MARK: - Synchronized Timing API
    
    /// Get the current playback time from the metronome's timing engine
    /// This ensures visual elements use the same time reference as audio
    func getCurrentPlaybackTime() -> TimeInterval? {
        return timingEngine.getCurrentPlaybackTime()
    }
    
    /// Get the current beat progress from the metronome's timing engine
    /// Returns precise beat timing for synchronized visual updates
    func getCurrentBeatProgress() -> (totalBeats: Double, beatInMeasure: Double)? {
        return timingEngine.getCurrentBeatProgress(timeSignature: timeSignature)
    }
    
    /// Convert CFAbsoluteTime (metronome timebase) to AVAudioEngine node time
    /// This enables sample-accurate synchronization between metronome and external audio players
    func convertToAudioEngineTime(_ cfTime: CFAbsoluteTime) -> AVAudioTime? {
        return audioDriver.convertToAudioEngineTime(cfTime)
    }
}
