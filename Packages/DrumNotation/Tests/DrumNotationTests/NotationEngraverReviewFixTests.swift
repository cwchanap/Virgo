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

    /// The beam's stroked ink — the composer's `lineBounds` formula. The
    /// centerline clearance assertions alone would miss that the painted
    /// edge reaches `thickness / 2` back toward the chord.
    private func beamInk(_ beam: EngravedBeam) -> CGRect {
        CGRect(
            x: min(beam.start.x, beam.end.x), y: min(beam.start.y, beam.end.y),
            width: abs(beam.end.x - beam.start.x), height: abs(beam.end.y - beam.start.y)
        ).insetBy(dx: -beam.thickness / 2, dy: -beam.thickness / 2)
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
        // finding's exact overlap; the chord term must bind instead. The
        // centerline must sit a half beam thickness beyond the minimum so
        // the STROKED ink edge — what actually paints — keeps the full
        // extension clear of the far chord member.
        let repBaseY = try anchor(engraved, noteID: 2).y - style.stemLength
        #expect(repBaseY > farHead.paintedBounds.minY - style.minimumStemExtensionPastChord)
        #expect(primary.start.y <= farHead.paintedBounds.minY
            - style.minimumStemExtensionPastChord - style.beamThickness / 2)
        #expect(beamInk(primary).maxY <= farHead.paintedBounds.minY
            - style.minimumStemExtensionPastChord)

        // The shared base is the most extreme of the default-length reach
        // and every participating member's far edge + extension +
        // half-thickness stroked offset.
        let repAnchors = [try anchor(engraved, noteID: 1), try anchor(engraved, noteID: 2)]
        let memberBounds = [try head(engraved, id: 1), try head(engraved, id: 2), farHead]
        let expected = (repAnchors.map { $0.y - style.stemLength }
            + memberBounds.map {
                $0.paintedBounds.minY - style.minimumStemExtensionPastChord
                    - style.beamThickness / 2
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
        #expect(primary.start.y >= farHead.paintedBounds.maxY
            + style.minimumStemExtensionPastChord + style.beamThickness / 2)
        #expect(beamInk(primary).minY >= farHead.paintedBounds.maxY
            + style.minimumStemExtensionPastChord)

        let repAnchors = [try anchor(engraved, noteID: 1), try anchor(engraved, noteID: 2)]
        let memberBounds = [try head(engraved, id: 1), try head(engraved, id: 2), farHead]
        let expected = (repAnchors.map { $0.y + style.stemLength }
            + memberBounds.map {
                $0.paintedBounds.maxY + style.minimumStemExtensionPastChord
                    + style.beamThickness / 2
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
                // Its 60-tick duration chains the next onset at tick 60.
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
                // Adjacent beamable onsets pull the mixed chord into a
                // primary run — the asserted beam must be the chord's own.
                Fixtures.makeNote(
                    id: 3, localTick: 60, staffStep: 3,
                    duration: .sixteenth, durationTicks: 120
                ),
                Fixtures.makeNote(
                    id: 4, localTick: 180, staffStep: 3,
                    duration: .sixteenth, durationTicks: 120
                ),
                // An isolated engravable sixteenth keeps flag coverage
                // non-vacuous: its canonical flag exists only because an
                // engravable representative governs its group.
                Fixtures.makeNote(
                    id: 5, localTick: 480, staffStep: 3,
                    duration: .sixteenth, durationTicks: 120
                )
            ],
            rests: [], controls: []
        )
        let engraved = try NotationEngraver.engrave(input, style: style)

        // Beams: the level-0 full beam of the chord's own primary run
        // retains BOTH chord member IDs — the suppressed sibling keeps
        // chord membership even though it owns no rhythm primitives.
        let primaryBeam = try #require(engraved.beams.first {
            $0.level == 0 && $0.kind == .full && $0.noteIDs.contains(1)
        })
        #expect(primaryBeam.noteIDs == [1, 2, 3, 4])

        // The chord's extra level hooks forward onto the next onset; the
        // hook's membership likewise carries the suppressed ID.
        #expect(engraved.beams.contains {
            $0.level == 2 && $0.kind == .forwardHook && $0.noteIDs == [1, 2]
        })

        // Stems: one stem serves the engravable member only — the
        // suppressed head keeps its ink but no rhythm primitives.
        let stem = try #require(engraved.stems.first { $0.noteIDs.contains(1) })
        #expect(stem.noteIDs == [1])
        #expect(engraved.stems.allSatisfy { !$0.noteIDs.contains(2) })

        // Flags: the only painted flag is the isolated engravable
        // sixteenth's canonical flag; the suppressed sibling can never
        // own flag ink.
        let flag = try #require(engraved.flags.first)
        #expect(engraved.flags.count == 1)
        #expect(flag.noteID == 5)
        #expect(flag.duration == .sixteenth)
        #expect(flag.origin.y == engraved.stems.first { $0.noteIDs == [5] }?.end.y)

        // Dots: the engravable member's dot paints; the suppressed
        // sibling's does not — even inside a shared beam.
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
