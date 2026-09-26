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

    /// Normalized per-note signature for every engraved note head in a
    /// measure: timing (tick within measure + absolute tick) and the app
    /// semantics (note type, voice, lane, interval, duration ticks, dots,
    /// tuplet) join back through the snapshot via the note's event ID;
    /// voice and stem direction come from the engraved primitive itself.
    /// Geometry (`position`, `rowIndex`) is deliberately excluded -- the
    /// aggregate `MeasureArtifacts` parity above covers counts, and x/y
    /// differs between terminal and mid-chart placements by construction
    /// (different row offsets), so locking it here would make the test
    /// assert false negatives rather than semantic drift.
    private func noteSignatures(
        in result: FixtureRenderResult,
        measureIndex: Int
    ) -> [String] {
        let notesByID = Dictionary(
            uniqueKeysWithValues: result.snapshot.notes.map { ($0.eventID.rawValue, $0) }
        )
        return result.engraved.noteHeads
            .filter { $0.measureIndex == measureIndex }
            .sorted { headA, headB in
                let tickA = notesByID[headA.noteID]?.position.localTick ?? 0
                let tickB = notesByID[headB.noteID]?.position.localTick ?? 0
                return tickA == tickB ? headA.noteID < headB.noteID : tickA < tickB
            }
            .map { head in
                guard let note = notesByID[head.noteID] else {
                    return "MISSING-SNAPSHOT-NOTE-\(head.noteID)"
                }
                let tuplet = note.rhythm.tuplet.map { "\($0.actual):\($0.normal)" } ?? "-"
                return "t\(note.position.localTick)"
                    + "/abs\(note.position.absoluteTick)"
                    + "/\(note.noteType.rawValue)"
                    + "/v\(head.voice.rawValue)"
                    + "/lane=\(note.sourceLaneID ?? "-")"
                    + "/int=\(note.rhythm.baseInterval.rawValue)"
                    + "/dur=\(note.durationTicks)"
                    + "/dots=\(note.rhythm.dotCount)"
                    + "/tup=\(tuplet)"
                    + "/stem=\(head.stemDirection.rawValue)"
            }
    }

    private func artifacts(
        in result: FixtureRenderResult,
        measureIndex: Int
    ) -> MeasureArtifacts {
        let noteHeads = result.engraved.noteHeads.filter {
            $0.measureIndex == measureIndex
        }
        let noteHeadIDs = Set(noteHeads.map(\.noteID))

        return MeasureArtifacts(
            noteHeadCount: noteHeads.count,
            stemCount: result.engraved.stems.count {
                $0.noteIDs.contains(where: noteHeadIDs.contains)
            },
            beamCount: result.engraved.beams.count {
                $0.noteIDs.contains(where: noteHeadIDs.contains)
            },
            flagCount: result.engraved.flags.count {
                noteHeadIDs.contains($0.noteID)
            },
            printedRestCount: result.engraved.rests.count {
                $0.measureIndex == measureIndex
            }
        )
    }
}
