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

        let terminalMeasure = try #require(
            terminalResult.snapshot.measures.first { $0.measureIndex == 0 }
        )
        let midChartMeasure = try #require(
            midChartResult.snapshot.measures.first { $0.measureIndex == 0 }
        )
        #expect(terminalMeasure.engravingSupport == .supported)
        #expect(terminalMeasure.engravingSupport == midChartMeasure.engravingSupport)
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
