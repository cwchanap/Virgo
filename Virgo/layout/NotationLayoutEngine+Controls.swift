import CoreGraphics

extension NotationLayoutEngine {
    /// Bound per-measure arrays, synthesized rests, and row geometry with the
    /// same chart-wide limit used by canonical rhythm validation.
    static let maximumRenderableMeasureCount = RhythmLimits.maximumMeasureCount

    struct ControlTimingResolution {
        let controls: [SemanticallyTimedControl]
        let invalidReasons: Set<String>
    }

    enum ControlProjection {
        case normalized(sourceTick: Int, sourceTicksPerMeasure: Int)
        case manual(offset: Double)
    }

    struct SemanticallyTimedControl {
        let event: NotationControlEvent
        let measureIndex: Int
        let projection: ControlProjection
    }

    struct StopNoteBuildResult {
        let stopNotes: [RenderedStopNote]
        let inexactSourceResolutions: Set<Int>
        let inexactManualOffsets: Set<Double>
        let unresolvedTargetLaneIDs: Set<String>
    }

    func totalMeasureCount(
        notes: [Note],
        controls: [SemanticallyTimedControl],
        minimumMeasureCount: Int
    ) -> Int {
        let maxNoteMeasureIndex = notes.map { note in
            MeasureUtils.measureIndex(from: MeasureUtils.timePosition(
                measureNumber: note.measureNumber, measureOffset: note.measureOffset
            ))
        }.max() ?? 0
        let maxControlMeasureIndex = controls.map(\.measureIndex).max() ?? 0
        let maximumMeasureIndex = max(maxNoteMeasureIndex, maxControlMeasureIndex)
        let (measureCount, overflow) = maximumMeasureIndex.addingReportingOverflow(1)
        let contentMeasureCount = overflow ? Self.maximumRenderableMeasureCount : measureCount
        return min(
            max(minimumMeasureCount, contentMeasureCount, 1),
            Self.maximumRenderableMeasureCount
        )
    }

    func resolveControlTimings(_ events: [NotationControlEvent]) -> ControlTimingResolution {
        var controls: [SemanticallyTimedControl] = []
        var invalidReasons: Set<String> = []
        for event in events {
            switch semanticTiming(for: event) {
            case let .success(control):
                controls.append(control)
            case let .failure(reason):
                invalidReasons.insert(reason.description)
            }
        }
        return ControlTimingResolution(controls: controls, invalidReasons: invalidReasons)
    }

    func buildStopNotes(
        controls: [SemanticallyTimedControl],
        measures: [RenderedMeasure],
        tabGrid: TabGrid,
        input: NotationLayoutInput
    ) -> StopNoteBuildResult {
        let measuresByIndex = Dictionary(uniqueKeysWithValues: measures.map { ($0.measureIndex, $0) })
        var candidates: [StopNoteCandidate] = []
        var inexactSourceResolutions: Set<Int> = []
        var inexactManualOffsets: Set<Double> = []
        var unresolvedTargetLaneIDs: Set<String> = []

        for control in controls {
            let target: ResolvedDrumNotationTarget?
            if let targetLaneID = control.event.targetLaneID,
               let resolvedTarget = DrumNotationCatalog.resolveTarget(laneID: targetLaneID) {
                target = resolvedTarget
            } else {
                unresolvedTargetLaneIDs.insert(control.event.targetLaneID?.uppercased() ?? "<missing>")
                target = nil
            }
            // Project the tick only after the target is resolved so that
            // unresolved-target controls are not also recorded as projection
            // failures (a separate, conflated diagnostic).
            guard let target else { continue }
            guard let targetTick = projectedTick(
                for: control,
                targetTicksPerMeasure: tabGrid.ticksPerMeasure,
                inexactSourceResolutions: &inexactSourceResolutions,
                inexactManualOffsets: &inexactManualOffsets
            ), let measure = measuresByIndex[control.measureIndex] else { continue }
            candidates.append(stopNoteCandidate(
                control: control,
                target: target,
                context: StopNotePlacementContext(
                    targetTick: targetTick,
                    measure: measure,
                    tabGrid: tabGrid,
                    input: input
                )
            ))
        }

        return StopNoteBuildResult(
            stopNotes: materializeStopNotes(candidates.sorted(by: stopCandidateComesBefore)),
            inexactSourceResolutions: inexactSourceResolutions,
            inexactManualOffsets: inexactManualOffsets,
            unresolvedTargetLaneIDs: unresolvedTargetLaneIDs
        )
    }

    func buildStopNotes(
        controls: [RhythmLayoutControl],
        measures: [RenderedMeasure],
        tabGrid: TabGrid,
        input: NotationLayoutInput
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
            let targetPosition = input.notePositionOverrides[target.definition.gameplayInstrument]
                ?? target.definition.defaultPosition
            let targetStaffStep = staffStep(for: targetPosition)
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
                    x: tabGrid.xPosition(in: measure, localTick: position.localTick),
                    y: GameplayLayout.StaffLinePosition.line1.absoluteY(for: measure.row)
                        + CGFloat(targetStaffStep) * GameplayLayout.staffLineSpacing / 2
                        - input.style.stopMarkVerticalOffset
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

    func logControlDiagnostics(
        timing: ControlTimingResolution,
        rendering: StopNoteBuildResult
    ) {
        if !timing.invalidReasons.isEmpty {
            Logger.warning(
                "Notation controls skipped for invalid timing: "
                    + timing.invalidReasons.sorted().joined(separator: ", ")
            )
        }
        if !rendering.inexactSourceResolutions.isEmpty {
            Logger.warning(
                "Notation controls skipped for inexact target-grid projection from resolutions: "
                    + rendering.inexactSourceResolutions.sorted().map(String.init).joined(separator: ", ")
            )
        }
        if !rendering.inexactManualOffsets.isEmpty {
            Logger.warning(
                "Notation controls skipped for off-grid manual measure offsets: "
                    + rendering.inexactManualOffsets.sorted().map { String($0) }.joined(separator: ", ")
            )
        }
        if !rendering.unresolvedTargetLaneIDs.isEmpty {
            Logger.warning(
                "Notation controls skipped for unresolved target lanes: "
                    + rendering.unresolvedTargetLaneIDs.sorted().joined(separator: ", ")
            )
        }
    }
}

private enum ControlTimingError: Error {
    case invalid(String)

    var description: String {
        switch self {
        case let .invalid(reason): reason
        }
    }
}

private struct StopNoteCandidate {
    let control: NotationLayoutEngine.SemanticallyTimedControl
    let target: ResolvedDrumNotationTarget
    let timeColumn: NotationTimeColumn
    let row: Int
    let position: CGPoint

    var baseID: String {
        let event = control.event
        return "control-m\(timeColumn.measureIndex)-t\(timeColumn.tickWithinMeasure)"
            + "-k\(event.kind.rawValue)-target\(target.laneID)"
            + "-source=\(idComponent(event.sourceLaneID))-id=\(idComponent(event.sourceNoteID))"
            + "-gp=\(idComponent(event.sourceGridPosition))-gs=\(idComponent(event.sourceGridSize))"
    }
}

private struct StopNotePlacementContext {
    let targetTick: Int
    let measure: RenderedMeasure
    let tabGrid: TabGrid
    let input: NotationLayoutInput
}

private extension NotationLayoutEngine {
    func semanticTiming(
        for event: NotationControlEvent
    ) -> Result<SemanticallyTimedControl, ControlTimingError> {
        let normalizedFields: [Int?] = [
            event.normalizedMeasureIndex,
            event.normalizedAbsoluteTick,
            event.normalizedTickWithinMeasure,
            event.normalizedTicksPerMeasure
        ]
        let presentFieldCount = normalizedFields.compactMap { $0 }.count
        if presentFieldCount == normalizedFields.count {
            return normalizedSemanticTiming(for: event)
        }
        if presentFieldCount > 0 {
            return .failure(.invalid("partial normalized tuple"))
        }
        return manualSemanticTiming(for: event)
    }

    func normalizedSemanticTiming(
        for event: NotationControlEvent
    ) -> Result<SemanticallyTimedControl, ControlTimingError> {
        guard let measureIndex = event.normalizedMeasureIndex,
              let absoluteTick = event.normalizedAbsoluteTick,
              let tick = event.normalizedTickWithinMeasure,
              let resolution = event.normalizedTicksPerMeasure else {
            return .failure(.invalid("partial normalized tuple"))
        }
        guard measureIndex >= 0 else { return .failure(.invalid("negative normalized measure index")) }
        guard measureIndex < Self.maximumRenderableMeasureCount else {
            return .failure(.invalid(
                "control measure exceeds renderable limit (\(Self.maximumRenderableMeasureCount))"
            ))
        }
        guard absoluteTick >= 0 else { return .failure(.invalid("negative normalized absolute tick")) }
        guard tick >= 0 else { return .failure(.invalid("negative normalized measure tick")) }
        guard resolution > 0 else { return .failure(.invalid("nonpositive normalized source resolution")) }
        guard tick <= resolution else { return .failure(.invalid("normalized measure tick exceeds resolution")) }
        let (measureStart, overflow) = measureIndex.multipliedReportingOverflow(by: resolution)
        let (expectedAbsoluteTick, additionOverflow) = measureStart.addingReportingOverflow(tick)
        guard !overflow, !additionOverflow, absoluteTick == expectedAbsoluteTick else {
            return .failure(.invalid("inconsistent normalized absolute tick"))
        }
        return .success(SemanticallyTimedControl(
            event: event,
            measureIndex: measureIndex,
            projection: .normalized(sourceTick: tick, sourceTicksPerMeasure: resolution)
        ))
    }

    func manualSemanticTiming(
        for event: NotationControlEvent
    ) -> Result<SemanticallyTimedControl, ControlTimingError> {
        guard event.originKind == .manual else {
            return .failure(.invalid("DTX control missing complete normalized timing"))
        }
        guard event.measureNumber >= 1 else { return .failure(.invalid("manual measure number below one")) }
        guard event.measureOffset.isFinite else { return .failure(.invalid("non-finite manual measure offset")) }
        guard (0...1).contains(event.measureOffset) else {
            return .failure(.invalid("manual measure offset outside zero through one"))
        }
        let reachesNextMeasure = event.measureOffset == 1
        let measureIndex = reachesNextMeasure ? event.measureNumber : event.measureNumber - 1
        guard measureIndex < Self.maximumRenderableMeasureCount else {
            return .failure(.invalid(
                "control measure exceeds renderable limit (\(Self.maximumRenderableMeasureCount))"
            ))
        }
        return .success(SemanticallyTimedControl(
            event: event,
            measureIndex: measureIndex,
            projection: .manual(offset: reachesNextMeasure ? 0 : event.measureOffset)
        ))
    }

    func projectedTick(
        for control: SemanticallyTimedControl,
        targetTicksPerMeasure: Int,
        inexactSourceResolutions: inout Set<Int>,
        inexactManualOffsets: inout Set<Double>
    ) -> Int? {
        switch control.projection {
        case let .normalized(sourceTick, sourceTicksPerMeasure):
            guard let tick = Self.exactRescaledTick(
                sourceTick: sourceTick,
                sourceTicksPerMeasure: sourceTicksPerMeasure,
                targetTicksPerMeasure: targetTicksPerMeasure
            ) else {
                inexactSourceResolutions.insert(sourceTicksPerMeasure)
                return nil
            }
            return tick
        case let .manual(offset):
            let scaled = offset * Double(targetTicksPerMeasure)
            guard scaled.isFinite, scaled.rounded() == scaled else {
                inexactManualOffsets.insert(offset)
                return nil
            }
            return Int(scaled)
        }
    }

    func stopNoteCandidate(
        control: SemanticallyTimedControl,
        target: ResolvedDrumNotationTarget,
        context: StopNotePlacementContext
    ) -> StopNoteCandidate {
        let instrument = target.definition.gameplayInstrument
        let targetPosition = context.input.notePositionOverrides[instrument] ?? target.definition.defaultPosition
        let targetStaffStep = staffStep(for: targetPosition)
        let timeColumn = NotationTimeColumn(
            measureIndex: control.measureIndex,
            tickWithinMeasure: context.targetTick,
            absoluteLayoutTick: control.measureIndex * context.tabGrid.ticksPerMeasure + context.targetTick
        )
        return StopNoteCandidate(
            control: control,
            target: target,
            timeColumn: timeColumn,
            row: context.measure.row,
            position: CGPoint(
                x: context.tabGrid.xPosition(in: context.measure, tickIndex: context.targetTick),
                y: GameplayLayout.StaffLinePosition.line1.absoluteY(for: context.measure.row)
                    + CGFloat(targetStaffStep) * GameplayLayout.staffLineSpacing / 2
                    - context.input.style.stopMarkVerticalOffset
            )
        )
    }
}

private func stopCandidateComesBefore(_ lhs: StopNoteCandidate, _ rhs: StopNoteCandidate) -> Bool {
    if lhs.timeColumn.measureIndex != rhs.timeColumn.measureIndex {
        return lhs.timeColumn.measureIndex < rhs.timeColumn.measureIndex
    }
    if lhs.timeColumn.tickWithinMeasure != rhs.timeColumn.tickWithinMeasure {
        return lhs.timeColumn.tickWithinMeasure < rhs.timeColumn.tickWithinMeasure
    }
    let left = lhs.control.event
    let right = rhs.control.event
    if left.kind.rawValue != right.kind.rawValue { return left.kind.rawValue < right.kind.rawValue }
    if lhs.target.laneID != rhs.target.laneID { return lhs.target.laneID < rhs.target.laneID }
    if left.sourceLaneID != right.sourceLaneID {
        return optionalStringComesBefore(left.sourceLaneID, right.sourceLaneID)
    }
    if left.sourceNoteID != right.sourceNoteID {
        return optionalStringComesBefore(left.sourceNoteID, right.sourceNoteID)
    }
    if left.sourceGridPosition != right.sourceGridPosition {
        return optionalIntComesBefore(left.sourceGridPosition, right.sourceGridPosition)
    }
    return optionalIntComesBefore(left.sourceGridSize, right.sourceGridSize)
}

private func materializeStopNotes(_ candidates: [StopNoteCandidate]) -> [RenderedStopNote] {
    var duplicateCounts: [String: Int] = [:]
    return candidates.map { candidate in
        let duplicateOrdinal = duplicateCounts[candidate.baseID, default: 0]
        duplicateCounts[candidate.baseID] = duplicateOrdinal + 1
        let event = candidate.control.event
        return RenderedStopNote(
            id: "\(candidate.baseID)-duplicate-\(duplicateOrdinal)",
            kind: event.kind,
            sourceLaneID: event.sourceLaneID,
            sourceNoteID: event.sourceNoteID,
            targetLaneID: candidate.target.laneID,
            targetDisplayName: candidate.target.displayName,
            timeColumn: candidate.timeColumn,
            row: candidate.row,
            position: candidate.position,
            eventID: nil,
            rhythmPosition: RhythmEventPosition(
                measureIndex: candidate.timeColumn.measureIndex,
                localTick: candidate.timeColumn.tickWithinMeasure,
                absoluteTick: candidate.timeColumn.absoluteLayoutTick
            )
        )
    }
}

private func optionalStringComesBefore(_ lhs: String?, _ rhs: String?) -> Bool {
    switch (lhs, rhs) {
    case (nil, .some): true
    case (.some, nil): false
    case let (.some(left), .some(right)): left < right
    case (nil, nil): false
    }
}

private func optionalIntComesBefore(_ lhs: Int?, _ rhs: Int?) -> Bool {
    switch (lhs, rhs) {
    case (nil, .some): true
    case (.some, nil): false
    case let (.some(left), .some(right)): left < right
    case (nil, nil): false
    }
}

private func idComponent(_ value: String?) -> String {
    guard let value else { return "n" }
    return "s\(value.utf8.count):\(value)"
}

private func idComponent(_ value: Int?) -> String {
    value.map { "i\($0)" } ?? "n"
}
