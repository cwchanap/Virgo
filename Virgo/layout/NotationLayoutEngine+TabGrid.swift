import CoreGraphics
import Foundation

/// Tab grid construction extracted from NotationLayoutEngine to keep the main
/// engine file under the SwiftLint file-length limit. These helpers resolve the
/// per-measure tick grid (ticks-per-measure, tick width, left padding) from the
/// note set's normalized grid metadata, then map notes to tick positions.
extension NotationLayoutEngine {
    // MARK: - Tab Grid

    func buildTabGrid(notes: [Note], input: NotationLayoutInput) -> TabGrid {
        let ticksPerMeasure = resolvedTicksPerMeasure(for: notes, timeSignature: input.timeSignature)
        let requiredGap = requiredGridColumnGap(notes: notes, ticksPerMeasure: ticksPerMeasure, input: input)
        let baselineGap = max(ticksPerMeasure / 16, 1)
        let actualSmallestGap = smallestPositiveTickGapAcrossMeasures(
            notes: notes,
            ticksPerMeasure: ticksPerMeasure
        )
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

    func resolvedTicksPerMeasure(for notes: [Note], timeSignature: TimeSignature) -> Int {
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

        // Raise the canonical grid to at least a sixteenth-note baseline for the
        // meter. A degenerate imported resolution (e.g. `normalizedTicksPerMeasure
        // == 1` from a chart with one chip per playable line) cannot represent
        // beat subdivisions, so `tickIndex(forBeatWithinMeasure:)` would collapse
        // every beat to 0 or 1 and the playhead/beat cache would jump to the
        // wrong columns. LCM-ing the baseline in (rather than max-ing the final
        // result) keeps exact tick placement for notes on finer imported grids
        // while guaranteeing the meter is representable on coarse ones.
        values.insert(Self.meterBaselineTicksPerMeasure(timeSignature: timeSignature))

        guard !values.isEmpty else { return TabGrid.fallbackTicksPerMeasure }

        // Once the running LCM exceeds the cap, short-circuit to the fallback
        // instead of substituting the fallback into the accumulator and
        // continuing. A later value could LCM with the fallback back under the
        // cap (e.g. 960 × 4096 = 61440), yielding a grid that is not divisible
        // by the resolution that overflowed, which pushes those notes onto
        // rounded fractional offsets and breaks column alignment.
        var resolvedTicks = 1
        for value in values.sorted() {
            guard let next = leastCommonMultiple(resolvedTicks, value),
                  next <= TabGrid.fallbackTicksPerMeasure * 64 else {
                return TabGrid.fallbackTicksPerMeasure
            }
            resolvedTicks = next
        }
        return resolvedTicks
    }

    /// Sixteenth-note tick baseline for a meter: the smallest canonical grid that
    /// can place every beat and every sixteenth in the measure.
    /// `beatsPerMeasure * 16 / noteValue` (e.g. 16 for 4/4, 12 for 6/8).
    static func meterBaselineTicksPerMeasure(timeSignature: TimeSignature) -> Int {
        guard timeSignature.noteValue > 0 else { return 16 }
        return max(timeSignature.beatsPerMeasure * 16 / timeSignature.noteValue, 1)
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

    func requiredGridColumnGap(notes: [Note], ticksPerMeasure: Int, input: NotationLayoutInput) -> CGFloat {
        let uniqueMeasureIndices = Set(notes.map { normalizedMeasureIndex(for: $0) })
        let hasCollision = uniqueMeasureIndices.contains { measureIndex in
            containsCrossVoiceCollision(measureIndex: measureIndex, ticksPerMeasure: ticksPerMeasure, notes: notes)
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

    /// Smallest positive tick gap between notes that share a measure.
    ///
    /// Grouping by measure index prevents adjacent tick columns in different
    /// measures (e.g. tick 0 in measure A, tick 1 in measure B) from being
    /// treated as a same-measure gap of 1, which would collapse `spacingTickGap`
    /// to 1 on high-resolution grids and inflate every measure width.
    func smallestPositiveTickGapAcrossMeasures(notes: [Note], ticksPerMeasure: Int) -> Int? {
        let measureTicks = Dictionary(grouping: notes) { normalizedMeasureIndex(for: $0) }
        return measureTicks.values.compactMap { measureNotes -> Int? in
            let ticks = Set(measureNotes.map { tickWithinMeasure(for: $0, ticksPerMeasure: ticksPerMeasure) }).sorted()
            return smallestPositiveGap(in: ticks)
        }.min()
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
