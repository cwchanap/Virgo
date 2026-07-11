import CoreGraphics
import Foundation

/// Core layout engine - handles measure construction and note head placement.
struct NotationLayoutEngine {
    static let topStaffStep = -8
    static let bottomStaffStep = 0

    private struct NoteHeadPlacement {
        let timeColumn: NotationTimeColumn
        let timePosition: Double
        let row: Int
        let center: CGPoint
        let staffStep: Int
    }

    private struct BuiltNoteHead {
        let head: RenderedNoteHead
        let fallbackLaneID: String?
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
        let tabGrid = buildTabGrid(notes: sortedNotes, input: input)
        let measures = buildMeasures(totalMeasures: totalMeasures, tabGrid: tabGrid, input: input)
        let noteHeads = buildNoteHeads(notes: sortedNotes, measures: measures, tabGrid: tabGrid, input: input)
        let beams = buildBeams(noteHeads: noteHeads, style: input.style)
        let stems = buildStems(noteHeads: noteHeads, beams: beams, style: input.style)
        let flags = buildFlags(noteHeads: noteHeads, beams: beams, stems: stems, style: input.style)
        let ledgerLines = buildLedgerLines(noteHeads: noteHeads, style: input.style)
        let measureBars = buildMeasureBars(measures: measures)
        let noteHeadPositionsByID = Dictionary(uniqueKeysWithValues: noteHeads.map { ($0.id, $0.position) })
        let noteHeadIDsByLayoutTick = Dictionary(
            grouping: noteHeads,
            by: { $0.timeColumn.absoluteLayoutTick }
        ).mapValues { Set($0.map(\.id)) }
        let totalHeight = GameplayLayout.totalHeight(
            for: measures.map {
                GameplayLayout.MeasurePosition(row: $0.row, xOffset: $0.xOffset, measureIndex: $0.measureIndex)
            }
        )

        return NotationLayout(
            tabGrid: tabGrid,
            measures: measures,
            noteHeadSize: input.style.noteHeadSize,
            noteHeads: noteHeads,
            stems: stems,
            beams: beams,
            flags: flags,
            ledgerLines: ledgerLines,
            measureBars: measureBars,
            noteHeadPositionsByID: noteHeadPositionsByID,
            noteHeadIDsByLayoutTick: noteHeadIDsByLayoutTick,
            totalHeight: totalHeight
        )
    }

    // MARK: - Measure Building

    private func buildMeasures(
        totalMeasures: Int,
        tabGrid: TabGrid,
        input: NotationLayoutInput
    ) -> [RenderedMeasure] {
        var result: [RenderedMeasure] = []
        var currentRow = 0
        var currentX = GameplayLayout.leftMargin

        for measureIndex in 0..<totalMeasures {
            if currentX + tabGrid.measureWidth > input.style.rowWidth, measureIndex > 0 {
                currentRow += 1
                currentX = GameplayLayout.leftMargin
            }
            result.append(
                RenderedMeasure(
                    id: measureIndex, measureIndex: measureIndex,
                    row: currentRow, xOffset: currentX, width: tabGrid.measureWidth
                )
            )
            currentX += tabGrid.measureWidth + GameplayLayout.measureSpacing
        }

        return result
    }

    // MARK: - Note Head Building

    private func buildNoteHeads(
        notes: [Note],
        measures: [RenderedMeasure],
        tabGrid: TabGrid,
        input: NotationLayoutInput
    ) -> [RenderedNoteHead] {
        let measuresByIndex = Dictionary(
            uniqueKeysWithValues: measures.map { ($0.measureIndex, $0) }
        )
        var fallbackLaneIDs: Set<String> = []
        let heads = notes.enumerated().compactMap { index, note -> RenderedNoteHead? in
            guard let built = buildNoteHead(
                index: index,
                note: note,
                measuresByIndex: measuresByIndex,
                tabGrid: tabGrid,
                input: input
            ) else { return nil }
            if let laneID = built.fallbackLaneID {
                fallbackLaneIDs.insert(laneID)
            }
            return built.head
        }

        if !fallbackLaneIDs.isEmpty {
            Logger.warning(
                "Drum notation used NoteType fallback for source lanes: "
                    + fallbackLaneIDs.sorted().joined(separator: ", ")
            )
        }

        return sortedNoteHeads(heads)
    }

    private func buildNoteHead(
        index: Int,
        note: Note,
        measuresByIndex: [Int: RenderedMeasure],
        tabGrid: TabGrid,
        input: NotationLayoutInput
    ) -> BuiltNoteHead? {
        guard let resolved = DrumNotationCatalog.resolve(
            noteType: note.noteType,
            sourceLaneID: note.sourceLaneID
        ) else {
            assertionFailure("Missing drum notation definition for \(note.noteType)")
            Logger.error("Skipping note with missing notation definition: \(note.noteType)")
            return nil
        }
        let definition = resolved.definition
        let drumType = definition.gameplayInstrument
        let position = input.notePositionOverrides[drumType] ?? definition.defaultPosition
        guard let placement = noteHeadPlacement(
            for: note,
            position: position,
            measuresByIndex: measuresByIndex,
            tabGrid: tabGrid
        ) else { return nil }

        let head = RenderedNoteHead(
            id: UInt64(index),
            sourceObjectID: ObjectIdentifier(note),
            sourceLaneID: note.sourceLaneID,
            sourceChipID: note.sourceNoteID,
            noteType: note.noteType,
            drumType: drumType,
            glyph: definition.glyph,
            variant: resolved.variant,
            voice: definition.voice,
            stemDirection: definition.defaultStemDirection,
            timeColumn: placement.timeColumn,
            timePosition: placement.timePosition,
            row: placement.row,
            position: placement.center,
            staffStep: placement.staffStep,
            interval: note.interval,
            catalogOrder: definition.catalogOrder
        )
        let fallbackLaneID = resolved.usedLaneFallback
            ? note.sourceLaneID?.uppercased()
            : nil
        return BuiltNoteHead(head: head, fallbackLaneID: fallbackLaneID)
    }

    private func noteHeadPlacement(
        for note: Note,
        position: GameplayLayout.NotePosition,
        measuresByIndex: [Int: RenderedMeasure],
        tabGrid: TabGrid
    ) -> NoteHeadPlacement? {
        let timePosition = MeasureUtils.timePosition(
            measureNumber: note.measureNumber,
            measureOffset: note.measureOffset
        )
        let measureIndex = MeasureUtils.measureIndex(from: timePosition)
        guard let measure = measuresByIndex[measureIndex] else { return nil }
        let tickIndex = tickWithinMeasure(for: note, ticksPerMeasure: tabGrid.ticksPerMeasure)
        let timeColumn = NotationTimeColumn(
            measureIndex: measureIndex,
            tickWithinMeasure: tickIndex,
            absoluteLayoutTick: measureIndex * tabGrid.ticksPerMeasure + tickIndex
        )
        let center = CGPoint(
            x: tabGrid.xPosition(in: measure, tickIndex: tickIndex),
            y: GameplayLayout.StaffLinePosition.line1.absoluteY(for: measure.row)
                + position.yOffset
        )
        return NoteHeadPlacement(
            timeColumn: timeColumn,
            timePosition: timePosition,
            row: measure.row,
            center: center,
            staffStep: staffStep(for: position)
        )
    }

    private func sortedNoteHeads(_ heads: [RenderedNoteHead]) -> [RenderedNoteHead] {
        // Sort by layout tick for deterministic column ordering. This differs
        // from stemRepresentative (in +Beams), which sorts by position.y to pick
        // the visually outermost note head for stem length — the two orderings
        // serve different purposes and intentionally use different primary keys.
        heads.sorted {
            if $0.timeColumn.absoluteLayoutTick != $1.timeColumn.absoluteLayoutTick {
                return $0.timeColumn.absoluteLayoutTick < $1.timeColumn.absoluteLayoutTick
            }
            if $0.catalogOrder != $1.catalogOrder {
                return $0.catalogOrder < $1.catalogOrder
            }
            return $0.id < $1.id
        }
    }

    // MARK: - Helpers

    func normalizedMeasureIndex(for note: Note) -> Int {
        MeasureUtils.measureIndex(from: MeasureUtils.timePosition(
            measureNumber: note.measureNumber, measureOffset: note.measureOffset
        ))
    }

    func normalizedOffset(for note: Note) -> Double {
        let timePos = MeasureUtils.timePosition(
            measureNumber: note.measureNumber, measureOffset: note.measureOffset
        )
        return timePos - Double(MeasureUtils.measureIndex(from: timePos))
    }

    private func staffStep(for position: GameplayLayout.NotePosition) -> Int {
        Int((position.yOffset / (GameplayLayout.staffLineSpacing / 2)).rounded())
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
}
