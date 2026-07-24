//
//  GameplayViewModel+Computations.swift
//  Virgo
//

import Foundation

extension GameplayViewModel {
    func makeRhythmRuntime(resolvedRhythm: ResolvedChartRhythm) -> GameplayRhythmRuntime {
        guard resolvedRhythm.availability == .valid,
              let timeline = resolvedRhythm.timeline,
              let track else {
            return GameplayRhythmRuntime(
                availability: resolvedRhythm.availability,
                timeline: nil,
                layoutSnapshot: nil,
                noteTargets: [],
                metronomeSchedule: nil,
                noteByEventID: [:],
                controlByEventID: [:],
                positionByNoteObjectID: [:],
                diagnostics: resolvedRhythm.runtimeDiagnostics
            )
        }

        let noteTargets: [RhythmNoteTarget] = resolvedRhythm.orderedEvents.compactMap { event -> RhythmNoteTarget? in
            guard let note = resolvedRhythm.noteByEventID[event.eventID],
                  let drumType = DrumType.from(noteType: note.noteType),
                  let targetSeconds = timeline.seconds(for: event.position, bpm: track.bpm, speed: 1) else {
                return nil
            }
            return RhythmNoteTarget(
                eventID: event.eventID,
                drumType: drumType,
                position: event.position,
                targetSecondsAtOneX: targetSeconds
            )
        }.sorted {
            if $0.targetSecondsAtOneX != $1.targetSecondsAtOneX {
                return $0.targetSecondsAtOneX < $1.targetSecondsAtOneX
            }
            return $0.eventID.rawValue < $1.eventID.rawValue
        }

        do {
            let layoutSnapshot = try makeRhythmLayoutSnapshot(
                resolvedRhythm: resolvedRhythm,
                timeline: timeline
            )
            let schedule = try RhythmMetronomeSchedule(timeline: timeline, bpm: track.bpm)
            return GameplayRhythmRuntime(
                availability: .valid,
                timeline: timeline,
                layoutSnapshot: layoutSnapshot,
                noteTargets: noteTargets,
                metronomeSchedule: schedule,
                noteByEventID: resolvedRhythm.noteByEventID,
                controlByEventID: resolvedRhythm.controlByEventID,
                positionByNoteObjectID: notePositionMap(for: resolvedRhythm),
                diagnostics: resolvedRhythm.runtimeDiagnostics
            )
        } catch let error as RhythmTimelineBuildError {
            return fatalRhythmRuntime(
                diagnostics: resolvedRhythm.runtimeDiagnostics,
                code: error.diagnosticCode
            )
        } catch {
            return fatalRhythmRuntime(
                diagnostics: resolvedRhythm.runtimeDiagnostics,
                code: .inconsistentPersistedTiming
            )
        }
    }

    private func notePositionMap(
        for resolvedRhythm: ResolvedChartRhythm
    ) -> [ObjectIdentifier: RhythmEventPosition] {
        var result: [ObjectIdentifier: RhythmEventPosition] = [:]
        for event in resolvedRhythm.orderedEvents {
            guard let note = resolvedRhythm.noteByEventID[event.eventID] else { continue }
            result[ObjectIdentifier(note)] = event.position
        }
        return result
    }

    private func makeRhythmLayoutSnapshot(
        resolvedRhythm: ResolvedChartRhythm,
        timeline: RhythmTimeline
    ) throws -> RhythmLayoutSnapshot {
        let analysisEvents = resolvedRhythm.orderedEvents.compactMap { event -> RhythmAnalysisEvent? in
            guard let note = resolvedRhythm.noteByEventID[event.eventID] else { return nil }
            let drumType = DrumType.from(noteType: note.noteType)
            return RhythmAnalysisEvent(
                eventID: event.eventID,
                origin: event.origin,
                position: event.position,
                voice: drumType.map(NotationVoice.voice(for:)) ?? .upper,
                storedInterval: note.interval,
                visualDurationCandidate: note.visualDurationCandidate
            )
        }
        let feel = resolvedRhythmFeel()
        let analysis = NotationRhythmAnalyzer().analyze(
            events: analysisEvents,
            measures: timeline.measures,
            ticksPerWholeNote: timeline.ticksPerWholeNote,
            feel: feel
        )
        let measures = rhythmMeasuresApplyingWarnings(timeline.measures, warnings: analysis.warnings)
        let notes = analysis.notes.compactMap { analyzed -> RhythmLayoutNote? in
            guard let note = resolvedRhythm.noteByEventID[analyzed.eventID] else { return nil }
            return RhythmLayoutNote(
                eventID: analyzed.eventID,
                sourceObjectID: ObjectIdentifier(note),
                sourceLaneID: note.sourceLaneID,
                sourceChipID: note.sourceNoteID,
                noteType: note.noteType,
                position: analyzed.position,
                durationTicks: analyzed.durationTicks,
                rhythm: analyzed.rhythm,
                tupletID: analyzed.tupletID
            )
        }
        let controls = resolvedRhythm.orderedEvents.compactMap { event -> RhythmLayoutControl? in
            guard let control = resolvedRhythm.controlByEventID[event.eventID] else { return nil }
            return RhythmLayoutControl(
                eventID: event.eventID,
                event: control,
                position: event.position
            )
        }
        let rests = analysis.rests.compactMap { rest -> RhythmLayoutRest? in
            guard let position = timeline.position(
                measureIndex: rest.measureIndex,
                localTick: rest.startTick
            ) else { return nil }
            return RhythmLayoutRest(
                position: position,
                durationTicks: rest.durationTicks,
                voice: rest.voice,
                rhythm: rest.rhythm,
                visibility: rest.visibility,
                tupletID: rest.tupletID
            )
        }
        let snapshot = try RhythmLayoutSnapshot(
            ticksPerWholeNote: timeline.ticksPerWholeNote,
            measures: measures,
            notes: notes,
            controls: controls,
            rests: rests,
            feel: feel,
            diagnostics: resolvedRhythm.runtimeDiagnostics
        )
        snapshot.logDiagnostics()
        return snapshot
    }

    private func resolvedRhythmFeel() -> RhythmicFeel {
        if case let .valid(metadata) = chart.rhythmMetadataState {
            return metadata.feel ?? .straight
        }
        return .straight
    }

    private func rhythmMeasuresApplyingWarnings(
        _ measures: [RhythmMeasure],
        warnings: [RhythmMeasureWarning]
    ) -> [RhythmMeasure] {
        let warningsByMeasure = Dictionary(uniqueKeysWithValues: warnings.map { ($0.measureIndex, $0.codes) })
        return measures.map { measure in
            guard let codes = warningsByMeasure[measure.measureIndex], !codes.isEmpty else { return measure }
            let existingCodes: Set<RhythmDiagnosticCode>
            if case let .unsupported(existing) = measure.engravingSupport {
                existingCodes = Set(existing)
            } else {
                existingCodes = []
            }
            return RhythmMeasure(
                measureIndex: measure.measureIndex,
                startTick: measure.startTick,
                durationTicks: measure.durationTicks,
                timeSignature: measure.timeSignature,
                beatGroups: measure.beatGroups,
                engravingSupport: .unsupported(Array(existingCodes.union(codes)).sorted { $0.rawValue < $1.rawValue })
            )
        }
    }

    private func fatalRhythmRuntime(
        diagnostics: [PersistedRhythmDiagnostic],
        code: RhythmDiagnosticCode
    ) -> GameplayRhythmRuntime {
        precondition(
            code.requiredSeverity == .timingFatal,
            "fatalRhythmRuntime requires a timingFatal code; received \(code.rawValue) (\(code.requiredSeverity))"
        )
        let diagnostic: PersistedRhythmDiagnostic
        do {
            diagnostic = try PersistedRhythmDiagnostic(code: code, severity: .timingFatal)
        } catch {
            preconditionFailure(
                "fatalRhythmRuntime: PersistedRhythmDiagnostic threw despite matching severity: \(error)"
            )
        }
        return GameplayRhythmRuntime(
            availability: .fatal,
            timeline: nil,
            layoutSnapshot: nil,
            noteTargets: [],
            metronomeSchedule: nil,
            noteByEventID: [:],
            controlByEventID: [:],
            positionByNoteObjectID: [:],
            diagnostics: diagnostics + [diagnostic]
        )
    }

    func configureInputTiming(speed: Double, elapsedOffset: Double = 0) {
        guard let configuration = inputTimingConfiguration(speed: speed) else { return }
        inputManager.configure(configuration, elapsedOffset: elapsedOffset)
    }

    func inputTimingConfiguration(speed: Double) -> InputTimingConfiguration? {
        if let timeline = cachedRhythmTimeline {
            return .timeline(
                targets: cachedRhythmNoteTargets,
                timeline: timeline,
                speed: speed
            )
        } else if let track {
            return .legacy(
                bpm: track.bpm * speed,
                timeSignature: track.timeSignature,
                notes: cachedNotes
            )
        }
        return nil
    }

    // MARK: - Unique ID Generation

    /// Generate a unique ID for a DrumBeat
    private func generateBeatId() -> UInt64 {
        defer { nextBeatId += 1 }
        return nextBeatId
    }

    // MARK: - Computation Methods

    func computeDrumBeats() {
        if cachedNotes.isEmpty {
            cachedDrumBeats = []
            nextBeatId = 0  // Reset counter for consistency
            return
        }

        if cachedRhythmRuntime.availability == .valid {
            computeTimelineDrumBeats()
            return
        }

        let groupedNotes = Dictionary(grouping: cachedNotes) { note in
            NotePositionKey(measureNumber: note.measureNumber, measureOffset: note.measureOffset).normalized()
        }

        cachedDrumBeats = groupedNotes.map { (positionKey, notes) in
            let beatID = generateBeatId()
            let timePosition = MeasureUtils.timePosition(
                measureNumber: positionKey.measureNumber,
                measureOffset: positionKey.measureOffset
            )
            let drumTypes = notes.compactMap { DrumType.from(noteType: $0.noteType) }
            let interval = notes.first?.interval ?? .quarter
            return DrumBeat(
                id: beatID,
                drums: drumTypes,
                timePosition: timePosition,
                interval: interval
            )
        }
        .sorted { $0.timePosition < $1.timePosition }

        cachedBeatIndices = Array(0..<cachedDrumBeats.count)
    }

    private func computeTimelineDrumBeats() {
        let groupedTargets = Dictionary(grouping: cachedRhythmNoteTargets, by: \.position)
        cachedDrumBeats = groupedTargets.compactMap { position, targets in
            guard let representative = targets.min(by: { $0.eventID.rawValue < $1.eventID.rawValue }),
                  let note = cachedNoteByRhythmEventID[representative.eventID] else {
                return nil
            }
            let drums = targets.sorted { $0.eventID.rawValue < $1.eventID.rawValue }.map(\.drumType)
            return DrumBeat(
                id: generateBeatId(),
                drums: drums,
                timePosition: MeasureUtils.timePosition(
                    measureNumber: note.measureNumber,
                    measureOffset: note.measureOffset
                ),
                interval: note.interval,
                rhythmEventID: representative.eventID,
                rhythmPosition: position
            )
        }.sorted {
            let leftTick = $0.rhythmPosition?.absoluteTick ?? Int.max
            let rightTick = $1.rhythmPosition?.absoluteTick ?? Int.max
            if leftTick != rightTick { return leftTick < rightTick }
            return ($0.rhythmEventID?.rawValue ?? Int.max) < ($1.rhythmEventID?.rawValue ?? Int.max)
        }
        cachedBeatIndices = Array(cachedDrumBeats.indices)
    }

    func computeCachedLayoutData() {
        guard let track = track else {
            cacheNotationLayout()
            return
        }

        let measuresCount: Int
        if let timeline = cachedRhythmTimeline {
            measuresCount = max(1, timeline.measures.count)
        } else {
            let secondsPerBeat = 60.0 / track.bpm
            let secondsPerMeasure = secondsPerBeat * Double(track.timeSignature.beatsPerMeasure)
            let trackDurationInSeconds = calculateTrackDurationInSeconds(secondsPerMeasure: secondsPerMeasure)
            measuresCount = max(1, Int(ceil(trackDurationInSeconds / secondsPerMeasure)))
        }
        cachedLayoutMeasureCount = measuresCount

        cachedMeasurePositions = GameplayLayout.calculateMeasurePositions(
            totalMeasures: measuresCount,
            timeSignature: track.timeSignature
        )

        measurePositionMap = [:]
        for position in cachedMeasurePositions {
            measurePositionMap[position.measureIndex] = position
        }

        staticStaffLinesView = AnyView(StaffLinesBackgroundView(measurePositions: cachedMeasurePositions))

        if measurePositionMap[0] == nil {
            Logger.warning("Measure 0 missing from measurePositionMap! Creating fallback measure 0.")
            let measure0 = GameplayLayout.MeasurePosition(
                row: 0,
                xOffset: GameplayLayout.leftMargin,
                measureIndex: 0
            )
            measurePositionMap[0] = measure0
        }

        cacheNotationLayout()
        cacheBeatPositions()
    }

    /// Reports the sheet music view's currently available row width. If this changes
    /// the notation layout is rebuilt so measures repack at the new width. Values at
    /// or below the legacy `maxRowWidth` (900) are treated as the floor so behavior
    /// on narrow windows matches the historical layout.
    func updateRowWidth(_ width: CGFloat) {
        guard width.isFinite, width > 0 else { return }
        let resolved = max(GameplayLayout.maxRowWidth, width)
        guard abs(resolved - cachedLayoutRowWidth) > 0.5 else {
            // Width returned to the cached value — cancel any pending stale
            // timer so a previously-scheduled wider/narrower update doesn't
            // fire after the window is already back at the current width.
            rowWidthTimer?.invalidate()
            rowWidthTimer = nil
            return
        }
        scheduleRowWidthUpdate(resolved)
    }

    /// Trailing-edge debounce for row-width changes. During macOS live resize the
    /// width changes every frame; rebuilding the full notation layout each time is
    /// expensive. This mirrors the speed-change debounce pattern: coalesce rapid
    /// width changes and rebuild layout once the user stops resizing.
    private func scheduleRowWidthUpdate(_ width: CGFloat) {
        rowWidthTimer?.invalidate()

        if !isGameplayPrepared {
            cachedLayoutRowWidth = width
            return
        }

        // Apply immediately in tests for deterministic behavior
        if TestEnvironment.isRunningTests {
            cachedLayoutRowWidth = width
            cacheNotationLayout()
            cacheBeatPositions()
            return
        }

        rowWidthTimer = Timer.scheduledTimer(
            withTimeInterval: rowWidthDebounceInterval,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.cachedLayoutRowWidth = width
                self.cacheNotationLayout()
                self.cacheBeatPositions()
            }
        }
    }

    func cacheNotationLayout() {
        guard let track = track else {
            cachedNotationLayout = .empty
            cachedNotationNoteHeadPositions = [:]
            cachedMeasureRowMap = [:]
            cachedNotationMeasuresByIndex = [:]
            notationStaffLinesView = nil
            return
        }

        // Use default positions in tests to avoid reading developer's local
        // UserDefaults overrides, which would make layout non-deterministic
        // across contributor machines.  Position overrides are independently
        // tested in DrumNotationSettingsManager unit tests.
        let notePositionOverrides: [DrumType: GameplayLayout.NotePosition]
        if TestEnvironment.isRunningTests {
            notePositionOverrides = Dictionary(
                uniqueKeysWithValues: DrumType.allCases.map { ($0, $0.notePosition) }
            )
        } else {
            notePositionOverrides = DrumNotationSettingsManager.loadPositions()
        }

        let resolvedRowWidth = max(GameplayLayout.maxRowWidth, cachedLayoutRowWidth)
        let style = NotationLayoutStyle.gameplayDefault.with(rowWidth: resolvedRowWidth)
        let input: NotationLayoutInput
        if let snapshot = cachedRhythmRuntime.layoutSnapshot {
            input = NotationLayoutInput(
                timing: .timeline(snapshot),
                minimumMeasureCount: cachedLayoutMeasureCount,
                style: style,
                notePositionOverrides: notePositionOverrides
            )
        } else {
            input = NotationLayoutInput(
                notes: cachedNotes,
                controlEvents: cachedControlEvents,
                timeSignature: track.timeSignature,
                minimumMeasureCount: cachedLayoutMeasureCount,
                style: style,
                notePositionOverrides: notePositionOverrides
            )
        }
        cachedNotationLayout = NotationLayoutEngine().layout(input: input)
        if cachedNotationLayout.hasRenderableContent {
            cachedMeasureRowMap = Dictionary(
                uniqueKeysWithValues: cachedNotationLayout.measures.map { ($0.measureIndex, $0.row) }
            )
            cachedNotationMeasuresByIndex = Dictionary(
                uniqueKeysWithValues: cachedNotationLayout.measures.map { ($0.measureIndex, $0) }
            )
            cacheNotationMeasurePositionMap()
        } else {
            cachedMeasureRowMap = [:]
            cachedNotationMeasuresByIndex = [:]
        }

        cacheNotationStaffLinesView()
        logDroppedNotesIfAny()

        cachedNotationNoteHeadPositions = Dictionary(
            uniqueKeysWithValues: cachedNotationLayout.noteHeadPositionsByID.map { noteHeadID, position in
                (noteHeadID, (x: Double(position.x), y: Double(position.y)))
            }
        )
    }

    /// Builds (or clears) the cached staff-lines background view. Only populated
    /// when the layout produced renderable notation, since a malformed empty layout has nothing to
    /// underlay. Extracted from `cacheNotationLayout()` to keep it under the
    /// function-body-length limit.
    private func cacheNotationStaffLinesView() {
        guard cachedNotationLayout.hasRenderableContent else {
            notationStaffLinesView = nil
            return
        }
        let notationMeasurePositions = cachedNotationLayout.measures.map { measure in
            GameplayLayout.MeasurePosition(
                row: measure.row,
                xOffset: measure.xOffset,
                measureIndex: measure.measureIndex
            )
        }
        let contentWidth = cachedNotationLayout.contentWidth
        notationStaffLinesView = AnyView(
            StaffLinesBackgroundView(measurePositions: notationMeasurePositions, width: contentWidth)
        )
    }

    /// Rebuilds `measurePositionMap` from the current notation layout's measures.
    /// Extracted from `cacheNotationLayout()` to keep it under the function-body-length limit.
    private func cacheNotationMeasurePositionMap() {
        measurePositionMap = Dictionary(
            uniqueKeysWithValues: cachedNotationLayout.measures.map { measure in
                (
                    measure.measureIndex,
                    GameplayLayout.MeasurePosition(
                        row: measure.row,
                        xOffset: measure.xOffset,
                        measureIndex: measure.measureIndex
                    )
                )
            }
        )
    }

    /// Logs a diagnostic when the notation layout engine drops notes (i.e. the
    /// rendered note-head count is lower than the cached note count). Extracted
    /// from `cacheNotationLayout()` to keep it under the function-body-length limit.
    private func logDroppedNotesIfAny() {
        guard cachedNotes.count != cachedNotationLayout.noteHeads.count, !cachedNotes.isEmpty else { return }
        let renderedSourceIDs = Set(cachedNotationLayout.noteHeads.map(\.sourceObjectID))
        let droppedNotes = cachedNotes.filter { !renderedSourceIDs.contains(ObjectIdentifier($0)) }
        let droppedReasons = droppedNotes.prefix(5).map { note in
            let drumType = DrumType.from(noteType: note.noteType)
            let measureIdx = MeasureUtils.measureIndex(from: MeasureUtils.timePosition(
                measureNumber: note.measureNumber, measureOffset: note.measureOffset
            ))
            return "noteType=\(note.noteType)(\(drumType?.description ?? "unknown")), " +
                    "measure=\(note.measureNumber)(idx=\(measureIdx))"
        }
        Logger.warning(
            "Layout engine dropped \(droppedNotes.count) note(s): \(droppedReasons.joined(separator: "; "))"
                + (droppedNotes.count > 5 ? " … and \(droppedNotes.count - 5) more" : "")
        )
    }

    func cacheBeatPositions() {
        guard let track = track else { return }

        cachedBeatPositions = [:]

        if cachedNotationLayout.hasPlayableContent {
            cacheNotationBeatPositions(track: track)
        } else if !cachedNotationLayout.hasRenderableContent {
            cacheLegacyBeatPositions(track: track)
        }

        Logger.debug("Cached \(cachedBeatPositions.count) beat positions for performance optimization")
    }

    private func cacheNotationBeatPositions(track: DrumTrack) {
        if cachedRhythmRuntime.availability == .valid {
            cacheTimelineNotationBeatPositions()
            return
        }
        for beat in cachedDrumBeats {
            let measureIndex = MeasureUtils.measureIndex(from: beat.timePosition)
            guard let measure = cachedNotationMeasuresByIndex[measureIndex] else { continue }
            let beatOffsetInMeasure = beat.timePosition - Double(measureIndex)
            let beatWithinMeasure = beatOffsetInMeasure * Double(track.timeSignature.beatsPerMeasure)
            let tick = cachedNotationLayout.tabGrid.tickIndex(
                forBeatWithinMeasure: beatWithinMeasure,
                beatsPerMeasure: track.timeSignature.beatsPerMeasure
            )
            let beatX = cachedNotationLayout.tabGrid.xPosition(in: measure, tickIndex: tick)
            let staffCenterY = GameplayLayout.StaffLinePosition.line3.absoluteY(for: measure.row)
            cachedBeatPositions[beat.id] = (x: Double(beatX), y: Double(staffCenterY))
        }
    }

    private func cacheTimelineNotationBeatPositions() {
        for beat in cachedDrumBeats {
            guard let position = beat.rhythmPosition,
                  let measure = cachedNotationMeasuresByIndex[position.measureIndex] else {
                continue
            }
            let beatX = cachedNotationLayout.tabGrid.xPosition(in: measure, localTick: position.localTick)
            let staffCenterY = GameplayLayout.StaffLinePosition.line3.absoluteY(for: measure.row)
            cachedBeatPositions[beat.id] = (x: Double(beatX), y: Double(staffCenterY))
        }
    }

    private func cacheLegacyBeatPositions(track: DrumTrack) {
        for beat in cachedDrumBeats {
            let measureIndex = MeasureUtils.measureIndex(from: beat.timePosition)

            if let measurePos = measurePositionMap[measureIndex] {
                let beatOffsetInMeasure = beat.timePosition - Double(measureIndex)
                let beatPosition = beatOffsetInMeasure * Double(track.timeSignature.beatsPerMeasure)
                let beatX = GameplayLayout.preciseNoteXPosition(
                    measurePosition: measurePos,
                    beatPosition: beatPosition,
                    timeSignature: track.timeSignature
                )
                let staffCenterY = GameplayLayout.StaffLinePosition.line3.absoluteY(for: measurePos.row)
                cachedBeatPositions[beat.id] = (x: Double(beatX), y: Double(staffCenterY))
            }
        }
    }

    private func calculateTrackDurationInSeconds(secondsPerMeasure: Double) -> Double {
        if let timeline = cachedRhythmTimeline,
           let track,
           let endSeconds = timeline.endSeconds(bpm: track.bpm, speed: 1) {
            return endSeconds
        }
        if let song = cachedSong, !song.duration.isEmpty && song.duration != "0:00" {
            let components = song.duration.split(separator: ":")
            if components.count == 2,
               let minutes = Double(components[0]),
               let seconds = Double(components[1]) {
                return minutes * 60 + seconds
            }
        }

        let maxIndex = (cachedDrumBeats.map {
            MeasureUtils.measureIndex(from: $0.timePosition)
        }.max() ?? 0)
        let noteMeasures = max(1, maxIndex + 1)
        return Double(noteMeasures) * secondsPerMeasure
    }

    func calculateTrackDuration() -> Double {
        guard let track = track else {
            Logger.error("calculateTrackDuration() called with nil track - returning 0.0")
            return 0.0
        }

        let secondsPerBeat = 60.0 / track.bpm
        let secondsPerMeasure = secondsPerBeat * Double(track.timeSignature.beatsPerMeasure)
        let baseDuration = calculateTrackDurationInSeconds(secondsPerMeasure: secondsPerMeasure)
        let speedMultiplier = practiceSettings.speedMultiplier
        guard speedMultiplier > 0 else {
            Logger.error("calculateTrackDuration called with zero speedMultiplier - returning base duration")
            return baseDuration
        }
        return baseDuration / speedMultiplier
    }

    func calculateBGMOffset() -> Double {
        guard let track = track else { return 0.0 }
        let speedMultiplier = practiceSettings.speedMultiplier
        if let timeline = cachedRhythmTimeline {
            let oneXOffset: Double
            if let anchor = timeline.bgmStartPosition,
               let seconds = timeline.seconds(for: anchor, bpm: track.bpm, speed: 1) {
                oneXOffset = seconds
            } else {
                oneXOffset = cachedRhythmNoteTargets.map(\.targetSecondsAtOneX).min() ?? 0
            }
            guard speedMultiplier > 0 else {
                Logger.error("calculateBGMOffset called with zero speedMultiplier - returning one-X timeline anchor")
                return oneXOffset
            }
            return oneXOffset / speedMultiplier
        }
        // `nil` means no authoritative BGM offset was parsed (fall back to the
        // first-note heuristic below). A non-nil value — including 0.0, which
        // means the chart explicitly starts BGM at time zero — is authoritative
        // and must be honored rather than replaced by the heuristic.
        if let bgmStartOffsetSeconds = cachedSong?.bgmStartOffsetSeconds {
            guard speedMultiplier > 0 else {
                Logger.error("calculateBGMOffset called with zero speedMultiplier - returning unscaled DTX BGM offset")
                return bgmStartOffsetSeconds
            }
            return bgmStartOffsetSeconds / speedMultiplier
        }

        let earliestNote = cachedNotes.min {
            $0.measureNumber < $1.measureNumber ||
            ($0.measureNumber == $1.measureNumber && $0.measureOffset < $1.measureOffset)
        }

        if let earliestNote = earliestNote,
           earliestNote.measureNumber > 1 || earliestNote.measureOffset > 0.0 {
            let secondsPerBeat = 60.0 / track.bpm
            let secondsPerMeasure = secondsPerBeat * Double(track.timeSignature.beatsPerMeasure)
            let noteTimeSeconds = Double(earliestNote.measureNumber - 1) * secondsPerMeasure +
                (earliestNote.measureOffset * secondsPerMeasure)
            guard speedMultiplier > 0 else {
                Logger.error("calculateBGMOffset called with zero speedMultiplier - returning unscaled offset")
                return noteTimeSeconds
            }
            return noteTimeSeconds / speedMultiplier
        }

        return 0.0
    }

    // MARK: - Scoring Methods

    /// Process a note match result from InputManager. Called by GameplayInputHandler closure.
    func recordHit(result: NoteMatchResult) {
        guard isPlaying else { return }

        // Flush any notes that were missed before this hit so combo state is correct
        // when processHit runs (handles 8th/16th notes within the same beat).
        if let hitSongSeconds = result.hitSongSeconds {
            scanForMissedNotes(upToSeconds: hitSongSeconds)
        } else if let measureNumber = result.measureNumber,
           let measureOffset = result.measureOffset {
            let hitTimePos = MeasureUtils.timePosition(
                measureNumber: measureNumber,
                measureOffset: measureOffset
            )
            scanForMissedNotes(upToTimePosition: hitTimePos)
        }

        // Prevent duplicate scoring: if this note was already scored (e.g. double-tap
        // within InputManager's search window), discard the repeated result entirely.
        if let eventID = result.matchedEventID {
            guard scoredRhythmEventIDs.insert(eventID).inserted else { return }
        } else if let note = result.matchedNote {
            let noteID = ObjectIdentifier(note)
            guard scoredNoteIDs.insert(noteID).inserted else { return }
        }

        let prevCombo = scoreEngine.combo
        scoreEngine.processHit(accuracy: result.timingAccuracy, timingError: result.timingError)

        if result.timingAccuracy == .miss {
            if prevCombo > 0 { triggerComboBreakFeedback() }
        } else {
            triggerHitHaptic()
            if ScoreEngine.milestone(crossedFrom: prevCombo, to: scoreEngine.combo) != nil {
                triggerMilestoneAnimation()
            }
        }

        Logger.userAction("Score: \(scoreEngine.score) | Combo: \(scoreEngine.combo)x")
    }

    /// Scan cachedNotes for notes that scrolled past without any hit attempt.
    func scanForMissedNotes(upToTimePosition playheadPosition: Double) {
        guard isPlaying || playheadPosition.isInfinite else { return }

        // Offset the miss boundary by the good-tier late tolerance so that late hits
        // arriving within ±100 ms can still score before we auto-mark them missed.
        let bpm = effectiveBPM()
        let beatsPerMeasure = Double(track?.timeSignature.beatsPerMeasure ?? 4)
        let secondsPerMeasure = beatsPerMeasure * 60.0 / bpm
        let lateWindowInMeasures = TimingAccuracy.good.toleranceMs / 1000.0 / secondsPerMeasure
        let scanBoundary = playheadPosition - lateWindowInMeasures

        // Bail out when not enough time has elapsed to guarantee any note is past the window.
        guard scanBoundary > lastScannedTimePosition else { return }

        // Capture combo before the loop so we can fire break feedback exactly once
        // if any auto-missed note drops the combo from non-zero to zero.
        let prevCombo = scoreEngine.combo

        // Walk forward from the cursor; notes are sorted ascending by time position,
        // so we stop as soon as we reach a note at or beyond the scan boundary.
        // This is O(new notes this tick) rather than O(totalNotes).
        while legacyMissedNoteScanCursor < sortedNotesByTimePosition.count {
            let note = sortedNotesByTimePosition[legacyMissedNoteScanCursor]
            let noteTimePos = MeasureUtils.timePosition(
                measureNumber: note.measureNumber,
                measureOffset: note.measureOffset
            )
            // All remaining notes are at or after the miss boundary — done for this tick.
            if noteTimePos >= scanBoundary { break }
            // Mark as miss only if no explicit hit was recorded for this note.
            let noteID = ObjectIdentifier(note)
            if !scoredNoteIDs.contains(noteID) {
                scoredNoteIDs.insert(noteID)
                scoreEngine.processMissedNote()
            }
            legacyMissedNoteScanCursor += 1
        }
        lastScannedTimePosition = scanBoundary

        // Fire combo-break feedback if any auto-miss above broke the combo.
        // Mirrors the same guard in recordHit; triggerComboBreakFeedback also
        // double-checks combo == 0 internally, so no duplication risk.
        if prevCombo > 0 && scoreEngine.combo == 0 {
            triggerComboBreakFeedback()
        }
    }

    /// Scan immutable timeline targets by effective target seconds.
    func scanForMissedNotes(upToSeconds playheadSeconds: Double) {
        guard isPlaying || playheadSeconds.isInfinite else { return }
        guard cachedRhythmTimeline != nil else { return }

        let lateWindowSeconds = TimingAccuracy.good.toleranceMs / 1_000
        let scanBoundary = playheadSeconds - lateWindowSeconds
        guard scanBoundary > lastScannedRhythmTargetSeconds else { return }
        let speed = practiceSettings.speedMultiplier
        guard speed.isFinite, speed > 0 else { return }
        let previousCombo = scoreEngine.combo

        while rhythmMissedNoteScanCursor < cachedRhythmNoteTargets.count {
            let target = cachedRhythmNoteTargets[rhythmMissedNoteScanCursor]
            let targetSeconds = target.targetSecondsAtOneX / speed
            if targetSeconds > scanBoundary + 1e-12 { break }
            if scoredRhythmEventIDs.insert(target.eventID).inserted {
                scoreEngine.processMissedNote()
            }
            rhythmMissedNoteScanCursor += 1
        }
        lastScannedRhythmTargetSeconds = scanBoundary

        if previousCombo > 0 && scoreEngine.combo == 0 {
            triggerComboBreakFeedback()
        }
    }

    func scanForAllMissedNotes() {
        if cachedRhythmTimeline != nil {
            scanForMissedNotes(upToSeconds: .infinity)
        } else {
            scanForMissedNotes(upToTimePosition: .infinity)
        }
    }

    /// Resets all scoring state. Called by resetPlaybackState() on restart and completion.
    func resetScoring() {
        scoreEngine.reset()
        sessionScoreSnapshot = .empty
        sessionRecordResult = .recorded
        isShowingSessionResults = false
        showMilestoneAnimation = false
        showComboBreakFeedback = false
        scoredNoteIDs = []
        scoredRhythmEventIDs = []
        legacyMissedNoteScanCursor = 0
        rhythmMissedNoteScanCursor = 0
        lastScannedTimePosition = 0.0
        lastScannedRhythmTargetSeconds = -.infinity
        // Cancel any in-flight feedback reset tasks so they cannot clear flags on
        // the fresh session that is about to start.
        milestoneAnimationTask?.cancel()
        milestoneAnimationTask = nil
        comboBreakFeedbackTask?.cancel()
        comboBreakFeedbackTask = nil
        // Cancel scheduled completion and reset flag for next session
        completionTask?.cancel()
        completionTask = nil
        completionScheduled = false
    }

    /// Wire GameplayInputHandler closures to ViewModel scoring methods.
    func wireInputHandler() {
        inputHandler.onNoteResult = { [weak self] result in
            self?.recordHit(result: result)
        }
        inputHandler.onSelectedSourceDisconnect = { [weak self] in
            self?.handleSelectedMIDISourceDisconnect()
        }
    }

    private func triggerMilestoneAnimation() {
        milestoneAnimationTask?.cancel()
        showMilestoneAnimation = true
        milestoneAnimationTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            self?.showMilestoneAnimation = false
        }
    }

    private func triggerComboBreakFeedback() {
        guard scoreEngine.combo == 0 else { return }
        comboBreakFeedbackTask?.cancel()
        showComboBreakFeedback = true
        triggerComboBreakHaptic()
        comboBreakFeedbackTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            self?.showComboBreakFeedback = false
        }
    }

    private func triggerHitHaptic() {
        #if os(iOS)
        hitHapticGenerator.impactOccurred(intensity: 0.6)
        #endif
    }

    private func triggerComboBreakHaptic() {
        #if os(iOS)
        comboBreakHapticGenerator.notificationOccurred(.warning)
        #endif
    }
}
