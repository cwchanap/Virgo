//
//  GameplayView.swift
//  Virgo
//
//  Created by Chan Wai Chan on 30/6/2025.
//

import SwiftUI
import AVFoundation
import Combine

struct GameplayView: View {
    let chart: Chart

    // Cache SwiftData relationships to avoid main thread blocking
    @State var cachedSong: Song?
    @State var cachedNotes: [Note] = []
    @State var isDataLoaded = false

    // Cache DrumTrack to avoid creating new objects on every access
    @State var track: DrumTrack?
    @State var isPlaying = false
    @State var playbackProgress: Double = 0.0
    @State var currentBeat: Int = 0
    @State var currentQuarterNotePosition: Double = 0.0
    @State var totalBeatsElapsed: Int = 0
    @State var currentBeatPosition: Double = 0.0  // Current beat position within measure (discretized)
    @State var rawBeatPosition: Double = 0.0     // Raw continuous beat position for purple bar sync
    @State var currentMeasureIndex: Int = 0       // Which measure we're currently in
    @State var lastMetronomeBeat: Int = 0        // Track previous beat to detect actual beat changes
    @State var lastDiscreteBeat: Int = -1        // Track last discrete beat to prevent unnecessary updates
    @State var playbackTimer: Timer?
    @State var playbackStartTime: Date?
    @State var pausedElapsedTime: Double = 0.0
    @State var lastBeatUpdate: Int = -1
    @State var cachedDrumBeats: [DrumBeat] = []
    @State var cachedMeasurePositions: [GameplayLayout.MeasurePosition] = []
    @State var cachedBeamGroups: [BeamGroup] = []
    @State var beatToBeamGroupMap: [Int: BeamGroup] = [:]
    @State var cachedTrackDuration: Double = 0.0
    @State var cachedBeatIndices: [Int] = []
    @State var measurePositionMap: [Int: GameplayLayout.MeasurePosition] = [:]
    // PERFORMANCE FIX: Cache expensive position calculations to avoid per-frame computation
    @State var cachedBeatPositions: [Int: (x: Double, y: Double)] = [:]
    // CRITICAL PERFORMANCE FIX: Cache which beat is currently active to avoid per-beat calculations
    @State var activeBeatId: Int?
    // PERFORMANCE FIX: Cache purple bar position to avoid expensive calculation every update
    @State var purpleBarPosition: (x: Double, y: Double)?
    @State var bgmPlayer: AVAudioPlayer?
    @State var bgmLoadingError: String?
    @State var bgmOffsetSeconds: Double = 0.0  // BGM start offset in seconds
    // PERFORMANCE FIX: Don't use @EnvironmentObject for metronome to avoid massive UI re-renders
    // GameplayView only needs method calls (start/stop/configure), not @Published state updates
    let metronome: MetronomeEngine
    @State var staticStaffLinesView: AnyView?
    @State var inputManager = InputManager()
    @State var inputHandler = GameplayInputHandler()
    @State private var metronomeSubscription: AnyCancellable?
    @Environment(\.dismiss) private var dismiss

    // PERFORMANCE FIX: Accept metronome as parameter instead of @EnvironmentObject
    init(chart: Chart, metronome: MetronomeEngine) {
        self.chart = chart
        self.metronome = metronome
    }

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
                controlsView
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
            // Setup InputManager delegate
            inputManager.delegate = inputHandler
            // CRITICAL FIX: Setup metronome subscription for comprehensive visual sync
            // Use metronome as the single source of timing truth for all visual updates
            metronomeSubscription = metronome.$currentBeat
                .sink { currentBeat in
                    // Only update when discrete beat position changes to avoid excessive updates
                    if isPlaying && currentBeat != lastMetronomeBeat {
                        lastMetronomeBeat = currentBeat
                        
                        // TIMING SYNC: Update all visual elements using metronome timing
                        updateVisualElementsFromMetronome()
                    }
                }
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
            inputManager.stopListening()
            metronomeSubscription?.cancel()
            metronomeSubscription = nil
        }
    }

    // MARK: - BGM Setup
    func setupBGMPlayer() {
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
            let errorMessage = "Failed to setup BGM player for track \(track?.title ?? "Unknown"): " +
                               "\(error.localizedDescription)"
            Logger.audioPlayback(errorMessage)
        }
    }

    // MARK: - Data Loading
    @MainActor
    func loadChartData() async {
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

    func setupGameplay() {
        guard let track = track else { return }
        computeDrumBeats()
        computeCachedLayoutData()
        // Calculate BGM offset from first BGM note (lane 01) position
        bgmOffsetSeconds = calculateBGMOffset()
        // Configure shared metronome instead of creating a new instance
        metronome.configure(bpm: track.bpm, timeSignature: track.timeSignature)
        setupBGMPlayer()
        // Cache track duration
        cachedTrackDuration = calculateTrackDuration()
        // Configure InputManager with song data
        inputManager.configure(bpm: track.bpm, timeSignature: track.timeSignature, notes: cachedNotes)
        // Don't auto-start playback - wait for user to click play
    }

    func computeCachedLayoutData() {
        // Cache measure positions based on actual track duration for complete beat progression support
        guard let track = track else { return }

        // Calculate total measures needed for the full track duration
        // This ensures beat progression works throughout the entire playback, not just where notes exist
        let secondsPerBeat = 60.0 / track.bpm
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
        // Create static staff lines view once and cache it
        staticStaffLinesView = AnyView(StaffLinesBackgroundView(measurePositions: cachedMeasurePositions))

        // CRITICAL: Ensure measure 0 always exists for beat progression to start at beginning
        if measurePositionMap[0] == nil {
            let warningMessage = "Measure 0 missing from measurePositionMap! Creating fallback measure 0."
            Logger.warning(warningMessage)
            // Create measure 0 as fallback to ensure beat progression can start
            let measure0 = GameplayLayout.MeasurePosition(row: 0, 
                                                          xOffset: GameplayLayout.leftMargin, 
                                                          measureIndex: 0)
            measurePositionMap[0] = measure0
        }

        // PERFORMANCE FIX: Pre-cache all beat positions to avoid expensive per-frame calculations
        cacheBeatPositions()
    }

    // MARK: - Helper Methods
    
    func cacheBeatPositions() {
        guard let track = track else { return }
        
        cachedBeatPositions = [:]
        
        for beat in cachedDrumBeats {
            let measureIndex = MeasureUtils.measureIndex(from: beat.timePosition)
            
            if let measurePos = measurePositionMap[measureIndex] {
                let beatOffsetInMeasure = beat.timePosition - Double(measureIndex)
                // FIX: beatOffsetInMeasure is already in the correct units (0.0 to 1.0 = full measure)
                // We need to convert to beat position within the measure (0.0 to beatsPerMeasure)
                let beatPosition = beatOffsetInMeasure * Double(track.timeSignature.beatsPerMeasure)
                let beatX = GameplayLayout.preciseNoteXPosition(measurePosition: measurePos,
                                                              beatPosition: beatPosition,
                                                              timeSignature: track.timeSignature)
                let staffCenterY = GameplayLayout.StaffLinePosition.line3.absoluteY(for: measurePos.row)
                
                cachedBeatPositions[beat.id] = (x: Double(beatX), y: Double(staffCenterY))
                
                // DEBUG: Log detailed position calculations for each beat
                Logger.debug("CACHED POSITION: id=\(beat.id), timePos=\(beat.timePosition), " +
                           "measureIdx=\(measureIndex), beatOffset=\(beatOffsetInMeasure), " +
                           "beatPos=\(beatPosition), x=\(beatX)")
            }
        }
        
        Logger.debug("Cached \(cachedBeatPositions.count) beat positions for performance optimization")
    }
    
    func updateActiveBeat() {
        guard let track = track, isPlaying else { 
            activeBeatId = nil
            return 
        }
        
        // FIX: Use same discrete beat calculation as purple bar for perfect sync
        guard let elapsedTime = calculateElapsedTime() else {
            activeBeatId = nil
            return
        }
        
        let secondsPerBeat = 60.0 / track.bpm
        let totalBeatsElapsed = elapsedTime / secondsPerBeat
        let beatsPerMeasure = track.timeSignature.beatsPerMeasure
        
        // Use same discrete beat calculation as purple bar
        let discreteTotalBeats = Int(totalBeatsElapsed)
        let measureIndex = discreteTotalBeats / beatsPerMeasure
        let beatWithinMeasure = Double(discreteTotalBeats % beatsPerMeasure)
        
        // Convert to timePosition format for beat matching
        let currentTimePosition = Double(measureIndex) + (beatWithinMeasure / Double(beatsPerMeasure))
        let timeTolerance = 0.05
        
        // DEBUG: Log yellow highlight calculations
        Logger.debug("YELLOW HIGHLIGHT: elapsedTime=\(elapsedTime), discreteBeats=\(discreteTotalBeats), " +
                   "measure=\(measureIndex), beatInMeasure=\(beatWithinMeasure), timePos=\(currentTimePosition)")
        
        // Find the active beat using time-based position matching
        for beat in cachedDrumBeats where abs(beat.timePosition - currentTimePosition) < timeTolerance {
            activeBeatId = beat.id
            Logger.debug("YELLOW HIGHLIGHT MATCH: beatId=\(beat.id), beatTimePos=\(beat.timePosition), " +
                       "difference=\(abs(beat.timePosition - currentTimePosition))")
            return
        }
        activeBeatId = nil
        Logger.debug("YELLOW HIGHLIGHT: No matching beat found for timePosition \(currentTimePosition)")
    }
    
    func calculatePurpleBarPosition() -> (x: Double, y: Double)? {
        guard let track = track, isPlaying else {
            return nil
        }
        
        // CRITICAL FIX: Use metronome's precise beat timing for perfect audio-visual sync
        guard let beatProgress = metronome.getCurrentBeatProgress() else { return nil }
        
        let beatsPerMeasure = track.timeSignature.beatsPerMeasure
        
        // Snap to discrete quarter note beats for visual consistency
        let discreteTotalBeats = Int(beatProgress.totalBeats)
        let measureIndex = discreteTotalBeats / beatsPerMeasure
        let beatWithinMeasure = Double(discreteTotalBeats % beatsPerMeasure) // 0, 1, 2, 3
        
        let measurePos = measurePositionMap[measureIndex] ?? measurePositionMap[0]
        
        if let measurePos = measurePos {
            let indicatorX = GameplayLayout.preciseNoteXPosition(
                measurePosition: measurePos,
                beatPosition: beatWithinMeasure,
                timeSignature: track.timeSignature
            )
            
            let staffCenterY = GameplayLayout.StaffLinePosition.line3.absoluteY(for: measurePos.row)
            return (x: Double(indicatorX), y: Double(staffCenterY))
        } else {
            return nil
        }
    }
    
    // CRITICAL FIX: Unified visual update function using metronome timing
    func updateVisualElementsFromMetronome() {
        guard let track = track, isPlaying else { return }
        
        // Use metronome's precise timing reference for all calculations
        guard let metronomeTime = metronome.getCurrentPlaybackTime() else { return }
        let elapsedTime = pausedElapsedTime + metronomeTime
        
        let secondsPerBeat = 60.0 / track.bpm
        let totalBeatsElapsedFloat = elapsedTime / secondsPerBeat
        let discreteTotalBeats = Int(totalBeatsElapsedFloat)
        
        // Only update if discrete beat position has changed
        if discreteTotalBeats != lastDiscreteBeat {
            lastDiscreteBeat = discreteTotalBeats
            
            // Update all visual elements using metronome timing
            let beatsPerMeasure = track.timeSignature.beatsPerMeasure
            let measureIndex = discreteTotalBeats / beatsPerMeasure
            let beatWithinMeasure = discreteTotalBeats % beatsPerMeasure
            let beatPosition = Double(beatWithinMeasure) / Double(beatsPerMeasure)
            
            // Update core playback state
            currentMeasureIndex = measureIndex
            currentBeatPosition = beatPosition
            currentBeat = findClosestBeatIndex(measureIndex: measureIndex, beatPosition: beatPosition)
            totalBeatsElapsed = discreteTotalBeats
            playbackProgress = min(elapsedTime / cachedTrackDuration, 1.0)
            
            // Update visual indicators
            updatePurpleBarPosition()
            updateActiveBeat()
            
            // Check for playback completion
            if playbackProgress >= 1.0 {
                handlePlaybackCompletion(track: track)
            }
            
            Logger.debug("🎯 METRONOME VISUAL SYNC: discreteBeats=\(discreteTotalBeats), " +
                       "measure=\(measureIndex), beat=\(beatWithinMeasure), " +
                       "elapsed=\(String(format: "%.3f", elapsedTime))s, progress=\(String(format: "%.3f", playbackProgress))")
        }
    }
    
    func updatePurpleBarPosition() {
        let newPosition = calculatePurpleBarPosition()
        purpleBarPosition = newPosition
    }
    
    func computeDrumBeats() {
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
            let timePosition = MeasureUtils.timePosition(measureNumber: positionKey.measureNumber, 
                                                         measureOffset: positionKey.measureOffset)

            let drumTypes = notes.compactMap { note in
                DrumType.from(noteType: note.noteType)
            }

            // Use the interval from the first note in the group (they should all have the same interval at the same position)
            let interval = notes.first?.interval ?? .quarter
            return DrumBeat(id: Int(timePosition * 1000), 
                            drums: drumTypes, 
                            timePosition: timePosition, 
                            interval: interval)
        }
        .sorted { $0.timePosition < $1.timePosition }

        // Cache indices to avoid enumeration on every render
        cachedBeatIndices = Array(0..<cachedDrumBeats.count)
    }

    // Calculate track duration once and cache it
    func calculateTrackDuration() -> Double {
        guard let track = track else { return 0.0 }

        // Calculate duration per measure in seconds
        let secondsPerBeat = 60.0 / track.bpm
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
        let maxIndex = (cachedDrumBeats.map { 
            MeasureUtils.measureIndex(from: $0.timePosition) 
        }.max() ?? 0)
        let totalMeasures = max(1, maxIndex + 1)

        return Double(totalMeasures) * secondsPerMeasure
    }

    // Calculate BGM offset based on the first BGM note (lane 01) position
    func calculateBGMOffset() -> Double {
        guard let track = track else { return 0.0 }
        
        // Look for BGM notes in the original DTX data
        // Since BGM notes are filtered out of cachedNotes, we need to access them differently
        // For now, check if there are notes starting before measure 1
        let earliestNote = cachedNotes.min { $0.measureNumber < $1.measureNumber || 
            ($0.measureNumber == $1.measureNumber && $0.measureOffset < $1.measureOffset) }
        
        // If the earliest note is not in measure 1 at offset 0, calculate the BGM offset
        if let earliestNote = earliestNote, 
           earliestNote.measureNumber > 1 || earliestNote.measureOffset > 0.0 {
            
            // Calculate offset: BGM should start when music starts (first note position)
            let secondsPerBeat = 60.0 / track.bpm
            let secondsPerMeasure = secondsPerBeat * Double(track.timeSignature.beatsPerMeasure)
            
            // Convert note position to seconds offset
            let noteTimeSeconds = Double(earliestNote.measureNumber - 1) * secondsPerMeasure + 
                                (earliestNote.measureOffset * secondsPerMeasure)
            
            let message = "Calculated BGM offset: \(noteTimeSeconds)s from first note at " +
                        "measure \(earliestNote.measureNumber), offset \(earliestNote.measureOffset)"
            Logger.audioPlayback(message)
            return noteTimeSeconds
        }
        
        // No offset needed if music starts at measure 1, beat 1
        return 0.0
    }
}

// MARK: - Stable Staff Lines Background View
struct StaffLinesBackgroundView: View {
    let measurePositions: [GameplayLayout.MeasurePosition]
    private let rows: [Int]

    init(measurePositions: [GameplayLayout.MeasurePosition]) {
        self.measurePositions = measurePositions
        self.rows = Array(Set(measurePositions.map { $0.row })).sorted()
    }

    var body: some View {
        ZStack {
            ForEach(rows, id: \.self) { row in
                ZStack {
                    ForEach(0..<GameplayLayout.staffLineCount, id: \.self) { lineIndex in
                        Rectangle()
                            .frame(width: GameplayLayout.maxRowWidth, height: 1)
                            .foregroundColor(.gray.opacity(0.5))
                            .position(
                                x: GameplayLayout.maxRowWidth / 2,
                                y: GameplayLayout.StaffLinePosition(rawValue: lineIndex)?.absoluteY(for: row) ?? 0
                            )
                    }
                }
            }
        }
    }
}
