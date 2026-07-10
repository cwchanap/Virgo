import Testing
import SwiftUI
@testable import Virgo

@Suite("Tab Grid Overflow Fallback Tests")
struct NotationLayoutEngineTabGridOverflowTests {
    @Test("tab grid degrades to fallback when LCM of tick resolutions overflows")
    func tabGridDegradesToFallbackWhenLCMOverflows() {
        // 256 and 251 are coprime → LCM = 64256, which exceeds the
        // fallbackTicksPerMeasure * 64 (61440) cap. The engine should
        // degrade to the fallback 960-tick grid rather than overflow.
        let notes = [
            Note(
                interval: .quarter,
                noteType: .snare,
                measureNumber: 1,
                measureOffset: 0.0,
                originKind: .dtx,
                normalizedMeasureIndex: 0,
                normalizedAbsoluteTick: 0,
                normalizedTickWithinMeasure: 0,
                normalizedTicksPerMeasure: 256
            ),
            Note(
                interval: .quarter,
                noteType: .bass,
                measureNumber: 1,
                measureOffset: 0.0,
                originKind: .dtx,
                normalizedMeasureIndex: 0,
                normalizedAbsoluteTick: 0,
                normalizedTickWithinMeasure: 0,
                normalizedTicksPerMeasure: 251
            )
        ]

        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
        )

        #expect(layout.tabGrid.ticksPerMeasure == TabGrid.fallbackTicksPerMeasure)
    }

    @Test("tab grid falls back when an intermediate LCM overflows even if a later value recovers")
    func tabGridFallsBackWhenIntermediateLCMOverflows() {
        // Sorted resolutions [16, 4095, 4096] (16 is the 4/4 meter baseline).
        // lcm(16, 4095) = 65520, which exceeds the 61440 cap. A naive reduce
        // that only substitutes the fallback for the overflowing step would
        // then compute lcm(960, 4096) = 61440 and return that — a grid not
        // divisible by 4095. The engine must short-circuit to the fallback
        // instead of letting a later value "rescue" the accumulator.
        let notes = [
            Note(
                interval: .quarter,
                noteType: .snare,
                measureNumber: 1,
                measureOffset: 0.0,
                originKind: .dtx,
                normalizedMeasureIndex: 0,
                normalizedAbsoluteTick: 0,
                normalizedTickWithinMeasure: 0,
                normalizedTicksPerMeasure: 4095
            ),
            Note(
                interval: .quarter,
                noteType: .bass,
                measureNumber: 1,
                measureOffset: 0.0,
                originKind: .dtx,
                normalizedMeasureIndex: 0,
                normalizedAbsoluteTick: 0,
                normalizedTickWithinMeasure: 0,
                normalizedTicksPerMeasure: 4096
            )
        ]

        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
        )

        #expect(layout.tabGrid.ticksPerMeasure == TabGrid.fallbackTicksPerMeasure)
    }

    @Test("tab grid overflow fallback preserves 7/8 meter beat alignment")
    func tabGridOverflowFallbackPreservesSevenEightMeterBeatAlignment() {
        // 256 and 251 are coprime → LCM = 64256, exceeding the 61440 cap.
        // In 7/8 the meter baseline is 14, which does not divide 960, so the
        // fallback must be LCM(960, 14) = 6720 — otherwise beat boundaries
        // land on fractional tick columns and the playhead drifts off beat.
        let notes = [
            Note(
                interval: .quarter,
                noteType: .snare,
                measureNumber: 1,
                measureOffset: 0.0,
                originKind: .dtx,
                normalizedMeasureIndex: 0,
                normalizedAbsoluteTick: 0,
                normalizedTickWithinMeasure: 0,
                normalizedTicksPerMeasure: 256
            ),
            Note(
                interval: .quarter,
                noteType: .bass,
                measureNumber: 1,
                measureOffset: 0.0,
                originKind: .dtx,
                normalizedMeasureIndex: 0,
                normalizedAbsoluteTick: 0,
                normalizedTickWithinMeasure: 0,
                normalizedTicksPerMeasure: 251
            )
        ]

        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .sevenEight)
        )

        let baseline = NotationLayoutEngine.meterBaselineTicksPerMeasure(timeSignature: .sevenEight)
        #expect(layout.tabGrid.ticksPerMeasure == 6720)
        #expect(layout.tabGrid.ticksPerMeasure.isMultiple(of: baseline))

        // Every beat in 7/8 must map to a whole tick column (6720 / 7 = 960).
        let beatTicks = (0...7).map {
            layout.tabGrid.tickIndex(forBeatWithinMeasure: Double($0), beatsPerMeasure: 7)
        }
        #expect(beatTicks == [0, 960, 1920, 2880, 3840, 4800, 5760, 6720])
    }
}
