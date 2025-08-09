//
//  GameplayView.swift
//  Virgo
//
//  Created by Chan Wai Chan on 30/6/2025.
//

import SwiftUI
import AVFoundation

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
    @State var currentBeatPosition: Double = 0.0  // Current beat position within measure (0, 0.25, 0.5, 0.75)
    @State var currentMeasureIndex: Int = 0       // Which measure we're currently in
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
    @State var bgmPlayer: AVAudioPlayer?
    @State var bgmLoadingError: String?
    @State var metronome = MetronomeEngine()
    @State var staticStaffLinesView: AnyView?
    @State var inputManager = InputManager()
    @State var inputHandler = GameplayInputHandler()
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
    }

    // MARK: - Helper Methods
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
        let maxIndex = (cachedDrumBeats.map { 
            MeasureUtils.measureIndex(from: $0.timePosition) 
        }.max() ?? 0)
        let totalMeasures = max(1, maxIndex + 1)

        return Double(totalMeasures) * secondsPerMeasure
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