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
    private var timer: Timer?
    private var bpm: Int = 120
    private var timeSignature: TimeSignature = .fourFour
    private var tickerBuffer: AVAudioPCMBuffer?
    
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
        guard let tickerData = NSDataAsset(name: "ticker") else {
            Logger.audioPlayback("Failed to find ticker data asset")
            return
        }
        
        do {
            // Create temporary file from data asset
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("ticker_temp.wav")
            try tickerData.data.write(to: tempURL)
            
            let audioFile = try AVAudioFile(forReading: tempURL)
            let frameCount = AVAudioFrameCount(audioFile.length)
            
            guard let buffer = AVAudioPCMBuffer(pcmFormat: audioFile.processingFormat, frameCapacity: frameCount) else {
                Logger.audioPlayback("Failed to create audio buffer for ticker.wav")
                return
            }
            
            try audioFile.read(into: buffer)
            tickerBuffer = buffer
            Logger.audioPlayback(
                "Successfully loaded ticker from data asset - frames: \(buffer.frameLength), " +
                "channels: \(buffer.format.channelCount), sample rate: \(buffer.format.sampleRate)"
            )
            
            // Clean up temporary file
            try? FileManager.default.removeItem(at: tempURL)
            
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
        
        isEnabled = true
        currentBeat = 0
        
        let interval = 60.0 / Double(bpm)
        
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.playClick()
        }
        
        Logger.audioPlayback("Metronome started at \(bpm) BPM")
    }
    
    func stop() {
        isEnabled = false
        currentBeat = 0
        timer?.invalidate()
        timer = nil
        playerNode?.stop()
        
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
        playClick()
    }
    
    private func playClick() {
        guard let player = playerNode, let buffer = tickerBuffer else { 
            Logger.audioPlayback("Missing player or buffer")
            return 
        }
        
        let isAccent = currentBeat == 0
        
        // Create volume buffer with proper format
        guard let volumeBuffer = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameCapacity) else {
            Logger.audioPlayback("Failed to create volume buffer")
            return
        }
        
        volumeBuffer.frameLength = buffer.frameLength
        
        // Apply volume and accent
        if let sourceData = buffer.floatChannelData?[0],
           let destData = volumeBuffer.floatChannelData?[0] {
            let accentMultiplier: Float = isAccent ? 1.3 : 1.0
            let effectiveVolume = volume * accentMultiplier
            
            for i in 0..<Int(buffer.frameLength) {
                destData[i] = sourceData[i] * effectiveVolume
            }
        } else {
            Logger.audioPlayback("Failed to access audio channel data")
            return
        }
        
        // Ensure the player is playing
        if !player.isPlaying {
            player.play()
        }
        
        // Schedule the buffer for playback
        player.scheduleBuffer(volumeBuffer) { [weak self] in
            // Buffer playback completed
        }
        
        Logger.audioPlayback("Scheduled metronome click - beat \(currentBeat), accent: \(isAccent)")
        
        // Update beat counter
        DispatchQueue.main.async {
            self.currentBeat = (self.currentBeat + 1) % self.timeSignature.beatsPerMeasure
        }
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
