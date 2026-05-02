import CoreGraphics
import Foundation

struct NotationLayoutEngine {
    func layout(input: NotationLayoutInput) -> NotationLayout {
        let normalizedNotes = input.notes.sorted {
            MeasureUtils.timePosition(measureNumber: $0.measureNumber, measureOffset: $0.measureOffset)
            < MeasureUtils.timePosition(measureNumber: $1.measureNumber, measureOffset: $1.measureOffset)
        }
        let totalMeasures = max(1, (normalizedNotes.map(\.measureNumber).max() ?? 1))
        let measures = buildMeasures(totalMeasures: totalMeasures, notes: normalizedNotes, input: input)
        let noteHeads = buildNoteHeads(notes: normalizedNotes, measures: measures, input: input)
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
            ledgerLines: [],
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
        let offsets = notes
            .filter { $0.measureNumber == measureNumber }
            .map(\.measureOffset)
            .sorted()

        guard offsets.count > 1 else {
            return GameplayLayout.measureWidth(for: input.timeSignature)
        }

        let smallestGap = zip(offsets.dropFirst(), offsets)
            .map { pair in pair.0 - pair.1 }
            .min() ?? 0.25
        let beatGap = max(
            input.style.minimumQuarterBeatGap,
            input.style.minimumNoteColumnGap / CGFloat(max(smallestGap * Double(input.timeSignature.beatsPerMeasure), 0.001))
        )
        return GameplayLayout.barLineWidth
            + input.style.measurePadding
            + CGFloat(input.timeSignature.beatsPerMeasure) * beatGap
            + input.style.measurePadding
    }

    private func buildNoteHeads(
        notes: [Note],
        measures: [RenderedMeasure],
        input: NotationLayoutInput
    ) -> [RenderedNoteHead] {
        var nextID: UInt64 = 0
        let measuresByIndex = Dictionary(uniqueKeysWithValues: measures.map { ($0.measureIndex, $0) })

        return notes.compactMap { note in
            guard let drumType = DrumType.from(noteType: note.noteType) else { return nil }
            let measureIndex = MeasureUtils.toZeroBasedIndex(note.measureNumber)
            guard let measure = measuresByIndex[measureIndex] else { return nil }
            let beatGap = beatGap(for: measure, input: input)
            let x = measure.xOffset + GameplayLayout.barLineWidth + input.style.measurePadding
                + CGFloat(note.measureOffset * Double(input.timeSignature.beatsPerMeasure)) * beatGap
            let y = GameplayLayout.StaffLinePosition.line1.absoluteY(for: measure.row)
                + drumType.notePosition.yOffset
            let id = nextID
            nextID += 1

            return RenderedNoteHead(
                id: id,
                sourceNoteID: ObjectIdentifier(note),
                drumType: drumType,
                voice: NotationVoice.voice(for: drumType),
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
            )
        }
    }

    private func beatGap(for measure: RenderedMeasure, input: NotationLayoutInput) -> CGFloat {
        let drawableWidth = measure.width - GameplayLayout.barLineWidth - input.style.measurePadding * 2
        return drawableWidth / CGFloat(input.timeSignature.beatsPerMeasure)
    }

    private func staffStep(for position: GameplayLayout.NotePosition) -> Int {
        Int((position.yOffset / (GameplayLayout.staffLineSpacing / 2)).rounded())
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
