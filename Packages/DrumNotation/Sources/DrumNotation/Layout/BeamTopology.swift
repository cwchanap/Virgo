// HPA-166 Task 2 — package ownership of Virgo's proven beam topology.
// This is a mechanical port of `Virgo/layout/NotationBeamTopology.swift`:
// same primary runs, exact-duration adjacency, beam levels, hook-neighbor
// rule, and boundaries by measure, voice, stem direction and beat-group
// ordinal.
//
// The pre-format row is intentionally absent from every grouping key — the
// formatter packs whole measures onto rows, so a group always maps to
// exactly one row (asserted post-format by the package test suite).
// Everything here is internal: the engraving result and tests consume the
// topology; no public API is added. Stem groups and the visible-flag plan
// that rides this topology live in `StemTopology.swift`.

// MARK: - Beam topology (mechanical port)

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

/// The package timeline event: measure-local tick + absolute tick replace
/// the app's `NotationTimeColumn`; no row exists pre-format.
struct BeamTimelineEvent: Hashable {
    let measureIndex: Int
    let localTick: Int
    let absoluteTick: Int
    let voice: NotationVoiceRole
    let stemDirection: NotationStemDirection
    let noteIDs: [Int]
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
    let voice: NotationVoiceRole
    let stemDirection: NotationStemDirection
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

/// Beat-scoped beam topology, ported verbatim minus the pre-format row and
/// the legacy simple-meter compatibility overload (the package only ever
/// sees resolved measure beat groups).
struct NotationBeamTopologyBuilder {
    private struct GroupKey: Hashable {
        let measureIndex: Int
        let voice: NotationVoiceRole
        let direction: NotationStemDirection
        let beatGroupIndex: Int
        let beatGroupStartTick: Int
        let beatGroupDurationTicks: Int
    }

    /// Builds topology from the canonical measure-local beat groups.
    func build(events: [BeamTimelineEvent], measures: [ResolvedMeasure]) -> BeamTopologyResult {
        guard !measures.isEmpty,
              Set(measures.map(\.index)).count == measures.count,
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
    /// Events whose `localTick` falls outside `[0, durationTicks)` are
    /// intentionally skipped: such ticks arise only from malformed input
    /// beat-scoped topology does not model. Validated input never produces
    /// them; the silent skip mirrors the app builder.
    private func groupEventsByResolvedGroup(
        events: [BeamTimelineEvent],
        measures: [ResolvedMeasure]
    ) -> [GroupKey: [Int]] {
        let measuresByIndex = Dictionary(uniqueKeysWithValues: measures.map { ($0.index, $0) })
        var grouped: [GroupKey: [Int]] = [:]
        for (index, event) in events.enumerated() {
            let tick = event.localTick
            guard let measure = measuresByIndex[event.measureIndex],
                  tick >= 0, tick < measure.durationTicks,
                  let beatGroupOrdinal = measure.beatGroups.firstIndex(where: {
                      tick >= $0.startTick && tick < $0.startTick + $0.durationTicks
                  }) else { continue }
            let beatGroup = measure.beatGroups[beatGroupOrdinal]
            let key = GroupKey(
                measureIndex: event.measureIndex,
                voice: event.voice,
                direction: event.stemDirection,
                beatGroupIndex: beatGroupOrdinal,
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
        // Tuplet members satisfy the same strict equality — their exact
        // resolved durations tile the beat group — so no tuplet-specific
        // handling is needed.
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
               events[index].absoluteTick
                == events[previous].absoluteTick + previousDuration {
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
        let firstTick = events[run[0]].absoluteTick
        let lastTick = events[run[run.count - 1]].absoluteTick
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
                    .absoluteTick
                    > events[ownerIndex].absoluteTick
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

        let ownerTick = events[run[ownerPosition]].localTick
        let previousTick = events[run[ownerPosition - 1]].localTick
        let nextTick = events[run[ownerPosition + 1]].localTick
        let previousDistance = ownerTick - previousTick
        let nextDistance = nextTick - ownerTick
        if previousDistance != nextDistance {
            return previousDistance < nextDistance ? ownerPosition - 1 : ownerPosition + 1
        }
        let beatMidpoint = key.beatGroupStartTick + key.beatGroupDurationTicks / 2
        return ownerTick < beatMidpoint ? ownerPosition + 1 : ownerPosition - 1
    }

    private func validMeasure(_ measure: ResolvedMeasure) -> Bool {
        guard measure.durationTicks > 0, !measure.beatGroups.isEmpty else { return false }
        var endTick = 0
        for group in measure.beatGroups {
            let groupEnd = group.startTick + group.durationTicks
            guard group.durationTicks > 0,
                  group.startTick == endTick,
                  groupEnd <= measure.durationTicks else { return false }
            endTick = groupEnd
        }
        return endTick == measure.durationTicks
    }

    private func groupKeyComesBefore(_ lhs: GroupKey, _ rhs: GroupKey) -> Bool {
        if lhs.measureIndex != rhs.measureIndex {
            return lhs.measureIndex < rhs.measureIndex
        }
        // App parity: `NotationVoice` is String-raw there, so "lower" sorts
        // before "upper" — replicate it with the Int-raw package role.
        if lhs.voice != rhs.voice {
            return lhs.voice == .lower
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
        if lhs.absoluteTick != rhs.absoluteTick {
            return lhs.absoluteTick < rhs.absoluteTick
        }
        return lhs.noteIDs.lexicographicallyPrecedes(rhs.noteIDs)
    }
}
