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
    @State private var playbackTimer: Timer?
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
        #if os(iOS)
        .navigationBarHidden(true)
        #endif
        .background(Color.black)
        .foregroundColor(.white)
        .onAppear {
            startPlayback()
        }
        .onDisappear {
            playbackTimer?.invalidate()
            playbackTimer = nil
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
                HStack(spacing: 8) {
                    Text("\(track.bpm) BPM")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Text(track.timeSignature.displayName)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                Text(track.difficulty.rawValue)
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
                
                // Bar lines
                barLinesView(geometry: geometry)
                
                // Drum clef
                drumClefView()
                
                // Time signature
                timeSignatureView()
                
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
    
    // MARK: - Drum Clef
    private func drumClefView() -> some View {
        HStack {
            DrumClefSymbol()
                .frame(width: 40, height: 80)
                .foregroundColor(.white)
                .position(x: 20, y: 150)
            
            Spacer()
        }
    }
    
    // MARK: - Time Signature
    private func timeSignatureView() -> some View {
        HStack {
            TimeSignatureSymbol(timeSignature: track.timeSignature)
                .frame(width: 30, height: 60)
                .foregroundColor(.white)
                .position(x: 55, y: 150)
            
            Spacer()
        }
    }
    
    // MARK: - Bar Lines
    private func barLinesView(geometry: GeometryProxy) -> some View {
        HStack(spacing: 0) {
            // Start after the clef and time signature
            Spacer()
                .frame(width: 100)
            
            // Calculate measures based on drum beats and time signature
            let measuresCount = max(1, (drumBeats.map { $0.id }.max() ?? 1000) / 1000)
            let notesPerMeasure = track.timeSignature.beatsPerMeasure
            let measureWidth: CGFloat = CGFloat(notesPerMeasure * 40) // 40 pixels per note
            
            ForEach(0..<measuresCount, id: \.self) { measureIndex in
                Rectangle()
                    .frame(width: 2, height: 160)
                    .foregroundColor(.white.opacity(0.8))
                    .position(x: 1, y: 150)
                
                if measureIndex < measuresCount - 1 {
                    Spacer()
                        .frame(width: measureWidth)
                }
            }
            
            // Bold double bar line at the end
            Spacer()
                .frame(width: measureWidth)
            
            HStack(spacing: 3) {
                Rectangle()
                    .frame(width: 2, height: 160)
                    .foregroundColor(.white)
                Rectangle()
                    .frame(width: 4, height: 160)
                    .foregroundColor(.white)
            }
            .position(x: 3, y: 150)
            
            Spacer()
        }
    }
    
    // MARK: - Drum Notation
    private func drumNotationView(geometry: GeometryProxy) -> some View {
        let spacing = 40.0 // Base spacing between notes
        
        return HStack(spacing: spacing) {
            ForEach(Array(drumBeats.enumerated()), id: \.offset) { index, beat in
                DrumBeatView(beat: beat, isActive: currentBeat == index)
            }
        }
        .padding(.leading, 100) // Extra padding to leave space for clef and time signature
        .padding(.trailing, 50)
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
    
    // MARK: - Computed Properties
    private var drumBeats: [DrumBeat] {
        // Group notes by their position in the measure
        let groupedNotes = Dictionary(grouping: track.notes) { note in
            Double(note.measureNumber) + note.measureOffset
        }
        
        // Convert to DrumBeat objects
        return groupedNotes.map { (position, notes) in
            let drumTypes = notes.compactMap { note in
                DrumType.from(noteType: note.noteType)
            }
            // Use the interval from the first note in the group (they should all have the same interval at the same position)
            let interval = notes.first?.interval ?? .quarter
            return DrumBeat(id: Int(position * 1000), drums: drumTypes, timePosition: position, interval: interval)
        }
        .sorted { $0.timePosition < $1.timePosition }
    }
    
    // MARK: - Actions
    private func togglePlayback() {
        isPlaying.toggle()
        if isPlaying {
            startPlayback()
        } else {
            playbackTimer?.invalidate()
            playbackTimer = nil
        }
    }
    
    private func startPlayback() {
        isPlaying = true
        playbackTimer?.invalidate()
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            if !isPlaying {
                timer.invalidate()
                return
            }
            
            playbackProgress += 0.01
            currentBeat = Int(playbackProgress * Double(drumBeats.count))
            
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
    let interval: NoteInterval
}

enum DrumType {
    case kick, snare, hiHat, crash, ride, tom1, tom2, tom3
    
    private enum LayoutConstants {
        static let staffLineHeight: CGFloat = 30
    }

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
        case .crash: return 0 * LayoutConstants.staffLineHeight
        case .hiHat: return 1 * LayoutConstants.staffLineHeight
        case .tom1: return 2 * LayoutConstants.staffLineHeight
        case .snare: return 3 * LayoutConstants.staffLineHeight
        case .tom2: return 4 * LayoutConstants.staffLineHeight
        case .tom3: return 5 * LayoutConstants.staffLineHeight
        case .kick: return 6 * LayoutConstants.staffLineHeight
        case .ride: return 7 * LayoutConstants.staffLineHeight
        }
    }
    
    static func from(noteType: NoteType) -> DrumType? {
        switch noteType {
        case .bass: return .kick
        case .snare: return .snare
        case .hiHat: return .hiHat
        case .openHiHat: return .hiHat
        case .crash: return .crash
        case .ride: return .ride
        case .highTom: return .tom1
        case .midTom: return .tom2
        case .lowTom: return .tom3
        case .china: return .crash
        case .splash: return .crash
        case .cowbell: return nil // Cowbell doesn't have a direct mapping
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
            
            // Drum symbols with tails
            ForEach(beat.drums, id: \.self) { drum in
                ZStack {
                    // Stem (tail) for notes that need it
                    if beat.interval.needsStem {
                        Rectangle()
                            .frame(width: 2, height: 75)
                            .foregroundColor(isActive ? .yellow : .white)
                            .position(x: 22, y: drum.yPosition - 37.5)
                    }
                    
                    // Flags for eighth notes and shorter
                    if beat.interval.needsFlag {
                        ForEach(0..<beat.interval.flagCount, id: \.self) { flagIndex in
                            FlagView(flagIndex: flagIndex)
                                .foregroundColor(isActive ? .yellow : .white)
                                .position(x: 24, y: drum.yPosition - 67.5 - CGFloat(flagIndex * 8))
                        }
                    }
                    
                    // Drum symbol
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

// MARK: - Flag View
struct FlagView: View {
    let flagIndex: Int
    
    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: 0))
            path.addCurve(to: CGPoint(x: 8, y: 4), 
                         control1: CGPoint(x: 4, y: -2), 
                         control2: CGPoint(x: 6, y: 2))
            path.addCurve(to: CGPoint(x: 0, y: 8), 
                         control1: CGPoint(x: 6, y: 6), 
                         control2: CGPoint(x: 4, y: 10))
            path.closeSubpath()
        }
        .fill(Color.white)
        .frame(width: 8, height: 8)
    }
}

// MARK: - Drum Clef Symbol
struct DrumClefSymbol: View {
    var body: some View {
        VStack(spacing: 4) {
            // Top rectangle
            Rectangle()
                .frame(width: 12, height: 8)
            
            // Middle rectangle
            Rectangle()
                .frame(width: 12, height: 8)
            
            // Bottom rectangle
            Rectangle()
                .frame(width: 12, height: 8)
        }
        .frame(width: 12, height: 32)
    }
}

// MARK: - Time Signature Symbol
struct TimeSignatureSymbol: View {
    let timeSignature: TimeSignature
    
    var body: some View {
        VStack(spacing: 2) {
            // Top number (beats per measure)
            Text("\(timeSignature.beatsPerMeasure)")
                .font(.system(size: 18, weight: .bold, design: .serif))
                .foregroundColor(.white)
            
            // Bottom number (note value)
            Text("\(timeSignature.noteValue)")
                .font(.system(size: 18, weight: .bold, design: .serif))
                .foregroundColor(.white)
        }
        .frame(width: 25, height: 50)
    }
}

#Preview {
    GameplayView(track: DrumTrack.sampleData.first!)
}
