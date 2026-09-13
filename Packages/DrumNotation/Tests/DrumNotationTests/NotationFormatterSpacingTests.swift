import CoreGraphics
import Testing
import DrumNotation

/// Tolerant position assert — derived X values may drift a last-ulp between
/// the formatter's accumulated arithmetic and the test's literals.
private func expectPosition(
    _ position: FormattedNotation.Position?,
    rowIndex: Int,
    x: CGFloat,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    #expect(position != nil, "no position resolved", sourceLocation: sourceLocation)
    #expect(position?.rowIndex == rowIndex, sourceLocation: sourceLocation)
    #expect(abs((position?.x ?? -1) - x) < 0.001, sourceLocation: sourceLocation)
}

@Suite("Notation formatter measured spacing")
struct NotationFormatterSpacingTests {
    /// X-black sixteenth run: `count` heads at `step * 120` ticks in
    /// `measureIndex`, one stem direction, no dots, fully beamed — adjacent
    /// intervals are the pure collision gap 10 + 8 + 10 = 28.
    private func runNotes(count: Int, measureIndex: Int, idBase: Int) -> [ResolvedNote] {
        (0..<count).map { step in
            Fixtures.makeNote(
                id: idBase + step,
                localTick: step * 120,
                staffStep: 3,
                duration: .sixteenth,
                measureIndex: measureIndex
            )
        }
    }

    /// Collision-gap constants for the sixteenth-run content at the default
    /// style. The vendored Bravura 1.392 X-black notehead paints 23.2pt wide
    /// at staff-space 20 (1.16 staff spaces), so the head half-width is 11.6
    /// — the plan's original 28pt pitch/490pt width assumed a 20pt head and
    /// is unreachable against the real font metrics; the decomposition below
    /// (leading inset + 15 collision intervals + last-head→end-anchor gap)
    /// is the regression that matters.
    static let headHalfWidth: CGFloat = 11.6
    static let collisionInterval: CGFloat = 2 * headHalfWidth + 8

    @Test("16-sixteenth 4/4 measure locks the collision-gap width; end anchor at 100 + width")
    func sixteenthRunMeasureWidthIs490() throws {
        let notes = runNotes(count: 16, measureIndex: 0, idBase: 0)
        let document = try Fixtures.document(notes: notes, rests: [], controls: [])
        let notation = try Fixtures.format(document)

        let measure = try #require(notation.measures.first)
        #expect(measure.rowIndex == 0)
        #expect(measure.xOffset == 100)
        #expect(measure.columns.count == 17)
        // leading inset 52 + 15 X-black collision intervals + last head → end
        // anchor gap (11.6 + 8).
        let expectedWidth: CGFloat = 52 + 15 * Self.collisionInterval + (Self.headHalfWidth + 8)
        #expect(abs(measure.width - expectedWidth) < 0.001)
        // Note columns pace uniformly; the end anchor closes with the shorter
        // last-head → end-anchor gap.
        for (step, column) in measure.columns.dropLast().enumerated() {
            let expected = 152 + CGFloat(step) * Self.collisionInterval
            #expect(abs(column.logicalColumnX - expected) < 0.001)
        }
        let endAnchor = try #require(measure.columns.last)
        #expect(abs(endAnchor.logicalColumnX - (100 + expectedWidth)) < 0.001)
        // A measure starting at X=100 ends at X = 100 + width, safely inside the 900pt row.
        #expect(abs(measure.xOffset + measure.width - (100 + expectedWidth)) < 0.001)
        expectPosition(
            notation.position(measureIndex: 0, localTick: 1920),
            rowIndex: 0,
            x: 100 + expectedWidth
        )
    }

    @Test("dense run expands locally without imposing its scale on a sparse neighbor")
    func denseMeasureDoesNotImposeScaleOnSparseNeighbor() throws {
        let notes = runNotes(count: 16, measureIndex: 0, idBase: 0) + [
            Fixtures.makeNote(id: 100, localTick: 0, staffStep: 3, measureIndex: 1),
            Fixtures.makeNote(id: 101, localTick: 960, staffStep: 3, measureIndex: 1)
        ]
        let document = try Fixtures.document(
            measures: [Fixtures.measure(), Fixtures.measure(index: 1, startTick: 1920)],
            notes: notes,
            rests: [],
            controls: []
        )
        let notation = try Fixtures.format(document)
        let dense = try #require(notation.measures.first { $0.index == 0 })
        let sparse = try #require(notation.measures.first { $0.index == 1 })

        // The dense run keeps its collision pitch (11.6 + 8 + 11.6 = 31.2)…
        #expect(abs(dense.columns[1].logicalColumnX - dense.columns[0].logicalColumnX - Self.collisionInterval) < 0.001)
        // …while the sparse neighbor paces by its own rhythm (half note = 100pt),
        // never the dense run's scale.
        #expect(abs(sparse.columns[1].logicalColumnX - sparse.columns[0].logicalColumnX - 100) < 0.001)
        #expect(abs(sparse.columns[2].logicalColumnX - sparse.columns[1].logicalColumnX - 100) < 0.001)
        #expect(abs(sparse.width - 252) < 0.001)
    }

    @Test("full-measure rest centers in the content span once width is known")
    func fullMeasureRestIsCenteredOnceWidthIsKnown() throws {
        let fullMeasure = ResolvedRest(
            id: 3,
            position: NotationTickPosition(measureIndex: 0, localTick: 0),
            duration: .whole,
            dotCount: 0,
            isFullMeasure: true
        )
        let notation = try Fixtures.format(try Fixtures.document(notes: [], rests: [fullMeasure], controls: []))
        let measure = try #require(notation.measures.first)

        // Columns [0, 1920]: anchor at 52, rhythmic gap 50 * 1920 * 4 / 1920 = 200 → width 252.
        #expect(measure.columns.map(\.localTick) == [0, 1920])
        #expect(abs(measure.width - 252) < 0.001)
        // The timing anchor stays the logical column X (sheet-local 152)…
        #expect(notation.position(measureIndex: 0, localTick: 0) == FormattedNotation.Position(rowIndex: 0, x: 152))
        // …while the visual centers in the content span [152, 352].
        let rest = try #require(try Fixtures.column(notation, localTick: 0).rest)
        #expect(abs(rest.visualX - 252) < 0.001)
    }

    @Test("greedy packing fits measures per row with measure spacing and wraps cleanly")
    func greedyRowPackingUsesMeasureSpacing() throws {
        let measures = [
            Fixtures.measure(),
            Fixtures.measure(index: 1, startTick: 1920),
            Fixtures.measure(index: 2, startTick: 3840),
            Fixtures.measure(index: 3, startTick: 5760)
        ]
        let document = try Fixtures.document(measures: measures, notes: [], rests: [], controls: [])
        let notation = try Fixtures.format(document)
        // Empty 4/4 measures are 252 wide: rows hold three (100, 364, 628) before
        // 628 + 252 + 12 would cross the 900pt row.
        #expect(notation.measures.map(\.rowIndex) == [0, 0, 0, 1])
        #expect(notation.measures.map(\.xOffset) == [100, 364, 628, 100])
    }

    @Test("over-wide measure keeps natural width alone on a row")
    func overWideMeasureKeepsNaturalWidthAlone() throws {
        // 31 intervals × (11.6 + 8 + 11.6) + (11.6 + 8) + 52 leading = 1038.8 > the 900pt row.
        let measures = [Fixtures.measure(durationTicks: 3840), Fixtures.measure(index: 1, startTick: 3840)]
        let document = try Fixtures.document(
            measures: measures,
            notes: runNotes(count: 32, measureIndex: 0, idBase: 0),
            rests: [],
            controls: []
        )
        let notation = try Fixtures.format(document)

        let wide = try #require(notation.measures.first)
        #expect(wide.rowIndex == 0 && wide.xOffset == 100)
        #expect(wide.width > 900)
        #expect(abs(wide.width - (52 + 31 * Self.collisionInterval + Self.headHalfWidth + 8)) < 0.001)
        let after = try #require(notation.measures.last)
        #expect(after.rowIndex == 1 && after.xOffset == 100)
    }

    @Test("reflow at a wider row keeps IDs and ticks; rows and lookup follow the new packing")
    func reflowIdentityAcrossRowWidths() throws {
        let measures = [Fixtures.measure(), Fixtures.measure(index: 1, startTick: 1920)]
        let notes = runNotes(count: 16, measureIndex: 0, idBase: 0) + runNotes(count: 16, measureIndex: 1, idBase: 100)
        let document = try Fixtures.document(measures: measures, notes: notes, rests: [], controls: [])

        let narrow = try NotationFormatter.format(document, style: .virgoDefault)
        let wide = try NotationFormatter.format(document, style: NotationFormattingStyle(availableRowWidth: 1200))

        // Identity: same measure indices, widths, ticks and note IDs at both widths.
        for (narrowMeasure, wideMeasure) in zip(narrow.measures, wide.measures) {
            #expect(narrowMeasure.index == wideMeasure.index)
            #expect(narrowMeasure.width == wideMeasure.width)
            #expect(narrowMeasure.columns.map(\.localTick) == wideMeasure.columns.map(\.localTick))
            for (narrowColumn, wideColumn) in zip(narrowMeasure.columns, wideMeasure.columns) {
                #expect(narrowColumn.noteHeads.map(\.noteID) == wideColumn.noteHeads.map(\.noteID))
            }
        }
        // Row assignment may change: at 900 the second ~539.6-wide measure
        // wraps (651.6 + 539.6 > 900); at 1200 both measures share row 0
        // (651.6 + 539.6 = 1191.2 ≤ 1200).
        #expect(narrow.measures[1].rowIndex == 1 && narrow.measures[1].xOffset == 100)
        #expect(wide.measures[1].rowIndex == 0)
        #expect(abs(wide.measures[1].xOffset - 651.6) < 0.001)
        // Lookup follows the new row without changing anchors.
        expectPosition(narrow.position(measureIndex: 1, localTick: 0), rowIndex: 1, x: 152)
        expectPosition(wide.position(measureIndex: 1, localTick: 0), rowIndex: 0, x: 703.6)
        expectPosition(narrow.position(measureIndex: 1, localTick: 60), rowIndex: 1, x: 167.6)
        expectPosition(wide.position(measureIndex: 1, localTick: 60), rowIndex: 0, x: 719.2)
    }
}

@Suite("Notation formatter tick lookup")
struct NotationFormatterLookupTests {
    private let interval = NotationFormatterSpacingTests.collisionInterval
    private let endGap = NotationFormatterSpacingTests.headHalfWidth + 8

    private func denseRunNotation() throws -> FormattedNotation {
        try Fixtures.format(try Fixtures.document(
            notes: (0..<16).map { step in
                Fixtures.makeNote(id: step, localTick: step * 120, staffStep: 3, duration: .sixteenth)
            },
            rests: [],
            controls: []
        ))
    }

    @Test("exact anchors resolve to their logical column X")
    func exactAnchorsResolveExactly() throws {
        let notation = try denseRunNotation()
        expectPosition(notation.position(measureIndex: 0, localTick: 0), rowIndex: 0, x: 152)
        expectPosition(notation.position(measureIndex: 0, localTick: 480), rowIndex: 0, x: 152 + 4 * interval)
        expectPosition(notation.position(measureIndex: 0, localTick: 1920), rowIndex: 0, x: 639.6)
    }

    @Test("between anchors the lookup interpolates linearly inside the measure")
    func betweenAnchorsInterpolates() throws {
        let notation = try denseRunNotation()
        expectPosition(notation.position(measureIndex: 0, localTick: 60), rowIndex: 0, x: 152 + interval / 2)
        expectPosition(notation.position(measureIndex: 0, localTick: 30), rowIndex: 0, x: 152 + interval / 4)
        // Midpoint of the last interval (last head → end anchor).
        expectPosition(
            notation.position(measureIndex: 0, localTick: 1860),
            rowIndex: 0,
            x: 152 + 15 * interval + endGap / 2
        )
    }

    @Test("empty measures resolve through their start and end anchors")
    func emptyMeasuresResolveThroughAnchors() throws {
        let notation = try Fixtures.format(try Fixtures.document(
            measures: [Fixtures.measure(), Fixtures.measure(index: 1, startTick: 1920)],
            notes: [],
            rests: [],
            controls: []
        ))
        // Measure 1 packs at X=364 (100 + 252 + 12 spacing); its anchors are 416/616.
        #expect(notation.position(measureIndex: 1, localTick: 0) == FormattedNotation.Position(rowIndex: 0, x: 416))
        #expect(notation.position(measureIndex: 1, localTick: 960) == FormattedNotation.Position(rowIndex: 0, x: 516))
        #expect(notation.position(measureIndex: 1, localTick: 1920) == FormattedNotation.Position(rowIndex: 0, x: 616))
    }

    @Test("non-finite and out-of-range ticks return nil; edge drift clamps to the boundary anchor")
    func invalidTicksReturnNilAndEdgeDriftClamps() throws {
        let notation = try denseRunNotation()
        #expect(notation.position(measureIndex: 0, localTick: .infinity) == nil)
        #expect(notation.position(measureIndex: 0, localTick: -.infinity) == nil)
        #expect(notation.position(measureIndex: 0, localTick: .nan) == nil)
        #expect(notation.position(measureIndex: 0, localTick: -1) == nil)
        #expect(notation.position(measureIndex: 0, localTick: 1921) == nil)
        #expect(notation.position(measureIndex: 7, localTick: 0) == nil)
        // Tiny floating-point drift at the measure edges clamps inward.
        expectPosition(notation.position(measureIndex: 0, localTick: -1e-9), rowIndex: 0, x: 152)
        expectPosition(notation.position(measureIndex: 0, localTick: 1920 + 1e-9), rowIndex: 0, x: 639.6)
    }
}
