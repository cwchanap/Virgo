//
//  MetronomeTimingEngine.swift
//  Virgo
//
//  Created by Claude Code on 4/8/2025.
//

import Foundation
import AVFoundation
import os.log

// Threading contract: instances are captured into the timer event handler that
// fires on `timerQueue` (see `startTimer` / `startTimerAtTime`). All mutable
// state is lock-guarded; `@unchecked Sendable` documents this manual contract
// and keeps the type consistent with `MetronomeAudioEngine`'s Sendable story.
private final class MetronomePlaybackToken: @unchecked Sendable {
    private let lock = NSLock()
    private var active = true

    var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return active
    }

    func cancel() {
        lock.lock()
        active = false
        lock.unlock()
    }
}

// Threading contract: a single instance is captured into the timer event
// handler and mutated only from that serial `timerQueue`. Today only one
// counter is captured per timer build, so `DispatchSourceTimer`'s serial
// delivery makes mutation safe. The `NSLock` below makes that contract
// self-enforcing: a future change that captures the same counter into a second
// handler (or mutates it off the timer queue) cannot introduce a silent data
// race. `@unchecked Sendable` documents this manual isolation story and
// matches the rest of the metronome's Sendable handling (see
// `MetronomePlaybackToken`).
private final class MetronomeBeatCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var nextBeatNumber: Int

    init(firstBeatNumber: Int) {
        self.nextBeatNumber = firstBeatNumber
    }

    func consumeNextBeatNumber() -> Int {
        lock.lock()
        defer { lock.unlock() }
        let beatNumber = nextBeatNumber
        nextBeatNumber += 1
        return beatNumber
    }
}

// MARK: - Timing Engine
@MainActor
class MetronomeTimingEngine: ObservableObject {
    private let isTestEnvironment: Bool

    // Timing state
    @Published var currentBeat: Int = 1
    @Published var isPlaying: Bool = false

    // Configuration
    var bpm: Double = 120.0 {
        didSet {
            // Cache beat interval when BPM changes to avoid repeated division
            updateCachedBeatInterval()
            if isPlaying {
                restartTimer()
            }
        }
    }

    var timeSignature: TimeSignature = .fourFour {
        didSet {
            updateCachedBeatInterval()
            currentBeat = 1
            if isPlaying {
                restartTimer()
            }
        }
    }

    // Timer - using single DispatchSourceTimer for consistency
    private var beatTimer: DispatchSourceTimer?
    private var playbackToken: MetronomePlaybackToken?
    private let timerQueue = DispatchQueue(label: "com.virgo.metronome.timing", qos: .userInitiated)
    
    // High-precision timing
    private var startTime: CFAbsoluteTime = 0
    private var beatOriginTime: CFAbsoluteTime = 0
    private var lastFiredBeat: Int = 0
    private var beatOffset: Int = 0
    
    // Performance optimization: Cache beat interval to avoid repeated division
    private var cachedBeatInterval: TimeInterval = 0.5
    private let audioSchedulingLeadTime: TimeInterval = 0.04

    // MARK: - Beat Callbacks

    /// Audio-tick callback, fired ~40ms ahead of each audible beat so the audio
    /// driver can schedule the tick sample-accurately. Invoked on `timerQueue`.
    ///
    /// - Important: This closure is captured by value when `start()` /
    ///   `startAtTime()` builds the timer (see `startTimer` / `startTimerAtTime`).
    ///   Reassigning `onAudioBeat` after playback has begun has no effect until
    ///   the timer is (re)started — mid-playback reassignment is intentionally
    ///   ignored to keep the captured callback stable across timer ticks.
    var onAudioBeat: ((Int, Bool, AVAudioTime?) -> Void)?

    /// Visual-beat callback, fired at the audible beat boundary for UI/haptic
    /// updates. Invoked on the main queue (dispatched from the timer handler).
    ///
    /// - Important: Like `onAudioBeat`, this closure is captured by value when
    ///   the timer is built. Reassignment after playback starts takes effect
    ///   only on the next `start()` / `startAtTime()` / `restartTimer()`.
    var onBeat: ((Int, Bool, AVAudioTime?) -> Void)?

    private var beatInterval: TimeInterval {
        return cachedBeatInterval
    }

    private func updateCachedBeatInterval() {
        cachedBeatInterval = 60.0 / bpm
    }
    
    init(isTestEnvironment: Bool = TestEnvironment.isRunningTests) {
        self.isTestEnvironment = isTestEnvironment
        // Initialize cached beat interval
        updateCachedBeatInterval()

        if isTestEnvironment {
            Logger.audioPlayback("Test environment - MetronomeTimingEngine will simulate timing")
        }
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
        
        if isTestEnvironment {
            // In test environment, simulate immediate start
            simulateTestBeat()
        } else {
            startTimer()
        }
    }

    func startAtTime(startTime: TimeInterval, totalBeatsElapsed: Int = 0) {
        startAtTime(startTime: startTime, totalBeatsElapsed: Double(totalBeatsElapsed))
    }

    func startAtTime(startTime: TimeInterval, totalBeatsElapsed: Double) {
        // A scheduled start is an explicit phase reset. Gameplay uses this when
        // playback begins, and it must rebase any free-running metronome started
        // from the standalone toggle.
        if !isPlaying {
            isPlaying = true
        }

        // Calculate current beat within measure (1-indexed)
        let beatsPerMeasure = timeSignature.beatsPerMeasure
        let completedBeats = Self.completedBeatCount(forTotalBeatsElapsed: totalBeatsElapsed)
        let beatInMeasure = completedBeats % beatsPerMeasure + 1
        currentBeat = beatInMeasure
        lastFiredBeat = Self.firstFiredBeatNumber(afterTotalBeatsElapsed: totalBeatsElapsed) - 1

        if isTestEnvironment {
            // In test environment, simulate start with provided timing
            simulateTestBeat(startTime: startTime, beatOffset: totalBeatsElapsed)
        } else {
            startTimerAtTime(startTime: startTime, totalBeatsElapsed: totalBeatsElapsed)
        }
    }

    func stop() {
        guard isPlaying else { return }

        isPlaying = false
        
        if !isTestEnvironment {
            stopTimer()
        }
        
        currentBeat = 1
        beatOffset = 0
        startTime = 0
        beatOriginTime = 0
        lastFiredBeat = 0
    }

    func toggle() {
        if isPlaying {
            stop()
        } else {
            start()
        }
    }

    // MARK: - Timer Management

    private func startTimer(initialBeatsElapsed: Int = 0) {
        stopTimer()

        // Record start time and initialize beat counter
        startTime = CFAbsoluteTimeGetCurrent() + audioSchedulingLeadTime
        beatOffset = initialBeatsElapsed
        beatOriginTime = startTime - (Double(beatOffset) * beatInterval)
        lastFiredBeat = initialBeatsElapsed

        scheduleBeatTimer(
            startTime: startTime,
            beatOffset: beatOffset,
            beatOriginTime: beatOriginTime,
            firstBeatNumber: initialBeatsElapsed + 1,
            referenceTime: CFAbsoluteTimeGetCurrent()
        )
    }

    private func startTimerAtTime(startTime: TimeInterval, totalBeatsElapsed: Double) {
        stopTimer()

        let currentTime = CFAbsoluteTimeGetCurrent()
        let delayUntilStart = startTime - currentTime
        let effectiveStartTime: TimeInterval
        let effectiveTotalBeatsElapsed: Double
        if delayUntilStart <= 0 {
            // Start time has already passed. Preserve phase by advancing the
            // elapsed beat count, while matching the previous behavior of using
            // "now" as the playback-time origin after a stale schedule.
            let elapsedSinceStart = currentTime - startTime
            effectiveStartTime = currentTime
            effectiveTotalBeatsElapsed = totalBeatsElapsed + (elapsedSinceStart / beatInterval)
        } else {
            effectiveStartTime = startTime
            effectiveTotalBeatsElapsed = totalBeatsElapsed
        }

        self.startTime = effectiveStartTime
        beatOffset = Self.completedBeatCount(forTotalBeatsElapsed: effectiveTotalBeatsElapsed)
        beatOriginTime = effectiveStartTime - (max(0, effectiveTotalBeatsElapsed) * beatInterval)
        let firstBeatNumber = Self.firstFiredBeatNumber(afterTotalBeatsElapsed: effectiveTotalBeatsElapsed)
        lastFiredBeat = firstBeatNumber - 1

        scheduleBeatTimer(
            startTime: effectiveStartTime,
            beatOffset: beatOffset,
            beatOriginTime: beatOriginTime,
            firstBeatNumber: firstBeatNumber,
            referenceTime: currentTime,
            onCancel: { Logger.debug("🕐 Scheduled timer cancelled") }
        )
    }

    private func scheduleBeatTimer(
        startTime: TimeInterval,
        beatOffset: Int,
        beatOriginTime: TimeInterval,
        firstBeatNumber: Int,
        referenceTime: TimeInterval,
        onCancel: (() -> Void)? = nil
    ) {
        let timer = DispatchSource.makeTimerSource(queue: timerQueue)
        beatTimer = timer
        let token = MetronomePlaybackToken()
        playbackToken = token

        // Use nanoseconds precision for accurate timing
        let nanoseconds = Int(beatInterval * 1_000_000_000)
        let schedule = MetronomeBeatSchedule(
            beatOriginTime: beatOriginTime,
            beatInterval: beatInterval,
            schedulingLeadTime: audioSchedulingLeadTime
        )
        let firstDeadline = schedule.timerDeadline(forBeatNumber: firstBeatNumber)
        let startDelayNanos = max(0, Int((firstDeadline - referenceTime) * 1_000_000_000))

        // Schedule first callback ahead of the precise start time, then repeat at beat intervals.
        timer.schedule(deadline: .now() + .nanoseconds(startDelayNanos), repeating: .nanoseconds(nanoseconds))

        let audioBeatHandler = onAudioBeat
        let timeSignature = timeSignature
        let beatCounter = MetronomeBeatCounter(firstBeatNumber: firstBeatNumber)
        timer.setEventHandler { [weak self] in
            guard token.isActive else { return }
            let firedBeatNumber = beatCounter.consumeNextBeatNumber()
            let idealBeatTime = schedule.audioTargetTime(forBeatNumber: firedBeatNumber)
            let beatToPlay = Self.beatInMeasure(forFiredBeatNumber: firedBeatNumber, timeSignature: timeSignature)
            let preciseAudioTime = Self.audioTime(forIdealBeatTime: idealBeatTime)
            audioBeatHandler?(beatToPlay, beatToPlay == 1, preciseAudioTime)

            Task { @MainActor in
                guard let self = self, token.isActive else { return }
                self.recordVisualBeat(
                    firedBeatNumber: firedBeatNumber,
                    idealBeatTime: idealBeatTime,
                    token: token
                )
            }
        }

        if let onCancel {
            timer.setCancelHandler(handler: onCancel)
        }

        timer.resume()
    }

    private func stopTimer() {
        playbackToken?.cancel()
        playbackToken = nil
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
    
    private func recordVisualBeat(
        firedBeatNumber: Int,
        idealBeatTime: CFAbsoluteTime,
        token: MetronomePlaybackToken
    ) {
        // SAFETY CHECK: Ensure we're still playing and haven't been stopped
        guard isPlaying else { 
            return 
        }

        lastFiredBeat = firedBeatNumber
        let beatToPlay = Self.beatInMeasure(forFiredBeatNumber: firedBeatNumber, timeSignature: timeSignature)
        self.handleVisualBeat(
            beatToPlay: beatToPlay,
            visualUpdateTime: idealBeatTime,
            token: token
        )
    }

    nonisolated static func beatInMeasure(forFiredBeatNumber beatNumber: Int, timeSignature: TimeSignature) -> Int {
        let beatsPerMeasure = max(timeSignature.beatsPerMeasure, 1)
        return (max(beatNumber, 1) - 1) % beatsPerMeasure + 1
    }

    nonisolated static func completedBeatCount(forTotalBeatsElapsed totalBeats: Double) -> Int {
        guard totalBeats.isFinite else { return 0 }
        return Int(floor(max(0, totalBeats) + 0.000_000_001))
    }

    nonisolated static func firstFiredBeatNumber(afterTotalBeatsElapsed totalBeats: Double) -> Int {
        guard totalBeats.isFinite else { return 1 }
        let clampedBeats = max(0, totalBeats)
        let nextBeatBoundary = Int(ceil(clampedBeats - 0.000_000_001))
        return max(1, nextBeatBoundary + 1)
    }

    nonisolated static func hostTime(
        forCFAbsoluteTime targetTime: CFAbsoluteTime,
        referenceCFTime: CFAbsoluteTime = CFAbsoluteTimeGetCurrent(),
        referenceHostTime: UInt64 = mach_absolute_time()
    ) -> UInt64 {
        let deltaSeconds = targetTime - referenceCFTime
        var timebaseInfo = mach_timebase_info_data_t()
        let timebaseResult = mach_timebase_info(&timebaseInfo)
        guard timebaseResult == KERN_SUCCESS else { return referenceHostTime }

        let deltaNanoseconds = deltaSeconds * Double(NSEC_PER_SEC)
        let deltaTicks = Int64(deltaNanoseconds * Double(timebaseInfo.denom) / Double(timebaseInfo.numer))
        if deltaTicks >= 0 {
            let addition = referenceHostTime.addingReportingOverflow(UInt64(deltaTicks))
            return addition.overflow ? UInt64.max : addition.partialValue
        }

        let subtraction = referenceHostTime.subtractingReportingOverflow(UInt64(-deltaTicks))
        // Return the actual converted target host time (reference − |delta|).
        // Returning referenceHostTime here would collapse every non-underflowing
        // past target onto "now", making small negative deltas indistinguishable
        // from zero and scheduling late callbacks against the reference instead
        // of the true target. Clamp to 0 only when the subtraction underflows
        // (target precedes the mach host-time epoch).
        return subtraction.overflow ? 0 : subtraction.partialValue
    }

    nonisolated static func audioTime(forIdealBeatTime idealBeatTime: CFAbsoluteTime) -> AVAudioTime? {
        let hostTime = Self.hostTime(forCFAbsoluteTime: idealBeatTime)
        let audioTime = AVAudioTime(hostTime: hostTime)
        guard audioTime.isHostTimeValid && hostTime > 0 else { return nil }
        return audioTime
    }

    private func handleVisualBeat(
        beatToPlay: Int,
        visualUpdateTime: CFAbsoluteTime,
        token: MetronomePlaybackToken
    ) {
        let isAccented = (beatToPlay == 1)

        // Use precise timing for sample-accurate audio synchronization
        let hasCallback = onBeat != nil
        let logMessage = "TimingEngine firing beat: \(beatToPlay), "
            + "isAccented: \(isAccented), "
            + "hasCallback: \(hasCallback)"
        Logger.audioDebug("⏰ \(logMessage)")
        // Update UI properties at the audible beat boundary, not at the early
        // scheduling callback.
        let visualDelay = max(0, visualUpdateTime - CFAbsoluteTimeGetCurrent())
        DispatchQueue.main.asyncAfter(deadline: .now() + visualDelay) {
            guard self.isPlaying, token.isActive else { return }
            self.onBeat?(beatToPlay, isAccented, nil)
            self.currentBeat = beatToPlay
        }
    }
    
    // MARK: - Synchronized Timing API
    
    /// Get current playback time - same time reference used for audio scheduling
    func getCurrentPlaybackTime() -> TimeInterval? {
        guard isPlaying else { return nil }
        return max(0, CFAbsoluteTimeGetCurrent() - startTime)
    }
    
    /// Get precise beat progress for visual synchronization
    func getCurrentBeatProgress(timeSignature: TimeSignature) -> (totalBeats: Double, beatInMeasure: Double)? {
        guard let elapsedTime = getCurrentPlaybackTime() else { return nil }
        
        let totalBeats = elapsedTime / beatInterval
        let beatsPerMeasure = Double(timeSignature.beatsPerMeasure)
        let beatInMeasure = totalBeats.truncatingRemainder(dividingBy: beatsPerMeasure)
        
        return (totalBeats: totalBeats, beatInMeasure: beatInMeasure)
    }
    
    // MARK: - Test Environment Simulation
    
    private func simulateTestBeat(startTime: TimeInterval = 0, beatOffset: Double = 0) {
        // In test environment, immediately fire a beat callback to allow tests to verify functionality
        Logger.audioPlayback("Test environment - simulating beat callback")
        let isAccented = (currentBeat == 1)

        let effectiveStartTime = startTime == 0 ? CFAbsoluteTimeGetCurrent() : startTime
        self.startTime = effectiveStartTime
        self.beatOffset = Self.completedBeatCount(forTotalBeatsElapsed: beatOffset)
        beatOriginTime = effectiveStartTime - (max(0, beatOffset) * beatInterval)
        lastFiredBeat = Self.firstFiredBeatNumber(afterTotalBeatsElapsed: beatOffset) - 1

        // Ensure state is published on main thread for Combine subscribers
        Task { @MainActor in
            // Guard: Don't update beat if playback has stopped to avoid publishing stale state
            guard isPlaying else { return }

            // Fire the beat callback
            onBeat?(currentBeat, isAccented, nil)

            // Update beat counter on main thread to trigger @Published
            currentBeat += 1
            if currentBeat > timeSignature.beatsPerMeasure {
                currentBeat = 1
            }
        }
    }
}
