//
//  MetronomeAudioEngine.swift
//  Virgo
//
//  Created by Claude Code on 4/8/2025.
//

import AVFoundation
import os.log

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Audio Driver Protocol
@MainActor
protocol AudioDriverProtocol {
    func playTick(volume: Float, isAccented: Bool, atTime: AVAudioTime?)
    func stop()
    func resume()
    func convertToAudioEngineTime(_ cfTime: CFAbsoluteTime) -> AVAudioTime?
}

// MARK: - Audio Engine
@MainActor
class MetronomeAudioEngine: ObservableObject, AudioDriverProtocol {
    private let logger = Logger()

    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    #if os(iOS)
    private var audioSession: AVAudioSession?
    #endif

    // Audio buffer cache
    private var cachedTickerBuffer: AVAudioPCMBuffer?

    // Configuration
    private let isTestEnvironment: Bool

    // Interruption handling callback
    var onInterruption: ((Bool) -> Void)?

    init() {
        self.isTestEnvironment = TestEnvironment.isRunningTests

        if !isTestEnvironment {
            // Normal runtime - initialize audio components
            self.audioEngine = AVAudioEngine()
            self.playerNode = AVAudioPlayerNode()
            #if os(iOS)
            self.audioSession = AVAudioSession.sharedInstance()
            #endif
            setupAudioEngine()
            setupAudioSessionNotifications()
        } else {
            // Test environment - don't create any audio objects to prevent crashes
            self.audioEngine = nil
            self.playerNode = nil
            #if os(iOS)
            self.audioSession = nil
            #endif
            Logger.audioPlayback("Test environment - no audio objects created to prevent crashes")
        }
    }

    deinit {
        // Perform cleanup synchronously in deinit to avoid closure capture issues
        guard !isTestEnvironment, let audioEngine = audioEngine, let playerNode = playerNode else { return }
        
        playerNode.stop()
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.detach(playerNode)
    }

    // MARK: - Audio Engine Setup

    private func setupAudioEngine() {
        guard !isTestEnvironment, let audioEngine = audioEngine, let playerNode = playerNode else {
            Logger.audioPlayback("Test environment detected - skipping audio engine setup")
            return
        }

        do {
            // Configure audio session for iOS
            #if os(iOS)
            if let audioSession = audioSession {
                Logger.audioPlayback("Setting up iOS audio session...")
                try audioSession.setCategory(.playback, mode: .default, options: [.mixWithOthers])
                try audioSession.setActive(true)
                Logger.audioPlayback("iOS audio session configured successfully")
            }
            #endif

            // Attach and connect player node
            Logger.audioPlayback("Attaching and connecting audio player node...")
            audioEngine.attach(playerNode)
            
            // Get the output format from the main mixer to ensure compatibility
            let outputFormat = audioEngine.mainMixerNode.outputFormat(forBus: 0)
            Logger.audioPlayback("Main mixer output format: \(outputFormat)")
            audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: outputFormat)

            // Start the audio engine
            Logger.audioPlayback("Starting audio engine...")
            try audioEngine.start()

            Logger.audioPlayback("Audio engine setup completed successfully")

        } catch {
            Logger.audioPlayback("Failed to setup audio engine: \(error.localizedDescription)")
            // Continue without audio instead of crashing
        }
    }

    // MARK: - Audio Session Notifications

    private func setupAudioSessionNotifications() {
        #if os(iOS)
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            self?.handleAudioInterruption(notification)
        }

        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            self?.handleRouteChange(notification)
        }
        #endif
    }

    #if os(iOS)
    private func handleAudioInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        switch type {
        case .began:
            // Interruption began - pause playback
            Logger.audioPlayback("Audio session interruption began (e.g., phone call)")
            playerNode?.pause()
            onInterruption?(true)

        case .ended:
            // Interruption ended - check if we should resume
            if let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    Logger.audioPlayback("Audio session interruption ended - resuming")
                    do {
                        try audioEngine?.start()
                        playerNode?.play()
                        onInterruption?(false)
                    } catch {
                        Logger.audioPlayback("Failed to resume after interruption: \(error.localizedDescription)")
                    }
                }
            }

        @unknown default:
            break
        }
    }

    private func handleRouteChange(_ notification: Notification) {
        guard let info = notification.userInfo,
              let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }

        switch reason {
        case .oldDeviceUnavailable:
            // Headphones unplugged - pause playback
            Logger.audioPlayback("Audio route changed - old device unavailable (headphones unplugged)")
            playerNode?.pause()
            onInterruption?(true)

        case .newDeviceAvailable:
            Logger.audioPlayback("Audio route changed - new device available")

        default:
            break
        }
    }
    #endif

    // MARK: - Audio Buffer Management

    private func getTickerBuffer() throws -> AVAudioPCMBuffer {
        if let existingBuffer = cachedTickerBuffer {
            return existingBuffer
        }
        
        guard let playerNode = playerNode else {
            throw AudioEngineError.audioEngineNotAvailable
        }

        Logger.audioPlayback("🔊 Looking for ticker asset...")
        guard let tickerData = NSDataAsset(name: "ticker") else {
            Logger.audioPlayback("🔊 ERROR: ticker asset not found in bundle!")
            throw AudioEngineError.assetNotFound
        }
        Logger.audioPlayback("🔊 Ticker asset found, data size: \(tickerData.data.count) bytes")

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("ticker_cached.wav")

        do {
            try tickerData.data.write(to: tempURL)

            let audioFile = try AVAudioFile(forReading: tempURL)
            let frameCount = AVAudioFrameCount(audioFile.length)
            
            Logger.audioPlayback("🔊 Audio file format: \(audioFile.processingFormat)")

            // Use the player node's output format to ensure compatibility
            let targetFormat = playerNode.outputFormat(forBus: 0)
            Logger.audioPlayback("🔊 Player node output format: \(targetFormat)")
            
            // Create buffer with the target format if different from file format
            let bufferFormat = targetFormat.channelCount > 0 ? targetFormat : audioFile.processingFormat
            Logger.audioPlayback("🔊 Using buffer format: \(bufferFormat)")
            
            guard let buffer = AVAudioPCMBuffer(pcmFormat: bufferFormat, frameCapacity: frameCount) else {
                try? FileManager.default.removeItem(at: tempURL)
                throw AudioEngineError.bufferCreationFailed
            }

            // If formats don't match, we need to convert
            if !audioFile.processingFormat.isEqual(bufferFormat) {
                Logger.audioPlayback("🔊 Format conversion needed from \(audioFile.processingFormat) to \(bufferFormat)")
                
                // Create a converter
                guard let converter = AVAudioConverter(from: audioFile.processingFormat, to: bufferFormat) else {
                    try? FileManager.default.removeItem(at: tempURL)
                    throw AudioEngineError.bufferCreationFailed
                }
                
                // Read the original data
                guard let originalBuffer = AVAudioPCMBuffer(pcmFormat: audioFile.processingFormat, frameCapacity: frameCount) else {
                    try? FileManager.default.removeItem(at: tempURL)
                    throw AudioEngineError.bufferCreationFailed
                }
                
                try audioFile.read(into: originalBuffer)
                
                // Convert to target format
                var error: NSError?
                let status = converter.convert(to: buffer, error: &error) { _, outStatus in
                    outStatus.pointee = .haveData
                    return originalBuffer
                }
                
                if status == .error {
                    throw error ?? AudioEngineError.bufferCreationFailed
                }
                
            } else {
                // Formats match, read directly
                try audioFile.read(into: buffer)
            }

            // Cache the buffer for future use
            cachedTickerBuffer = buffer
            Logger.audioPlayback("🔊 Buffer created successfully - frameLength: \(buffer.frameLength), channels: \(buffer.format.channelCount)")

            // Clean up temporary file
            try? FileManager.default.removeItem(at: tempURL)

            return buffer

        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            throw AudioEngineError.loadingFailed(error)
        }
    }

    // MARK: - Playback Control

    func playTick(volume: Float = 1.0, isAccented: Bool = false, atTime: AVAudioTime? = nil) {
        Logger.audioPlayback("🔊 playTick() called - volume: \(volume), isAccented: \(isAccented), atTime: \(atTime?.description ?? "immediate")")
        guard !isTestEnvironment else { 
            Logger.audioPlayback("🔊 Skipping playTick - test environment detected")
            return 
        }

        guard let audioEngine = audioEngine, let playerNode = playerNode else {
            Logger.audioPlayback("🔊 Audio engine not available - test environment")
            return
        }
        
        // Ensure audio engine is running before attempting playback
        Logger.audioPlayback("🔊 Audio engine running state: \(audioEngine.isRunning)")
        if !audioEngine.isRunning {
            Logger.audioPlayback("🔊 Audio engine not running - attempting to start...")
            do {
                try audioEngine.start()
                Logger.audioPlayback("🔊 Audio engine restarted successfully")
            } catch {
                Logger.audioPlayback("🔊 Failed to restart audio engine: \(error.localizedDescription)")
                return
            }
        }

        do {
            Logger.audioPlayback("🔊 Getting ticker buffer...")
            let buffer = try getTickerBuffer()
            Logger.audioPlayback("🔊 Ticker buffer obtained successfully")
            
            // Sanitize volume: replace NaN/infinite with safe default
            let sanitizedVolume = volume.isNaN || volume.isInfinite ? 0.0 : volume
            
            // Apply accent multiplier to sanitized volume
            let accentedVolume = isAccented ? sanitizedVolume * 1.3 : sanitizedVolume
            
            // Clamp the final volume between 0.0 and 1.0
            let adjustedVolume = max(0.0, min(1.0, accentedVolume))
            Logger.audioPlayback(
                "🔊 Volume processing: original=\(volume), sanitized=\(sanitizedVolume), " +
                "accented=\(accentedVolume), final=\(adjustedVolume)"
            )

            // Verify buffer has audio data
            Logger.audioPlayback("🔊 About to schedule buffer - frameLength: \(buffer.frameLength), format: \(buffer.format)")
            
            // Check if buffer actually has audio data
            if buffer.frameLength == 0 {
                Logger.audioPlayback("🔊 ERROR: Buffer has zero frame length - no audio data!")
                return
            }
            
            // Verify and validate AVAudioTime timebase for sample-accurate scheduling
            if let scheduledTime = atTime {
                // Verify the timebase is valid and compatible with our audio engine
                let hostTime = scheduledTime.hostTime
                if hostTime > 0 && scheduledTime.isHostTimeValid {
                    
                    // Use the validated time for precise scheduling
                    playerNode.scheduleBuffer(buffer, at: scheduledTime, options: [], completionHandler: { [weak self] in
                        Logger.audioPlayback("🔊 Buffer playback completed")
                    })
                    Logger.audioPlayback("🔊 Scheduled buffer at precise time: \(hostTime) with \(buffer.frameLength) frames")
                } else {
                    // Fallback to immediate playback if time is invalid
                    playerNode.scheduleBuffer(buffer, completionHandler: { [weak self] in
                        Logger.audioPlayback("🔊 Buffer playback completed (immediate)")
                    })
                    Logger.audioPlayback("🔊 Invalid AVAudioTime - using immediate playback fallback")
                }
            } else {
                playerNode.scheduleBuffer(buffer, completionHandler: { [weak self] in
                    Logger.audioPlayback("🔊 Buffer playback completed (no time)")
                })
                Logger.audioPlayback("🔊 Scheduled buffer immediately with \(buffer.frameLength) frames")
            }
            
            playerNode.volume = adjustedVolume

            // Always ensure the player node is playing after scheduling a buffer
            Logger.audioPlayback("🔊 Player node playing state: \(playerNode.isPlaying)")
            if !playerNode.isPlaying {
                Logger.audioPlayback("🔊 Starting player node...")
                playerNode.play()
                Logger.audioPlayback("🔊 Player node started - new state: \(playerNode.isPlaying)")
            }

        } catch {
            Logger.audioPlayback("🔊 Failed to play tick: \(error.localizedDescription)")
        }
        Logger.audioPlayback("🔊 playTick() completed")
    }

    func stop() {
        guard !isTestEnvironment, let audioEngine = audioEngine, let playerNode = playerNode else { return }

        playerNode.stop()

        do {
            audioEngine.stop()
            #if os(iOS)
            if let audioSession = audioSession {
                try audioSession.setActive(false)
            }
            #endif
        } catch {
            Logger.audioPlayback("Failed to stop audio engine: \(error.localizedDescription)")
        }
    }

    func resume() {
        guard !isTestEnvironment, let audioEngine = audioEngine else { return }

        do {
            #if os(iOS)
            if let audioSession = audioSession {
                try audioSession.setActive(true)
            }
            #endif

            if !audioEngine.isRunning {
                try audioEngine.start()
            }

        } catch {
            Logger.audioPlayback("Failed to resume audio engine: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Time Conversion
    
    /// Convert CFAbsoluteTime (metronome timebase) to AVAudioEngine timeline
    /// This ensures sample-accurate synchronization between metronome and external audio
    func convertToAudioEngineTime(_ cfTime: CFAbsoluteTime) -> AVAudioTime? {
        guard !isTestEnvironment, let audioEngine = audioEngine, audioEngine.isRunning else { return nil }
        
        // Get current times from both domains
        let currentCFTime = CFAbsoluteTimeGetCurrent()
        let currentHostTime = mach_absolute_time()
        
        // Calculate time offset from current moment
        let timeOffset = cfTime - currentCFTime
        
        // Convert time offset to host time units (nanoseconds)
        var timebaseInfo = mach_timebase_info_data_t()
        mach_timebase_info(&timebaseInfo)
        let nanosPerTick = Double(timebaseInfo.numer) / Double(timebaseInfo.denom)
        let offsetNanos = timeOffset * 1_000_000_000.0 // Convert seconds to nanoseconds
        let hostTimeOffset = UInt64(offsetNanos / nanosPerTick)
        
        // Calculate target host time
        let targetHostTime = currentHostTime + hostTimeOffset
        
        // Create AVAudioTime for the target host time
        return AVAudioTime(hostTime: targetHostTime)
    }
}

// MARK: - Errors

enum AudioEngineError: Error, LocalizedError {
    case assetNotFound
    case bufferCreationFailed
    case loadingFailed(Error)
    case audioEngineNotAvailable

    var errorDescription: String? {
        switch self {
        case .assetNotFound:
            return "Ticker audio asset not found"
        case .bufferCreationFailed:
            return "Failed to create audio buffer"
        case .loadingFailed(let error):
            return "Failed to load audio buffer: \(error.localizedDescription)"
        case .audioEngineNotAvailable:
            return "Audio engine not available in test environment"
        }
    }
}
