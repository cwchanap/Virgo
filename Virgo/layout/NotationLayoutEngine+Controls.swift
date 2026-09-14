import CoreGraphics

extension NotationLayoutEngine {
    /// Builds stop notes from timeline controls. X anchors at the formatted
    /// logical column of the control's tick (controls carry zero ink).
    func buildStopNotes(
        controls: [RhythmLayoutControl],
        measures: [RenderedMeasure],
        columnXByKey: [MeasureTickKey: CGFloat],
        style: NotationLayoutStyle,
        notePositionOverrides: [DrumType: GameplayLayout.NotePosition]
    ) -> [RenderedStopNote] {
        let measuresByIndex = Dictionary(uniqueKeysWithValues: measures.map { ($0.measureIndex, $0) })
        return controls.compactMap { control -> RenderedStopNote? in
            let position = control.position
            guard let measure = measuresByIndex[position.measureIndex],
                  position.localTick >= 0,
                  position.localTick < measure.durationTicks,
                  position.absoluteTick == measure.startTick + position.localTick,
                  let targetLaneID = control.event.targetLaneID,
                  let target = DrumNotationCatalog.resolveTarget(laneID: targetLaneID) else {
                return nil
            }
            let targetPosition = notePositionOverrides[target.definition.gameplayInstrument]
                ?? target.definition.defaultPosition
            let targetStaffStep = Self.staffStep(for: targetPosition)
            let timeColumn = NotationTimeColumn(
                measureIndex: position.measureIndex,
                tickWithinMeasure: position.localTick,
                absoluteLayoutTick: position.absoluteTick
            )
            return RenderedStopNote(
                id: "control-event-\(control.eventID.rawValue)",
                kind: control.event.kind,
                sourceLaneID: control.event.sourceLaneID,
                sourceNoteID: control.event.sourceNoteID,
                targetLaneID: target.laneID,
                targetDisplayName: target.displayName,
                timeColumn: timeColumn,
                row: measure.row,
                position: CGPoint(
                    x: Self.columnX(
                        measureIndex: position.measureIndex,
                        localTick: position.localTick,
                        columnXByKey: columnXByKey,
                        fallbackMeasure: measure
                    ),
                    y: GameplayLayout.StaffLinePosition.line1.absoluteY(for: measure.row)
                        + CGFloat(targetStaffStep) * GameplayLayout.staffLineSpacing / 2
                        - style.stopMarkVerticalOffset
                ),
                eventID: control.eventID,
                rhythmPosition: position
            )
        }.sorted {
            if $0.timeColumn.absoluteLayoutTick != $1.timeColumn.absoluteLayoutTick {
                return $0.timeColumn.absoluteLayoutTick < $1.timeColumn.absoluteLayoutTick
            }
            return $0.id < $1.id
        }
    }

    func buildArticulations(
        noteHeads: [RenderedNoteHead],
        style: NotationLayoutStyle
    ) -> [RenderedArticulation] {
        noteHeads
            .filter { $0.variant == .openHiHat }
            .map { head in
                RenderedArticulation(
                    id: "openHiHat-head-\(head.id)",
                    kind: .openHiHat,
                    sourceNoteHeadID: head.id,
                    row: head.row,
                    position: CGPoint(
                        x: head.position.x,
                        y: head.position.y - style.articulationVerticalOffset
                    )
                )
            }
            .sorted { $0.sourceNoteHeadID < $1.sourceNoteHeadID }
    }
}
