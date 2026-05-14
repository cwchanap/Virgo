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
        let style = NotationLayoutStyle.gameplayDefault
        for beam in layout.beams {
            #expect(abs(beam.start.y - beam.end.y) < 0.001, "Beam should be horizontal")
            // Verify the beam picks the correct extremum (min for up-stems)
            let beamHeads = layout.noteHeads.filter { beam.noteHeadIDs.contains($0.id) }
            for head in beamHeads where head.stemDirection == .up {
                #expect(
                    beam.start.y <= head.position.y - style.stemLength + 0.001,
                    "Up-stem beam Y should be at or above note head minus stem length"
                )
            }
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

    @Test("four 8th-note measures at default row width span multiple rows (baseline)")
    func fourEighthNoteMeasuresAtDefaultRowWidthSpanMultipleRows() {
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

    @Test("down-stem beams are horizontal and at the correct extremum")
    func downStemBeamsAreHorizontalAtCorrectExtremum() throws {
        // Crash drums are above line5 and default to .down stem direction.
        // This tests the .down branch of sharedBeamY (candidates.max()).
        let notes = [
            Note(interval: .eighth, noteType: .crash, measureNumber: 1, measureOffset: 0),
            Note(interval: .eighth, noteType: .crash, measureNumber: 1, measureOffset: 0.125),
            Note(interval: .eighth, noteType: .crash, measureNumber: 1, measureOffset: 0.25),
            Note(interval: .eighth, noteType: .crash, measureNumber: 1, measureOffset: 0.375)
        ]
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
        )

        let beam = try #require(layout.beams.first, "Down-stem crash eighths should form a beam")
        #expect(abs(beam.start.y - beam.end.y) < 0.001, "Down-stem beam should be horizontal")

        let style = NotationLayoutStyle.gameplayDefault
        let beamHeads = layout.noteHeads.filter { beam.noteHeadIDs.contains($0.id) }
        #expect(!beamHeads.isEmpty)
        for head in beamHeads {
            #expect(head.stemDirection == .down, "Crash notes should have .down stem direction")
            #expect(
                beam.start.y >= head.position.y + style.stemLength - 0.001,
                "Down-stem beam Y should be at or below note head plus stem length"
            )
        }
    }

    @Test("secondary beam levels stack consistently above the primary beam for up-stems")
    func secondaryBeamStacksAbovePrimaryBeamForUpStems() throws {
        // All snare (upper voice, up-stem) with mixed durations.
        // 16th notes produce beams at levels 0 and 1; 8th notes only at level 0.
        let notes = [
            Note(interval: .sixteenth, noteType: .snare, measureNumber: 1, measureOffset: 0),
            Note(interval: .sixteenth, noteType: .snare, measureNumber: 1, measureOffset: 0.0625),
            Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: 0.125),
            Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: 0.1875)
        ]
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
        )

        #expect(
            !layout.beams.isEmpty,
            "Should produce beams — got \(layout.beams.count) beams: \(layout.beams.map { "L\($0.level)" })"
        )

        let level0Beams = layout.beams.filter { $0.level == 0 }
        let level1Beams = layout.beams.filter { $0.level == 1 }
        #expect(!level0Beams.isEmpty, "Should have at least one primary beam (level 0)")

        // If level 1 beams exist, they must stack above (lower Y) the primary beam
        if !level1Beams.isEmpty {
            let level0Y = level0Beams[0].start.y
            for beam in level1Beams {
                #expect(
                    beam.start.y < level0Y - 0.001,
                    "Level 1 beam Y (\(beam.start.y)) must be above level 0 Y (\(level0Y)) for up-stems"
                )
            }
        }
    }

    @Test("secondary beam levels stack consistently below the primary beam for down-stems")
    func secondaryBeamStacksBelowPrimaryBeamForDownStems() throws {
        // Crash notes default to down-stem direction.
        let notes = [
            Note(interval: .sixteenth, noteType: .crash, measureNumber: 1, measureOffset: 0),
            Note(interval: .sixteenth, noteType: .crash, measureNumber: 1, measureOffset: 0.125)
        ]
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
        )

        let level0Beam = try #require(
            layout.beams.first { $0.level == 0 },
            "Should have a primary beam (level 0)"
        )
        let level1Beam = try #require(
            layout.beams.first { $0.level == 1 },
            "Should have a secondary beam (level 1)"
        )

        // For down-stems: higher Y = lower on screen; secondary beam must be below primary.
        #expect(
            level1Beam.start.y > level0Beam.start.y + 0.001,
            "Secondary beam Y (\(level1Beam.start.y)) must be below primary beam Y (\(level0Beam.start.y)) for down-stems"
        )
    }

    @Test("remaining flags for beamed notes originate at beam-adjusted stem end")
    func remainingFlagsOriginateAtBeamAdjustedStemEnd() throws {
        // 16th + 32nd + 16th — the single 32nd note can't form a level 2 beam
        // segment (needs ≥ 2 consecutive 32nd notes). It gets covered at levels
        // 0 and 1, but has 3 total flags → 1 remaining flag that must be positioned
        // at the beam-adjusted stem end, not the default stem length.
        let notes = [
            Note(interval: .sixteenth, noteType: .snare, measureNumber: 1, measureOffset: 0),
            Note(interval: .thirtysecond, noteType: .snare, measureNumber: 1, measureOffset: 0.0625),
            Note(interval: .sixteenth, noteType: .snare, measureNumber: 1, measureOffset: 0.125)
        ]
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
        )

        let flags = layout.flags
        #expect(
            !flags.isEmpty,
            "Isolated 32nd note should have 1 remaining flag beyond beams — beams: \(layout.beams.map { "L\($0.level)(\($0.noteHeadIDs.count))" })"
        )

        for flag in flags {
            let head = layout.noteHeads.first { $0.id == flag.noteHeadID }
            let stem = layout.stems.first { $0.noteHeadIDs.contains(flag.noteHeadID) }
            if let head = head, let stem = stem {
                // The flag origin should be near the beam-adjusted stem end, not at
                // the default stem-length position.
                let distance = abs(flag.origin.y - stem.end.y)
                #expect(
                    distance < GameplayLayout.flagHeight * 5,
                    "Flag at Y=\(flag.origin.y) should be near stem end Y=\(stem.end.y) (distance=\(distance))"
                )
            }
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
