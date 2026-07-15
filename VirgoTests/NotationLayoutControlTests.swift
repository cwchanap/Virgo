import Testing
@testable import Virgo

@Suite("Notation Layout Control Tests")
struct NotationLayoutControlTests {
    private let support = NotationLayoutTestSupport()

    @Test("complete normalized control timing overrides conflicting manual timing")
    func normalizedTimingTakesPrecedence() throws {
        let event = support.control(
            measureNumber: 99,
            measureOffset: 0.9,
            originKind: .manual,
            normalizedMeasureIndex: 0,
            normalizedAbsoluteTick: 1,
            normalizedTickWithinMeasure: 1,
            normalizedTicksPerMeasure: 4
        )
        let result = support.layout(notes: [support.fallbackGridNote()], controls: [event])
        let stop = try #require(result.stopNotes.first)

        #expect(result.measures.count == 1)
        #expect(stop.timeColumn.measureIndex == 0)
        #expect(stop.timeColumn.tickWithinMeasure == 240)
    }

    @Test("invalid complete normalized tuples contribute neither measures nor marks")
    func invalidNormalizedTimingIsRejected() {
        let invalidControls = [
            support.control(
                measureNumber: 8, normalizedMeasureIndex: -1,
                normalizedAbsoluteTick: 1, normalizedTickWithinMeasure: 1, normalizedTicksPerMeasure: 4
            ),
            support.control(
                measureNumber: 8, normalizedMeasureIndex: 0,
                normalizedAbsoluteTick: -1, normalizedTickWithinMeasure: 1, normalizedTicksPerMeasure: 4
            ),
            support.control(
                measureNumber: 8, normalizedMeasureIndex: 0,
                normalizedAbsoluteTick: 0, normalizedTickWithinMeasure: -1, normalizedTicksPerMeasure: 4
            ),
            support.control(
                measureNumber: 8, normalizedMeasureIndex: 0,
                normalizedAbsoluteTick: 5, normalizedTickWithinMeasure: 5, normalizedTicksPerMeasure: 4
            ),
            support.control(
                measureNumber: 8, normalizedMeasureIndex: 0,
                normalizedAbsoluteTick: 1, normalizedTickWithinMeasure: 1, normalizedTicksPerMeasure: 0
            ),
            support.control(
                measureNumber: 8, normalizedMeasureIndex: 1,
                normalizedAbsoluteTick: 4, normalizedTickWithinMeasure: 1, normalizedTicksPerMeasure: 4
            )
        ]
        let result = support.layout(notes: [], controls: invalidControls)

        #expect(result.measures.count == 1)
        #expect(result.stopNotes.isEmpty)
    }

    @Test("normalized controls reject overflowing and resource-exhausting measure indices")
    func normalizedTimingRejectsUnrenderableMeasureIndices() {
        let engine = NotationLayoutEngine()
        let controls = [
            support.control(
                originKind: .dtx,
                normalizedMeasureIndex: Int.max,
                normalizedAbsoluteTick: Int.max,
                normalizedTickWithinMeasure: 0,
                normalizedTicksPerMeasure: 1
            ),
            support.control(
                originKind: .dtx,
                normalizedMeasureIndex: 4_096,
                normalizedAbsoluteTick: 4_096,
                normalizedTickWithinMeasure: 0,
                normalizedTicksPerMeasure: 1
            )
        ]

        let resolution = engine.resolveControlTimings(controls)

        #expect(resolution.controls.isEmpty)
        #expect(resolution.invalidReasons == ["control measure exceeds renderable limit (4096)"])
    }

    @Test("manual controls reject resource-exhausting measure indices")
    func manualTimingRejectsUnrenderableMeasureIndices() {
        let resolution = NotationLayoutEngine().resolveControlTimings([
            support.control(measureNumber: 4_097, measureOffset: 0),
            support.control(measureNumber: 4_096, measureOffset: 1)
        ])

        #expect(resolution.controls.isEmpty)
        #expect(resolution.invalidReasons == ["control measure exceeds renderable limit (4096)"])
    }

    @Test("measure count is capped at the renderable resource limit")
    func measureCountIsResourceBounded() {
        let engine = NotationLayoutEngine()

        #expect(engine.totalMeasureCount(
            notes: [],
            controls: [],
            minimumMeasureCount: Int.max
        ) == 4_096)
    }

    @Test("a partial normalized tuple is invalid instead of using manual fallback")
    func partialNormalizedTimingIsRejected() {
        let partials = [
            support.control(measureNumber: 4, normalizedMeasureIndex: 3),
            support.control(measureNumber: 4, normalizedMeasureIndex: 3, normalizedAbsoluteTick: 12),
            support.control(
                measureNumber: 4,
                normalizedMeasureIndex: 3,
                normalizedAbsoluteTick: 12,
                normalizedTickWithinMeasure: 0
            )
        ]
        let result = support.layout(notes: [], controls: partials)

        #expect(result.measures.count == 1)
        #expect(result.stopNotes.isEmpty)
    }

    @Test("all-nil normalized timing permits only exact manual grid columns")
    func manualTimingRequiresExactGridProjection() {
        let controls = [
            support.control(measureOffset: 0.25, sourceNoteID: "exact"),
            support.control(measureOffset: 1.0 / 7.0, sourceNoteID: "inexact")
        ]
        let result = support.layout(notes: [support.fallbackGridNote()], controls: controls)

        #expect(result.stopNotes.count == 1)
        #expect(result.stopNotes.first?.sourceNoteID == "exact")
        #expect(result.stopNotes.first?.timeColumn.tickWithinMeasure == 240)
    }

    @Test("manual timing validates measure number offset finiteness and range")
    func invalidManualTimingIsRejected() {
        let controls = [
            support.control(measureNumber: 0, measureOffset: 0),
            support.control(measureNumber: 4, measureOffset: -0.1),
            support.control(measureNumber: 4, measureOffset: 1.1),
            support.control(measureNumber: 4, measureOffset: .nan)
        ]
        let result = support.layout(notes: [], controls: controls)

        #expect(result.measures.count == 1)
        #expect(result.stopNotes.isEmpty)
    }

    @Test("manual offset one normalizes to the next measure at tick zero")
    func manualEndOffsetNormalizesToNextMeasure() throws {
        let result = support.layout(
            notes: [support.fallbackGridNote()],
            controls: [support.control(measureNumber: 1, measureOffset: 1)]
        )
        let stop = try #require(result.stopNotes.first)

        #expect(result.measures.count == 2)
        #expect(stop.timeColumn.measureIndex == 1)
        #expect(stop.timeColumn.tickWithinMeasure == 0)
    }

    @Test("DTX controls never use manual timing fallback")
    func dtxTimingRequiresCompleteNormalizedTuple() {
        let result = support.layout(notes: [], controls: [
            support.control(measureNumber: 4, measureOffset: 0.25, originKind: .dtx)
        ])

        #expect(result.measures.count == 1)
        #expect(result.stopNotes.isEmpty)
    }

    @Test("normalized quarter timing projects exactly onto the fixed 960 grid")
    func normalizedQuarterProjectsExactly() throws {
        let result = support.layout(notes: [support.fallbackGridNote()], controls: [
            support.control(
                originKind: .dtx,
                normalizedMeasureIndex: 0,
                normalizedAbsoluteTick: 1,
                normalizedTickWithinMeasure: 1,
                normalizedTicksPerMeasure: 4
            )
        ])
        let stop = try #require(result.stopNotes.first)

        #expect(result.tabGrid.ticksPerMeasure == 960)
        #expect(stop.timeColumn.tickWithinMeasure == 240)
    }

    @Test("valid inexact source timing contributes its measure without a mark")
    func inexactProjectionStillContributesMeasure() {
        let result = support.layout(notes: [support.fallbackGridNote()], controls: [
            support.control(
                measureNumber: 99,
                originKind: .dtx,
                normalizedMeasureIndex: 2,
                normalizedAbsoluteTick: 15,
                normalizedTickWithinMeasure: 1,
                normalizedTicksPerMeasure: 7
            )
        ])

        #expect(result.tabGrid.ticksPerMeasure == 960)
        #expect(result.measures.count == 3)
        #expect(result.stopNotes.isEmpty)
    }

    @Test("a measure-three control adds no playable or note-derived artifact")
    func controlCanExtendMeasuresWithoutBecomingPlayable() {
        let result = support.layout(notes: [], controls: [
            support.control(
                originKind: .dtx,
                normalizedMeasureIndex: 2,
                normalizedAbsoluteTick: 8,
                normalizedTickWithinMeasure: 0,
                normalizedTicksPerMeasure: 4
            )
        ])

        #expect(result.measures.count == 3)
        #expect(result.noteHeads.isEmpty)
        #expect(result.stems.isEmpty)
        #expect(result.beams.isEmpty)
        #expect(result.flags.isEmpty)
        #expect(!result.hasPlayableContent)
    }
}
