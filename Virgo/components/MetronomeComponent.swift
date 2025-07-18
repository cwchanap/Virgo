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
    
    // Static cached buffer to avoid recreating the ticker sound buffer for each instance
    private static var cachedTickerBuffer: AVAudioPCMBuffer?
    
    // Thread-safe access queue for the cached buffer
    private static let cacheQueue = DispatchQueue(label: "com.virgo.metronome.cache", attributes: .concurrent)
    
    init() {
        configureAudioSession()
        setupAudioEngine()
        loadTickerSound()
    }
    
    private func configureAudioSession() {
        #if os(iOS)
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try audioSession.setActive(true)
            Logger.audioPlayback("Audio session configured successfully")
        } catch {
            Logger.audioPlayback("Failed to configure audio session: \(error)")
        }
        #else
        Logger.audioPlayback("Audio session configuration skipped on macOS")
        #endif
    }
    
    deinit {
        stop()
        audioEngine?.stop()
    }
    
    private func setupAudioEngine() {
        audioEngine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()
        
        guard let engine = audioEngine, let player = playerNode else { 
            Logger.audioPlayback("Failed to create audio engine or player")
            return 
        }
        
        engine.attach(player)
        
        // Connect player to mixer with explicit format
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)
        sampleRate = format?.sampleRate ?? 44100.0
        engine.connect(player, to: engine.mainMixerNode, format: format)
        
        // Prepare the engine
        engine.prepare()
        
        do {
            try engine.start()
            Logger.audioPlayback("Audio engine started successfully")
        } catch {
            Logger.audioPlayback("Failed to start audio engine: \(error)")
        }
    }
    
    private func loadTickerSound() {
        // Thread-safe check for cached buffer
        let existingBuffer = Self.cacheQueue.sync {
            return Self.cachedTickerBuffer
        }
        
        if let cachedBuffer = existingBuffer {
            tickerBuffer = cachedBuffer
            Logger.audioPlayback("Using cached ticker buffer")
            return
        }
        
        guard let tickerData = NSDataAsset(name: "ticker") else {
            Logger.audioPlayback("Failed to find ticker data asset")
            return
        }
        
        do {
            // Create the temporary file only once for caching
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("ticker_cached.wav")
            try tickerData.data.write(to: tempURL)
            
            let audioFile = try AVAudioFile(forReading: tempURL)
            let frameCount = AVAudioFrameCount(audioFile.length)
            
            guard let buffer = AVAudioPCMBuffer(pcmFormat: audioFile.processingFormat, frameCapacity: frameCount) else {
                Logger.audioPlayback("Failed to create audio buffer for ticker.wav")
                // Clean up on failure
                try? FileManager.default.removeItem(at: tempURL)
                return
            }
            
            try audioFile.read(into: buffer)
            
            // Thread-safe cache update using barrier to ensure exclusive write access
            Self.cacheQueue.async(flags: .barrier) {
                // Double-check that another thread hasn't already cached the buffer
                if Self.cachedTickerBuffer == nil {
                    Self.cachedTickerBuffer = buffer
                }
            }
            
            tickerBuffer = buffer
            
            // Clean up temporary file after successful caching
            try? FileManager.default.removeItem(at: tempURL)
            
            Logger.audioPlayback(
                "Successfully loaded and cached ticker from data asset - frames: \(buffer.frameLength), " +
                "channels: \(buffer.format.channelCount), sample rate: \(buffer.format.sampleRate)"
            )
            
        } catch {
            Logger.audioPlayback("Failed to load ticker from data asset: \(error)")
        }
    }
    
    func configure(bpm: Int, timeSignature: TimeSignature) {
        self.bpm = bpm
        self.timeSignature = timeSignature
    }
    
    func start() {
        guard !isEnabled else { return }
        guard let player = playerNode else { return }
        
        isEnabled = true
        currentBeat = 0
        
        // Start the player if not already playing
        if !player.isPlaying {
            player.play()
        }
        
        // Get current time and schedule the first beat immediately
        startTime = AVAudioTime(sampleTime: 0, atRate: sampleRate)
        nextBeatTime = AVAudioTime(sampleTime: 0, atRate: sampleRate)
        
        scheduleNextBeats()
        
        Logger.audioPlayback("Metronome started at \(bpm) BPM with sample-accurate timing")
    }
    
    func stop() {
        isEnabled = false
        currentBeat = 0
        playerNode?.stop()
        startTime = nil
        nextBeatTime = nil
        
        Logger.audioPlayback("Metronome stopped")
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
        Logger.audioPlayback("Testing single metronome click")
        playClick(at: nil, beatIndex: 0)
    }
    
    private func scheduleNextBeats() {
        guard isEnabled, playerNode != nil else { return }
        
        let beatsToSchedule = 8 // Schedule beats ahead for smooth playback
        let samplesPerBeat = Int64(60.0 * sampleRate / Double(bpm))
        
        for i in 0..<beatsToSchedule {
            let beatIndex = (currentBeat + i) % timeSignature.beatsPerMeasure
            let sampleTime = Int64(i) * samplesPerBeat
            let playTime = AVAudioTime(sampleTime: sampleTime, atRate: sampleRate)
            
            playClick(at: playTime, beatIndex: beatIndex)
        }
    }
    
    private func playClick(at time: AVAudioTime?, beatIndex: Int) {
        guard let player = playerNode, let buffer = tickerBuffer else { 
            Logger.audioPlayback("Missing player or buffer")
            return 
        }
        
        let isAccent = beatIndex == 0
        let accentMultiplier: Float = isAccent ? 1.3 : 1.0
        let effectiveVolume = volume * accentMultiplier
        
        // Set volume directly on the player node - much more efficient than buffer copying
        player.volume = effectiveVolume
        
        // Schedule the buffer for playback at the specified time
        let completionHandler: AVAudioNodeCompletionHandler = { [weak self] in
            // Update beat counter on main queue
            DispatchQueue.main.async {
                guard let self = self, self.isEnabled else { return }
                self.currentBeat = (self.currentBeat + 1) % self.timeSignature.beatsPerMeasure
                
                // Schedule more beats if we're running low
                if self.currentBeat == 0 {
                    self.scheduleNextBeats()
                }
            }
        }
        
        if let playTime = time {
            player.scheduleBuffer(buffer, at: playTime, options: [], completionHandler: completionHandler)
        } else {
            player.scheduleBuffer(buffer, completionHandler: completionHandler)
        }
        
        Logger.audioPlayback("Scheduled metronome click - beat \(beatIndex), accent: \(isAccent), sample-accurate: \(time != nil)")
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
