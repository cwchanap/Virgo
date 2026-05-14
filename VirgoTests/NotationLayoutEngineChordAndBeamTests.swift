import Testing
import SwiftUI
@testable import Virgo

@Suite("Notation Layout Engine – Chord & Beam Tests")
struct NotationLayoutEngineChordAndBeamTests {

    @Test("beams are horizontal across notes at different staff positions")
    func beamsAreHorizontalAcrossDifferentPositions() throws {
        let notes = [
            Note(interval: .eighth, noteType: .bass, measureNumber: 1, measureOffset: 0),
            Note(interval: .eighth, noteType: .hiHatPedal, measureNumber: 1, measureOffset: 0.125),
            Note(interval: .eighth, noteType: .bass, measureNumber: 1, measureOffset: 0.25),
            Note(interval: .eighth, noteType: .hiHatPedal, measureNumber: 1, measureOffset: 0.375)
        ]
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
        )

        #expect(!layout.beams.isEmpty, "Run of beamable lower-voice notes should form a beam")
        for beam in layout.beams {
            #expect(abs(beam.start.y - beam.end.y) < 0.001, "Beam should be horizontal")
        }
    }

    @Test("beam stays horizontal regardless of staff-position order")
    func beamHorizontalWithReversedPositionOrder() throws {
        let notes = [
            Note(interval: .eighth, noteType: .hiHatPedal, measureNumber: 1, measureOffset: 0),
            Note(interval: .eighth, noteType: .bass, measureNumber: 1, measureOffset: 0.125)
        ]
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
        )

        let beam = try #require(layout.beams.first)
        #expect(abs(beam.start.y - beam.end.y) < 0.001)
    }

    @Test("default 900pt row width fits only one 8th-note measure per row (baseline)")
    func defaultRowWidthFitsOneEighthNoteMeasurePerRow() {
        let notes = (1...4).flatMap { measure -> [Note] in
            (0..<8).map { offsetIndex in
                Note(
                    interval: .eighth,
                    noteType: .snare,
                    measureNumber: measure,
                    measureOffset: Double(offsetIndex) / 8.0
                )
            }
        }
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
        )

        let maxRow = layout.measures.map(\.row).max() ?? 0
        #expect(maxRow >= 1, "Sanity: 4 measures at 900pt cap should span multiple rows")
    }

    @Test("wider rowWidth packs more measures per row")
    func widerRowWidthPacksMoreMeasuresPerRow() {
        let notes = (1...4).flatMap { measure -> [Note] in
            (0..<8).map { offsetIndex in
                Note(
                    interval: .eighth,
                    noteType: .snare,
                    measureNumber: measure,
                    measureOffset: Double(offsetIndex) / 8.0
                )
            }
        }
        let wideStyle = NotationLayoutStyle.gameplayDefault.with(rowWidth: 2000)
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour, style: wideStyle)
        )

        let rowCount = (layout.measures.map(\.row).max() ?? 0) + 1
        #expect(rowCount == 1, "All four 8th-note measures should pack into one row at 2000pt rowWidth")
    }

    @Test("adjacent rows do not vertically overlap with default drum content")
    func adjacentRowsDoNotOverlapWithDefaultDrumContent() {
        let notes = (1...4).flatMap { measure -> [Note] in
            var arr: [Note] = []
            for offsetIndex in 0..<8 {
                arr.append(
                    Note(
                        interval: .sixtyfourth,
                        noteType: .bass,
                        measureNumber: measure,
                        measureOffset: Double(offsetIndex) / 64.0
                    )
                )
            }
            arr.append(
                Note(interval: .quarter, noteType: .crash, measureNumber: measure, measureOffset: 0)
            )
            return arr
        }
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
        )
        let rows = Set(layout.measures.map(\.row)).sorted()
        #expect(rows.count >= 2, "Test setup should produce multiple rows")

        for row in rows.dropLast() {
            let bottom = rowContentMaxY(layout: layout, row: row)
            let nextTop = rowContentMinY(layout: layout, row: row + 1)
            #expect(
                bottom < nextTop,
                "Row content overlap detected; investigate row pitch sizing"
            )
        }
    }

    @Test("same-voice chord with mixed default stem directions shares one stem")
    func sameVoiceChordWithMixedDirectionsSharesOneStem() throws {
        let notes = [
            Note(interval: .quarter, noteType: .crash, measureNumber: 1, measureOffset: 0),
            Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0)
        ]
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
        )

        #expect(
            layout.stems.count == 1,
            "Mixed-direction same-voice chord should share one stem"
        )
        let stem = try #require(layout.stems.first)
        #expect(stem.noteHeadIDs.count == 2)
    }

    @Test("same-voice chord with mixed default directions also yields no split beam group")
    func sameVoiceChordWithMixedDirectionsYieldsSingleBeamGroup() throws {
        let notes = [
            Note(interval: .eighth, noteType: .crash, measureNumber: 1, measureOffset: 0),
            Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: 0),
            Note(interval: .eighth, noteType: .crash, measureNumber: 1, measureOffset: 0.125),
            Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: 0.125)
        ]
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
        )

        #expect(layout.beams.count == 1, "Unified chords should form a single beam group")
        #expect(layout.stems.count == 2, "One stem per beat (each shared by both chord notes)")
    }

    @Test("stems extend to the shared beam Y when notes differ in pitch")
    func stemsExtendToSharedBeamY() throws {
        let notes = [
            Note(interval: .eighth, noteType: .bass, measureNumber: 1, measureOffset: 0),
            Note(interval: .eighth, noteType: .hiHatPedal, measureNumber: 1, measureOffset: 0.125)
        ]
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
        )

        let beam = try #require(layout.beams.first)
        #expect(layout.stems.count == 2)
        for stem in layout.stems {
            #expect(abs(stem.end.y - beam.start.y) < 0.001, "Stem must reach unified beam Y")
        }
    }

    private func rowContentMaxY(layout: NotationLayout, row: Int) -> CGFloat {
        let heads = layout.noteHeads.filter { $0.row == row }
        let headIDs = Set(heads.map(\.id))
        var ys: [CGFloat] = []
        for head in heads {
            ys.append(head.position.y + GameplayLayout.drumSymbolFontSize / 2)
        }
        for stem in layout.stems where stem.noteHeadIDs.contains(where: { headIDs.contains($0) }) {
            ys.append(max(stem.start.y, stem.end.y))
        }
        for beam in layout.beams where beam.noteHeadIDs.contains(where: { headIDs.contains($0) }) {
            ys.append(max(beam.start.y, beam.end.y) + beam.thickness / 2)
        }
        for flag in layout.flags where headIDs.contains(flag.noteHeadID) {
            ys.append(flag.origin.y + GameplayLayout.flagHeight)
        }
        for ledger in layout.ledgerLines where ledger.row == row {
            ys.append(max(ledger.start.y, ledger.end.y))
        }
        return ys.max() ?? -.infinity
    }

    private func rowContentMinY(layout: NotationLayout, row: Int) -> CGFloat {
        let heads = layout.noteHeads.filter { $0.row == row }
        let headIDs = Set(heads.map(\.id))
        var ys: [CGFloat] = []
        for head in heads {
            ys.append(head.position.y - GameplayLayout.drumSymbolFontSize / 2)
        }
        for stem in layout.stems where stem.noteHeadIDs.contains(where: { headIDs.contains($0) }) {
            ys.append(min(stem.start.y, stem.end.y))
        }
        for beam in layout.beams where beam.noteHeadIDs.contains(where: { headIDs.contains($0) }) {
            ys.append(min(beam.start.y, beam.end.y) - beam.thickness / 2)
        }
        for flag in layout.flags where headIDs.contains(flag.noteHeadID) {
            ys.append(flag.origin.y - GameplayLayout.flagHeight)
        }
        for ledger in layout.ledgerLines where ledger.row == row {
            ys.append(min(ledger.start.y, ledger.end.y))
        }
        return ys.min() ?? .infinity
    }
}
