//
//  VisualDurationLookup.swift
//  Virgo
//
//  Extracted from DTXFileParser to keep parser file under SwiftLint limits.
//

import Foundation

/// Pure lookup helper that maps DTX chips to readable `NoteInterval` visual
/// duration candidates based on musical spacing in a shared tick space.
///
/// The lookup sorts every playable chip by absolute tick across all measures
/// (not just within a single measure) so that the final chip in one measure
/// can inherit its visual duration from the first chip in the next measure.
/// This is musically more correct than a per-measure-only scan and is covered
/// by `testVisualDurationCandidatesUseNextMeasureChip`.
enum VisualDurationLookup {

    /// Returns a dictionary keyed by `chipKey` mapping each playable chip to
    /// its inferred visual duration candidate.
    static func candidates(
        for chips: [DTXNote],
        ticksPerMeasure: Int
    ) -> [String: NoteInterval] {
        guard ticksPerMeasure > 0 else {
            return [:]
        }

        let playableChips = chips.filter { chip in
            chip.gridSize > 0
                && chip.gridPosition >= 0
                && chip.gridPosition < chip.gridSize
        }
        let playableChipsByMeasure = Dictionary(grouping: playableChips, by: \.measureIndex)
        let fallbackTickSpanByMeasure = playableChipsByMeasure.mapValues { measureChips in
            let uniqueTicks = Set(measureChips.map {
                normalizedTick(for: $0, ticksPerMeasure: ticksPerMeasure)
            })

            return uniqueTicks.count == ticksPerMeasure ? 1 : max(ticksPerMeasure / 4, 1)
        }
        let sortedChips = playableChips.sorted { lhs, rhs in
            let lhsTick = normalizedAbsoluteTick(for: lhs, ticksPerMeasure: ticksPerMeasure)
            let rhsTick = normalizedAbsoluteTick(for: rhs, ticksPerMeasure: ticksPerMeasure)

            if lhsTick == rhsTick {
                return chipKey(lhs) < chipKey(rhs)
            }

            return lhsTick < rhsTick
        }
        let uniqueAbsoluteTicks = Array(Set(sortedChips.map {
            normalizedAbsoluteTick(for: $0, ticksPerMeasure: ticksPerMeasure)
        })).sorted()
        var nextAbsoluteTickByTick: [Int: Int] = [:]
        for index in uniqueAbsoluteTicks.indices.dropLast() {
            nextAbsoluteTickByTick[uniqueAbsoluteTicks[index]] = uniqueAbsoluteTicks[index + 1]
        }

        var candidates: [String: NoteInterval] = [:]

        for chip in sortedChips {
            let currentTick = normalizedAbsoluteTick(for: chip, ticksPerMeasure: ticksPerMeasure)
            let tickSpan = nextAbsoluteTickByTick[currentTick].map { $0 - currentTick }
                ?? fallbackTickSpanByMeasure[chip.measureIndex]
                ?? max(ticksPerMeasure / 4, 1)

            candidates[chipKey(chip)] = closestInterval(
                toTickSpan: tickSpan,
                ticksPerMeasure: ticksPerMeasure
            )
        }

        return candidates
    }

    static func chipKey(_ chip: DTXNote) -> String {
        [
            String(chip.measureIndex),
            chip.laneID.uppercased(),
            chip.noteID.uppercased(),
            String(chip.gridPosition),
            String(chip.gridSize)
        ].joined(separator: "|")
    }

    static func normalizedTick(for chip: DTXNote, ticksPerMeasure: Int) -> Int {
        guard chip.gridSize > 0, ticksPerMeasure > 0 else {
            return 0
        }

        return chip.gridPosition * (ticksPerMeasure / chip.gridSize)
    }

    static func normalizedAbsoluteTick(for chip: DTXNote, ticksPerMeasure: Int) -> Int {
        chip.measureIndex * ticksPerMeasure + normalizedTick(for: chip, ticksPerMeasure: ticksPerMeasure)
    }

    /// Snaps a raw tick span to the closest supported `NoteInterval`.
    /// `.sixtyfourth` is the finest supported resolution and acts as the
    /// floor for very dense spacing.
    static func closestInterval(toTickSpan tickSpan: Int, ticksPerMeasure: Int) -> NoteInterval {
        guard tickSpan > 0, ticksPerMeasure > 0 else {
            return .quarter
        }

        let measureFraction = Double(tickSpan) / Double(ticksPerMeasure)
        let supportedIntervals: [(interval: NoteInterval, measureFraction: Double)] = [
            (.full, 1.0),
            (.half, 0.5),
            (.quarter, 0.25),
            (.eighth, 0.125),
            (.sixteenth, 0.0625),
            (.thirtysecond, 0.03125),
            (.sixtyfourth, 0.015625)
        ]

        return supportedIntervals.min { lhs, rhs in
            abs(measureFraction - lhs.measureFraction) < abs(measureFraction - rhs.measureFraction)
        }?.interval ?? .quarter
    }
}
