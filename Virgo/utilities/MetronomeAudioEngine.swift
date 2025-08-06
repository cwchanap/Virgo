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
        Task { @MainActor in
            self.stop()
            self.audioEngine.detach(self.playerNode)
        }
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
            try audioSession.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try audioSession.setActive(true)
            #endif

            // Attach and connect player node
            audioEngine.attach(playerNode)
            audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: nil)

            // Start the audio engine
            try audioEngine.start()

            Logger.audioPlayback("Audio engine setup completed successfully")

        } catch {
            Logger.audioPlayback("Failed to setup audio engine: \(error.localizedDescription)")
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

            guard let buffer = AVAudioPCMBuffer(pcmFormat: audioFile.processingFormat, frameCapacity: frameCount) else {
                try? FileManager.default.removeItem(at: tempURL)
                throw AudioEngineError.bufferCreationFailed
            }

            try audioFile.read(into: buffer)

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

    func playTick(volume: Float = 1.0, isAccented: Bool = false) {
        guard !isTestEnvironment else { return }

        do {
            let buffer = try getTickerBuffer()
            let adjustedVolume = isAccented ? min(volume * 1.3, 1.0) : volume

            playerNode.scheduleBuffer(buffer) {
                // Buffer completed playback
            }

            playerNode.volume = adjustedVolume

            if !playerNode.isPlaying {
                playerNode.play()
            }

        } catch {
            Logger.audioPlayback("Failed to play tick: \(error.localizedDescription)")
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
