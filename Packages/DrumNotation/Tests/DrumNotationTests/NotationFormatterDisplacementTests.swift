import CoreGraphics
import Testing
import DrumNotation

/// The VexFlow staff-second displacement suite. Split from
/// `NotationFormatterTests` to keep both files under the lint length limit.
@Suite("Notation formatter staff-second displacement")
struct NotationFormatterDisplacementTests {
    private let style = NotationFormattingStyle.virgoDefault

    /// VexFlow displacement magnitude: one head width minus half the stem width.
    private func displacement(
        headStyle: PercussionNoteheadStyle = .x,
        duration: NotationDuration = .quarter
    ) -> CGFloat {
        let width = PercussionGlyphMetrics.notehead(
            style: headStyle, duration: duration, stemDirection: .up, staffSpace: style.staffSpace
        ).paintedBounds.width
        return width - style.stemWidth / 2
    }

    @Test("up-stem second: stem-side head stays, adjacent upper head displaces onto the shared stem")
    func upStemSecondDisplacesUpperHead() throws {
        let notes = [
            Fixtures.makeNote(id: 1, localTick: 0, staffStep: 3),
            Fixtures.makeNote(id: 2, localTick: 0, staffStep: 4)
        ]
        let notation = try Fixtures.format(try Fixtures.document(notes: notes, rests: [], controls: []))
        let column = try Fixtures.column(notation, localTick: 0)
        let lower = try #require(column.noteHeads.first { $0.noteID == 1 })
        let upper = try #require(column.noteHeads.first { $0.noteID == 2 })

        // The stem-side (lowest) head stays at base X; the column never moves.
        #expect(lower.headCenterX == column.logicalColumnX)
        // Sheet-local: rowLeadingInset 100 + leadingMeasureInset 52.
        #expect(column.logicalColumnX == 152)
        let shift = displacement()
        #expect(upper.headCenterX == column.logicalColumnX + shift)

        // The shared stem axis (base head's stem anchor) stays put and remains
        // inside the displaced head's ink: the head shifted, the stem did not.
        // X values are sheet-local; express them relative to the column base.
        let head = PercussionGlyphMetrics.notehead(
            style: .x, duration: .quarter, stemDirection: .up, staffSpace: style.staffSpace
        )
        let stemX = head.stemAnchorOffset.x
        #expect(stemX >= head.paintedBounds.minX && stemX <= head.paintedBounds.maxX)
        let displacedInkMinX = upper.headCenterX - column.logicalColumnX + head.paintedBounds.minX
        let displacedInkMaxX = upper.headCenterX - column.logicalColumnX + head.paintedBounds.maxX
        #expect(displacedInkMinX <= stemX)
        #expect(displacedInkMaxX >= stemX)

        // Displaced ink widens the column on the shift side.
        #expect(abs(column.rightExtent - (shift + head.paintedBounds.maxX)) < 0.001)
    }

    @Test("down-stem second: stem-side head stays, adjacent lower head displaces onto the shared stem")
    func downStemSecondDisplacesLowerHead() throws {
        let notes = [
            Fixtures.makeNote(id: 1, localTick: 0, staffStep: 3, stem: .down),
            Fixtures.makeNote(id: 2, localTick: 0, staffStep: 4, stem: .down)
        ]
        let notation = try Fixtures.format(try Fixtures.document(notes: notes, rests: [], controls: []))
        let column = try Fixtures.column(notation, localTick: 0)
        let lower = try #require(column.noteHeads.first { $0.noteID == 1 })
        let upper = try #require(column.noteHeads.first { $0.noteID == 2 })

        // The stem-side (highest) head stays at base X; the lower head shifts left.
        #expect(upper.headCenterX == column.logicalColumnX)
        let shift = displacement()
        #expect(lower.headCenterX == column.logicalColumnX - shift)

        let head = PercussionGlyphMetrics.notehead(
            style: .x, duration: .quarter, stemDirection: .down, staffSpace: style.staffSpace
        )
        let stemX = head.stemAnchorOffset.x
        #expect(stemX <= head.paintedBounds.maxX && stemX >= head.paintedBounds.minX)
        let relativeCenterX = lower.headCenterX - column.logicalColumnX
        #expect(relativeCenterX + head.paintedBounds.maxX >= stemX)
        #expect(relativeCenterX + head.paintedBounds.minX <= stemX)
        #expect(abs(column.leftExtent - -(relativeCenterX + head.paintedBounds.minX)) < 0.001)
    }

    @Test("stemless stem-side head never holds the base slot; the stem member keeps the stem axis")
    func stemlessHeadNeverDisplacesStemMemberOntoPaintedAxis() throws {
        // Adjacent staff steps, stemless whole on the stem side: the caller
        // paints the shared stem and flag from the stem member's undisplaced
        // anchor, so the eighth must stay at base X and the stemless head
        // takes the shift.
        let notes = [
            Fixtures.makeNote(id: 1, localTick: 0, staffStep: 3, duration: .whole),
            Fixtures.makeNote(id: 2, localTick: 0, staffStep: 4, duration: .eighth, flag: .eighth)
        ]
        let notation = try Fixtures.format(try Fixtures.document(notes: notes, rests: [], controls: []))
        let column = try Fixtures.column(notation, localTick: 0)
        let stemless = try #require(column.noteHeads.first { $0.noteID == 1 })
        let stemmed = try #require(column.noteHeads.first { $0.noteID == 2 })

        #expect(stemmed.headCenterX == column.logicalColumnX)
        let wholeShift = displacement(headStyle: .x, duration: .whole)
        #expect(stemless.headCenterX == column.logicalColumnX + wholeShift)

        // The flag's measured ink is anchored at the stem member's
        // undisplaced axis — the same axis the caller paints it from.
        let flagInkMaxX = Fixtures.stemAxisX(stem: .up)
            - style.stemWidth / 2
            + Fixtures.flagRightInk(duration: .eighth, stem: .up)
        #expect(column.rightExtent >= flagInkMaxX)
    }

    @Test("a down-stem stemless head also yields the base slot to the stem member")
    func downStemlessHeadYieldsBaseSlot() throws {
        // Down-stem walk is descending (highest step = stem side): the
        // stemless whole sorts first but must take the far-side shift while
        // the eighth keeps the painted stem axis at base X.
        let notes = [
            Fixtures.makeNote(id: 1, localTick: 0, staffStep: 4, stem: .down, duration: .whole),
            Fixtures.makeNote(id: 2, localTick: 0, staffStep: 3, stem: .down, duration: .eighth)
        ]
        let notation = try Fixtures.format(try Fixtures.document(notes: notes, rests: [], controls: []))
        let column = try Fixtures.column(notation, localTick: 0)
        let stemless = try #require(column.noteHeads.first { $0.noteID == 1 })
        let stemmed = try #require(column.noteHeads.first { $0.noteID == 2 })

        #expect(stemmed.headCenterX == column.logicalColumnX)
        let wholeShift = displacement(headStyle: .x, duration: .whole)
        #expect(stemless.headCenterX == column.logicalColumnX - wholeShift)
    }

    @Test("non-adjacent same-stem heads stay centered")
    func nonAdjacentHeadsStayCentered() throws {
        let notes = [
            Fixtures.makeNote(id: 1, localTick: 0, staffStep: 3),
            Fixtures.makeNote(id: 2, localTick: 0, staffStep: 5)
        ]
        let notation = try Fixtures.format(try Fixtures.document(notes: notes, rests: [], controls: []))
        let column = try Fixtures.column(notation, localTick: 0)
        #expect(column.noteHeads.allSatisfy { $0.headCenterX == column.logicalColumnX })
    }

    @Test("adjacent chains alternate base and shifted walking away from the stem side")
    func adjacentChainAlternates() throws {
        let notes = [
            Fixtures.makeNote(id: 1, localTick: 0, staffStep: 3),
            Fixtures.makeNote(id: 2, localTick: 0, staffStep: 4),
            Fixtures.makeNote(id: 3, localTick: 0, staffStep: 5),
            Fixtures.makeNote(id: 4, localTick: 0, staffStep: 7),
            Fixtures.makeNote(id: 5, localTick: 0, staffStep: 8)
        ]
        let notation = try Fixtures.format(try Fixtures.document(notes: notes, rests: [], controls: []))
        let column = try Fixtures.column(notation, localTick: 0)
        let shift = displacement()
        // 3-4-5 alternate; the 5→7 gap resets so 7 is base and 8 shifts again.
        let expected = [1: 0, 2: shift, 3: 0, 4: 0, 5: shift]
        for head in column.noteHeads {
            let expectedX = try #require(expected[head.noteID])
            #expect(head.headCenterX == column.logicalColumnX + expectedX)
        }
    }

    @Test("mixed-stem same-tick chord stays on one column; seconds displace only within a direction")
    func mixedStemSecondStaysOnOneColumn() throws {
        let notes = [
            Fixtures.makeNote(id: 1, localTick: 0, staffStep: 3, stem: .up),
            Fixtures.makeNote(id: 2, localTick: 0, staffStep: 4, stem: .up),
            Fixtures.makeNote(id: 3, localTick: 0, staffStep: 12, stem: .down)
        ]
        let notation = try Fixtures.format(try Fixtures.document(notes: notes, rests: [], controls: []))
        let column = try Fixtures.column(notation, localTick: 0)
        #expect(column.noteHeads.count == 3)
        let shift = displacement()
        let expected = [1: 0, 2: shift, 3: 0]
        for head in column.noteHeads {
            let expectedX = try #require(expected[head.noteID])
            #expect(head.headCenterX == column.logicalColumnX + expectedX)
        }
    }
}
