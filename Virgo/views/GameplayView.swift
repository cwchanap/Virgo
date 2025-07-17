//
//  GameplayView.swift
//  Virgo
//
//  Created by Chan Wai Chan on 30/6/2025.
//

import SwiftUI

// MARK: - Note Position Key
struct NotePositionKey: Hashable {
    let measureNumber: Int
    let measureOffsetInMilliseconds: Int  // Convert to integer to avoid floating-point precision issues
    
    init(measureNumber: Int, measureOffset: Double) {
        self.measureNumber = measureNumber
        // Convert to milliseconds for precise integer representation
        // This supports up to 3 decimal places which is sufficient for musical notation
        self.measureOffsetInMilliseconds = Int(measureOffset * 1000)
    }
    
    var measureOffset: Double {
        return Double(measureOffsetInMilliseconds) / 1000.0
    }
}

struct GameplayView: View {
    let track: DrumTrack
    @State private var isPlaying = false
    @State private var playbackProgress: Double = 0.0
    @State private var currentBeat: Int = 0
    @State private var playbackTimer: Timer?
    @State private var playbackStartTime: Date?
    @State private var cachedDrumBeats: [DrumBeat] = []
    @EnvironmentObject private var metronome: MetronomeEngine
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Header with track info and controls
                GameplayHeaderView(
                    track: track,
                    isPlaying: $isPlaying,
                    onDismiss: { dismiss() },
                    onPlayPause: togglePlayback,
                    onRestart: restartPlayback
                )
                .background(Color.black)
                
                // Main sheet music area - now the primary scrollable content
                sheetMusicView(geometry: geometry)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // Bottom controls
                GameplayControlsView(
                    track: track,
                    isPlaying: $isPlaying,
                    playbackProgress: $playbackProgress,
                    metronome: metronome,
                    onPlayPause: togglePlayback,
                    onRestart: restartPlayback,
                    onSkipToEnd: skipToEnd
                )
                .background(Color.black)
            }
        }
        #if os(iOS)
        .toolbar(.hidden)
        #endif
        .background(Color.black)
        .foregroundColor(.white)
        .onAppear {
            Logger.userAction("Opened gameplay view for track: \(track.title)")
            computeDrumBeats()
            metronome.configure(bpm: track.bpm, timeSignature: track.timeSignature)
            startPlayback()
        }
        .onDisappear {
            playbackTimer?.invalidate()
            playbackTimer = nil
            metronome.stop()
        }
    }
    
    // MARK: - Sheet Music View
    private func sheetMusicView(geometry: GeometryProxy) -> some View {
        let maxIndex = (cachedDrumBeats.map { $0.id / 1000 }.max() ?? 0)
        let measuresCount = max(1, maxIndex + 1)
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
        let beamGroups = BeamGroupingHelper.calculateBeamGroups(from: cachedDrumBeats)
        
        return ZStack {
            // Render beams first (behind notes)
            ForEach(beamGroups, id: \.id) { beamGroup in
                BeamGroupView(
                    beamGroup: beamGroup,
                    measurePositions: measurePositions,
                    timeSignature: track.timeSignature,
                    isActive: beamGroup.beats.contains { beat in
                        currentBeat == cachedDrumBeats.firstIndex(where: { $0.id == beat.id })
                    }
                )
            }
            
            // Then render individual notes
            ForEach(Array(cachedDrumBeats.enumerated()), id: \.offset) { index, beat in
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
    
    // MARK: - Helper Methods
    private func computeDrumBeats() {
        // Handle empty tracks by leaving cachedDrumBeats empty
        if track.notes.isEmpty {
            cachedDrumBeats = []
            return
        }
        
        // Group notes by their position in the measure using a hashable key to avoid floating-point precision issues
        let groupedNotes = Dictionary(grouping: track.notes) { note in
            NotePositionKey(measureNumber: note.measureNumber, measureOffset: note.measureOffset)
        }
        
        // Convert to DrumBeat objects
        cachedDrumBeats = groupedNotes.map { (positionKey, notes) in
            // Convert 1-based measure numbers to 0-based for indexing
            let timePosition = Double(positionKey.measureNumber - 1) + positionKey.measureOffset
            let drumTypes = notes.compactMap { note in
                DrumType.from(noteType: note.noteType)
            }
            // Use the interval from the first note in the group (they should all have the same interval at the same position)
            let interval = notes.first?.interval ?? .quarter
            return DrumBeat(id: Int(timePosition * 1000), drums: drumTypes, timePosition: timePosition, interval: interval)
        }
        .sorted { $0.timePosition < $1.timePosition }
        
        Logger.debug("Computed \(cachedDrumBeats.count) drum beats for track: \(track.title)")
    }
    
    // Calculate actual track duration in seconds based on measures and BPM
    private var actualTrackDuration: Double {
        // Find the total number of measures based on the highest measure number
        let maxIndex = (cachedDrumBeats.map { $0.id / 1000 }.max() ?? 0)
        let totalMeasures = max(1, maxIndex + 1)
        
        // Calculate duration per measure in seconds
        // 60 seconds per minute / BPM = seconds per beat
        // multiply by beats per measure to get seconds per measure
        let secondsPerBeat = 60.0 / Double(track.bpm)
        let secondsPerMeasure = secondsPerBeat * Double(track.timeSignature.beatsPerMeasure)
        
        return Double(totalMeasures) * secondsPerMeasure
    }
    
    // MARK: - Actions
    private func togglePlayback() {
        isPlaying.toggle()
        if isPlaying {
            startPlayback()
        } else {
            playbackTimer?.invalidate()
            playbackTimer = nil
            playbackStartTime = nil
        }
    }
    
    private func startPlayback() {
        isPlaying = true
        playbackStartTime = Date()
        playbackTimer?.invalidate()
        Logger.audioPlayback("Started playback for track: \(track.title)")
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            if !isPlaying {
                timer.invalidate()
                return
            }
            
            // Calculate elapsed time since playback started
            guard let startTime = playbackStartTime else {
                timer.invalidate()
                return
            }
            
            let elapsedTime = Date().timeIntervalSince(startTime)
            let trackDuration = actualTrackDuration
            
            // Calculate progress based on actual elapsed time vs. track duration
            playbackProgress = min(elapsedTime / trackDuration, 1.0)
            currentBeat = Int(playbackProgress * Double(cachedDrumBeats.count))
            
            if playbackProgress >= 1.0 {
                timer.invalidate()
                isPlaying = false
                playbackProgress = 0.0
                currentBeat = 0
                playbackStartTime = nil
                Logger.audioPlayback("Playback finished for track: \(track.title)")
            }
        }
    }
    
    private func restartPlayback() {
        playbackProgress = 0.0
        currentBeat = 0
        playbackStartTime = nil
        Logger.audioPlayback("Restarted playback for track: \(track.title)")
        if isPlaying {
            startPlayback()
        }
    }
    
    private func skipToEnd() {
        playbackProgress = 1.0
        isPlaying = false
        playbackTimer?.invalidate()
        playbackTimer = nil
        playbackStartTime = nil
        Logger.audioPlayback("Skipped to end for track: \(track.title)")
    }
}

#Preview {
    GameplayView(track: DrumTrack.sampleData.first!)
        .environmentObject(MetronomeEngine())
}
