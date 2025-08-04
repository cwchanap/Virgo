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
    
    // Cache DrumTrack to avoid creating new objects on every access
    @State private var track: DrumTrack?
    @State private var isPlaying = false
    @State private var playbackProgress: Double = 0.0
    @State private var currentBeat: Int = 0
    @State private var currentQuarterNotePosition: Double = 0.0
    @State private var totalBeatsElapsed: Int = 0
    @State private var currentBeatPosition: Double = 0.0  // Current beat position within measure (0, 0.25, 0.5, 0.75)
    @State private var currentMeasureIndex: Int = 0       // Which measure we're currently in
    @State private var playbackTimer: Timer?
    @State private var playbackStartTime: Date?
    @State private var pausedElapsedTime: Double = 0.0
    @State private var lastBeatUpdate: Int = -1
    @State private var cachedDrumBeats: [DrumBeat] = []
    @State private var cachedMeasurePositions: [GameplayLayout.MeasurePosition] = []
    @State private var cachedBeamGroups: [BeamGroup] = []
    @State private var beatToBeamGroupMap: [Int: BeamGroup] = [:]
    @State private var cachedTrackDuration: Double = 0.0
    @State private var cachedBeatIndices: [Int] = []
    @State private var measurePositionMap: [Int: GameplayLayout.MeasurePosition] = [:]
    @State private var bgmPlayer: AVAudioPlayer?
    @State private var bgmLoadingError: String?
    @State private var metronome = MetronomeEngine()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Header with track info and controls
                GameplayHeaderView(
                    track: track ?? DrumTrack(chart: chart),
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
                    track: track ?? DrumTrack(chart: chart),
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
            Logger.userAction("Opened gameplay view for track: \(track?.title ?? "Unknown")")
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
        let totalHeight = GameplayLayout.totalHeight(for: cachedMeasurePositions)
        
        return ScrollView([.horizontal, .vertical], showsIndicators: false) {
            ZStack(alignment: .topLeading) {
                // Staff lines background
                staffLinesView(measurePositions: cachedMeasurePositions)
                
                // Bar lines
                barLinesView(measurePositions: cachedMeasurePositions)
                
                // Clefs and time signatures for each row
                clefsAndTimeSignaturesView(measurePositions: cachedMeasurePositions)
                
                    // Drum notation
                drumNotationView(measurePositions: cachedMeasurePositions)
                
                // Time-based beat progression bars (purple bars at all quarter note positions)
                timeBasedBeatProgressionBars(measurePositions: cachedMeasurePositions)
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
                    TimeSignatureSymbol(timeSignature: track?.timeSignature ?? TimeSignature.fourFour)
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
                let measureWidth = GameplayLayout.measureWidth(for: track?.timeSignature ?? TimeSignature.fourFour)
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
        return ZStack {
            // Render beams first (behind notes)
            ForEach(cachedBeamGroups, id: \.id) { beamGroup in
                BeamGroupView(
                    beamGroup: beamGroup,
                    measurePositions: measurePositions,
                    timeSignature: track?.timeSignature ?? TimeSignature.fourFour,
                    isActive: false // Keep disabled for performance
                )
            }
            
            // Then render individual notes
            ForEach(cachedBeatIndices, id: \.self) { index in
                let beat = cachedDrumBeats[index]
                // Find which measure this beat belongs to based on the measure number in the beat
                let measureIndex = MeasureUtils.measureIndex(from: beat.timePosition)
                
                if let measurePos = measurePositionMap[measureIndex] {
                    // Calculate precise beat position within the measure based on measureOffset
                    let beatOffsetInMeasure = beat.timePosition - Double(measureIndex)
                    let beatPosition = beatOffsetInMeasure * Double(track?.timeSignature.beatsPerMeasure ?? 4)
                    // Use precise beat positioning system
                    let beatX = GameplayLayout.preciseNoteXPosition(measurePosition: measurePos, beatPosition: beatPosition, timeSignature: track?.timeSignature ?? TimeSignature.fourFour)
                    
                    // Use the center of the staff area as the reference point for individual drum positioning
                    let staffCenterY = GameplayLayout.StaffLinePosition.line3.absoluteY(for: measurePos.row)
                    
                    // Use cached lookup map for O(1) beam group check
                    let isBeamed = beatToBeamGroupMap[beat.id] != nil
                    
                    // FIXED: Use timer-based values for note highlighting (same as purple bar)
                    // SwiftUI won't update for non-@Published metronome methods, so use our timer values
                    // Use floor to get the current beat index (0,1,2,3 for quarter notes)
                    let displayBeat = Int(floor(currentBeatPosition * Double(track?.timeSignature.beatsPerMeasure ?? 4)))
                    let displayMeasure = currentMeasureIndex
                    
                    // Convert to time position for comparison with beat.timePosition
                    let currentTimePosition = Double(displayMeasure) + (Double(displayBeat) / Double(track?.timeSignature.beatsPerMeasure ?? 4))
                    let timeTolerance = 0.05 // Small tolerance for time-based matching
                    let isCurrentlyActive = isPlaying && abs(beat.timePosition - currentTimePosition) < timeTolerance
                    
                    DrumBeatView(
                        beat: beat, 
                        isActive: isCurrentlyActive,
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
    
    // MARK: - Beat Progression Indicator
    private func beatProgressionIndicator(measurePositions: [GameplayLayout.MeasurePosition]) -> some View {
        Group {
            if isPlaying {
                // Always try to get the measure position, with fallback to measure 0
                let measurePos = measurePositionMap[currentMeasureIndex] ?? measurePositionMap[0]
                
                if let measurePos = measurePos {
                    // Calculate X position based on current beat position within measure
                    let beatPosition = currentBeatPosition * Double(track?.timeSignature.beatsPerMeasure ?? 4)
                    let indicatorX = GameplayLayout.preciseNoteXPosition(
                        measurePosition: measurePos, 
                        beatPosition: beatPosition, 
                        timeSignature: track?.timeSignature ?? TimeSignature.fourFour
                    )
                    
                    // Position at center of staff
                    let staffCenterY = GameplayLayout.StaffLinePosition.line3.absoluteY(for: measurePos.row)
                    
                    // Red circle indicator
                    Circle()
                        .fill(Color.red.opacity(0.8))
                        .frame(width: 12, height: 12)
                        .position(x: indicatorX, y: staffCenterY)
                        .animation(.easeInOut(duration: 0.1), value: indicatorX)
                }
            }
        }
    }
    
    // MARK: - Time-Based Beat Progression Bars
    private func timeBasedBeatProgressionBars(measurePositions: [GameplayLayout.MeasurePosition]) -> some View {
        Group {
            if isPlaying, let track = track {
                // FIXED: Use timer-based values that trigger SwiftUI updates
                // SwiftUI won't update for non-@Published metronome methods, so use our timer values
                let displayMeasure = currentMeasureIndex
                
                // Get measure position from display timing
                let measurePos = measurePositionMap[displayMeasure] ?? measurePositionMap[0]
                
                if let measurePos = measurePos {
                    // currentBeatPosition is now fractional (0.0-1.0), need to convert to beat index (0-3 for 4/4)
                    let beatPosition = currentBeatPosition * Double(track.timeSignature.beatsPerMeasure)
                    
                    // Calculate exact X position using metronome measure position
                    let indicatorX = GameplayLayout.preciseNoteXPosition(
                        measurePosition: measurePos,
                        beatPosition: beatPosition,
                        timeSignature: track.timeSignature
                    )
                    
                    // Position at center of staff
                    let staffCenterY = GameplayLayout.StaffLinePosition.line3.absoluteY(for: measurePos.row)
                    
                    Rectangle()
                        .frame(width: GameplayLayout.beatColumnWidth, height: GameplayLayout.staffHeight)
                        .foregroundColor(Color.purple.opacity(GameplayLayout.activeOpacity))
                        .cornerRadius(GameplayLayout.beatColumnCornerRadius)
                        .position(x: indicatorX, y: staffCenterY)
                }
            }
        }
    }
    
    // MARK: - BGM Setup
    private func setupBGMPlayer() {
        guard let song = cachedSong,
              let bgmFilePath = song.bgmFilePath,
              !bgmFilePath.isEmpty else {
            Logger.audioPlayback("No BGM file available for track: \(track?.title ?? "Unknown")")
            return
        }
        
        let bgmURL = URL(fileURLWithPath: bgmFilePath)
        
        do {
            bgmPlayer = try AVAudioPlayer(contentsOf: bgmURL)
            bgmPlayer?.prepareToPlay()
            bgmPlayer?.volume = 0.7 // Set BGM volume lower than metronome
            Logger.audioPlayback("BGM player setup successful for track: \(track?.title ?? "Unknown")")
        } catch {
            bgmLoadingError = "Failed to load BGM: \(error.localizedDescription)"
            Logger.audioPlayback("Failed to setup BGM player for track \(track?.title ?? "Unknown"): \(error.localizedDescription)")
        }
    }
    
    // MARK: - Data Loading
    @MainActor
    private func loadChartData() async {
        // Cache SwiftData relationships in background to avoid main thread blocking
        cachedSong = chart.song
        cachedNotes = chart.notes.map { $0 } // Copy notes to avoid relationship access
        
        await MainActor.run {
            // Cache track object
            track = DrumTrack(chart: chart)
            isDataLoaded = true
            // Setup gameplay once data is loaded
            setupGameplay()
        }
    }
    
    private func setupGameplay() {
        guard let track = track else { return }
        computeDrumBeats()
        computeCachedLayoutData()
        metronome.configure(bpm: track.bpm, timeSignature: track.timeSignature)
        setupBGMPlayer()
        // Cache track duration
        cachedTrackDuration = calculateTrackDuration()
        // Don't auto-start playback - wait for user to click play
    }
    
    private func computeCachedLayoutData() {
        // Cache measure positions based on actual track duration for complete beat progression support
        guard let track = track else { return }
        
        // Calculate total measures needed for the full track duration
        // This ensures beat progression works throughout the entire playback, not just where notes exist
        let secondsPerBeat = 60.0 / Double(track.bpm)
        let secondsPerMeasure = secondsPerBeat * Double(track.timeSignature.beatsPerMeasure)
        
        // Use track duration from song metadata if available, otherwise calculate from notes
        let trackDurationInSeconds: Double
        if let song = cachedSong, !song.duration.isEmpty && song.duration != "0:00" {
            // Parse duration string (format: "M:SS" or "MM:SS")
            let components = song.duration.split(separator: ":")
            if components.count == 2,
               let minutes = Double(components[0]),
               let seconds = Double(components[1]) {
                trackDurationInSeconds = minutes * 60 + seconds
            } else {
                // Fallback to calculated duration
                let maxIndex = (cachedDrumBeats.map { 
                    MeasureUtils.measureIndex(from: $0.timePosition) 
                }.max() ?? 0)
                let noteMeasures = max(1, maxIndex + 1)
                trackDurationInSeconds = Double(noteMeasures) * secondsPerMeasure
            }
        } else {
            // Calculate from notes
            let maxIndex = (cachedDrumBeats.map { 
                MeasureUtils.measureIndex(from: $0.timePosition) 
            }.max() ?? 0)
            let noteMeasures = max(1, maxIndex + 1)
            trackDurationInSeconds = Double(noteMeasures) * secondsPerMeasure
        }
        
        // Calculate total measures needed for full track
        let totalMeasuresForDuration = Int(ceil(trackDurationInSeconds / secondsPerMeasure))
        // CRITICAL: Always ensure measure 0 exists, even if no notes are there
        // Beat progression must start at measure 0 following metronome timing
        let measuresCount = max(1, totalMeasuresForDuration)
        
        cachedMeasurePositions = GameplayLayout.calculateMeasurePositions(
            totalMeasures: measuresCount, 
            timeSignature: track.timeSignature
        )
        
        // Cache beam groups and create lookup map
        cachedBeamGroups = BeamGroupingHelper.calculateBeamGroups(from: cachedDrumBeats)
        
        // Create efficient lookup map for beat-to-beam-group relationships
        beatToBeamGroupMap = [:]
        for beamGroup in cachedBeamGroups {
            for beat in beamGroup.beats {
                beatToBeamGroupMap[beat.id] = beamGroup
            }
        }
        
        // Create efficient lookup map for measure positions (O(1) access)
        measurePositionMap = [:]
        for position in cachedMeasurePositions {
            measurePositionMap[position.measureIndex] = position
        }
        
        // CRITICAL: Ensure measure 0 always exists for beat progression to start at beginning
        if measurePositionMap[0] == nil {
            Logger.warning("Measure 0 missing from measurePositionMap! Creating fallback measure 0.")
            // Create measure 0 as fallback to ensure beat progression can start
            let measure0 = GameplayLayout.MeasurePosition(row: 0, xOffset: GameplayLayout.leftMargin, measureIndex: 0)
            measurePositionMap[0] = measure0
        }
    }
    
    // MARK: - Helper Methods
    private func computeDrumBeats() {
        // Use cached notes instead of accessing relationship directly
        if cachedNotes.isEmpty {
            cachedDrumBeats = []
            return
        }
        
        // Group notes by their position in the measure using a hashable key to avoid floating-point precision issues
        let groupedNotes = Dictionary(grouping: cachedNotes) { note in
            NotePositionKey(measureNumber: note.measureNumber, measureOffset: note.measureOffset)
        }
        
        // Convert to DrumBeat objects
        cachedDrumBeats = groupedNotes.map { (positionKey, notes) in
            // Convert 1-based measure numbers to 0-based for indexing
            let timePosition = MeasureUtils.timePosition(measureNumber: positionKey.measureNumber, measureOffset: positionKey.measureOffset)
            
            let drumTypes = notes.compactMap { note in
                DrumType.from(noteType: note.noteType)
            }
            
            // Use the interval from the first note in the group (they should all have the same interval at the same position)
            let interval = notes.first?.interval ?? .quarter
            return DrumBeat(id: Int(timePosition * 1000), drums: drumTypes, timePosition: timePosition, interval: interval)
        }
        .sorted { $0.timePosition < $1.timePosition }
        
        // Cache indices to avoid enumeration on every render
        cachedBeatIndices = Array(0..<cachedDrumBeats.count)
    }
    
    // Calculate track duration once and cache it
    private func calculateTrackDuration() -> Double {
        guard let track = track else { return 0.0 }
        
        // Calculate duration per measure in seconds
        let secondsPerBeat = 60.0 / Double(track.bpm)
        let secondsPerMeasure = secondsPerBeat * Double(track.timeSignature.beatsPerMeasure)
        
        // Use track duration from song metadata if available, otherwise calculate from notes
        if let song = cachedSong, !song.duration.isEmpty && song.duration != "0:00" {
            // Parse duration string (format: "M:SS" or "MM:SS")
            let components = song.duration.split(separator: ":")
            if components.count == 2,
               let minutes = Double(components[0]),
               let seconds = Double(components[1]) {
                return minutes * 60 + seconds
            }
        }
        
        // Fallback: calculate from the highest measure number with notes
        let maxIndex = (cachedDrumBeats.map { MeasureUtils.measureIndex(from: $0.timePosition) }.max() ?? 0)
        let totalMeasures = max(1, maxIndex + 1)
        
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
        
        // Stop metronome
        metronome.stop()
        
        // Save elapsed time when pausing
        if let startTime = playbackStartTime {
            pausedElapsedTime += Date().timeIntervalSince(startTime)
        }
        playbackStartTime = nil
        
        bgmPlayer?.pause()
        Logger.audioPlayback("Paused playback for track: \(track?.title ?? "Unknown")")
    }
    
    private func startPlayback() {
        isPlaying = true
        
        // Start metronome first for timing synchronization
        metronome.start()
        
        // Set start time after metronome starts to ensure sync
        playbackStartTime = Date()
        playbackTimer?.invalidate()
        
        // Start BGM playback if available
        if let bgmPlayer = bgmPlayer {
            // Check if BGM was previously paused and resume from current position
            if bgmPlayer.currentTime > 0 && !bgmPlayer.isPlaying {
                bgmPlayer.play()
                Logger.audioPlayback("Resumed BGM playback for track: \(track?.title ?? "Unknown")")
            } else {
                // Start from beginning
                bgmPlayer.currentTime = 0
                bgmPlayer.play()
                Logger.audioPlayback("Started BGM playback for track: \(track?.title ?? "Unknown")")
            }
        }
        
        Logger.audioPlayback("Started playback for track: \(track?.title ?? "Unknown")")
        
        // Initialize playback position
        currentBeat = 0
        currentQuarterNotePosition = 0.0
        totalBeatsElapsed = 0
        lastBeatUpdate = -1
        currentBeatPosition = 0.0
        currentMeasureIndex = 0
        
        // CRITICAL: Force immediate UI update to show purple bar at position 0 from the start
        // This ensures the purple bar appears at beat 0 before the first timer update
        playbackProgress = 0.0
        
        // Re-enable timer now that MetronomeEngine threading is fixed
        // Use background queue timer to avoid blocking main thread
        let backgroundQueue = DispatchQueue(label: "playback.timer", qos: .userInitiated)
        
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { timer in
            backgroundQueue.async {
                self.updatePlaybackPosition(timer: timer)
            }
        }
    }
    
    private func updatePlaybackPosition(timer: Timer) {
        guard isPlaying else {
            DispatchQueue.main.async {
                timer.invalidate()
            }
            return
        }
        
        // Calculate progress based on actual elapsed time
        guard let startTime = playbackStartTime else { return }
        let currentSessionTime = Date().timeIntervalSince(startTime)
        let elapsedTime = pausedElapsedTime + currentSessionTime
        
        // FIXED: Use time-based calculation for smooth progression
        guard let track = track else { return }
        
        // Calculate position based on elapsed time for smooth progression
        let secondsPerBeat = 60.0 / Double(track.bpm)
        let beatsElapsed = elapsedTime / secondsPerBeat
        
        // Convert to measure and beat position
        let totalBeats = Int(beatsElapsed)
        let newMeasureIndex = totalBeats / track.timeSignature.beatsPerMeasure
        let beatWithinMeasure = totalBeats % track.timeSignature.beatsPerMeasure
        let newBeatPosition = Double(beatWithinMeasure) / Double(track.timeSignature.beatsPerMeasure)
        
        // Find the closest actual beat index for highlighting existing notes
        var newBeatIndex = 0
        if !cachedDrumBeats.isEmpty {
            var left = 0
            var right = cachedDrumBeats.count - 1
            
            while left <= right {
                let mid = (left + right) / 2
                let currentTimePosition = Double(newMeasureIndex) + newBeatPosition
                if cachedDrumBeats[mid].timePosition <= currentTimePosition {
                    newBeatIndex = mid
                    left = mid + 1
                } else {
                    right = mid - 1
                }
            }
        }
        
        // Calculate other values based on time-based timing
        let newTotalBeats = Int(beatsElapsed)
        let trackDuration = cachedTrackDuration
        let newProgress = min(elapsedTime / trackDuration, 1.0)
        
        // Only update UI on main thread if something actually changed
        DispatchQueue.main.async {
            var shouldUpdateUI = false
            
            // Only update currentBeat if it actually changed to reduce UI re-renders
            if newBeatIndex != currentBeat {
                currentBeat = newBeatIndex
                shouldUpdateUI = true
            }
            
            // Update beat position for progression indicator
            if abs(newBeatPosition - currentBeatPosition) > 0.005 || newMeasureIndex != currentMeasureIndex {
                currentBeatPosition = newBeatPosition
                currentMeasureIndex = newMeasureIndex
                shouldUpdateUI = true
            }
            
            // Only update timing values if they changed significantly
            if newTotalBeats != totalBeatsElapsed {
                totalBeatsElapsed = newTotalBeats
                currentQuarterNotePosition = Double(newMeasureIndex) + newBeatPosition
                shouldUpdateUI = true
            }
            
            // Update progress less frequently to reduce UI churn
            if abs(playbackProgress - newProgress) > 0.02 {
                playbackProgress = newProgress
                shouldUpdateUI = true
            }
            
            // Only process updates if something actually changed
            if !shouldUpdateUI {
                return
            }
            
            if playbackProgress >= 1.0 {
                timer.invalidate()
                isPlaying = false
                metronome.stop()
                playbackProgress = 0.0
                currentBeat = 0
                currentQuarterNotePosition = 0.0
                totalBeatsElapsed = 0
                lastBeatUpdate = -1
                currentBeatPosition = 0.0
                currentMeasureIndex = 0
                playbackStartTime = nil
                pausedElapsedTime = 0.0
                bgmPlayer?.stop()
                Logger.audioPlayback("Playback finished for track: \(track.title)")
            }
        }
    }
    
    private func restartPlayback() {
        playbackProgress = 0.0
        currentBeat = 0
        currentQuarterNotePosition = 0.0
        totalBeatsElapsed = 0
        lastBeatUpdate = -1
        currentBeatPosition = 0.0
        currentMeasureIndex = 0
        playbackStartTime = nil
        pausedElapsedTime = 0.0  // Reset paused time on restart
        metronome.stop()
        bgmPlayer?.stop()
        bgmPlayer?.currentTime = 0
        Logger.audioPlayback("Restarted playback for track: \(track?.title ?? "Unknown")")
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
        Logger.audioPlayback("Skipped to end for track: \(track?.title ?? "Unknown")")
    }
}

#Preview {
    GameplayView(chart: Song.sampleData.first!.charts.first!)
}
