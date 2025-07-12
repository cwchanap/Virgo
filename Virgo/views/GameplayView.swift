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
        let beamGroups = calculateBeamGroups(from: drumBeats)
        
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
    
    // MARK: - Beam Grouping Logic
    private func calculateBeamGroups(from beats: [DrumBeat]) -> [BeamGroup] {
        var beamGroups: [BeamGroup] = []
        var currentGroup: [DrumBeat] = []
        
        for beat in beats {
            // Only group eighth notes and shorter that need flags
            if beat.interval.needsFlag {
                // Check if this beat is consecutive to the previous one
                if let lastBeat = currentGroup.last {
                    let timeDifference = abs(beat.timePosition - lastBeat.timePosition)
                    let measureNumber = Int(beat.timePosition)
                    let lastMeasureNumber = Int(lastBeat.timePosition)
                    
                    // Group notes if they're in the same measure and consecutive (within 0.3 time units)
                    if measureNumber == lastMeasureNumber && timeDifference <= 0.3 {
                        currentGroup.append(beat)
                    } else {
                        // Finish current group if it has 2+ notes
                        if currentGroup.count >= 2 {
                            beamGroups.append(BeamGroup(
                                id: "beam_\(currentGroup.first?.id ?? 0)",
                                beats: currentGroup
                            ))
                        }
                        currentGroup = [beat]
                    }
                } else {
                    currentGroup = [beat]
                }
            } else {
                // Finish current group for non-beamable notes
                if currentGroup.count >= 2 {
                    beamGroups.append(BeamGroup(
                        id: "beam_\(currentGroup.first?.id ?? 0)",
                        beats: currentGroup
                    ))
                }
                currentGroup = []
            }
        }
        
        // Don't forget the last group
        if currentGroup.count >= 2 {
            beamGroups.append(BeamGroup(
                id: "beam_\(currentGroup.first?.id ?? 0)",
                beats: currentGroup
            ))
        }
        
        return beamGroups
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

// MARK: - Supporting Models
struct DrumBeat {
    let id: Int
    let drums: [DrumType]
    let timePosition: Double
    let interval: NoteInterval
}

// MARK: - Beam Group Models
struct BeamGroup: Identifiable {
    let id: String
    let beats: [DrumBeat]
    
    var beamCount: Int {
        return beats.map { $0.interval.flagCount }.max() ?? 1
    }
}

// MARK: - Beam Group View
struct BeamGroupView: View {
    let beamGroup: BeamGroup
    let measurePositions: [GameplayLayout.MeasurePosition]
    let timeSignature: TimeSignature
    let isActive: Bool
    
    var body: some View {
        ZStack {
            ForEach(0..<beamGroup.beamCount, id: \.self) { beamLevel in
                BeamView(
                    beats: beamGroup.beats,
                    beamLevel: beamLevel,
                    measurePositions: measurePositions,
                    timeSignature: timeSignature,
                    isActive: isActive
                )
            }
        }
    }
}

// MARK: - Individual Beam View
struct BeamView: View {
    let beats: [DrumBeat]
    let beamLevel: Int
    let measurePositions: [GameplayLayout.MeasurePosition]
    let timeSignature: TimeSignature
    let isActive: Bool
    
    var body: some View {
        // Filter beats that need this beam level
        let beamedBeats = beats.filter { $0.interval.flagCount > beamLevel }
        
        guard beamedBeats.count >= 2,
              let firstBeat = beamedBeats.first,
              let lastBeat = beamedBeats.last else {
            return AnyView(EmptyView())
        }
        
        // Calculate beam positions
        let firstMeasureIndex = firstBeat.id / 1000
        let lastMeasureIndex = lastBeat.id / 1000
        
        guard let firstMeasurePos = measurePositions.first(where: { $0.measureIndex == firstMeasureIndex }),
              let lastMeasurePos = measurePositions.first(where: { $0.measureIndex == lastMeasureIndex }),
              firstMeasurePos.row == lastMeasurePos.row else {
            return AnyView(EmptyView())
        }
        
        // Calculate X positions
        let firstBeatOffset = firstBeat.timePosition - Double(firstMeasureIndex)
        let lastBeatOffset = lastBeat.timePosition - Double(lastMeasureIndex)
        let firstBeatIndex = Int(firstBeatOffset * Double(timeSignature.beatsPerMeasure))
        let lastBeatIndex = Int(lastBeatOffset * Double(timeSignature.beatsPerMeasure))
        
        let startX = GameplayLayout.noteXPosition(measurePosition: firstMeasurePos, beatIndex: firstBeatIndex, timeSignature: timeSignature) + 7 // Stem offset
        let endX = GameplayLayout.noteXPosition(measurePosition: lastMeasurePos, beatIndex: lastBeatIndex, timeSignature: timeSignature) + 7
        
        // Beam Y position (above the notes, accounting for beam level)
        let baseY = GameplayLayout.StaffLinePosition.line3.absoluteY(for: firstMeasurePos.row) - 60 - CGFloat(beamLevel * 6)
        
        return AnyView(
            Path { path in
                path.move(to: CGPoint(x: startX, y: baseY))
                path.addLine(to: CGPoint(x: endX, y: baseY))
            }
            .stroke(isActive ? Color.yellow : Color.white, lineWidth: 4)
        )
    }
}

// MARK: - Drum Beat View
struct DrumBeatView: View {
    let beat: DrumBeat
    let isActive: Bool
    let row: Int
    let isBeamed: Bool
    
    // Calculate stem connection info for multiple simultaneous notes
    private var stemInfo: StemConnectionInfo {
        guard beat.interval.needsStem && beat.drums.count > 1 else {
            return StemConnectionInfo(hasConnectedStem: false, stemTop: 0, stemBottom: 0, mainStemX: 7)
        }
        
        let noteOffsets = beat.drums.map { $0.notePosition.yOffset }
        let topOffset = noteOffsets.min() ?? 0 // Highest note (smallest y offset)
        let bottomOffset = noteOffsets.max() ?? 0 // Lowest note (largest y offset)
        
        // Only connect stems if notes span multiple staff positions
        let shouldConnect = abs(topOffset - bottomOffset) > GameplayLayout.staffLineSpacing
        
        if shouldConnect {
            // Extend stem upward from the topmost note only (standard music notation)
            let stemExtension: CGFloat = 35
            return StemConnectionInfo(
                hasConnectedStem: true,
                stemTop: topOffset - stemExtension,
                stemBottom: bottomOffset, // Don't extend beyond the bottommost note
                mainStemX: 7
            )
        } else {
            return StemConnectionInfo(hasConnectedStem: false, stemTop: 0, stemBottom: 0, mainStemX: 7)
        }
    }
    
    var body: some View {
        ZStack {
            // Beat column background
            Rectangle()
                .frame(width: 30, height: GameplayLayout.staffHeight)
                .foregroundColor(isActive ? Color.purple.opacity(0.3) : Color.clear)
                .cornerRadius(4)
            
            // Connected stem for multiple notes (if applicable)
            if stemInfo.hasConnectedStem && beat.interval.needsStem {
                let stemTop: CGFloat = isBeamed ? -60 : stemInfo.stemTop  // End at beam if beamed
                let stemBottom = stemInfo.stemBottom
                let stemHeight = stemBottom - stemTop
                let stemCenterY = (stemTop + stemBottom) / 2
                
                Rectangle()
                    .frame(width: 2, height: stemHeight)
                    .foregroundColor(isActive ? .yellow : .white)
                    .offset(x: stemInfo.mainStemX, y: stemCenterY)
            }
            
            // Flags on the main stem (for connected stems, only if not beamed)
            if stemInfo.hasConnectedStem && beat.interval.needsFlag && !isBeamed {
                ForEach(0..<beat.interval.flagCount, id: \.self) { flagIndex in
                    FlagView(flagIndex: flagIndex)
                        .foregroundColor(isActive ? .yellow : .white)
                        .offset(x: stemInfo.mainStemX + 2, y: stemInfo.stemTop - CGFloat(flagIndex * 8))
                }
            }
            
            // Drum symbols with individual stems (for single notes or connection to main stem)
            ForEach(beat.drums, id: \.self) { drum in
                ZStack {
                    let drumYOffset = drum.notePosition.yOffset
                    
                    // Individual stem for single notes or short connection to main stem
                    if beat.interval.needsStem {
                        if !stemInfo.hasConnectedStem {
                            if isBeamed {
                                // Beamed stem - calculate height to reach beam position
                                let beamY: CGFloat = -60 // Base beam position relative to center staff line
                                let stemHeight = abs(drumYOffset - beamY)
                                let stemCenterY = (drumYOffset + beamY) / 2
                                
                                Rectangle()
                                    .frame(width: 2, height: stemHeight)
                                    .foregroundColor(isActive ? .yellow : .white)
                                    .offset(x: 7, y: stemCenterY)
                            } else {
                                // Individual stem for single note (not beamed)
                                Rectangle()
                                    .frame(width: 2, height: 75)
                                    .foregroundColor(isActive ? .yellow : .white)
                                    .offset(x: 7, y: drumYOffset - 37.5)
                            }
                        } else {
                            // Short connector to main stem (only if note is not at the extreme ends)
                            let isTopNote = drumYOffset == beat.drums.map { $0.notePosition.yOffset }.min()
                            let isBottomNote = drumYOffset == beat.drums.map { $0.notePosition.yOffset }.max()
                            
                            if !isTopNote && !isBottomNote {
                                // Short horizontal connector to main stem
                                Rectangle()
                                    .frame(width: 5, height: 2)
                                    .foregroundColor(isActive ? .yellow : .white)
                                    .offset(x: 4.5, y: drumYOffset)
                            }
                        }
                    }
                    
                    // Flags for individual notes (only if not using connected stem and not beamed)
                    if !stemInfo.hasConnectedStem && beat.interval.needsFlag && !isBeamed {
                        ForEach(0..<beat.interval.flagCount, id: \.self) { flagIndex in
                            FlagView(flagIndex: flagIndex)
                                .foregroundColor(isActive ? .yellow : .white)
                                .offset(x: 9, y: drumYOffset - 67.5 - CGFloat(flagIndex * 8))
                        }
                    }
                    
                    // Drum symbol
                    Text(drum.symbol)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(isActive ? .yellow : .white)
                        .offset(x: 0, y: drumYOffset)
                }
            }
        }
        .frame(width: 30, height: GameplayLayout.staffHeight)
    }
}

// MARK: - Stem Connection Info
private struct StemConnectionInfo {
    let hasConnectedStem: Bool
    let stemTop: CGFloat
    let stemBottom: CGFloat
    let mainStemX: CGFloat
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
