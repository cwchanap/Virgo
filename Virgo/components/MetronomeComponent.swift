// swiftlint:disable file_length type_body_length
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

struct MetronomeConfiguration {
    static let defaultSampleRate: Double = 44100.0
    static let accentMultiplier: Float = 1.3
    static let uiUpdateThreshold = 4
    static let maxBPMForSlowUpdate = 60
    static let mediumBPMThreshold = 120
}

class MetronomeEngine: ObservableObject {
    @Published var isEnabled = false
    @Published var currentBeat = 0  // UI-only, updated less frequently
    @Published var volume: Float = 0.7
    
    // Thread-safe beat counter for audio logic
    private let beatCounterQueue = DispatchQueue(label: "com.virgo.metronome.beatCounter")
    private var _internalCurrentBeat = 0
    
    private var internalCurrentBeat: Int {
        get { beatCounterQueue.sync { _internalCurrentBeat } }
        set { beatCounterQueue.sync { _internalCurrentBeat = newValue } }
    }
    
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var bpm: Int = 120
    private var timeSignature: TimeSignature = .fourFour
    private var tickerBuffer: AVAudioPCMBuffer?
    private var startTime: AVAudioTime?
    private var sampleRate: Double = MetronomeConfiguration.defaultSampleRate
    private var beatTimer: Timer?
    private var dispatchTimer: DispatchSourceTimer?
    private var displayLink: CADisplayLink?
    private var nextBeatTime: TimeInterval = 0
    private var metronomeStartTime: TimeInterval = 0
    private var beatCount: Int = 0
    
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
        
        // Enhanced resource cleanup
        playerNode?.stop()
        if let engine = audioEngine, engine.isRunning {
            engine.stop()
        }
        
        // Explicit nil assignments
        audioEngine = nil
        playerNode = nil
        tickerBuffer = nil
        
        beatTimer?.invalidate()
        beatTimer = nil
        dispatchTimer?.cancel()
        dispatchTimer = nil
        displayLink?.invalidate()
        displayLink = nil
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
            Logger.audioPlayback("Audio engine start failed: \(error.localizedDescription)")
            // Continue with visual-only metronome
            self.audioEngine = nil
            self.playerNode = nil
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
            Logger.audioPlayback("Failed to load ticker sound: \(error.localizedDescription)")
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
                Logger.audioPlayback("Failed to load ticker buffer from cache: \(error.localizedDescription)")
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
        internalCurrentBeat = 0
        
        // Start timer-based metronome
        startBeatTimer()
        
        // Move audio engine operations to background queue to avoid blocking main thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // Only perform audio operations if player is available
            if let player = self.playerNode, let engine = self.audioEngine {
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
                    Logger.audioPlayback("Audio playback failed: \(error.localizedDescription)")
                    // Continue in silent mode - just update UI state
                }
            }
        }
    }
    
    func stop() {
        isEnabled = false
        currentBeat = 0
        internalCurrentBeat = 0
        beatTimer?.invalidate()
        beatTimer = nil
        dispatchTimer?.cancel()
        dispatchTimer = nil
        displayLink?.invalidate()
        displayLink = nil
        playerNode?.stop()
        startTime = nil
        nextBeatTime = 0
        metronomeStartTime = 0
        beatCount = 0
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
        
        // Stop any existing timer first
        beatTimer?.invalidate()
        
        metronomeStartTime = CACurrentMediaTime()
        beatCount = 0
        
        // Use DispatchSourceTimer for better threading control
        dispatchTimer?.cancel()
        
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "com.virgo.metronome", qos: .userInitiated))
        dispatchTimer = timer
        
        timer.schedule(deadline: .now(), repeating: interval)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            guard self.isEnabled else { 
                timer.cancel()
                return 
            }
            
            self.beatCount += 1
            
            // Update internal beat counter for audio logic
            self.internalCurrentBeat = (self.internalCurrentBeat + 1) % self.timeSignature.beatsPerMeasure
            
            // Play the click sound
            self.playClick()
            
            // Adaptive UI update frequency based on BPM
            let updateInterval: TimeInterval = self.bpm <= MetronomeConfiguration.maxBPMForSlowUpdate ? 0.5 :
                                              (self.bpm <= MetronomeConfiguration.mediumBPMThreshold ? 0.25 : 0.15)
            let shouldUpdate = self.internalCurrentBeat == 0 || 
                              self.beatCount % MetronomeConfiguration.uiUpdateThreshold == 0 ||
                              CACurrentMediaTime() - self.metronomeStartTime >= updateInterval
            
            if shouldUpdate {
                DispatchQueue.main.async {
                    self.currentBeat = self.internalCurrentBeat
                }
            }
        }
        
        timer.resume()
    }
    
    private func playClick() {
        guard let player = playerNode, let buffer = tickerBuffer else { 
            return 
        }
        
        // Use internal beat counter for audio logic to avoid UI dependency
        let isAccent = internalCurrentBeat == 0
        let accentMultiplier: Float = isAccent ? MetronomeConfiguration.accentMultiplier : 1.0
        let effectiveVolume = volume * accentMultiplier
        
        // Move audio operations to background queue to avoid blocking main thread
        DispatchQueue.global(qos: .userInitiated).async {
            // Set volume directly on the player node
            player.volume = effectiveVolume
            
            // Schedule the buffer for immediate playback
            player.scheduleBuffer(buffer, completionHandler: nil)
        }
    }
    
    // Get current beat for UI without triggering re-renders
    func getCurrentBeat() -> Int {
        return internalCurrentBeat
    }
    
    // Get current measure index from total beat count
    func getCurrentMeasure() -> Int {
        return beatCount / timeSignature.beatsPerMeasure
    }
    
    // Get current BPM for adaptive UI updates
    func getCurrentBPM() -> Int {
        return bpm
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
    
    // Local UI state to reduce dependency on metronome's @Published properties
    @State private var uiCurrentBeat: Int = 0
    @State private var beatUpdateTimer: Timer?
    
    var body: some View {
        HStack(spacing: 12) {
            // Metronome toggle button
            Button(action: metronome.toggle) {
                Image(systemName: metronome.isEnabled ? "metronome.fill" : "metronome")
                    .font(.title3)
                    .foregroundColor(metronome.isEnabled ? .purple : .gray)
            }
            .disabled(isPlaying)
            
            // Beat indicator - uses local UI state
            HStack(spacing: 4) {
                ForEach(0..<track.timeSignature.beatsPerMeasure, id: \.self) { beat in
                    Circle()
                        .frame(width: 8, height: 8)
                        .foregroundColor(
                            metronome.isEnabled && uiCurrentBeat == beat ? 
                            (beat == 0 ? .purple : .white) : .gray.opacity(0.3)
                        )
                        .scaleEffect(
                            metronome.isEnabled && uiCurrentBeat == beat ? 1.2 : 1.0
                        )
                        .animation(.easeInOut(duration: 0.1), value: uiCurrentBeat)
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
        .onChange(of: isPlaying) { _, playing in
            if !playing && metronome.isEnabled {
                metronome.stop()
            }
        }
        .onChange(of: metronome.isEnabled) { _, enabled in
            if enabled {
                startUIBeatTimer()
            } else {
                stopUIBeatTimer()
                uiCurrentBeat = 0
            }
        }
        .onDisappear {
            stopUIBeatTimer()
        }
    }
    
    private func startUIBeatTimer() {
        stopUIBeatTimer()
        
        // Adaptive UI update frequency based on BPM
        let bpm = metronome.getCurrentBPM()
        let updateInterval: TimeInterval = bpm <= MetronomeConfiguration.maxBPMForSlowUpdate ? 0.5 : 
                                          (bpm <= MetronomeConfiguration.mediumBPMThreshold ? 0.25 : 0.15)
        
        beatUpdateTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { _ in
            if metronome.isEnabled {
                uiCurrentBeat = metronome.getCurrentBeat()
            }
        }
    }
    
    private func stopUIBeatTimer() {
        beatUpdateTimer?.invalidate()
        beatUpdateTimer = nil
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
