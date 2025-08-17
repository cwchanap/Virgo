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

// MARK: - Audio Engine
@MainActor
class MetronomeAudioEngine: ObservableObject {
    private let logger = Logger()

    private var audioEngine: AVAudioEngine
    private var playerNode: AVAudioPlayerNode
    #if os(iOS)
    private var audioSession: AVAudioSession
    #endif

    // Audio buffer cache
    private var cachedTickerBuffer: AVAudioPCMBuffer?

    // Configuration
    private let isTestEnvironment: Bool

    init() {
        self.isTestEnvironment = ProcessInfo.processInfo.arguments.contains("XCTestConfigurationFilePath")
        self.audioEngine = AVAudioEngine()
        self.playerNode = AVAudioPlayerNode()
        #if os(iOS)
        self.audioSession = AVAudioSession.sharedInstance()
        #endif

        setupAudioEngine()
    }

    deinit {
        // Perform cleanup synchronously in deinit to avoid closure capture issues
        playerNode.stop()
        audioEngine.stop()
        audioEngine.detach(playerNode)
    }

    // MARK: - Audio Engine Setup

    private func setupAudioEngine() {
        guard !isTestEnvironment else {
            Logger.audioPlayback("Test environment detected - skipping audio engine setup")
            return
        }

        do {
            // Configure audio session for iOS
            #if os(iOS)
            Logger.audioPlayback("Setting up iOS audio session...")
            try audioSession.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try audioSession.setActive(true)
            Logger.audioPlayback("iOS audio session configured successfully")
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

    // MARK: - Audio Buffer Management

    private func getTickerBuffer() throws -> AVAudioPCMBuffer {
        if let existingBuffer = cachedTickerBuffer {
            return existingBuffer
        }

        guard let tickerData = NSDataAsset(name: "ticker") else {
            throw AudioEngineError.assetNotFound
        }

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
        guard !isTestEnvironment else { return }

        // Ensure audio engine is running before attempting playback
        if !audioEngine.isRunning {
            do {
                try audioEngine.start()
            } catch {
                Logger.audioPlayback("🔊 Failed to restart audio engine: \(error.localizedDescription)")
                return
            }
        }

        do {
            let buffer = try getTickerBuffer()
            
            // Sanitize volume: replace NaN/infinite with safe default
            let sanitizedVolume = volume.isNaN || volume.isInfinite ? 0.0 : volume
            
            // Apply accent multiplier to sanitized volume
            let accentedVolume = isAccented ? sanitizedVolume * 1.3 : sanitizedVolume
            
            // Clamp the final volume between 0.0 and 1.0
            let adjustedVolume = max(0.0, min(1.0, accentedVolume))

            // Verify and validate AVAudioTime timebase for sample-accurate scheduling
            if let scheduledTime = atTime {
                // Verify the timebase is valid and compatible with our audio engine
                let hostTime = scheduledTime.hostTime
                if hostTime > 0 && scheduledTime.isHostTimeValid {
                    
                    // Use the validated time for precise scheduling
                    playerNode.scheduleBuffer(buffer, at: scheduledTime, options: [], completionHandler: nil)
                    Logger.audioPlayback("🔊 Scheduled buffer at precise time: \(hostTime)")
                } else {
                    // Fallback to immediate playback if time is invalid
                    playerNode.scheduleBuffer(buffer)
                    Logger.audioPlayback("🔊 Invalid AVAudioTime - using immediate playback fallback")
                }
            } else {
                playerNode.scheduleBuffer(buffer) // Immediate playback (fallback)
            }
            
            playerNode.volume = adjustedVolume

            // Always ensure the player node is playing after scheduling a buffer
            if !playerNode.isPlaying {
                playerNode.play()
            }

        } catch {
            Logger.audioPlayback("🔊 Failed to play tick: \(error.localizedDescription)")
        }
    }

    func stop() {
        guard !isTestEnvironment else { return }

        playerNode.stop()

        do {
            audioEngine.stop()
            #if os(iOS)
            try audioSession.setActive(false)
            #endif
        } catch {
            Logger.audioPlayback("Failed to stop audio engine: \(error.localizedDescription)")
        }
    }

    func resume() {
        guard !isTestEnvironment else { return }

        do {
            #if os(iOS)
            try audioSession.setActive(true)
            #endif

            if !audioEngine.isRunning {
                try audioEngine.start()
            }

        } catch {
            Logger.audioPlayback("Failed to resume audio engine: \(error.localizedDescription)")
        }
    }
}

// MARK: - Errors

enum AudioEngineError: Error, LocalizedError {
    case assetNotFound
    case bufferCreationFailed
    case loadingFailed(Error)

    var errorDescription: String? {
        switch self {
        case .assetNotFound:
            return "Ticker audio asset not found"
        case .bufferCreationFailed:
            return "Failed to create audio buffer"
        case .loadingFailed(let error):
            return "Failed to load audio buffer: \(error.localizedDescription)"
        }
    }
}
