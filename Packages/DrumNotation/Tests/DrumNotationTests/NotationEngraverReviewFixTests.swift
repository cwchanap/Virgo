import CoreGraphics
import Testing
@testable import DrumNotation

/// HPA-166 Task 4 review round 1: the Important findings' engraver-level
/// fixtures — wide-chord beam clearance, mixed-support stem groups, and
/// the all-primitive painted-bounds containment net. Topology-level
/// assertions for the flag representative live in `StemTopologyTests.swift`;
/// the tuplet and row-furniture fixtures live in
/// `NotationEngraverDescriptorTests.swift`.
@Suite("Engraver wide-chord beam clearance")
struct EngraverWideChordBeamTests {
    private let style = NotationEngravingStyle()
    private let staffSpace = NotationFormattingStyle.virgoDefault.staffSpace

    private func head(_ engraved: EngravedNotation, id: Int) throws -> EngravedNoteHead {
        try #require(engraved.noteHeads.first { $0.noteID == id })
    }

    private func anchor(_ engraved: EngravedNotation, noteID: Int) throws -> CGPoint {
        let noteHead = try head(engraved, id: noteID)
        let metrics = PercussionGlyphMetrics.notehead(
            style: noteHead.noteheadStyle,
            duration: noteHead.duration,
            stemDirection: noteHead.stemDirection,
            staffSpace: staffSpace
        )
        return CGPoint(
            x: noteHead.position.x + metrics.stemAnchorOffset.x,
            y: noteHead.position.y + metrics.stemAnchorOffset.y
        )
    }

    @Test("an up-stem beam clears the wide chord's far member ink")
    func upStemBeamClearsWideChord() throws {
        let input = try Fixtures.document(
            notes: [
                Fixtures.makeNote(
                    id: 1, localTick: 0, staffStep: 3,
                    duration: .sixteenth, durationTicks: 120
                ),
                // The stem-side member of the tick-120 chord keeps the
                // representative; the far member rides the same onset.
                Fixtures.makeNote(
                    id: 2, localTick: 120, staffStep: 3,
                    duration: .sixteenth, durationTicks: 120
                ),
                Fixtures.makeNote(
                    id: 3, localTick: 120, staffStep: 16,
                    duration: .sixteenth, durationTicks: 120
                )
            ],
            rests: [], controls: []
        )
        let engraved = try NotationEngraver.engrave(input, style: style)
        let primary = try #require(engraved.beams.first { $0.level == 0 })
        let farHead = try head(engraved, id: 3)

        // A representative-only base cannot clear the far member — the
        // finding's exact overlap; the chord term must bind instead.
        let repBaseY = try anchor(engraved, noteID: 2).y - style.stemLength
        #expect(repBaseY > farHead.paintedBounds.minY - style.minimumStemExtensionPastChord)
        #expect(primary.start.y <= farHead.paintedBounds.minY - style.minimumStemExtensionPastChord)

        // The shared base is the most extreme of the default-length reach
        // and every participating member's far edge + extension.
        let repAnchors = [try anchor(engraved, noteID: 1), try anchor(engraved, noteID: 2)]
        let memberBounds = [try head(engraved, id: 1), try head(engraved, id: 2), farHead]
        let expected = (repAnchors.map { $0.y - style.stemLength }
            + memberBounds.map {
                $0.paintedBounds.minY - style.minimumStemExtensionPastChord
            }).min()
        #expect(primary.start.y == expected)

        // The shared stem serves the whole chord and still reaches the
        // outermost beam from the stem-side representative's anchor.
        let stem = try #require(engraved.stems.first { $0.noteIDs.contains(3) })
        let repAnchor = try anchor(engraved, noteID: 2)
        #expect(stem.noteIDs == [2, 3])
        #expect(stem.start == repAnchor)
        let outermostY = try #require(engraved.beams.map(\.start.y).min())
        #expect(stem.end.y == outermostY)
    }

    @Test("a down-stem beam clears the wide chord's far member ink")
    func downStemBeamClearsWideChord() throws {
        let input = try Fixtures.document(
            notes: [
                Fixtures.makeNote(
                    id: 1, localTick: 0, staffStep: 3, stem: .down,
                    duration: .sixteenth, voice: .lower, durationTicks: 120
                ),
                // The highest member keeps the down-stem representative;
                // the far member sits far below it on the same onset.
                Fixtures.makeNote(
                    id: 2, localTick: 120, staffStep: 3, stem: .down,
                    duration: .sixteenth, voice: .lower, durationTicks: 120
                ),
                Fixtures.makeNote(
                    id: 3, localTick: 120, staffStep: -8, stem: .down,
                    duration: .sixteenth, voice: .lower, durationTicks: 120
                )
            ],
            rests: [], controls: []
        )
        let engraved = try NotationEngraver.engrave(input, style: style)
        let primary = try #require(engraved.beams.first { $0.level == 0 })
        let farHead = try head(engraved, id: 3)

        let repBaseY = try anchor(engraved, noteID: 2).y + style.stemLength
        #expect(repBaseY < farHead.paintedBounds.maxY + style.minimumStemExtensionPastChord)
        #expect(primary.start.y >= farHead.paintedBounds.maxY + style.minimumStemExtensionPastChord)

        let repAnchors = [try anchor(engraved, noteID: 1), try anchor(engraved, noteID: 2)]
        let memberBounds = [try head(engraved, id: 1), try head(engraved, id: 2), farHead]
        let expected = (repAnchors.map { $0.y + style.stemLength }
            + memberBounds.map {
                $0.paintedBounds.maxY + style.minimumStemExtensionPastChord
            }).max()
        #expect(primary.start.y == expected)
    }
}

@Suite("Engraver mixed-support stem groups")
struct EngraverMixedSupportTests {
    private let style = NotationEngravingStyle()

    @Test("a suppressed sibling never governs the chord's stems, beams, flags or dots")
    func suppressedSiblingNeverGoverns() throws {
        let input = try Fixtures.document(
            notes: [
                // The engravable member: fewer flag levels than its
                // suppressed sibling but the only legal representative.
                Fixtures.makeNote(
                    id: 1, localTick: 0, staffStep: 3,
                    duration: .thirtySecond, dotCount: 1, durationTicks: 60
                ),
                // The suppressed sibling owns MORE flag levels — the
                // representative the unfixed comparator would wrongly pick,
                // turning the whole chord into a boundary event.
                Fixtures.makeNote(
                    id: 2, localTick: 0, staffStep: 5,
                    duration: .sixtyFourth, dotCount: 1,
                    durationTicks: 30, isRhythmEngravable: false
                ),
                // A normal beamed pair elsewhere keeps beams in the fixture.
                Fixtures.makeNote(
                    id: 3, localTick: 120, staffStep: 3,
                    duration: .sixteenth, durationTicks: 120
                ),
                Fixtures.makeNote(
                    id: 4, localTick: 240, staffStep: 3,
                    duration: .sixteenth, durationTicks: 120
                )
            ],
            rests: [], controls: []
        )
        let engraved = try NotationEngraver.engrave(input, style: style)

        // Stems: one stem serves the engravable member only — the
        // suppressed head keeps its ink but no rhythm primitives.
        let stem = try #require(engraved.stems.first { $0.noteIDs.contains(1) })
        #expect(stem.noteIDs == [1])

        // Beams: the sixteenth pair forms one primary run untouched by
        // the mixed onset.
        #expect(engraved.beams.contains { $0.kind == .full && $0.noteIDs == [3, 4] })

        // Flags: the isolated engravable 32nd paints its canonical flag —
        // never suppressed by the sibling's higher flag count.
        let flag = try #require(engraved.flags.first)
        #expect(engraved.flags.count == 1)
        #expect(flag.noteID == 1)
        #expect(flag.duration == .thirtySecond)
        #expect(flag.origin.y == stem.end.y)

        // Dots: the engravable member's dot paints; the suppressed
        // sibling's does not.
        #expect(engraved.rhythmDots.contains { $0.source == .note(1) })
        #expect(engraved.rhythmDots.contains { $0.source == .note(2) } == false)
    }
}

@Suite("Engraver painted-bounds containment")
struct EngraverPaintedBoundsContainmentTests {
    private let style = NotationEngravingStyle()
    private var staffSpace: CGFloat { style.formatting.staffSpace }

    @Test("every primitive paints inside the final painted bounds")
    func primitivesInsidePaintedBounds() throws {
        let engraved = try NotationEngraver.engrave(allPrimitiveFixture(), style: style)
        let bounds = engraved.paintedBounds

        #expect(allPrimitiveInk(in: engraved).allSatisfy(bounds.contains))
    }

    /// One fixture exercising every primitive kind: a flagged head above
    /// the staff (ledgers + dot + flag + stem), a down-stem head, a beamed
    /// pair, an articulated head, a bracketed tuplet, a rest, a control,
    /// the measure bars, and the row furniture.
    private func allPrimitiveFixture() throws -> ResolvedNotationInput {
        try Fixtures.document(
            notes: [
                Fixtures.makeNote(
                    id: 1, localTick: 0, staffStep: 10,
                    duration: .eighth, dotCount: 1, durationTicks: 240
                ),
                Fixtures.makeNote(
                    id: 2, localTick: 960, staffStep: -4, stem: .down,
                    headStyle: .normal, durationTicks: 480
                ),
                Fixtures.makeNote(
                    id: 5, localTick: 480, staffStep: 3,
                    duration: .sixteenth, durationTicks: 120
                ),
                Fixtures.makeNote(
                    id: 6, localTick: 600, staffStep: 3,
                    duration: .sixteenth, durationTicks: 120
                ),
                Fixtures.makeNote(
                    id: 7, localTick: 1200, staffStep: 5,
                    durationTicks: 480, articulation: .open
                )
            ],
            rests: [Fixtures.rest(id: 3, localTick: 1440)],
            controls: [Fixtures.control(id: 9, localTick: 720)],
            tuplets: [
                ResolvedTupletGroup(
                    id: 1, measureIndex: 0, voice: .upper,
                    ratio: ResolvedTupletRatio(actual: 3, normal: 2),
                    memberNoteIDs: [5, 6, 7], memberRestIDs: []
                )
            ]
        )
    }

    /// Every primitive array's ink plus the row furniture's, derived the
    /// same way the composer unions it — a containment failure means the
    /// painted union dropped a primitive's ink before the shift.
    private func allPrimitiveInk(in engraved: EngravedNotation) -> [CGRect] {
        var rowsByIndex: [Int: EngravedRow] = [:]
        for row in engraved.rows { rowsByIndex[row.index] = row }
        let staffHeight = 4 * staffSpace
        var ink: [CGRect] = []
        ink += engraved.noteHeads.map(\.paintedBounds)
        ink += engraved.rests.map(\.paintedBounds)
        ink += engraved.ledgerLines.map(\.paintedBounds)
        ink += engraved.rhythmDots.map(\.paintedBounds)
        ink += engraved.stems.map {
            strokedInk(start: $0.start, end: $0.end, width: style.formatting.stemWidth)
        }
        ink += engraved.beams.map {
            strokedInk(start: $0.start, end: $0.end, width: $0.thickness)
        }
        ink += engraved.flags.map(flagInk)
        ink += engraved.articulations.map(articulationInk)
        ink += engraved.controls.map(controlInk)
        ink += engraved.tuplets.map(tupletInk)
        ink += engraved.measureBars.map {
            barInk($0, rowsByIndex: rowsByIndex, staffHeight: staffHeight)
        }
        ink += engraved.rows.map(\.paintedBounds)
        ink += engraved.rows.map { $0.clef.paintedBounds }
        ink += engraved.rows.map { $0.meterSignature.paintedBounds }
        return ink
    }

    /// Stroked-segment ink — the composer's `lineBounds` formula.
    private func strokedInk(start: CGPoint, end: CGPoint, width: CGFloat) -> CGRect {
        CGRect(
            x: min(start.x, end.x), y: min(start.y, end.y),
            width: abs(end.x - start.x), height: abs(end.y - start.y)
        ).insetBy(dx: -width / 2, dy: -width / 2)
    }

    /// The flag glyph's painted bounds hung at `flag.origin`.
    private func flagInk(_ flag: EngravedFlag) -> CGRect {
        let metrics = PercussionGlyphMetrics.flag(
            duration: flag.duration, direction: flag.stemDirection, staffSpace: staffSpace
        )
        return metrics.paintedBounds.offsetBy(
            dx: flag.origin.x - metrics.attachmentOffset.x,
            dy: flag.origin.y - metrics.attachmentOffset.y
        )
    }

    /// The articulation glyph's painted bounds centered on its position.
    private func articulationInk(_ mark: EngravedArticulation) -> CGRect {
        PercussionGlyphMetrics.articulation(mark.kind, staffSpace: staffSpace)
            .paintedBounds.offsetBy(dx: mark.position.x, dy: mark.position.y)
    }

    /// The control cross mark's ink square centered on its position.
    private func controlInk(_ control: EngravedControl) -> CGRect {
        let extent = style.stopMarkSize + style.stopMarkStrokeWidth
        return CGRect(
            x: control.position.x - extent / 2, y: control.position.y - extent / 2,
            width: extent, height: extent
        )
    }

    /// The tuplet's bracket + label ink — the composer's painted-bounds rule.
    private func tupletInk(_ tuplet: EngravedTuplet) -> CGRect {
        var ink = tuplet.bracketPoints.isEmpty
            ? CGRect.null
            : tuplet.bracketPoints.dropFirst().reduce(
                CGRect(origin: tuplet.bracketPoints[0], size: .zero)
            ) { $0.union(CGRect(origin: $1, size: .zero)) }
        ink = ink.union(CGRect(
            x: tuplet.labelPosition.x - style.tupletLabelSize.width / 2,
            y: tuplet.labelPosition.y - style.tupletLabelSize.height / 2,
            width: style.tupletLabelSize.width,
            height: style.tupletLabelSize.height
        ))
        return ink.insetBy(dx: -style.tupletLineWidth / 2, dy: -style.tupletLineWidth / 2)
    }

    /// The bar's stroked ink — thin single bar, or the final double bar.
    private func barInk(
        _ bar: EngravedMeasureBar,
        rowsByIndex: [Int: EngravedRow],
        staffHeight: CGFloat
    ) -> CGRect {
        let centerY = rowsByIndex[bar.rowIndex]?.staffCenterY ?? 0
        if bar.isFinal {
            let width = style.doubleBarThinWidth + style.doubleBarSpacing + style.doubleBarThickWidth
            return CGRect(
                x: bar.x - width, y: centerY - staffHeight / 2,
                width: width, height: staffHeight
            )
        }
        return CGRect(
            x: bar.x - style.barLineWidth / 2, y: centerY - staffHeight / 2,
            width: style.barLineWidth, height: staffHeight
        )
    }
}
