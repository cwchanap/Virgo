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

    func layout(input: NotationLayoutInput) -> NotationLayout {
        let normalizedNotes = input.notes.sorted {
            MeasureUtils.timePosition(measureNumber: $0.measureNumber, measureOffset: $0.measureOffset)
            < MeasureUtils.timePosition(measureNumber: $1.measureNumber, measureOffset: $1.measureOffset)
        }
        let totalMeasures = max(1, (normalizedNotes.map(\.measureNumber).max() ?? 1))
        let measures = buildMeasures(totalMeasures: totalMeasures, notes: normalizedNotes, input: input)
        let noteHeads = buildNoteHeads(notes: normalizedNotes, measures: measures, input: input)
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
            stems: [],
            beams: [],
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
        let minimumBeatGap = input.style.minimumNoteColumnGap / CGFloat(
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
                        stemDirection: .up,
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
