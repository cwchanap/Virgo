import Testing
import SwiftUI
@testable import Virgo

// Task-focused geometry coverage intentionally lives with the existing chord/beam suite.
// swiftlint:disable file_length

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

    @Test("canonical upper-voice chord shares one up stem")
    func canonicalUpperVoiceChordSharesOneUpStem() throws {
        let notes = [
            Note(interval: .quarter, noteType: .crash, measureNumber: 1, measureOffset: 0),
            Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0)
        ]
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
        )

        #expect(layout.stems.count == 1)
        let stem = try #require(layout.stems.first)
        #expect(Set(stem.noteHeadIDs) == Set(layout.noteHeads.map(\.id)))
        #expect(stem.direction == .up)
    }

    @Test("canonical upper-voice chord yields a single beam group")
    func canonicalUpperVoiceChordYieldsSingleBeamGroup() throws {
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
        #expect(layout.beams.allSatisfy { $0.direction == .up })
        #expect(layout.stems.allSatisfy { $0.direction == .up })
    }

    @Test("canonical upper-voice chord and solo form one beam")
    func canonicalUpperVoiceChordAndSoloFormOneBeam() throws {
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

        let upperHeads = layout.noteHeads.filter { $0.voice == .upper }
        #expect(upperHeads.allSatisfy { $0.stemDirection == .up })

        // Verify the crash note head is part of the beam.
        let beam = try #require(layout.beams.first)
        let crashHead = try #require(layout.noteHeads.first { $0.drumType == .crash })
        #expect(
            beam.noteHeadIDs.contains(crashHead.id),
            "Crash note head should be included in the beam"
        )
    }

    @Test("canonical upper voice ignores distance from middle")
    func canonicalUpperVoiceIgnoresDistanceFromMiddle() throws {
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
            Note(interval: .sixteenth, noteType: .bass, measureNumber: 1, measureOffset: 0.0625)
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

    @Test("implicit gap splits mixed-duration run and leaves final sixteenth isolated")
    func implicitGapSplitsMixedDurationRun() throws {
        let notes = [
            Note(interval: .sixteenth, noteType: .snare, measureNumber: 1, measureOffset: 0),
            Note(interval: .thirtysecond, noteType: .snare, measureNumber: 1, measureOffset: 0.0625),
            Note(interval: .sixteenth, noteType: .snare, measureNumber: 1, measureOffset: 0.125)
        ]
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
        )

        let finalHead = try #require(
            layout.noteHeads.first { abs($0.timePosition - 0.125) < 0.000_001 }
        )
        #expect(layout.beams.contains { $0.kind == .backwardHook && $0.level == 2 })
        #expect(layout.flags.filter { $0.noteHeadID == finalHead.id }.count == 2)
    }

    @Test("canonical upper-voice chord does not duplicate flags")
    func canonicalUpperVoiceChordDoesNotDuplicateFlags() throws {
        // Crash and snare share the catalog-authored .up direction and one stem.
        // Both are eighth notes, but only one flag should be emitted for that stem.
        let notes = [
            Note(interval: .eighth, noteType: .crash, measureNumber: 1, measureOffset: 0),
            Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: 0)
        ]
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
        )

        #expect(layout.stems.count == 1)
        #expect(layout.beams.isEmpty, "Isolated chord notes should not form beams")
        #expect(
            layout.flags.count == 1,
            "Chord should emit exactly 1 flag for the shared stem, got \(layout.flags.count)"
        )
    }

    @Test("stemless head is excluded from shared stem membership")
    func stemlessHeadIsExcludedFromSharedStemMembership() throws {
        let notes = [
            Note(interval: .half, noteType: .crash, measureNumber: 1, measureOffset: 0),
            Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: 0)
        ]
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
        )

        let crashHead = try #require(layout.noteHeads.first { $0.drumType == .crash })
        let snareHead = try #require(layout.noteHeads.first { $0.drumType == .snare })
        let stem = try #require(layout.stems.first)

        #expect(layout.stems.count == 1)
        #expect(!stem.noteHeadIDs.contains(crashHead.id))
        #expect(stem.noteHeadIDs.contains(snareHead.id))
        #expect(stem.direction == .up)
    }

    @Test("stemless note sharing a beam run time column does not hijack beam endpoint X")
    func stemlessNoteInBeamRunDoesNotHijackEndpointX() throws {
        // Two snare eighths form a beam run. A hiHat half sits at the same
        // time column as the first eighth. hiHat uses a .cross glyph (different
        // stem anchor X than snare's .filledDiamond), and its position is
        // overridden to line1 (below snare's line3) so that without the
        // needsStem filter, stemRepresentative would pick the half note as the
        // beam owner (largest y for up-stems), misaligning beam start.x from
        // the stem start.x that buildStems computes (it filters to needsStem).
        let notes = [
            Note(interval: .half, noteType: .hiHat, measureNumber: 1, measureOffset: 0),
            Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: 0),
            Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: 0.125)
        ]
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(
                notes: notes,
                timeSignature: .fourFour,
                notePositionOverrides: [.hiHat: .line1]
            )
        )

        let halfHead = try #require(layout.noteHeads.first { $0.drumType == .hiHat })
        let snareHeads = layout.noteHeads.filter { $0.drumType == .snare }
        let firstSnare = try #require(snareHeads.min { $0.timeColumn.absoluteLayoutTick < $1.timeColumn.absoluteLayoutTick })

        // Sanity: the half and first eighth share the same time column, and
        // the half is positioned lower (larger y) so it would be picked as
        // representative for an up-stem without the needsStem filter.
        #expect(halfHead.timeColumn == firstSnare.timeColumn)
        #expect(halfHead.position.y > firstSnare.position.y)

        // A beam run should form.
        let beam = try #require(layout.beams.first { $0.kind == .full && $0.level == 0 })

        // The stem for the first snare's stem group.
        let stem = try #require(layout.stems.first { $0.noteHeadIDs.contains(firstSnare.id) })

        // The beam start.x must match the stem start.x — not the half note's
        // stem anchor x. Without the needsStem filter this would fail because
        // the half note (lower position, largest y for up-stem, .cross glyph)
        // would be picked as the beam owner.
        let style = NotationLayoutStyle.gameplayDefault
        let halfAnchorX = NotationLayoutEngine().stemAnchor(for: halfHead, style: style).x
        #expect(
            abs(beam.start.x - stem.start.x) < 0.001,
            "Beam start.x (\(beam.start.x)) should match stem start.x (\(stem.start.x))"
        )
        #expect(
            abs(beam.start.x - halfAnchorX) > 0.001,
            "Beam start.x should not coincide with the stemless half note's stem anchor (\(halfAnchorX))"
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

    @Test("beamed higher-level singleton uses a hook instead of a residual flag")
    func beamedHigherLevelSingletonUsesHook() throws {
        let notes = [
            Note(interval: .sixteenth, noteType: .snare, measureNumber: 1, measureOffset: 0),
            Note(interval: .thirtysecond, noteType: .snare, measureNumber: 1, measureOffset: 0.0625),
            Note(interval: .sixteenth, noteType: .snare, measureNumber: 1, measureOffset: 0.125)
        ]
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
        )

        let thirtySecond = try #require(
            layout.noteHeads.first { $0.interval == .thirtysecond }
        )
        let hook = try #require(
            layout.beams.first { $0.level == 2 && $0.noteHeadIDs == [thirtySecond.id] }
        )

        #expect(hook.kind == .backwardHook)
        #expect(layout.flags.allSatisfy { $0.noteHeadID != thirtySecond.id })
    }

    @Test("down-stem multi-flag notes stack toward the note head")
    func downStemMultiFlagStacksTowardNoteHead() throws {
        // Isolated lower-voice pedal hi-hat uses the catalog-authored .down direction.
        // The stem tip is below the note head.  Extra flags should stack
        // upward (negative-y in SwiftUI) toward the note head.
        let note = Note(interval: .sixteenth, noteType: .hiHatPedal, measureNumber: 1, measureOffset: 0)
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: [note], timeSignature: .fourFour)
        )

        #expect(layout.flags.count == 2, "Isolated 16th pedal hi-hat should have 2 flags")
        let stem = try #require(layout.stems.first)
        #expect(stem.direction == .down, "Pedal hi-hat should have down-stem")

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

    @Test("Same-time mixed voices use disjoint stems on opposite glyph sides")
    func sameTimeMixedVoicesUseDisjointOppositeStems() throws {
        let style = NotationLayoutStyle.gameplayDefault
        let notes = [
            Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0),
            Note(interval: .quarter, noteType: .bass, measureNumber: 1, measureOffset: 0)
        ]
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
        )
        let upperHead = try #require(layout.noteHeads.first { $0.voice == .upper })
        let lowerHead = try #require(layout.noteHeads.first { $0.voice == .lower })
        let upperStem = try #require(layout.stems.first { $0.noteHeadIDs.contains(upperHead.id) })
        let lowerStem = try #require(layout.stems.first { $0.noteHeadIDs.contains(lowerHead.id) })
        let size = style.noteHeadSize
        let upperOffset = upperHead.glyph.stemAnchorOffset(direction: .up, in: size)
        let lowerOffset = lowerHead.glyph.stemAnchorOffset(direction: .down, in: size)
        let expectedUpperStart = CGPoint(
            x: upperHead.position.x + upperOffset.x,
            y: upperHead.position.y + upperOffset.y
        )
        let expectedLowerStart = CGPoint(
            x: lowerHead.position.x + lowerOffset.x,
            y: lowerHead.position.y + lowerOffset.y
        )

        #expect(upperHead.position.x == lowerHead.position.x)
        #expect(upperStem.direction == .up)
        #expect(lowerStem.direction == .down)
        #expect(Set(upperStem.noteHeadIDs).isDisjoint(with: Set(lowerStem.noteHeadIDs)))
        #expect(upperStem.start == expectedUpperStart)
        #expect(lowerStem.start == expectedLowerStart)
    }

    @Test("Unbeamed stem covers a tall same-voice chord")
    func unbeamedStemCoversTallSameVoiceChord() throws {
        let style = NotationLayoutStyle.gameplayDefault
        let notes = [
            Note(interval: .quarter, noteType: .crash, measureNumber: 1, measureOffset: 0),
            Note(interval: .quarter, noteType: .lowTom, measureNumber: 1, measureOffset: 0)
        ]
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(
                notes: notes,
                timeSignature: .fourFour,
                notePositionOverrides: [.crash: .aboveLine9, .tom3: .belowLine6]
            )
        )
        let stem = try #require(layout.stems.first)
        let highestVisibleY = try #require(
            layout.noteHeads.map {
                $0.glyph.bounds(centeredAt: $0.position, size: layout.noteHeadSize).minY
            }.min()
        )
        let lowestHead = try #require(
            layout.noteHeads.max(by: { $0.position.y < $1.position.y })
        )
        let lowestOffset = lowestHead.glyph.stemAnchorOffset(
            direction: .up,
            in: layout.noteHeadSize
        )
        let expectedStart = CGPoint(
            x: lowestHead.position.x + lowestOffset.x,
            y: lowestHead.position.y + lowestOffset.y
        )

        #expect(layout.stems.count == 1)
        #expect(stem.direction == .up)
        #expect(stem.start == expectedStart)
        #expect(stem.end.y <= highestVisibleY - style.minimumStemExtensionPastChord)
        #expect(stem.start.y - stem.end.y >= style.stemLength)
    }

    @Test("Unbeamed lower-voice stem covers a tall chord from the left")
    func unbeamedLowerVoiceStemCoversTallChordFromLeft() throws {
        let style = NotationLayoutStyle.gameplayDefault
        let notes = [
            Note(interval: .quarter, noteType: .bass, measureNumber: 1, measureOffset: 0),
            Note(interval: .quarter, noteType: .hiHatPedal, measureNumber: 1, measureOffset: 0)
        ]
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(
                notes: notes,
                timeSignature: .fourFour,
                notePositionOverrides: [.kick: .aboveLine9, .hiHatPedal: .belowLine6]
            )
        )
        let stem = try #require(layout.stems.first)
        let lowestVisibleY = try #require(
            layout.noteHeads.map {
                $0.glyph.bounds(centeredAt: $0.position, size: layout.noteHeadSize).maxY
            }.max()
        )
        let highestHead = try #require(
            layout.noteHeads.min(by: { $0.position.y < $1.position.y })
        )
        let highestOffset = highestHead.glyph.stemAnchorOffset(
            direction: .down,
            in: layout.noteHeadSize
        )
        let expectedStart = CGPoint(
            x: highestHead.position.x + highestOffset.x,
            y: highestHead.position.y + highestOffset.y
        )

        #expect(layout.stems.count == 1)
        #expect(stem.direction == .down)
        #expect(stem.start == expectedStart)
        #expect(stem.end.y >= lowestVisibleY + style.minimumStemExtensionPastChord)
        #expect(stem.end.y - stem.start.y >= style.stemLength)
    }

    @Test("Shared-chord flags originate from the rendered stem")
    func sharedChordFlagsOriginateFromRenderedStem() throws {
        let notes = [
            Note(interval: .sixteenth, noteType: .hiHat, measureNumber: 1, measureOffset: 0),
            Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: 0)
        ]
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
        )
        let stem = try #require(layout.stems.first)
        let firstFlag = try #require(layout.flags.first { $0.flagIndex == 0 })
        let secondFlag = try #require(layout.flags.first { $0.flagIndex == 1 })

        #expect(layout.stems.count == 1)
        #expect(layout.beams.isEmpty)
        #expect(layout.flags.count == 2)
        #expect(firstFlag.origin.x == stem.start.x + GameplayLayout.flagXOffset)
        #expect(firstFlag.origin.y == stem.end.y)
        #expect(secondFlag.origin.x == firstFlag.origin.x)
        #expect(secondFlag.origin.y == stem.end.y + GameplayLayout.flagVerticalSpacing)
    }

    @Test("Beam endpoint uses the shared chord stem anchor")
    func beamEndpointUsesSharedChordStemAnchor() throws {
        let notes = [
            Note(interval: .eighth, noteType: .hiHat, measureNumber: 1, measureOffset: 0),
            Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: 0),
            Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: 0.125)
        ]
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
        )
        let firstColumn = try #require(
            layout.noteHeads.map(\.timeColumn).min(by: {
                $0.absoluteLayoutTick < $1.absoluteLayoutTick
            })
        )
        let firstIDs = Set(
            layout.noteHeads
                .filter { $0.timeColumn == firstColumn }
                .map(\.id)
        )
        let firstStem = try #require(
            layout.stems.first { !firstIDs.isDisjoint(with: Set($0.noteHeadIDs)) }
        )
        let beam = try #require(layout.beams.first { $0.level == 0 })

        #expect(beam.start.x == firstStem.start.x)
    }

    @Test("Mixed quarter/eighth chord beam anchor matches stem anchor")
    func mixedQuarterEighthChordBeamAnchorMatchesStemAnchor() throws {
        // Quarter snare (.filledDiamond, line3) + eighth hi-hat (.cross, line5)
        // share a stem at column 0.  The eighth hi-hat beams to an eighth snare
        // at column 1.  Before the fix, buildStems picked the representative from
        // the full chord (snare, highest Y for .up) while beams(for:) picked it
        // from only the flagged subset (hi-hat), producing different glyph anchor
        // X values and a visible stem/beam misalignment.
        let notes = [
            Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0),
            Note(interval: .eighth, noteType: .hiHat, measureNumber: 1, measureOffset: 0),
            Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: 0.125)
        ]
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
        )

        let snareQuarterOpt = layout.noteHeads.first { $0.drumType == .snare && $0.interval == .quarter }
        let snareQuarter = try #require(snareQuarterOpt)
        let hiHatEighthOpt = layout.noteHeads.first { $0.drumType == .hiHat && $0.interval == .eighth }
        let hiHatEighth = try #require(hiHatEighthOpt)

        // Both heads at column 0 share one stem.
        let firstStemOpt = layout.stems.first { stem in
            stem.noteHeadIDs.contains(snareQuarter.id)
        }
        let firstStem = try #require(firstStemOpt)
        #expect(
            firstStem.noteHeadIDs.contains(hiHatEighth.id),
            "Quarter snare and eighth hi-hat at the same column should share a stem"
        )

        // The beam must exist and its start X must match the stem start X.
        let beam = try #require(layout.beams.first { $0.level == 0 })
        let beamDelta = abs(beam.start.x - firstStem.start.x)
        #expect(
            beamDelta < 0.001,
            "Beam start X must match stem start X (delta=\(beamDelta)) — same chord representative glyph"
        )

        // The representative should be the snare (highest Y for up-stems),
        // not the hi-hat.  Verify by computing the expected anchor from the
        // snare's glyph and confirming it matches.
        let style = NotationLayoutStyle.gameplayDefault
        let snareAnchor = snareQuarter.glyph.stemAnchorOffset(
            direction: StemDirection.up,
            in: style.noteHeadSize
        )
        let expectedX = snareQuarter.position.x + snareAnchor.x
        let stemDelta = abs(firstStem.start.x - expectedX)
        #expect(
            stemDelta < 0.001,
            "Stem should be anchored on the snare (.filledDiamond) representative (delta=\(stemDelta))"
        )
        let beamRepDelta = abs(beam.start.x - expectedX)
        #expect(
            beamRepDelta < 0.001,
            "Beam should be anchored on the same snare representative as the stem (delta=\(beamRepDelta))"
        )
    }

    @Test("full 4/4 sixteenth run creates four two-level beat groups")
    func fullSixteenthRunIsBeatScoped() {
        let notes = (0..<16).map {
            Note(
                interval: .sixteenth,
                noteType: .snare,
                measureNumber: 1,
                measureOffset: Double($0) / 16.0
            )
        }
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
        )

        #expect(layout.beams.filter { $0.level == 0 && $0.kind == .full }.count == 4)
        #expect(layout.beams.filter { $0.level == 1 && $0.kind == .full }.count == 4)
        #expect(layout.flags.isEmpty)
    }

    @Test("mixed sixteenth and eighth use a forward hook without flags")
    func mixedDurationsRenderForwardHook() throws {
        let notes = [
            Note(interval: .sixteenth, noteType: .snare, measureNumber: 1, measureOffset: 0),
            Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: 1.0 / 16.0)
        ]
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
        )

        let hook = try #require(layout.beams.first { $0.level == 1 })
        #expect(hook.kind == .forwardHook)
        #expect(hook.noteHeadIDs.count == 1)
        #expect(hook.end.x > hook.start.x)
        #expect(hook.end.x - hook.start.x <= 12)
        #expect(layout.flags.isEmpty)
    }

    @Test("eighth followed by sixteenth uses a backward hook without flags")
    func mixedDurationsRenderBackwardHook() throws {
        let notes = [
            Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: 0),
            Note(interval: .sixteenth, noteType: .snare, measureNumber: 1, measureOffset: 1.0 / 8.0)
        ]
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
        )
        let hook = try #require(layout.beams.first { $0.level == 1 })
        #expect(hook.kind == .backwardHook)
        #expect(hook.noteHeadIDs.count == 1)
        #expect(hook.end.x < hook.start.x)
        #expect(hook.start.x - hook.end.x <= 12)
        #expect(layout.flags.isEmpty)
    }

    @Test("stemless boundary prevents adjacent flagged notes from beaming")
    func stemlessBoundaryBreaksLayoutRun() {
        let notes = [
            Note(interval: .sixteenth, noteType: .snare, measureNumber: 1, measureOffset: 0),
            Note(interval: .half, noteType: .snare, measureNumber: 1, measureOffset: 1.0 / 32.0),
            Note(interval: .sixteenth, noteType: .snare, measureNumber: 1, measureOffset: 1.0 / 16.0)
        ]
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour)
        )

        #expect(layout.beams.isEmpty)
        #expect(layout.flags.count == 4)
    }

    @Test("adjacent measures never share a beam across the bar line")
    func adjacentMeasuresDoNotShareBeam() {
        // Eighth notes straddle the boundary between measure 1 and measure 2.
        // The last eighth of m1 (offset 0.875) is contiguous in absolute time
        // with the first eighth of m2 (offset 0), so a measure-agnostic beamer
        // would wrongly join them. Beat-scoped topology must keep each measure's
        // beams self-contained.
        let notes = [
            Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: 0.625),
            Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: 0.75),
            Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: 0.875),
            Note(interval: .eighth, noteType: .snare, measureNumber: 2, measureOffset: 0),
            Note(interval: .eighth, noteType: .snare, measureNumber: 2, measureOffset: 0.125),
            Note(interval: .eighth, noteType: .snare, measureNumber: 2, measureOffset: 0.25)
        ]
        let wideStyle = NotationLayoutStyle.gameplayDefault.with(rowWidth: 2_500)
        let layout = NotationLayoutEngine().layout(
            input: NotationLayoutInput(notes: notes, timeSignature: .fourFour, style: wideStyle)
        )

        let headByID = Dictionary(uniqueKeysWithValues: layout.noteHeads.map { ($0.id, $0) })

        // Sanity: both measures are present and beaming is active.
        let measureIndices = Set(layout.noteHeads.map(\.measureIndex))
        #expect(measureIndices == [0, 1], "Both measures should be rendered")
        #expect(!layout.beams.isEmpty, "Eighth runs within each measure should beam")

        // No beam may contain note heads from more than one measure.
        for beam in layout.beams {
            let beamMeasures = Set(beam.noteHeadIDs.compactMap { headByID[$0]?.measureIndex })
            #expect(
                beamMeasures.count <= 1,
                "Beam \(beam.id) spans measures \(beamMeasures); must stay within one measure"
            )
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

// swiftlint:enable file_length
