//
//  GameplayViewModel+Computations.swift
//  Virgo
//

import Foundation

extension GameplayViewModel {
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

    func computeCachedLayoutData() {
        guard let track = track else {
            cacheNotationLayout()
            return
        }

        let secondsPerBeat = 60.0 / track.bpm
        let secondsPerMeasure = secondsPerBeat * Double(track.timeSignature.beatsPerMeasure)

        let trackDurationInSeconds = calculateTrackDurationInSeconds(secondsPerMeasure: secondsPerMeasure)
        let totalMeasuresForDuration = Int(ceil(trackDurationInSeconds / secondsPerMeasure))
        let measuresCount = max(1, totalMeasuresForDuration)
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
            }
        }
    }

    func cacheNotationLayout() {
        guard let track = track else {
            cachedNotationLayout = .empty
            cachedNotationNoteHeadPositions = [:]
            cachedMeasureRowMap = [:]
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
        let input = NotationLayoutInput(
            notes: cachedNotes,
            timeSignature: track.timeSignature,
            minimumMeasureCount: cachedLayoutMeasureCount,
            style: style,
            notePositionOverrides: notePositionOverrides
        )
        cachedNotationLayout = NotationLayoutEngine().layout(input: input)
        cachedMeasureRowMap = Dictionary(
            uniqueKeysWithValues: cachedNotationLayout.measures.map { ($0.measureIndex, $0.row) }
        )

        if !cachedNotationLayout.noteHeads.isEmpty {
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
        } else {
            notationStaffLinesView = nil
        }

        if cachedNotes.count != cachedNotationLayout.noteHeads.count, !cachedNotes.isEmpty {
            let renderedSourceIDs = Set(cachedNotationLayout.noteHeads.map { $0.sourceNoteID })
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

        cachedNotationNoteHeadPositions = Dictionary(
            uniqueKeysWithValues: cachedNotationLayout.noteHeadPositionsByID.map { noteHeadID, position in
                (noteHeadID, (x: Double(position.x), y: Double(position.y)))
            }
        )
    }

    func cacheBeatPositions() {
        guard let track = track else { return }

        cachedBeatPositions = [:]

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

        Logger.debug("Cached \(cachedBeatPositions.count) beat positions for performance optimization")
    }

    private func calculateTrackDurationInSeconds(secondsPerMeasure: Double) -> Double {
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
        if let bgmStartOffsetSeconds = cachedSong?.bgmStartOffsetSeconds, bgmStartOffsetSeconds > 0 {
            let speedMultiplier = practiceSettings.speedMultiplier
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
            let speedMultiplier = practiceSettings.speedMultiplier
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
        let hitTimePos = MeasureUtils.timePosition(
            measureNumber: result.measureNumber,
            measureOffset: result.measureOffset
        )
        scanForMissedNotes(upToTimePosition: hitTimePos)

        // Prevent duplicate scoring: if this note was already scored (e.g. double-tap
        // within InputManager's search window), discard the repeated result entirely.
        if let note = result.matchedNote {
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
        while missedNoteScanCursor < sortedNotesByTimePosition.count {
            let note = sortedNotesByTimePosition[missedNoteScanCursor]
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
            missedNoteScanCursor += 1
        }
        lastScannedTimePosition = scanBoundary

        // Fire combo-break feedback if any auto-miss above broke the combo.
        // Mirrors the same guard in recordHit; triggerComboBreakFeedback also
        // double-checks combo == 0 internally, so no duplication risk.
        if prevCombo > 0 && scoreEngine.combo == 0 {
            triggerComboBreakFeedback()
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
        missedNoteScanCursor = 0
        lastScannedTimePosition = 0.0
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
