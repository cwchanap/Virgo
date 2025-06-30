//
//  GameplayView.swift
//  Virgo
//
//  Created by Chan Wai Chan on 30/6/2025.
//

import SwiftUI

struct GameplayView: View {
    let track: DrumTrack
    @State private var isPlaying = false
    @State private var playbackProgress: Double = 0.0
    @State private var currentBeat: Int = 0
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Header with track info and controls
                headerView
                
                // Main sheet music area
                sheetMusicView(geometry: geometry)
                
                // Bottom controls
                controlsView
            }
        }
        .navigationBarHidden(true)
        .background(Color.black)
        .foregroundColor(.white)
        .onAppear {
            startPlayback()
        }
    }
    
    // MARK: - Header View
    private var headerView: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.title2)
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(track.title)
                    .font(.headline)
                    .foregroundColor(.white)
                Text(track.artist)
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(track.bpm) BPM")
                    .font(.caption)
                    .foregroundColor(.gray)
                Text(track.difficulty)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.purple.opacity(0.3))
                    .cornerRadius(8)
            }
        }
        .padding()
        .background(Color.black.opacity(0.9))
    }
    
    // MARK: - Sheet Music View
    private func sheetMusicView(geometry: GeometryProxy) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            ZStack(alignment: .leading) {
                // Staff lines background
                staffLinesView(width: geometry.size.width * 3)
                
                // Drum notation
                drumNotationView(geometry: geometry)
            }
            .frame(height: 300)
        }
        .background(Color.gray.opacity(0.1))
    }
    
    // MARK: - Staff Lines
    private func staffLinesView(width: CGFloat) -> some View {
        VStack(spacing: 20) {
            ForEach(0..<5, id: \.self) { _ in
                Rectangle()
                    .frame(width: width, height: 1)
                    .foregroundColor(.gray.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Drum Notation
    private func drumNotationView(geometry: GeometryProxy) -> some View {
        HStack(spacing: 40) {
            ForEach(mockDrumBeats, id: \.id) { beat in
                DrumBeatView(beat: beat, isActive: currentBeat == beat.id)
            }
        }
        .padding(.horizontal, 50)
        .frame(height: 300)
    }
    
    
    // MARK: - Controls View
    private var controlsView: some View {
        HStack(spacing: 30) {
            // Restart button
            Button(action: restartPlayback) {
                Image(systemName: "backward.end.fill")
                    .font(.title2)
                    .foregroundColor(.white)
            }
            
            // Play/Pause button
            Button(action: togglePlayback) {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 50))
                    .foregroundColor(.purple)
            }
            
            // Speed controls
            VStack(spacing: 8) {
                Button(action: { /* Increase speed */ }) {
                    Text("1.25x")
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Color.gray.opacity(0.3))
                        .cornerRadius(12)
                }
                
                Button(action: { /* Normal speed */ }) {
                    Text("1.0x")
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Color.purple.opacity(0.5))
                        .cornerRadius(12)
                }
            }
        }
        .padding()
        .background(Color.black.opacity(0.9))
    }
    
    // MARK: - Mock Data
    private var mockDrumBeats: [DrumBeat] {
        [
            DrumBeat(id: 0, drums: [.kick, .hiHat], timePosition: 0.0),
            DrumBeat(id: 1, drums: [.hiHat], timePosition: 0.25),
            DrumBeat(id: 2, drums: [.snare, .hiHat], timePosition: 0.5),
            DrumBeat(id: 3, drums: [.hiHat], timePosition: 0.75),
            DrumBeat(id: 4, drums: [.kick, .hiHat], timePosition: 1.0),
            DrumBeat(id: 5, drums: [.hiHat], timePosition: 1.25),
            DrumBeat(id: 6, drums: [.snare, .hiHat], timePosition: 1.5),
            DrumBeat(id: 7, drums: [.hiHat, .crash], timePosition: 1.75),
            DrumBeat(id: 8, drums: [.kick, .hiHat], timePosition: 2.0),
            DrumBeat(id: 9, drums: [.hiHat], timePosition: 2.25),
            DrumBeat(id: 10, drums: [.snare, .hiHat], timePosition: 2.5),
            DrumBeat(id: 11, drums: [.hiHat], timePosition: 2.75),
        ]
    }
    
    // MARK: - Actions
    private func togglePlayback() {
        isPlaying.toggle()
        if isPlaying {
            startPlayback()
        }
    }
    
    private func startPlayback() {
        isPlaying = true
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            if !isPlaying {
                timer.invalidate()
                return
            }
            
            playbackProgress += 0.01
            currentBeat = Int(playbackProgress * Double(mockDrumBeats.count))
            
            if playbackProgress >= 1.0 {
                timer.invalidate()
                isPlaying = false
                playbackProgress = 0.0
                currentBeat = 0
            }
        }
    }
    
    private func restartPlayback() {
        playbackProgress = 0.0
        currentBeat = 0
        if isPlaying {
            startPlayback()
        }
    }
}

// MARK: - Supporting Models
struct DrumBeat {
    let id: Int
    let drums: [DrumType]
    let timePosition: Double
}

enum DrumType {
    case kick, snare, hiHat, crash, ride, tom1, tom2, tom3
    
    var symbol: String {
        switch self {
        case .kick: return "●"
        case .snare: return "◆"
        case .hiHat: return "×"
        case .crash: return "◉"
        case .ride: return "○"
        case .tom1: return "◐"
        case .tom2: return "◑"
        case .tom3: return "◒"
        }
    }
    
    var yPosition: CGFloat {
        switch self {
        case .crash: return 0
        case .hiHat: return 30
        case .tom1: return 60
        case .snare: return 90
        case .tom2: return 120
        case .tom3: return 150
        case .kick: return 180
        case .ride: return 210
        }
    }
}

// MARK: - Drum Beat View
struct DrumBeatView: View {
    let beat: DrumBeat
    let isActive: Bool
    
    var body: some View {
        ZStack {
            // Beat column background
            Rectangle()
                .frame(width: 30, height: 280)
                .foregroundColor(isActive ? Color.purple.opacity(0.3) : Color.clear)
                .cornerRadius(4)
            
            // Drum symbols
            VStack {
                ForEach(beat.drums, id: \.self) { drum in
                    Text(drum.symbol)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(isActive ? .yellow : .white)
                        .position(x: 15, y: drum.yPosition)
                }
            }
        }
        .frame(width: 30, height: 280)
    }
}

#Preview {
    GameplayView(track: DrumTrack.sampleData.first!)
}