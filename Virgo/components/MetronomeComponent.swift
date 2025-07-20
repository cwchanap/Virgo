//
//  MetronomeComponent.swift
//  Virgo
//
//  Created by Chan Wai Chan on 13/7/2025.
//

import SwiftUI
import AVFoundation
import os.log

#if canImport(AVFAudio)
import AVFAudio
#endif

actor AudioBufferCache {
    static let shared = AudioBufferCache()
    
    private var cachedTickerBuffer: AVAudioPCMBuffer?
    
    private init() {}
    
    func getTickerBuffer() throws -> AVAudioPCMBuffer {
        if let existingBuffer = cachedTickerBuffer {
            return existingBuffer
        }
        
        guard let tickerData = NSDataAsset(name: "ticker") else {
            throw AudioBufferError.assetNotFound
        }
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("ticker_cached.wav")
        
        do {
            try tickerData.data.write(to: tempURL)
            
            let audioFile = try AVAudioFile(forReading: tempURL)
            let frameCount = AVAudioFrameCount(audioFile.length)
            
            guard let buffer = AVAudioPCMBuffer(pcmFormat: audioFile.processingFormat, frameCapacity: frameCount) else {
                try? FileManager.default.removeItem(at: tempURL)
                throw AudioBufferError.bufferCreationFailed
            }
            
            try audioFile.read(into: buffer)
            
            // Cache the buffer for future use
            cachedTickerBuffer = buffer
            
            // Clean up temporary file
            try? FileManager.default.removeItem(at: tempURL)
            
            return buffer
            
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            throw AudioBufferError.loadingFailed(error)
        }
    }
}

enum AudioBufferError: Error, LocalizedError {
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

class MetronomeEngine: ObservableObject {
    @Published var isEnabled = false
    @Published var currentBeat = 0
    @Published var volume: Float = 0.7
    
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var bpm: Int = 120
    private var timeSignature: TimeSignature = .fourFour
    private var tickerBuffer: AVAudioPCMBuffer?
    private var startTime: AVAudioTime?
    private var nextBeatTime: AVAudioTime?
    private var sampleRate: Double = 44100.0
    private var beatTimer: Timer?
    
    // Use AudioBufferCache singleton for thread-safe buffer management
    private static let bufferCache = AudioBufferCache.shared
    
    init() {
        // Check if we're in a test, preview, or simulator environment
        let isTestEnvironment = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
                                ProcessInfo.processInfo.arguments.contains("UITesting") ||
                                NSClassFromString("XCTest") != nil
        
        let isPreviewEnvironment = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" ||
                                  ProcessInfo.processInfo.arguments.contains("Previews")
        
        #if targetEnvironment(simulator)
        let isSimulator = true
        #else
        let isSimulator = false
        #endif
        
        if isTestEnvironment || isPreviewEnvironment {
            return
        }
        
        if isSimulator {
            setupMinimalAudio()
            return
        }
        
        // Initialize audio components safely for production
        configureAudioSession()
        loadTickerSoundSync() // Load ticker synchronously first to get its format
        setupAudioEngine() // Then setup engine to match ticker format
    }
    
    private func configureAudioSession() {
        #if os(iOS)
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try audioSession.setActive(true)
        } catch {
            // Don't throw - this should be non-fatal
        }
        #endif
    }
    
    deinit {
        stop()
        
        // Safely cleanup audio resources
        if let engine = audioEngine {
            if engine.isRunning {
                engine.stop()
            }
            audioEngine = nil
        }
        
        playerNode = nil
        tickerBuffer = nil
        beatTimer?.invalidate()
        beatTimer = nil
    }
    
    private func setupMinimalAudio() {
        // Minimal setup for simulator to prevent ViewBridge errors
        // Just set sample rate without creating actual audio components
        sampleRate = 44100.0
    }
    
    private func setupAudioEngine() {
        audioEngine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()
        
        guard let engine = audioEngine, let player = playerNode else { 
            return 
        }
        
        engine.attach(player)
        
        // Use the ticker buffer's format if available, otherwise fallback to standard format
        let format: AVAudioFormat
        if let buffer = tickerBuffer {
            format = buffer.format
        } else {
            // Fallback to mono format (most common for audio assets)
            format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        }
        
        sampleRate = format.sampleRate
        engine.connect(player, to: engine.mainMixerNode, format: format)
        
        // Prepare the engine
        engine.prepare()
        
        do {
            try engine.start()
        } catch {
            // Engine start failure is non-fatal - metronome can still function for basic operations
        }
    }
    
    private func loadTickerSoundSync() {
        // Synchronous loading for initialization
        do {
            guard let tickerData = NSDataAsset(name: "ticker") else {
                return
            }
            
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("ticker_init.wav")
            
            try tickerData.data.write(to: tempURL)
            
            let audioFile = try AVAudioFile(forReading: tempURL)
            let frameCount = AVAudioFrameCount(audioFile.length)
            
            guard let buffer = AVAudioPCMBuffer(pcmFormat: audioFile.processingFormat, frameCapacity: frameCount) else {
                try? FileManager.default.removeItem(at: tempURL)
                return
            }
            
            try audioFile.read(into: buffer)
            
            self.tickerBuffer = buffer
            
            // Clean up temporary file
            try? FileManager.default.removeItem(at: tempURL)
            
        } catch {
            // Silently handle errors
        }
    }
    
    private func loadTickerSound() {
        Task {
            do {
                let buffer = try await Self.bufferCache.getTickerBuffer()
                await MainActor.run {
                    self.tickerBuffer = buffer
                }
            } catch {
                // Silently handle errors
            }
        }
    }
    
    func configure(bpm: Int, timeSignature: TimeSignature) {
        self.bpm = bpm
        self.timeSignature = timeSignature
    }
    
    func start() {
        guard !isEnabled else { return }
        
        isEnabled = true
        currentBeat = 0
        
        // Start timer-based metronome
        startBeatTimer()
        
        // Only perform audio operations if player is available
        if let player = playerNode, let engine = audioEngine {
            do {
                // Ensure engine is running
                if !engine.isRunning {
                    try engine.start()
                }
                
                // Start the player if not already playing
                if !player.isPlaying {
                    player.play()
                }
            } catch {
                // Continue in silent mode - just update UI state
            }
        }
    }
    
    func stop() {
        isEnabled = false
        currentBeat = 0
        beatTimer?.invalidate()
        beatTimer = nil
        playerNode?.stop()
        startTime = nil
        nextBeatTime = nil
    }
    
    func toggle() {
        if isEnabled {
            stop()
        } else {
            start()
        }
    }
    
    // Test method to play a single click for debugging
    func testClick() {
        playClick()
    }
    
    private func startBeatTimer() {
        let interval = 60.0 / Double(bpm) // Time between beats in seconds
        
        beatTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self = self, self.isEnabled else { return }
            
            // Play the click sound
            self.playClick()
            
            // Update beat counter
            self.currentBeat = (self.currentBeat + 1) % self.timeSignature.beatsPerMeasure
        }
    }
    
    private func playClick() {
        guard let player = playerNode, let buffer = tickerBuffer else { 
            return 
        }
        
        let isAccent = currentBeat == 0
        let accentMultiplier: Float = isAccent ? 1.3 : 1.0
        let effectiveVolume = volume * accentMultiplier
        
        // Set volume directly on the player node
        player.volume = effectiveVolume
        
        // Schedule the buffer for immediate playback
        player.scheduleBuffer(buffer, completionHandler: nil)
    }
    
    // Static factory method for safe preview initialization
    static func forPreview() -> MetronomeEngine {
        let engine = MetronomeEngine()
        return engine
    }
}

struct MetronomeControlsView: View {
    @ObservedObject var metronome: MetronomeEngine
    let track: DrumTrack
    @Binding var isPlaying: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            // Metronome toggle button
            Button(action: metronome.toggle) {
                Image(systemName: metronome.isEnabled ? "metronome.fill" : "metronome")
                    .font(.title3)
                    .foregroundColor(metronome.isEnabled ? .purple : .gray)
            }
            .disabled(isPlaying)
            
            // Beat indicator
            HStack(spacing: 4) {
                ForEach(0..<track.timeSignature.beatsPerMeasure, id: \.self) { beat in
                    Circle()
                        .frame(width: 8, height: 8)
                        .foregroundColor(
                            metronome.isEnabled && metronome.currentBeat == beat ? 
                            (beat == 0 ? .purple : .white) : .gray.opacity(0.3)
                        )
                        .scaleEffect(
                            metronome.isEnabled && metronome.currentBeat == beat ? 1.2 : 1.0
                        )
                        .animation(.easeInOut(duration: 0.1), value: metronome.currentBeat)
                }
            }
            
            // Volume control
            if metronome.isEnabled {
                HStack(spacing: 8) {
                    Image(systemName: "speaker.fill")
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    Slider(value: $metronome.volume, in: 0.0...1.0)
                        .frame(width: 60)
                        .accentColor(.purple)
                }
            }
        }
        .onChange(of: isPlaying) { playing in
            if !playing && metronome.isEnabled {
                metronome.stop()
            }
        }
    }
}

struct MetronomeComponent: View {
    @StateObject private var metronome = MetronomeEngine()
    let track: DrumTrack
    @Binding var isPlaying: Bool
    
    var body: some View {
        MetronomeControlsView(metronome: metronome, track: track, isPlaying: $isPlaying)
            .onAppear {
                metronome.configure(bpm: track.bpm, timeSignature: track.timeSignature)
            }
    }
}

struct MetronomeControlsInGameplay: View {
    @ObservedObject var metronome: MetronomeEngine
    let track: DrumTrack
    @Binding var isPlaying: Bool
    
    var body: some View {
        MetronomeControlsView(metronome: metronome, track: track, isPlaying: $isPlaying)
    }
}

#Preview {
    MetronomeComponent(track: DrumTrack.sampleData.first!, isPlaying: .constant(false))
        .padding()
        .background(Color.black)
}
