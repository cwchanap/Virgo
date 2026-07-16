import CoreGraphics

extension NotationLayoutEngine {
    func buildRestTimelineNotes(
        noteHeads: [RenderedNoteHead],
        tabGrid: TabGrid,
        timeSignature: TimeSignature,
        topologyBuilder: NotationRestTopologyBuilder
    ) -> [RestTimelineNote] {
        noteHeads.map { head in
            RestTimelineNote(
                timeColumn: head.timeColumn,
                voice: head.voice,
                durationTicks: topologyBuilder.noteDurationTicks(
                    for: head.interval,
                    ticksPerMeasure: tabGrid.ticksPerMeasure,
                    timeSignature: timeSignature
                )
            )
        }
    }

    func buildRests(
        noteHeads: [RenderedNoteHead],
        measures: [RenderedMeasure],
        tabGrid: TabGrid,
        input: NotationLayoutInput
    ) -> [RenderedRest] {
        let topologyBuilder = NotationRestTopologyBuilder()
        let timelineNotes = buildRestTimelineNotes(
            noteHeads: noteHeads,
            tabGrid: tabGrid,
            timeSignature: input.timeSignature,
            topologyBuilder: topologyBuilder
        )
        let events = topologyBuilder.build(
            notes: timelineNotes,
            totalMeasureCount: measures.count,
            ticksPerMeasure: tabGrid.ticksPerMeasure,
            timeSignature: input.timeSignature
        )
        let measuresByIndex = Dictionary(uniqueKeysWithValues: measures.map { ($0.measureIndex, $0) })
        let candidates = events.compactMap { event -> RestLayoutCandidate? in
            guard let measure = measuresByIndex[event.measureIndex] else { return nil }
            return RestLayoutCandidate(event: event, measure: measure)
        }.sorted(by: restCandidateComesBefore)

        var previousKey: RestSemanticKey?
        var duplicateOrdinal = 0
        return candidates.map { candidate in
            let key = RestSemanticKey(event: candidate.event)
            duplicateOrdinal = key == previousKey ? duplicateOrdinal + 1 : 0
            previousKey = key
            return renderedRest(
                candidate: candidate,
                semanticKey: key,
                duplicateOrdinal: duplicateOrdinal,
                tabGrid: tabGrid,
                style: input.style
            )
        }
    }
}

private struct RestLayoutCandidate {
    let event: RestTopologyEvent
    let measure: RenderedMeasure
}

private struct RestSemanticKey: Equatable {
    let measureIndex: Int
    let voice: NotationVoice
    let startTick: Int
    let durationTicks: Int
    let duration: NotationRestDuration
    let visibility: NotationRestVisibility

    init(event: RestTopologyEvent) {
        measureIndex = event.measureIndex
        voice = event.voice
        startTick = event.startTick
        durationTicks = event.durationTicks
        duration = event.duration
        visibility = event.visibility
    }

    var baseID: String {
        "rest-m\(measureIndex)-v\(voice.rawValue)-t\(startTick)-n\(durationTicks)"
            + "-d\(duration.rawValue)-x\(visibility.rawValue)"
    }
}

private func renderedRest(
    candidate: RestLayoutCandidate,
    semanticKey: RestSemanticKey,
    duplicateOrdinal: Int,
    tabGrid: TabGrid,
    style: NotationLayoutStyle
) -> RenderedRest {
    let event = candidate.event
    let measure = candidate.measure
    let x = event.duration == .fullMeasure
        ? measure.xOffset + measure.width / 2
        : tabGrid.xPosition(in: measure, tickIndex: event.startTick)
    let voiceOffset = event.voice == .upper
        ? style.upperVoiceRestOffset
        : style.lowerVoiceRestOffset
    let timeColumn = NotationTimeColumn(
        measureIndex: event.measureIndex,
        tickWithinMeasure: event.startTick,
        absoluteLayoutTick: event.measureIndex * tabGrid.ticksPerMeasure + event.startTick
    )

    return RenderedRest(
        id: "\(semanticKey.baseID)-duplicate-\(duplicateOrdinal)",
        timeColumn: timeColumn,
        measureIndex: event.measureIndex,
        row: measure.row,
        voice: event.voice,
        durationTicks: event.durationTicks,
        duration: event.duration,
        visibility: event.visibility,
        position: CGPoint(
            x: x,
            y: GameplayLayout.StaffLinePosition.line3.absoluteY(for: measure.row) + voiceOffset
        )
    )
}

private func restCandidateComesBefore(_ lhs: RestLayoutCandidate, _ rhs: RestLayoutCandidate) -> Bool {
    let left = RestSemanticKey(event: lhs.event)
    let right = RestSemanticKey(event: rhs.event)
    if left.measureIndex != right.measureIndex { return left.measureIndex < right.measureIndex }
    if left.voice != right.voice { return left.voice == .upper }
    if left.startTick != right.startTick { return left.startTick < right.startTick }
    if left.durationTicks != right.durationTicks { return left.durationTicks < right.durationTicks }
    if left.duration.sortOrder != right.duration.sortOrder {
        return left.duration.sortOrder < right.duration.sortOrder
    }
    return left.visibility.sortOrder < right.visibility.sortOrder
}
