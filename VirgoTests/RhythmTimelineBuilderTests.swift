//
//  RhythmTimelineBuilderTests.swift
//  VirgoTests
//

import Foundation
import Testing
@testable import Virgo

@Suite("Rhythm timeline builder")
struct RhythmTimelineBuilderTests {
    @Test("ordinary four-four projects source grids exactly")
    func ordinaryFourFourProjectsSourceGridsExactly() throws {
        let events = [
            dtxEvent(ordinal: 0, measureIndex: 0, gridPosition: 1, gridSize: 3),
            dtxEvent(ordinal: 1, measureIndex: 0, gridPosition: 5, gridSize: 6),
            dtxEvent(ordinal: 2, measureIndex: 0, gridPosition: 11, gridSize: 12)
        ]

        let timeline = try build(metadata: metadata(.fourFour), events: events)

        #expect(timeline.ticksPerWholeNote == 12)
        #expect(timeline.measures[0].durationTicks == 12)
        #expect(timeline.position(for: events[0].id)?.localTick == 4)
        #expect(timeline.position(for: events[1].id)?.localTick == 10)
        #expect(timeline.position(for: events[2].id)?.localTick == 11)
    }

    @Test("compound six-eight uses dotted-quarter beat groups and quarter-note BPM")
    func compoundSixEightGroupsAndSeconds() throws {
        let event = dtxEvent(ordinal: 0, measureIndex: 0, gridPosition: 1, gridSize: 12)
        let timeline = try build(metadata: metadata(.sixEight), events: [event])

        #expect(timeline.ticksPerWholeNote == 16)
        #expect(timeline.measures[0].durationTicks == 12)
        #expect(timeline.measures[0].beatGroups.map(\.durationTicks) == [6, 6])
        #expect(timeline.seconds(forAbsoluteTick: 2, bpm: 120, speed: 1) == 0.25)
        #expect(timeline.seconds(forAbsoluteTick: 6, bpm: 120, speed: 1) == 0.75)
        #expect(timeline.endSeconds(bpm: 120, speed: 1) == 1.5)
    }

    @Test("shortened and extended measures change cumulative positions")
    func cumulativeVariableMeasures() throws {
        let pickup = try MeasureLengthOverride(
            measureIndex: 0,
            ratioToWholeNote: .init(numerator: 3, denominator: 4)
        )
        let extended = try MeasureLengthOverride(
            measureIndex: 1,
            ratioToWholeNote: .init(numerator: 3, denominator: 2)
        )
        let chartMetadata = metadata(.threeFour, overrides: [pickup, extended])
        let event = dtxEvent(ordinal: 0, measureIndex: 1, gridPosition: 1, gridSize: 3)

        let timeline = try build(metadata: chartMetadata, events: [event], minimumMeasureCount: 2)

        #expect(timeline.ticksPerWholeNote == 4)
        #expect(timeline.measures.map(\.durationTicks) == [3, 6])
        #expect(timeline.measures[1].startTick == 3)
        #expect(timeline.position(for: event.id)?.absoluteTick == 5)
        #expect(timeline.seconds(forAbsoluteTick: 3, bpm: 120, speed: 1) == 1.5)
        #expect(timeline.endTick == 9)
    }

    @Test("mixed sixty-four and ninety-six grids share an exact quantum")
    func mixedFineGridsAreExact() throws {
        let first = dtxEvent(ordinal: 0, measureIndex: 0, gridPosition: 63, gridSize: 64)
        let second = dtxEvent(ordinal: 1, measureIndex: 0, gridPosition: 95, gridSize: 96)

        let timeline = try build(metadata: metadata(.fourFour), events: [first, second])

        #expect(timeline.ticksPerWholeNote == 192)
        #expect(timeline.position(for: first.id)?.localTick == 189)
        #expect(timeline.position(for: second.id)?.localTick == 190)
    }

    @Test("continuous seconds conversion is bounded and invertible")
    func continuousTickConversion() throws {
        let timeline = try build(metadata: metadata(.fourFour), events: [], minimumMeasureCount: 2)

        #expect(timeline.continuousTick(forSeconds: 1.25, bpm: 120, speed: 1) == 2.5)
        #expect(timeline.continuousTick(forSeconds: 0.625, bpm: 120, speed: 2) == 2.5)
        #expect(timeline.continuousTick(forSeconds: -0.001, bpm: 120, speed: 1) == nil)
        #expect(timeline.continuousTick(forSeconds: 5, bpm: 120, speed: 1) == nil)
        #expect(timeline.seconds(forAbsoluteTick: 9, bpm: 120, speed: 1) == nil)
        #expect(timeline.seconds(forAbsoluteTick: 1, bpm: 0, speed: 1) == nil)
    }

    @Test("seconds conversion does not require a quantum divisible by four")
    func secondsConversionWithNonQuarterQuantum() throws {
        let override = try MeasureLengthOverride(
            measureIndex: 0,
            ratioToWholeNote: .init(numerator: 1, denominator: 3)
        )
        let timeline = try build(metadata: metadata(.sevenEight, overrides: [override]), events: [])

        #expect(timeline.ticksPerWholeNote == 3)
        #expect(timeline.seconds(forAbsoluteTick: 1, bpm: 60, speed: 1) == 4.0 / 3.0)
    }

    @Test("inclusive measure ends canonicalize to the following measure")
    func measureEndCanonicalization() throws {
        let timeline = try build(metadata: metadata(.fourFour), events: [], minimumMeasureCount: 2)
        let measureEnd = timeline.measures[0].durationTicks

        #expect(timeline.position(measureIndex: 0, localTick: measureEnd) == .init(
            measureIndex: 1,
            localTick: 0,
            absoluteTick: measureEnd
        ))
        #expect(timeline.position(forAbsoluteTick: measureEnd)?.measureIndex == 1)
        #expect(timeline.position(
            measureIndex: 1,
            localTick: timeline.measures[1].durationTicks
        )?.absoluteTick == timeline.endTick)
        #expect(timeline.position(measureIndex: 0, localTick: measureEnd + 1) == nil)
    }

    @Test("beat-group lookup handles simple, residual, and ambiguous meters")
    func beatGroupLookup() throws {
        let shortened = try MeasureLengthOverride(
            measureIndex: 0,
            ratioToWholeNote: .init(numerator: 5, denominator: 8)
        )
        let simple = try build(metadata: metadata(.fourFour, overrides: [shortened]), events: [])
        let ambiguous = try build(metadata: metadata(.sevenEight), events: [])

        #expect(simple.measures[0].beatGroups.map(\.durationTicks) == [2, 2, 1])
        #expect(simple.measures[0].beatGroups.map(\.isResidual) == [false, false, true])
        #expect(simple.beatGroup(containingAbsoluteTick: 4)?.isResidual == true)
        #expect(ambiguous.measures[0].engravingSupport == .unsupported([.ambiguousBeatGrouping]))
        #expect(ambiguous.measures[0].beatGroups.count == 1)
    }

    @Test("compound nine-eight and twelve-eight use dotted-quarter groups")
    func remainingCompoundMeters() throws {
        let nineEight = try build(metadata: metadata(.nineEight), events: [])
        let twelveEight = try build(metadata: metadata(.twelveEight), events: [])

        #expect(nineEight.measures[0].beatGroups.count == 3)
        #expect(nineEight.measures[0].beatGroups.map(\.durationTicks) == [3, 3, 3])
        #expect(twelveEight.measures[0].beatGroups.count == 4)
        #expect(twelveEight.measures[0].beatGroups.map(\.durationTicks) == [3, 3, 3, 3])
    }

    @Test("BGM source anchors use the same exact projection")
    func bgmAnchorProjection() throws {
        let anchor = try RhythmSourceAnchor(measureIndex: 1, gridPosition: 3, gridSize: 4)
        let chartMetadata = try ChartRhythmMetadata(
            timeSignature: .sixEight,
            feel: .straight,
            measureLengthOverrides: [],
            bgmStartAnchor: anchor,
            timingStatus: .valid,
            diagnostics: []
        )

        let timeline = try build(metadata: chartMetadata, events: [])

        #expect(timeline.ticksPerWholeNote == 16)
        #expect(timeline.bgmStartPosition == .init(measureIndex: 1, localTick: 9, absoluteTick: 21))
    }

    @Test("manual offsets rationalize and exact-one rolls into the next measure")
    func manualOffsetRationalizationAndRollover() throws {
        let tenth = manualEvent(ordinal: 0, measureNumber: 1, measureOffset: 0.1)
        let third = manualEvent(ordinal: 1, measureNumber: 1, measureOffset: 0.333333333333)
        let rollover = manualEvent(ordinal: 2, measureNumber: 1, measureOffset: 1)

        let timeline = try build(
            metadata: metadata(.fourFour),
            events: [tenth, third, rollover],
            minimumMeasureCount: 2
        )

        #expect(timeline.ticksPerWholeNote == 60)
        #expect(timeline.position(for: tenth.id)?.localTick == 6)
        #expect(timeline.position(for: third.id)?.localTick == 20)
        #expect(timeline.position(for: rollover.id) == .init(measureIndex: 1, localTick: 0, absoluteTick: 60))
    }

    @Test("event onsets remain half-open")
    func eventOnsetsRemainHalfOpen() throws {
        let invalid = dtxEvent(ordinal: 0, measureIndex: 0, gridPosition: 4, gridSize: 4)

        #expect(throws: RhythmTimelineBuildError.invalidSourceCoordinate) {
            _ = try build(metadata: metadata(.fourFour), events: [invalid])
        }
    }
}

extension RhythmTimelineBuilderTests {
    @Test("resolution accepts 4032 and rejects the next hostile LCM")
    func boundedResolution() throws {
        let accepted = [
            dtxEvent(ordinal: 0, measureIndex: 0, gridPosition: 1, gridSize: 63),
            dtxEvent(ordinal: 1, measureIndex: 0, gridPosition: 1, gridSize: 64)
        ]
        let rejected = [
            dtxEvent(ordinal: 0, measureIndex: 0, gridPosition: 1, gridSize: 64),
            dtxEvent(ordinal: 1, measureIndex: 0, gridPosition: 1, gridSize: 65)
        ]

        #expect(try build(metadata: metadata(.fourFour), events: accepted).ticksPerWholeNote == 4_032)
        #expect(throws: RhythmTimelineBuildError.resolutionLimitExceeded) {
            _ = try build(metadata: metadata(.fourFour), events: rejected)
        }
    }

    @Test("coupled measure and grid factors prevent inexact slot projection")
    func coupledMeasureGridFactor() throws {
        let override = try MeasureLengthOverride(
            measureIndex: 0,
            ratioToWholeNote: .init(numerator: 3, denominator: 4)
        )
        let event = dtxEvent(ordinal: 0, measureIndex: 0, gridPosition: 2, gridSize: 3)

        let timeline = try build(metadata: metadata(.fourFour, overrides: [override]), events: [event])

        #expect(timeline.ticksPerWholeNote == 4)
        #expect(timeline.measures[0].durationTicks == 3)
        #expect(timeline.position(for: event.id)?.localTick == 2)
    }

    @Test("checked arithmetic rejects factor and duration overflow")
    func checkedArithmeticOverflow() throws {
        let denominatorOverflow = try MeasureLengthOverride(
            measureIndex: 0,
            ratioToWholeNote: .init(numerator: 1, denominator: 4_096)
        )
        let source = dtxEvent(
            ordinal: 0,
            measureIndex: 0,
            gridPosition: 0,
            gridSize: Int.max
        )
        let durationOverflow = try MeasureLengthOverride(
            measureIndex: 0,
            ratioToWholeNote: .init(numerator: Int.max, denominator: 1)
        )

        #expect(throws: RhythmTimelineBuildError.arithmeticOverflow) {
            _ = try build(metadata: metadata(.fourFour, overrides: [denominatorOverflow]), events: [source])
        }
        #expect(throws: RhythmTimelineBuildError.arithmeticOverflow) {
            _ = try build(metadata: metadata(.fourFour, overrides: [durationOverflow]), events: [])
        }
    }

    @Test("the final cumulative tick is an exact Double integer")
    func exactDoubleTickBound() throws {
        let acceptedOverride = try MeasureLengthOverride(
            measureIndex: 0,
            ratioToWholeNote: .init(numerator: RhythmLimits.maximumExactDoubleInteger, denominator: 1)
        )
        let rejectedOverride = try MeasureLengthOverride(
            measureIndex: 0,
            ratioToWholeNote: .init(numerator: RhythmLimits.maximumExactDoubleInteger + 1, denominator: 1)
        )

        // Ambiguous 7/8 intentionally materializes one beat group regardless of
        // duration, so this arithmetic boundary proof cannot allocate per tick.
        let accepted = try build(metadata: metadata(.sevenEight, overrides: [acceptedOverride]), events: [])
        #expect(accepted.endTick == RhythmLimits.maximumExactDoubleInteger)
        #expect(Double(accepted.endTick) == Double(RhythmLimits.maximumExactDoubleInteger))
        #expect(throws: RhythmTimelineBuildError.cumulativeTickLimitExceeded) {
            _ = try build(metadata: metadata(.sevenEight, overrides: [rejectedOverride]), events: [])
        }
    }

    @Test("beat-group preflight accepts the cap without materializing groups")
    func beatGroupPreflightAcceptsCap() throws {
        let count = try RhythmTimelineBuilder.preflightBeatGroupMaterialization(
            timeSignature: .fourFour,
            durationTicksByMeasure: [RhythmLimits.maximumMaterializedRhythmUnitCount],
            ticksPerWholeNote: 4
        )

        #expect(count == RhythmLimits.maximumMaterializedRhythmUnitCount)
    }

    @Test("simple-meter beat-group count above the cap fails before materialization")
    func beatGroupMaterializationLimit() throws {
        let excessiveCount = RhythmLimits.maximumMaterializedRhythmUnitCount + 1
        let excessiveOverride = try MeasureLengthOverride(
            measureIndex: 0,
            ratioToWholeNote: .init(numerator: excessiveCount, denominator: 4)
        )

        #expect(throws: RhythmTimelineBuildError.materializationLimitExceeded) {
            _ = try RhythmTimelineBuilder.preflightBeatGroupMaterialization(
                timeSignature: .fourFour,
                durationTicksByMeasure: [excessiveCount],
                ticksPerWholeNote: 4
            )
        }
        #expect(throws: RhythmTimelineBuildError.materializationLimitExceeded) {
            _ = try build(metadata: metadata(.fourFour, overrides: [excessiveOverride]), events: [])
        }
    }

    @Test("measure and rollover bounds reject index 4096 before allocation")
    func measureBounds() throws {
        let last = manualEvent(ordinal: 0, measureNumber: 4_096, measureOffset: 0)
        let lastSource = dtxEvent(ordinal: 3, measureIndex: 4_095, gridPosition: 0, gridSize: 1)
        let finalRollover = manualEvent(ordinal: 1, measureNumber: 4_096, measureOffset: 1)
        let sourceBeyondLimit = dtxEvent(ordinal: 2, measureIndex: 4_096, gridPosition: 0, gridSize: 1)

        #expect(try build(metadata: metadata(.fourFour), events: [last]).measures.count == 4_096)
        #expect(try build(metadata: metadata(.fourFour), events: [lastSource]).measures.count == 4_096)
        #expect(throws: RhythmTimelineBuildError.measureLimitExceeded) {
            _ = try build(metadata: metadata(.fourFour), events: [finalRollover])
        }
        #expect(throws: RhythmTimelineBuildError.measureLimitExceeded) {
            _ = try build(metadata: metadata(.fourFour), events: [sourceBeyondLimit])
        }
        #expect(throws: RhythmTimelineBuildError.measureLimitExceeded) {
            _ = try build(metadata: metadata(.fourFour), events: [], minimumMeasureCount: 4_097)
        }
    }

    @Test("measure overrides share the inclusive 4095 exclusive 4096 bound")
    func measureOverrideBounds() throws {
        let ratio = try RhythmRatio(numerator: 1, denominator: 1)

        #expect(try MeasureLengthOverride(measureIndex: 4_095, ratioToWholeNote: ratio).measureIndex == 4_095)
        #expect(throws: RhythmMetadataValidationError.invalidMeasureIndex) {
            _ = try MeasureLengthOverride(measureIndex: 4_096, ratioToWholeNote: ratio)
        }
    }

    @Test("manual irrational offsets outside tolerance are rejected")
    func manualOffsetOutsideTolerance() throws {
        let irrational = manualEvent(
            ordinal: 0,
            measureNumber: 1,
            measureOffset: 0.4142135623730951
        )

        #expect(throws: RhythmTimelineBuildError.manualOffsetUnrepresentable) {
            _ = try build(metadata: metadata(.fourFour), events: [irrational])
        }
    }

    @Test("source event IDs must be unique")
    func duplicateSourceEventIDs() throws {
        let first = dtxEvent(ordinal: 0, measureIndex: 0, gridPosition: 0, gridSize: 4)
        let duplicate = dtxEvent(ordinal: 0, measureIndex: 0, gridPosition: 1, gridSize: 4)

        #expect(throws: RhythmTimelineBuildError.duplicateSourceEventID) {
            _ = try build(metadata: metadata(.fourFour), events: [first, duplicate])
        }
    }

    private func build(
        metadata: ChartRhythmMetadata,
        events: [RhythmSourceEvent],
        minimumMeasureCount: Int = 1
    ) throws -> RhythmTimeline {
        try RhythmTimelineBuilder().build(
            metadata: metadata,
            events: events,
            minimumMeasureCount: minimumMeasureCount
        )
    }

    private func metadata(
        _ timeSignature: TimeSignature,
        overrides: [MeasureLengthOverride] = []
    ) -> ChartRhythmMetadata {
        try! ChartRhythmMetadata(
            timeSignature: timeSignature,
            feel: .straight,
            measureLengthOverrides: overrides,
            bgmStartAnchor: nil,
            timingStatus: .valid,
            diagnostics: []
        )
    }

    private func dtxEvent(
        ordinal: Int,
        measureIndex: Int,
        gridPosition: Int,
        gridSize: Int
    ) -> RhythmSourceEvent {
        RhythmSourceEvent(
            id: .init(kind: .note, stableOrdinal: ordinal),
            coordinate: .dtx(
                measureIndex: measureIndex,
                gridPosition: gridPosition,
                gridSize: gridSize
            ),
            sourceLaneID: "11",
            sourceNoteID: String(format: "%02X", ordinal),
            drumLaneID: "snare"
        )
    }

    private func manualEvent(
        ordinal: Int,
        measureNumber: Int,
        measureOffset: Double
    ) -> RhythmSourceEvent {
        RhythmSourceEvent(
            id: .init(kind: .note, stableOrdinal: ordinal),
            coordinate: .manual(measureNumber: measureNumber, measureOffset: measureOffset),
            drumLaneID: "snare"
        )
    }
}
