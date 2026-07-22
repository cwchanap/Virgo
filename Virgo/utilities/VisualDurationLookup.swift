//
//  VisualDurationLookup.swift
//  Virgo
//
//  Extracted from DTXFileParser to keep parser file under SwiftLint limits.
//

import Foundation

/// Pure lookup helper that maps DTX chips with a later same-voice onset to
/// readable `NoteInterval` visual duration candidates in a shared tick space.
/// Terminal chips are deliberately absent because the source contains no
/// duration evidence.
///
/// Each notation voice is scanned independently across all measures (not just
/// within a single measure), while same-tick chips remain one chord onset. This
/// lets the final chip in one measure inherit from a same-voice chip in the next
/// measure without borrowing duration evidence from the opposite voice.
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
        let positions = playableChips.compactMap { chip -> (
            key: String,
            absoluteTick: Int,
            voice: NotationVoice
        )? in
            guard let noteType = chip.toNoteType() else { return nil }
            let voice = DrumNotationCatalog.definition(for: noteType)?.voice ?? .upper
            return (
                key: chipKey(chip),
                absoluteTick: normalizedAbsoluteTick(for: chip, ticksPerMeasure: ticksPerMeasure),
                voice: voice
            )
        }
        return candidates(for: positions, ticksPerWholeNote: ticksPerMeasure)
    }

    static func candidates<Key: Hashable>(
        for positions: [(key: Key, absoluteTick: Int, voice: NotationVoice)],
        ticksPerWholeNote: Int
    ) -> [Key: NoteInterval] {
        guard ticksPerWholeNote > 0 else { return [:] }
        let positionsByVoice = Dictionary(grouping: positions) { $0.voice }
        var result: [Key: NoteInterval] = [:]

        for voicePositions in positionsByVoice.values {
            let orderedTicks = Array(Set(voicePositions.map { $0.absoluteTick })).sorted()
            let nextTickByTick = Dictionary(uniqueKeysWithValues: zip(orderedTicks, orderedTicks.dropFirst()))
            for position in voicePositions {
                guard let nextTick = nextTickByTick[position.absoluteTick] else { continue }
                result[position.key] = closestInterval(
                    toTickSpan: nextTick - position.absoluteTick,
                    ticksPerMeasure: ticksPerWholeNote
                )
            }
        }
        return result
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

        // `min` is stable, so on equal-distance ties it keeps the earlier
        // element. The array is ordered longest-duration-first, which means
        // ties resolve to the longer (more legible) interval.
        return supportedIntervals.min { lhs, rhs in
            abs(measureFraction - lhs.measureFraction) < abs(measureFraction - rhs.measureFraction)
        }?.interval ?? .quarter
    }
}
