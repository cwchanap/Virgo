//
//  GameplayView.swift
//  Virgo
//
//  Created by Chan Wai Chan on 30/6/2025.
//

import SwiftUI
import AVFoundation

// swiftlint:disable file_length type_body_length line_length

// MARK: - Measure Utilities
struct MeasureUtils {
    /// Converts 1-based measure number to 0-based index for calculations
    static func toZeroBasedIndex(_ measureNumber: Int) -> Int {
        return measureNumber - 1
    }
    
    /// Converts 0-based measure index to 1-based measure number for display
    static func toOneBasedNumber(_ measureIndex: Int) -> Int {
        return measureIndex + 1
    }
    
    /// Calculates time position from measure number and offset
    static func timePosition(measureNumber: Int, measureOffset: Double) -> Double {
        return Double(toZeroBasedIndex(measureNumber)) + measureOffset
    }
    
    /// Extracts measure index from time position
    static func measureIndex(from timePosition: Double) -> Int {
        return Int(timePosition)
    }
}

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
    let chart: Chart
    
    // Cache SwiftData relationships to avoid main thread blocking
    @State private var cachedSong: Song?
    @State private var cachedNotes: [Note] = []
    @State private var isDataLoaded = false
    
    // Create a computed DrumTrack for backward compatibility
    private var track: DrumTrack {
        DrumTrack(chart: chart)
    }
    @State private var isPlaying = false
    @State private var playbackProgress: Double = 0.0
    @State private var currentBeat: Int = 0
    @State private var playbackTimer: Timer?
    @State private var playbackStartTime: Date?
    @State private var pausedElapsedTime: Double = 0.0
    @State private var cachedDrumBeats: [DrumBeat] = []
    @State private var bgmPlayer: AVAudioPlayer?
    @State private var bgmLoadingError: String?
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
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .background(Color.black)
        .foregroundColor(.white)
        .task {
            // Load SwiftData relationships asynchronously to avoid blocking main thread
            await loadChartData()
        }
        .onAppear {
            Logger.userAction("Opened gameplay view for track: \(track.title)")
            // Only proceed if data is loaded
            if isDataLoaded {
                setupGameplay()
            }
        }
        .onDisappear {
            playbackTimer?.invalidate()
            playbackTimer = nil
            metronome.stop()
            bgmPlayer?.stop()
            bgmPlayer = nil
        }
    }
    
    // MARK: - Sheet Music View
    private func sheetMusicView(geometry: GeometryProxy) -> some View {
        let maxIndex = (cachedDrumBeats.map { 
            MeasureUtils.measureIndex(from: $0.timePosition) 
        }.max() ?? 0)
        let measuresCount = max(1, maxIndex + 1)
        let measurePositions = GameplayLayout.calculateMeasurePositions(
            totalMeasures: measuresCount, 
            timeSignature: track.timeSignature
        )
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
                let measureIndex = MeasureUtils.measureIndex(from: beat.timePosition)
                
                if let measurePos = measurePositions.first(where: { $0.measureIndex == measureIndex }) {
                    // Calculate precise beat position within the measure based on measureOffset
                    let beatOffsetInMeasure = beat.timePosition - Double(measureIndex)
                    let beatPosition = beatOffsetInMeasure * Double(track.timeSignature.beatsPerMeasure)
                    // Use precise beat positioning system
                    let beatX = GameplayLayout.preciseNoteXPosition(measurePosition: measurePos, beatPosition: beatPosition, timeSignature: track.timeSignature)
                    
                    // Use the center of the staff area as the reference point for individual drum positioning
                    let staffCenterY = GameplayLayout.StaffLinePosition.line3.absoluteY(for: measurePos.row)
                    
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
                        y: staffCenterY
                    )
                }
            }
        }
    }
    
    // MARK: - BGM Setup
    private func setupBGMPlayer() {
        guard let song = cachedSong,
              let bgmFilePath = song.bgmFilePath,
              !bgmFilePath.isEmpty else {
            Logger.audioPlayback("No BGM file available for track: \(track.title)")
            return
        }
        
        let bgmURL = URL(fileURLWithPath: bgmFilePath)
        
        do {
            bgmPlayer = try AVAudioPlayer(contentsOf: bgmURL)
            bgmPlayer?.prepareToPlay()
            bgmPlayer?.volume = 0.7 // Set BGM volume lower than metronome
            Logger.audioPlayback("BGM player setup successful for track: \(track.title)")
        } catch {
            bgmLoadingError = "Failed to load BGM: \(error.localizedDescription)"
            Logger.audioPlayback("Failed to setup BGM player for track \(track.title): \(error.localizedDescription)")
        }
    }
    
    // MARK: - Data Loading
    @MainActor
    private func loadChartData() async {
        // Cache SwiftData relationships in background to avoid main thread blocking
        cachedSong = chart.song
        cachedNotes = chart.notes.map { $0 } // Copy notes to avoid relationship access
        
        await MainActor.run {
            isDataLoaded = true
            // Setup gameplay once data is loaded
            setupGameplay()
        }
    }
    
    private func setupGameplay() {
        computeDrumBeats()
        metronome.configure(bpm: track.bpm, timeSignature: track.timeSignature)
        setupBGMPlayer()
        // Don't auto-start playback - wait for user to click play
    }
    
    // MARK: - Helper Methods
    private func computeDrumBeats() {
        // Use cached notes instead of accessing relationship directly
        if cachedNotes.isEmpty {
            cachedDrumBeats = []
            return
        }
        
        // Debug: Check what note types we have in cachedNotes
        let noteTypeCounts = Dictionary(grouping: cachedNotes) { $0.noteType }
            .mapValues { $0.count }
        Logger.debug("CachedNotes by noteType: \(noteTypeCounts)")
        
        // Debug: Specifically check for hiHatPedal notes
        let hiHatPedalNotes = cachedNotes.filter { $0.noteType == .hiHatPedal }
        Logger.debug("Found \(hiHatPedalNotes.count) hiHatPedal notes in cachedNotes")
        for note in hiHatPedalNotes {
            Logger.debug("HiHatPedal note: measure \(note.measureNumber), offset \(note.measureOffset), interval \(note.interval.rawValue)")
        }
        
        // Group notes by their position in the measure using a hashable key to avoid floating-point precision issues
        let groupedNotes = Dictionary(grouping: cachedNotes) { note in
            NotePositionKey(measureNumber: note.measureNumber, measureOffset: note.measureOffset)
        }
        
        // Convert to DrumBeat objects
        cachedDrumBeats = groupedNotes.map { (positionKey, notes) in
            // Convert 1-based measure numbers to 0-based for indexing
            let timePosition = MeasureUtils.timePosition(measureNumber: positionKey.measureNumber, measureOffset: positionKey.measureOffset)
            
            // Debug: Check what note types we have at this position
            let noteTypes = notes.map { $0.noteType }
            if noteTypes.contains(.hiHatPedal) {
                Logger.debug("Found hiHatPedal note at measure \(positionKey.measureNumber), offset \(positionKey.measureOffset)")
            }
            
            let drumTypes = notes.compactMap { note in
                let drumType = DrumType.from(noteType: note.noteType)
                if note.noteType == .hiHatPedal {
                    Logger.debug("Converting hiHatPedal noteType to drumType: \(drumType?.description ?? "nil")")
                }
                return drumType
            }
            
            // Debug: Check if hiHatPedal made it through the conversion
            if drumTypes.contains(.hiHatPedal) {
                Logger.debug("Successfully converted hiHatPedal to drumType at time position \(timePosition)")
            }
            
            // Use the interval from the first note in the group (they should all have the same interval at the same position)
            let interval = notes.first?.interval ?? .quarter
            return DrumBeat(id: Int(timePosition * 1000), drums: drumTypes, timePosition: timePosition, interval: interval)
        }
        .sorted { $0.timePosition < $1.timePosition }
        
        Logger.debug("Computed \(cachedDrumBeats.count) drum beats for track: \(track.title)")
        
        // Debug: Check for hi-hat pedal notes specifically
        let hiHatPedalBeats = cachedDrumBeats.filter { beat in
            beat.drums.contains(.hiHatPedal)
        }
        Logger.debug("Found \(hiHatPedalBeats.count) hi-hat pedal beats")
        for beat in hiHatPedalBeats {
            Logger.debug("Hi-hat pedal beat at time position: \(beat.timePosition), drums: \(beat.drums)")
        }
    }
    
    // Calculate actual track duration in seconds based on measures and BPM
    private var actualTrackDuration: Double {
        // Find the total number of measures based on the highest measure number
        let maxIndex = (cachedDrumBeats.map { MeasureUtils.measureIndex(from: $0.timePosition) }.max() ?? 0)
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
            pausePlayback()
        }
    }
    
    private func pausePlayback() {
        playbackTimer?.invalidate()
        playbackTimer = nil
        
        // Save elapsed time when pausing
        if let startTime = playbackStartTime {
            pausedElapsedTime += Date().timeIntervalSince(startTime)
        }
        playbackStartTime = nil
        
        bgmPlayer?.pause()
        Logger.audioPlayback("Paused playback for track: \(track.title)")
    }
    
    private func startPlayback() {
        isPlaying = true
        playbackStartTime = Date()
        playbackTimer?.invalidate()
        
        // Start BGM playback if available
        if let bgmPlayer = bgmPlayer {
            // Check if BGM was previously paused and resume from current position
            if bgmPlayer.currentTime > 0 && !bgmPlayer.isPlaying {
                bgmPlayer.play()
                Logger.audioPlayback("Resumed BGM playback for track: \(track.title)")
            } else {
                // Start from beginning
                bgmPlayer.currentTime = 0
                bgmPlayer.play()
                Logger.audioPlayback("Started BGM playback for track: \(track.title)")
            }
        }
        
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
            
            let currentSessionTime = Date().timeIntervalSince(startTime)
            let elapsedTime = pausedElapsedTime + currentSessionTime
            let trackDuration = actualTrackDuration
            
            // Calculate current beat position based on BPM timing
            let secondsPerBeat = 60.0 / Double(track.bpm)
            let secondsPerMeasure = secondsPerBeat * Double(track.timeSignature.beatsPerMeasure)
            let currentTimePosition = elapsedTime / secondsPerMeasure
            
            // Find the beat that should be active at this time position
            var activeBeatIndex = 0
            for (index, beat) in cachedDrumBeats.enumerated() {
                if beat.timePosition <= currentTimePosition {
                    activeBeatIndex = index
                } else {
                    break
                }
            }
            
            currentBeat = activeBeatIndex
            playbackProgress = min(elapsedTime / trackDuration, 1.0)
            
            if playbackProgress >= 1.0 {
                timer.invalidate()
                isPlaying = false
                playbackProgress = 0.0
                currentBeat = 0
                playbackStartTime = nil
                pausedElapsedTime = 0.0  // Reset paused time when playback finishes
                bgmPlayer?.stop()
                Logger.audioPlayback("Playback finished for track: \(track.title)")
            }
        }
    }
    
    private func restartPlayback() {
        playbackProgress = 0.0
        currentBeat = 0
        playbackStartTime = nil
        pausedElapsedTime = 0.0  // Reset paused time on restart
        bgmPlayer?.stop()
        bgmPlayer?.currentTime = 0
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
        pausedElapsedTime = 0.0  // Reset paused time on skip to end
        bgmPlayer?.stop()
        Logger.audioPlayback("Skipped to end for track: \(track.title)")
    }
}

#Preview {
    GameplayView(chart: Song.sampleData.first!.charts.first!)
        .environmentObject(MetronomeEngine())
}
