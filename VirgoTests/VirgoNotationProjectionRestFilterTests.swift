import DrumNotation
import Testing
@testable import Virgo

/// HPA-164 Task 4: rest filtering at the pre-format projection — hidden
/// rests never reach the package, and rests in engraving-unsupported
/// measures are dropped before they can reserve measured ink. Split from
/// `VirgoNotationProjectionTests` to stay under SwiftLint's file-length
/// limit.
@Suite("Virgo Notation Projection Rest Filtering")
struct VirgoNotationProjectionRestFilterTests {
    private let ticksPerWholeNote = 960

    @Test("Hidden rests are filtered; printed and full-measure rest geometry survives")
    func hiddenRestsAreFilteredAndPrintedRestsSurvive() throws {
        let measure = makeMeasure(index: 0)
        let snapshot = try makeSnapshot(
            measures: [measure],
            rests: [
                makeRest(
                    measureIndex: 0,
                    localTick: 0,
                    durationTicks: 960,
                    voice: .upper,
                    interval: .full,
                    visibility: .printed
                ),
                makeRest(
                    measureIndex: 0,
                    localTick: 240,
                    durationTicks: 240,
                    voice: .lower,
                    interval: .quarter,
                    visibility: .hiddenSpacing
                ),
                makeRest(
                    measureIndex: 0,
                    localTick: 480,
                    durationTicks: 240,
                    voice: .upper,
                    interval: .quarter,
                    visibility: .hiddenDuplicate
                )
            ]
        )

        let input = try VirgoNotationProjection.resolvedNotation(
            snapshot: snapshot,
            expandedMeasures: [measure],
            notePositionOverrides: [:]
        )

        #expect(input.rests.count == 1)
        let rest = try #require(input.rests.first)
        #expect(rest.position.measureIndex == 0)
        #expect(rest.position.localTick == 0)
        #expect(rest.duration == .whole)
        #expect(rest.isFullMeasure)
    }

    @Test("Rests in engraving-unsupported measures never reach the package input")
    func unsupportedMeasureRestsAreFilteredAtProjection() throws {
        let supported = makeMeasure(index: 0)
        let unsupported = RhythmMeasure(
            measureIndex: 1,
            startTick: 960,
            durationTicks: 960,
            timeSignature: .fourFour,
            beatGroups: (0..<4).map {
                RhythmBeatGroup(groupIndex: $0, startTick: $0 * 240, durationTicks: 240, isResidual: false)
            },
            engravingSupport: .unsupported([.malformedMeasureLength])
        )
        // The chart's only rest is printed but lives in the unsupported
        // measure: Virgo suppresses its engraving, so the package must never
        // see it (it would widen the measured column for ink never painted).
        let rest = makeRest(
            measureIndex: 1,
            localTick: 480,
            durationTicks: 240,
            voice: .upper,
            interval: .quarter,
            visibility: .printed
        )
        let measures = [supported, unsupported]
        let snapshot = try makeSnapshot(measures: measures, rests: [rest])

        let input = try VirgoNotationProjection.resolvedNotation(
            snapshot: snapshot,
            expandedMeasures: measures,
            notePositionOverrides: [:]
        )
        #expect(input.rests.isEmpty)

        // Measure geometry is identical to the same chart with no rest.
        let withoutRest = try VirgoNotationProjection.resolvedNotation(
            snapshot: try makeSnapshot(measures: measures),
            expandedMeasures: measures,
            notePositionOverrides: [:]
        )
        let withoutRestGeometry = try NotationFormatter.format(
            withoutRest,
            style: VirgoNotationProjection.formattingStyle(rowWidth: 1_400, style: .gameplayDefault)
        )
        let withRestGeometry = try NotationFormatter.format(
            input,
            style: VirgoNotationProjection.formattingStyle(rowWidth: 1_400, style: .gameplayDefault)
        )
        #expect(withRestGeometry.measures.map(\.width) == withoutRestGeometry.measures.map(\.width))
        #expect(withRestGeometry.measures.map(\.xOffset) == withoutRestGeometry.measures.map(\.xOffset))
    }

    // MARK: - Fixtures

    /// Four-beat 4/4 measure at 960 ticks/whole-note: quarter = 240 ticks.
    private func makeMeasure(index: Int, startTick: Int = 0) -> RhythmMeasure {
        RhythmMeasure(
            measureIndex: index,
            startTick: startTick,
            durationTicks: 960,
            timeSignature: .fourFour,
            beatGroups: (0..<4).map {
                RhythmBeatGroup(groupIndex: $0, startTick: $0 * 240, durationTicks: 240, isResidual: false)
            },
            engravingSupport: .supported
        )
    }

    private func makeSnapshot(
        measures: [RhythmMeasure],
        notes: [RhythmLayoutNote] = [],
        rests: [RhythmLayoutRest] = [],
        controls: [RhythmLayoutControl] = []
    ) throws -> RhythmLayoutSnapshot {
        try RhythmLayoutSnapshot(
            ticksPerWholeNote: ticksPerWholeNote,
            measures: measures,
            notes: notes,
            controls: controls,
            rests: rests,
            feel: .straight
        )
    }

    private func makeRest(
        measureIndex: Int,
        localTick: Int,
        voice: NotationVoice,
        interval: NoteInterval,
        visibility: NotationRestVisibility
    ) -> RhythmLayoutRest {
        let durationTicks = ticksPerWholeNote / Self.tickDivisor(of: interval)
        return RhythmLayoutRest(
            position: RhythmEventPosition(
                measureIndex: measureIndex,
                localTick: localTick,
                absoluteTick: measureIndex * 960 + localTick
            ),
            durationTicks: durationTicks,
            voice: voice,
            rhythm: NotationRhythm(baseInterval: interval),
            visibility: visibility,
            tupletID: nil
        )
    }

    private static func tickDivisor(of interval: NoteInterval) -> Int {
        switch interval {
        case .full: return 1
        case .half: return 2
        case .quarter: return 4
        case .eighth: return 8
        case .sixteenth: return 16
        case .thirtysecond: return 32
        case .sixtyfourth: return 64
        }
    }
}
