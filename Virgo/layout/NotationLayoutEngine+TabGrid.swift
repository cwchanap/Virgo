import CoreGraphics
import Foundation

/// Tab grid construction extracted from NotationLayoutEngine to keep the main
/// engine file under the SwiftLint file-length limit. These helpers resolve the
/// per-measure tick grid (ticks-per-measure, tick width, left padding) from the
/// note set's normalized grid metadata, then map notes to tick positions.
extension NotationLayoutEngine {
    // MARK: - Tab Grid

    func buildTabGrid(notes: [Note], input: NotationLayoutInput) -> TabGrid {
        let ticksPerMeasure = resolvedTicksPerMeasure(for: notes)
        let requiredGap = requiredGridColumnGap(notes: notes, input: input)
        let baselineGap = max(ticksPerMeasure / 16, 1)
        let occupiedTicks = Set(notes.map { tickWithinMeasure(for: $0, ticksPerMeasure: ticksPerMeasure) })
        let actualSmallestGap = smallestPositiveGap(in: occupiedTicks.sorted())
        let spacingTickGap = min(actualSmallestGap ?? baselineGap, baselineGap)
        let tickWidth = requiredGap / CGFloat(max(spacingTickGap, 1))
        let leftPadding = GameplayLayout.barLineWidth + GameplayLayout.uniformSpacing
        let measureWidth = TabGrid.measureWidth(
            ticksPerMeasure: ticksPerMeasure,
            tickWidth: tickWidth,
            leftPadding: leftPadding
        )

        return TabGrid(
            ticksPerMeasure: ticksPerMeasure,
            tickWidth: tickWidth,
            leftPadding: leftPadding,
            measureWidth: measureWidth
        )
    }

    func resolvedTicksPerMeasure(for notes: [Note]) -> Int {
        var values = Set<Int>()
        var needsFallbackResolution = false

        for note in notes {
            guard let normalizedGrid = normalizedGridMetadata(for: note) else {
                needsFallbackResolution = true
                continue
            }
            values.insert(normalizedGrid.ticksPerMeasure)
        }

        if needsFallbackResolution {
            values.insert(TabGrid.fallbackTicksPerMeasure)
        }

        guard !values.isEmpty else { return TabGrid.fallbackTicksPerMeasure }

        return values.sorted().reduce(1) { partial, value in
            guard let next = leastCommonMultiple(partial, value), next <= TabGrid.fallbackTicksPerMeasure * 64 else {
                return TabGrid.fallbackTicksPerMeasure
            }
            return next
        }
    }

    func leastCommonMultiple(_ lhs: Int, _ rhs: Int) -> Int? {
        guard lhs > 0, rhs > 0 else { return nil }
        let divisor = greatestCommonDivisor(lhs, rhs)
        let divided = lhs / divisor
        guard divided <= Int.max / rhs else { return nil }
        return divided * rhs
    }

    func greatestCommonDivisor(_ lhs: Int, _ rhs: Int) -> Int {
        var a = lhs
        var b = rhs
        while b != 0 {
            let next = a % b
            a = b
            b = next
        }
        return abs(a)
    }

    func requiredGridColumnGap(notes: [Note], input: NotationLayoutInput) -> CGFloat {
        let uniqueMeasureIndices = Set(notes.map { normalizedMeasureIndex(for: $0) })
        let hasCollision = uniqueMeasureIndices.contains { measureIndex in
            containsCrossVoiceCollision(measureIndex: measureIndex, notes: notes)
        }

        return hasCollision
            ? input.style.minimumNoteColumnGap + 2 * input.style.voiceCollisionOffset
            : input.style.minimumNoteColumnGap
    }

    func smallestPositiveGap(in ticks: [Int]) -> Int? {
        guard ticks.count > 1 else { return nil }
        return zip(ticks.dropFirst(), ticks)
            .map { $0.0 - $0.1 }
            .filter { $0 > 0 }
            .min()
    }

    // MARK: - Tick Resolution

    func normalizedGridMetadata(for note: Note) -> (tickWithinMeasure: Int, ticksPerMeasure: Int)? {
        guard let sourceTick = note.normalizedTickWithinMeasure,
              let sourceTicksPerMeasure = note.normalizedTicksPerMeasure,
              sourceTick >= 0,
              sourceTicksPerMeasure > 0,
              sourceTick <= sourceTicksPerMeasure else {
            return nil
        }

        return (sourceTick, sourceTicksPerMeasure)
    }

    func tickWithinMeasure(for note: Note, ticksPerMeasure: Int) -> Int {
        if let normalizedGrid = normalizedGridMetadata(for: note),
           ticksPerMeasure.isMultiple(of: normalizedGrid.ticksPerMeasure) {
            return min(
                normalizedGrid.tickWithinMeasure
                    * (ticksPerMeasure / normalizedGrid.ticksPerMeasure),
                ticksPerMeasure
            )
        }

        let offset = normalizedOffset(for: note)
        return min(max(Int((offset * Double(ticksPerMeasure)).rounded()), 0), ticksPerMeasure)
    }
}
