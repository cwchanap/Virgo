import Testing
@testable import Virgo

@Suite("Final measure engraving", .serialized)
@MainActor
struct FinalMeasureEngravingTests {
    private struct MeasureArtifacts: Equatable {
        let noteHeadCount: Int
        let stemCount: Int
        let beamCount: Int
        let flagCount: Int
        let printedRestCount: Int
    }

    @Test("a terminal measure engraves exactly like the same measure mid-chart")
    func terminalMeasureMatchesMidChart() throws {
        let upper = DrumTabFixture.line(
            measure: 0,
            lane: "11",
            at: [1, 2, 3, 4, 8, 12],
            total: 16
        )
        let lower = DrumTabFixture.line(
            measure: 0,
            lane: "13",
            at: [2, 4, 8, 12],
            total: 16
        )
        let terminal = DrumTabFixture(
            name: "hpa-419-terminal",
            dtx: DrumTabFixtureCatalog.chart([upper, lower])
        )
        let midChart = DrumTabFixture(
            name: "hpa-419-mid-chart",
            dtx: DrumTabFixtureCatalog.chart([
                upper,
                lower,
                DrumTabFixture.line(measure: 1, lane: "11", at: [0], total: 1),
                DrumTabFixture.line(measure: 1, lane: "13", at: [0], total: 1)
            ])
        )

        let terminalResult = try DrumTabFixtureHarness.render(terminal)
        let midChartResult = try DrumTabFixtureHarness.render(midChart)
        let expected = MeasureArtifacts(
            noteHeadCount: 10,
            stemCount: 10,
            beamCount: 2,
            flagCount: 1,
            printedRestCount: 2
        )

        #expect(artifacts(in: midChartResult, measureIndex: 0) == expected)
        #expect(artifacts(in: terminalResult, measureIndex: 0) == expected)
        #expect(
            artifacts(in: terminalResult, measureIndex: 0)
                == artifacts(in: midChartResult, measureIndex: 0)
        )

        // Aggregate counts can pass when two notes swap intervals, dots, or
        // tuplet membership -- the totals match but the per-note semantics
        // drift. Pin a normalized per-note signature so timing, duration
        // inference, dots, tuplet assignment, and voice/lane routing must
        // match element-by-element between the terminal and mid-chart
        // renderings of the same measure.
        #expect(
            noteSignatures(in: terminalResult, measureIndex: 0)
                == noteSignatures(in: midChartResult, measureIndex: 0),
            "per-note signatures in measure 0 must match between terminal and mid-chart"
        )

        let terminalMeasure = try #require(
            terminalResult.snapshot.measures.first { $0.measureIndex == 0 }
        )
        let midChartMeasure = try #require(
            midChartResult.snapshot.measures.first { $0.measureIndex == 0 }
        )
        #expect(terminalMeasure.engravingSupport == .supported)
        #expect(terminalMeasure.engravingSupport == midChartMeasure.engravingSupport)
    }

    /// Normalized per-note signature for every note head in a measure:
    /// timing (tick within measure + absolute layout tick), drum lane
    /// (drumType + voice + sourceLaneID), inferred interval, resolved
    /// duration ticks, augmentation dots, tuplet ratio, and stem direction.
    /// Geometry (`position`, `row`) is deliberately excluded -- the
    /// aggregate `MeasureArtifacts` parity above covers counts, and x/y
    /// differs between terminal and mid-chart placements by construction
    /// (different row offsets), so locking it here would make the test
    /// assert false negatives rather than semantic drift.
    private func noteSignatures(
        in result: FixtureRenderResult,
        measureIndex: Int
    ) -> [String] {
        result.layout.noteHeads
            .filter { $0.timeColumn.measureIndex == measureIndex }
            .sorted {
                ($0.timeColumn.tickWithinMeasure,
                 $0.timeColumn.absoluteLayoutTick,
                 $0.catalogOrder,
                 $0.id)
                    < ($1.timeColumn.tickWithinMeasure,
                       $1.timeColumn.absoluteLayoutTick,
                       $1.catalogOrder,
                       $1.id)
            }
            .map { head in
                let tuplet = head.rhythm.tuplet.map { "\($0.actual):\($0.normal)" } ?? "-"
                return "t\(head.timeColumn.tickWithinMeasure)"
                    + "/abs\(head.timeColumn.absoluteLayoutTick)"
                    + "/\(head.drumType.description)"
                    + "/v\(head.voice.rawValue)"
                    + "/lane=\(head.sourceLaneID ?? "-")"
                    + "/int=\(head.interval.rawValue)"
                    + "/dur=\(head.rhythmDurationTicks.map(String.init) ?? "-")"
                    + "/dots=\(head.rhythm.dotCount)"
                    + "/tup=\(tuplet)"
                    + "/stem=\(head.stemDirection.rawValue)"
            }
    }

    private func artifacts(
        in result: FixtureRenderResult,
        measureIndex: Int
    ) -> MeasureArtifacts {
        let noteHeads = result.layout.noteHeads.filter {
            $0.timeColumn.measureIndex == measureIndex
        }
        let noteHeadIDs = Set(noteHeads.map(\.id))

        return MeasureArtifacts(
            noteHeadCount: noteHeads.count,
            stemCount: result.layout.stems.count {
                $0.noteHeadIDs.contains(where: noteHeadIDs.contains)
            },
            beamCount: result.layout.beams.count {
                $0.noteHeadIDs.contains(where: noteHeadIDs.contains)
            },
            flagCount: result.layout.flags.count {
                noteHeadIDs.contains($0.noteHeadID)
            },
            printedRestCount: result.layout.rests.count {
                $0.measureIndex == measureIndex && $0.isPrinted
            }
        )
    }
}
