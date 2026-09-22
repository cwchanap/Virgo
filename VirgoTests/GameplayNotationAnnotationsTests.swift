import CoreGraphics
import DrumNotation
import Testing
@testable import Virgo

/// App-owned overlay annotations against the installed engraving: the feel
/// mark's first-measure pick across wrapped rows, warning suppression when a
/// flagged measure never reaches the engraving, and the chart-fatal label's
/// no-measure-number fallback.
@Suite("Gameplay notation annotations")
struct GameplayNotationAnnotationsTests {
    /// The one preparation route — same seam `GameplayNotationPreparer`
    /// drives in production; `.failed` fails the test.
    private func preparedEngraving(
        _ snapshot: RhythmLayoutSnapshot,
        minimumMeasureCount: Int = 1
    ) throws -> EngravedNotation {
        let prepared = GameplayNotationPreparer.prepare(GameplayNotationPreparationRequest(
            snapshot: snapshot,
            minimumMeasureCount: minimumMeasureCount,
            style: .gameplayDefault,
            notePositionOverrides: [:]
        ))
        guard case let .ready(engraved, _) = prepared else {
            Issue.record("Expected .ready, got \(prepared)")
            throw PreparationNotReady()
        }
        return engraved
    }

    private struct PreparationNotReady: Error {}

    private func layoutNote(id: Int, tick: Int, measureIndex: Int = 0) -> RhythmLayoutNote {
        RhythmLayoutNote(
            eventID: RhythmEventID(rawValue: id),
            sourceLaneID: nil,
            sourceChipID: nil,
            noteType: .snare,
            position: RhythmEventPosition(
                measureIndex: measureIndex,
                localTick: tick,
                absoluteTick: measureIndex * 960 + tick
            ),
            durationTicks: 240,
            rhythm: NotationRhythm(baseInterval: .quarter),
            tupletID: nil
        )
    }

    private func rhythmMeasure(
        index: Int,
        startTick: Int,
        durationTicks: Int = 960,
        support: RhythmEngravingSupport = .supported
    ) -> RhythmMeasure {
        RhythmMeasure(
            measureIndex: index,
            startTick: startTick,
            durationTicks: durationTicks,
            timeSignature: .fourFour,
            beatGroups: [RhythmBeatGroup(
                groupIndex: 0,
                startTick: 0,
                durationTicks: durationTicks,
                isResidual: false
            )],
            engravingSupport: support
        )
    }

    private func snapshot(
        measures: [RhythmMeasure],
        notes: [RhythmLayoutNote] = []
    ) throws -> RhythmLayoutSnapshot {
        try RhythmLayoutSnapshot(
            ticksPerWholeNote: 960,
            measures: measures,
            notes: notes,
            controls: [],
            rests: [],
            feel: .straight
        )
    }

    @Test("the feel mark anchors to the lowest row's leading measure across wraps")
    func feelMarkAnchorsToLowestRowLeadingMeasure() throws {
        // Four full-meter measures overflow one 900pt row: the (row, xOffset)
        // pick must consult both comparator arms — equal rows break on
        // xOffset, different rows break on rowIndex.
        let measures = (0..<4).map { rhythmMeasure(index: $0, startTick: $0 * 960) }
        let engraved = try preparedEngraving(
            try snapshot(measures: measures, notes: [layoutNote(id: 1, tick: 0)]),
            minimumMeasureCount: 4
        )
        // Non-vacuous: the engraving really did wrap to a second row.
        #expect(Set(engraved.measures.map(\.rowIndex)).count > 1)

        let annotations = GameplayNotationAnnotations.build(
            feel: .swing,
            expandedMeasures: measures,
            engraved: engraved,
            style: .gameplayDefault
        )

        let mark = try #require(annotations.feelMarks.first)
        #expect(annotations.feelMarks.count == 1)
        #expect(mark.rowIndex == 0)
        #expect(mark.position.y
            == (engraved.rows.first { $0.index == 0 }?.staffLineYs.last ?? 0)
                - NotationLayoutStyle.gameplayDefault.feelMarkVerticalOffset)
        // The anchor is the row-leading measure — never a later same-row one.
        let rowZeroMeasures = engraved.measures.filter { $0.rowIndex == 0 }
        let leadingX = try #require(rowZeroMeasures.map(\.xOffset).min())
        #expect(mark.position.x == leadingX
            + engraved.style.formatting.leadingMeasureInset
            + NotationLayoutStyle.gameplayDefault.feelMarkSize.width / 2)
    }

    @Test("warnings on measures absent from the engraving are suppressed")
    func warningsOnUnengravedMeasuresAreSuppressed() throws {
        let warningMeasure = rhythmMeasure(
            index: 0,
            startTick: 0,
            support: .warning([.indeterminateTerminalDuration])
        )
        // Phantom flags: these indices never enter the engraving, so the
        // warning builder must drop them instead of fabricating a position.
        let phantomWarning = rhythmMeasure(
            index: 3,
            startTick: 2_880,
            support: .warning([.indeterminateTerminalDuration])
        )
        let phantomUnsupported = rhythmMeasure(
            index: 4,
            startTick: 3_840,
            support: .unsupported([.ambiguousBeatGrouping])
        )
        let engraved = try preparedEngraving(try snapshot(
            measures: [warningMeasure],
            notes: [layoutNote(id: 1, tick: 0)]
        ))

        let annotations = GameplayNotationAnnotations.build(
            feel: .straight,
            expandedMeasures: [warningMeasure, phantomWarning, phantomUnsupported],
            engraved: engraved,
            style: .gameplayDefault
        )

        // Only the measure that really engraved materializes a warning.
        #expect(annotations.rhythmWarnings.map(\.scope) == [.measure(0)])
    }

    @Test("a chart-fatal warning without a source measure labels without a measure number")
    func chartFatalLabelWithoutMeasureNumber() throws {
        let diagnostic = try PersistedRhythmDiagnostic(
            code: .malformedTimeSignature,
            severity: .timingFatal
        )
        let warning = GameplayRhythmWarning.chartFatal(
            diagnostics: [diagnostic],
            position: .zero,
            size: NotationLayoutStyle.gameplayDefault.warningSize
        )

        #expect(warning.displayMeasureNumber == nil)
        #expect(
            warning.accessibilityLabel
                == "Unsupported chart timing: The chart time signature is malformed."
        )
        #expect(!warning.accessibilityLabel.contains("measure"))
    }
}
