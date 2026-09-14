import CoreGraphics
import Foundation

/// Notation primitive builders consumed by ``GameplayNotationPreparer``.
/// The measured formatter (HPA-164) owns every X: measure bounds and rows
/// come from the formatted measures, and head/rest/control builders receive
/// the package's column X through lookup tables. This engine owns the
/// app-owned remainder: staff Y placement, voice/semantics, trailing-measure
/// expansion, and the derived artifacts rebuilt from positioned primitives.
/// (The fixed-grid route was removed in HPA-164 Task 6.)
struct NotationLayoutEngine {
    static let topStaffStep = -8
    static let bottomStaffStep = 0

    // MARK: - Measure Expansion

    /// Bound per-measure arrays, synthesized rests, and row geometry with the
    /// same chart-wide limit used by canonical rhythm validation.
    static let maximumRenderableMeasureCount = RhythmLimits.maximumMeasureCount

    func expandedRhythmMeasures(
        _ snapshot: RhythmLayoutSnapshot,
        minimumMeasureCount: Int
    ) -> [RhythmMeasure] {
        var measures = snapshot.measures.sorted { $0.measureIndex < $1.measureIndex }
        let requestedCount = min(
            max(minimumMeasureCount, measures.count, 1),
            Self.maximumRenderableMeasureCount
        )
        guard let template = measures.last else { return [] }
        while measures.count < requestedCount {
            let measureIndex = measures.count
            let durationTicks = nominalDurationTicks(
                timeSignature: template.timeSignature,
                ticksPerWholeNote: snapshot.ticksPerWholeNote
            ) ?? template.durationTicks
            let startTick = measures.last?.endTick ?? 0
            measures.append(RhythmMeasure(
                measureIndex: measureIndex,
                startTick: startTick,
                durationTicks: durationTicks,
                timeSignature: template.timeSignature,
                beatGroups: RhythmBeatGroupBuilder.groups(
                    timeSignature: template.timeSignature,
                    durationTicks: durationTicks,
                    ticksPerWholeNote: snapshot.ticksPerWholeNote
                ),
                engravingSupport: template.engravingSupport
            ))
        }
        return measures
    }

    private func nominalDurationTicks(
        timeSignature: TimeSignature,
        ticksPerWholeNote: Int
    ) -> Int? {
        let product = ticksPerWholeNote.multipliedReportingOverflow(by: timeSignature.beatsPerMeasure)
        guard !product.overflow,
              timeSignature.noteValue > 0,
              product.partialValue.isMultiple(of: timeSignature.noteValue) else { return nil }
        return product.partialValue / timeSignature.noteValue
    }

    // MARK: - Derived Artifacts

    struct BuiltDerivedArtifacts {
        let beams: [RenderedBeam]
        let stems: [RenderedStem]
        let flags: [RenderedFlag]
        let ledgerLines: [RenderedLedgerLine]
        let measureBars: [RenderedMeasureBar]
    }

    // MARK: - Note Head Building

    /// Builds note heads from snapshot notes. X comes from the package:
    /// `headCenterXByID` carries each note's displaced head-center, and
    /// `columnXByKey` the logical column anchors used as the deterministic
    /// fallback when a head has no package entry.
    func buildNoteHeads(
        notes: [RhythmLayoutNote],
        measures: [RenderedMeasure],
        headCenterXByID: [UInt64: CGFloat],
        columnXByKey: [MeasureTickKey: CGFloat],
        style: NotationLayoutStyle,
        notePositionOverrides: [DrumType: GameplayLayout.NotePosition]
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
            let notePosition = notePositionOverrides[drumType] ?? definition.defaultPosition
            let timeColumn = NotationTimeColumn(
                measureIndex: note.position.measureIndex,
                tickWithinMeasure: note.position.localTick,
                absoluteLayoutTick: note.position.absoluteTick
            )
            let centerX: CGFloat
            if let headCenterX = headCenterXByID[id] {
                centerX = headCenterX
            } else {
                // Drift guard (HPA-164): the adapter's projection guards match
                // the ones above, so every built head has a package column.
                // Keep rendering deterministic if that invariant ever drifts.
                assertionFailure("No formatted head-center for note \(id)")
                Logger.warning("Note head \(id) missing from formatter output; using column anchor")
                centerX = Self.columnX(
                    measureIndex: note.position.measureIndex,
                    localTick: note.position.localTick,
                    columnXByKey: columnXByKey,
                    fallbackMeasure: measure
                )
            }
            return RenderedNoteHead(
                id: id,
                sourceLaneID: note.sourceLaneID,
                sourceChipID: note.sourceChipID,
                noteType: note.noteType,
                drumType: drumType,
                variant: resolved.variant,
                voice: definition.voice,
                stemDirection: definition.defaultStemDirection,
                timeColumn: timeColumn,
                timePosition: Double(note.position.absoluteTick),
                row: measure.row,
                position: CGPoint(
                    x: centerX,
                    y: GameplayLayout.StaffLinePosition.line1.absoluteY(for: measure.row)
                        + notePosition.yOffset
                ),
                staffStep: Self.staffStep(for: notePosition),
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

    /// Column anchor lookup shared by the drift fallbacks: the formatted
    /// logical column X for the tick, else the measure's leading inset.
    static func columnX(
        measureIndex: Int,
        localTick: Int,
        columnXByKey: [MeasureTickKey: CGFloat],
        fallbackMeasure: RenderedMeasure
    ) -> CGFloat {
        if let x = columnXByKey[MeasureTickKey(measureIndex: measureIndex, tick: localTick)] {
            return x
        }
        // Mirrors the formatter's leading inset so a drifted primitive stays
        // inside its measure.
        return fallbackMeasure.xOffset + GameplayLayout.barLineWidth + GameplayLayout.uniformSpacing
    }

    static func staffStep(for position: GameplayLayout.NotePosition) -> Int {
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
