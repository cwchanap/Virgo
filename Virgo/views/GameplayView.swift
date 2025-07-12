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
        let measuresCount = max(1, (drumBeats.map { $0.id }.max() ?? 1000) / 1000)
        let measurePositions = GameplayLayout.calculateMeasurePositions(totalMeasures: measuresCount, timeSignature: track.timeSignature)
        let totalHeight = GameplayLayout.totalHeight(for: measurePositions)
        
        return ScrollView([.horizontal, .vertical], showsIndicators: false) {
            ZStack(alignment: .topLeading) {
                // Staff lines background
                staffLinesView(measurePositions: measurePositions)
                
                // Bar lines
                barLinesView(measurePositions: measurePositions)
                
                // Clefs and time signatures for each row
                clefsAndTimeSignaturesView(measurePositions: measurePositions)
                
                // Drum notation
                drumNotationView(measurePositions: measurePositions)
            }
            .frame(width: GameplayLayout.maxRowWidth, height: totalHeight)
        }
        .background(Color.gray.opacity(0.1))
    }
    
    // MARK: - Staff Lines
    private func staffLinesView(measurePositions: [GameplayLayout.MeasurePosition]) -> some View {
        let rows = Set(measurePositions.map { $0.row })
        
        return ZStack {
            ForEach(Array(rows), id: \.self) { row in
                ForEach(0..<GameplayLayout.staffLineCount, id: \.self) { lineIndex in
                    Rectangle()
                        .frame(width: GameplayLayout.maxRowWidth, height: 1) // Full width to cover clef area
                        .foregroundColor(.gray.opacity(0.5))
                        .position(
                            x: GameplayLayout.maxRowWidth / 2, // Center in full width
                            y: GameplayLayout.StaffLinePosition(rawValue: lineIndex)?.absoluteY(for: row) ?? 0
                        )
                }
            }
        }
    }
    
    // MARK: - Clefs and Time Signatures
    private func clefsAndTimeSignaturesView(measurePositions: [GameplayLayout.MeasurePosition]) -> some View {
        let rows = Set(measurePositions.map { $0.row })
        
        return ZStack {
            ForEach(Array(rows), id: \.self) { row in
                Group {
                    // Drum Clef - position at center of staff (line 3)
                    DrumClefSymbol()
                        .frame(width: GameplayLayout.clefWidth, height: GameplayLayout.staffHeight)
                        .foregroundColor(.white)
                        .position(
                            x: GameplayLayout.clefX,
                            y: GameplayLayout.StaffLinePosition.line3.absoluteY(for: row)
                        )
                    
                    // Time Signature - position at center of staff (line 3)
                    TimeSignatureSymbol(timeSignature: track.timeSignature)
                        .frame(width: GameplayLayout.timeSignatureWidth, height: GameplayLayout.staffHeight)
                        .foregroundColor(.white)
                        .position(
                            x: GameplayLayout.timeSignatureX,
                            y: GameplayLayout.StaffLinePosition.line3.absoluteY(for: row)
                        )
                }
            }
        }
    }
    
    // MARK: - Bar Lines
    private func barLinesView(measurePositions: [GameplayLayout.MeasurePosition]) -> some View {
        ZStack {
            // Regular bar lines
            ForEach(measurePositions, id: \.measureIndex) { position in
                // Use the same Y positioning as staff lines - center of the staff for this row
                let centerY = GameplayLayout.StaffLinePosition.line3.absoluteY(for: position.row) // Middle staff line
                
                Rectangle()
                    .frame(width: GameplayLayout.barLineWidth, height: GameplayLayout.staffHeight)
                    .foregroundColor(.white.opacity(0.8))
                    .position(
                        x: position.xOffset,
                        y: centerY
                    )
            }
            
            // Double bar line at the very end
            if let lastPosition = measurePositions.last {
                let measureWidth = GameplayLayout.measureWidth(for: track.timeSignature)
                let endX = lastPosition.xOffset + measureWidth
                let centerY = GameplayLayout.StaffLinePosition.line3.absoluteY(for: lastPosition.row) // Middle staff line
                
                HStack(spacing: GameplayLayout.doubleBarLineSpacing) {
                    Rectangle()
                        .frame(width: GameplayLayout.doubleBarLineWidths.thin, height: GameplayLayout.staffHeight)
                        .foregroundColor(.white)
                    Rectangle()
                        .frame(width: GameplayLayout.doubleBarLineWidths.thick, height: GameplayLayout.staffHeight)
                        .foregroundColor(.white)
                }
                .position(
                    x: endX,
                    y: centerY
                )
            }
        }
    }
    
    // MARK: - Drum Notation
    private func drumNotationView(measurePositions: [GameplayLayout.MeasurePosition]) -> some View {
        let beamGroups = BeamGroupingHelper.calculateBeamGroups(from: drumBeats)
        
        return ZStack {
            // Render beams first (behind notes)
            ForEach(beamGroups, id: \.id) { beamGroup in
                BeamGroupView(
                    beamGroup: beamGroup,
                    measurePositions: measurePositions,
                    timeSignature: track.timeSignature,
                    isActive: beamGroup.beats.contains { beat in
                        currentBeat == drumBeats.firstIndex(where: { $0.id == beat.id })
                    }
                )
            }
            
            // Then render individual notes
            ForEach(Array(drumBeats.enumerated()), id: \.offset) { index, beat in
                // Find which measure this beat belongs to based on the measure number in the beat
                let measureIndex = beat.id / 1000
                
                if let measurePos = measurePositions.first(where: { $0.measureIndex == measureIndex }) {
                    // Calculate beat index within the measure based on measureOffset
                    let beatOffsetInMeasure = beat.timePosition - Double(measureIndex)
                    // Convert offset to beat index (0, 1, 2, 3 for 4/4 time)
                    let beatIndex = Int(beatOffsetInMeasure * Double(track.timeSignature.beatsPerMeasure))
                    // Use unified spacing system
                    let beatX = GameplayLayout.noteXPosition(measurePosition: measurePos, beatIndex: beatIndex, timeSignature: track.timeSignature)
                    
                    // Use the same Y positioning as other elements - center of staff for this row
                    let centerY = GameplayLayout.StaffLinePosition.line3.absoluteY(for: measurePos.row)
                    
                    // Check if this beat is part of a beam group
                    let isBeamed = beamGroups.contains { group in
                        group.beats.contains { $0.id == beat.id }
                    }
                    
                    DrumBeatView(
                        beat: beat, 
                        isActive: currentBeat == index,
                        row: measurePos.row,
                        isBeamed: isBeamed
                    )
                    .position(
                        x: beatX,
                        y: centerY
                    )
                }
            }
        }
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
        // If track has no notes, create some default beats for demonstration
        if track.notes.isEmpty {
            return [
                DrumBeat(id: 0, drums: [.kick], timePosition: 0.0, interval: .quarter),
                DrumBeat(id: 250, drums: [.hiHat], timePosition: 0.25, interval: .eighth),
                DrumBeat(id: 500, drums: [.snare], timePosition: 0.5, interval: .quarter),
                DrumBeat(id: 750, drums: [.hiHat], timePosition: 0.75, interval: .eighth)
            ]
        }
        
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

#Preview {
    GameplayView(track: DrumTrack.sampleData.first!)
}
