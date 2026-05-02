import CoreGraphics
import Foundation

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

    private struct BeamGroupKey: Hashable {
        let measureIndex: Int
        let row: Int
        let voice: NotationVoice
        let stemDirection: StemDirection
    }

    func layout(input: NotationLayoutInput) -> NotationLayout {
        let normalizedNotes = input.notes.sorted {
            MeasureUtils.timePosition(measureNumber: $0.measureNumber, measureOffset: $0.measureOffset)
            < MeasureUtils.timePosition(measureNumber: $1.measureNumber, measureOffset: $1.measureOffset)
        }
        let totalMeasures = max(1, (normalizedNotes.map(\.measureNumber).max() ?? 1))
        let measures = buildMeasures(totalMeasures: totalMeasures, notes: normalizedNotes, input: input)
        let noteHeads = buildNoteHeads(notes: normalizedNotes, measures: measures, input: input)
        let stems = buildStems(noteHeads: noteHeads, style: input.style)
        let beams = buildBeams(noteHeads: noteHeads, style: input.style)
        let ledgerLines = buildLedgerLines(noteHeads: noteHeads, style: input.style)
        let measureBars = buildMeasureBars(measures: measures)
        let beatLookup = Dictionary(uniqueKeysWithValues: noteHeads.map { ($0.id, $0.position) })
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
            ledgerLines: ledgerLines,
            measureBars: measureBars,
            beatLookup: beatLookup,
            totalHeight: totalHeight
        )
    }

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
                    id: measureIndex,
                    measureIndex: measureIndex,
                    row: currentRow,
                    xOffset: currentX,
                    width: width
                )
            )
            currentX += width + GameplayLayout.measureSpacing
        }

        return result
    }

    private func measureWidth(
        measureIndex: Int,
        notes: [Note],
        input: NotationLayoutInput
    ) -> CGFloat {
        let measureNumber = MeasureUtils.toOneBasedNumber(measureIndex)
        let offsets = columnOffsets(for: measureNumber, notes: notes)
        let legacyWidth = GameplayLayout.measureWidth(for: input.timeSignature)

        guard offsets.count > 1 else {
            return legacyWidth
        }

        let smallestGap = zip(offsets.dropFirst(), offsets)
            .map { pair in pair.0 - pair.1 }
            .min() ?? 0.25
        let requiredColumnGap = minimumColumnGap(
            measureNumber: measureNumber,
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
        measureNumber: Int,
        notes: [Note],
        style: NotationLayoutStyle
    ) -> CGFloat {
        guard containsCrossVoiceCollision(measureNumber: measureNumber, notes: notes) else {
            return style.minimumNoteColumnGap
        }

        return style.minimumNoteColumnGap + 2 * style.voiceCollisionOffset
    }

    private func containsCrossVoiceCollision(measureNumber: Int, notes: [Note]) -> Bool {
        Dictionary(
            grouping: notes.filter { $0.measureNumber == measureNumber },
            by: { quantizedColumn(for: $0.measureOffset) }
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
            let measureIndex = MeasureUtils.toZeroBasedIndex(note.measureNumber)
            guard let measure = measuresByIndex[measureIndex] else { continue }
            let beatGap = beatGap(for: measure, input: input)
            let beatPosition = quantizedOffset(for: note.measureOffset) * Double(input.timeSignature.beatsPerMeasure)
            let x = measure.xOffset + GameplayLayout.barLineWidth + GameplayLayout.uniformSpacing
                + CGFloat(beatPosition) * beatGap
            let y = GameplayLayout.StaffLinePosition.line1.absoluteY(for: measure.row)
                + drumType.notePosition.yOffset
            let id = nextID
            let voice = NotationVoice.voice(for: drumType)
            let direction = stemDirection(for: drumType, voice: voice)
            nextID += 1

            drafts.append(
                NoteHeadDraft(
                    noteHead: RenderedNoteHead(
                        id: id,
                        sourceNoteID: ObjectIdentifier(note),
                        drumType: drumType,
                        voice: voice,
                        timePosition: MeasureUtils.timePosition(
                            measureNumber: note.measureNumber,
                            measureOffset: note.measureOffset
                        ),
                        measureIndex: measureIndex,
                        row: measure.row,
                        position: CGPoint(x: x, y: y),
                        staffStep: staffStep(for: drumType.notePosition),
                        stemDirection: direction,
                        interval: note.interval
                    ),
                    collisionColumn: VoiceCollisionColumn(
                        measureIndex: measureIndex,
                        quantizedColumn: quantizedColumn(for: note.measureOffset)
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

        return drafts.map { draft in
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
    }

    private func beatGap(for measure: RenderedMeasure, input: NotationLayoutInput) -> CGFloat {
        let drawableWidth = measure.width - GameplayLayout.barLineWidth - GameplayLayout.uniformSpacing
        return drawableWidth / CGFloat(input.timeSignature.beatsPerMeasure)
    }

    private func columnOffsets(for measureNumber: Int, notes: [Note]) -> [Double] {
        Set(notes
            .filter { $0.measureNumber == measureNumber }
            .map { quantizedOffset(for: $0.measureOffset) })
            .sorted()
    }

    private func quantizedOffset(for measureOffset: Double) -> Double {
        (measureOffset * Self.columnResolution).rounded() / Self.columnResolution
    }

    private func quantizedColumn(for measureOffset: Double) -> Int {
        Int((measureOffset * Self.columnResolution).rounded())
    }

    private func staffStep(for position: GameplayLayout.NotePosition) -> Int {
        Int((position.yOffset / (GameplayLayout.staffLineSpacing / 2)).rounded())
    }
}

private extension NotationLayoutEngine {
    private func stemDirection(for drumType: DrumType, voice: NotationVoice) -> StemDirection {
        guard voice == .upper else { return .down }

        switch drumType.notePosition {
        case .aboveLine9, .aboveLine8, .aboveLine7, .aboveLine6, .aboveLine5, .line5:
            return .down
        case .spaceBetween4And5,
             .line4,
             .spaceBetween3And4,
             .line3,
             .spaceBetween2And3,
             .line2,
             .spaceBetween1And2,
             .line1,
             .spaceBetweenLine1AndBelow,
             .belowLine1,
             .belowLine2,
             .belowLine3,
             .belowLine4,
             .belowLine5,
             .belowLine6:
            return .up
        }
    }

    private func buildStems(
        noteHeads: [RenderedNoteHead],
        style: NotationLayoutStyle
    ) -> [RenderedStem] {
        noteHeads
            .filter { $0.interval.needsStem }
            .map { noteHead in
                let start = stemStart(for: noteHead, style: style)
                let endY = switch noteHead.stemDirection {
                case .up:
                    start.y - style.stemLength
                case .down:
                    start.y + style.stemLength
                }

                return RenderedStem(
                    id: "stem_\(noteHead.id)",
                    noteHeadIDs: [noteHead.id],
                    direction: noteHead.stemDirection,
                    start: start,
                    end: CGPoint(x: start.x, y: endY)
                )
            }
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
                beamRuns(from: heads).flatMap { run in
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
                guard let firstHead = levelHeads.first, let lastHead = levelHeads.last, levelHeads.count >= 2 else {
                    return nil
                }

                let start = beamPoint(for: firstHead, level: level, style: style)
                let end = beamPoint(for: lastHead, level: level, style: style)
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

    private func ledgerSteps(for staffStep: Int) -> [Int] {
        if staffStep < Self.topStaffStep {
            return stride(from: Self.topStaffStep - 2, through: staffStep, by: -2).map { $0 }
        }
        if staffStep > Self.bottomStaffStep {
            return stride(from: Self.bottomStaffStep + 2, through: staffStep, by: 2).map { $0 }
        }
        return []
    }

    private func buildMeasureBars(measures: [RenderedMeasure]) -> [RenderedMeasureBar] {
        measures.flatMap { measure in
            [
                RenderedMeasureBar(
                    id: "bar_\(measure.measureIndex)",
                    row: measure.row,
                    x: measure.xOffset,
                    isFinal: false
                ),
                RenderedMeasureBar(
                    id: "bar_\(measure.measureIndex)_end",
                    row: measure.row,
                    x: measure.xOffset + measure.width,
                    isFinal: measure.measureIndex == measures.last?.measureIndex
                )
            ]
        }
    }
}
