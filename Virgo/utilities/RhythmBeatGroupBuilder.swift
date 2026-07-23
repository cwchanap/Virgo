import Foundation

/// Canonical meter-driven beat grouping shared by timeline construction and
/// notation layout. Keeping this contract in one place prevents expanded
/// layout measures from drifting from the persisted rhythm timeline.
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

        let standardDuration: Int
        switch timeSignature {
        case .sixEight, .nineEight, .twelveEight:
            standardDuration = ticksPerWholeNote / 8 * 3
        case .twoFour, .threeFour, .fourFour, .fiveFour:
            standardDuration = ticksPerWholeNote / 4
        case .sevenEight:
            return []
        }
        guard standardDuration > 0 else { return [] }

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
}
