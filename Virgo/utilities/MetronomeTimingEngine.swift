//
//  MetronomeTimingEngine.swift
//  Virgo
//
//  Created by Claude Code on 4/8/2025.
//

import Foundation
import AVFoundation
import os.log

// MARK: - Timing Engine
@MainActor
class MetronomeTimingEngine: ObservableObject {
    private let logger = Logger()

    // Timing state
    @Published var currentBeat: Int = 1
    @Published var isPlaying: Bool = false

    // Configuration
    var bpm: Double = 120.0 {
        didSet {
            // Cache beat interval when BPM changes to avoid repeated division
            cachedBeatInterval = 60.0 / bpm
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
    
    // Performance optimization: Cache beat interval to avoid repeated division
    private var cachedBeatInterval: TimeInterval = 0.5

    // Callbacks
    var onBeat: ((Int, Bool, AVAudioTime?) -> Void)?

    private var beatInterval: TimeInterval {
        return cachedBeatInterval
    }
    
    init() {
        // Initialize cached beat interval
        cachedBeatInterval = 60.0 / bpm
    }

    deinit {
        // Ensure proper cleanup to prevent crashes
        if let timer = beatTimer {
            timer.cancel()
            beatTimer = nil
        }
    }

    // MARK: - Playback Control

    func start() {
        guard !isPlaying else { return }

        isPlaying = true
        currentBeat = 1
        startTimer()
    }

    func startAtTime(startTime: TimeInterval) {
        guard !isPlaying else { return }

        isPlaying = true
        currentBeat = 1
        startTimerAtTime(startTime: startTime)
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

        // Use nanoseconds precision for accurate timing
        let nanoseconds = Int(beatInterval * 1_000_000_000)

        // Use repeating timer with nanosecond precision 
        timer.schedule(deadline: .now(), repeating: .nanoseconds(nanoseconds))
        
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            let actualFireTime = CFAbsoluteTimeGetCurrent()
            self.fireBeat(actualFireTime: actualFireTime)
        }
        
        timer.resume()
    }

    private func startTimerAtTime(startTime: TimeInterval) {
        stopTimer()

        // Calculate when to actually start relative to current time
        let currentTime = CFAbsoluteTimeGetCurrent()
        let delayUntilStart = startTime - currentTime
        
        if delayUntilStart <= 0 {
            // Start time has already passed, start immediately
            self.startTime = currentTime
            startTimer()
            return
        }
        
        // Schedule timer to start at the specified time
        self.startTime = startTime
        lastFiredBeat = 0
        
        let timer = DispatchSource.makeTimerSource(queue: timerQueue)
        beatTimer = timer
        
        // Use nanoseconds precision for accurate timing
        let nanoseconds = Int(beatInterval * 1_000_000_000)
        let startDelayNanos = Int(delayUntilStart * 1_000_000_000)
        
        // Schedule first beat at the precise start time, then repeat at beat intervals
        timer.schedule(deadline: .now() + .nanoseconds(startDelayNanos), repeating: .nanoseconds(nanoseconds))
        
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            let actualFireTime = CFAbsoluteTimeGetCurrent()
            self.fireBeat(actualFireTime: actualFireTime)
        }
        
        timer.setCancelHandler {
            Logger.debug("🕐 Scheduled timer cancelled")
        }
        
        timer.resume()
        
    }

    private func stopTimer() {
        if let timer = beatTimer {
            timer.cancel()
            beatTimer = nil
        }
    }

    private func restartTimer() {
        if isPlaying {
            startTimer()
        }
    }
    
    private func fireBeat(actualFireTime: CFAbsoluteTime) {
        // SAFETY CHECK: Ensure we're still playing and haven't been stopped
        guard isPlaying else { 
            return 
        }
        
        lastFiredBeat += 1
        
        // Create precise AVAudioTime for sample-accurate scheduling
        let preciseAudioTime = createPreciseAudioTime(for: actualFireTime)
        
        // Play the current beat with precise timing
        self.handleBeat(preciseAudioTime: preciseAudioTime)
    }

    private func createPreciseAudioTime(for fireTime: CFAbsoluteTime) -> AVAudioTime? {
        // Calculate the ideal beat time based on our start time and beat interval
        let beatNumber = lastFiredBeat
        let _ = startTime + (Double(beatNumber - 1) * beatInterval) // For future timing calculations
        
        // Create AVAudioTime for the ideal beat timing
        let hostTime = mach_absolute_time()
        let audioTime = AVAudioTime(hostTime: hostTime)
        
        // Validate the created audio time
        if audioTime.isHostTimeValid && hostTime > 0 {
            return audioTime
        }
        
        return nil
    }

    private func handleBeat(preciseAudioTime: AVAudioTime? = nil) {
        let isAccented = (currentBeat == 1)
        let beatToPlay = currentBeat

        // Use precise timing for sample-accurate audio synchronization
        onBeat?(beatToPlay, isAccented, preciseAudioTime)

        // Update UI properties on main thread
        DispatchQueue.main.async {
            self.currentBeat += 1
            if self.currentBeat > self.timeSignature.beatsPerMeasure {
                self.currentBeat = 1
            }
        }
    }
    
    // MARK: - Synchronized Timing API
    
    /// Get current playback time - same time reference used for audio scheduling
    func getCurrentPlaybackTime() -> TimeInterval? {
        guard isPlaying else { return nil }
        return CFAbsoluteTimeGetCurrent() - startTime
    }
    
    /// Get precise beat progress for visual synchronization
    func getCurrentBeatProgress(timeSignature: TimeSignature) -> (totalBeats: Double, beatInMeasure: Double)? {
        guard let elapsedTime = getCurrentPlaybackTime() else { return nil }
        
        let totalBeats = elapsedTime / beatInterval
        let beatsPerMeasure = Double(timeSignature.beatsPerMeasure)
        let beatInMeasure = totalBeats.truncatingRemainder(dividingBy: beatsPerMeasure)
        
        return (totalBeats: totalBeats, beatInMeasure: beatInMeasure)
    }
}
