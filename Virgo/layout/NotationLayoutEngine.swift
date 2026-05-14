import CoreGraphics
import Foundation

/// Core layout engine - handles measure construction and note head placement.
// swiftlint:disable:next type_body_length
struct NotationLayoutEngine {
    private static let columnResolution = 960.0
    private static let topStaffStep = -8
    private static let bottomStaffStep = 0

    private struct VoiceCollisionColumn: Hashable {
        let measureIndex: Int
        let quantizedColumn: Int
    }
    private struct NoteHeadDraft {
        let noteHead: RenderedNoteHead
        let collisionColumn: VoiceCollisionColumn
    }

    struct BeamGroupKey: Hashable {
        let measureIndex: Int
        let row: Int
        let voice: NotationVoice
        let stemDirection: StemDirection
    }

    func layout(input: NotationLayoutInput) -> NotationLayout {
        let sortedNotes = input.notes.sorted {
            MeasureUtils.timePosition(measureNumber: $0.measureNumber, measureOffset: $0.measureOffset)
            < MeasureUtils.timePosition(measureNumber: $1.measureNumber, measureOffset: $1.measureOffset)
        }
        let maxNormalizedMeasureIndex = sortedNotes.map { note in
            MeasureUtils.measureIndex(from: MeasureUtils.timePosition(
                measureNumber: note.measureNumber, measureOffset: note.measureOffset
            ))
        }.max() ?? 0
        let totalMeasures = max(input.minimumMeasureCount, maxNormalizedMeasureIndex + 1, 1)
        let measures = buildMeasures(totalMeasures: totalMeasures, notes: sortedNotes, input: input)
        let noteHeads = buildNoteHeads(notes: sortedNotes, measures: measures, input: input)
        let beams = buildBeams(noteHeads: noteHeads, style: input.style)
        let stems = buildStems(noteHeads: noteHeads, beams: beams, style: input.style)
        let flags = buildFlags(noteHeads: noteHeads, beams: beams, style: input.style)
        let ledgerLines = buildLedgerLines(noteHeads: noteHeads, style: input.style)
        let measureBars = buildMeasureBars(measures: measures)
        let noteHeadPositionsByID = Dictionary(uniqueKeysWithValues: noteHeads.map { ($0.id, $0.position) })
        let noteHeadIDsByTimePosition = Dictionary(
            grouping: noteHeads,
            by: { NotationLayout.timePositionKey($0.timePosition) }
        ).mapValues { Set($0.map(\.id)) }
        let totalHeight = GameplayLayout.totalHeight(
            for: measures.map {
                GameplayLayout.MeasurePosition(row: $0.row, xOffset: $0.xOffset, measureIndex: $0.measureIndex)
            }
        )

        return NotationLayout(
            measures: measures,
            noteHeads: noteHeads,
            stems: stems,
            beams: beams,
            flags: flags,
            ledgerLines: ledgerLines,
            measureBars: measureBars,
            noteHeadPositionsByID: noteHeadPositionsByID,
            noteHeadIDsByTimePosition: noteHeadIDsByTimePosition,
            totalHeight: totalHeight
        )
    }

    // MARK: - Measure Building

    private func buildMeasures(
        totalMeasures: Int,
        notes: [Note],
        input: NotationLayoutInput
    ) -> [RenderedMeasure] {
        var result: [RenderedMeasure] = []
        var currentRow = 0
        var currentX = GameplayLayout.leftMargin
        for measureIndex in 0..<totalMeasures {
            let width = measureWidth(measureIndex: measureIndex, notes: notes, input: input)
            if currentX + width > input.style.rowWidth, measureIndex > 0 {
                currentRow += 1
                currentX = GameplayLayout.leftMargin
            }
            result.append(
                RenderedMeasure(
                    id: measureIndex, measureIndex: measureIndex,
                    row: currentRow, xOffset: currentX, width: width
                )
            )
            currentX += width + GameplayLayout.measureSpacing
        }

        return result
    }

    func measureWidth(
        measureIndex: Int,
        notes: [Note],
        input: NotationLayoutInput
    ) -> CGFloat {
        let offsets = columnOffsets(forMeasureIndex: measureIndex, notes: notes)
        let legacyWidth = GameplayLayout.measureWidth(for: input.timeSignature)

        guard offsets.count > 1 else {
            return legacyWidth
        }

        let smallestGap = zip(offsets.dropFirst(), offsets)
            .map { pair in pair.0 - pair.1 }
            .min() ?? 0.25
        let requiredColumnGap = minimumColumnGap(
            measureIndex: measureIndex,
            notes: notes,
            style: input.style
        )
        let minimumBeatGap = requiredColumnGap / CGFloat(
            max(smallestGap * Double(input.timeSignature.beatsPerMeasure), 0.001)
        )
        let beatGap = max(
            input.style.minimumQuarterBeatGap,
            minimumBeatGap
        )
        let adaptiveWidth = GameplayLayout.barLineWidth
            + GameplayLayout.uniformSpacing
            + CGFloat(input.timeSignature.beatsPerMeasure) * beatGap

        return max(legacyWidth, adaptiveWidth)
    }

    private func minimumColumnGap(
        measureIndex: Int,
        notes: [Note],
        style: NotationLayoutStyle
    ) -> CGFloat {
        guard containsCrossVoiceCollision(measureIndex: measureIndex, notes: notes) else {
            return style.minimumNoteColumnGap
        }

        return style.minimumNoteColumnGap + 2 * style.voiceCollisionOffset
    }

    func containsCrossVoiceCollision(measureIndex: Int, notes: [Note]) -> Bool {
        Dictionary(
            grouping: notes.filter { normalizedMeasureIndex(for: $0) == measureIndex },
            by: { quantizedColumn(for: normalizedOffset(for: $0)) }
        )
        .values
        .contains { columnNotes in
            let voices = Set(columnNotes.compactMap { note -> NotationVoice? in
                guard let drumType = DrumType.from(noteType: note.noteType) else {
                    return nil
                }
                return NotationVoice.voice(for: drumType)
            })

            return voices.count > 1
        }
    }

    // MARK: - Note Head Building

    private func buildNoteHeads(
        notes: [Note],
        measures: [RenderedMeasure],
        input: NotationLayoutInput
    ) -> [RenderedNoteHead] {
        var nextID: UInt64 = 0
        let measuresByIndex = Dictionary(uniqueKeysWithValues: measures.map { ($0.measureIndex, $0) })
        var drafts: [NoteHeadDraft] = []

        for note in notes {
            guard let drumType = DrumType.from(noteType: note.noteType) else { continue }
            let timePos = MeasureUtils.timePosition(
                measureNumber: note.measureNumber,
                measureOffset: note.measureOffset
            )
            let normalizedMeasureIndex = MeasureUtils.measureIndex(from: timePos)
            let normalizedOffset = timePos - Double(normalizedMeasureIndex)
            guard let measure = measuresByIndex[normalizedMeasureIndex] else { continue }
            let beatGap = beatGap(for: measure, input: input)
            let beatPosition = quantizedOffset(for: normalizedOffset) * Double(input.timeSignature.beatsPerMeasure)
            let x = measure.xOffset + GameplayLayout.barLineWidth + GameplayLayout.uniformSpacing
                + CGFloat(beatPosition) * beatGap
            let resolvedPosition = notePosition(for: drumType, overrides: input.notePositionOverrides)
            let y = GameplayLayout.StaffLinePosition.line1.absoluteY(for: measure.row)
                + resolvedPosition.yOffset
            let voice = NotationVoice.voice(for: drumType)
            let direction = stemDirection(for: resolvedPosition, voice: voice)
            nextID += 1
            drafts.append(
                NoteHeadDraft(
                    noteHead: RenderedNoteHead(
                        id: nextID - 1,
                        sourceNoteID: ObjectIdentifier(note),
                        drumType: drumType,
                        voice: voice,
                        timePosition: timePos,
                        measureIndex: normalizedMeasureIndex,
                        row: measure.row,
                        position: CGPoint(x: x, y: y),
                        staffStep: staffStep(for: resolvedPosition),
                        stemDirection: direction,
                        interval: note.interval
                    ),
                    collisionColumn: VoiceCollisionColumn(
                        measureIndex: normalizedMeasureIndex,
                        quantizedColumn: quantizedColumn(for: normalizedOffset)
                    )
                )
            )
        }

        return applyVoiceCollisionOffsets(to: drafts, style: input.style)
    }

    private func applyVoiceCollisionOffsets(
        to drafts: [NoteHeadDraft],
        style: NotationLayoutStyle
    ) -> [RenderedNoteHead] {
        let collisionColumns = Set(
            Dictionary(grouping: drafts, by: \.collisionColumn).compactMap { column, drafts in
                Set(drafts.map(\.noteHead.voice)).count > 1 ? column : nil
            }
        )

        let offsetHeads = drafts.map { draft -> RenderedNoteHead in
            let noteHead = draft.noteHead
            guard collisionColumns.contains(draft.collisionColumn) else {
                return noteHead
            }

            let xOffset = noteHead.voice == .upper
                ? style.voiceCollisionOffset
                : -style.voiceCollisionOffset
            return RenderedNoteHead(
                id: noteHead.id,
                sourceNoteID: noteHead.sourceNoteID,
                drumType: noteHead.drumType,
                voice: noteHead.voice,
                timePosition: noteHead.timePosition,
                measureIndex: noteHead.measureIndex,
                row: noteHead.row,
                position: CGPoint(
                    x: noteHead.position.x + xOffset,
                    y: noteHead.position.y
                ),
                staffStep: noteHead.staffStep,
                stemDirection: noteHead.stemDirection,
                interval: noteHead.interval
            )
        }

        return applyChordDirectionUnification(to: offsetHeads)
    }

    /// Unifies stemDirection for each same-voice chord (notes that share x, row,
    /// measureIndex, and voice). Without this, a chord with notes whose individual
    /// default directions disagree (e.g. crash on aboveLine5 → .down + snare on
    /// line3 → .up, both upper voice) would be split into two stems on opposite
    /// sides of the column. The chord adopts the direction of the notehead
    /// farthest from the middle staff line, matching standard engraving practice.
    private func applyChordDirectionUnification(
        to noteHeads: [RenderedNoteHead]
    ) -> [RenderedNoteHead] {
        struct ChordKey: Hashable {
            let x: Int
            let row: Int
            let measureIndex: Int
            let voice: NotationVoice
        }
        let middleStaffStep = -4  // line3 is at yOffset -40 → staffStep -4
        let groups = Dictionary(grouping: noteHeads) { head in
            ChordKey(
                x: Int((head.position.x * 1000).rounded()),
                row: head.row,
                measureIndex: head.measureIndex,
                voice: head.voice
            )
        }
        var unifiedDirectionByID: [UInt64: StemDirection] = [:]
        for (_, chord) in groups where chord.count > 1 {
            guard Set(chord.map(\.stemDirection)).count > 1 else { continue }
            let farthest = chord.max {
                let dist0 = abs($0.staffStep - middleStaffStep)
                let dist1 = abs($1.staffStep - middleStaffStep)
                if dist0 != dist1 { return dist0 < dist1 }
                // Tie-break: prefer higher staffStep (closer to top of staff)
                return $0.staffStep < $1.staffStep
            }
            guard let direction = farthest?.stemDirection else { continue }
            for head in chord {
                unifiedDirectionByID[head.id] = direction
            }
        }

        return noteHeads.map { head in
            guard let newDirection = unifiedDirectionByID[head.id],
                  newDirection != head.stemDirection else {
                return head
            }
            return RenderedNoteHead(
                id: head.id,
                sourceNoteID: head.sourceNoteID,
                drumType: head.drumType,
                voice: head.voice,
                timePosition: head.timePosition,
                measureIndex: head.measureIndex,
                row: head.row,
                position: head.position,
                staffStep: head.staffStep,
                stemDirection: newDirection,
                interval: head.interval
            )
        }
    }

    // MARK: - Helpers

    private func beatGap(for measure: RenderedMeasure, input: NotationLayoutInput) -> CGFloat {
        let drawableWidth = measure.width - GameplayLayout.barLineWidth - GameplayLayout.uniformSpacing
        return drawableWidth / CGFloat(input.timeSignature.beatsPerMeasure)
    }

    private func columnOffsets(forMeasureIndex measureIndex: Int, notes: [Note]) -> [Double] {
        Set(notes
            .filter { normalizedMeasureIndex(for: $0) == measureIndex }
            .map { quantizedOffset(for: normalizedOffset(for: $0)) })
            .sorted()
    }

    private func quantizedOffset(for measureOffset: Double) -> Double {
        (measureOffset * Self.columnResolution).rounded() / Self.columnResolution
    }

    private func normalizedMeasureIndex(for note: Note) -> Int {
        MeasureUtils.measureIndex(from: MeasureUtils.timePosition(
            measureNumber: note.measureNumber, measureOffset: note.measureOffset
        ))
    }

    private func normalizedOffset(for note: Note) -> Double {
        let timePos = MeasureUtils.timePosition(
            measureNumber: note.measureNumber, measureOffset: note.measureOffset
        )
        return timePos - Double(MeasureUtils.measureIndex(from: timePos))
    }

    private func quantizedColumn(for measureOffset: Double) -> Int {
        Int((measureOffset * Self.columnResolution).rounded())
    }

    private func staffStep(for position: GameplayLayout.NotePosition) -> Int {
        Int((position.yOffset / (GameplayLayout.staffLineSpacing / 2)).rounded())
    }

    private func notePosition(
        for drumType: DrumType,
        overrides: [DrumType: GameplayLayout.NotePosition]
    ) -> GameplayLayout.NotePosition {
        overrides[drumType] ?? drumType.notePosition
    }

    private func stemDirection(
        for position: GameplayLayout.NotePosition,
        voice: NotationVoice
    ) -> StemDirection {
        guard voice == .upper else { return .down }

        switch position {
        case .aboveLine9, .aboveLine8, .aboveLine7, .aboveLine6, .aboveLine5, .line5:
            return .down
        case .spaceBetween4And5, .line4, .spaceBetween3And4, .line3,
             .spaceBetween2And3, .line2, .spaceBetween1And2, .line1,
             .spaceBetweenLine1AndBelow, .belowLine1, .belowLine2,
             .belowLine3, .belowLine4, .belowLine5, .belowLine6:
            return .up
        }
    }

    // MARK: - Rendering Primitives (delegated to fileprivate extension)

    private func buildStems(
        noteHeads: [RenderedNoteHead],
        beams: [RenderedBeam],
        style: NotationLayoutStyle
    ) -> [RenderedStem] {
        // Index beams under every noteHeadID so non-leading notes in a beam run
        // can also look up their beam geometry.
        var beamsByNoteHeadID: [UInt64: [RenderedBeam]] = [:]
        for beam in beams {
            for noteHeadID in beam.noteHeadIDs {
                beamsByNoteHeadID[noteHeadID, default: []].append(beam)
            }
        }

        let headsNeedingStems = noteHeads.filter { $0.interval.needsStem }

        // Group note heads that share the same x, voice, and stem direction
        // (i.e., chord tones) so they share a single stem instead of overlapping.
        struct StemGroupKey: Hashable {
            let x: Int // Rounded to avoid floating-point drift
            let row: Int
            let measureIndex: Int
            let voice: NotationVoice
            let direction: StemDirection
        }

        let grouped = Dictionary(grouping: headsNeedingStems) { head in
            StemGroupKey(
                x: Int((head.position.x * 1000).rounded()),
                row: head.row,
                measureIndex: head.measureIndex,
                voice: head.voice,
                direction: head.stemDirection
            )
        }

        return grouped.compactMap { key, group in
            let allIDs = group.map(\.id)

            let representative: RenderedNoteHead
            switch key.direction {
            case .up:
                guard let r = group.max(by: { $0.position.y < $1.position.y }) else {
                    Logger.error("Stem grouping empty for key \(key) — skipping"); return nil
                }
                representative = r
            case .down:
                guard let r = group.min(by: { $0.position.y < $1.position.y }) else {
                    Logger.error("Stem grouping empty for key \(key) — skipping"); return nil
                }
                representative = r
            }

            let start = stemStart(for: representative, style: style)

            let candidateBeams = group.flatMap { head in
                beamsByNoteHeadID[head.id] ?? []
            }
            let outermostBeam = key.direction == .up
                ? candidateBeams.min(by: { $0.start.y < $1.start.y })
                : candidateBeams.max(by: { $0.start.y < $1.start.y })

            if let beam = outermostBeam,
               let beamY = beamEndY(for: representative, beam: beam, style: style) {
                return RenderedStem(
                    id: "stem_group_\(key.x)_r\(key.row)_m\(key.measureIndex)_\(key.voice.rawValue)_\(key.direction.rawValue)",
                    noteHeadIDs: allIDs,
                    direction: key.direction,
                    start: start,
                    end: CGPoint(x: start.x, y: beamY)
                )
            }
            // Not beamed — use fixed stem length from the representative head.
            let endY: CGFloat = switch key.direction {
            case .up: start.y - style.stemLength
            case .down: start.y + style.stemLength
            }

            return RenderedStem(
                id: "stem_group_\(key.x)_r\(key.row)_m\(key.measureIndex)_\(key.voice.rawValue)_\(key.direction.rawValue)",
                noteHeadIDs: allIDs,
                direction: key.direction,
                start: start,
                end: CGPoint(x: start.x, y: endY)
            )
        }
    }

    /// Computes stem end Y from beam geometry if noteHead is beamed.
    private func beamEndY(
        for noteHead: RenderedNoteHead,
        beam: RenderedBeam,
        style: NotationLayoutStyle
    ) -> Double? {
        // Only extend to beam if beam has multiple note heads.
        guard beam.noteHeadIDs.count > 1 else { return nil }

        let startX = beam.start.x, endX = beam.end.x
        let stemX = stemStart(for: noteHead, style: style).x

        guard stemX >= min(startX, endX) && stemX <= max(startX, endX) else { return nil }

        guard endX != startX else { return nil }

        let t = (stemX - startX) / (endX - startX)
        let beamY = beam.start.y + t * (beam.end.y - beam.start.y)

        // For upward stems, beam is above notehead so stem extends to beam Y.
        // For downward stems, beam is below notehead so stem extends to beam Y.
        return beamY
    }

    private func buildBeams(
        noteHeads: [RenderedNoteHead],
        style: NotationLayoutStyle
    ) -> [RenderedBeam] {
        let groupedHeads = Dictionary(grouping: noteHeads) {
            BeamGroupKey(
                measureIndex: $0.measureIndex,
                row: $0.row,
                voice: $0.voice,
                stemDirection: $0.stemDirection
            )
        }

        return groupedHeads.values
            .flatMap { heads in
                beamRuns(from: Array(heads)).flatMap { run in
                    beams(for: run, style: style)
                }
            }
            .sorted {
                if $0.start.y != $1.start.y {
                    return $0.start.y < $1.start.y
                }
                if $0.start.x != $1.start.x {
                    return $0.start.x < $1.start.x
                }
                return $0.level < $1.level
            }
    }

    private func buildFlags(
        noteHeads: [RenderedNoteHead],
        beams: [RenderedBeam],
        style: NotationLayoutStyle
    ) -> [RenderedFlag] {
        var coveredLevelsByNoteHead: [UInt64: Int] = [:]
        for beam in beams {
            for noteHeadID in beam.noteHeadIDs {
                let current = coveredLevelsByNoteHead[noteHeadID] ?? 0
                coveredLevelsByNoteHead[noteHeadID] = max(current, beam.level + 1)
            }
        }

        return noteHeads
            .filter { $0.interval.needsFlag }
            .flatMap { noteHead -> [RenderedFlag] in
                let coveredLevels = coveredLevelsByNoteHead[noteHead.id] ?? 0
                let totalFlags = noteHead.interval.flagCount
                guard coveredLevels < totalFlags else { return [] }

                let stemBottom = stemStart(for: noteHead, style: style)
                let flagOrigin = CGPoint(
                    x: stemBottom.x + GameplayLayout.flagXOffset,
                    y: noteHead.stemDirection == .up
                        ? stemBottom.y - style.stemLength
                        : stemBottom.y + style.stemLength
                )

                return (coveredLevels..<totalFlags).map { flagIndex in
                    let yOffset = noteHead.stemDirection == .up
                        ? CGFloat(flagIndex) * GameplayLayout.flagVerticalSpacing
                        : -CGFloat(flagIndex) * GameplayLayout.flagVerticalSpacing

                    return RenderedFlag(
                        id: "flag_\(noteHead.id)_\(flagIndex)",
                        noteHeadID: noteHead.id,
                        stemDirection: noteHead.stemDirection,
                        flagIndex: flagIndex,
                        origin: CGPoint(x: flagOrigin.x, y: flagOrigin.y + yOffset)
                    )
                }
            }
    }

    private func buildLedgerLines(
        noteHeads: [RenderedNoteHead],
        style: NotationLayoutStyle
    ) -> [RenderedLedgerLine] {
        noteHeads.flatMap { noteHead in
            ledgerSteps(for: noteHead.staffStep).map { step in
                let y = GameplayLayout.StaffLinePosition.line1.absoluteY(for: noteHead.row)
                    + CGFloat(step) * (style.staffLineSpacing / 2)
                let overhang = style.noteHeadWidth / 2 + style.ledgerLineOverhang

                return RenderedLedgerLine(
                    id: "ledger_\(noteHead.id)_\(step)",
                    row: noteHead.row,
                    start: CGPoint(x: noteHead.position.x - overhang, y: y),
                    end: CGPoint(x: noteHead.position.x + overhang, y: y)
                )
            }
        }
    }

    func buildMeasureBars(measures: [RenderedMeasure]) -> [RenderedMeasureBar] {
        var bars: [RenderedMeasureBar] = []

        for (index, measure) in measures.enumerated() {
            let isFirstInRow = index == 0 || measures[index - 1].row != measure.row
            let isLastOverall = measure.measureIndex == measures.last?.measureIndex

            if isFirstInRow {
                bars.append(RenderedMeasureBar(
                    id: "bar_\(measure.measureIndex)",
                    row: measure.row,
                    x: measure.xOffset,
                    isFinal: false
                ))
            }

            let nextOnSameRow = measures.count > index + 1
                && measures[index + 1].row == measure.row
            let endX: CGFloat
            if nextOnSameRow {
                endX = measures[index + 1].xOffset
            } else {
                endX = measure.xOffset + measure.width
            }

            bars.append(RenderedMeasureBar(
                id: "bar_\(measure.measureIndex)_end",
                row: measure.row,
                x: endX,
                isFinal: isLastOverall
            ))
        }

        return bars
    }

    // MARK: - Beam Helpers

    private func beamRuns(from noteHeads: [RenderedNoteHead]) -> [[RenderedNoteHead]] {
        let sortedHeads = noteHeads.sorted {
            if abs($0.timePosition - $1.timePosition) > BeamGroupingConstants.comparisonTolerance {
                return $0.timePosition < $1.timePosition
            }
            return $0.id < $1.id
        }
        var runs: [[RenderedNoteHead]] = []
        var currentRun: [RenderedNoteHead] = []

        for noteHead in sortedHeads {
            guard noteHead.interval.needsFlag else {
                if currentRun.count >= 2 {
                    runs.append(currentRun)
                }
                currentRun = []
                continue
            }

            if let previousHead = currentRun.last {
                let timeDifference = abs(noteHead.timePosition - previousHead.timePosition)
                if timeDifference <= BeamGroupingConstants.maxConsecutiveInterval
                    + BeamGroupingConstants.comparisonTolerance {
                    currentRun.append(noteHead)
                } else {
                    if currentRun.count >= 2 {
                        runs.append(currentRun)
                    }
                    currentRun = [noteHead]
                }
            } else {
                currentRun = [noteHead]
            }
        }

        if currentRun.count >= 2 {
            runs.append(currentRun)
        }

        return runs
    }

    private func beams(
        for noteHeads: [RenderedNoteHead],
        style: NotationLayoutStyle
    ) -> [RenderedBeam] {
        let maxFlagCount = noteHeads.map(\.interval.flagCount).max() ?? 0

        return (0..<maxFlagCount).flatMap { level in
            beamSegments(for: noteHeads, level: level).compactMap { levelHeads in
                guard let firstHead = levelHeads.first,
                      let lastHead = levelHeads.last,
                      levelHeads.count >= 2 else {
                    return nil
                }

                // Horizontal beam: choose the extremum stem-tip Y across the run
                // so every stem stays in its proper direction. Stems of the
                // notes farther from the beam will be lengthened to meet it.
                let sharedY = sharedBeamY(for: levelHeads, level: level, style: style)
                let startX = stemStart(for: firstHead, style: style).x
                let endX = stemStart(for: lastHead, style: style).x
                let start = CGPoint(x: startX, y: sharedY)
                let end = CGPoint(x: endX, y: sharedY)
                guard hasPositiveBeamSpan(from: firstHead, to: lastHead, start: start, end: end) else {
                    return nil
                }

                return RenderedBeam(
                    id: "beam_\(firstHead.measureIndex)_\(firstHead.row)_\(firstHead.voice.rawValue)_"
                        + "\(firstHead.stemDirection.rawValue)_\(level)_\(firstHead.id)_\(lastHead.id)",
                    noteHeadIDs: levelHeads.map(\.id),
                    direction: firstHead.stemDirection,
                    level: level,
                    start: start,
                    end: end,
                    thickness: style.beamThickness
                )
            }
        }
    }

    private func sharedBeamY(
        for noteHeads: [RenderedNoteHead],
        level: Int,
        style: NotationLayoutStyle
    ) -> CGFloat {
        let direction = noteHeads.first?.stemDirection ?? .up
        let levelOffset = CGFloat(level) * style.beamLevelSpacing
        let candidates = noteHeads.map { head -> CGFloat in
            switch direction {
            case .up: return head.position.y - style.stemLength - levelOffset
            case .down: return head.position.y + style.stemLength + levelOffset
            }
        }
        switch direction {
        case .up: return candidates.min() ?? 0
        case .down: return candidates.max() ?? 0
        }
    }

    private func beamSegments(
        for noteHeads: [RenderedNoteHead],
        level: Int
    ) -> [[RenderedNoteHead]] {
        var segments: [[RenderedNoteHead]] = []
        var currentSegment: [RenderedNoteHead] = []

        for noteHead in noteHeads {
            if noteHead.interval.flagCount > level {
                currentSegment.append(noteHead)
            } else {
                if currentSegment.count >= 2 {
                    segments.append(currentSegment)
                }
                currentSegment = []
            }
        }

        if currentSegment.count >= 2 {
            segments.append(currentSegment)
        }

        return segments
    }

    private func hasPositiveBeamSpan(
        from firstHead: RenderedNoteHead,
        to lastHead: RenderedNoteHead,
        start: CGPoint,
        end: CGPoint
    ) -> Bool {
        abs(lastHead.timePosition - firstHead.timePosition) > BeamGroupingConstants.comparisonTolerance
            && abs(end.x - start.x) > BeamGroupingConstants.comparisonTolerance
    }

    private func stemStart(
        for noteHead: RenderedNoteHead,
        style: NotationLayoutStyle
    ) -> CGPoint {
        let xOffset = switch noteHead.stemDirection {
        case .up:
            style.stemXInset
        case .down:
            -style.stemXInset
        }

        return CGPoint(x: noteHead.position.x + xOffset, y: noteHead.position.y)
    }

    private func beamPoint(
        for noteHead: RenderedNoteHead,
        level: Int,
        style: NotationLayoutStyle
    ) -> CGPoint {
        let start = stemStart(for: noteHead, style: style)
        let yOffset = switch noteHead.stemDirection {
        case .up:
            -style.stemLength - CGFloat(level) * style.beamLevelSpacing
        case .down:
            style.stemLength + CGFloat(level) * style.beamLevelSpacing
        }

        return CGPoint(x: start.x, y: noteHead.position.y + yOffset)
    }

    private func ledgerSteps(for staffStep: Int) -> [Int] {
        if staffStep < Self.topStaffStep {
            return stride(from: Self.topStaffStep - 2, through: staffStep, by: -2).map { $0 }
        }
        if staffStep > Self.bottomStaffStep {
            return stride(from: Self.bottomStaffStep + 2, through: staffStep, by: 2).map { $0 }
        }
        return []
    }
}
