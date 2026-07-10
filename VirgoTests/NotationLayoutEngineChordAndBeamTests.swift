import Testing
import SwiftUI
@testable import Virgo

@Suite("Notation Layout Engine – Chord & Beam Tests")
// swiftlint:disable:next type_body_length
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
        let wideStyle = NotationLayoutStyle.gameplayDefault.with(rowWidth: 2_500)
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour, style: wideStyle)
        )

        let rowCount = (layout.measures.map(\.row).max() ?? 0) + 1
        #expect(rowCount == 1, "All four 8th-note measures should pack into one row at 2500pt rowWidth")
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

    @Test("same-voice chord with one catalog direction shares one stem")
    func sameVoiceChordWithOneCatalogDirectionSharesOneStem() throws {
        let notes = [
            Note(interval: .quarter, noteType: .crash, measureNumber: 1, measureOffset: 0),
            Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0)
        ]
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
        )

        #expect(
            layout.stems.count == 1,
            "Same-direction same-voice chord should share one stem"
        )
        let stem = try #require(layout.stems.first)
        #expect(stem.noteHeadIDs.count == 2)
    }

    @Test("same-voice chord with one catalog direction yields one beam group")
    func sameVoiceChordWithOneCatalogDirectionYieldsSingleBeamGroup() throws {
        let notes = [
            Note(interval: .eighth, noteType: .crash, measureNumber: 1, measureOffset: 0),
            Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: 0),
            Note(interval: .eighth, noteType: .crash, measureNumber: 1, measureOffset: 0.125),
            Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: 0.125)
        ]
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
        )

        #expect(layout.beams.count == 1, "Same-direction chords should form one beam group")
        #expect(layout.stems.count == 2, "One stem per beat (each shared by both chord notes)")
    }

    @Test("catalog direction keeps chord and adjacent solo note in one beam run")
    func catalogDirectionKeepsChordAndAdjacentSoloInOneBeamRun() throws {
        // Crash and snare share the catalog-authored upper-voice .up direction,
        // so the chord and adjacent solo snare remain in one beam group.
        let notes = [
            Note(interval: .eighth, noteType: .crash, measureNumber: 1, measureOffset: 0),
            Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: 0),
            Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: 0.125)
        ]
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
        )

        #expect(
            layout.beams.count == 1,
            "Chord + solo note in same voice should form a single beam, got \(layout.beams.count) beams"
        )

        // All upper-voice note heads preserve their catalog-authored direction.
        let upperHeads = layout.noteHeads.filter { $0.voice == .upper }
        let directions = Set(upperHeads.map(\.stemDirection))
        #expect(
            directions.count == 1,
            "All upper-voice notes should preserve one catalog direction, got \(directions)"
        )

        // Verify the crash note head is part of the beam.
        let beam = try #require(layout.beams.first)
        let crashHead = try #require(layout.noteHeads.first { $0.drumType == .crash })
        #expect(
            beam.noteHeadIDs.contains(crashHead.id),
            "Crash note head should be included in the beam"
        )
    }

    @Test("beam run preserves catalog-authored upper directions")
    func beamRunPreservesCatalogAuthoredUpperDirections() throws {
        let notes = [
            Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: 0),
            Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: 0.125),
            Note(interval: .eighth, noteType: .hiHat, measureNumber: 1, measureOffset: 0.25)
        ]
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
        )

        let beam = try #require(layout.beams.first, "Should form a beam across all three notes")
        let heads = layout.noteHeads.filter { beam.noteHeadIDs.contains($0.id) }
        let directions = Set(heads.map(\.stemDirection))
        #expect(
            directions == [.up],
            "All notes in beam run should preserve catalog-authored .up, got \(directions)"
        )
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
            #expect(abs(stem.end.y - beam.start.y) < 0.001, "Stem must reach shared beam Y")
        }
    }

    @Test("down-stem beams are horizontal and at the correct extremum")
    func downStemBeamsAreHorizontalAtCorrectExtremum() throws {
        // Bass drums use the catalog-authored .down stem direction.
        let notes = [
            Note(interval: .eighth, noteType: .bass, measureNumber: 1, measureOffset: 0),
            Note(interval: .eighth, noteType: .bass, measureNumber: 1, measureOffset: 0.125),
            Note(interval: .eighth, noteType: .bass, measureNumber: 1, measureOffset: 0.25),
            Note(interval: .eighth, noteType: .bass, measureNumber: 1, measureOffset: 0.375)
        ]
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
        )

        let beam = try #require(layout.beams.first, "Down-stem bass eighths should form a beam")
        #expect(abs(beam.start.y - beam.end.y) < 0.001, "Down-stem beam should be horizontal")

        let style = NotationLayoutStyle.gameplayDefault
        let beamHeads = layout.noteHeads.filter { beam.noteHeadIDs.contains($0.id) }
        #expect(!beamHeads.isEmpty)
        for head in beamHeads {
            #expect(head.stemDirection == .down, "Bass notes should have .down stem direction")
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
        // Bass notes use the catalog-authored down-stem direction.
        let notes = [
            Note(interval: .sixteenth, noteType: .bass, measureNumber: 1, measureOffset: 0),
            Note(interval: .sixteenth, noteType: .bass, measureNumber: 1, measureOffset: 0.125)
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

    @Test("same-direction chord does not produce duplicate flags")
    func sameDirectionChordDoesNotProduceDuplicateFlags() throws {
        // Crash and snare share the catalog-authored .up direction and one stem.
        // Both are eighth notes, but only one flag should be emitted for that stem.
        let notes = [
            Note(interval: .eighth, noteType: .crash, measureNumber: 1, measureOffset: 0),
            Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: 0)
        ]
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
        )

        // Isolated unbeamed chord: no beams, so each note head would have flags.
        #expect(layout.beams.isEmpty, "Isolated chord notes should not form beams")
        #expect(
            layout.flags.count == 1,
            "Chord should emit exactly 1 flag for the shared stem, got \(layout.flags.count)"
        )
    }

    @Test("stemless note leaves stemmed note catalog direction unchanged")
    func stemlessNoteLeavesStemmedNoteCatalogDirectionUnchanged() throws {
        let notes = [
            Note(interval: .half, noteType: .crash, measureNumber: 1, measureOffset: 0),
            Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: 0)
        ]
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
        )

        let snareHead = try #require(
            layout.noteHeads.first { $0.drumType == .snare },
            "Should have a snare note head"
        )
        #expect(
            snareHead.stemDirection == .up,
            "Snare stem should preserve its catalog-authored .up direction"
        )
    }

    @Test("unbeamed eighth note flag attaches at stem tip")
    func unbeamedEighthNoteFlagAttachesAtStemTip() throws {
        let note = Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: 0)
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: [note], timeSignature: .fourFour)
        )

        let flag = try #require(layout.flags.first, "Eighth note should produce exactly one flag")
        let stem = try #require(layout.stems.first, "Eighth note should have a stem")

        // The first flag of an unbeamed note should be at the stem tip (offset 0),
        // not displaced by flagVerticalSpacing.
        let distance = abs(flag.origin.y - stem.end.y)
        #expect(
            distance < 0.001,
            "First flag (Y=\(flag.origin.y)) should be at stem tip (Y=\(stem.end.y)), distance=\(distance)"
        )
    }

    @Test("unbeamed sixteenth note flags stack from stem tip")
    func unbeamedSixteenthNoteFlagsStackFromStemTip() throws {
        // Two consecutive sixteenth notes that are NOT beamed (different voices so
        // they don't join into a beam run — use snare + bass on same offset but
        // different voices).  Actually, same-voice consecutive 16ths DO beam, so
        // use an isolated 16th note.
        let note = Note(interval: .sixteenth, noteType: .snare, measureNumber: 1, measureOffset: 0)
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: [note], timeSignature: .fourFour)
        )

        #expect(layout.flags.count == 2, "Isolated 16th should have 2 flags")
        let stem = try #require(layout.stems.first)

        let flag0 = layout.flags.first { $0.flagIndex == 0 }
        let flag1 = layout.flags.first { $0.flagIndex == 1 }
        try #require(flag0 != nil && flag1 != nil)

        // Flag 0 should be at the stem tip.
        let distance0 = abs(flag0!.origin.y - stem.end.y)
        #expect(distance0 < 0.001, "Flag 0 should be at stem tip, distance=\(distance0)")

        // Flag 1 should be offset by exactly one flagVerticalSpacing from stem tip,
        // toward the note head.  For up-stem notes the stem tip is above the head,
        // so "toward the head" means positive-y (downward in SwiftUI).
        let spacing = GameplayLayout.flagVerticalSpacing
        #expect(
            stem.direction == .up,
            "Snare on line3 should have up-stem"
        )
        let signedOffset = flag1!.origin.y - stem.end.y
        #expect(
            abs(signedOffset - spacing) < 0.001,
            "Flag 1 should be \(spacing) below stem tip (toward note head), got offset \(signedOffset)"
        )
    }

    @Test("beamed residual flag is offset from beam, not at stem tip")
    func beamedResidualFlagIsOffsetFromBeam() throws {
        // 16th + 32nd + 16th — the 32nd gets covered at levels 0 and 1 but has
        // 3 total flags → 1 remaining flag that must be offset from the beam.
        let notes = [
            Note(interval: .sixteenth, noteType: .snare, measureNumber: 1, measureOffset: 0),
            Note(interval: .thirtysecond, noteType: .snare, measureNumber: 1, measureOffset: 0.0625),
            Note(interval: .sixteenth, noteType: .snare, measureNumber: 1, measureOffset: 0.125)
        ]
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
        )

        let flag = try #require(layout.flags.first, "Should have 1 remaining flag")
        let stem = try #require(
            layout.stems.first { $0.noteHeadIDs.contains(flag.noteHeadID) }
        )

        // The beamed residual flag should NOT be at the stem tip — it must be
        // offset by at least flagVerticalSpacing from the beam level.
        let distance = abs(flag.origin.y - stem.end.y)
        #expect(
            distance >= GameplayLayout.flagVerticalSpacing - 0.001,
            "Beamed residual flag should be offset from stem end, distance=\(distance)"
        )
    }

    @Test("down-stem multi-flag notes stack toward the note head")
    func downStemMultiFlagStacksTowardNoteHead() throws {
        // Isolated sixteenth bass drum: catalog-authored .down direction.
        // The stem tip is below the note head.  Extra flags should stack
        // upward (negative-y in SwiftUI) toward the note head.
        let note = Note(interval: .sixteenth, noteType: .bass, measureNumber: 1, measureOffset: 0)
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: [note], timeSignature: .fourFour)
        )

        #expect(layout.flags.count == 2, "Isolated 16th bass drum should have 2 flags")
        let stem = try #require(layout.stems.first)
        #expect(stem.direction == .down, "Bass drum should have down-stem")

        let flag0 = try #require(layout.flags.first { $0.flagIndex == 0 })
        let flag1 = try #require(layout.flags.first { $0.flagIndex == 1 })

        // Flag 0 at stem tip.
        let distance0 = abs(flag0.origin.y - stem.end.y)
        #expect(distance0 < 0.001, "Flag 0 should be at stem tip")

        // Flag 1 should be one spacing ABOVE the stem tip (toward note head).
        let spacing = GameplayLayout.flagVerticalSpacing
        let signedOffset = flag1.origin.y - stem.end.y
        #expect(
            abs(signedOffset + spacing) < 0.001,
            "Flag 1 should be \(spacing) above stem tip (toward note head), got offset \(signedOffset)"
        )
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
