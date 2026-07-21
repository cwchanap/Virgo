enum BeamTimelineEventRole: Hashable {
    case beamable(requiredBeamLevels: Int, durationTicks: Int?)
    case boundary

    var requiredBeamLevels: Int {
        if case let .beamable(levels, _) = self { return levels }
        return 0
    }

    var durationTicks: Int? {
        if case let .beamable(_, durationTicks) = self { return durationTicks }
        return nil
    }
}

struct BeamTimelineEvent: Hashable {
    let timeColumn: NotationTimeColumn
    let row: Int
    let voice: NotationVoice
    let stemDirection: StemDirection
    let noteHeadIDs: [UInt64]
    let role: BeamTimelineEventRole
}

enum BeamSegmentKind: String, Hashable {
    case full
    case forwardHook
    case backwardHook
}

struct BeamTopologySegment: Hashable {
    let level: Int
    let kind: BeamSegmentKind
    let eventIndices: [Int]
    let hookNeighborIndex: Int?
}

struct BeamPrimaryGroupID: Hashable {
    let measureIndex: Int
    let row: Int
    let voice: NotationVoice
    let stemDirection: StemDirection
    let beatGroupIndex: Int
    let firstAbsoluteTick: Int
    let lastAbsoluteTick: Int
}

struct BeamPrimaryGroup: Hashable {
    let id: BeamPrimaryGroupID
    let eventIndices: [Int]
    let segments: [BeamTopologySegment]
}

struct BeamTopologyResult: Equatable {
    let primaryGroups: [BeamPrimaryGroup]
    let coveredLevelsByEventIndex: [Int: Set<Int>]

    static let empty = BeamTopologyResult(
        primaryGroups: [],
        coveredLevelsByEventIndex: [:]
    )
}

struct NotationBeamTopologyBuilder {
    private struct GroupKey: Hashable {
        let measureIndex: Int
        let row: Int
        let voice: NotationVoice
        let direction: StemDirection
        let beatGroupIndex: Int
        let beatGroupStartTick: Int
        let beatGroupDurationTicks: Int
    }

    /// Builds beat-scoped beam topology from timeline events.
    ///
    /// Events are grouped by measure, row, voice, stem direction, and beat
    /// group index. Consecutive beamable events within a beat group form
    /// primary runs, which are then segmented into full beams and hooks.
    /// Compound meters (X/8) are intentionally unsupported and return
    /// ``BeamTopologyResult/empty``.
    func build(
        events: [BeamTimelineEvent],
        ticksPerMeasure: Int,
        timeSignature: TimeSignature
    ) -> BeamTopologyResult {
        // Simple X/4 meters (4/4, 3/4, 2/4, 5/4) share quarter-note beats, so
        // beat scoping generalizes trivially: one beat = ticksPerMeasure /
        // beatsPerMeasure. Compound meters (6/8, 12/8, …) use dotted-quarter
        // beats and a different grouping; they are intentionally deferred here
        // and fall back to flags-only rendering until a compound beat grouper
        // is added.
        guard timeSignature.noteValue == 4,
              ticksPerMeasure > 0,
              ticksPerMeasure.isMultiple(of: timeSignature.beatsPerMeasure) else {
            return .empty
        }

        let beatTicks = ticksPerMeasure / timeSignature.beatsPerMeasure
        let measure = RhythmMeasure(
            measureIndex: 0,
            startTick: 0,
            durationTicks: ticksPerMeasure,
            timeSignature: timeSignature,
            beatGroups: (0..<timeSignature.beatsPerMeasure).map {
                RhythmBeatGroup(
                    groupIndex: $0,
                    startTick: $0 * beatTicks,
                    durationTicks: beatTicks,
                    isResidual: false
                )
            },
            engravingSupport: .supported
        )
        let measureIndices = Set(events.map(\.timeColumn.measureIndex))
        let measures = measureIndices.map { index in
            RhythmMeasure(
                measureIndex: index,
                startTick: 0,
                durationTicks: measure.durationTicks,
                timeSignature: measure.timeSignature,
                beatGroups: measure.beatGroups,
                engravingSupport: measure.engravingSupport
            )
        }
        return build(events: events, measures: measures.isEmpty ? [measure] : measures)
    }

    /// Builds topology from the canonical measure-local beat groups.
    func build(events: [BeamTimelineEvent], measures: [RhythmMeasure]) -> BeamTopologyResult {
        guard !measures.isEmpty,
              Set(measures.map(\.measureIndex)).count == measures.count,
              measures.allSatisfy(validMeasure) else {
            return .empty
        }
        let grouped = groupEventsByResolvedGroup(events: events, measures: measures)
        let (primaryGroups, coverage) = buildPrimaryGroups(grouped: grouped, events: events)

        return BeamTopologyResult(
            primaryGroups: primaryGroups,
            coveredLevelsByEventIndex: coverage
        )
    }

    /// Groups beamable event indices by their containing beat.
    ///
    /// Events whose `tickWithinMeasure` falls outside `[0, ticksPerMeasure)` are
    /// intentionally skipped: such ticks arise only from malformed input or
    /// partial-measure/pickup columns that beat-scoped topology does not model.
    /// Dropping them keeps the grouper total without manufacturing a beat index
    /// from an out-of-range tick. The skip is silent by design — callers that
    /// need to detect malformed input should validate upstream.
    private func groupEventsByResolvedGroup(
        events: [BeamTimelineEvent],
        measures: [RhythmMeasure]
    ) -> [GroupKey: [Int]] {
        let measuresByIndex = Dictionary(uniqueKeysWithValues: measures.map { ($0.measureIndex, $0) })
        var grouped: [GroupKey: [Int]] = [:]
        for (index, event) in events.enumerated() {
            let tick = event.timeColumn.tickWithinMeasure
            guard let measure = measuresByIndex[event.timeColumn.measureIndex],
                  case .supported = measure.engravingSupport,
                  tick >= 0, tick < measure.durationTicks,
                  let beatGroup = measure.beatGroups.first(where: {
                    tick >= $0.startTick && tick < $0.endTick
                  }) else { continue }
            let key = GroupKey(
                measureIndex: event.timeColumn.measureIndex,
                row: event.row,
                voice: event.voice,
                direction: event.stemDirection,
                beatGroupIndex: beatGroup.groupIndex,
                beatGroupStartTick: beatGroup.startTick,
                beatGroupDurationTicks: beatGroup.durationTicks
            )
            grouped[key, default: []].append(index)
        }
        return grouped
    }

    private func buildPrimaryGroups(
        grouped: [GroupKey: [Int]],
        events: [BeamTimelineEvent]
    ) -> (primaryGroups: [BeamPrimaryGroup], coverage: [Int: Set<Int>]) {
        let orderedKeys = grouped.keys.sorted(by: groupKeyComesBefore)
        var primaryGroups: [BeamPrimaryGroup] = []
        var coverage: [Int: Set<Int>] = [:]

        for key in orderedKeys {
            let indices = (grouped[key] ?? []).sorted {
                eventComesBefore(events[$0], events[$1])
            }
            for run in primaryRuns(indices: indices, events: events) {
                let group = makePrimaryGroup(
                    key: key,
                    run: run,
                    events: events
                )
                primaryGroups.append(group)
                for segment in group.segments {
                    let coveredIndices = segment.kind == .full
                        ? segment.eventIndices
                        : Array(segment.eventIndices.prefix(1))
                    for index in coveredIndices {
                        coverage[index, default: []].insert(segment.level)
                    }
                }
            }
        }

        return (primaryGroups, coverage)
    }

    private func primaryRuns(
        indices: [Int],
        events: [BeamTimelineEvent]
    ) -> [[Int]] {
        // Adjacency is exact tick-to-tick based on each event's duration.
        // Tuplets (which subdivide a beat into non-power-of-two parts) are not
        // supported: their compressed durations would not satisfy the strict
        // equality below and would break runs prematurely.
        var runs: [[Int]] = []
        var current: [Int] = []

        func flush() {
            if current.count >= 2 { runs.append(current) }
            current = []
        }

        for index in indices {
            guard case let .beamable(levels, duration?) = events[index].role,
                  levels > 0,
                  duration > 0 else {
                flush()
                continue
            }
            if let previous = current.last,
               let previousDuration = events[previous].role.durationTicks,
               events[index].timeColumn.absoluteLayoutTick
                == events[previous].timeColumn.absoluteLayoutTick + previousDuration {
                current.append(index)
            } else {
                flush()
                current = [index]
            }
        }
        flush()
        return runs
    }

    private func makePrimaryGroup(
        key: GroupKey,
        run: [Int],
        events: [BeamTimelineEvent]
    ) -> BeamPrimaryGroup {
        let firstTick = events[run[0]].timeColumn.absoluteLayoutTick
        let lastTick = events[run[run.count - 1]].timeColumn.absoluteLayoutTick
        var segments = [BeamTopologySegment(
            level: 0,
            kind: .full,
            eventIndices: run,
            hookNeighborIndex: nil
        )]
        let maximumLevel = run.map { events[$0].role.requiredBeamLevels }.max() ?? 1

        for level in 1..<maximumLevel {
            segments.append(contentsOf: secondarySegments(
                level: level,
                run: run,
                events: events,
                key: key
            ))
        }

        return BeamPrimaryGroup(
            id: BeamPrimaryGroupID(
                measureIndex: key.measureIndex,
                row: key.row,
                voice: key.voice,
                stemDirection: key.direction,
                beatGroupIndex: key.beatGroupIndex,
                firstAbsoluteTick: firstTick,
                lastAbsoluteTick: lastTick
            ),
            eventIndices: run,
            segments: segments
        )
    }

    private func secondarySegments(
        level: Int,
        run: [Int],
        events: [BeamTimelineEvent],
        key: GroupKey
    ) -> [BeamTopologySegment] {
        var eligiblePositions: [Int] = []
        var segments: [BeamTopologySegment] = []

        func flushEligible() {
            guard !eligiblePositions.isEmpty else { return }
            let eligibleIndices = eligiblePositions.map { run[$0] }
            if eligibleIndices.count >= 2 {
                segments.append(BeamTopologySegment(
                    level: level,
                    kind: .full,
                    eventIndices: eligibleIndices,
                    hookNeighborIndex: nil
                ))
            } else if let position = eligiblePositions.first {
                let neighborPosition = hookNeighborPosition(
                    ownerPosition: position,
                    run: run,
                    events: events,
                    key: key
                )
                let ownerIndex = run[position]
                let neighborIndex = run[neighborPosition]
                let kind: BeamSegmentKind = events[neighborIndex]
                    .timeColumn.absoluteLayoutTick
                    > events[ownerIndex].timeColumn.absoluteLayoutTick
                    ? .forwardHook : .backwardHook
                segments.append(BeamTopologySegment(
                    level: level,
                    kind: kind,
                    eventIndices: [ownerIndex],
                    hookNeighborIndex: neighborIndex
                ))
            }
            eligiblePositions = []
        }

        for position in run.indices {
            if events[run[position]].role.requiredBeamLevels > level {
                eligiblePositions.append(position)
            } else {
                flushEligible()
            }
        }
        flushEligible()
        return segments
    }

    private func hookNeighborPosition(
        ownerPosition: Int,
        run: [Int],
        events: [BeamTimelineEvent],
        key: GroupKey
    ) -> Int {
        precondition(run.count >= 2, "hookNeighborPosition requires a primary run of at least 2 events")
        if ownerPosition == run.startIndex { return ownerPosition + 1 }
        if ownerPosition == run.index(before: run.endIndex) { return ownerPosition - 1 }

        let ownerTick = events[run[ownerPosition]].timeColumn.tickWithinMeasure
        let previousTick = events[run[ownerPosition - 1]].timeColumn.tickWithinMeasure
        let nextTick = events[run[ownerPosition + 1]].timeColumn.tickWithinMeasure
        let previousDistance = ownerTick - previousTick
        let nextDistance = nextTick - ownerTick
        if previousDistance != nextDistance {
            return previousDistance < nextDistance ? ownerPosition - 1 : ownerPosition + 1
        }
        let beatMidpoint = key.beatGroupStartTick + key.beatGroupDurationTicks / 2
        return ownerTick < beatMidpoint ? ownerPosition + 1 : ownerPosition - 1
    }

    private func validMeasure(_ measure: RhythmMeasure) -> Bool {
        guard measure.durationTicks > 0, !measure.beatGroups.isEmpty else { return false }
        var endTick = 0
        for group in measure.beatGroups {
            guard group.durationTicks > 0,
                  group.startTick == endTick,
                  group.endTick <= measure.durationTicks else { return false }
            endTick = group.endTick
        }
        return endTick == measure.durationTicks
    }

    private func groupKeyComesBefore(_ lhs: GroupKey, _ rhs: GroupKey) -> Bool {
        if lhs.measureIndex != rhs.measureIndex {
            return lhs.measureIndex < rhs.measureIndex
        }
        if lhs.row != rhs.row { return lhs.row < rhs.row }
        if lhs.voice.rawValue != rhs.voice.rawValue {
            return lhs.voice.rawValue < rhs.voice.rawValue
        }
        if lhs.direction.rawValue != rhs.direction.rawValue {
            return lhs.direction.rawValue < rhs.direction.rawValue
        }
        return lhs.beatGroupIndex < rhs.beatGroupIndex
    }

    private func eventComesBefore(
        _ lhs: BeamTimelineEvent,
        _ rhs: BeamTimelineEvent
    ) -> Bool {
        if lhs.timeColumn.absoluteLayoutTick != rhs.timeColumn.absoluteLayoutTick {
            return lhs.timeColumn.absoluteLayoutTick < rhs.timeColumn.absoluteLayoutTick
        }
        return lhs.noteHeadIDs.lexicographicallyPrecedes(rhs.noteHeadIDs)
    }
}
