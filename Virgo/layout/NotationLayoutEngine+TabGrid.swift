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
        // Derive the display baseline from the active meter's sixteenth-note
        // count rather than a hard-coded 16, so sparse meters (2/4, 3/4, 5/4,
        // /8) get the correct column count when `ticksPerMeasure` is raised
        // above the meter baseline by imported grid resolution or LCM folding.
        let baselineGap = max(
            ticksPerMeasure / Self.meterBaselineTicksPerMeasure(timeSignature: input.timeSignature),
            1
        )
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

        guard !values.isEmpty else { return meterCompatibleFallbackTicksPerMeasure(for: timeSignature) }

        // Once the running LCM exceeds the cap, short-circuit to the fallback
        // instead of substituting the fallback into the accumulator and
        // continuing. A later value could LCM with the fallback back under the
        // cap (e.g. 960 × 4096 = 61440), yielding a grid that is not divisible
        // by the resolution that overflowed, which pushes those notes onto
        // rounded fractional offsets and breaks column alignment.
        let fallback = meterCompatibleFallbackTicksPerMeasure(for: timeSignature)
        var resolvedTicks = 1
        for value in values.sorted() {
            guard let next = leastCommonMultiple(resolvedTicks, value),
                  next <= TabGrid.fallbackTicksPerMeasure * 64 else {
                Logger.warning(
                    "Tab grid LCM overflowed cap (\(TabGrid.fallbackTicksPerMeasure * 64)) "
                        + "at value \(value); falling back to \(fallback) ticks/measure"
                )
                return fallback
            }
            resolvedTicks = next
        }
        return resolvedTicks
    }

    /// Fallback tick resolution that preserves the active meter's beat grid.
    ///
    /// `TabGrid.fallbackTicksPerMeasure` (960) is divisible by the sixteenth
    /// baseline of most meters, but not all — 7/8 (baseline 14) and 9/8
    /// (baseline 18) leave a remainder, so returning 960 directly on overflow
    /// or empty input pushes beat boundaries onto fractional tick columns and
    /// drifts the playhead off the beat. LCM-ing the fallback with the meter
    /// baseline yields a grid divisible by both (e.g. 6720 for 7/8), keeping
    /// beat alignment for every supported meter.
    func meterCompatibleFallbackTicksPerMeasure(for timeSignature: TimeSignature) -> Int {
        let baseline = Self.meterBaselineTicksPerMeasure(timeSignature: timeSignature)
        guard let lcm = leastCommonMultiple(TabGrid.fallbackTicksPerMeasure, baseline) else {
            return baseline
        }
        return lcm
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

    func requiredGridColumnGap(
        notes: [Note],
        ticksPerMeasure: Int,
        input: NotationLayoutInput
    ) -> CGFloat {
        // notes and ticksPerMeasure are intentionally unused; reserved for
        // future density-aware gap calculations per the HPA-141 plan.
        input.style.minimumNoteColumnGap
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
