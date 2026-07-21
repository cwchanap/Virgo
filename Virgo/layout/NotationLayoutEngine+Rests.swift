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

    func buildRests(
        rests: [RhythmLayoutRest],
        measures: [RenderedMeasure],
        tabGrid: TabGrid,
        style: NotationLayoutStyle
    ) -> [RenderedRest] {
        let measuresByIndex = Dictionary(uniqueKeysWithValues: measures.map { ($0.measureIndex, $0) })
        let candidates = rests.compactMap { rest -> (RhythmLayoutRest, RenderedMeasure)? in
            guard let measure = measuresByIndex[rest.position.measureIndex],
                  rest.position.localTick >= 0,
                  rest.position.localTick < measure.durationTicks,
                  rest.position.absoluteTick == measure.startTick + rest.position.localTick,
                  rest.durationTicks > 0,
                  rest.position.localTick + rest.durationTicks <= measure.durationTicks else {
                return nil
            }
            return (rest, measure)
        }.sorted {
            if $0.0.position.absoluteTick != $1.0.position.absoluteTick {
                return $0.0.position.absoluteTick < $1.0.position.absoluteTick
            }
            if $0.0.voice != $1.0.voice { return $0.0.voice == .upper }
            return $0.0.durationTicks > $1.0.durationTicks
        }
        var duplicateCounts: [String: Int] = [:]
        return candidates.map { rest, measure in
            let duration = legacyRestDuration(
                rhythm: rest.rhythm,
                fillsMeasure: rest.position.localTick == 0
                    && rest.durationTicks == measure.durationTicks
            )
            let baseID = "rest-m\(rest.position.measureIndex)-v\(rest.voice.rawValue)"
                + "-t\(rest.position.localTick)-n\(rest.durationTicks)"
                + "-d\(duration.rawValue)-x\(rest.visibility.rawValue)"
            let ordinal = duplicateCounts[baseID, default: 0]
            duplicateCounts[baseID] = ordinal + 1
            let localTick = duration == .fullMeasure
                ? measure.durationTicks / 2
                : rest.position.localTick
            let voiceOffset = rest.voice == .upper
                ? style.upperVoiceRestOffset
                : style.lowerVoiceRestOffset
            return RenderedRest(
                id: "\(baseID)-duplicate-\(ordinal)",
                timeColumn: NotationTimeColumn(
                    measureIndex: rest.position.measureIndex,
                    tickWithinMeasure: rest.position.localTick,
                    absoluteLayoutTick: rest.position.absoluteTick
                ),
                measureIndex: rest.position.measureIndex,
                row: measure.row,
                voice: rest.voice,
                durationTicks: rest.durationTicks,
                duration: duration,
                visibility: rest.visibility,
                position: CGPoint(
                    x: tabGrid.xPosition(in: measure, localTick: localTick),
                    y: GameplayLayout.StaffLinePosition.line3.absoluteY(for: measure.row) + voiceOffset
                ),
                rhythmPosition: rest.position,
                rhythm: rest.rhythm,
                tupletID: rest.tupletID
            )
        }
    }
}

private func legacyRestDuration(
    rhythm: NotationRhythm,
    fillsMeasure: Bool
) -> NotationRestDuration {
    if fillsMeasure { return .fullMeasure }
    switch rhythm.baseInterval {
    case .full: return .fullMeasure
    case .half: return .half
    case .quarter: return .quarter
    case .eighth: return .eighth
    case .sixteenth: return .sixteenth
    case .thirtysecond: return .thirtySecond
    case .sixtyfourth: return .sixtyFourth
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
        ),
        rhythmPosition: RhythmEventPosition(
            measureIndex: timeColumn.measureIndex,
            localTick: timeColumn.tickWithinMeasure,
            absoluteTick: timeColumn.absoluteLayoutTick
        ),
        tupletID: nil
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
