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
        switch input.timing {
        case .timeline(let snapshot):
            return layoutTimeline(snapshot: snapshot, input: input)
        case .legacy:
            return layoutLegacy(input: input)
        }
    }

    private func layoutLegacy(input: NotationLayoutInput) -> NotationLayout {
        let sortedNotes = input.notes.sorted {
            MeasureUtils.timePosition(measureNumber: $0.measureNumber, measureOffset: $0.measureOffset)
                < MeasureUtils.timePosition(measureNumber: $1.measureNumber, measureOffset: $1.measureOffset)
        }
        let controlTiming = resolveControlTimings(input.controlEvents)
        let totalMeasures = totalMeasureCount(
            notes: sortedNotes,
            controls: controlTiming.controls,
            minimumMeasureCount: input.minimumMeasureCount
        )
        let tabGrid = buildTabGrid(notes: sortedNotes, input: input)
        let measures = buildMeasures(totalMeasures: totalMeasures, tabGrid: tabGrid, input: input)
        let noteHeads = buildNoteHeads(notes: sortedNotes, measures: measures, tabGrid: tabGrid, input: input)
        let derived = buildDerivedArtifacts(
            noteHeads: noteHeads,
            measures: measures,
            tabGrid: tabGrid,
            rhythmMeasures: nil,
            input: input
        )
        let rests = buildRests(noteHeads: noteHeads, measures: measures, tabGrid: tabGrid, input: input)
        let renderedControls = buildStopNotes(
            controls: controlTiming.controls,
            measures: measures,
            tabGrid: tabGrid,
            input: input
        )
        let articulations = buildArticulations(noteHeads: noteHeads, style: input.style)
        logControlDiagnostics(timing: controlTiming, rendering: renderedControls)
        return finalizedLayout(NotationLayoutFinalizationInput(
            tabGrid: tabGrid,
            measures: measures,
            noteHeads: noteHeads,
            rests: rests,
            stopNotes: renderedControls.stopNotes,
            articulations: articulations,
            derived: derived,
            rhythmDots: [],
            tuplets: [],
            feelMarks: [],
            rhythmWarnings: [],
            style: input.style
        ))
    }

    private func layoutTimeline(
        snapshot: RhythmLayoutSnapshot,
        input: NotationLayoutInput
    ) -> NotationLayout {
        let tabGrid = buildTabGrid(snapshot: snapshot, input: input)
        let rhythmMeasures = expandedRhythmMeasures(
            snapshot,
            minimumMeasureCount: input.minimumMeasureCount
        )
        let measures = buildMeasures(rhythmMeasures: rhythmMeasures, tabGrid: tabGrid, input: input)
        let unsupportedMeasureIndexes = Set(rhythmMeasures.compactMap { measure -> Int? in
            if case .unsupported = measure.engravingSupport { return measure.measureIndex }
            return nil
        })
        let noteHeads = buildNoteHeads(
            notes: snapshot.notes,
            measures: measures,
            tabGrid: tabGrid,
            input: input
        )
        let derived = buildDerivedArtifacts(
            noteHeads: noteHeads,
            measures: measures,
            tabGrid: tabGrid,
            rhythmMeasures: rhythmMeasures,
            input: input
        )
        let rests = buildRests(
            rests: snapshot.rests.filter {
                !unsupportedMeasureIndexes.contains($0.position.measureIndex)
            },
            measures: measures,
            tabGrid: tabGrid,
            style: input.style
        )
        let stopNotes = buildStopNotes(
            controls: snapshot.controls,
            measures: measures,
            tabGrid: tabGrid,
            input: input
        )
        let articulations = buildArticulations(noteHeads: noteHeads, style: input.style)
        let rhythmDots = buildRhythmDots(
            noteHeads: noteHeads,
            rests: rests,
            unsupportedMeasureIndexes: unsupportedMeasureIndexes,
            style: input.style
        )
        let tuplets = buildTuplets(
            noteHeads: noteHeads,
            rests: rests,
            context: TupletRenderingContext(
                beams: derived.beams,
                feel: snapshot.feel,
                rhythmMeasures: rhythmMeasures,
                unsupportedMeasureIndexes: unsupportedMeasureIndexes,
                style: input.style
            )
        )
        let feelMarks = buildFeelMarks(feel: snapshot.feel, measures: measures, style: input.style)
        let rhythmWarnings = buildRhythmWarnings(
            rhythmMeasures: rhythmMeasures,
            renderedMeasures: measures,
            style: input.style
        )
        return finalizedLayout(NotationLayoutFinalizationInput(
            tabGrid: tabGrid,
            measures: measures,
            noteHeads: noteHeads,
            rests: rests,
            stopNotes: stopNotes,
            articulations: articulations,
            derived: derived,
            rhythmDots: rhythmDots,
            tuplets: tuplets,
            feelMarks: feelMarks,
            rhythmWarnings: rhythmWarnings,
            style: input.style
        ))
    }

    struct BuiltDerivedArtifacts {
        let beams: [RenderedBeam]
        let stems: [RenderedStem]
        let flags: [RenderedFlag]
        let ledgerLines: [RenderedLedgerLine]
        let measureBars: [RenderedMeasureBar]
    }

    /// Builds beams, stems, flags, ledger lines, and measure bars from the
    /// placed note heads. Extracted from ``layout(input:)`` to keep that
    /// function under SwiftLint's function-body-length warn limit.
    private func buildDerivedArtifacts(
        noteHeads: [RenderedNoteHead],
        measures: [RenderedMeasure],
        tabGrid: TabGrid,
        rhythmMeasures: [RhythmMeasure]?,
        input: NotationLayoutInput
    ) -> BuiltDerivedArtifacts {
        let beamBuild: BeamBuildResult
        if let rhythmMeasures {
            beamBuild = buildBeams(
                noteHeads: noteHeads,
                measures: rhythmMeasures,
                style: input.style
            )
        } else {
            beamBuild = buildBeams(
                noteHeads: noteHeads,
                tabGrid: tabGrid,
                timeSignature: input.timeSignature,
                style: input.style
            )
        }
        let stems = buildStems(
            noteHeads: noteHeads,
            beams: beamBuild.beams,
            style: input.style
        )
        let flags = buildFlags(
            noteHeads: noteHeads,
            beamBuild: beamBuild,
            stems: stems,
            style: input.style
        )
        let ledgerLines = buildLedgerLines(noteHeads: noteHeads, style: input.style)
        let measureBars = rhythmMeasures == nil
            ? buildMeasureBars(measures: measures)
            : buildMeasureBars(measures: measures, tabGrid: tabGrid)
        return BuiltDerivedArtifacts(
            beams: beamBuild.beams,
            stems: stems,
            flags: flags,
            ledgerLines: ledgerLines,
            measureBars: measureBars
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
                    row: currentRow, xOffset: currentX, width: tabGrid.measureWidth,
                    startTick: measureIndex * tabGrid.ticksPerMeasure,
                    durationTicks: tabGrid.ticksPerMeasure
                )
            )
            currentX += tabGrid.measureWidth + GameplayLayout.measureSpacing
        }

        return result
    }

    private func buildMeasures(
        rhythmMeasures: [RhythmMeasure],
        tabGrid: TabGrid,
        input: NotationLayoutInput
    ) -> [RenderedMeasure] {
        var result: [RenderedMeasure] = []
        var currentRow = 0
        var currentX = GameplayLayout.leftMargin
        let rowWidth = max(GameplayLayout.maxRowWidth, input.style.rowWidth)

        for rhythmMeasure in rhythmMeasures {
            let width = tabGrid.leftPadding + CGFloat(rhythmMeasure.durationTicks) * tabGrid.tickWidth
            if currentX + width > rowWidth, !result.isEmpty {
                currentRow += 1
                currentX = GameplayLayout.leftMargin
            }
            result.append(RenderedMeasure(
                id: rhythmMeasure.measureIndex,
                measureIndex: rhythmMeasure.measureIndex,
                row: currentRow,
                xOffset: currentX,
                width: width,
                startTick: rhythmMeasure.startTick,
                durationTicks: rhythmMeasure.durationTicks
            ))
            currentX += width + GameplayLayout.measureSpacing
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

    private func buildNoteHeads(
        notes: [RhythmLayoutNote],
        measures: [RenderedMeasure],
        tabGrid: TabGrid,
        input: NotationLayoutInput
    ) -> [RenderedNoteHead] {
        let measuresByIndex = Dictionary(uniqueKeysWithValues: measures.map { ($0.measureIndex, $0) })
        return notes.compactMap { note in
            guard let resolved = DrumNotationCatalog.resolve(
                noteType: note.noteType,
                sourceLaneID: note.sourceLaneID
            ), let id = UInt64(exactly: note.eventID.rawValue),
            let measure = measuresByIndex[note.position.measureIndex],
            note.position.localTick >= 0,
            note.position.localTick < measure.durationTicks,
            note.position.absoluteTick == measure.startTick + note.position.localTick else {
                return nil
            }
            let definition = resolved.definition
            let drumType = definition.gameplayInstrument
            let notePosition = input.notePositionOverrides[drumType] ?? definition.defaultPosition
            let timeColumn = NotationTimeColumn(
                measureIndex: note.position.measureIndex,
                tickWithinMeasure: note.position.localTick,
                absoluteLayoutTick: note.position.absoluteTick
            )
            return RenderedNoteHead(
                id: id,
                sourceObjectID: note.sourceObjectID,
                sourceLaneID: note.sourceLaneID,
                sourceChipID: note.sourceChipID,
                noteType: note.noteType,
                drumType: drumType,
                glyph: definition.glyph,
                variant: resolved.variant,
                voice: definition.voice,
                stemDirection: definition.defaultStemDirection,
                timeColumn: timeColumn,
                timePosition: Double(note.position.absoluteTick),
                row: measure.row,
                position: CGPoint(
                    x: tabGrid.xPosition(in: measure, localTick: note.position.localTick),
                    y: GameplayLayout.StaffLinePosition.line1.absoluteY(for: measure.row)
                        + notePosition.yOffset
                ),
                staffStep: staffStep(for: notePosition),
                interval: note.rhythm.baseInterval,
                catalogOrder: definition.catalogOrder,
                eventID: note.eventID,
                rhythmPosition: note.position,
                rhythmDurationTicks: note.durationTicks,
                rhythm: note.rhythm,
                tupletID: note.tupletID
            )
        }.sorted {
            if $0.timeColumn.absoluteLayoutTick != $1.timeColumn.absoluteLayoutTick {
                return $0.timeColumn.absoluteLayoutTick < $1.timeColumn.absoluteLayoutTick
            }
            if $0.catalogOrder != $1.catalogOrder { return $0.catalogOrder < $1.catalogOrder }
            return $0.id < $1.id
        }
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
            catalogOrder: definition.catalogOrder,
            eventID: nil,
            rhythmPosition: RhythmEventPosition(
                measureIndex: placement.timeColumn.measureIndex,
                localTick: placement.timeColumn.tickWithinMeasure,
                absoluteTick: placement.timeColumn.absoluteLayoutTick
            ),
            rhythmDurationTicks: NotationRestTopologyBuilder().noteDurationTicks(
                for: note.interval,
                ticksPerMeasure: tabGrid.ticksPerMeasure,
                timeSignature: input.timeSignature
            ),
            rhythm: NotationRhythm(baseInterval: note.interval),
            tupletID: nil
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

    func staffStep(for position: GameplayLayout.NotePosition) -> Int {
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

    func buildMeasureBars(
        measures: [RenderedMeasure],
        tabGrid: TabGrid
    ) -> [RenderedMeasureBar] {
        var bars: [RenderedMeasureBar] = []
        for (index, measure) in measures.enumerated() {
            let isFirstInRow = index == 0 || measures[index - 1].row != measure.row
            if isFirstInRow {
                bars.append(RenderedMeasureBar(
                    id: "bar_\(measure.measureIndex)",
                    row: measure.row,
                    x: measure.xOffset,
                    isFinal: false
                ))
            }
            bars.append(RenderedMeasureBar(
                id: "bar_\(measure.measureIndex)_end",
                row: measure.row,
                x: tabGrid.xPosition(in: measure, localTick: measure.durationTicks),
                isFinal: measure.measureIndex == measures.last?.measureIndex
            ))
        }
        return bars
    }
}
