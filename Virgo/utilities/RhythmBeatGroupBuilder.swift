import Foundation

/// Canonical meter-driven beat grouping shared by timeline construction and
/// notation layout. Keeping this contract in one place prevents expanded
/// layout measures from drifting from the persisted rhythm timeline.
///
/// `count(...)` is the single source of truth for how many beat groups a
/// measure materializes. Both `groups(...)` (which builds the groups) and
/// `RhythmTimelineBuilder.preflightBeatGroupMaterialization(...)` (which
/// bounds the total before allocation) route through it, so the 49,152
/// materialization cap cannot drift from what `groups` actually produces.
enum RhythmBeatGroupBuilder {
    static func groups(
        timeSignature: TimeSignature,
        durationTicks: Int,
        ticksPerWholeNote: Int
    ) -> [RhythmBeatGroup] {
        guard durationTicks > 0, ticksPerWholeNote > 0 else { return [] }
        if timeSignature == .sevenEight {
            return [RhythmBeatGroup(
                groupIndex: 0,
                startTick: 0,
                durationTicks: durationTicks,
                isResidual: false
            )]
        }

        guard let standardDuration = standardBeatGroupDuration(
            for: timeSignature,
            ticksPerWholeNote: ticksPerWholeNote
        ), standardDuration > 0 else { return [] }

        var groups: [RhythmBeatGroup] = []
        var startTick = 0
        while durationTicks - startTick >= standardDuration {
            groups.append(RhythmBeatGroup(
                groupIndex: groups.count,
                startTick: startTick,
                durationTicks: standardDuration,
                isResidual: false
            ))
            startTick += standardDuration
        }
        if startTick < durationTicks {
            groups.append(RhythmBeatGroup(
                groupIndex: groups.count,
                startTick: startTick,
                durationTicks: durationTicks - startTick,
                isResidual: true
            ))
        }
        return groups
    }

    /// Returns the number of beat groups a measure would materialize, or `nil`
    /// when the meter cannot be projected exactly onto `ticksPerWholeNote`
    /// (e.g. compound meter whose whole-note tick count is not a multiple of 8).
    /// `sevenEight` always returns 1 (one conservative ambiguous group).
    static func count(
        timeSignature: TimeSignature,
        durationTicks: Int,
        ticksPerWholeNote: Int
    ) -> Int? {
        guard durationTicks > 0, ticksPerWholeNote > 0 else { return nil }
        if timeSignature == .sevenEight { return 1 }
        guard let standardDuration = standardBeatGroupDuration(
            for: timeSignature,
            ticksPerWholeNote: ticksPerWholeNote
        ), standardDuration > 0 else { return nil }
        let completeCount = durationTicks / standardDuration
        let residualCount = durationTicks.isMultiple(of: standardDuration) ? 0 : 1
        return completeCount + residualCount
    }

    /// Canonical per-meter beat-group duration in ticks. `nil` for `sevenEight`
    /// (which uses one whole-measure group) or when `ticksPerWholeNote` cannot
    /// represent the meter exactly.
    private static func standardBeatGroupDuration(
        for timeSignature: TimeSignature,
        ticksPerWholeNote: Int
    ) -> Int? {
        switch timeSignature {
        case .sixEight, .nineEight, .twelveEight:
            guard ticksPerWholeNote.isMultiple(of: 8) else { return nil }
            return ticksPerWholeNote / 8 * 3
        case .twoFour, .threeFour, .fourFour, .fiveFour:
            guard ticksPerWholeNote.isMultiple(of: 4) else { return nil }
            return ticksPerWholeNote / 4
        case .sevenEight:
            return nil
        }
    }
}
